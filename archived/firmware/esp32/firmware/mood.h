#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp).
//
// The screen mood system (PEBBLE-UX §2.1) — the product's primary alert
// channel. The most legible signal a screen can send across a room is
// overall luminance, not color or shape, so the background field is
// promoted from a constant to a carrier of meaning, with one rule:
//
//     Field brightness encodes how much the buddy needs you.
//     Black = nothing needed. Light = act now.
//
// Two moods, pre-attentively distinguishable with zero reading:
//
//   Night    true black field, glow-on-black face   (the default; everything
//                                                    except the one below)
//   Lantern  warm cream field, DARK INK face        (approval, passkey)
//
// The spec's third mood (Ember, a lifted warm field for errors) is gone —
// see the note on MoodKind.
//
// Lantern is a genuine luminance inversion — the whole panel flips
// dark->light. Nothing else in the product does this, which is what makes
// it unmissable in peripheral vision. It is rare and transient, so the
// usual AMOLED objections (power, burn-in) don't apply; the night-aware
// entry and the 2-minute decay below cap exposure anyway.
//
// Reserving light strictly for "act now" is what keeps it powerful. The
// glance card, gift-waiting, and celebrate all stay in Night even though
// they're visually eventful — spending the lantern on happy states would
// cost it its meaning.

// --- Palette ---------------------------------------------------------------
// The 8bpp canvas quantizes to RGB332: red and green keep 8 levels each,
// blue only 4 (0, 82, 173, 255). Neutral off-whites are therefore
// unreachable — but warm creams are, which suits the brand. These are the
// spec's tokens; LGFX snaps them to the nearest lattice point on the way
// into the sprite, so they render with essentially no quantization error.
static const uint16_t FIELD_LANTERN     = animRGB(255, 219, 173);  // #FFDBAD
static const uint16_t FIELD_LANTERN_HOT = animRGB(255, 182,  82);  // #FFB652
static const uint16_t MOOD_INK          = animRGB( 33,   0,   0);  // #210000
static const uint16_t MOOD_INK_DIM      = animRGB(107,  36,   0);  // #6B2400
static const uint16_t MOOD_RIPPLE       = animRGB( 36, 219,  82);  // approve green
// Red-orange: warnings, impatience, deny. Lives here rather than in main.cpp
// so the card and bubble surfaces can reach it too.
static const uint16_t MOOD_HOT          = 0xFA20;

// Two moods, not the spec's three. §2.1's Ember (a lifted warm field for
// errors) went through a loud orange and then a soft clay before landing on
// the answer that was there all along: the dizzy face is expressive enough
// on its own, and lifting the field for it spent the product's scarcest
// signal — luminance — on a state the human usually can't act on. Black is
// now genuinely reserved for "nothing needed", and light for "act now".
enum MoodKind : uint8_t { MOOD_NIGHT = 0, MOOD_LANTERN = 2 };

// Transition timings (§2.1.3). Bloom is slower than snuff on purpose:
// arriving is a lamp warming, resolving should feel decisive.
static const float MOOD_BLOOM_RATE = 9.0f;    // ~350ms to full reach
static const float MOOD_SNUFF_RATE = 13.0f;   // ~250ms to contract away
static const float MOOD_FADE_RATE  = 9.0f;    // ~350ms even fade (deny)
static const float MOOD_INK_RATE   = 9.0f;    // face crossfade, tracks bloom

static MoodKind _moodTarget = MOOD_NIGHT;
// Two independent axes make every transition in §2.1.3 expressible:
//   reach — how far the light FRONT has expanded (bloom / snuff)
//   level — how BRIGHT the lit field is        (fade / night-aware peak)
// Bloom moves reach; deny's fade moves level; approve's snuff moves reach
// back. They never fight because each transition only drives one.
static float _moodReach = 0.0f;
static float _moodLevel = 0.0f;
static float _moodHot   = 0.0f;    // 0..1 blend toward FIELD_LANTERN_HOT
static float _moodDecay = 0.0f;    // 0..1 dim-down after 2min unanswered
static float _moodInk   = 0.0f;    // 0..1 face crossfade glow -> ink
static float _moodPeak  = 1.0f;    // night-aware entry cap
static float _moodRipple = -1.0f;  // >=0 while the approve ripple runs
// The lit field HOLDS steady. An earlier build swung it black<->cream on a
// 2.4s cosine to fight banner blindness, but on the real panel a full-field
// luminance strobe reads as an alarm, not an ask (field-tested 2026-08-02).
// The dark->light inversion itself is the attention grab; the ±6% breath in
// moodFieldColor() keeps it alive without flashing.
static bool  _moodSnuffing = false;
static bool  _moodFading = false;

// Where the light front is centred: behind the face, slightly above centre,
// so the bloom reads as the buddy lighting itself up to ask.
static const int MOOD_CX = HAL_W / 2;
static const int MOOD_CY = 100;

