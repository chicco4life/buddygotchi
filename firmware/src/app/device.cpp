#include "app/device.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

#include "app/codec.h"
#include "render/palette.h"
#include "render/pattern.h"
#include "render/screens.h"

namespace app {

namespace {

constexpr uint32_t kDefaultPressMs = 100;
constexpr uint32_t kTouchHoldMs = 600;     // UX.md §4
constexpr uint32_t kStatusMs = 60000;      // PROTOCOL.md §4

void copyStr(char* dst, size_t n, const char* src) { std::snprintf(dst, n, "%s", src ? src : ""); }

const char* linkName(Link l) {
  switch (l) {
    case Link::kUsb: return "usb";
    case Link::kBle: return "ble";
    default: return "none";
  }
}

bool parseHex(const char* s, uint32_t& out) {
  if (!s || s[0] != '#' || std::strlen(s) != 7) return false;
  unsigned v = 0;
  if (std::sscanf(s + 1, "%6x", &v) != 1) return false;
  out = v;
  return true;
}

void sinkToOut(void* ctx, const char* text, size_t n) { static_cast<Out*>(ctx)->write(text, n); }

}  // namespace

Device::Device(Hal& hal, uint8_t* pixels, bool frozenClock) : hal_(hal), canvas_(pixels) {
  clock_.start(frozenClock, hal_.realMs());
  b_.reset(0, rng_);
}

// Forgets everything the Mac said and freezes the clock at 0, so a scenario
// starts from the same place on the board and in the simulator.
void Device::reset() {
  clock_.freeze(0);
  rng_.seed(0);
  b_.reset(0, rng_);
  hush();
  sfxSeen_ = b_.sfx(sfxSeenAt_);
  pattern_ = false;
  patternFill_ = -1;
  targetX_ = targetY_ = -1;
  injPress_ = injTouch_ = touchDown_ = touchHeld_ = false;
  boot_ = ButtonGesture{};
  last_ = LastInput{};
  drawnT_ = 0;
  dirty_ = true;
}

void Device::reply(Link link, const char* text, size_t n) {
  Out* out = outs_[int(link)];
  if (!out) return;
  out->write(text, n);
  out->write("\n", 1);
}

void Device::emit(const char* k) {
  char buf[48];
  int n = std::snprintf(buf, sizeof(buf), "{\"t\":\"input\",\"k\":\"%s\"}", k);
  reply(link_, buf, size_t(n));
}

void Device::input(const char* k, uint32_t t, int x, int y) {
  last_ = {k, t, x, y};
  dirty_ = true;
}

void Device::handleLine(const char* line, size_t n, Link from) {
  JsonDocument doc;
  if (deserializeJson(doc, line, n) != DeserializationError::Ok) return;
  const char* t = doc["t"];
  if (!t) return;
  bool debug = std::strncmp(t, "dbg.", 4) == 0;
  if (debug && from != Link::kUsb) return;  // the debug channel is USB only
  uint32_t real = hal_.realMs();
  // USB's "connect": the Mac's first word, or its first after a silence.
  bool hello = !debug && from == Link::kUsb &&
               (link_ != Link::kUsb || real - heardReal_ >= Behaviour::kNoAppMs);
  if (!debug) link_ = from, heardReal_ = real;
  uint32_t at = now();
  b_.advance(at, rng_);

  if (!std::strcmp(t, "state")) {
    ++rxState_;
    Model m;
    if (doc["base"].is<const char*>()) copyStr(m.base, sizeof(m.base), doc["base"]);
    JsonObjectConst attn = doc["attn"];
    if (attn) {
      m.attn = true;
      copyStr(m.agent, sizeof(m.agent), attn["agent"] | "");
      copyStr(m.project, sizeof(m.project), attn["project"] | "");
      m.more = attn["more"] | 0;
    }
    m.busy = doc["busy"] | 0;
    m.idle = doc["idle"] | 0;
    m.wait = doc["wait"] | 0;
    JsonObjectConst mood = doc["mood"];
    m.energy = mood["energy"] | 100;
    m.pace = mood["pace"] | 100;
    m.pitch = mood["pitch"] | 100;
    m.quiet = doc["quiet"] | 0;
    m.focus = doc["focus"] | false;
    m.vol = doc["vol"] | 6;
    m.night = doc["night"] | false;
    copyStr(m.name, sizeof(m.name), doc["name"] | "");
    m.level = doc["level"] | 1;
    m.prog = doc["prog"] | 0;
    m.days = doc["days"] | 0;
    m.hungry = doc["hungry"] | 0;
    for (JsonArrayConst row : doc["threads"].as<JsonArrayConst>()) {
      if (m.nThreads >= 8) break;
      render::Thread& th = m.threads[m.nThreads++];
      copyStr(th.agent, sizeof(th.agent), row[0] | "");
      copyStr(th.project, sizeof(th.project), row[1] | "");
      const char* st = row[2] | "idle";
      th.status = !std::strcmp(st, "wait") ? 'w' : !std::strcmp(st, "work") ? 'b' : 'i';
    }
    b_.onState(m, at, rng_);
    if (m.attn || m.quiet > 0 || m.focus || m.vol <= 0) hush();  // VOICE.md §9
    pattern_ = false;
    dirty_ = true;
  } else if (!std::strcmp(t, "moment")) {
    ++rxMoment_;
    MomentIn mo;
    mo.anim = render::animFromName(doc["anim"]);
    mo.size = doc["size"] | 1;
    voice::Line line;
    JsonObjectConst say = doc["say"];
    if (say) {
      // Syllables are separated by spaces (words) and hyphens.
      int syl = 0;
      const char* p = say["syl"] | "";
      while (*p) {
        while (*p == ' ' || *p == '-') ++p;
        const char* s = p;
        while (*p && *p != ' ' && *p != '-') ++p;
        if (p == s) break;
        if (line.n < voice::kMaxSyllables) {
          int i = voice::syllableIndex(s, size_t(p - s));
          line.syl[line.n++] = i < 0 ? voice::kSilent : uint8_t(i);
        }
        ++syl;
      }
      mo.syllables = syl;
      const char* word = say["word"] | "";
      mo.word = word[0] ? word : nullptr;
      mo.at = say["at"] | syl;
      mo.ms = say["ms"] | 120u;
      line.word = voice::wordIndex(mo.word);
      line.at = mo.at;
      line.tune = voice::tuneFromName(say["tune"]);
      line.ms = uint16_t(mo.ms < 60 ? 60 : mo.ms > 400 ? 400 : mo.ms);  // as the mouth
    }
    uint32_t seq = b_.momentSeq();
    bool mumble = b_.onMoment(mo, at, rng_);  // copies the word
    const Model& m = b_.model();
    if (mumble && m.vol > 0) {
      line.pitch = uint16_t(m.pitch);
      line.vol = uint8_t(m.vol > 10 ? 10 : m.vol);
      line.seed = at * 2654435761u + rxMoment_;  // not from rng_, which the frames depend on
      hal_.say(line);
      saying_ = true;
      sayMoment_ = b_.momentSeq();
    } else if (b_.momentSeq() != seq) {
      hush();  // a new moment replaces the line
    }
    dirty_ = true;
  } else if (!std::strcmp(t, "dbg.reset")) {
    reset();
    reply(from, "{\"t\":\"dbg.reset\"}", 17);
  } else if (!std::strcmp(t, "dbg.ping")) {
    sendPing(from);
  } else if (!std::strcmp(t, "dbg.state")) {
    sendState(from);
  } else if (!std::strcmp(t, "dbg.shot")) {
    sendShot(from);
  } else if (!std::strcmp(t, "dbg.pattern")) {
    // With "fill", a solid screen of that palette index (webcam framing).
    // With "target": [x, y], a cross to tap on black (boopctl calibrate).
    int fill = doc["fill"] | -1;
    patternFill_ = fill;
    JsonArrayConst target = doc["target"];
    targetX_ = target.size() == 2 ? target[0].as<int>() : -1;
    targetY_ = target.size() == 2 ? target[1].as<int>() : -1;
    pattern_ = true;
    dirty_ = true;
    reply(from, "{\"t\":\"dbg.pattern\"}", 19);
  } else if (!std::strcmp(t, "dbg.clock")) {
    if (doc["freeze"].is<uint32_t>()) {
      uint32_t to = doc["freeze"];
      clock_.freeze(to);
      rng_.seed(to);
    } else if (doc["step"].is<uint32_t>()) {
      clock_.step(doc["step"].as<uint32_t>(), real);
    } else if (doc["run"].as<bool>()) {
      clock_.run(real);
    }
    char buf[64];
    int len = std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.clock\",\"now\":%lu,\"frozen\":%s}",
                            (unsigned long)now(), clock_.frozen() ? "true" : "false");
    reply(from, buf, size_t(len));
  } else if (!std::strcmp(t, "dbg.press")) {
    injPress_ = true;
    injPressUntil_ = now() + (doc["ms"] | kDefaultPressMs);
    reply(from, "{\"t\":\"dbg.press\"}", 17);
  } else if (!std::strcmp(t, "dbg.touch")) {
    injTouch_ = true;
    injX_ = doc["x"] | 0;
    injY_ = doc["y"] | 0;
    injTouchUntil_ = now() + (doc["ms"] | kDefaultPressMs);
    reply(from, "{\"t\":\"dbg.touch\"}", 17);
  } else if (!std::strcmp(t, "dbg.touchcal")) {
    // "set": [ax, bx, cx, ay, by, cy] in 1/65536 (TouchCal), or "clear".
    JsonArrayConst set = doc["set"];
    if (set.size() == 6) {
      TouchCal c;
      c.ax = set[0].as<int32_t>(), c.bx = set[1].as<int32_t>(), c.cx = set[2].as<int32_t>();
      c.ay = set[3].as<int32_t>(), c.by = set[4].as<int32_t>(), c.cy = set[5].as<int32_t>();
      c.valid = true;
      hal_.setTouchCal(c);
    } else if (doc["clear"] | false) {
      hal_.setTouchCal(TouchCal{});
    }
    TouchCal c = hal_.touchCal();
    char buf[160];
    int len = c.valid ? std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.touchcal\",\"cal\":[%ld,%ld,%ld,%ld,%ld,%ld]}",
                                      long(c.ax), long(c.bx), long(c.cx), long(c.ay), long(c.by), long(c.cy))
                      : std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.touchcal\",\"cal\":null}");
    reply(from, buf, size_t(len));
  } else if (!std::strcmp(t, "dbg.light")) {
    if (doc["bl"].is<int>()) b_.overrideBacklight(uint8_t(doc["bl"].as<int>()));
    uint32_t rgb;
    if (parseHex(doc["led"], rgb)) b_.overrideLed(rgb);
    reply(from, "{\"t\":\"dbg.light\"}", 17);
  }
  if (hello) sendStatus(from);
}

