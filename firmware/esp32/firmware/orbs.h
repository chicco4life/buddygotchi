#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "mood.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h.
//
// Session orbs (PEBBLE-UX §3.2) — agent sessions as fireflies drifting
// around the face. One orb per session:
//
//   running          species accent, soft pulse
//   waiting on user  amber, brighter, gravitates toward an eye
//   gift (§8)        gold, twinkling
//
// Orbs are ANONYMOUS. The data source is tama.sessionsRunning /
// sessionsWaiting — counts, not identities — so no wire change was needed.
// Exact numbers live in the glance card; the resting screen only carries
// "how much is going on", which is a thing you read without reading.
//
// Orbits are elliptical with per-orb radius, speed and phase, sized so the
// path never crosses the face. That is cheaper and steadier than the spec's
// Lissajous-plus-exclusion-zone: an exclusion test has to shove orbs out of
// the way when they wander in, which reads as a twitch. Keeping them out by
// construction means they simply never do.

static const int ORBS_MAX = 6;          // §3.2 cap
static const int ORB_CX = HAL_W / 2;
static const int ORB_CY = 104;
// The face's outermost pixels sit ~98px from centre, so orbits start clear
// of that. The axes are separate rather than one radius with an x-stretch:
// a circular orbit wide enough to clear the face horizontally is taller
// than the panel has room for above centre (ORB_CY is 104 of 280), and orbs
// silently drifted off the top edge — three of four visible on hardware.
static const float ORB_R_BASE = 116.0f;
static const float ORB_R_SWING = 16.0f;
static const float ORB_RX_SCALE = 1.62f;   // fills the landscape width
static const float ORB_RY_SCALE = 0.70f;   // stays on the panel vertically

enum OrbKind : uint8_t { ORB_RUNNING = 0, ORB_WAITING = 1, ORB_GIFT = 2 };

struct Orb {
  bool     alive = false;
  bool     dying = false;
  uint8_t  kind = ORB_RUNNING;
  float    grow = 0.0f;      // 0..1 spawn/despawn envelope
  uint32_t bornAt = 0;
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
static inline void _orbOrbit(int i, uint32_t now, float* x, float* y) {
  uint32_t h = animHash(0x0B0Bu + (uint32_t)i * 2654435761u);
  float speed = 0.10f + (float)(h % 37) * 0.004f;        // rad/s
  float phase = (float)(h % 628) / 100.0f;
  float swingSpeed = 0.23f + (float)((h >> 8) % 19) * 0.006f;
  float swingPhase = (float)((h >> 4) % 628) / 100.0f;
  float t = (float)now / 1000.0f;
  float a = t * speed + phase;
  float r = ORB_R_BASE + ORB_R_SWING * sinf(t * swingSpeed + swingPhase);
  *x = ORB_CX + cosf(a) * r * ORB_RX_SCALE;
  *y = ORB_CY + sinf(a) * r * ORB_RY_SCALE;
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
            _orbs[i].bornAt = now;
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
  float x, y;
  _orbOrbit(_orbLastSpawnIdx, now, &x, &y);
  return animClamp((x - ORB_CX) / (float)ORB_CX, -1.0f, 1.0f);
}

// Waiting orbs gravitate toward an eye — the one place on the face a human
// already looks. gain fades the whole sky out under a lit field, the same
// way the halo yields (§2.1).
inline void orbsDraw(BuddyCanvas& spr, uint32_t now, uint16_t accent, float gain) {
  if (gain <= 0.04f) return;
  const uint16_t AMBER = animRGB(255, 182, 0);
  const uint16_t GOLD  = animRGB(255, 219, 82);

  for (int i = 0; i < ORBS_MAX; i++) {
    if (!_orbs[i].alive) continue;
    float x, y;
    _orbOrbit(i, now, &x, &y);

    uint16_t c = accent;
    float amp = 0.55f;
    float rad = 5.0f;
    if (_orbs[i].kind == ORB_WAITING) {
      // Drift a third of the way toward the near eye and sit brighter.
      float eyeX = (x < ORB_CX) ? (ORB_CX - 76) : (ORB_CX + 76);
      x += (eyeX - x) * 0.34f;
      y += (92.0f - y) * 0.34f;
      c = AMBER; amp = 0.95f; rad = 6.0f;
    } else if (_orbs[i].kind == ORB_GIFT) {
      c = GOLD; amp = 0.90f; rad = 6.0f;
    }

    // Pulse: slow for running, urgent for waiting, twinkle for gifts.
    uint32_t h = animHash(0xA11Eu + (uint32_t)i * 7919u);
    float period = (_orbs[i].kind == ORB_WAITING) ? 900.0f
                 : (_orbs[i].kind == ORB_GIFT)    ? 520.0f
                 : 2100.0f + (float)(h % 700);
    float pulse = 0.72f + 0.28f * (0.5f + 0.5f * sinf((float)now * (6.2831853f / period)
                                                      + (float)(h % 628) / 100.0f));
    // The last rendered orb doubles as the "many" indicator when there are
    // more sessions than orbs: bigger, with a second pulse riding the first.
    if (_orbOverflow > 0 && i == ORBS_MAX - 1) {
      rad += 2.5f;
      pulse *= 0.80f + 0.20f * (0.5f + 0.5f * sinf((float)now * (6.2831853f / 260.0f)));
    }

    float g = _orbs[i].grow;
    int r = animPx(rad * (0.35f + 0.65f * g));
    if (r < 1) continue;
    uint16_t col = _moodMix(BLACK, c, animClamp(amp * pulse * g * gain, 0.0f, 1.0f));
    spr.fillSmoothCircle(animPx(x), animPx(y), r, col);
  }
}
