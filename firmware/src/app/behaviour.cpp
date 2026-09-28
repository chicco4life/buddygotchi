#include "app/behaviour.h"

#include <algorithm>
#include <cstring>

#include "render/raster.h"
#include "voice/effects.h"

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

render::SceneState actFromName(const char* name) {
  using render::SceneState;
  SceneState s = render::stateFromName(name);
  switch (s) {
    case SceneState::kPlanning:
    case SceneState::kTerminal:
    case SceneState::kToolUse:
    case SceneState::kSearching:
    case SceneState::kAnalyzing:
    case SceneState::kTesting:
    case SceneState::kDelegating:
    case SceneState::kWaiting: return s;
    default: return SceneState::kWorking;
  }
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

bool Behaviour::listening(uint32_t t) const { return momentOn(t) && moment_.anim == render::Anim::kListening; }

// What shows, first first (BEHAVIORS.md §1): no app, listening, needs you,
// then a tap's poke and the moments, then the look. So with no app, while
// something needs you and while listening waits for the reply, a tap only
// dips the face and a moment's animation is skipped.
bool Behaviour::held(uint32_t t) const { return noApp(t) || model_.attn || listening(t); }

bool Behaviour::sayOn(uint32_t t) const { return say_.say.syllables > 0 && within(t, say_.at, say_.ms); }

bool Behaviour::sayDue(uint32_t t) const {
  return say_.say.syllables > 0 && int32_t(t - say_.at) < int32_t(say_.ms);
}

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

// A blink, unless an animation is playing, Boop is asleep, or the look is
// a flip-book, which blinks by itself.
void Behaviour::startBlink(uint32_t t, Rng& rng) {
  Source s = sourceAt(t);
  blink_ = s.anim == render::Anim::kNone && s.look != render::SceneState::kAsleep &&
           s.look != render::SceneState::kNoApp && !render::blinksItself(s.mood, s.look, s.lookVariant);
  blinkAt_ = t;
  nextBlink_ = t + (blink_ ? kBlinkMs : 0) + blinkGap(rng);
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
    // A loop's end is a turn only if the look could take one when it began.
    uint32_t turnAt = loopEnd(modelT_);
    bool turning = turnable(modelT_);
    if (turning) consider(turnAt);
    if (!found) break;
    // Everything due at `next`, in a fixed order.
    resync(next);
    if (next == nextBlink_) startBlink(next, rng);
    if (turning && next == turnAt) turn(next, rng);
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
  if (say_.say.syllables > 0 && !sayDue(t)) say_ = Say{};
  if (blFade_ && !within(t, blAt_, render::kBlendMs)) blFade_ = false;
}

// ---- Taking turns (BEHAVIORS.md §2) ---------------------------------------

// Only the looks that loop on take turns: needs you holds its pose, and no
// app has its one design. A moment or its expression holds the look as it
// is.
bool Behaviour::turnable(uint32_t t) const {
  return !held(t) && !momentOn(t) && !exprOn(t) && render::variants(model_.mood, model_.look()) > 1;
}

uint32_t Behaviour::loopEnd(uint32_t t) const {
  uint32_t loop = render::loopMs(src_.mood, src_.look, src_.lookVariant);
  return t - (t - lookAt_) % loop + loop;
}

// At a loop's end, once the variation has shown kTurnMinMs: another one
// with kTurnPct chance, never the same. The blink that hides a change of
// design hides the cut, and the new one's clock starts from 0.
void Behaviour::turn(uint32_t t, Rng& rng) {
  if (!turnable(t) || int32_t(t - lookAt_) < int32_t(kTurnMinMs)) return;
  if (rng.range(1, 100) > kTurnPct) return;  // another loop of this one
  int v = rng.range(0, render::variants(model_.mood, model_.look()) - 2);
  if (v >= lookVariant_) ++v;
  change(t, [&] { lookVariant_ = uint8_t(v); });
}

// ---- Moments the Mac waits on (PROTOCOL.md §4 `ended`) ---------------------

// A moment is over when none of its parts plays: the animation, the mumble
// and its bubble, the expression. It was cut if its animation or its mumble
// was stopped early. Its expression holds on after its mumble, and ending
// that early doesn't cut it: the reaction was seen and heard.
bool Behaviour::holds(uint32_t id, uint32_t t) const {
  return (momentOn(t) && moment_.id == id) || (sayDue(t) && say_.id == id) || (exprOn(t) && exprId_ == id);
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
    // Another visual, or another variation of it from the Mac, starts the
    // looks' turns over from the Mac's; the same one again leaves them.
    bool look = m.attn != model_.attn || m.look() != model_.look() || m.variant != model_.variant;
    model_ = m;
    if (look) lookVariant_ = m.variant;
    lastState_ = t;
    stale_ = false;
    ledOverride_ = blOverride_ = false;
    if (fresh) {  // a new request: its performance plays from the start, and attention wins
      alerted_ = true, alertAt_ = t;
      lookAt_ = t;
      if (had) switched_ = true, switchAt_ = t;  // starting over mid-performance: the eyes hide the jump
      // Listening is the one moment that plays on (BEHAVIORS.md §1), so
      // push-to-talk still works.
      if (momentOn(t) && !listening(t)) cut(moment_.id, CutBy::kNeedsYou), moment_.anim = render::Anim::kNone;
      if (sayDue(t)) cut(say_.id, CutBy::kNeedsYou);
      say_ = Say{};  // no mumbles while something needs you
      expr_ = false;
    }
    // Answered on the Mac (`attn` leaves), or back after no app: the face
    // blinks into what the state says.
  });
}

