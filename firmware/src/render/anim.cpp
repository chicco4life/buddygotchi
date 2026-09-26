#include "render/anim.h"

#include <cstring>

#include "render/raster.h"

namespace render {

namespace {

const char* const kNames[] = {"none", "nod", "cheer", "wiggle", "listening", "thinking", "shrug"};
static_assert(sizeof(kNames) / sizeof(kNames[0]) == size_t(Anim::kCount), "one name per anim");

struct Key {
  uint32_t t;
  Pose p;
};

// Eased keyframes: each segment eases from one key to the next.
template <int N>
Pose keys(uint32_t t, const Key (&k)[N]) {
  if (t <= k[0].t) return k[0].p;
  for (int i = 0; i + 1 < N; ++i) {
    if (t < k[i + 1].t) return blend(k[i].p, k[i + 1].p, ease(int(t - k[i].t), int(k[i + 1].t - k[i].t)));
  }
  return k[N - 1].p;
}

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
// Looking up and away to think. With no pupils to roll up, the whole face
// lifts and the eyes stay round on top: lids would make it the working face
// (hooded, looking down) mirrored.
Pose thinking() {
  Pose p;
  p.lookX = 650, p.lookY = -1000, p.dy = -6, p.squash = 100, p.mouthCurve = -150, p.mouthWide = 600;
  p.mouthX = 8;
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
    case Anim::kNod: return 600;
    case Anim::kCheer: return 2000;  // long enough to notice
    case Anim::kWiggle: return 700;
    case Anim::kListening: return 30000;  // until release; capped
    case Anim::kThinking: return 8000;    // until the reply; capped
    case Anim::kShrug: return 1200;
    default: return 0;
  }
}

Pose animPose(Anim a, uint32_t t) {
  Pose n;  // neutral
  switch (a) {
    case Anim::kNod: {
      Pose up = with(with(n, &Pose::lidBot, 350), &Pose::mouthCurve, 500);
      Pose down = with(with(up, &Pose::dy, 9), &Pose::lidTop, 180);
      const Key k[] = {{0, up}, {150, down}, {330, with(up, &Pose::dy, -2)}, {480, up}};
      return keys(t, k);
    }
    case Anim::kCheer: return cheer(t);
    case Anim::kWiggle: {  // a tap: a happy squint, a smile and a heart
      Pose p = with(with(with(n, &Pose::lidBot, 650), &Pose::mouthCurve, 800), &Pose::heart, 1000);
      // Two slow sways, not a shiver: at 175 ms and 7 px it read as trembling.
      p.dx = int16_t(wave(t, 350, 4));
      p.squash = int16_t(wave(t + 88, 350, 60));
      return p;
    }
    case Anim::kListening: {
      Pose p = listening();
      p.size = int16_t(1000 + wave(t, 1200, 15));
      return p;
    }
    case Anim::kThinking: {
      Pose p = thinking();
      p.lookX = int16_t(650 + wave(t, 2400, 150));
      return p;
    }
    case Anim::kShrug: {
      Pose p = with(with(with(n, &Pose::lidTilt, -500), &Pose::lidTop, 150), &Pose::mouthCurve, -400);
      Pose up = with(with(p, &Pose::dy, -7), &Pose::squash, -120);
      const Key k[] = {{0, p}, {140, up}, {700, up}, {850, p}};
      return keys(t, k);
    }
    default: return n;
  }
}

const char* lookName(Look look) {
  switch (look) {
    case Look::kWorking: return "working";
    case Look::kAsleep: return "asleep";
    case Look::kNoApp: return "no_app";
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
    case Look::kNoApp:  // waiting for the Mac: eyes open, glancing up and aside (gen-2's pre-contact look)
      p.lookX = 350, p.lookY = -300, p.mouthWide = 800;
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
