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

inline void faceTick(uint8_t persona, const char* activity, bool boopActive) {
  uint32_t now = millis();
  static uint32_t nextFrameAt = 0;
  static uint8_t lastPersona = 0xFF;
  static uint32_t nextBlinkAt = 2800;
  static uint32_t blinkUntil = 0;
  static uint32_t nextGlanceAt = 6500;
  static uint32_t glanceUntil = 0;
  static int glanceDir = 1;

  if (persona == lastPersona && (int32_t)(now - nextFrameAt) < 0) return;
  lastPersona = persona;
  nextFrameAt = now + 100;
  FaceEyes e = _faceEyes();

  // Blink / glance scheduling (idle life). Runs off wall time so state
  // changes don't reset the rhythm.
  if ((int32_t)(now - nextBlinkAt) >= 0) {
    blinkUntil = now + 130;
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

  uint16_t accent = buddySpeciesColor();
  const uint16_t PINK = 0xFB56;

  // Slow whole-face bob: life at a glance and continuous sub-pixel-ish
  // motion for the AMOLED. ~6s cycle, ±2px.
  static const int8_t BOB[8] = { 0, 1, 2, 2, 1, 0, -1, -1 };
  int bob = BOB[(now / 750) & 7];

  const int cx = HAL_W / 2;
  int eyeY = 46 + bob;
  int eyeDX = 38;
  int mouthY = 72 + bob;
  int gaze = glancing ? glanceDir * 4 : 0;

  spr.fillSprite(BLACK);

  switch (persona) {
    case 0: {  // sleep — closed lids, drifting z's, slow breath
      int breathe = ((now / 1400) & 1) ? 1 : 0;
      if (boopActive) {
        // Sleep-peek: a boop cracks one eye open to see who's there,
        // then it drifts shut again. The signature move.
        _faceEye(cx - eyeDX, eyeY + breathe, e.w, 4, e.r, accent);
        _faceEye(cx + eyeDX, eyeY + breathe, e.w, e.h - 6, e.r, accent);
      } else {
        _faceEye(cx - eyeDX, eyeY + breathe, e.w, 4, e.r, accent);
        _faceEye(cx + eyeDX, eyeY + breathe, e.w, 4, e.r, accent);
      }
      spr.setTextSize(1);
      spr.setTextColor(accent, BLACK);
      uint32_t ph = now / 600;
      for (int i = 0; i < 3; i++) {
        int step = (int)((ph + i * 2) % 6);
        spr.setCursor(cx + 52 + i * 10 + step, eyeY - 18 - step * 4);
        spr.print(i == 1 ? "Z" : "z");
      }
      break;
    }
    case 2: {  // busy — half-lidded focus, flat mouth, working dots
      int bh = (e.h * 3) / 5;
      _faceEye(cx - eyeDX + gaze, eyeY, e.w, bh, e.r, accent);
      _faceEye(cx + eyeDX + gaze, eyeY, e.w, bh, e.r, accent);
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
      // The tallest species (h=30) grown by +8 and raised by 6 tops out at
      // exactly y=20 — flush under the armed-prompt band (rows 0..19).
      // Keep the -6/+8 pair in sync with the band height if either moves.
      _faceEye(cx - eyeDX, eyeY - 6, e.w + 2, e.h + 8, e.r, accent);
      _faceEye(cx + eyeDX, eyeY - 6, e.w + 2, e.h + 8, e.r, accent);
      spr.fillArc(cx, mouthY, 4, 7, 0, 360, accent);   // small "o"
      break;
    }
    case 4: {  // celebrate — happy arcs, big smile, confetti
      _faceEyeHappy(cx - eyeDX, eyeY, accent);
      _faceEyeHappy(cx + eyeDX, eyeY, accent);
      spr.fillArc(cx, mouthY - 6, 12, 16, 25, 155, accent);
      static const uint16_t CONF[5] = { 0xF800, 0x07E0, 0x001F, 0xFFE0, 0xF81F };
      for (int i = 0; i < 12; i++) {
        uint32_t h = _faceHash(i * 7919u);
        int px = (int)(h % (HAL_W - 1));
        int py = (int)((h / 331 + now / 90) % (HAL_H - HAL_HUD_H - 1));
        spr.fillRect(px, py, 2, 2, CONF[i % 5]);
      }
      break;
    }
    case 5: {  // dizzy — X eyes, wobbly mouth
      int tilt = ((now / 400) & 1) ? 2 : -2;
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
      int h = blinking ? 4 : e.h;
      _faceEye(cx - eyeDX + gaze, eyeY, e.w, h, e.r, accent);
      _faceEye(cx + eyeDX + gaze, eyeY, e.w, h, e.r, accent);
      spr.fillArc(cx, mouthY - 5, 8, 11, 30, 150, accent);
      break;
    }
  }
}
