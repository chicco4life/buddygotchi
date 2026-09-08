#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "mood.h"
#include "glance.h"
#include "ble_bridge.h"
#include "data.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after glance.h (for the Bluetooth glyph) and data.h.
//
// Presence (PEBBLE-UX §9.1) — how the device behaves when the desktop isn't
// there. The tension the spec identifies: a never-paired device must fail
// LOUDLY (nothing works and the user needs instruction), but a paired device
// whose laptop went to sleep must stay CUTE (the condition is routine and
// self-heals). Getting that wrong in either direction is bad — a loud error
// screen every time a lid closes is obnoxious, and a cute nap on a device
// that has never been adopted tells a new owner nothing.
//
// The resolver is the bond store. "Never adopted" is gated on bleBonded(),
// a condition that exists only before first adoption (or after an explicit
// unpair), so a customer sees the loud state exactly once and every later
// interruption presents as rest.
//
//   never adopted           PAIR-ME  loud, in-universe, asks to be adopted
//   adopted, link down      NAP      quiet, honest, with a link glyph
//   adopted, link up, no data  NAP    same; the glance card carries the tell
//
// All three signals are local to the device. No wire change.

enum PresenceKind : uint8_t { PRESENCE_LIVE = 0, PRESENCE_NAP, PRESENCE_PAIRME };

// Radio hiccups should be invisible: a link that drops and returns inside
// this window never reaches the face at all.
static const uint32_t PRESENCE_GRACE_MS = 10000;
// Pair-me blooms the lantern briefly when someone engages, then settles
// back to Night. It can persist for hours on an unadopted device, and a
// permanent cream field would burn power and panel for a message nobody is
// currently reading.
static const uint32_t PAIRME_BLOOM_MS = 3000;
// The one state that wears Bluetooth blue, so the colour itself says
// "radio". Blue keeps only 4 levels in RGB332, so this is deliberately
// bright enough to survive quantization.
static const uint16_t PAIRME_BLUE = animRGB(82, 146, 255);

static uint32_t _presLinkLostAt = 0;
static uint32_t _presPairBloomUntil = 0;
// Debug/HIL override. Pair-me is otherwise only reachable by having no bond
// at all, and the only way to produce that on a working device is to erase
// its real pairing — destructive, and it would make the test suite hostile
// to run on the developer's own desk. -1 = follow the bond store.
static int8_t _presForce = -1;

inline void presenceForce(int8_t k) { _presForce = k; }
inline bool presenceForced() { return _presForce >= 0; }

inline PresenceKind presenceNow() {
  if (_presForce >= 0) return (PresenceKind)_presForce;
  if (!bleBonded()) return PRESENCE_PAIRME;
  if (!dataConnected()) return PRESENCE_NAP;
  return PRESENCE_LIVE;
}

inline const char* presenceName() {
  switch (presenceNow()) {
    case PRESENCE_PAIRME: return "pair-me";
    case PRESENCE_NAP:    return "nap";
    default:              return "live";
  }
}

// Track link loss so the grace window can be measured. Called every loop.
inline void presenceTick(uint32_t now) {
  if (dataConnected()) _presLinkLostAt = 0;
  else if (_presLinkLostAt == 0) _presLinkLostAt = now;
}

// True while a link drop is still inside its grace window — the face should
// carry on as if nothing happened.
inline bool presenceGraced(uint32_t now) {
  return _presLinkLostAt != 0 && (now - _presLinkLostAt) < PRESENCE_GRACE_MS;
}

// Someone pressed a button or touched the glass on an unadopted device:
// bloom the instruction loudly for a few seconds, then settle back.
inline void presenceEngaged(uint32_t now) {
  if (presenceNow() != PRESENCE_PAIRME) return;
  _presPairBloomUntil = now + PAIRME_BLOOM_MS;
}

inline bool presencePairBlooming(uint32_t now) {
  return (int32_t)(_presPairBloomUntil - now) > 0;
}

// The pair-me speech, cycling ~4s between the instruction and the name the
// device is actually advertising — the two things someone standing in front
// of an unadopted buddy needs.
inline void presencePairText(char* out, size_t n, const char* btName, uint32_t now) {
  if (((now / 4000) & 1) == 0) snprintf(out, n, "pair me!");
  else                         snprintf(out, n, "I'm %s", btName && btName[0] ? btName : "Boop");
}

// The link-down marker: a small crossed-out Bluetooth rune centred on the
// bottom edge, on the same baseline as the corner readouts, so it sits
// between them rather than floating over the face.
//
// It was originally a dream bubble drifting up beside the head, which put a
// second moving object on a screen whose whole point is the face — and it
// collided with the sleep z's. Down here it reads as what it is: a status
// tell, in the strip where status lives, small enough to ignore and specific
// enough to answer "why is it asleep?" when you look.
//
// Still breathes rather than sitting perfectly static, because a hard-edged
// permanent icon on the resting screen is exactly the status text §14
// deleted.
inline void presenceDrawLinkGlyph(BuddyCanvas& spr, uint32_t now, uint16_t tint) {
  const int S = HAL_UI_SCALE;
  int cx = HAL_W / 2;
  // Genuinely the corner readouts' baseline, not an approximation of it —
  // this used to be a hand-picked 13*S against their 9*S, so the glyph sat
  // 8px below the text its own comment said it lined up with.
  int cy = HAL_H - CORNER_SAFE_Y - 3 * S;
  // Slow fade in and out, ~5s cycle, never fully gone.
  float a = 0.72f + 0.28f * animPulse01(now, 5000.0f);
  glanceBtGlyph(spr, cx, cy, 7 * S, animMix(BLACK, tint, 0.95f * a), true);
}
