#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h.
//
// Session tracking (PEBBLE-UX §3.2, reduced).
//
// This was a full firefly renderer — one drifting orb per agent session.
// The orbs are no longer drawn: once the halo came out and the face grew to
// fill the panel, small dots orbiting it read as dust on the glass rather
// than as sessions. What survived is the part that still has consumers:
//
//   - the live count and overflow, reported in the `state` JSON
//   - which SIDE a newly started session is on, so the face can flick its
//     gaze that way (§3.3) and look like it noticed
//
// The spawn/despawn reconciliation is kept because the gaze flick needs to
// know WHICH change happened, not just that the total moved. Orbs are
// anonymous: the source is tama.sessionsRunning / sessionsWaiting, counts
// rather than identities, so no wire change was ever needed.

static const int ORBS_MAX = 6;          // §3.2 cap
static const int ORB_CX = HAL_W / 2;
// The face's outermost pixels sit ~98px from centre, so orbits start clear
// of that. The axes are separate rather than one radius with an x-stretch:
// a circular orbit wide enough to clear the face horizontally is taller
// than the panel has room for above centre, and orbs
// silently drifted off the top edge — three of four visible on hardware.
static const float ORB_R_BASE = 116.0f;
static const float ORB_R_SWING = 16.0f;
static const float ORB_RX_SCALE = 1.62f;   // fills the landscape width

enum OrbKind : uint8_t { ORB_RUNNING = 0, ORB_WAITING = 1, ORB_GIFT = 2 };

struct Orb {
  bool     alive = false;
  bool     dying = false;
  uint8_t  kind = ORB_RUNNING;
  float    grow = 0.0f;      // 0..1 spawn/despawn envelope
};

static Orb     _orbs[ORBS_MAX];
static uint8_t _orbOverflow = 0;      // sessions beyond the render cap
static uint32_t _orbLastSpawnAt = 0;  // drives the gaze flick (§3.3)
static int      _orbLastSpawnIdx = -1;
static uint32_t _orbNextChangeAt = 0; // staggers count changes

inline int orbsAlive() {
  int n = 0;
  for (int i = 0; i < ORBS_MAX; i++) if (_orbs[i].alive && !_orbs[i].dying) n++;
  return n;
}

inline uint8_t orbsOverflow() { return _orbOverflow; }

// Deterministic per-slot orbit parameters — no rand(), so HIL screenshots
// stay reproducible (the same rule the face's particles follow).
static inline float _orbOrbitX(int i, uint32_t now) {
  uint32_t h = animHash(0x0B0Bu + (uint32_t)i * 2654435761u);
  float speed = 0.10f + (float)(h % 37) * 0.004f;        // rad/s
  float phase = (float)(h % 628) / 100.0f;
  float swingSpeed = 0.23f + (float)((h >> 8) % 19) * 0.006f;
  float swingPhase = (float)((h >> 4) % 628) / 100.0f;
  float t = (float)now / 1000.0f;
  float a = t * speed + phase;
  float r = ORB_R_BASE + ORB_R_SWING * sinf(t * swingSpeed + swingPhase);
  return ORB_CX + cosf(a) * r * ORB_RX_SCALE;
}

// Reconcile the orb sky with the heartbeat's counts. Changes animate one
// orb at a time (~150ms apart) so the sky never flickers when several
// sessions start or finish together.
inline void orbsTick(uint32_t now, float dt, uint8_t running, uint8_t waiting, uint8_t gifts) {
  int wantWaiting = waiting;
  int wantRunning = running;
  int wantGift = gifts > 0 ? 1 : 0;
  int want = wantRunning + wantWaiting + wantGift;
  _orbOverflow = want > ORBS_MAX ? (uint8_t)(want - ORBS_MAX) : 0;
  if (want > ORBS_MAX) {
    // Waiting sessions and gifts are the ones a human might act on, so they
    // keep their orbs; running sessions are what get folded into the
    // "many" indicator.
    wantRunning = ORBS_MAX - wantWaiting - wantGift;
    if (wantRunning < 0) { wantRunning = 0; wantWaiting = ORBS_MAX - wantGift; }
  }

  // Count what's currently promised (alive and not dying) per kind.
  int have[3] = {0, 0, 0};
  for (int i = 0; i < ORBS_MAX; i++)
    if (_orbs[i].alive && !_orbs[i].dying) have[_orbs[i].kind]++;
  int wantK[3] = { wantRunning, wantWaiting, wantGift };

  // One change per stagger window.
  if ((int32_t)(now - _orbNextChangeAt) >= 0) {
    for (uint8_t k = 0; k < 3; k++) {
      if (have[k] < wantK[k]) {
        for (int i = 0; i < ORBS_MAX; i++) {
          if (!_orbs[i].alive) {
            // Field-by-field, not brace-init: Orb carries default member
            // initializers, which makes it a non-aggregate under the older
            // C++ standard the M5 core still builds with.
            _orbs[i].alive = true;
            _orbs[i].dying = false;
            _orbs[i].kind = k;
            _orbs[i].grow = 0.0f;
            _orbLastSpawnAt = now;
            _orbLastSpawnIdx = i;
            _orbNextChangeAt = now + 150;
            goto changed;
          }
        }
      } else if (have[k] > wantK[k]) {
        for (int i = ORBS_MAX - 1; i >= 0; i--) {
          if (_orbs[i].alive && !_orbs[i].dying && _orbs[i].kind == k) {
            _orbs[i].dying = true;
            _orbNextChangeAt = now + 150;
            goto changed;
          }
        }
      }
    }
  }
changed:

  for (int i = 0; i < ORBS_MAX; i++) {
    if (!_orbs[i].alive) continue;
    // Spawn: fade + scale in over ~400ms. Despawn: shrink and pop.
    float target = _orbs[i].dying ? 0.0f : 1.0f;
    _orbs[i].grow = animEase(_orbs[i].grow, target, _orbs[i].dying ? 14.0f : 8.0f, dt);
    if (_orbs[i].dying && _orbs[i].grow < 0.03f) _orbs[i].alive = false;
  }
}

// Horizontal offset the eyes should flick toward, or 0. A session starting
// is something the buddy NOTICES (§3.3) — the gaze snaps to the new orb for
// ~600ms, then goes back to whatever it was doing.
inline float orbsGazeNudge(uint32_t now) {
  if (_orbLastSpawnIdx < 0 || now - _orbLastSpawnAt > 600) return 0.0f;
  float x = _orbOrbitX(_orbLastSpawnIdx, now);
  return animClamp((x - ORB_CX) / (float)ORB_CX, -1.0f, 1.0f);
}

