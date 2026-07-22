#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "buddy.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp).
//
// Face-first renderer for the landscape board: the screen IS the
// character's face — big glowing eyes and a mouth on pure black (black
// pixels are off on the AMOLED, which is both the product look and the
// burn-in strategy). Species differ by accent color (their procedural
// bodyColor); the ASCII body art stays the M5/portrait renderer.
//
// faceTick(persona) uses the same 0..6 persona indices as the Species
// state table: 0=sleep 1=idle 2=busy 3=attention 4=celebrate 5=dizzy
// 6=heart. It redraws the whole sprite at ~10fps (or on state change);
// the HUD/band overlays draw after it every loop.

extern BuddyCanvas spr;

// Small deterministic hash for organic-feeling timing without rand()
// (keeps behavior reproducible in HIL screenshots).
static inline uint32_t _faceHash(uint32_t x) {
  x *= 2654435761u;
  return x ^ (x >> 16);
}

// Per-species eye geometry — the accent color plus these shapes are what
// make each character read as itself on the face board. Indexed by
// buddySpeciesIdx(); MUST stay in SPECIES_TABLE registry order
// (buddy.cpp): capybara, duck, goose, blob, cat, dragon, octopus, owl,
// penguin, turtle, snail, ghost, axolotl, cactus, robot, rabbit,
// mushroom, chonk.
struct FaceEyes { uint8_t w, h, r; };
static const FaceEyes FACE_EYES[] = {
  { 24, 18,  6 },   // capybara — chill half-lids
  { 22, 26,  8 },   // duck — round and eager
  { 18, 30,  7 },   // goose — tall and alert
  { 24, 28,  9 },   // blob — big and soft
  { 16, 28,  8 },   // cat — vertical almonds
  { 22, 22,  4 },   // dragon — fierce squint
  { 22, 26, 11 },   // octopus — very round
  { 28, 30, 13 },   // owl — enormous
  { 18, 22,  9 },   // penguin — small and neat
  { 22, 16,  6 },   // turtle — sleepy
  { 16, 20,  8 },   // snail — small, high
  { 20, 26, 10 },   // ghost — hollow ovals
  { 22, 24, 10 },   // axolotl — happy rounds
  { 14, 18,  6 },   // cactus — tiny
  { 22, 22,  2 },   // robot — square
  { 16, 28,  7 },   // rabbit — tall
  { 12, 16,  6 },   // mushroom — dots
  { 28, 18,  8 },   // chonk — wide and squished
};
static const uint8_t FACE_EYES_N = sizeof(FACE_EYES) / sizeof(FACE_EYES[0]);

static FaceEyes _faceEyes() {
  uint8_t i = buddySpeciesIdx();
  if (i >= FACE_EYES_N) return FaceEyes{ 22, 26, 8 };
  return FACE_EYES[i];
}

static void _faceEye(int cx, int cy, int w, int h, int r, uint16_t c) {
  if (h <= 5) {
    spr.fillRoundRect(cx - w / 2, cy - 2, w, 4, 2, c);   // closed lid
  } else {
    if (r > h / 2) r = h / 2;
    if (r > w / 2) r = w / 2;
    spr.fillRoundRect(cx - w / 2, cy - h / 2, w, h, r, c);
  }
}

static void _faceEyeHappy(int cx, int cy, uint16_t c) {
  spr.fillArc(cx, cy + 5, 8, 11, 180, 360, c);           // ∩ arc
}

static void _faceEyeX(int cx, int cy, uint16_t c) {
  for (int t = -1; t <= 1; t++) {
    spr.drawLine(cx - 7, cy - 7 + t, cx + 7, cy + 7 + t, c);
    spr.drawLine(cx - 7, cy + 7 + t, cx + 7, cy - 7 + t, c);
  }
}

static void _faceEyeHeart(int cx, int cy, uint16_t c) {
  spr.fillCircle(cx - 5, cy - 3, 6, c);
  spr.fillCircle(cx + 5, cy - 3, 6, c);
  spr.fillTriangle(cx - 10, cy, cx + 10, cy, cx, cy + 11, c);
}

// Map the wire activity kind to the verb the busy face wears.
static const char* _faceActivityVerb(const char* activity) {
  if (!activity || !activity[0]) return "working";
  if (strcmp(activity, "verify") == 0) return "testing";
  if (strcmp(activity, "read") == 0)   return "reading";
  if (strcmp(activity, "write") == 0)  return "writing";
  if (strcmp(activity, "shell") == 0)  return "running";
  if (strcmp(activity, "web") == 0)    return "browsing";
  return "working";
}