inline const char* moodName() {
  // Report what's on glass, not what was asked for — a mood mid-bloom is
  // the interesting case for both HIL and debugging.
  if (_moodReach * _moodLevel > 0.02f) return _moodTarget == MOOD_LANTERN ? "lantern" : "lantern-out";
  return "night";
}

// 0..1 how lit the field is right now. The screenshot oracle asserts on the
// corner pixel; this is the same number in float form for `state`.
inline float moodLit() { return _moodReach >= 0.999f ? _moodLevel : 0.0f; }
inline float moodInkBlend() { return _moodInk; }
inline bool  moodIsInk() { return moodInkBlend() > 0.5f; }

// Ask for a mood. Night-aware entry: if the screen was dark when a prompt
// arrived, the lantern blooms to a reduced peak and only ramps to full as
// it escalates. Waking a dark room with a full-brightness cream field is
// the one way this feature turns hostile.
inline void moodSet(MoodKind k, bool screenWasDark) {
  if (k == _moodTarget) return;
  if (k == MOOD_LANTERN) {
    _moodPeak = screenWasDark ? 0.6f : 1.0f;
    _moodHot = 0.0f;
    _moodDecay = 0.0f;
    _moodSnuffing = false;
    _moodFading = false;
    _moodRipple = -1.0f;
  }
  _moodTarget = k;
  Serial.printf("<<MOOD %s>>\n", k == MOOD_LANTERN ? "lantern" : "night");
}

// Approve: the light contracts back INTO the face and goes out, with a
// green ripple leading it. Deliberately faster than the bloom.
inline void moodSnuff() {
  if (_moodTarget != MOOD_LANTERN) return;
  _moodSnuffing = true;
  _moodRipple = 0.0f;
  _moodTarget = MOOD_NIGHT;
  Serial.println("<<MOOD snuff>>");
}

// Deny: the field dims evenly to black. No ripple, no contraction —
// denial is responsible, not punished.
inline void moodFade() {
  if (_moodTarget != MOOD_LANTERN) return;
  _moodFading = true;
  _moodTarget = MOOD_NIGHT;
  Serial.println("<<MOOD fade>>");
}

// Escalation (§7): unanswered >=10s warms the field and quickens its
// breath. This IS the urgency signal — it replaces the numeric counter.
// After 2 minutes the field dims down with a top-edge pulse, which protects
// the panel and avoids lighting an empty room all night while staying
// honest that the prompt is still pending.
inline void moodEscalation(float hot01, float decay01) {
  _moodHot = animClamp(hot01, 0.0f, 1.0f);
  _moodDecay = animClamp(decay01, 0.0f, 1.0f);
  // Escalating overrides a night-aware entry: if it's still unanswered
  // after 10s, someone is awake and the field has earned full brightness.
  if (_moodHot > 0.0f) _moodPeak = animClamp(0.6f + 0.4f * _moodHot, _moodPeak, 1.0f);
}

inline void moodTick(uint32_t now, float dt) {
  bool wantLantern = (_moodTarget == MOOD_LANTERN);

  if (wantLantern) {
    _moodReach = animEase(_moodReach, 1.0f, MOOD_BLOOM_RATE, dt);
    // Level leads reach deliberately. §2.1.3 asks for a light front that
    // fills FIELD_LANTERN *as it goes* — ramping both together instead
    // makes the early bloom a dark disc sitting in the middle of the face,
    // which reads as a hole rather than as a lamp warming.
    _moodLevel = animEase(_moodLevel, _moodPeak, MOOD_BLOOM_RATE * 3.0f, dt);
  } else if (_moodSnuffing) {
    // Contract the front back into the face; level rides along at the end
    // so the last sliver doesn't linger as a bright dot.
    _moodReach = animEase(_moodReach, 0.0f, MOOD_SNUFF_RATE, dt);
    if (_moodReach < 0.06f) _moodLevel = animEase(_moodLevel, 0.0f, MOOD_SNUFF_RATE * 2.0f, dt);
    if (_moodReach < 0.01f) { _moodReach = 0.0f; _moodLevel = 0.0f; _moodSnuffing = false; }
  } else if (_moodFading) {
    _moodLevel = animEase(_moodLevel, 0.0f, MOOD_FADE_RATE, dt);
    if (_moodLevel < 0.01f) { _moodLevel = 0.0f; _moodReach = 0.0f; _moodFading = false; }
  } else {
    _moodReach = animEase(_moodReach, 0.0f, MOOD_FADE_RATE, dt);
    _moodLevel = animEase(_moodLevel, 0.0f, MOOD_FADE_RATE, dt);
  }

  // The face inverts to ink only under a genuinely lit field, so a snuff
  // hands the glow back as the light leaves.
  _moodInk = animEase(_moodInk, wantLantern ? 1.0f : 0.0f, MOOD_INK_RATE, dt);

  if (_moodRipple >= 0.0f) {
    _moodRipple += dt * 3.6f;          // ~280ms sweep to the corners
    if (_moodRipple > 1.0f) _moodRipple = -1.0f;
  }
  (void)now;
}

