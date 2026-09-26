#include "app/behaviour.h"

#include <cstdio>
#include <cstring>

#include "render/raster.h"

namespace app {

namespace {

constexpr uint32_t kAmberDim = 0x805800;  // needs you: amber at half

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b
bool within(uint32_t t, uint32_t from, uint32_t ms) { return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms); }
int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// The one moment that may play while something needs you (BEHAVIORS.md §1:
// attention wins), so push-to-talk still works.
bool overAttention(render::Anim a) { return a == render::Anim::kListening; }

// 0 → 1024 → 0: up over `in` ms, held, down over the last `out` ms.
int envelope(uint32_t t, uint32_t ms, uint32_t in, uint32_t out) {
  if (t >= ms) return 0;
  if (t < in) return render::ease(int(t), int(in));
  if (t + out > ms) return 1024 - render::ease(int(t + out - ms), int(out));
  return 1024;
}

}  // namespace

const char* screenName(Screen s) {
  switch (s) {
    case Screen::kFace: return "face";
    case Screen::kNeedsYou: return "needs_you";
    case Screen::kNoApp: return "no_app";
    case Screen::kPattern: return "pattern";
  }
  return "face";
}

const char* lifeName(Life l) { return l == Life::kBlink ? "blink" : nullptr; }

void Behaviour::reset(uint32_t t, Rng& rng) {
  *this = Behaviour{};
  modelT_ = t;
  lastState_ = t;
  nextLife_ = t + lifeGap(rng);
  src_ = sourceAt(t);
}

// ---- Time ------------------------------------------------------------------

bool Behaviour::noApp(uint32_t t) const { return stale_ || int32_t(t - lastState_) >= int32_t(kNoAppMs); }

bool Behaviour::momentOn(uint32_t t) const {
  return moment_.anim != render::Anim::kNone && within(t, moment_.at, moment_.ms);
}

bool Behaviour::sayOn(uint32_t t) const { return say_.say.syllables > 0 && within(t, say_.at, say_.ms); }

// Blinks: every 2–6 s idle, 2–5 s working (1.2–3.5 s with 3+ busy)
// (BEHAVIORS.md §2). Asleep, and so with no app, the gap passes unblinked.
uint32_t Behaviour::lifeGap(Rng& rng) const {
  int lo = 2000, hi = 6000;
  if (!std::strcmp(model_.base, "working")) lo = model_.busy >= 3 ? 1200 : 2000, hi = model_.busy >= 3 ? 3500 : 5000;
  return uint32_t(rng.range(lo, hi));
}

// A blink, unless an animation is playing or Boop is asleep.
void Behaviour::startLife(uint32_t t, Rng& rng) {
  life_ = LifeEvent{};
  Source s = sourceAt(t);
  if (s.anim == render::Anim::kNone && s.look != render::Look::kAsleep) {
    life_.kind = Life::kBlink, life_.at = t, life_.ms = kBlinkMs;
  }
  nextLife_ = t + life_.ms + lifeGap(rng);
}

void Behaviour::sound(const char* k, uint32_t t) {
  sfx_ = k;
  sfxAt_ = t;
}

void Behaviour::advance(uint32_t t, Rng& rng) {
  if (int32_t(t - modelT_) < 0) {  // the clock went back: no history to replay
    modelT_ = t;
    if (after(nextLife_, t + 10000)) nextLife_ = t + lifeGap(rng);
    resync(t);
    return;
  }
  for (;;) {
    bool found = false;
    uint32_t next = t;
    auto consider = [&](uint32_t c) {
      if (after(c, modelT_) && !after(c, t) && (!found || after(next, c))) next = c, found = true;
    };
    if (moment_.anim != render::Anim::kNone) consider(moment_.at + moment_.ms);
    if (say_.say.syllables > 0) consider(say_.at + say_.ms);
    consider(lastState_ + kNoAppMs);
    consider(nextLife_);
    if (!found) break;
    // Everything due at `next`, in a fixed order.
    resync(next);
    if (next == nextLife_) startLife(next, rng);
  }
  resync(t);
}

// Time-based changes at t: a moment that has ended (the blend starts from
// its last pose), and the Mac's silence turning into "no app".
void Behaviour::resync(uint32_t t) {
  settle(t);
  change(t, [&] {
    if (moment_.anim != render::Anim::kNone && !within(t, moment_.at, moment_.ms)) moment_.anim = render::Anim::kNone;
    if (!stale_ && int32_t(t - lastState_) >= int32_t(kNoAppMs)) stale_ = true;
  });
}

