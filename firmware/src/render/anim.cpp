#include "render/anim.h"

#include <cstring>

#include "render/raster.h"

namespace render {

namespace {

const char* const kNames[] = {
    "none",     "nod",   "cheer",   "oops",   "side_eye", "wiggle",  "listening",
    "thinking", "shrug", "zip",     "gobble", "rumble",   "levelup", "happy",
    "proud",    "smug",  "curious", "sleepy", "worried",  "sulky",   "love",
};
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
Pose happy() {  // gen-2's "^ ^" and a closed "u" smile
  Pose p;
  p.lidBot = 700, p.mouthCurve = 900;
  return p;
}
Pose proud() {
  Pose p;
  p.lidTop = 250, p.lidBot = 550, p.lookY = -350, p.mouthCurve = 800, p.dy = -4, p.size = 1030;
  return p;
}
Pose smug() {
  Pose p;
  p.lidTop = 420, p.wink = 180, p.lookX = 350, p.mouthCurve = 500, p.mouthWide = 700, p.mouthX = 7;
  return p;
}
Pose curious() {
  Pose p;
  p.eyeSize = 1080, p.lookX = 450, p.lookY = -250, p.wink = -250, p.mouthOpen = 250, p.mouthWide = 450;
  p.size = 1030;
  return p;
}
Pose sleepy() {
  Pose p;
  p.open = 380, p.lidTilt = -250, p.lookY = 350, p.mouthWide = 600, p.dy = 4;
  return p;
}
Pose worried() {
  Pose p;
  p.lidTilt = -650, p.lidTop = 250, p.eyeSize = 950, p.lookY = 200, p.mouthCurve = -600, p.mouthWide = 700;
  return p;
}
Pose sulky() {
  Pose p;
  p.lidTop = 450, p.lidTilt = 450, p.lookY = 450, p.lookX = -400, p.mouthCurve = -500, p.mouthWide = 650;
  return p;
}
Pose love() {
  Pose p;
  p.glow = 1000, p.lidBot = 650, p.eyeSize = 1060, p.mouthCurve = 900, p.mouthOpen = 250, p.size = 1040;
  p.heart = 1000;
  return p;
}
Pose sideEye() {
  Pose p;
  p.lookX = 900, p.lidTop = 480, p.lidTilt = 200, p.mouthCurve = -300, p.mouthWide = 700, p.mouthX = 6;
  return p;
}
Pose startled() {
  Pose p;
  p.squash = -150, p.eyeSize = 1120, p.mouthOpen = 400, p.mouthWide = 500, p.mouthCurve = -300, p.oops = 750;
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

Pose cheer(int size, uint32_t t) {
  int hops = size + 1;
  const uint32_t period = 380;
  Pose p = happy();
  p.mouthOpen = int16_t(350 + 150 * size);
  p.glow = int16_t(size >= 2 ? 1000 : 450);
  p.heart = int16_t(size >= 2 ? 1000 : 0);  // a big cheer is fond; a small one isn't
  if (t < hops * period) {
    int h = hop(t, period, 1024);
    p.dy = int16_t(-(4 + 5 * size) * h / 1024);
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

uint32_t animDuration(Anim a, int size) {
  if (size < 1) size = 1;
  if (size > 3) size = 3;
  switch (a) {
    case Anim::kNone: return 0;
    case Anim::kNod: return 600;
    case Anim::kCheer: return 2000 + (size - 1) * 400;  // long enough to notice
    case Anim::kOops: return 1400;
    case Anim::kSideEye: return 1600;
    case Anim::kWiggle: return 700;
    case Anim::kListening: return 30000;  // until release; capped
    case Anim::kThinking: return 8000;    // until the reply; capped
    case Anim::kShrug: return 1200;
    case Anim::kZip: return 1500;
    case Anim::kGobble: return 1500;
    case Anim::kRumble: return 1500;
    case Anim::kLevelup: return 2400;
    default: return 2500;  // the faces the brain picks
  }
}

Pose animPose(Anim a, int size, uint32_t t) {
  if (size < 1) size = 1;
  if (size > 3) size = 3;
  Pose n;  // neutral
  switch (a) {
    case Anim::kNone: return n;
    case Anim::kNod: {
      Pose up = with(with(n, &Pose::lidBot, 350), &Pose::mouthCurve, 500);
      Pose down = with(with(up, &Pose::dy, 9), &Pose::lidTop, 180);
      const Key k[] = {{0, up}, {150, down}, {330, with(up, &Pose::dy, -2)}, {480, up}};
      return keys(t, k);
    }
    case Anim::kCheer: return cheer(size, t);
    case Anim::kOops: {
      Pose p = startled();
      if (t < 500) p.dx = int16_t(wave(t, 125, 4));
      Pose after = with(with(with(p, &Pose::lidTop, 300), &Pose::mouthCurve, -600), &Pose::mouthOpen, 0);
      after.oops = 600, after.squash = 0, after.eyeSize = 940, after.dx = 0;
      const Key k[] = {{0, p}, {800, p}, {950, after}};
      return keys(t, k);
    }
    case Anim::kSideEye: return sideEye();
    case Anim::kWiggle: {  // a tap: "^ ^" eyes, a smile and a heart
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
    case Anim::kZip: {
      Pose p = with(with(with(n, &Pose::lidTop, 350), &Pose::lidTilt, 300), &Pose::lookX, -300);
      Pose shut = with(p, &Pose::mouthWide, 400);
      const Key k[] = {{0, with(p, &Pose::mouthWide, 800)}, {150, with(p, &Pose::mouthWide, 800)}, {300, shut}};
      return keys(t, k);
    }
    case Anim::kGobble: {
      Pose p = happy();
      p.glow = 500;
      if (t < 1200) p.mouthOpen = int16_t(900 * hop(t, 300, 1024) / 1024);
      return p;
    }
    case Anim::kRumble: {
      Pose p = worried();
      p.lookY = 700;
      if (t >= 300 && t < 1000) p.dx = int16_t(wave(t, 80, 2)), p.squash = int16_t(wave(t, 160, 60));
      return p;
    }
    case Anim::kLevelup: {
      Pose crouch = with(with(happy(), &Pose::squash, 250), &Pose::dy, 6);
      Pose jump = happy();
      jump.squash = -300, jump.dy = -18, jump.glow = 1000;
      Pose glad = with(with(happy(), &Pose::glow, 1000), &Pose::heart, 1000);
      if (t >= 1100) {
        glad.dy = int16_t(t < 1100 + 2 * 380 ? -hop(t - 1100, 380, 6) : 0);
        return glad;
      }
      const Key k[] = {{0, crouch}, {300, crouch}, {420, jump}, {700, jump}, {850, with(glad, &Pose::squash, 150)},
                       {1000, glad}};
      return keys(t, k);
    }
    case Anim::kHappy: return happy();
    case Anim::kProud: return proud();
    case Anim::kSmug: return smug();
    case Anim::kCurious: return curious();
    case Anim::kSleepy: return sleepy();
    case Anim::kWorried: return worried();
    case Anim::kSulky: return sulky();
    case Anim::kLove: {
      Pose p = love();
      p.size = int16_t(1040 + hop(t, 700, 25));
      return p;
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

Pose lookPose(Look look, int rung, int busy) {
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
    case Look::kNeedsYou:
      if (rung < 1) rung = 1;
      if (rung > 3) rung = 3;
      p.eyeSize = 1080, p.lookY = -100, p.mouthOpen = 200, p.mouthWide = 550;
      p.size = int16_t(1000 + 60 * rung);
      p.dy = int16_t(2 * rung);
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