void Device::connected(Link link) {
  link_ = link;
  heardReal_ = hal_.realMs();
  sendStatus(link);
}

void Device::disconnected(Link link) {
  if (link_ == link) link_ = Link::kNone;
}

// BOOT and touch, turned into gestures (UX.md §4). Every press and touch
// shows on screen at once, before the Mac hears about it.
void Device::readInputs(uint32_t t) {
  if (injPress_ && int32_t(t - injPressUntil_) >= 0) injPress_ = false;
  switch (boot_.update(hal_.bootDown() || injPress_, t)) {
    case ButtonGesture::kDown:
      b_.pressDown(t);
      dirty_ = true;
      break;
    case ButtonGesture::kTap:
      b_.pressUp(t);
      b_.tap(t, rng_);
      input("tap", t);
      emit("tap");
      break;
    case ButtonGesture::kHoldStart:
      b_.pressUp(t);
      b_.talkOn(t, rng_);
      input("talk_on", t);
      emit("talk_on");
      break;
    case ButtonGesture::kHoldEnd:
      b_.talkOff(t, rng_);
      input("talk_off", t);
      emit("talk_off");
      break;
    default:
      break;
  }

  if (injTouch_ && int32_t(t - injTouchUntil_) >= 0) injTouch_ = false;
  int x = 0, y = 0;
  bool touching = injTouch_ ? (x = injX_, y = injY_, true) : hal_.touch(x, y);
  Screen s = screenAt(t);
  bool faced = s == Screen::kFace || s == Screen::kNeedsYou || s == Screen::kNoApp;
  if (touching && !touchDown_) {
    input("touch", t, x, y);
    touchAt_ = t;
    touchHeld_ = false;
    touchStrip_ = y >= render::kStripTop;
    if (!touchStrip_ && faced) b_.pressDown(t);
  }
  if (touching && !touchHeld_ && t - touchAt_ >= kTouchHoldMs) {  // touch and hold
    touchHeld_ = true;
    b_.pressUp(t);
    if (touchStrip_) {
      b_.toggleFocus(t);
      input("focus", t);
      emit("focus");
    } else if (faced) {
      b_.feel(t, rng_);
      input("feel", t);
      emit("feel");
    }
  }
  if (!touching && touchDown_) {
    b_.pressUp(t);
    if (!touchHeld_) {
      if (touchStrip_) {
        b_.stripTap(t);
      } else if (faced) {
        b_.tap(t, rng_);
        input("tap", t);
        emit("tap");
      } else {
        b_.contentTap(t);
      }
    }
    dirty_ = true;
  }
  if (touching != touchDown_) dirty_ = true;
  touchDown_ = touching;
}

