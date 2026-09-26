#include "render/anim.h"

#include <cstring>

#include "render/raster.h"

namespace render {

namespace {

const char* const kNames[] = {"none", "cheer", "wiggle", "listening"};
static_assert(sizeof(kNames) / sizeof(kNames[0]) == size_t(Anim::kCount), "one name per anim");

// |sin| bounces: `period` ms per hop, peaking at `amp`.
int hop(uint32_t t, uint32_t period, int amp) {
  int s = isin(int(t % period * 512 / period));
  return amp * s / 1024;
}
// A side-to-side wave of `period` ms.
int wave(uint32_t t, uint32_t period, int amp) { return amp * isin(int(t % period * 1024 / period)) / 1024; }

// The expressions. Each is the neutral pose with a few fields changed.
Pose happy() {  // boxy eyes squinting from the bottom, and a small "u" smile
  Pose p;
  p.lidBot = 700, p.mouthCurve = 900;
  return p;
}
Pose listening() {
  Pose p;
  p.eyeSize = 1080, p.lookY = -250, p.wink = -150, p.mouthOpen = 250, p.mouthWide = 500;
  return p;
}
Pose with(Pose p, int16_t Pose::*field, int value) {
  p.*field = int16_t(value);
  return p;
}

// Three hops, then the happy squint, a small open smile and the heart held
// until the end (BEHAVIORS.md §5).
Pose cheer(uint32_t t) {
  const int hops = 3;
  const uint32_t period = 380;
  Pose p = happy();
  p.mouthOpen = 650, p.heart = 1000;
  if (t < hops * period) {
    int h = hop(t, period, 1024);
    p.dy = int16_t(-14 * h / 1024);
    p.squash = int16_t(220 - 380 * h / 1024);  // squashed on landing, stretched in the air
  }
  return p;
}

}  // namespace

Anim animFromName(const char* name) {
  if (!name) return Anim::kNone;
  for (int i = 1; i < int(Anim::kCount); ++i) {
    if (!std::strcmp(name, kNames[i])) return Anim(i);
  }
  return Anim::kNone;
}

const char* animName(Anim a) { return kNames[int(a) < int(Anim::kCount) ? int(a) : 0]; }

uint32_t animDuration(Anim a) {
  switch (a) {
    case Anim::kCheer: return 2000;  // long enough to notice
    case Anim::kWiggle: return 700;
    case Anim::kListening: return 30000;  // while held, capped; then the reply wait (Behaviour)
    default: return 0;
  }
}

Pose animPose(Anim a, uint32_t t) {
  Pose n;  // neutral
  switch (a) {
    case Anim::kCheer: return cheer(t);
    case Anim::kWiggle: {  // a tap: a happy squint, a smile and a heart
      Pose p = with(with(with(n, &Pose::lidBot, 650), &Pose::mouthCurve, 800), &Pose::heart, 1000);
      // Two slow sways, not a shiver: at 175 ms and 7 px it read as trembling.
      p.dx = int16_t(wave(t, 350, 4));
      p.squash = int16_t(wave(t + 88, 350, 60));
      return p;
    }
    case Anim::kListening: {  // all ears, bobbing gently
      Pose p = listening();
      p.dy = bob(t, 1200);
      return p;
    }
    default: return n;
  }
}

const char* lookName(Look look) {
  switch (look) {
    case Look::kWorking: return "working";
    case Look::kAsleep: return "asleep";
    case Look::kNeedsYou: return "needs_you";
    default: return "idle";
  }
}

Pose lookPose(Look look, int busy) {
  Pose p;
  switch (look) {
    case Look::kIdle:  // gen-2's resting face: open eyes and a short flat mouth
      break;
    case Look::kWorking:
      p.lidTop = 180, p.lookX = -250, p.lookY = 350, p.mouthWide = 700;
      p.eyeSize = int16_t(busy >= 3 ? 950 : 1000);  // busier, more focused
      break;
    case Look::kAsleep:
      p.open = 0, p.dy = 10, p.mouthWide = 600;
      break;
    case Look::kNeedsYou:  // turned to you and leaning in
      p.eyeSize = 1080, p.lookY = -100, p.mouthOpen = 200, p.mouthWide = 550;
      p.size = 1060, p.dy = 2;
      break;
  }
  return p;
}

Pose Blend::apply(uint32_t now, const Pose& target) const {
  if (!blending(now)) return target;
  int32_t t = int32_t(now - at_);
  if (t < 0) t = 0;
  return blend(from_, target, ease(int(t), int(kBlendMs)));
}

}  // namespace render
