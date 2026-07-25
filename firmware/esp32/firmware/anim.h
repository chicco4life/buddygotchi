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
static inline float animEase(float cur, float target, float rate, float dt) {
  return cur + (target - cur) * (1.0f - expf(-rate * dt));
}

// Round-to-nearest for float -> panel pixel.
static inline int animPx(float v) { return (int)floorf(v + 0.5f); }

// Clamp helper; std::clamp isn't worth an <algorithm> include here.
static inline float animClamp(float v, float lo, float hi) {
  return v < lo ? lo : (v > hi ? hi : v);
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

  void reset(float p) { pos = p; vel = 0.0f; }

  void step(float target, float freqHz, float zeta, float dt) {
    // Clamp dt the same way faceTick does: a long stall (screenshot dump,
    // OTA chunk) must not launch the spring across the screen.
    if (dt <= 0.0f || dt > 0.05f) dt = 0.016f;
    float omega = 6.2831853f * freqHz;
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

  // True once the spring has effectively arrived — lets callers skip work
  // for an off-screen surface instead of simulating it forever.
  bool settled(float target, float eps = 0.002f) const {
    return fabsf(pos - target) < eps && fabsf(vel) < eps * 20.0f;
  }
};

// RGB565 from 8-bit components. The sprite quantizes to RGB332 on the WS
// board (blue keeps only 4 levels), so prefer values that already sit on
// the RGB332 lattice — R/G in {0,36,73,109,146,182,219,255} and B in
// {0,82,173,255} — when an exact tone matters.
static inline uint16_t animRGB(uint8_t r, uint8_t g, uint8_t b) {
  return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}
