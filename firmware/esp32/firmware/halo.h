#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "mood.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h.
//
// The halo (PEBBLE-UX §3.1) — the ambient channel *within* Night mode. The
// halo and the field (§2.1) are complementary, not redundant: attention and
// error are carried by the field, so the halo has no state for them, and it
// yields entirely while the field is lit (moodHaloGain) so the two never
// fight for the same pixels.
//
//   idle           warm amber ring, breathing    ~6s
//   busy/thinking  species accent ring           ~4s
//   celebrate      one green ripple outward      one-shot ~1.2s
//   sleep          none
//
// DIVERGENCE FROM SPEC, on purpose. §3.1 asks for "a soft radial glow
// behind/around the face". This renders a RING around the face instead.
// Three hardware facts forced it, each found by sampling real screenshots
// rather than by reasoning:
//
//  1. LGFX truncates when it narrows RGB565 to RGB332 (it does not round),
//     so any tint below ~15% amplitude quantizes to pure black. A first
//     attempt at the spec's "barely-there" glow rendered an entirely black
//     frame — the panel cannot represent it at all.
//
//  2. Blue keeps only 4 levels and dies first, so a dim warm white lands on
//     olive. "Warm" at this luminance has to be an amber tint chosen so red
//     sits one lattice level above green.
//
//  3. With ~5 usable dim levels, a filled glow behind the face is a flat
//     plate, not light — and it puts the face on brown, violating doctrine
//     #1 (the face lives on true black). Radial dithering to fake more
//     levels cost ~11ms/frame and still banded.
//
// A ring resolves all three: the face keeps its black, the light sits
// around it (which is what "halo" meant in the first place), and it costs
// ring area rather than disc area. Breathing rides the RADIUS, not the
// brightness — modulating amplitude across so few levels makes the whole
// ring pop between colours, while radius is continuous (doctrine #8).

static const int HALO_CX = HAL_W / 2;
static const int HALO_CY = 100;      // matches the bloom centre
static const int HALO_R_IN  = 130;   // clears the face (~98px out at most)
static const int HALO_R_MID = 158;
static const int HALO_R_OUT = 190;
// Amber, not warm white — see note 2 above.
static const uint16_t HALO_TINT_IDLE = animRGB(255, 150, 40);
// Inner band is brighter than the outer, which is the whole falloff the
// palette can afford. Busy runs slightly hotter so "working" reads across a
// desk — but only slightly: the species accents are saturated, and matching
// the amber's amplitude with a pure green made the ring the loudest thing
// on the panel, drowning both the face and the orbs.
static const float HALO_OUT_AMP_IDLE = 0.15f;
static const float HALO_IN_AMP_IDLE  = 0.27f;
static const float HALO_OUT_AMP_BUSY = 0.11f;
static const float HALO_IN_AMP_BUSY  = 0.19f;

static float    _haloGain = 0.0f;      // eased presence, kills pop on state change
static uint32_t _haloCelebrateAt = 0;  // one-shot ripple start

inline void haloCelebrate(uint32_t now) { _haloCelebrateAt = now; }

// persona uses the same 0..6 indices as faceTick.
inline void haloTick(uint8_t persona, float dt) {
  // Sleep has no halo at all; everything else breathes. Easing the gain
  // means a state change dissolves the ring instead of cutting it.
  float target = (persona == 0) ? 0.0f : 1.0f;
  _haloGain = animEase(_haloGain, target, 5.0f, dt);
}

// tintOverride != 0 replaces the state-derived colour. Pair-me uses it to
// wear Bluetooth blue — the one state where the halo's colour is itself the
// message ("this is about the radio"), rather than ambient decoration.
inline void haloDraw(BuddyCanvas& spr, uint32_t now, uint8_t persona, uint16_t accent,
                     uint16_t tintOverride = 0) {
  float gain = _haloGain * moodHaloGain();
  if (gain <= 0.06f) return;

  bool busy = (persona == 2);
  // Idle wears the amber so the resting screen reads as ambient rather than
  // branded; working wears the species accent, which is what makes "my
  // buddy is doing something" legible from across a desk.
  uint16_t tint = tintOverride ? tintOverride : (busy ? accent : HALO_TINT_IDLE);
  float ampOut = busy ? HALO_OUT_AMP_BUSY : HALO_OUT_AMP_IDLE;
  float ampIn  = busy ? HALO_IN_AMP_BUSY  : HALO_IN_AMP_IDLE;

  float periodMs = busy ? 4000.0f : 6000.0f;
  float breath = 1.0f + 0.06f * sinf((float)now * (6.2831853f / periodMs));
  float scale = breath * (0.45f + 0.55f * gain);   // gain grows the ring in

  int rIn  = animPx(HALO_R_IN * scale);
  int rMid = animPx(HALO_R_MID * scale);
  int rOut = animPx(HALO_R_OUT * scale);
  spr.fillArc(HALO_CX, HALO_CY, rMid, rOut, 0, 360, _moodMix(BLACK, tint, ampOut));
  spr.fillArc(HALO_CX, HALO_CY, rIn, rMid, 0, 360, _moodMix(BLACK, tint, ampIn));

  // Celebrate: one green front races outward through the ring and past it,
  // fading as it goes. Night mood throughout — spending the lantern on a
  // happy state would cost the lantern its meaning (§2.1).
  if (_haloCelebrateAt != 0) {
    float age = (float)(now - _haloCelebrateAt) / 1200.0f;
    if (age > 1.0f) {
      _haloCelebrateAt = 0;
    } else if (age >= 0.0f) {
      int rr = animPx((HALO_R_IN + (HALO_R_OUT * 1.8f - HALO_R_IN) * age) * scale);
      int w = 14 + animPx(16.0f * (1.0f - age));
      if (rr > w) {
        spr.fillArc(HALO_CX, HALO_CY, rr - w, rr, 0, 360,
                    _moodMix(BLACK, MOOD_RIPPLE, 0.22f + 0.42f * (1.0f - age)));
      }
    }
  }
}