// A moment with an animation replaces the one playing, and its mumble too;
// the animation plays its loops of its design. A mumble on its own plays
// over whatever face is showing, replacing any line (PROTOCOL.md §3). With
// an animation, the line starts at its design's voice window (VOICE.md
// §10), and the animation holds on until the line and its bubble are over
// rather than the line being hurried. A moment with an expression draws
// the design showing in its mood for as long as its animation plays, or
// with none for its loops of the design it's drawn in, and at least as long
// as its mumble and bubble. What outranks the moments (BEHAVIORS.md §1): no
// app, and while something needs you no animation takes the face over and
// no mumble plays. A moment the Mac waits on that plays nothing ends at
// once, skipped.
//
// Listening (DEVICE.md §4) plays even while something needs you, and holds
// until the reply: a moment with a `say` is the reply, and ends it before
// playing as it would have; so does the empty moment, which does nothing
// else. Nothing else ends it or plays while it waits: not a one-shot, a
// finish, a face on its own or an animation the device doesn't know. A
// listening moment while listening carries on with the same design, its
// time starting over.
bool Behaviour::onMoment(const MomentIn& in, uint32_t t) {
  if (in.id) forget(in.id);
  const bool listen = in.anim == render::Anim::kListening;
  if (listening(t) && !listen && (in.said || in.empty)) change(t, [&] { moment_.anim = render::Anim::kNone; });
  bool anim = in.anim != render::Anim::kNone && (listen || !held(t));
  bool mumble = in.syllables > 0 && !model_.attn && !noApp(t);
  if (!anim && !mumble) {
    if (in.id) report(Ended{in.id, MomentEnd::kSkipped, CutBy::kNone, in.from});
    return false;
  }
  change(t, [&] {
    const render::Mood mood = in.expr ? in.mood : model_.mood;  // the mood it's drawn in
    uint32_t voice = 0;  // when its line starts, from t
    if (anim && listen && listening(t)) {
      if (moment_.id && moment_.id != in.id) cut(moment_.id, CutBy::kMoment);
      moment_.ms = (t - moment_.at) + kListenMs + kReplyWaitMs;
      moment_.id = in.id;
    } else if (anim) {
      play(in.anim, t, CutBy::kMoment, in.loops, mood, in.variant);
      moment_.id = in.id;
      bool finish = in.anim == render::Anim::kTaskComplete || in.anim == render::Anim::kReplyReady;
      if (finish && in.whoAgent && in.whoAgent[0]) {
        copyStr(moment_.agent, sizeof(moment_.agent), in.whoAgent);
        copyStr(moment_.thread, sizeof(moment_.thread), in.whoThread);
      }
      if (!listen) voice = voice::score(int(mood), int(render::animState(in.anim)), in.variant).voiceMs;
    }
    if (mumble) {
      startSay(in, t, t + voice);
      say_.id = in.id;
      if (anim && !listen && voice + say_.ms > moment_.ms) moment_.ms = voice + say_.ms;
    }
    if (in.expr) {
      expr_ = true;
      exprMood_ = in.mood;
      exprAt_ = t;
      exprMs_ = anim ? moment_.ms : holdMs(in.mood, in.loops, t);
      if (mumble && voice + say_.ms > exprMs_) exprMs_ = voice + say_.ms;
      exprId_ = in.id;
    }
    if (in.id) wait(in.id, in.from);
  });
  return mumble;
}

