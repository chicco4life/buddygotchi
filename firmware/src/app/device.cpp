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
// stopped (PROTOCOL.md §5).
constexpr uint32_t kThawMs = 60000;
// BOOT's cap on talking is where listening stops listening (DEVICE.md §4).
static_assert(ButtonGesture::kTalkCapMs == Behaviour::kListenMs, "the talk cap is listening's");

const char* linkName(Link l) {
  switch (l) {
    case Link::kUsb: return "usb";
    case Link::kBle: return "ble";
    default: return "none";
  }
}

void sinkToOut(void* ctx, const char* text, size_t n) { static_cast<Out*>(ctx)->write(text, n); }

// A number the device holds to lo–hi (PROTOCOL.md §3): any JSON number,
// one past either end (even too big for an int) as that end, and a
// fraction as its whole part. Missing or not a number reads as `missing`.
int heldTo(JsonVariantConst v, int lo, int hi, int missing) {
  if (!v.is<double>() || v.is<bool>()) return missing;
  double n = v.as<double>();
  return n >= hi ? hi : n > lo ? int(n) : lo;
}

}  // namespace

Device::Device(Hal& hal, uint8_t* pixels, bool frozenClock) : hal_(hal), canvas_(pixels) {
  clock_.start(frozenClock, hal_.realMs());
  b_.reset(0, rng_);
  fpsSinceReal_ = hal_.realMs();
}

// Forgets everything the Mac said and freezes the clock at 0, so a scenario
// starts from the same place on the board and in the simulator.
void Device::reset() {
  clock_.freeze(0);
  toolFrozen_ = true;
  rng_.seed(0);
  b_.reset(0, rng_);
  hush();
  linePending_ = false;
  fx_.reset();
  hal_.stopEffects();
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
  if (heard_[int(Link::kUsb)] && hal_.realMs() - heardReal_[int(Link::kUsb)] < Behaviour::kNoAppMs) {
    reply(Link::kUsb, buf, size_t(n));
  }
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
               (link_ != Link::kUsb || real - heardReal_[int(Link::kUsb)] >= Behaviour::kNoAppMs);
  if (!debug) link_ = from, heard_[int(from)] = true, heardReal_[int(from)] = real;
  else dbgReal_ = real;
  uint32_t at = now();
  b_.advance(at, rng_);

  if (!std::strcmp(t, "state")) {
    ++rxState_;
    Model m;
    m.base = baseFromName(doc["base"]);          // idle if missing or unknown
    m.act = actFromName(doc["act"]);             // working's design if missing or unknown
    m.mood = render::moodFromName(doc["mood"]);  // happy if missing or unknown
    JsonObjectConst attn = doc["attn"];
    if (attn) {
      m.attn = true;
      copyStr(m.agent, sizeof(m.agent), attn["agent"] | "");
      copyStr(m.project, sizeof(m.project), attn["project"] | "");
      copyStr(m.name, sizeof(m.name), attn["name"] | "");
      m.more = attn["more"] | 0;
      m.attnId = attn["id"] | 0u;
    }
    m.busy = doc["busy"] | 0;
    m.vol = heldTo(doc["vol"], 0, 10, 6);
    // The visual's variation, from 1: missing reads as 1, and one out of range is held to it.
    m.variant = uint8_t(
        heldTo(doc["variant"], 1, render::variants(m.mood, m.attn ? render::SceneState::kNeedsYou : m.look()), 1) - 1);
    b_.onState(m, at);
    if (m.attn || m.vol == 0) hush();  // VOICE.md §9
    if (m.vol == 0) hal_.stopEffects();
    pattern_ = false;
    dirty_ = true;
  } else if (!std::strcmp(t, "moment")) {
    ++rxMoment_;
    MomentIn mo;
    const char* anim = doc["anim"];
    mo.anim = render::animFromName(anim);  // none, or unknown: only the line or the face
    mo.expr = render::parseMood(doc["mood"], mo.mood);  // unknown or missing: the state's mood
    mo.loops = heldTo(doc["loops"], 1, Behaviour::kMaxLoops, 1);
    // The animation's variation: the Mac's (from 1) when it's one of its
    // design's, in the mood it's drawn in, for the finish's outcome or the
    // start's context ("cheer" is a success); else the device picks one of
    // those, never the one it showed last.
    if (mo.anim != render::Anim::kNone) {
      render::Outcome outcome = render::Outcome::kNone;
      render::StartCtx ctx = render::StartCtx::kNone;
      if (mo.anim == render::Anim::kTaskComplete) {
        outcome = !std::strcmp(anim, "cheer") ? render::Outcome::kSuccess : render::outcomeFromName(doc["outcome"]);
      }
      if (mo.anim == render::Anim::kStarting) ctx = render::ctxFromName(doc["ctx"]);
      mo.variant = b_.pick(mo.anim, mo.expr ? mo.mood : b_.model().mood, heldTo(doc["variant"], 0, 255, 0), outcome,
                           ctx, rng_);
    }
    mo.said = !doc["say"].isNull();
    // Nothing to play or show: the empty moment, which ends listening.
    mo.empty = doc["anim"].isNull() && !mo.said && doc["mood"].isNull();
    JsonObjectConst who = doc["who"];  // copied by onMoment, while doc lives
    if (who) mo.whoAgent = who["agent"] | "", mo.whoThread = who["thread"] | "";
    // The line: a take by its id, and maybe a second, `then`, from the
    // card's voice pack. `{}`, or an id the pack doesn't have (or no card),
    // is still a `say` (the reply listening waits for) but plays nothing.
    mo.take = voice::takeIndex(doc["say"]["take"].as<const char*>());
    mo.then = mo.take >= 0 ? voice::takeIndex(doc["say"]["then"].as<const char*>()) : -1;
    voice::Line line = voice::makeLine(mo.take, mo.then);
    mo.id = doc["id"] | 0u;  // the Mac waits on it: `ended` goes back where it came from
    mo.from = uint8_t(from);
    uint32_t seq = b_.momentSeq();
    bool speaks = b_.onMoment(mo, at);
    linePending_ = false;
    if (speaks) {
      // Its sound goes with its bubble: now, or at its animation's voice
      // window (VOICE.md §10).
      line_ = line;
      linePending_ = true;
      lineMoment_ = b_.momentSeq();
    }
    if (!startLine(at) && b_.momentSeq() != seq) hush();  // a new moment replaces the line
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
  } else if (!std::strcmp(t, "dbg.card")) {
    CardOp o;
    o.op = doc["op"] | "";
    o.keep = doc["keep"] | false;
    o.at = doc["at"] | 0u, o.c = doc["c"] | 0u, o.size = doc["size"] | 0u, o.crc = doc["crc"] | 0u;
    o.d = doc["d"] | "";
    cardCopy(o, from);
  } else if (!std::strcmp(t, "dbg.light")) {
    if (doc["bl"].is<int>()) b_.overrideBacklight(uint8_t(doc["bl"].as<int>()));
    reply(from, "{\"t\":\"dbg.light\"}", 17);
  }
  if (hello) sendStatus(from);
  sendEnded();
  return debug;
}