// Clears timers that have run out, so none comes back when the clock's
// differences wrap: the blend's signed compare after 2^31 ms (24.9 days),
// the others after 2^32 (49.7 days). None of them is part of the source,
// so the face doesn't change.
void Behaviour::settle(uint32_t t) {
  if (blending_ && !within(t, blendAt_, render::kBlendMs)) blend_ = render::Blend{}, blending_ = false;
  if (say_.say.syllables > 0 && !within(t, say_.at, say_.ms)) say_ = Say{};
  if (releaseAt_ && !within(t, releaseAt_, kPressEaseMs)) releaseAt_ = 0;
  if (blFade_ && !within(t, blAt_, render::kBlendMs)) blFade_ = false;
}

// ---- Messages --------------------------------------------------------------

void Behaviour::onState(const Model& m, uint32_t t, Rng& rng) {
  (void)rng;
  change(t, [&] {
    bool wasNoApp = noApp(t);
    bool had = model_.attn;
    bool fresh = m.attn && (!had || std::strncmp(model_.agent, m.agent, sizeof(m.agent)) ||
                            std::strncmp(model_.project, m.project, sizeof(m.project)));
    model_ = m;
    lastState_ = t;
    stale_ = false;
    ledOverride_ = blOverride_ = false;
    if (fresh) {  // a new "needs you": one chirp, and attention wins
      sound("chirp", t);
      if (momentOn(t) && !overAttention(moment_.anim)) moment_.anim = render::Anim::kNone;
      say_ = Say{};  // no mumbles while something needs you
    }
    // Answered on the Mac (`attn` leaves): the face just blends back.
    if (wasNoApp && heard_ && !momentOn(t)) {  // reconnect: a quick blink
      life_ = LifeEvent{};
      life_.kind = Life::kBlink, life_.at = t, life_.ms = kBlinkMs;
    }
    heard_ = true;
  });
}

// A moment with an anim replaces the one playing, and its mumble too. A
// mumble on its own plays over whatever face is showing and doesn't change
// it, except that it's the reply `listening` waits for, so it ends that,
// even when it doesn't show (needs you, quiet). The empty moment ends
// `listening` too, and nothing else (PROTOCOL.md §3).
bool Behaviour::onMoment(const MomentIn& in, uint32_t t, Rng& rng) {
  bool anim = in.anim != render::Anim::kNone;
  if (anim && model_.attn && !noApp(t) && !overAttention(in.anim)) return false;
  bool mumble = in.syllables > 0 && !model_.attn && model_.quiet <= 0;
  bool ends = !anim && (in.syllables > 0 || in.empty) && momentOn(t) && moment_.anim == render::Anim::kListening;
  if (!anim && !mumble && !ends) return false;
  (void)rng;
  change(t, [&] {
    if (anim) play(in.anim, t, false);
    else if (ends) moment_.anim = render::Anim::kNone;
    if (mumble) startSay(in, t);
  });
  return mumble;
}

void Behaviour::play(render::Anim a, uint32_t t, bool local) {
  moment_ = Moment{};
  ++momentSeq_;
  moment_.anim = a;
  moment_.at = t;
  moment_.ms = render::animDuration(a);
  moment_.local = local;
  say_ = Say{};  // a new moment replaces the line
  life_ = LifeEvent{};
}

void Behaviour::startSay(const MomentIn& in, uint32_t t) {
  say_ = Say{};
  ++momentSeq_;
  Say& s = say_;
  std::snprintf(s.word, sizeof(s.word), "%s", in.word ? in.word : "");
  s.say.syllables = in.syllables;
  s.say.word = s.word[0] ? s.word : nullptr;
  s.say.at = s.word[0] ? clamp(in.at < 0 ? in.syllables : in.at, 0, in.syllables) : -1;
  s.sylMs = uint32_t(clamp(int(in.ms), 60, 400));
  s.speakMs = uint32_t(in.syllables + (s.word[0] ? 2 : 0)) * s.sylMs;  // a word is two beats
  s.at = t;
  s.ms = s.speakMs + kBubbleReadMs;
  // With an animation, the bubble stays at least as long as it plays.
  if (moment_.anim != render::Anim::kNone && moment_.at == t && moment_.ms > s.ms) s.ms = moment_.ms;
}