void Device::tick() {
  if (link_ != Link::kNone && hal_.realMs() - statusReal_ >= kStatusMs) sendStatus(link_);
  uint32_t t = now();
  b_.advance(t, rng_);
  readInputs(t);
  followSound(t);

  uint32_t led = b_.led(t);
  if (led != led_) led_ = led, hal_.setLed(led);
  uint8_t bl = b_.backlight(t);
  if (bl != backlight_) backlight_ = bl, hal_.setBacklight(bl);

  Screen screen = screenAt(t);
  if (screen != screen_) screen_ = screen, dirty_ = true;
  bool faced = screen_ == Screen::kFace || screen_ == Screen::kNeedsYou || screen_ == Screen::kNoApp;
  bool moving = faced && b_.moving(t);
  if (dirty_ || ((moving || drawnMoving_) && t != drawnT_)) render(t);
}

void Device::hush() {
  if (saying_) hal_.hush();
  saying_ = false;
}

// Stops a line whose moment ended or was replaced (a tap's wiggle, say),
// and plays new sound cues (BEHAVIORS.md). A cue waits out a line: the
// jingle arrives with the cheer that carries the line.
void Device::followSound(uint32_t t) {
  if (saying_ && (b_.momentSeq() != sayMoment_ || !b_.mumble(t))) hush();
  uint32_t at;
  const char* k = b_.sfx(at);
  if (k == sfxSeen_ && at == sfxSeenAt_) return;
  sfxSeen_ = k, sfxSeenAt_ = at;
  const Model& m = b_.model();
  if (k && !saying_ && !m.focus && m.vol > 0) hal_.cue(voice::cueFromName(k), uint8_t(m.vol > 10 ? 10 : m.vol));
}

