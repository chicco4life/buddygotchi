#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "mood.h"
#include "buddy.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h and buddy.h.
//
// Rituals (PEBBLE-UX §13) — the two moments that aren't states.
//
//   HATCHING       first-ever boot, once per device (NVS one-shot). Egg on
//                  black, rocking, cracks, burst, a blinking newborn face,
//                  then it settles into normal presence. ~6s, skippable by
//                  any button. This is the unboxing moment; it has to feel
//                  hand-finished, which is why it's a scripted sequence
//                  rather than a state the reducer can wander into.
//
//   MORNING STRETCH first link-up after a long absence. Stretch, yawn,
//                  settle. ~2s. There is no RTC on this board, so "long"
//                  is measured from the heartbeat's time sync while linked;
//                  after a reboot that history is gone, and a fresh boot
//                  feels like waking up anyway, so the stretch shows.
//
// Both drive the face through FaceOpts rather than drawing their own faces,
// so a ritual can't drift out of sync with what the buddy looks like.

enum RitualKind : uint8_t { RITUAL_NONE = 0, RITUAL_HATCH, RITUAL_STRETCH };

static const uint32_t HATCH_MS   = 6000;
static const uint32_t STRETCH_MS = 2000;

static RitualKind _ritual = RITUAL_NONE;
static uint32_t   _ritualStart = 0;

inline bool ritualActive() { return _ritual != RITUAL_NONE; }
inline bool ritualIsHatch() { return _ritual == RITUAL_HATCH; }
inline const char* ritualName() {
  return _ritual == RITUAL_HATCH ? "hatch"
       : _ritual == RITUAL_STRETCH ? "stretch" : "none";
}

inline void ritualStart(RitualKind k, uint32_t now) {
  if (_ritual == k) return;
  _ritual = k;
  _ritualStart = now;
  Serial.printf("<<RITUAL %s>>\n", ritualName());
}

// Any button skips. A ritual is a gift, not a toll — someone who has seen
// it (or is in a hurry) must always be able to get past it.
inline void ritualSkip() {
  if (_ritual == RITUAL_NONE) return;
  Serial.printf("<<RITUAL %s skipped>>\n", ritualName());
  _ritual = RITUAL_NONE;
}

// 0..1 through the current ritual; ends itself at 1.
inline float ritualProgress(uint32_t now) {
  if (_ritual == RITUAL_NONE) return 0.0f;
  uint32_t span = (_ritual == RITUAL_HATCH) ? HATCH_MS : STRETCH_MS;
  float t = (float)(now - _ritualStart) / (float)span;
  if (t >= 1.0f) {
    Serial.printf("<<RITUAL %s done>>\n", ritualName());
    _ritual = RITUAL_NONE;
    return 1.0f;
  }
  return t;
}

// The hatch owns the whole screen until the shell breaks. Phases:
//   0.00-0.45  egg sits and rocks, twice, with a pause between
//   0.45-0.70  cracks spread from the middle
//   0.70-0.78  burst
//   0.78-1.00  newborn face blinks into existence (drawn by the caller)
// Returns true while the egg still owns the screen; false once the face
// should take over.
inline bool ritualDrawHatch(BuddyCanvas& spr, uint32_t now, float t) {
  if (t >= 0.78f) return false;

  const int cx = HAL_W / 2, cy = HAL_H / 2;
  uint16_t shell = animRGB(255, 219, 173);
  uint16_t shade = animRGB(182, 146, 82);

  // Rock: two deliberate sways, then stillness before the crack. The pause
  // is what makes the crack land — motion that never stops reads as idle.
  float rock = 0.0f;
  if (t < 0.45f) {
    float p = t / 0.45f;
    float env = (p < 0.75f) ? sinf(p * 3.14159f / 0.75f) : 0.0f;
    rock = env * 0.22f * sinf(p * 6.2831853f * 2.4f);
  }
  int dx = animPx(rock * 26.0f);
  int lean = animPx(rock * 10.0f);

  // Egg: a body ellipse plus a narrower one above it for the taper. The
  // shading is the same silhouette drawn in shadow and then re-drawn a few
  // pixels to the left in shell — what's left is a crescent hugging the
  // right edge, which reads as a curved surface. Drawing the shadow as its
  // own ellipse instead just paints a dark stripe down the middle.
  int rw = 62, rh = 84;
  const int SHADE_OFF = 9;
  spr.fillEllipse(cx + dx, cy + 6, rw, rh, shade);
  spr.fillEllipse(cx + dx - lean, cy - 30, rw - 12, rh - 34, shade);
  spr.fillEllipse(cx + dx - SHADE_OFF, cy + 6, rw, rh, shell);
  spr.fillEllipse(cx + dx - lean - SHADE_OFF, cy - 30, rw - 12, rh - 34, shell);

  if (t >= 0.45f) {
    float c = (t - 0.45f) / 0.25f;           // 0..1 across the crack phase
    if (c > 1.0f) c = 1.0f;
    int reach = animPx(c * rw);
    // A jagged seam, deterministic so screenshots reproduce.
    int y = cy - 4;
    int px = cx + dx - reach;
    for (int i = 0; px < cx + dx + reach && i < 24; i++) {
      uint32_t h = animHash(0xE66u + i * 2654435761u);
      int step = 6 + (int)(h % 9);
      int dy = (int)(h % 15) - 7;
      spr.drawLine(px, y, px + step, y + dy, BLACK);
      spr.drawLine(px, y + 1, px + step, y + dy + 1, BLACK);
      px += step;
      y += dy;
      if (y < cy - 22) y = cy - 22;
      if (y > cy + 14) y = cy + 14;
    }
  }

  if (t >= 0.70f) {
    // Burst: shell fragments fly outward and the egg gives way.
    float b = (t - 0.70f) / 0.08f;
    for (int i = 0; i < 14; i++) {
      uint32_t h = animHash(0xB0057u + i * 7919u);
      float a = (float)(h % 628) / 100.0f;
      float d = b * (70.0f + (float)(h % 90));
      int fx = cx + dx + animPx(cosf(a) * d);
      int fy = cy + animPx(sinf(a) * d * 0.7f);
      int fr = 3 + (int)(h % 4);
      spr.fillSmoothCircle(fx, fy, fr, shell);
    }
  }
  return true;
}

// The stretch is a face modifier, not a drawing: the face scales up ~5%
// with the eyes lifted, then settles. Returned as a scale factor the caller
// folds into FaceOpts.
inline float ritualStretchScale(float t) {
  if (_ritual != RITUAL_STRETCH) return 1.0f;
  // Up fast, hold briefly, down slow — the shape of an actual stretch.
  float env = (t < 0.35f) ? (t / 0.35f)
            : (t < 0.55f) ? 1.0f
            : (1.0f - (t - 0.55f) / 0.45f);
  return 1.0f + 0.05f * animClamp(env, 0.0f, 1.0f);
}

// True while the stretch's yawn should be on the face.
inline bool ritualYawning(float t) {
  return _ritual == RITUAL_STRETCH && t > 0.15f && t < 0.70f;
}