// The lit field's colour this frame: lantern warmed toward HOT by
// escalation, then decayed back toward ember if it's gone unanswered for
// two minutes, then scaled by level (night-aware peak + fade) and
// modulated by the luminance breath.
inline uint16_t moodFieldColor(uint32_t now) {
  uint16_t c = animMix(FIELD_LANTERN, FIELD_LANTERN_HOT, _moodHot);
  // Breath: +-6%, 4s at rest, quickening to 1.2s when hot. Field MOTION is
  // detected peripherally even better than hue, which is why escalation
  // spends its budget here rather than on a counter.
  float periodMs = 4000.0f - 2800.0f * _moodHot;
  float breath = 0.94f + 0.12f * animPulse01(now, periodMs);
  // The long-unanswered decay dims the field rather than recolouring it:
  // with Ember gone there is nowhere warm to decay TO, and dimming is what
  // the rule was actually for.
  float lvl = _moodLevel * breath * (1.0f - 0.65f * _moodDecay);
  return animMix(BLACK, c, animClamp(lvl, 0.0f, 1.0f));
}

// Paint the field for this frame. Replaces the face renderer's old
// fillSprite(BLACK) — everything else draws on top of whatever this laid
// down. Nothing snaps (doctrine #6): a mood change is always a front
// expanding, a level fading, or a slow crossfade.
inline void moodDrawField(BuddyCanvas& spr, uint32_t now) {
  // One clear, not two. This used to fillSprite(BLACK) unconditionally and
  // then fillSprite(field) over the top whenever the bloom had reached the
  // corners — i.e. for the whole time an approval is on screen, the single
  // most latency-sensitive state in the product, it painted all 127KB of
  // the PSRAM canvas twice per frame.
  bool lit = (_moodLevel > 0.01f && _moodReach > 0.001f);
  uint16_t field = lit ? moodFieldColor(now) : BLACK;
  spr.fillSprite((lit && _moodReach >= 0.995f) ? field : BLACK);
  if (!lit) return;
  // Furthest screen corner from the bloom centre — the front has to pass it
  // before the field counts as full.
  static const float MAX_R = sqrtf((float)(MOOD_CX * MOOD_CX) +
                                   (float)((HAL_H - MOOD_CY) * (HAL_H - MOOD_CY))) + 8.0f;
  if (_moodReach < 0.995f) {
    // Mid-bloom: the light front expands from behind the face outward past
    // the screen corners — a lamp warming, not a fade-in. (At full reach
    // the fillSprite above already laid the field down.)
    spr.fillSmoothCircle(MOOD_CX, MOOD_CY, animPx(_moodReach * MAX_R), field);
  }

  // Approve ripple: a green ring racing outward just ahead of the snuff.
  if (_moodRipple >= 0.0f) {
    int r = animPx(_moodRipple * MAX_R);
    int w = 6 + animPx(10.0f * (1.0f - _moodRipple));
    if (r > w) {
      spr.fillArc(MOOD_CX, MOOD_CY, r - w, r, 0, 360,
                  animMix(field, MOOD_RIPPLE, 1.0f - _moodRipple * 0.6f));
    }
  }

  // Long-unanswered decay keeps a slow amber pulse at the top edge: the
  // prompt is still pending and the device stays honest about it without
  // lighting the whole room.
  if (_moodDecay > 0.3f) {
    float pulse = animPulse01(now, 2200.0f);
    spr.fillRect(0, 0, HAL_W, 3 * HAL_UI_SCALE,
                 animMix(field, FIELD_LANTERN_HOT, pulse * _moodDecay));
  }
}

// The field colour behind the face right now — what text runs should use as
// their background so they don't punch holes in a lit field. The bloom
// starts behind the face, so once any light exists the face's own area is
// already lit.
inline uint16_t moodBackdrop(uint32_t now) {
  if (_moodLevel <= 0.01f || _moodReach <= 0.001f) {
    return BLACK;
  }
  return moodFieldColor(now);
}

// What colour the face draws in: it crossfades toward warm near-black ink
// as the field lights up, and otherwise keeps its species glow.
inline uint16_t moodFaceColor(uint16_t accent) {
  return animMix(accent, MOOD_INK, moodInkBlend());
}

// Stroke weight for the face (§2.1.2). Light shapes on dark fields
// optically expand (halation); dark shapes on light fields don't. Reusing
// the glow geometry unchanged makes the ink face read heavy and clumsy, so
// it thins by ~10% as the field lights up.
inline float moodStrokeWeight() { return 1.0f - 0.10f * moodInkBlend(); }