uint8_t Behaviour::pick(render::Anim a, render::Mood mood, int wanted, render::Outcome o, render::StartCtx c,
                        Rng& rng) const {
  const render::SceneState s = render::animState(a);
  uint8_t fit[render::kMaxVariants];
  int n = render::fitting(mood, s, o, c, fit);
  for (int i = 0; i < n; ++i) {
    if (fit[i] + 1 == wanted) return fit[i];
  }
  uint8_t others[render::kMaxVariants];
  int k = 0;
  for (int i = 0; i < n; ++i) {
    if (fit[i] + 1 != last_[int(s)]) others[k++] = fit[i];
  }
  if (k <= 1) return k ? others[0] : fit[0];  // one to choose: no roll
  return others[rng.range(0, k - 1)];
}

// Whatever of the moment playing still plays is cut short, by `by`.
void Behaviour::play(render::Anim a, uint32_t t, CutBy by, int loops, render::Mood mood, uint8_t variant) {
  if (momentOn(t)) cut(moment_.id, by);
  if (sayDue(t)) cut(say_.id, by);
  moment_ = Moment{};
  ++momentSeq_;
  moment_.anim = a;
  moment_.variant = variant;
  moment_.at = t;
  const render::SceneState s = render::animState(a);
  if (a == render::Anim::kListening) {
    moment_.ms = kListenMs + kReplyWaitMs;
    moment_.playMs = UINT32_MAX;  // its design loops on until the reply
  } else {
    moment_.ms = moment_.playMs = uint32_t(loops) * render::loopMs(mood, s, variant);
  }
  moment_.outcome = render::variantOutcome(mood, s, variant);
  last_[int(s)] = uint8_t(variant + 1);
  say_ = Say{};  // a new moment replaces the line, and its expression
  expr_ = false;
  blink_ = false;
}

// The design is the animation's while one plays, on its clock, else the
// look's, on the look's; the first loop ends at its clock's next boundary
// after t, so it can be short. A later change of look or animation doesn't
// move the end.
uint32_t Behaviour::holdMs(render::Mood mood, int loops, uint32_t t) const {
  Source src = sourceAt(t);
  uint32_t loop = render::loopMs(mood, src.state(), src.variant());
  uint32_t into = (t - (src.anim != render::Anim::kNone ? src.at : lookAt_)) % loop;
  return loop - into + uint32_t(loops - 1) * loop;
}

void Behaviour::startSay(const MomentIn& in, uint32_t t, uint32_t at) {
  if (sayDue(t)) cut(say_.id, CutBy::kMoment);
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
  s.at = at;
  s.ms = s.speakMs + kBubbleReadMs;
}

// ---- Inputs ----------------------------------------------------------------

void Behaviour::pressDown(uint32_t t) {
  pressed_ = true;
  pressAt_ = t;
}

void Behaviour::pressUp() { pressed_ = false; }

