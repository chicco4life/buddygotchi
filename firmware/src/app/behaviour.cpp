#include "app/behaviour.h"

#include <cstdio>
#include <cstring>

#include "render/raster.h"

namespace app {

namespace {

constexpr uint32_t kAmberDim = 0x805800;  // needs you: amber at half

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b
bool within(uint32_t t, uint32_t from, uint32_t ms) { return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms); }

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
  lookAt_ = t;
}

// ---- Time ------------------------------------------------------------------

bool Behaviour::noApp(uint32_t t) const { return stale_ || int32_t(t - lastState_) >= int32_t(kNoAppMs); }

bool Behaviour::momentOn(uint32_t t) const {
  return moment_.anim != render::Anim::kNone && within(t, moment_.at, moment_.ms);
}

bool Behaviour::held(uint32_t t) const { return model_.attn && !noApp(t); }

bool Behaviour::sayOn(uint32_t t) const { return say_.say.syllables > 0 && within(t, say_.at, say_.ms); }

// Blinks: every 2–6 s idle, 2–5 s working (BEHAVIORS.md §2). Asleep and
// with no app, the gap passes unblinked.
uint32_t Behaviour::lifeGap(Rng& rng) const {
  int lo = 2000, hi = 6000;
  if (!std::strcmp(model_.base, "working")) hi = 5000;
  return uint32_t(rng.range(lo, hi));
}