// Copying a voice pack onto the card over USB (PROTOCOL.md §5, VOICE.md §8):
// `begin` (afresh, or `keep` to go on), then `put`s of base64 chunks at
// the end of what the card holds, each with its CRC-32, then `end` with the
// whole file's size and CRC-32. Every reply says what the card holds, so
// a chunk lost on the way is simply sent again.
void Device::cardCopy(const CardOp& o, Link from) {
  char buf[160];
  int n = 0;
  uint32_t have = 0;
  const char* why = "";
  bool ok = false;
  if (!std::strcmp(o.op, "begin")) {
    ok = hal_.packBegin(o.keep, have, why);
  } else if (!std::strcmp(o.op, "put")) {
    static uint8_t chunk[kCardChunk];
    long got = app::base64Decode(o.d, std::strlen(o.d), chunk, sizeof(chunk));
    hal_.packAppend(chunk, 0, have);  // how much the card holds
    if (got < 0) why = "not base64";
    else if (app::crc32(chunk, size_t(got)) != o.c) why = "wrong crc";
    else if (o.at != have) why = "not where the card is";
    else if (!(ok = hal_.packAppend(chunk, size_t(got), have))) why = "can't write";
  } else if (!std::strcmp(o.op, "end")) {
    hush();  // nothing reads the old pack while it's swapped
    linePending_ = false;
    ok = hal_.packEnd(o.size, o.crc, why);
    n = std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.card\",\"op\":\"end\",\"ok\":%s,\"voice\":\"%s\",\"why\":\"%s\"}",
                      ok ? "true" : "false", voice::assetsVersion(), ok ? "" : why);
    reply(from, buf, size_t(n));
    return;
  } else {
    why = "op is begin, put or end";
  }
  const char* name = ok || std::strcmp(why, "op is begin, put or end") ? o.op : "?";  // never echo junk
  n = std::snprintf(buf, sizeof(buf), "{\"t\":\"dbg.card\",\"op\":\"%s\",\"ok\":%s,\"have\":%lu,\"why\":\"%s\"}", name,
                    ok ? "true" : "false", (unsigned long)have, ok ? "" : why);
  reply(from, buf, size_t(n));
}

