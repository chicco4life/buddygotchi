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
constexpr uint32_t kNoAppMs = 30000;       // PROTOCOL.md §3
constexpr uint32_t kRung2Ms = 45000;       // BEHAVIORS.md §3.2 (proposed)
constexpr uint32_t kRung3Ms = 120000;
constexpr uint32_t kTouchHoldMs = 600;     // UX.md §4
constexpr uint32_t kBubbleReadMs = 1200;   // the word stays up after the mumble

void copyStr(char* dst, size_t n, const char* src) { std::snprintf(dst, n, "%s", src ? src : ""); }

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b

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

const char* screenName(Screen s) {
  switch (s) {
    case Screen::kFace: return "face";
    case Screen::kNeedsYou: return "needs_you";
    case Screen::kThreads: return "threads";
    case Screen::kStats: return "stats";
    case Screen::kNoApp: return "no_app";
    case Screen::kPattern: return "pattern";
  }
  return "face";
}

Device::Device(Hal& hal, uint8_t* pixels, bool frozenClock) : hal_(hal), canvas_(pixels) {
  clock_.start(frozenClock, hal_.realMs());
  src_ = sourceAt(0);
}

// Forgets everything the Mac said and freezes the clock at 0, so a scenario
// starts from the same place on the board and in the simulator.
void Device::reset() {
  model_ = Model{};
  moment_ = Moment{};
  blend_ = render::Blend{};
  pattern_ = false;
  patternFill_ = -1;
  userScreen_ = Screen::kFace;
  injPress_ = injTouch_ = touchDown_ = false;
  boot_ = ButtonGesture{};
  last_ = LastInput{};
  clock_.freeze(0);
  rng_.seed(0);
  modelT_ = drawnT_ = 0;
  src_ = sourceAt(0);
  dirty_ = true;
}

bool Device::noApp(uint32_t t) const { return int32_t(t - model_.lastState) >= int32_t(kNoAppMs); }

int Device::rung(uint32_t t) const {
  if (!model_.attn) return 0;
  int32_t d = int32_t(t - model_.attnSince);
  return 1 + (d >= int32_t(kRung2Ms)) + (d >= int32_t(kRung3Ms));
}

Device::Source Device::sourceAt(uint32_t t) const {
  Source s;
  if (moment_.anim != render::Anim::kNone && int32_t(t - moment_.at) < int32_t(moment_.ms)) {
    s.anim = moment_.anim, s.size = moment_.size, s.at = moment_.at;
    return s;
  }
  if (noApp(t)) {
    s.look = render::Look::kNoApp;
  } else if (model_.attn) {
    s.look = render::Look::kNeedsYou, s.rung = rung(t);
  } else if (!std::strcmp(model_.base, "asleep")) {
    s.look = render::Look::kAsleep;
  } else if (!std::strcmp(model_.base, "working")) {
    s.look = render::Look::kWorking;
  }
  return s;
}

render::Pose Device::sourcePose(const Source& s, uint32_t t) const {
  if (s.anim != render::Anim::kNone) return render::animPose(s.anim, s.size, t - s.at);
  return render::lookPose(s.look, s.rung, model_.busy);
}

void Device::resync(uint32_t t) {
  if (moment_.anim != render::Anim::kNone && int32_t(t - moment_.at) >= int32_t(moment_.ms)) {
    // Ended: the blend starts from the moment's last pose, not from later.
    render::Pose last = blend_.apply(t, sourcePose(src_, t));
    moment_.anim = render::Anim::kNone;
    Source next = sourceAt(t);
    if (!(next == src_)) blend_.start(t, last), src_ = next;
    dirty_ = true;
  }
  Source next = sourceAt(t);
  if (!(next == src_)) {
    blend_.start(t, poseAt(t));
    src_ = next;
    dirty_ = true;
  }
  modelT_ = t;
}

void Device::advance(uint32_t t) {
  if (int32_t(t - modelT_) < 0) {  // the clock went back: no history to replay
    modelT_ = t;
    return;
  }
  for (;;) {
    bool found = false;
    uint32_t next = t;
    auto consider = [&](uint32_t c) {
      if (after(c, modelT_) && !after(c, t) && (!found || after(next, c))) next = c, found = true;
    };
    if (moment_.anim != render::Anim::kNone) consider(moment_.at + moment_.ms);
    consider(model_.lastState + kNoAppMs);
    if (model_.attn) consider(model_.attnSince + kRung2Ms), consider(model_.attnSince + kRung3Ms);
    if (!found) break;
    resync(next);
  }
  resync(t);
}

