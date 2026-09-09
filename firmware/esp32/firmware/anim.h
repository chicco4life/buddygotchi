#pragma once
#include <Arduino.h>
#include <math.h>

// Shared motion primitives for the face-first renderer. Doctrine #6 says
// nothing teleports and #10 says physics over keyframes, so every surface
// (face, glance card, mood field, orbs, bubbles) animates through one of
// these two integrators rather than a hand-rolled lerp per file.
//
// Both are frame-rate independent: they take the real dt, so the WS board's
// ~24ms present cadence and the M5's ~16ms loop produce the same motion.

// Damped exponential approach — eases toward the target with no overshoot.
// rate is 1/s: higher = snappier. This is the default for anything that
// should feel settled rather than playful (lids, brightness, gaze).
static const float ANIM_TAU = 6.2831853f;

static inline float animEase(float cur, float target, float rate, float dt) {
  return cur + (target - cur) * (1.0f - expf(-rate * dt));
}

// Round-to-nearest for float -> panel pixel.
static inline int animPx(float v) { return (int)floorf(v + 0.5f); }

// Clamp helper; std::clamp isn't worth an <algorithm> include here.
static inline float animClamp(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

// Clock-sampled arrival with one 6% overshoot; exact endpoints, no integrator
// history, so seeking the frozen clock produces the same motion.
static inline float animPop(float u) {
  u=animClamp(u,0,1);
  const float c=1.283f; // peak overshoot ~= 0.060
  float v=u-1;
  return 1+(c+1)*v*v*v+c*v*v;
}

// One spring arrival followed by an eased return. Call twice for two bounces.
static inline float animBounce(uint32_t age, uint32_t duration) {
  if (age>=duration) return 0;
  float u=(float)age/duration;
  if (u<0.35f) return animPop(u/0.35f);
  float v=(u-0.35f)/0.65f;
  return (1-v)*(1-v);
}

// Critically-under-damped spring. Used where the motion should overshoot
// and settle (cards springing up, squish, head tilt) — the "playful" half
// of doctrine #6.
//
// zeta is the damping ratio: overshoot = exp(-pi*zeta/sqrt(1-zeta^2)).
//   0.65 -> ~7% overshoot   (the spec's "overshoot ~6%" card motion)
//   1.0  -> critical, no overshoot
// Settling time is roughly 4/(zeta*omega), so freqHz ~4 with zeta 0.65
// lands the ~250ms settle the spec asks for.
struct AnimSpring {
  float pos = 0.0f;
  float vel = 0.0f;

  void step(float target, float freqHz, float zeta, float dt) {
    // Clamp dt the same way faceTick does: a long stall (screenshot dump,
    // OTA chunk) must not launch the spring across the screen.
    if (dt <= 0.0f || dt > 0.05f) dt = 0.016f;
    float omega = ANIM_TAU * freqHz;
    // Sub-step so the integrator stays accurate at the board's ~24ms
    // present cadence. Explicit Euler on a 4Hz spring at 24ms has
    // omega*dt ~= 0.6, which overshoots far past the analytic response —
    // measured on hardware as a card that flew a quarter-screen too high
    // before settling. Capping omega*h at ~0.15 keeps the overshoot at the
    // zeta the caller actually asked for.
    int steps = (int)(omega * dt / 0.15f) + 1;
    if (steps > 16) steps = 16;
    float h = dt / (float)steps;
    for (int i = 0; i < steps; i++) {
      float accel = omega * omega * (target - pos) - 2.0f * zeta * omega * vel;
      vel += accel * h;
      pos += vel * h;
    }
  }

// Small deterministic hash. Every surface that wants organic-feeling
// variation uses this rather than rand(), so HIL screenshots of the same
// millisecond are always identical.
static inline uint32_t animHash(uint32_t x) {
  x *= 2654435761u;
  return x ^ (x >> 16);
}

  // Retract to rest without bouncing. Springing out and easing back is the
  // product's motion rule — a card arriving is playful, a card leaving
  // should just go — and it was written out longhand at three call sites
  // before living here.
  void retract(float rate, float dt, float eps = 0.004f) {
    pos = animEase(pos, 0.0f, rate, dt);
    vel = 0.0f;
    if (pos < eps) pos = 0.0f;
  }
};

// Small deterministic hash. Every surface that wants organic-feeling
// variation uses this rather than rand(), so HIL screenshots of the same
// millisecond are always identical.
static inline uint32_t animHash(uint32_t x) {
  x *= 2654435761u;
  return x ^ (x >> 16);
}

// Channel-wise RGB565 blend, t in 0..1. Lives here rather than in mood.h
// because it knows nothing about moods — six files reach for it.
static inline uint16_t animMix(uint16_t a, uint16_t b, float t) {
  t = animClamp(t, 0.0f, 1.0f);
  int ar = (a >> 11) & 0x1F, ag = (a >> 5) & 0x3F, ab = a & 0x1F;
  int br = (b >> 11) & 0x1F, bg = (b >> 5) & 0x3F, bb = b & 0x1F;
  int r = ar + (int)((br - ar) * t + 0.5f);
  int g = ag + (int)((bg - ag) * t + 0.5f);
  int bl = ab + (int)((bb - ab) * t + 0.5f);
  return (uint16_t)((r << 11) | (g << 5) | bl);
}

// 0..1 breath. Doctrine #8 says everything breathes, and every surface was
// spelling out the same sin() by hand.
static inline float animPulse01(uint32_t now, float periodMs) {
  return 0.5f + 0.5f * sinf((float)now * (ANIM_TAU / periodMs));
}

// RGB565 from 8-bit components. The sprite quantizes to RGB332 on the WS
// board (blue keeps only 4 levels), so prefer values that already sit on
// the RGB332 lattice — R/G in {0,36,73,109,146,182,219,255} and B in
// {0,82,173,255} — when an exact tone matters.
static inline uint16_t animRGB(uint8_t r, uint8_t g, uint8_t b) {
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}