// ---- Inputs ----------------------------------------------------------------

void Behaviour::pressDown(uint32_t t) {
  pressed_ = true;
  pressAt_ = t;
}

void Behaviour::pressUp(uint32_t t) {
  if (!pressed_) return;
  pressed_ = false;
  releaseAt_ = t;
}

// While something needs you, a tap shows the press squash only.
void Behaviour::tap(uint32_t t, Rng& rng) {
  (void)rng;
  if (model_.attn && !noApp(t)) return;
  change(t, [&] { play(render::Anim::kWiggle, t, true); });
}

void Behaviour::talkOn(uint32_t t, Rng& rng) {
  (void)rng;
  change(t, [&] { play(render::Anim::kListening, t, true); });
}

// Released: listening carries on, without a new blend, and waits at most
// kReplyWaitMs for the reply (BEHAVIORS.md §3.3). If it isn't playing any
// more (the 30 s cap, or the Mac replaced it), there's nothing to wait on.
void Behaviour::talkOff(uint32_t t, Rng& rng) {
  (void)rng;
  change(t, [&] {
    if (momentOn(t) && moment_.anim == render::Anim::kListening) moment_.ms = (t - moment_.at) + kReplyWaitMs;
  });
}

// ---- What shows ------------------------------------------------------------

Screen Behaviour::screen(uint32_t t) const {
  if (noApp(t)) return Screen::kNoApp;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
}

Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  if (sayOn(t)) s.say = true, s.sayAt = say_.at, s.speakMs = say_.speakMs, s.sylMs = say_.sylMs;
  if (momentOn(t)) {
    s.anim = moment_.anim, s.at = moment_.at;
    s.raised = model_.attn;
    return s;
  }
  if (noApp(t)) {
    s.look = render::Look::kAsleep;  // no app looks asleep; the strip's icon tells them apart
  } else if (model_.attn) {
    s.look = render::Look::kNeedsYou;
  } else if (!std::strcmp(model_.base, "asleep")) {
    s.look = render::Look::kAsleep;
  } else if (!std::strcmp(model_.base, "working")) {
    s.look = render::Look::kWorking;
    s.busier = model_.busy >= 3;
  }
  return s;
}

// The look, with its own motion and idle life on top.
render::Pose Behaviour::basePose(const Source& s, uint32_t t) const {
  render::Pose p = render::lookPose(s.look, s.busier ? 3 : 1);
  if (s.look == render::Look::kNeedsYou) p.raise = 1000;
  if (s.look == render::Look::kAsleep) {  // slow breathing, and "zzZZ" rising every 2.4 s
    p.size = int16_t(p.size + 14 * render::isin(int(t % 4000 * 1024 / 4000)) / 1024);
    p.zzz = int16_t(1 + t % 2400 * 999 / 2400);
  }
  if (s.look == render::Look::kWorking) {
    // Effort: every couple of seconds (more often when busier) Boop strains
    // for 0.8 s: the eyes squeeze, the mouth tightens and a small shiver
    // runs through it. A sweat drop slides down beside the right eye.
    uint32_t period = s.busier ? 1800 : 2600;
    int e = envelope(t % period, 800, 150, 250);
    p.squash = int16_t(p.squash + 240 * e / 1024);
    p.lidTop = int16_t(p.lidTop + 170 * e / 1024);
    p.mouthWide = int16_t(p.mouthWide - (p.mouthWide - 450) * e / 1024);
    p.mouthCurve = int16_t(p.mouthCurve - 150 * e / 1024);
    p.dy = int16_t(p.dy + 2 * e / 1024);
    p.dx = int16_t(p.dx + 2 * render::isin(int(t % 90 * 1024 / 90)) / 1024 * e / 1024);
    p.sweat = int16_t(1 + t % 3000 * 999 / 3000);
  }
  if (life_.kind != Life::kBlink || !within(t, life_.at, life_.ms)) return p;
  uint32_t lt = t - life_.at;
  render::Pose q = p;
  q.open = 0;
  int env = lt < 90 ? render::ease(int(lt), 90) : 1024 - render::ease(int(lt - 90), 90);
  return render::blend(p, q, env);
}

