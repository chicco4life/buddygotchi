#include "app/device.h"

#include <ArduinoJson.h>

#include <cstdio>
#include <cstring>

#include "app/codec.h"
#include "render/palette.h"
#include "render/pattern.h"
#include "render/raster.h"
#include "render/screens.h"

namespace app {

namespace {

constexpr uint32_t kDefaultPressMs = 100;
constexpr uint32_t kStatusMs = 60000;  // PROTOCOL.md §4
// Motion redraws at most this often, in real ms: about 60 fps. Parts of
// the face that cross block lines a few ms apart show together
// (DEVICE.md §6).
constexpr uint32_t kFrameMs = 16;
// A clock a tool froze runs again after this long, in real ms, with no
// dbg.* message, so a tool that dies mid-run can't leave the board
// stopped (VERIFICATION.md §3).
constexpr uint32_t kThawMs = 60000;

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
  toolFrozen_ = true;
  rng_.seed(0);
  b_.reset(0, rng_);
  hush();
  sfxSeen_ = b_.sfx(sfxSeenAt_);
  pattern_ = false;
  patternFill_ = -1;
  targetX_ = targetY_ = -1;
  injPress_ = injTouch_ = bootInjected_ = touchDown_ = touchInjected_ = false;
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

// On every live Mac link (PROTOCOL.md §4): Bluetooth while connected, and
// USB while the Mac has spoken there within kNoAppMs. A tool's `moment`
// over USB doesn't take the taps away from the app on Bluetooth. Input a
// tool injected goes back only over USB, where the tool is, so a test run
// never reaches the everyday app on Bluetooth.
void Device::emit(const char* k, bool injected) {
  char buf[48];
  int n = std::snprintf(buf, sizeof(buf), "{\"t\":\"input\",\"k\":\"%s\"}", k);
  if (injected) return reply(Link::kUsb, buf, size_t(n));
  if (bleUp_) reply(Link::kBle, buf, size_t(n));
  if (usbHeard_ && hal_.realMs() - usbHeardReal_ < Behaviour::kNoAppMs) reply(Link::kUsb, buf, size_t(n));
}

void Device::input(const char* k, uint32_t t, int x, int y) {
  last_ = {k, t, x, y};
  dirty_ = true;
}

bool Device::handleLine(const char* line, size_t n, Link from) {
  JsonDocument doc;
  if (deserializeJson(doc, line, n) != DeserializationError::Ok) return false;
  const char* t = doc["t"];
  if (!t) return false;
  bool debug = std::strncmp(t, "dbg.", 4) == 0;
  if (debug && from != Link::kUsb) return false;  // the debug channel is USB only
  uint32_t real = hal_.realMs();
  // USB's "connect": the Mac's first word, or its first after a silence.
  bool hello = !debug && from == Link::kUsb &&
               (link_ != Link::kUsb || real - heardReal_ >= Behaviour::kNoAppMs);
  if (!debug) link_ = from, heardReal_ = real;
  else dbgReal_ = real;
  if (!debug && from == Link::kUsb) usbHeard_ = true, usbHeardReal_ = real;
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
    m.vol = doc["vol"] | 6;
    b_.onState(m, at);
    if (m.attn || m.vol <= 0) hush();  // VOICE.md §9
    pattern_ = false;
    dirty_ = true;
  } else if (!std::strcmp(t, "moment")) {
    ++rxMoment_;
    MomentIn mo;
    mo.anim = render::animFromName(doc["anim"]);  // none, or unknown: only the mumble
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
    bool mumble = b_.onMoment(mo, at);  // copies the word
    const Model& m = b_.model();
    if (mumble && m.vol > 0) {
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
    targetX_ = target.size() == 2 ? render::clamp(target[0].as<int>(), 0, render::kWidth - 1) : -1;
    targetY_ = target.size() == 2 ? render::clamp(target[1].as<int>(), 0, render::kHeight - 1) : -1;
    pattern_ = true;
    dirty_ = true;
    reply(from, "{\"t\":\"dbg.pattern\"}", 19);
  } else if (!std::strcmp(t, "dbg.clock")) {
    if (doc["freeze"].is<uint32_t>()) {
      uint32_t to = doc["freeze"];
      clock_.freeze(to);
      rng_.seed(to);
      toolFrozen_ = true;
    } else if (doc["step"].is<uint32_t>()) {
      clock_.step(doc["step"].as<uint32_t>(), real);
      toolFrozen_ = true;
    } else if (doc["run"].as<bool>()) {
      clock_.run(real);
      toolFrozen_ = false;
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
  return debug;
}

void Device::connected(Link link) {
  link_ = link;
  heardReal_ = hal_.realMs();
  if (link == Link::kBle) bleUp_ = true;
  sendStatus(link);
}

void Device::disconnected(Link link) {
  if (link_ == link) link_ = Link::kNone;
  if (link == Link::kBle) bleUp_ = false;
}

// BOOT and touch, turned into gestures (UX.md §4). Every press and touch
// shows on screen at once, before the Mac hears about it.
void Device::readInputs(uint32_t t) {
  if (injPress_ && int32_t(t - injPressUntil_) >= 0) injPress_ = false;
  switch (boot_.update(hal_.bootDown() || injPress_, t)) {
    case ButtonGesture::kDown:
      bootInjected_ = !hal_.bootDown();
      b_.pressDown(t);
      dirty_ = true;
      break;
    case ButtonGesture::kTap:
      b_.pressUp(t);
      b_.tap(t);
      input("tap", t);
      emit("tap", bootInjected_);
      break;
    default:
      break;
  }

  // A touch anywhere is a tap, sent on release however long it was held.
  // The press shows at once. The panel misses readings under a light
  // press, so its touch ends only after kTouchReleaseMs without contact,
  // in real time so that it ends while a tool has the clock frozen; an
  // injected one ends when it says. The debug pattern ignores touches.
  if (injTouch_ && int32_t(t - injTouchUntil_) >= 0) injTouch_ = false;
  int x = 0, y = 0;
  bool contact = injTouch_ ? (x = injX_, y = injY_, true) : hal_.touch(x, y);
  uint32_t real = hal_.realMs();
  if (contact) touchSeenReal_ = real, touchInjected_ = injTouch_;
  bool touching = contact || (touchDown_ && !touchInjected_ && real - touchSeenReal_ < kTouchReleaseMs);
  bool faced = screenAt(t) != Screen::kPattern;
  if (touching && !touchDown_) {
    input("touch", t, x, y);
    if (faced) b_.pressDown(t);
  }
  if (!touching && touchDown_) {
    b_.pressUp(t);
    if (faced) {
      b_.tap(t);
      input("tap", t);
      emit("tap", touchInjected_);
    }
  }
  if (touching != touchDown_) dirty_ = true;
  touchDown_ = touching;
}

void Device::tick() {
  if (link_ != Link::kNone && hal_.realMs() - statusReal_ >= kStatusMs) sendStatus(link_);
  if (toolFrozen_ && hal_.realMs() - dbgReal_ >= kThawMs) clock_.run(hal_.realMs()), toolFrozen_ = false;
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
  if (debugLabel(t) != labelDrawn_) dirty_ = true;
  bool moving = movingAt(t);
  // A frozen clock looks on every step, so scenario frames stay exact,
  // and the press squish on every pass, so the cap doesn't delay a press.
  bool due = clock_.frozen() || b_.pressEasing(t) || hal_.realMs() - drawnReal_ >= kFrameMs;
  if (dirty_ || ((moving || drawnMoving_) && t != drawnT_ && due)) render(t, moving);
}

void Device::hush() {
  if (saying_) hal_.hush();
  saying_ = false;
}

// Stops a line whose mumble ended or was replaced (a tap's wiggle, say),
// and plays new sound cues (BEHAVIORS.md §4): the chirp, once when
// something starts needing you. Its `state` has already hushed any line.
void Device::followSound(uint32_t t) {
  if (saying_ && (b_.momentSeq() != sayMoment_ || !b_.mumble(t))) hush();
  uint32_t at;
  const char* k = b_.sfx(at);
  if (k == sfxSeen_ && at == sfxSeenAt_) return;
  sfxSeen_ = k, sfxSeenAt_ = at;
  const Model& m = b_.model();
  if (k && m.vol > 0) hal_.cue(voice::cueFromName(k), uint8_t(m.vol > 10 ? 10 : m.vol));
}

// Draws the frame for t, unless nothing on it can have changed since the
// last one (DEVICE.md §6): no message or input since (dirty_), the face
// laid out on the same blocks and the bubble still up or still down. The
// pixel face moves a block at a time, so most passes in motion find the
// picture unchanged.
void Device::render(uint32_t t, bool moving) {
  render::FaceLayout face = render::faceLayout(b_.pose(t));
  const render::Mumble* mumble = b_.mumble(t);
  bool same = !dirty_ && face == drawnFace_ && (mumble != nullptr) == drawnBubble_;
  drawnMoving_ = moving;
  drawnT_ = t;
  drawnReal_ = hal_.realMs();
  if (same) return;
  drawnFace_ = face;
  drawnBubble_ = mumble != nullptr;
  render::Strip strip = b_.strip(t);
  const Model& m = b_.model();
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
    case Screen::kNeedsYou: {
      render::Attention a;
      a.agent = m.agent, a.project = m.project, a.more = m.more;
      render::drawNeedsYou(canvas_, face, a, strip);
      break;
    }
    default:
      render::drawFaceScreen(canvas_, face, mumble, strip);
      break;
  }
  labelDrawn_ = debugLabel(t);
  if (labelDrawn_) canvas_.drawText(2, 2, labelDrawn_, render::inkAt(render::kInkDim, render::kLevels));
  dirty_ = false;
  frame_ = true;
}

// The face's state name, on the face screens, when BOOP_DEBUG_LABEL is on.
// Frozen-clock frames (the simulator and scenario runs) leave it out, so
// device screenshots still match the goldens pixel for pixel.
const char* Device::debugLabel(uint32_t t) const {
  if (!BOOP_DEBUG_LABEL || clock_.frozen()) return nullptr;
  if (screen_ == Screen::kPattern) return nullptr;
  return b_.faceName(t);
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
  d["w"] = render::kWidth;  // the screen as drawn, for boopctl calibrate
  d["h"] = render::kHeight;
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
  d["vol"] = m.vol;
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
  dirty_ = true;
  uint32_t t = now();
  render(t, movingAt(t));
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
