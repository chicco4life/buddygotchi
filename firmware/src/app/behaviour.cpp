#include "app/behaviour.h"

#include <cstdio>
#include <cstring>

#include "render/raster.h"

namespace app {

namespace {

constexpr uint32_t kAmber = 0xFFB000, kAmberDim = 0x805800, kWarm = 0xFF7020;

bool after(uint32_t a, uint32_t b) { return int32_t(a - b) > 0; }  // a later than b
bool within(uint32_t t, uint32_t from, uint32_t ms) { return int32_t(t - from) >= 0 && int32_t(t - from) < int32_t(ms); }
int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// Moments that may play while something needs you (BEHAVIORS.md §1:
// attention wins). Only direct replies to the person get through.
bool overAttention(render::Anim a) {
  using render::Anim;
  return a == Anim::kNod || a == Anim::kListening || a == Anim::kThinking || a == Anim::kShrug ||
         a == Anim::kZip;
}

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
    case Screen::kThreads: return "threads";
    case Screen::kStats: return "stats";
    case Screen::kNoApp: return "no_app";
    case Screen::kPattern: return "pattern";
  }
  return "face";
}

const char* lifeName(Life l) {
  switch (l) {
    case Life::kBlink: return "blink";
    case Life::kGlance: return "glance";
    case Life::kBob: return "bob";
    case Life::kPeek: return "peek";
    case Life::kRumble: return "rumble";
    default: return nullptr;
  }
}

void Behaviour::reset(uint32_t t, Rng& rng) {
  *this = Behaviour{};
  modelT_ = t;
  lastState_ = t;
  nextLife_ = t + lifeGap(rng);
  src_ = sourceAt(t);
}

// ---- Time ------------------------------------------------------------------

bool Behaviour::noApp(uint32_t t) const { return int32_t(t - lastState_) >= int32_t(kNoAppMs); }

int Behaviour::rungAt(uint32_t t) const {
  if (!model_.attn) return 0;
  int32_t d = int32_t(t - attnSince_);
  return 1 + (d >= int32_t(kRung2Ms)) + (d >= int32_t(kRung3Ms));
}

// Tapping stops the nudges, so the lean stops climbing too.
int Behaviour::rung(uint32_t t) const { return rungAt(hushed_ && after(t, hushAt_) ? hushAt_ : t); }

bool Behaviour::momentOn(uint32_t t) const {
  return moment_.anim != render::Anim::kNone && within(t, moment_.at, moment_.ms);
}

uint32_t Behaviour::lifeGap(Rng& rng) const {
  int lo = 2000, hi = 6000;  // blinks every 2–6 s
  if (noApp(modelT_)) lo = 5000, hi = 9000;  // the slow idle loop
  else if (!std::strcmp(model_.base, "working")) lo = model_.busy >= 3 ? 1200 : 2000, hi = model_.busy >= 3 ? 3500 : 5000;
  int scale = 100;
  if (model_.night) scale = scale * 3 / 2;
  if (model_.energy < 70) scale = scale * 13 / 10;
  if (model_.hungry) scale = scale * 13 / 10;  // slower idle
  return uint32_t(rng.range(lo, hi) * scale / 100);
}

void Behaviour::startLife(uint32_t t, Rng& rng) {
  life_ = LifeEvent{};
  Source s = sourceAt(t);
  bool asleep = s.look == render::Look::kAsleep, needs = s.look == render::Look::kNeedsYou;
  if (s.anim == render::Anim::kNone && !asleep) {
    int r = rng.range(0, 99);
    LifeEvent& e = life_;
    e.at = t;
    if (s.look == render::Look::kNoApp || needs || r < 55) {
      e.kind = Life::kBlink, e.ms = 180;
    } else if (s.look == render::Look::kWorking) {
      e.kind = Life::kGlance, e.ms = uint32_t(rng.range(700, 1400));
      e.dx = rng.range(-700, 100), e.dy = rng.range(250, 450);  // at the work
    } else if (model_.hungry && r < 70) {
      e.kind = Life::kRumble, e.ms = render::animDuration(render::Anim::kRumble, 1);
    } else if (r < 80) {
      e.kind = Life::kGlance, e.ms = uint32_t(rng.range(900, 1600));
      int side = rng.range(0, 1) ? 1 : -1;
      if (model_.hungry) {
        e.dx = side * rng.range(100, 250), e.dy = -350;  // a hopeful look up at you
      } else {
        e.dx = side * rng.range(400, 750), e.dy = rng.range(-150, 150);
      }
    } else if (r < 92 && model_.energy >= 80 && !model_.night && !model_.hungry) {
      e.kind = Life::kBob, e.ms = 1100;  // a little hum to itself
    } else {
      e.kind = Life::kPeek, e.ms = 1400, e.dx = rng.range(-300, 300);
    }
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
    resync(t, rng);
    return;
  }
  for (;;) {
    bool found = false;
    uint32_t next = t;
    auto consider = [&](uint32_t c) {
      if (after(c, modelT_) && !after(c, t) && (!found || after(next, c))) next = c, found = true;
    };
    if (moment_.anim != render::Anim::kNone) consider(moment_.at + moment_.ms);
    consider(lastState_ + kNoAppMs);
    if (model_.attn) consider(attnSince_ + kRung2Ms), consider(attnSince_ + kRung3Ms);
    consider(nextLife_);
    if (user_ != Screen::kFace) consider(userAt_ + kUserScreenMs);
    if (!found) break;
    // Everything due at `next`, in a fixed order.
    if (model_.attn && !hushed_ && !model_.focus && !noApp(next)) {
      if (next == attnSince_ + kRung2Ms) sound("chirp", next);
      if (next == attnSince_ + kRung3Ms) sound("pulse", next);  // the buzz, on a board with no motor
    }
    if (user_ != Screen::kFace && next == userAt_ + kUserScreenMs) user_ = Screen::kFace;
    resync(next, rng);
    if (next == nextLife_) startLife(next, rng);
  }
  resync(t, rng);
}