render::Pose Behaviour::sourcePose(const Source& s, uint32_t t) const {
  render::Pose p;
  if (s.anim == render::Anim::kNone) {
    p = basePose(s, t);
  } else {
    p = render::animPose(s.anim, t - s.at);
    if (s.raised) p.raise = 1000;  // where the needs-you face sits
  }
  if (s.say) p.raise = 1000;  // room for the bubble
  if (s.say && s.sylMs && t - s.sayAt < s.speakMs) {  // the mouth follows the syllables
    uint32_t lt = t - s.sayAt;
    int phase = int(lt % s.sylMs * 512 / s.sylMs);
    int open = 150 + 550 * render::isin(phase) / 1024;
    if (open > p.mouthOpen) p.mouthOpen = int16_t(open);
    if (p.mouthWide > 750) p.mouthWide = 750;
  }
  return p;
}

render::Pose Behaviour::pose(uint32_t t) const {
  render::Pose p = blended(t);
  int amt = 0;  // the press squish: feedback on the press itself
  if (pressed_) amt = pressEasing(t) ? render::ease(int(t - pressAt_), kPressEaseMs) : 1024;
  else if (within(t, releaseAt_, kPressEaseMs) && releaseAt_) amt = 1024 - render::ease(int(t - releaseAt_), kPressEaseMs);
  if (amt) {
    p.squash = int16_t(p.squash + 200 * amt / 1024);
    p.dy = int16_t(p.dy + 4 * amt / 1024);
  }
  return p;
}

bool Behaviour::moving(uint32_t t) const {
  if (momentOn(t) || sayOn(t) || blend_.blending(t)) return true;
  if (life_.kind != Life::kNone && within(t, life_.at, life_.ms)) return true;
  // The looks with motion of their own: asleep breathes and says zzZZ,
  // working strains and sweats (BEHAVIORS.md §2).
  bool looping = src_.look == render::Look::kAsleep || src_.look == render::Look::kWorking;
  if (src_.anim == render::Anim::kNone && looping) return true;
  if (pressed_ ? pressEasing(t) : (releaseAt_ && within(t, releaseAt_, kPressEaseMs))) return true;
  return false;
}

bool Behaviour::pressEasing(uint32_t t) const { return pressed_ && within(t, pressAt_, kPressEaseMs); }

const char* Behaviour::faceName(uint32_t t) const {
  Source s = sourceAt(t);
  return s.anim != render::Anim::kNone ? render::animName(s.anim) : render::lookName(s.look);
}

Life Behaviour::life(uint32_t t) const {
  return life_.kind != Life::kNone && within(t, life_.at, life_.ms) ? life_.kind : Life::kNone;
}

// Amber at half while something needs you; otherwise off (BEHAVIORS.md §3.2).
uint32_t Behaviour::led(uint32_t t) const {
  if (ledOverride_) return ledSet_;
  if (noApp(t)) return 0;
  return model_.attn ? kAmberDim : 0;
}

// Dims with the asleep look, eased over the face's blend.
uint8_t Behaviour::backlight(uint32_t t) const {
  if (blOverride_) return blSet_;
  int target = blLevel_;
  if (!blFade_ || !within(t, blAt_, render::kBlendMs)) return uint8_t(target);
  return uint8_t(blFrom_ + (target - blFrom_) * render::ease(int(t - blAt_), int(render::kBlendMs)) / 1024);
}

uint8_t Behaviour::blTarget(uint32_t t) const {
  if (noApp(t)) return 60;      // the asleep look, dimmed like asleep
  if (model_.attn) return 255;  // dimming never hides "needs you"
  if (!std::strcmp(model_.base, "asleep")) return 60;
  return 255;
}

// With no app the Mac's counts and quiet are stale, so only the unplugged
// icon shows (BEHAVIORS.md §3.4).
render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  s.noApp = noApp(t);
  if (s.noApp) return s;
  s.wait = model_.wait;
  s.busy = model_.busy;
  s.quiet = model_.quiet > 0;
  return s;
}

const render::Mumble* Behaviour::mumble(uint32_t t) const { return sayOn(t) ? &say_.say : nullptr; }

render::Anim Behaviour::moment(uint32_t t, uint32_t& left) const {
  if (!momentOn(t)) {
    left = 0;
    return render::Anim::kNone;
  }
  left = moment_.at + moment_.ms - t;
  return moment_.anim;
}

bool Behaviour::speaking(uint32_t t) const { return sayOn(t) && within(t, say_.at, say_.speakMs); }

}  // namespace app
