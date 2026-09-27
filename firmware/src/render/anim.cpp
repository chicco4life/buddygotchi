#include "render/anim.h"

#include <cstring>

#include "render/raster.h"

namespace render {

namespace {

const char* const kNames[] = {"none", "cheer", "wiggle"};
static_assert(sizeof(kNames) / sizeof(kNames[0]) == size_t(Anim::kCount), "one name per anim");

// A side-to-side wave of `period` ms.
int wave(uint32_t t, uint32_t period, int amp) { return amp * isin(int(t % period * 1024 / period)) / 1024; }

// The expressions. Each is the neutral pose with a few fields changed.
Pose happy() {  // boxy eyes squinting from the bottom, and a small "u" smile
  Pose p;
  p.lidBot = 700, p.mouthCurve = 900;
  return p;
}
Pose with(Pose p, int16_t Pose::*field, int value) {
  p.*field = int16_t(value);
  return p;
}

// Three hops, then the happy squint, a small open smile and a beating heart
// until the end (BEHAVIORS.md §5).
Pose cheer(uint32_t t) {
  const int hops = 3;
  const uint32_t period = 380, land = 30;
  const uint32_t beat = 430, thumpAt = 230, thump = 100;  // the heart, once landed
  Pose p = happy();
  p.mouthOpen = 650, p.heart = 1000;
  if (t < hops * period + land) {
    uint32_t in = t % period;
    if (in < land || in >= period - land) {  // on the ground: squashed wide for 60 ms around each landing
      p.squash = 260;
    } else {  // in the air: stretched with the speed, so round at the top
      int turn = int(in * 512 / period);
      int speed = isin(turn + 256);
      p.dy = int16_t(-14 * isin(turn) / 1024);
      p.squash = int16_t(-140 * (speed < 0 ? -speed : speed) / 1024);
    }
  } else {
    uint32_t b = (t - hops * period - land) % beat;
    if (b >= thumpAt && b < thumpAt + thump) p.heart = 600;  // the heart beats: small for a moment
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

Pose lookPose(Look look) {
  Pose p;
  switch (look) {
    case Look::kIdle:  // gen-2's resting face: open eyes and a short flat mouth
      break;
    case Look::kWorking:
      p.lidTop = 180, p.lookX = -250, p.lookY = 350, p.mouthWide = 700;
      break;
    case Look::kAsleep:
      p.open = 0, p.dy = 10, p.mouthWide = 600;
      break;
    case Look::kNeedsYou:  // turned to you and leaning in
      p.eyeSize = 1080, p.lookY = -100, p.mouthWide = 550;
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