// A blink, unless an animation is playing or Boop is asleep.
void Behaviour::startLife(uint32_t t, Rng& rng) {
  life_ = LifeEvent{};
  Source s = sourceAt(t);
  if (s.anim == render::Anim::kNone && s.look != render::Look::kAsleep && s.look != render::Look::kNoApp) {
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

// Time-based changes at t: a moment that has ended, and the Mac's silence
// turning into "no app".
void Behaviour::resync(uint32_t t) {
  settle(t);
  change(t, [&] {
    if (moment_.anim != render::Anim::kNone && !within(t, moment_.at, moment_.ms)) moment_.anim = render::Anim::kNone;
    if (!stale_ && int32_t(t - lastState_) >= int32_t(kNoAppMs)) stale_ = true;
  });
}

// Clears timers that have run out, so none comes back when the clock's
// differences wrap after 2^31 ms (24.9 days). None of them is part of the
// source, so the face doesn't change.
void Behaviour::settle(uint32_t t) {
  if (switched_ && !within(t, switchAt_, render::kBlendMs)) switched_ = false;
  if (say_.say.syllables > 0 && !within(t, say_.at, say_.ms)) say_ = Say{};
  if (blFade_ && !within(t, blAt_, render::kBlendMs)) blFade_ = false;
}

// ---- Messages --------------------------------------------------------------

void Behaviour::onState(const Model& m, uint32_t t) {
  change(t, [&] {
    bool had = model_.attn;
    bool fresh = m.attn && (!had || std::strncmp(model_.agent, m.agent, sizeof(m.agent)) ||
                            std::strncmp(model_.project, m.project, sizeof(m.project)));
    model_ = m;
    lastState_ = t;
    stale_ = false;
    ledOverride_ = blOverride_ = false;
    if (fresh) {  // a new "needs you": one chirp, and attention wins
      sound("chirp", t);
      if (momentOn(t)) moment_.anim = render::Anim::kNone;
      say_ = Say{};  // no mumbles while something needs you
    }
    // Answered on the Mac (`attn` leaves), or back after no app: the face
    // blinks into what the state says.
  });
}

// A moment with an anim replaces the one playing, and its mumble too. A
// mumble on its own plays over whatever face is showing and doesn't change
// it (PROTOCOL.md §3). Attention wins (BEHAVIORS.md §1): while something
// needs you, no animation takes the face over and no mumble plays.
bool Behaviour::onMoment(const MomentIn& in, uint32_t t) {
  bool anim = in.anim != render::Anim::kNone && !held(t);
  bool mumble = in.syllables > 0 && !model_.attn;
  if (!anim && !mumble) return false;
  change(t, [&] {
    if (anim) play(in.anim, t);
    if (mumble) startSay(in, t);
  });
  return mumble;
}

void Behaviour::play(render::Anim a, uint32_t t) {
  moment_ = Moment{};
  ++momentSeq_;
  moment_.anim = a;
  moment_.at = t;
  moment_.ms = render::animDuration(a);
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
  s.say.at = s.word[0] ? render::clamp(in.at < 0 ? in.syllables : in.at, 0, in.syllables) : -1;
  s.sylMs = uint32_t(render::clamp(int(in.ms), 60, 400));
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

void Behaviour::pressUp(uint32_t) { pressed_ = false; }

// While the face is held, a tap shows the press dip only.
void Behaviour::tap(uint32_t t) {
  if (held(t)) return;
  change(t, [&] { play(render::Anim::kWiggle, t); });
}

// ---- What shows ------------------------------------------------------------

Screen Behaviour::screen(uint32_t t) const {
  if (noApp(t)) return Screen::kNoApp;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
}

Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  s.mood = model_.mood;
  if (sayOn(t)) s.say = true, s.sayAt = say_.at, s.speakMs = say_.speakMs, s.sylMs = say_.sylMs;
  if (noApp(t)) {
    s.look = render::Look::kNoApp;
  } else if (model_.attn) {
    s.look = render::Look::kNeedsYou;
  } else if (!std::strcmp(model_.base, "asleep")) {
    s.look = render::Look::kAsleep;
  } else if (!std::strcmp(model_.base, "working")) {
    s.look = render::Look::kWorking;
  }
  if (momentOn(t)) s.anim = moment_.anim, s.at = moment_.at;
  return s;
}

render::SceneState Behaviour::Source::state() const {
  if (anim == render::Anim::kCheer) return render::SceneState::kTaskComplete;
  switch (look) {
    case render::Look::kWorking: return render::SceneState::kWorking;
    case render::Look::kAsleep: return render::SceneState::kAsleep;
    case render::Look::kNeedsYou: return render::SceneState::kNeedsYou;
    case render::Look::kNoApp: return render::SceneState::kNoApp;
    default: return render::SceneState::kIdle;
  }
}

// The design and its clock: the cheer's from when it began, a look's from
// when the look began, so a tap's wiggle doesn't restart it. On top: a
// blink, or the blink that hides a change of design; the wiggle's sway and
// heart; the bubble taking the prop's room, and the mouth an "o" for the
// first half of each syllable; and the press's dip.
render::SceneShow Behaviour::show(uint32_t t) const {
  render::SceneShow s;
  s.mood = src_.mood;
  s.state = src_.state();
  s.t = src_.anim == render::Anim::kCheer ? t - src_.at : t - lookAt_;
  if (src_.anim == render::Anim::kWiggle) {
    // Two slow sways, not a shiver: at 175 ms and 7 px it read as trembling.
    uint32_t lt = t - src_.at;
    s.dx = int16_t(3 * render::isin(int(lt % 350 * 1024 / 350)) / 1024);
    s.heart = lt < 100 ? 1 : 2;
  }
  bool blink = life_.kind == Life::kBlink && within(t, life_.at, life_.ms);
  s.eyesShut = blink || (switched_ && within(t, switchAt_, render::kBlendMs));
  if (src_.say) {
    s.hideProp = true;
    uint32_t lt = t - src_.sayAt;
    s.mouthOpen = src_.sylMs && lt < src_.speakMs && lt % src_.sylMs < src_.sylMs / 2;
  }
  if (pressed_) s.dy = int16_t(s.dy + kPressPx);
  return s;
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

// Dims with the asleep look, eased over kBlendMs.
uint8_t Behaviour::backlight(uint32_t t) const {
  if (blOverride_) return blSet_;
  int target = blLevel_;
  if (!blFade_ || !within(t, blAt_, render::kBlendMs)) return uint8_t(target);
  return uint8_t(blFrom_ + (target - blFrom_) * render::ease(int(t - blAt_), int(render::kBlendMs)) / 1024);
}

uint8_t Behaviour::blTarget(uint32_t t) const {
  if (noApp(t)) return 60;      // dimmed like asleep
  if (model_.attn) return 255;  // dimming never hides "needs you"
  if (!std::strcmp(model_.base, "asleep")) return 60;
  return 255;
}

// With no app the Mac's counts are stale, so only the unplugged
// icon shows (BEHAVIORS.md §3.4).
render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  s.noApp = noApp(t);
  if (s.noApp) return s;
  s.wait = model_.wait;
  s.busy = model_.busy;
  if (model_.attn) s.agent = model_.agent, s.project = model_.project, s.more = model_.more;
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