// Damped exponential approach — eases toward the target with no
// overshoot, matching the product's "physical, never bouncy" motion
// language. rate is 1/s: higher = snappier.
static float _easeToward(float cur, float target, float rate, float dt) {
  return cur + (target - cur) * (1.0f - expf(-rate * dt));
}

static int _px(float v) { return (int)floorf(v + 0.5f); }

inline void faceTick(uint8_t persona, const char* activity, bool boopActive) {
  uint32_t now = millis();
  static uint32_t lastMs = 0;
  static uint32_t nextBlinkAt = 2800;
  static uint32_t blinkUntil = 0;
  static uint32_t nextGlanceAt = 6500;
  static uint32_t glanceUntil = 0;
  static int glanceDir = 1;
  // Eased face parameters — updated every frame, drawn every frame. The
  // present throttle in halPresent decides what reaches glass.
  static float lidL = 1.0f, lidR = 1.0f;   // eye openness, 1 = full state height
  static float lift = 0.0f;                // eye raise px (attention looks up)
  static float boost = 0.0f;               // extra eye height px (attention pop)
  static float gaze = 0.0f;                // horizontal glance px

  float dt = (now - lastMs) / 1000.0f;
  lastMs = now;
  if (dt <= 0.0f || dt > 0.05f) dt = 0.016f;   // first frame / hiccup clamp

  FaceEyes e = _faceEyes();

  // Blink / glance scheduling (idle life). Runs off wall time so state
  // changes don't reset the rhythm.
  if ((int32_t)(now - nextBlinkAt) >= 0) {
    blinkUntil = now + 140;
    uint32_t h = _faceHash(now);
    nextBlinkAt = now + 2600 + (h % 2200);
    if ((h & 7) == 0) nextBlinkAt = now + 420;   // occasional double-blink
  }
  if ((int32_t)(now - nextGlanceAt) >= 0) {
    glanceUntil = now + 900;
    glanceDir = (_faceHash(now) & 1) ? 1 : -1;
    nextGlanceAt = now + 5500 + (_faceHash(now ^ 0x9E37) % 4500);
  }
  bool blinking = (int32_t)(blinkUntil - now) > 0;
  bool glancing = (int32_t)(glanceUntil - now) > 0;

  // Per-state targets; easing morphs between them (state changes glide
  // in over ~100-200ms instead of popping).
  float lidTargetL = 1.0f, lidTargetR = 1.0f;
  float liftTarget = 0.0f, boostTarget = 0.0f;
  switch (persona) {
    case 0:   // sleep (peek: a boop cracks the right eye open)
      lidTargetL = 0.10f;
      lidTargetR = boopActive ? 0.75f : 0.10f;
      break;
    case 2: lidTargetL = lidTargetR = 0.62f; break;             // busy focus
    case 3: liftTarget = -6.0f; boostTarget = 8.0f; break;      // attention
    default: break;
  }
  if (blinking && (persona == 1 || persona == 2)) lidTargetL = lidTargetR = 0.08f;
  float gazeTarget = (glancing && (persona == 1 || persona == 2)) ? glanceDir * 4.0f : 0.0f;

  // Lids close fast, open slower — the asymmetry is what reads as alive.
  lidL = _easeToward(lidL, lidTargetL, lidTargetL < lidL ? 26.0f : 11.0f, dt);
  lidR = _easeToward(lidR, lidTargetR, lidTargetR < lidR ? 26.0f : 11.0f, dt);
  lift = _easeToward(lift, liftTarget, 14.0f, dt);
  boost = _easeToward(boost, boostTarget, 18.0f, dt);
  gaze = _easeToward(gaze, gazeTarget, 8.0f, dt);

  uint16_t accent = buddySpeciesColor();
  const uint16_t PINK = 0xFB56;

  // Slow continuous whole-face bob: life at a glance plus constant
  // micro-motion for the AMOLED. Sleep breathes slower and deeper.
  float bobF = (persona == 0)
      ? 2.5f * sinf((float)now * (6.2832f / 4500.0f))
      : 2.0f * sinf((float)now * (6.2832f / 6000.0f));
  int bob = _px(bobF);

  const int cx = HAL_W / 2;
  int eyeY = 46 + bob + _px(lift);
  int eyeDX = 38;
  int mouthY = 72 + bob;
  int gazeI = _px(gaze);
  int eyeHL = _px(e.h * lidL + boost);
  int eyeHR = _px(e.h * lidR + boost);
  int eyeW = _px(e.w + (boost > 1.0f ? 2.0f : 0.0f));

  spr.fillSprite(BLACK);

  switch (persona) {
    case 0: {  // sleep — lids (peek eased via lidR), drifting z's
      _faceEye(cx - eyeDX, eyeY, e.w, eyeHL, e.r, accent);
      _faceEye(cx + eyeDX, eyeY, e.w, eyeHR, e.r, accent);
      spr.setTextSize(1);
      spr.setTextColor(accent, BLACK);
      for (int i = 0; i < 3; i++) {
        float ph = fmodf((float)now / 600.0f + i * 2.0f, 6.0f);
        spr.setCursor(cx + 52 + i * 10 + _px(ph), eyeY - 18 - _px(ph * 4.0f));
        spr.print(i == 1 ? "Z" : "z");
      }
      break;
    }
    case 2: {  // busy — half-lidded focus, flat mouth, working dots
      _faceEye(cx - eyeDX + gazeI, eyeY, eyeW, eyeHL, e.r, accent);
      _faceEye(cx + eyeDX + gazeI, eyeY, eyeW, eyeHR, e.r, accent);
      spr.fillRect(cx - 8, mouthY, 16, 3, accent);
      int active = (now / 350) % 3;
      for (int i = 0; i < 3; i++) {
        uint16_t c = (i == active) ? accent : (uint16_t)((accent >> 2) & 0x39E7);
        spr.fillCircle(cx + 20 + i * 9, mouthY + 2, 2, c);
      }
      // What the agent is actually doing, small and dim above the eyes —
      // the `activity` wire field finally rendered somewhere.
      spr.setTextSize(1);
      spr.setTextDatum(TC_DATUM);
      spr.setTextColor((uint16_t)((accent >> 1) & 0x7BEF), BLACK);
      spr.drawString(_faceActivityVerb(activity), cx, 12);
      spr.setTextDatum(TL_DATUM);
      break;
    }
    case 3: {  // attention — wide eyes raised toward the boop button
      // The tallest species (h=30) with the full +8 boost and -6 lift
      // tops out at exactly y=20 — flush under the armed-prompt band
      // (rows 0..19). Keep the lift/boost targets in sync with the band
      // height if either moves.
      _faceEye(cx - eyeDX, eyeY, eyeW, eyeHL, e.r, accent);
      _faceEye(cx + eyeDX, eyeY, eyeW, eyeHR, e.r, accent);
      spr.fillArc(cx, mouthY, 4, 7, 0, 360, accent);   // small "o"
      break;
    }
    case 4: {  // celebrate — happy arcs, big smile, falling confetti
      _faceEyeHappy(cx - eyeDX, eyeY, accent);
      _faceEyeHappy(cx + eyeDX, eyeY, accent);
      spr.fillArc(cx, mouthY - 6, 12, 16, 25, 155, accent);
      static const uint16_t CONF[5] = { 0xF800, 0x07E0, 0x001F, 0xFFE0, 0xF81F };
      for (int i = 0; i < 12; i++) {
        uint32_t h = _faceHash(i * 7919u);
        // Per-particle fall speed (60-110 px/s) so the rain has depth.
        float speed = 0.060f + (h % 50) * 0.001f;
        int px = (int)(h % (HAL_W - 1));
        int py = _px(fmodf(h / 331.0f + (float)now * speed, (float)(HAL_H - HAL_HUD_H - 1)));
        spr.fillRect(px, py, 2, 2, CONF[i % 5]);
      }
      break;
    }
    case 5: {  // dizzy — X eyes, continuous wobble
      int tilt = _px(2.5f * sinf((float)now * (6.2832f / 800.0f)));
      _faceEyeX(cx - eyeDX, eyeY + tilt, accent);
      _faceEyeX(cx + eyeDX, eyeY - tilt, accent);
      for (int i = 0; i < 4; i++) {
        spr.fillRect(cx - 12 + i * 6, mouthY + ((i & 1) ? 2 : 0), 6, 2, accent);
      }
      break;
    }
    case 6: {  // heart — heart eyes, blush, smile
      _faceEyeHeart(cx - eyeDX, eyeY, PINK);
      _faceEyeHeart(cx + eyeDX, eyeY, PINK);
      spr.fillArc(cx, mouthY - 5, 10, 13, 25, 155, accent);
      spr.fillRoundRect(cx - eyeDX - 22, eyeY + 16, 13, 5, 2, PINK);
      spr.fillRoundRect(cx + eyeDX + 9, eyeY + 16, 13, 5, 2, PINK);
      break;
    }
    default: {  // idle — open eyes, blinks, glances, soft smile
      _faceEye(cx - eyeDX + gazeI, eyeY, eyeW, eyeHL, e.r, accent);
      _faceEye(cx + eyeDX + gazeI, eyeY, eyeW, eyeHR, e.r, accent);
      spr.fillArc(cx, mouthY - 5, 8, 11, 30, 150, accent);
      break;
    }
  }
}