void Behaviour::resync(uint32_t t, Rng& rng) {
  if (moment_.anim != render::Anim::kNone && !within(t, moment_.at, moment_.ms)) {
    // Ended: the blend starts from the moment's last pose, not from later.
    render::Pose last = blended(t);
    bool thinking = moment_.anim == render::Anim::kThinking && moment_.local;
    moment_.anim = render::Anim::kNone;
    if (thinking) {
      play(render::Anim::kShrug, 1, t, true);  // no reply came: "hmm?"
      moment_.local = true;
    }
    Source next = sourceAt(t);
    if (!(next == src_)) blend_.start(t, last), src_ = next;
  }
  Source next = sourceAt(t);
  if (!(next == src_)) {
    blend_.start(t, blended(t));
    src_ = next;
  }
  modelT_ = t;
  (void)rng;
}

// ---- Messages --------------------------------------------------------------

void Behaviour::onState(const Model& m, uint32_t t, Rng& rng) {
  bool wasNoApp = noApp(t);
  bool had = model_.attn;
  bool fresh = m.attn && (!had || std::strncmp(model_.agent, m.agent, sizeof(m.agent)) ||
                          std::strncmp(model_.project, m.project, sizeof(m.project)));
  model_ = m;
  lastState_ = t;
  ledOverride_ = blOverride_ = false;
  if (fresh) {  // a new "needs you" restarts the ladder
    attnSince_ = t;
    hushed_ = false;
    user_ = Screen::kFace;  // attention wins over threads and stats
    if (!m.focus) sound("chirp", t);
    if (momentOn(t) && !overAttention(moment_.anim)) moment_.anim = render::Anim::kNone;
  } else if (had && !m.attn && !momentOn(t)) {
    play(render::Anim::kNod, 1, t, true);  // answered on the Mac: a nod, then back
  }
  if (wasNoApp && heard_ && !momentOn(t)) {  // reconnect: a quick blink
    life_ = LifeEvent{};
    life_.kind = Life::kBlink, life_.at = t, life_.ms = 180;
  }
  heard_ = true;
  resync(t, rng);
}

void Behaviour::onMoment(const MomentIn& in, uint32_t t, Rng& rng) {
  if (in.anim == render::Anim::kNone) return;
  if (model_.attn && !noApp(t) && !overAttention(in.anim)) return;
  int size = clamp(in.size, 1, 3);
  if (in.anim == render::Anim::kCheer) {  // colour changes how, not what
    if (model_.energy < 60) size = clamp(size - 1, 1, 3);
    if (model_.energy >= 140) size = clamp(size + 1, 1, 3);
  }
  play(in.anim, size, t, false);
  bool mumble = in.syllables > 0 && !model_.attn && model_.quiet <= 0 && !model_.focus;
  if (mumble) {
    Moment& mo = moment_;
    std::snprintf(mo.word, sizeof(mo.word), "%s", in.word ? in.word : "");
    mo.say.syllables = in.syllables;
    mo.say.word = mo.word[0] ? mo.word : nullptr;
    mo.say.at = mo.word[0] ? clamp(in.at < 0 ? in.syllables : in.at, 0, in.syllables) : -1;
    mo.sylMs = clamp(int(in.ms), 60, 400);
    mo.speakMs = uint32_t(in.syllables + (mo.word[0] ? 2 : 0)) * mo.sylMs;  // a word is two beats
    if (mo.speakMs + kBubbleReadMs > mo.ms) mo.ms = mo.speakMs + kBubbleReadMs;
  }
  if (in.anim == render::Anim::kCheer && size >= 2 && !model_.focus) sound("jingle", t);
  resync(t, rng);
}