void Device::connected() {
  link_ = Link::kBle;
  bleUp_ = true;
  heard_[int(Link::kBle)] = true, heardReal_[int(Link::kBle)] = hal_.realMs();
  sendStatus(Link::kBle);
}

void Device::disconnected() {
  if (link_ == Link::kBle) link_ = Link::kNone;
  bleUp_ = false;
  heard_[int(Link::kBle)] = false;
}

bool Device::shouldDrop(Link link) {
  if (link != Link::kBle || !bleUp_) return false;  // USB has no connection to let go
  uint32_t real = hal_.realMs();
  uint32_t& heard = heardReal_[int(link)];
  if (real - heard < Behaviour::kNoAppMs) return false;
  heard = real;
  return true;
}

void Device::tapped(uint32_t t, bool injected) {
  b_.tap(t, rng_);
  input("tap", t);
  emit("tap", injected);
}

// BOOT and touch, turned into gestures (DEVICE.md §4). Every press and
// touch shows on screen at once, before the Mac hears about it.
void Device::readInputs(uint32_t t) {
  if (injPress_ && int32_t(t - injPressUntil_) >= 0) injPress_ = false;
  switch (boot_.update(hal_.bootDown() || injPress_, t)) {
    case ButtonGesture::kDown:
      bootInjected_ = !hal_.bootDown();
      b_.pressDown(t);
      dirty_ = true;
      break;
    case ButtonGesture::kTap:
      b_.pressUp();
      tapped(t, bootInjected_);
      break;
    case ButtonGesture::kHoldStart:  // push-to-talk: listening at once, before the Mac hears
      b_.pressUp();
      b_.talkOn(t, rng_);
      input("talk_on", t);
      emit("talk_on", bootInjected_);
      break;
    case ButtonGesture::kHoldEnd:  // let go, or the 30 s cap
      b_.talkOff(t);
      input("talk_off", t);
      emit("talk_off", bootInjected_);
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
    b_.pressUp();
    if (faced) tapped(t, touchInjected_);
  }
  if (touching != touchDown_) dirty_ = true;
  touchDown_ = touching;
}

void Device::tick() {
  uint32_t real = hal_.realMs();
  if (real - fpsSinceReal_ >= 1000) fps_ = frames_ * 1000 / (real - fpsSinceReal_), frames_ = 0, fpsSinceReal_ = real;
  if (link_ != Link::kNone && hal_.realMs() - statusReal_ >= kStatusMs) sendStatus(link_);
  if (toolFrozen_ && hal_.realMs() - dbgReal_ >= kThawMs) clock_.run(hal_.realMs()), toolFrozen_ = false;
  uint32_t t = now();
  b_.advance(t, rng_);
  readInputs(t);
  followSound(t);
  sendEnded();

  uint32_t led = b_.led(t);
  if (led != led_) led_ = led, hal_.setLed(led);
  uint8_t bl = b_.backlight(t);
  if (bl != backlight_) backlight_ = bl, hal_.setBacklight(bl);

  Screen screen = screenAt(t);
  if (screen != screen_) screen_ = screen, dirty_ = true;
  // The face may change without a message: its design moves on its own
  // clock (a breath, keys lighting, a blink), so on the face screens every
  // step is checked, and drawn only if its frame changed. A frozen clock
  // looks on every step, so scenario frames stay exact, and the press
  // squish on every pass, so the cap doesn't delay a press.
  bool due = clock_.frozen() || b_.pressEasing(t) || hal_.realMs() - drawnReal_ >= kFrameMs;
  if (dirty_ || (screen_ != Screen::kPattern && t != drawnT_ && due)) render(t);
}

void Device::hush() {
  if (saying_) hal_.hush();
  saying_ = false;
}

