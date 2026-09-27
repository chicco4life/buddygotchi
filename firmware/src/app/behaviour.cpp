#include "app/behaviour.h"

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

const char* momentEndName(MomentEnd e) {
  switch (e) {
    case MomentEnd::kCut: return "cut";
    case MomentEnd::kSkipped: return "skipped";
    default: return "done";
  }
}

const char* cutByName(CutBy c) {
  switch (c) {
    case CutBy::kMoment: return "moment";
    case CutBy::kTap: return "tap";
    case CutBy::kNeedsYou: return "needs_you";
    case CutBy::kReset: return "reset";
    default: return nullptr;
  }
}

render::SceneState baseFromName(const char* name) {
  render::SceneState s = render::stateFromName(name);
  return s == render::SceneState::kWorking || s == render::SceneState::kAsleep ? s : render::SceneState::kIdle;
}

// Forgets everything but what the Mac is owed: each moment it waits on
// has stopped playing, cut short.
void Behaviour::reset(uint32_t t, Rng& rng) {
  Owed owed = owed_;
  *this = Behaviour{};
  owed_ = owed;
  for (int i = 0; i < owed_.nWaiting; ++i) cut(owed_.waiting[i].id, CutBy::kReset);
  sweep(t);
  modelT_ = t;
  lastState_ = t;
  nextBlink_ = t + blinkGap(rng);
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

bool Behaviour::exprOn(uint32_t t) const { return expr_ && within(t, exprAt_, exprMs_); }

bool Behaviour::expression(uint32_t t, render::Mood& mood) const {
  if (!exprOn(t)) return false;
  mood = exprMood_;
  return true;
}

// Blinks: every 2–6 s idle, 2–5 s working (BEHAVIORS.md §2). Asleep and
// with no app, the gap passes unblinked.
uint32_t Behaviour::blinkGap(Rng& rng) const {
  int lo = 2000, hi = 6000;
  if (model_.base == render::SceneState::kWorking) hi = 5000;
  return uint32_t(rng.range(lo, hi));
}

// A blink, unless an animation is playing or Boop is asleep.
void Behaviour::startBlink(uint32_t t, Rng& rng) {
  Source s = sourceAt(t);
  blink_ = s.anim == render::Anim::kNone && s.look != render::SceneState::kAsleep &&
           s.look != render::SceneState::kNoApp;
  blinkAt_ = t;
  nextBlink_ = t + (blink_ ? kBlinkMs : 0) + blinkGap(rng);
}

void Behaviour::sound(const char* k, uint32_t t) {
  sfx_ = k;
  sfxAt_ = t;
}

void Behaviour::advance(uint32_t t, Rng& rng) {
  if (int32_t(t - modelT_) < 0) {  // the clock went back: no history to replay
    modelT_ = t;
    if (after(nextBlink_, t + 10000)) nextBlink_ = t + blinkGap(rng);
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
    if (expr_) consider(exprAt_ + exprMs_);
    consider(lastState_ + kNoAppMs);
    consider(nextBlink_);
    if (!found) break;
    // Everything due at `next`, in a fixed order.
    resync(next);
    if (next == nextBlink_) startBlink(next, rng);
  }
  resync(t);
}

// Time-based changes at t: a moment or its expression that has ended, and
// the Mac's silence turning into "no app".
void Behaviour::resync(uint32_t t) {
  settle(t);
  change(t, [&] {
    if (moment_.anim != render::Anim::kNone && !within(t, moment_.at, moment_.ms)) moment_.anim = render::Anim::kNone;
    if (expr_ && !within(t, exprAt_, exprMs_)) expr_ = false;
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

// ---- Moments the Mac waits on (PROTOCOL.md §4 `ended`) ---------------------

// A moment is over when none of its parts plays: the animation, the mumble
// and its bubble, the expression. It was cut if any part was stopped early.
bool Behaviour::holds(uint32_t id, uint32_t t) const {
  return (momentOn(t) && moment_.id == id) || (sayOn(t) && say_.id == id) || (exprOn(t) && exprId_ == id);
}

void Behaviour::wait(uint32_t id, uint8_t from) {
  // Can't overflow: each part holds one moment, and those with none left
  // were ended at the last change.
  if (owed_.nWaiting < Owed::kWaiting) owed_.waiting[owed_.nWaiting++] = Waiting{id, from, CutBy::kNone};
}

// An id the device still waits on, arriving again: the Mac app never
// reuses an id within a launch, so it's an earlier launch's, which is gone.
// Its moment is forgotten, unreported, and whatever of it still plays no
// longer holds the id, so the new moment's end is its own.
void Behaviour::forget(uint32_t id) {
  int kept = 0;
  for (int i = 0; i < owed_.nWaiting; ++i) {
    if (owed_.waiting[i].id != id) owed_.waiting[kept++] = owed_.waiting[i];
  }
  owed_.nWaiting = kept;
  if (moment_.id == id) moment_.id = 0;
  if (say_.id == id) say_.id = 0;
  if (exprId_ == id) exprId_ = 0;
}

// The first cut is the one reported.
void Behaviour::cut(uint32_t id, CutBy by) {
  for (int i = 0; i < owed_.nWaiting; ++i) {
    Waiting& w = owed_.waiting[i];
    if (w.id == id && w.cut == CutBy::kNone) w.cut = by;
  }
}

void Behaviour::sweep(uint32_t t) {
  int kept = 0;
  for (int i = 0; i < owed_.nWaiting; ++i) {
    const Waiting w = owed_.waiting[i];
    if (holds(w.id, t)) {
      owed_.waiting[kept++] = w;
    } else {
      report(Ended{w.id, w.cut == CutBy::kNone ? MomentEnd::kDone : MomentEnd::kCut, w.cut, w.from});
    }
  }
  owed_.nWaiting = kept;
}

// Device takes the ends after every line and tick, so a few are enough.
void Behaviour::report(const Ended& e) {
  if (owed_.nEnded < Owed::kEnded) owed_.ended[owed_.nEnded++] = e;
}

bool Behaviour::takeEnded(Ended& e) {
  if (owed_.nEnded == 0) return false;
  e = owed_.ended[0];
  for (int i = 1; i < owed_.nEnded; ++i) owed_.ended[i - 1] = owed_.ended[i];
  --owed_.nEnded;
  return true;
}

// ---- Messages --------------------------------------------------------------

void Behaviour::onState(const Model& m, uint32_t t) {
  change(t, [&] {
    // A different request shown: another number, or another agent or
    // project (all a Mac that sends no number says).
    bool had = model_.attn;
    bool fresh = m.attn && (!had || m.attnId != model_.attnId || std::strncmp(model_.agent, m.agent, sizeof(m.agent)) ||
                            std::strncmp(model_.project, m.project, sizeof(m.project)));
    model_ = m;
    lastState_ = t;
    stale_ = false;
    ledOverride_ = blOverride_ = false;
    if (fresh) {  // a new "needs you": one chirp, and attention wins
      sound("chirp", t);
      if (momentOn(t)) cut(moment_.id, CutBy::kNeedsYou), moment_.anim = render::Anim::kNone;
      if (sayOn(t)) cut(say_.id, CutBy::kNeedsYou);
      if (exprOn(t)) cut(exprId_, CutBy::kNeedsYou);
      say_ = Say{};  // no mumbles while something needs you
      expr_ = false;
    }
    // Answered on the Mac (`attn` leaves), or back after no app: the face
    // blinks into what the state says.
  });
}

// A moment with an anim replaces the one playing, and its mumble too; the
// cheer plays its loops. A mumble on its own plays over whatever face is
// showing, replacing any line (PROTOCOL.md §3). A moment with an
// expression draws the look in its mood for as long as its animation
// plays, or with none for its loops of the design it's drawn in, and at
// least as long as its mumble and bubble. Attention wins (BEHAVIORS.md
// §1): while something needs you, no animation takes the face over and no
// mumble plays. A moment the Mac waits on that plays nothing ends at once,
// skipped.
bool Behaviour::onMoment(const MomentIn& in, uint32_t t) {
  if (in.id) forget(in.id);
  bool anim = in.anim != render::Anim::kNone && !held(t);
  bool mumble = in.syllables > 0 && !model_.attn;
  if (!anim && !mumble) {
    if (in.id) report(Ended{in.id, MomentEnd::kSkipped, CutBy::kNone, in.from});
    return false;
  }
  change(t, [&] {
    if (anim) play(in.anim, t, CutBy::kMoment, in.loops, in.expr ? in.mood : model_.mood), moment_.id = in.id;
    if (mumble) startSay(in, t), say_.id = in.id;
    if (in.expr) {
      expr_ = true;
      exprMood_ = in.mood;
      exprAt_ = t;
      exprMs_ = anim ? moment_.ms : holdMs(in.mood, in.loops, t);
      if (mumble && say_.ms > exprMs_) exprMs_ = say_.ms;
      exprId_ = in.id;
    }
    if (in.id) wait(in.id, in.from);
  });
  return mumble;
}

// Whatever of the moment playing still plays is cut short, by `by`.
void Behaviour::play(render::Anim a, uint32_t t, CutBy by, int loops, render::Mood mood) {
  if (momentOn(t)) cut(moment_.id, by);
  if (sayOn(t)) cut(say_.id, by);
  if (exprOn(t)) cut(exprId_, by);
  moment_ = Moment{};
  ++momentSeq_;
  moment_.anim = a;
  moment_.at = t;
  moment_.ms = a == render::Anim::kWiggle ? render::kWiggleMs
               : a == render::Anim::kCheer   ? uint32_t(loops) * render::loopMs(mood, render::SceneState::kTaskComplete)
                                             : 0;
  say_ = Say{};  // a new moment replaces the line, and its expression
  expr_ = false;
  blink_ = false;
}

// The design is the cheer's while one plays, on the cheer's clock, else
// the look's, on the look's; the first loop ends at its clock's next
// boundary after t, so it can be short. A later change of look or cheer
// doesn't move the end.
uint32_t Behaviour::holdMs(render::Mood mood, int loops, uint32_t t) const {
  bool cheer = momentOn(t) && moment_.anim == render::Anim::kCheer;
  uint32_t loop = render::loopMs(mood, cheer ? render::SceneState::kTaskComplete : sourceAt(t).look);
  uint32_t into = (t - (cheer ? moment_.at : lookAt_)) % loop;
  return loop - into + uint32_t(loops - 1) * loop;
}

void Behaviour::startSay(const MomentIn& in, uint32_t t) {
  if (sayOn(t)) cut(say_.id, CutBy::kMoment);
  if (exprOn(t)) cut(exprId_, CutBy::kMoment);
  say_ = Say{};
  expr_ = false;  // a new line ends the last moment's expression
  ++momentSeq_;
  Say& s = say_;
  copyStr(s.word, sizeof(s.word), in.word);
  s.say.syllables = in.syllables;
  s.say.word = s.word[0] ? s.word : nullptr;
  s.say.at = s.word[0] ? in.at : -1;
  s.sylMs = in.ms;
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

void Behaviour::pressUp() { pressed_ = false; }

// While the face is held, a tap shows the press dip only.
void Behaviour::tap(uint32_t t) {
  if (held(t)) return;
  change(t, [&] { play(render::Anim::kWiggle, t, CutBy::kTap); });
}

// ---- What shows ------------------------------------------------------------

Screen Behaviour::screen(uint32_t t) const {
  if (noApp(t)) return Screen::kNoApp;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
}

Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  s.mood = exprOn(t) ? exprMood_ : model_.mood;  // the moment's expression, or the mood
  if (noApp(t)) {
    s.look = render::SceneState::kNoApp;
  } else if (model_.attn) {
    s.look = render::SceneState::kNeedsYou;
  } else {
    s.look = model_.base;
  }
  if (momentOn(t)) s.anim = moment_.anim, s.at = moment_.at;
  return s;
}

// The design and its clock: the cheer's from when it began, starting over
// each loop, a look's from when the look began, so a tap's wiggle doesn't
// restart it. On top: a blink, or the blink that hides a change of design;
// the wiggle's sway and heart; the bubble taking the prop's room, and the
// mouth an "o" for the first half of each syllable; and the press's dip.
render::SceneShow Behaviour::show(uint32_t t) const {
  render::SceneShow s;
  s.mood = src_.mood;
  s.state = src_.state();
  s.t = src_.anim == render::Anim::kCheer ? (t - src_.at) % render::loopMs(s.mood, s.state) : t - lookAt_;
  if (src_.anim == render::Anim::kWiggle) {
    // Two slow sways, not a shiver: at 175 ms and 7 px it read as trembling.
    uint32_t lt = t - src_.at;
    s.dx = int16_t(3 * render::isin(int(lt % 350 * 1024 / 350)) / 1024);
    s.heart = lt < 100 ? 1 : 2;
  }
  s.eyesShut = blinking(t) || (switched_ && within(t, switchAt_, render::kBlendMs));
  if (sayOn(t)) {
    s.hideProp = true;
    uint32_t lt = t - say_.at;
    s.mouthOpen = say_.sylMs && lt < say_.speakMs && lt % say_.sylMs < say_.sylMs / 2;
  }
  if (pressed_) s.dy = int16_t(s.dy + kPressPx);
  return s;
}

bool Behaviour::pressEasing(uint32_t t) const { return pressed_ && within(t, pressAt_, kPressEaseMs); }

const char* Behaviour::faceName(uint32_t t) const {
  Source s = sourceAt(t);
  return s.anim != render::Anim::kNone ? render::animName(s.anim) : render::stateName(s.look);
}

bool Behaviour::blinking(uint32_t t) const { return blink_ && within(t, blinkAt_, kBlinkMs); }

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
  if (model_.base == render::SceneState::kAsleep) return 60;
  return 255;
}

// With no app the Mac's counts are stale, so only the unplugged
// icon shows (BEHAVIORS.md §3.4).
render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  s.noApp = noApp(t);
  if (s.noApp) return s;
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