// Every tap counts in the run, those that only dip the face too, as the
// Mac counts pokes; while the face is held, a tap shows the press dip only.
// Otherwise it plays poked in Boop's mood, or tap_spam from the run's
// third tap on, cutting whatever plays.
void Behaviour::tap(uint32_t t, Rng& rng) {
  bool inRun = taps_ > 0 && int32_t(t - lastTap_) < int32_t(kTapRunMs);
  taps_ = inRun ? std::min(taps_ + 1, 1000) : 1;
  lastTap_ = t;
  if (held(t)) return;
  const render::Anim a = taps_ >= kTapSpamFrom ? render::Anim::kTapSpam : render::Anim::kPoked;
  const uint8_t v = pick(a, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
  change(t, [&] { play(a, t, CutBy::kTap, 1, model_.mood, v); });
}

// BOOT held: listening at once, even while something needs you, cutting
// whatever else plays as a tap would. Already listening (the Mac's own
// mic), it carries on with the same design.
void Behaviour::talkOn(uint32_t t, Rng& rng) {
  change(t, [&] {
    if (listening(t)) {
      moment_.ms = (t - moment_.at) + kListenMs + kReplyWaitMs;
    } else {
      uint8_t v = pick(render::Anim::kListening, model_.mood, 0, render::Outcome::kNone, render::StartCtx::kNone, rng);
      play(render::Anim::kListening, t, CutBy::kTap, 1, model_.mood, v);
    }
  });
}

// Let go, or capped: listening carries on, with no new blend, and waits
// at most kReplyWaitMs for the reply. If it isn't playing any more (the
// Mac ended it), there's nothing to wait on.
void Behaviour::talkOff(uint32_t t) {
  change(t, [&] {
    if (listening(t) && moment_.ms > (t - moment_.at) + kReplyWaitMs) moment_.ms = (t - moment_.at) + kReplyWaitMs;
  });
}

// ---- What shows ------------------------------------------------------------

Screen Behaviour::screen(uint32_t t) const {
  if (noApp(t)) return Screen::kNoApp;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
}

// No app shows over everything; then an animation (listening only, while
// something needs you) over the look: needs you's, or what the agents are
// doing, idle, working or asleep.
Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  if (noApp(t)) {  // no Mac to pick a variation: the first
    s.look = render::SceneState::kNoApp;
    s.mood = model_.mood;
    return s;
  }
  s.mood = exprOn(t) ? exprMood_ : model_.mood;  // the moment's expression, or the mood
  if (model_.attn) {
    s.look = render::SceneState::kNeedsYou;
    s.lookVariant = model_.variant;
  } else {
    s.look = model_.look();
    s.lookVariant = lookVariant_;
  }
  if (momentOn(t)) s.anim = moment_.anim, s.at = moment_.at, s.animVariant = moment_.variant;
  return s;
}

// The design and its clock: an animation's from when it began, starting
// over each loop and resting on its last frame once its loops are over, a
// look's from when the look began. On top: a blink, or the blink that hides
// a change of design; the mouth an "o" for the first half of each syllable;
// and the press's dip.
render::SceneShow Behaviour::show(uint32_t t) const {
  render::SceneShow s;
  s.mood = src_.mood;
  s.state = src_.state();
  s.variant = src_.variant();
  s.t = designMs(t);
  const uint32_t loop = render::loopMs(s.mood, s.state, s.variant);
  if (src_.anim != render::Anim::kNone) s.t = s.t >= moment_.playMs ? loop - 1 : s.t % loop;
  // Needs you's performance plays once, then holds its pending pose, the
  // frame it starts and ends on (the animation bank's contract).
  if (s.state == render::SceneState::kNeedsYou && s.t >= loop) s.t = 0;
  s.eyesShut = blinking(t) || (switched_ && within(t, switchAt_, render::kBlendMs));
  if (sayOn(t)) {
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
// icon shows (BEHAVIORS.md §3.4). While the brain's finish plays, whose
// turn it was (BEHAVIORS.md §5).
render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  s.noApp = noApp(t);
  if (s.noApp) return s;
  s.busy = model_.busy;
  if (model_.attn) s.agent = model_.agent, s.project = model_.project, s.name = model_.name, s.more = model_.more;
  bool finish = moment_.anim == render::Anim::kTaskComplete || moment_.anim == render::Anim::kReplyReady;
  if (momentOn(t) && finish && moment_.agent[0]) {
    s.doneAgent = moment_.agent, s.doneThread = moment_.thread, s.doneOutcome = moment_.outcome;
  }
  return s;
}

// With no app, no line shows: it outranks the moments.
const render::Mumble* Behaviour::mumble(uint32_t t) const { return sayOn(t) && !noApp(t) ? &say_.say : nullptr; }

bool Behaviour::lineAhead(uint32_t t) const { return sayDue(t) && !sayOn(t); }

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