// The line that arrived starts its sound when its bubble shows, at the
// volume then; one replaced, or over, before it started is dropped. True
// when it starts now.
bool Device::startLine(uint32_t t) {
  if (!linePending_) return false;
  if (b_.momentSeq() != lineMoment_ || (!b_.bubble(t) && !b_.lineAhead(t))) {
    linePending_ = false;
    return false;
  }
  if (!b_.bubble(t)) return false;  // it waits for its animation's voice window
  linePending_ = false;
  const Model& m = b_.model();
  if (m.vol <= 0) return false;
  line_.vol = uint8_t(m.vol);
  hal_.say(line_);
  saying_ = true;
  sayMoment_ = lineMoment_;
  return true;
}

// Stops a line whose bubble ended or was replaced (a newer moment, say), and
// starts one that waited for its voice window, then plays the face's sound
// effects (VOICE.md §10): its design's events as its clock reaches them,
// and silence for the last design's when it changes or starts over (needs
// you's, for a new request).
void Device::followSound(uint32_t t) {
  if (saying_ && (b_.momentSeq() != sayMoment_ || !b_.bubble(t))) hush();
  startLine(t);
  const Model& m = b_.model();
  render::SceneShow show = b_.show(t);
  show.t = b_.designMs(t);
  voice::FxEvent due[EffectTrack::kMaxOut];
  bool changed;
  int n = fx_.follow(screenAt(t) == Screen::kPattern ? nullptr : &show, due, changed);
  if (changed) hal_.stopEffects();
  if (m.vol == 0) return;
  for (int i = 0; i < n; ++i) {
    voice::Effect e;
    e.clip = due[i].clip;
    e.gain = due[i].gain;
    e.pitch = due[i].pitch;
    e.vol = uint8_t(m.vol);
    e.duck = fx_.duck();
    hal_.effect(e);
    ++fxSent_;
    fxLast_ = e.clip;
  }
}

// Draws the frame for t, unless nothing on it can have changed since the
// last one (DEVICE.md §6): no message or input since (dirty_), the face's
// design on the same steps with the same additions, and the bubble still
// up or still down. The designs step a few times a second, so most passes
// find the picture unchanged.
void Device::render(uint32_t t) {
  drawnT_ = t;
  drawnReal_ = hal_.realMs();
  if (screen_ == Screen::kPattern) {  // drawn only when dirty: it doesn't move
    if (targetX_ >= 0) {
      canvas_.fill(render::kBlack);
      canvas_.fillRect(targetX_ - 10, targetY_ - 1, 21, 3, render::kAmber);
      canvas_.fillRect(targetX_ - 1, targetY_ - 10, 3, 21, render::kAmber);
    } else if (patternFill_ >= 0) {
      canvas_.fill(uint8_t(patternFill_));
    } else {
      render::drawPattern(canvas_);
    }
  } else if (render::SceneShow show = b_.show(t); screen_ == Screen::kNeedsYou && show.state == render::SceneState::kNeedsYou) {
    // Needs you holds up the sign in its design's place (DEVICE.md §6);
    // listening, which plays over it, shows as the face.
    render::SignPose pose = render::signPose(b_.designMs(t), show.eyesShut, show.dy);
    if (!dirty_ && drawnSign_ && pose == drawnPose_) return;
    drawnSign_ = true;
    drawnPose_ = pose;
    drawnFrame_ = render::SceneFrame{};
    render::drawSignScreen(canvas_, pose, b_.strip(t));
  } else {  // the face, needs you's listening and no app: what differs is in the show and the strip
    drawnSign_ = false;
    render::SceneFrame frame = render::sceneFrame(show);
    const char* bubble = b_.bubble(t);
    if (!dirty_ && frame == drawnFrame_ && (bubble != nullptr) == drawnBubble_) return;
    drawnFrame_ = frame;
    drawnBubble_ = bubble != nullptr;
    render::drawFaceScreen(canvas_, frame, bubble, b_.strip(t));
  }
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
  d["fps"] = fps_;
  d["draw_us"] = drawUs_;
  d["push_us"] = pushUs_;
  d["link"] = linkName(link_);
  d["ble"] = hal_.bleState();
  if (hal_.bleName()[0]) d["name"] = hal_.bleName();
  d["voice"] = voice::assetsVersion();
  d["card"] = hal_.cardState();
  d["fx"] = voice::effectsVersion();
  d["w"] = render::kWidth;  // the screen as drawn, for boopctl calibrate
  d["h"] = render::kHeight;
  char buf[384];
  size_t n = serializeJson(d, buf, sizeof(buf));
  reply(to, buf, n);
}