void Device::render(uint32_t t) {
  render::Strip strip = b_.strip(t);
  strip.pressed = touchDown_ && touchStrip_;
  const Model& m = b_.model();
  bool faced = false;
  switch (screen_) {
    case Screen::kPattern:
      if (targetX_ >= 0) {
        canvas_.fill(render::kBlack);
        canvas_.fillRect(targetX_ - 10, targetY_ - 1, 21, 3, render::kAmber);
        canvas_.fillRect(targetX_ - 1, targetY_ - 10, 3, 21, render::kAmber);
      } else if (patternFill_ >= 0) {
        canvas_.fill(uint8_t(patternFill_));
      } else {
        render::drawPattern(canvas_);
      }
      break;
    case Screen::kThreads: render::drawThreads(canvas_, m.threads, m.nThreads, strip); break;
    case Screen::kStats: {
      render::Stats st;
      st.name = m.name, st.level = m.level, st.prog = m.prog, st.days = m.days;
      render::drawStats(canvas_, st, strip);
      break;
    }
    case Screen::kNeedsYou: {
      render::Attention a;
      a.agent = m.agent, a.project = m.project, a.more = m.more;
      render::drawNeedsYou(canvas_, b_.pose(t), a, strip);
      faced = true;
      break;
    }
    default:
      render::drawFaceScreen(canvas_, b_.pose(t), b_.mumble(t), strip, screen_ == Screen::kFace && m.hungry >= 2);
      faced = true;
      break;
  }
  drawnMoving_ = faced && b_.moving(t);
  drawnT_ = t;
  dirty_ = false;
  frame_ = true;
}

void Device::sendPing(Link to) {
  JsonDocument d;
  d["t"] = "dbg.ping";
  d["fw"] = hal_.fwVersion();
  d["sha"] = hal_.gitSha();
  d["up"] = hal_.realMs();
  d["heap"] = hal_.heapFree();
  d["heap_min"] = hal_.heapMin();
  d["fps"] = hal_.fps();
  uint32_t drawUs, pushUs;
  hal_.frameUs(drawUs, pushUs);
  d["draw_us"] = drawUs;
  d["push_us"] = pushUs;
  d["link"] = linkName(link_);
  d["ble"] = hal_.bleState();
  if (hal_.bleName()[0]) d["name"] = hal_.bleName();
  d["voice"] = voice::assetsVersion();
  char buf[320];
  size_t n = serializeJson(d, buf, sizeof(buf));
  reply(to, buf, n);
}

void Device::sendStatus(Link to) {
  statusReal_ = hal_.realMs();
  char buf[160];
  int n = std::snprintf(buf, sizeof(buf), "{\"t\":\"status\",\"v\":1,\"id\":\"%s\",\"fw\":\"%s\",\"bat\":%lu,\"usb\":%d}",
                        hal_.deviceId(), hal_.fwVersion(), (unsigned long)hal_.batteryMv(), hal_.usbPowered() ? 1 : 0);
  reply(to, buf, size_t(n));
}