void Behaviour::play(render::Anim a, int size, uint32_t t, bool local) {
  moment_ = Moment{};
  moment_.anim = a;
  moment_.size = size;
  moment_.pace = clamp(model_.pace, 70, 140);
  moment_.at = t;
  moment_.ms = render::animDuration(a, size) * 100 / uint32_t(moment_.pace);
  moment_.local = local;
  life_ = LifeEvent{};
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

void Behaviour::tap(uint32_t t, Rng& rng) {
  user_ = Screen::kFace;
  if (model_.attn && !noApp(t)) {
    if (!hushed_) hushed_ = true, hushAt_ = t;  // nudges stop; it stays amber
    play(render::Anim::kNod, 1, t, true);
  } else {
    play(render::Anim::kWiggle, 1, t, true);
  }
  resync(t, rng);
}

void Behaviour::talkOn(uint32_t t, Rng& rng) {
  user_ = Screen::kFace;
  play(render::Anim::kListening, 1, t, true);
  resync(t, rng);
}

void Behaviour::talkOff(uint32_t t, Rng& rng) {
  play(render::Anim::kThinking, 1, t, true);
  resync(t, rng);
}

// How Boop feels, from the mood, hunger and the time of day (BEHAVIORS §5).
void Behaviour::feel(uint32_t t, Rng& rng) {
  using render::Anim;
  Anim a = Anim::kHappy;
  if (model_.hungry >= 2) a = Anim::kWorried;
  else if (model_.hungry == 1) a = Anim::kCurious;
  else if (model_.night || model_.energy < 60) a = Anim::kSleepy;
  else if (model_.energy >= 140) a = Anim::kLove;
  play(a, 1, t, true);
  resync(t, rng);
}

void Behaviour::toggleFocus(uint32_t t) {
  model_.focus = !model_.focus;  // shown at once; the Mac confirms in the next state
  (void)t;
}

void Behaviour::stripTap(uint32_t t) {
  user_ = user_ == Screen::kFace ? Screen::kThreads : user_ == Screen::kThreads ? Screen::kStats : Screen::kFace;
  userAt_ = t;
}

void Behaviour::contentTap(uint32_t t) {
  user_ = Screen::kFace;
  userAt_ = t;
}

// ---- What shows ------------------------------------------------------------

Screen Behaviour::screen(uint32_t t) const {
  if (noApp(t)) return Screen::kNoApp;
  if (user_ != Screen::kFace) return user_;
  return model_.attn ? Screen::kNeedsYou : Screen::kFace;
}

Behaviour::Source Behaviour::sourceAt(uint32_t t) const {
  Source s;
  if (momentOn(t)) {
    s.anim = moment_.anim, s.at = moment_.at;
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

// The look, coloured by night and hunger, with idle life on top.
render::Pose Behaviour::basePose(const Source& s, uint32_t t) const {
  render::Pose p = render::lookPose(s.look, s.rung, model_.busy);
  if (s.look == render::Look::kNeedsYou) p.raise = 1000;
  if (s.look == render::Look::kIdle || s.look == render::Look::kWorking) {
    if (model_.night) p.lidTop = int16_t(p.lidTop + 180), p.dy = int16_t(p.dy + 2);  // drowsier
    if (model_.hungry >= 2) {  // starving: low energy
      p.lidTop = int16_t(p.lidTop + 250), p.lidTilt = -200, p.dy = int16_t(p.dy + 5), p.mouthCurve = -150;
    }
  }
  if (s.look == render::Look::kAsleep) {  // slow breathing
    p.size = int16_t(p.size + 14 * render::isin(int(t % 4000 * 1024 / 4000)) / 1024);
  }
  if (life_.kind == Life::kNone || !within(t, life_.at, life_.ms)) return p;
  uint32_t lt = t - life_.at;
  render::Pose q = p;
  int env = 0;
  switch (life_.kind) {
    case Life::kBlink:
      q.open = 0;
      env = lt < 90 ? render::ease(int(lt), 90) : 1024 - render::ease(int(lt - 90), 90);
      break;
    case Life::kGlance:
      q.lookX = int16_t(life_.dx), q.lookY = int16_t(life_.dy);
      env = envelope(lt, life_.ms, 150, 150);
      break;
    case Life::kPeek:
      q.lookX = int16_t(life_.dx), q.lookY = -550, q.pupil = 1200, q.mouthOpen = 150, q.mouthWide = 500;
      env = envelope(lt, life_.ms, 150, 150);
      break;
    case Life::kBob:
      q.lidBot = 300, q.mouthCurve = 700;
      q.dy = int16_t(p.dy - 5 * render::isin(int(lt % 550 * 512 / 550)) / 1024);
      env = envelope(lt, life_.ms, 120, 120);
      break;
    case Life::kRumble:
      q = render::animPose(render::Anim::kRumble, 1, lt);
      env = envelope(lt, life_.ms, 120, 150);
      break;
    default: break;
  }
  return render::blend(p, q, env);
}

render::Pose Behaviour::sourcePose(const Source& s, uint32_t t) const {
  if (s.anim == render::Anim::kNone) return basePose(s, t);
  uint32_t lt = t - s.at;
  render::Pose p = render::animPose(s.anim, moment_.size, lt * uint32_t(moment_.pace) / 100);
  if (s.at == moment_.at && (moment_.say.syllables > 0 || model_.attn)) p.raise = 1000;  // room for the bubble
  if (s.at == moment_.at && lt < moment_.speakMs) {  // the mouth follows the syllables
    int phase = int(lt % moment_.sylMs * 512 / moment_.sylMs);
    int open = 150 + 550 * render::isin(phase) / 1024;
    if (open > p.mouthOpen) p.mouthOpen = int16_t(open);
    if (p.mouthWide > 750) p.mouthWide = 750;
  }
  return p;
}

render::Pose Behaviour::pose(uint32_t t) const {
  render::Pose p = blended(t);
  int amt = 0;  // the press squish: feedback on the press itself
  if (pressed_) amt = within(t, pressAt_, kPressEaseMs) ? render::ease(int(t - pressAt_), kPressEaseMs) : 1024;
  else if (within(t, releaseAt_, kPressEaseMs) && releaseAt_) amt = 1024 - render::ease(int(t - releaseAt_), kPressEaseMs);
  if (amt) {
    p.squash = int16_t(p.squash + 200 * amt / 1024);
    p.dy = int16_t(p.dy + 4 * amt / 1024);
  }
  return p;
}

bool Behaviour::moving(uint32_t t) const {
  if (momentOn(t) || blend_.blending(t)) return true;
  if (life_.kind != Life::kNone && within(t, life_.at, life_.ms)) return true;
  if (src_.anim == render::Anim::kNone && src_.look == render::Look::kAsleep) return true;
  if (pressed_ ? within(t, pressAt_, kPressEaseMs) : (releaseAt_ && within(t, releaseAt_, kPressEaseMs))) return true;
  return false;
}

Life Behaviour::life(uint32_t t) const {
  return life_.kind != Life::kNone && within(t, life_.at, life_.ms) ? life_.kind : Life::kNone;
}

uint32_t Behaviour::led(uint32_t t) const {
  if (ledOverride_) return ledSet_;
  if (noApp(t)) return 0;
  if (model_.attn) {
    uint32_t p3 = attnSince_ + kRung3Ms;
    if (!hushed_ && !model_.focus && within(t, p3, 3 * kPulseMs)) {
      return (t - p3) % kPulseMs < kPulseMs / 2 ? kAmber : 0;  // three strong pulses
    }
    return kAmberDim;
  }
  if (momentOn(t) && moment_.anim == render::Anim::kCheer && moment_.size >= 2) return kWarm;
  return 0;
}

uint8_t Behaviour::backlight(uint32_t t) const {
  if (blOverride_) return blSet_;
  if (noApp(t)) return 70;
  if (model_.attn) return 255;  // dimming never hides "needs you"
  if (!std::strcmp(model_.base, "asleep")) return model_.night ? 40 : 60;
  if (model_.night) return 110;
  return 255;
}

render::Strip Behaviour::strip(uint32_t t) const {
  render::Strip s;
  s.wait = model_.wait;
  s.busy = model_.busy;
  s.noApp = noApp(t);
  s.quiet = model_.quiet > 0;
  s.focus = model_.focus;
  return s;
}

const render::Mumble* Behaviour::mumble(uint32_t t) const {
  return momentOn(t) && moment_.say.syllables > 0 ? &moment_.say : nullptr;
}

render::Anim Behaviour::moment(uint32_t t, uint32_t& left) const {
  if (!momentOn(t)) {
    left = 0;
    return render::Anim::kNone;
  }
  left = moment_.at + moment_.ms - t;
  return moment_.anim;
}

bool Behaviour::speaking(uint32_t t) const { return momentOn(t) && within(t, moment_.at, moment_.speakMs); }

}  // namespace app