// Each moment the Mac waited on that has ended, once, on the link it came
// in on (PROTOCOL.md §4).
void Device::sendEnded() {
  Ended e;
  while (b_.takeEnded(e)) {
    char buf[80];
    const char* why = cutByName(e.by);
    int n = why ? std::snprintf(buf, sizeof(buf), "{\"t\":\"ended\",\"id\":%lu,\"how\":\"%s\",\"why\":\"%s\"}",
                                (unsigned long)e.id, momentEndName(e.how), why)
                : std::snprintf(buf, sizeof(buf), "{\"t\":\"ended\",\"id\":%lu,\"how\":\"%s\"}", (unsigned long)e.id,
                                momentEndName(e.how));
    if (e.from < 3) reply(Link(e.from), buf, size_t(n));
  }
}

void Device::sendStatus(Link to) {
  statusReal_ = hal_.realMs();
  char buf[160];
  int n = std::snprintf(buf, sizeof(buf), "{\"t\":\"status\",\"id\":\"%s\",\"fw\":\"%s\",\"voice\":\"%s\"}",
                        hal_.deviceId(), hal_.fwVersion(), voice::assetsVersion());
  reply(to, buf, size_t(n));
}

void Device::sendState(Link to) {
  JsonDocument d;
  d["t"] = "dbg.state";
  uint32_t t = now();
  const Model& m = b_.model();
  d["screen"] = screenName(screenAt(t));
  d["base"] = render::stateName(m.base);
  if (m.act != render::SceneState::kWorking) d["act"] = render::stateName(m.act);
  else d["act"] = nullptr;
  d["mood"] = render::moodName(m.mood);
  d["variant"] = m.variant + 1;
  d["look_variant"] = b_.lookVariant() + 1;
  if (m.attn) {
    d["attn"]["agent"] = m.agent;
    d["attn"]["project"] = m.project;
    d["attn"]["name"] = m.name;
    d["attn"]["more"] = m.more;
    d["attn"]["id"] = m.attnId;
  } else {
    d["attn"] = nullptr;
  }
  uint32_t left;
  render::Anim anim = b_.moment(t, left);
  if (anim != render::Anim::kNone) {
    d["moment"]["anim"] = render::animName(anim);
    d["moment"]["left_ms"] = left;
    d["moment"]["variant"] = b_.momentVariant() + 1;
  } else {
    d["moment"] = nullptr;
  }
  render::Mood expr;
  if (b_.expression(t, expr)) d["expr"] = render::moodName(expr);
  else d["expr"] = nullptr;
  if (b_.blinking(t)) d["life"] = "blink";
  else d["life"] = nullptr;
  d["vol"] = m.vol;
  char led[8];
  std::snprintf(led, sizeof(led), "#%06lX", (unsigned long)(b_.led(t) & 0xFFFFFF));
  d["led"] = led;
  d["audio"]["playing"] = b_.speaking(t);
  const char* take = b_.bubble(t) ? voice::takeId(b_.take()) : nullptr;
  if (take) d["audio"]["take"] = take;
  else d["audio"]["take"] = nullptr;
  AudioOut ao = hal_.audioOut();
  JsonObject out = d["audio"]["out"].to<JsonObject>();
  out["ready"] = ao.ready;
  out["playing"] = ao.playing;
  out["lines"] = ao.lines;
  if (voice::takeId(ao.take)) out["take"] = voice::takeId(ao.take);
  else out["take"] = nullptr;
  out["plan_ms"] = ao.planMs;
  out["out_ms"] = ao.outMs;
  out["wall_ms"] = ao.wallMs;
  out["cut"] = ao.cut;
  out["errors"] = ao.errors;
  JsonObject fx = d["audio"]["fx"].to<JsonObject>();
  fx["sent"] = fxSent_;
  if (fxLast_ >= 0) fx["last"] = voice::effectName(fxLast_);
  else fx["last"] = nullptr;
  uint32_t alertAt;
  if (b_.alerted(alertAt)) d["alert"] = alertAt;
  else d["alert"] = nullptr;
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