void Device::sendState(Link to) {
  JsonDocument d;
  d["t"] = "dbg.state";
  uint32_t t = now();
  const Model& m = b_.model();
  d["screen"] = screenName(screenAt(t));
  d["base"] = m.base;
  if (m.attn) {
    d["attn"]["agent"] = m.agent;
    d["attn"]["project"] = m.project;
    d["attn"]["more"] = m.more;
  } else {
    d["attn"] = nullptr;
  }
  d["rung"] = b_.rung(t);
  d["hushed"] = b_.hushed();
  uint32_t left;
  render::Anim anim = b_.moment(t, left);
  if (anim != render::Anim::kNone) {
    d["moment"]["anim"] = render::animName(anim);
    d["moment"]["left_ms"] = left;
  } else {
    d["moment"] = nullptr;
  }
  const char* life = lifeName(b_.life(t));
  if (life) d["life"] = life;
  else d["life"] = nullptr;
  d["quiet"] = m.quiet;
  d["focus"] = m.focus;
  d["night"] = m.night;
  d["hungry"] = m.hungry;
  char led[8];
  std::snprintf(led, sizeof(led), "#%06lX", (unsigned long)(b_.led(t) & 0xFFFFFF));
  d["led"] = led;
  d["audio"]["playing"] = b_.speaking(t);
  d["audio"]["syllables"] = b_.mumble(t) ? b_.syllables() : 0;
  AudioOut ao = hal_.audioOut();
  JsonObject out = d["audio"]["out"].to<JsonObject>();
  out["ready"] = ao.ready;
  out["playing"] = ao.playing;
  out["lines"] = ao.lines;
  out["syl"] = ao.syl;
  out["word"] = ao.word;
  out["plan_ms"] = ao.planMs;
  out["out_ms"] = ao.outMs;
  out["wall_ms"] = ao.wallMs;
  out["cut"] = ao.cut;
  out["errors"] = ao.errors;
  uint32_t sfxAt;
  if (const char* sfx = b_.sfx(sfxAt)) {
    d["sfx"]["k"] = sfx;
    d["sfx"]["at"] = sfxAt;
  } else {
    d["sfx"] = nullptr;
  }
  if (last_.k) {
    JsonObject li = d["last_input"].to<JsonObject>();
    li["k"] = last_.k;
    li["at"] = last_.at;
    if (last_.x >= 0) {
      li["x"] = last_.x;
      li["y"] = last_.y;
    }
  } else {
    d["last_input"] = nullptr;
  }
  // Bring-up extras (F1): the clock and raw hardware readings.
  d["clock"]["now"] = now();
  d["clock"]["frozen"] = clock_.frozen();
  d["boot"] = boot_.down();
  int rx, ry, rz;
  bool irq;
  hal_.touchRaw(rx, ry, rz, irq);
  JsonObject touch = d["touch"].to<JsonObject>();
  touch["down"] = touchDown_;
  touch["irq"] = irq;
  JsonArray raw = touch["raw"].to<JsonArray>();
  raw.add(rx), raw.add(ry), raw.add(rz);
  d["bat"] = hal_.batteryMv();
  d["amp"] = hal_.ampOn();
  d["bl"] = b_.backlight(t);
  d["rx"]["state"] = rxState_;
  d["rx"]["moment"] = rxMoment_;
  char buf[1536];
  size_t n = serializeJson(d, buf, sizeof(buf));
  reply(to, buf, n);
}

// Header line, then one base64 line: 256 little-endian RGB565 palette
// entries followed by one palette index per pixel, row by row.
void Device::sendShot(Link to) {
  Out* out = outs_[int(to)];
  if (!out) return;
  screen_ = screenAt(now());
  render(now());
  uint8_t pal[512];
  for (int i = 0; i < 256; ++i) {
    uint16_t c = render::paletteAt(i);
    pal[2 * i] = uint8_t(c & 0xFF);
    pal[2 * i + 1] = uint8_t(c >> 8);
  }
  const size_t npx = size_t(render::kWidth) * render::kHeight;
  uint32_t crc = crc32(canvas_.pixels(), npx, crc32(pal, sizeof(pal)));
  char head[128];
  int n = std::snprintf(head, sizeof(head), "{\"t\":\"dbg.shot\",\"w\":%d,\"h\":%d,\"bytes\":%u,\"crc\":%lu}",
                        render::kWidth, render::kHeight, unsigned(sizeof(pal) + npx), (unsigned long)crc);
  reply(to, head, size_t(n));
  Base64Writer b64(sinkToOut, out);
  b64.write(pal, sizeof(pal));
  b64.write(canvas_.pixels(), npx);
  b64.finish();
  out->write("\n", 1);
}

}  // namespace app