Screen Device::screenAt(uint32_t t) const {
  if (pattern_) return Screen::kPattern;
  if (noApp(t)) return Screen::kNoApp;
  if (userScreen_ != Screen::kFace) return userScreen_;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
}

render::Strip Device::strip(uint32_t t) const {
  render::Strip s;
  s.wait = model_.wait;
  s.busy = model_.busy;
  s.noApp = noApp(t);
  s.quiet = model_.quiet > 0;
  s.focus = model_.focus;
  return s;
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

void Device::handleLine(const char* line, size_t n, Link from) {
  JsonDocument doc;
  if (deserializeJson(doc, line, n) != DeserializationError::Ok) return;
  const char* t = doc["t"];
  if (!t) return;
  bool debug = std::strncmp(t, "dbg.", 4) == 0;
  if (debug && from != Link::kUsb) return;  // the debug channel is USB only
  if (!debug) link_ = from;
  uint32_t real = hal_.realMs();
  uint32_t at = now();
  advance(at);

  if (!std::strcmp(t, "state")) {
    Model& m = model_;
    if (doc["base"].is<const char*>()) copyStr(m.base, sizeof(m.base), doc["base"]);
    JsonObjectConst attn = doc["attn"];
    if (attn) {
      const char* agent = attn["agent"] | "";
      const char* project = attn["project"] | "";
      if (!m.attn || std::strncmp(m.agent, agent, sizeof(m.agent) - 1) ||
          std::strncmp(m.project, project, sizeof(m.project) - 1)) {
        m.attnSince = at;  // a new "needs you" restarts the ladder
      }
      m.attn = true;
      copyStr(m.agent, sizeof(m.agent), agent);
      copyStr(m.project, sizeof(m.project), project);
      m.more = attn["more"] | 0;
    } else {
      m.attn = false;
    }
    m.busy = doc["busy"] | 0;
    m.idle = doc["idle"] | 0;
    m.wait = doc["wait"] | 0;
    m.quiet = doc["quiet"] | 0;
    m.focus = doc["focus"] | false;
    copyStr(m.name, sizeof(m.name), doc["name"] | "");
    m.level = doc["level"] | 1;
    m.prog = doc["prog"] | 0;
    m.days = doc["days"] | 0;
    m.nThreads = 0;
    for (JsonArrayConst row : doc["threads"].as<JsonArrayConst>()) {
      if (m.nThreads >= 8) break;
      render::Thread& th = m.threads[m.nThreads++];
      copyStr(th.agent, sizeof(th.agent), row[0] | "");
      copyStr(th.project, sizeof(th.project), row[1] | "");
      const char* st = row[2] | "idle";
      th.status = !std::strcmp(st, "wait") ? 'w' : !std::strcmp(st, "work") ? 'b' : 'i';
    }
    m.lastState = at;
    pattern_ = false;
    dirty_ = true;
    resync(at);
  } else if (!std::strcmp(t, "moment")) {
    render::Anim anim = render::animFromName(doc["anim"]);
    if (anim != render::Anim::kNone) {
      Moment& mo = moment_;
      mo = Moment{};
      mo.anim = anim;
      mo.size = doc["size"] | 1;
      mo.at = at;
      mo.ms = render::animDuration(anim, mo.size);
      JsonObjectConst say = doc["say"];
      if (say) {
        int n = 0;
        bool inSyl = false;
        for (const char* p = say["syl"] | ""; *p; ++p) {
          bool sep = *p == ' ' || *p == '-';
          if (!sep && !inSyl) ++n;
          inSyl = !sep;
        }
        copyStr(mo.word, sizeof(mo.word), say["word"] | "");
        mo.say.syllables = n;
        mo.say.word = mo.word[0] ? mo.word : nullptr;
        mo.say.at = mo.word[0] ? (say["at"] | n) : -1;
        uint32_t spoken = uint32_t(n + (mo.word[0] ? 2 : 0)) * (say["ms"] | 120u) + kBubbleReadMs;
        if (spoken > mo.ms) mo.ms = spoken;
      }
      resync(at);
      dirty_ = true;
    }
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
    int fill = doc["fill"] | -1;
    patternFill_ = fill;
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
  } else if (!std::strcmp(t, "dbg.light")) {
    if (doc["bl"].is<int>()) {
      backlight_ = uint8_t(doc["bl"].as<int>());
      hal_.setBacklight(backlight_);
    }
    uint32_t rgb;
    if (parseHex(doc["led"], rgb)) {
      led_ = rgb;
      hal_.setLed(rgb);
    }
    reply(from, "{\"t\":\"dbg.light\"}", 17);
  }
}

void Device::tick() {
  uint32_t t = now();
  advance(t);

  // BOOT: the physical button or an injected press.
  if (injPress_ && int32_t(t - injPressUntil_) >= 0) injPress_ = false;
  switch (boot_.update(hal_.bootDown() || injPress_, t)) {
    case ButtonGesture::kTap:
      last_ = {"tap", t, -1, -1};
      emit("tap");
      break;
    case ButtonGesture::kHoldStart:
      last_ = {"talk_on", t, -1, -1};
      emit("talk_on");
      break;
    case ButtonGesture::kHoldEnd:
      last_ = {"talk_off", t, -1, -1};
      emit("talk_off");
      break;
    default:
      break;
  }

  // Touch: a short tap on the status strip cycles face → threads → stats.
  // F3 adds the other gestures.
  if (injTouch_ && int32_t(t - injTouchUntil_) >= 0) injTouch_ = false;
  int x = 0, y = 0;
  bool touching = injTouch_ ? (x = injX_, y = injY_, true) : hal_.touch(x, y);
  if (touching && !touchDown_) {
    last_ = {"touch", t, x, y};
    touchAt_ = t, touchX_ = x, touchY_ = y;
  }
  if (!touching && touchDown_ && t - touchAt_ < kTouchHoldMs && touchY_ >= render::kStripTop) {
    userScreen_ = userScreen_ == Screen::kFace ? Screen::kThreads
                  : userScreen_ == Screen::kThreads ? Screen::kStats : Screen::kFace;
    dirty_ = true;
  }
  touchDown_ = touching;

  Screen screen = screenAt(t);
  if (screen != screen_) screen_ = screen, dirty_ = true;
  bool faced = screen_ == Screen::kFace || screen_ == Screen::kNeedsYou || screen_ == Screen::kNoApp;
  bool moving = faced && (src_.anim != render::Anim::kNone || blend_.blending(t));
  if (dirty_ || ((moving || drawnMoving_) && t != drawnT_)) render(t);
}

void Device::render(uint32_t t) {
  render::Strip strip = this->strip(t);
  bool moving = false;
  switch (screen_) {
    case Screen::kPattern:
      if (patternFill_ >= 0) {
        canvas_.fill(uint8_t(patternFill_));
      } else {
        render::drawPattern(canvas_);
      }
      break;
    case Screen::kThreads: render::drawThreads(canvas_, model_.threads, model_.nThreads, strip); break;
    case Screen::kStats: {
      render::Stats st;
      st.name = model_.name, st.level = model_.level, st.prog = model_.prog, st.days = model_.days;
      render::drawStats(canvas_, st, strip);
      break;
    }
    case Screen::kNeedsYou: {
      render::Attention a;
      a.agent = model_.agent, a.project = model_.project, a.more = model_.more;
      render::drawNeedsYou(canvas_, poseAt(t), a, strip);
      moving = true;
      break;
    }
    default: {
      bool talking = src_.anim != render::Anim::kNone && moment_.say.syllables > 0;
      render::drawFaceScreen(canvas_, poseAt(t), talking ? &moment_.say : nullptr, strip);
      moving = true;
      break;
    }
  }
  drawnMoving_ = moving && (src_.anim != render::Anim::kNone || blend_.blending(t));
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
  char buf[256];
  size_t n = serializeJson(d, buf, sizeof(buf));
  reply(to, buf, n);
}

void Device::sendState(Link to) {
  JsonDocument d;
  d["t"] = "dbg.state";
  d["screen"] = screenName(screenAt(now()));
  uint32_t t = now();
  d["base"] = model_.base;
  if (model_.attn) {
    d["attn"]["agent"] = model_.agent;
    d["attn"]["project"] = model_.project;
    d["attn"]["more"] = model_.more;
  } else {
    d["attn"] = nullptr;
  }
  d["rung"] = rung(t);
  if (src_.anim != render::Anim::kNone) {
    d["moment"]["anim"] = render::animName(src_.anim);
    d["moment"]["left_ms"] = moment_.at + moment_.ms - t;
  } else {
    d["moment"] = nullptr;
  }
  d["quiet"] = model_.quiet;
  d["focus"] = model_.focus;
  char led[8];
  std::snprintf(led, sizeof(led), "#%06lX", (unsigned long)(led_ & 0xFFFFFF));
  d["led"] = led;
  d["audio"]["playing"] = false;
  d["audio"]["syllables"] = 0;
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
  d["bl"] = backlight_;
  char buf[768];
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
