#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
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

// Motion primitives live in anim.h now — every surface shares them so the
// card, the field, and the face all ease with the same curve. Declared
// above the draw helpers because those round with _px.
static inline float _easeToward(float cur, float target, float rate, float dt) {
  return animEase(cur, target, rate, dt);
}

static inline int _px(float v) { return animPx(v); }

// Native-resolution, anti-aliased face parts (the face only runs on the
// landscape board — coordinates here are panel pixels, 2x the logical
// units in FACE_EYES).
static void _faceEye(int cx, int cy, int w, int h, int r, uint16_t c) {
  if (h <= 10) {
    spr.fillSmoothRoundRect(cx - w / 2, cy - 4, w, 8, 4, c);   // closed lid
  } else {
    if (r > h / 2) r = h / 2;
    if (r > w / 2) r = w / 2;
    spr.fillSmoothRoundRect(cx - w / 2, cy - h / 2, w, h, r, c);
  }
}

static void _faceEyeHappy(int cx, int cy, uint16_t c) {
  spr.fillArc(cx, cy + 10, 16, 22, 180, 360, c);         // ∩ arc
}

static void _faceEyeX(int cx, int cy, uint16_t c) {
  for (int t = -2; t <= 2; t++) {
    spr.drawLine(cx - 14, cy - 14 + t, cx + 14, cy + 14 + t, c);
    spr.drawLine(cx - 14, cy + 14 + t, cx + 14, cy - 14 + t, c);
  }
}

// k scales the heart with the squish spring so a boop deforms the affection
// face too — otherwise booping a buddy that's already showing hearts
// produces no visible reaction at all, which is exactly when you'd expect
// the biggest one.
static void _faceEyeHeart(int cx, int cy, uint16_t c, float kw = 1.0f, float kh = 1.0f) {
  int rx = _px(10 * kw), ry = _px(6 * kh);
  int r  = _px(12 * (kw + kh) * 0.5f);
  spr.fillSmoothCircle(cx - rx, cy - ry, r, c);
  spr.fillSmoothCircle(cx + rx, cy - ry, r, c);
  spr.fillTriangle(cx - _px(20 * kw), cy, cx + _px(20 * kw), cy,
                   cx, cy + _px(22 * kh), c);
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

// How the face should render this frame. The face no longer owns the
// background — mood.h paints the field first (§2.1) and the face draws on
// top of whatever mood is current, which is what lets the same geometry
// serve both glow-on-black and ink-on-cream.
struct FaceOpts {
  int      lift   = 0;        // px the whole face rides up (glance card, §6)
  uint16_t color  = 0;        // mood-resolved face colour; 0 = species accent
  uint16_t bg     = BLACK;    // field colour under the face, for text runs
  float    weight = 1.0f;     // stroke weight; ink-on-light thins ~10% (§2.1.2)
  // -1..1 horizontal gaze override (§3.3). Idle gaze is not random noise:
  // a target here (a newly spawned orb, a finger on the glass) outranks the
  // ambient glance drift, because the buddy noticing something specific is
  // more legible than the buddy looking around.
  float    gazeBias = 0.0f;
  // A finger is resting on the glass. The eyes settle into a contented
  // half-blink rather than staying wide — being petted should look like
  // being petted, not like being startled.
  bool     petting = false;
  // Dangle offsets in panel px (§10.2): while the buddy is being held, the
  // eyes swing with the accelerometer through a spring, so it reads as
  // weight rather than as a wobble animation.
  int      dangleX = 0;
  int      dangleY = 0;
  // A gift is waiting to be collected (§8). The idle face carries a subtly
  // expectant look — it's holding something out for you.
  bool     expectant = false;
  // Whole-face scale, driven by the morning stretch ritual (§13).
  float    scale = 1.0f;
  // Big open yawn — the stretch's other half, and a micro-idle in its own
  // right (§12).
  bool     yawn = false;
  // ms since the last real interaction. Micro-idles never fire within 10s
  // of one: the interaction WAS the moment, and following it with a
  // scripted charming beat cheapens both.
  uint32_t sinceInteractionMs = 0;
};

// --- Micro-idles (§12) -----------------------------------------------------
// Rare randomized moments while idle. Global minimum spacing >=90s, uniform
// selection, each <=2s. Rarity is the entire charm: something that happens
// every ten seconds is a screensaver, something that happens twice an hour
// is a personality.
enum MicroIdle : uint8_t {
  MI_NONE = 0, MI_YAWN, MI_ORB_CHASE, MI_WIGGLE, MI_LOOK_AT_YOU, MI_HEAD_TILT,
  MI_COUNT
};
static const uint32_t MI_SPACING_MS = 90000;
static const uint32_t MI_QUIET_MS   = 10000;   // after a real interaction

static uint8_t  _miKind = MI_NONE;
static uint32_t _miStart = 0;
static uint32_t _miEnd = 0;
static uint32_t _miNextAt = 0;
// A debug-forced micro-idle ignores the idle/quiet gate. Without this a
// test that presses a button (most of them do) can never see one, because
// the gate cancels it on the very next frame.
static bool     _miForced = false;

inline const char* faceMicroIdleName() {
  switch (_miKind) {
    case MI_YAWN:        return "yawn";
    case MI_ORB_CHASE:   return "orb-chase";
    case MI_WIGGLE:      return "wiggle";
    case MI_LOOK_AT_YOU: return "look";
    case MI_HEAD_TILT:   return "tilt";
    default:             return "none";
  }
}

// Debug/HIL: force one now. Micro-idles are deliberately rare enough that
// waiting for one in a test would take minutes.
inline void faceForceMicroIdle(uint8_t kind, uint32_t now) {
  if (kind == MI_NONE || kind >= MI_COUNT) return;
  _miKind = kind;
  _miStart = now;
  _miEnd = now + 1800;
  _miForced = true;
}

// Boop squish (§10.1, doctrine #10: physics over keyframes). A boop kicks
// the spring with an impulse and it rings down on its own, so every squish
// is slightly different depending on when the last one landed — which is
// what a sprite sequence can never do.
static AnimSpring _faceSquish;
inline void faceBoopSquish() {
  // Add to the velocity rather than setting position: booping an
  // already-wobbling face should compound, not restart.
  _faceSquish.vel += 7.5f;
  if (_faceSquish.vel > 16.0f) _faceSquish.vel = 16.0f;
}

inline void faceTick(uint8_t persona, const char* activity, bool boopActive,
                     const FaceOpts& opt) {
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

  // Micro-idle scheduling. Only while genuinely idle, and only once the
  // human has left it alone for a while.
  bool miAllowed = (persona == 1) && opt.sinceInteractionMs > MI_QUIET_MS;
  if (_miKind == MI_NONE) {
    if (_miNextAt == 0) _miNextAt = now + MI_SPACING_MS;
    if (miAllowed && (int32_t)(now - _miNextAt) >= 0) {
      uint32_t h = _faceHash(now ^ 0x1D1Eu);
      _miKind = (uint8_t)(MI_YAWN + (h % (MI_COUNT - 1)));
      _miStart = now;
      _miEnd = now + 1200 + (h % 800);      // each <= 2s
    }
  }
  if (_miKind != MI_NONE && ((int32_t)(now - _miEnd) >= 0 || (!miAllowed && !_miForced))) {
    _miKind = MI_NONE;
    _miForced = false;
    _miNextAt = now + MI_SPACING_MS + (_faceHash(now) % 45000);
  }
  // 0..1 through the current micro-idle, and a 0->1->0 envelope so every
  // one of them eases in and out instead of snapping.
  float miT = (_miKind != MI_NONE && _miEnd > _miStart)
                ? animClamp((float)(now - _miStart) / (float)(_miEnd - _miStart), 0.0f, 1.0f)
                : 0.0f;
  float miEnv = sinf(miT * 3.14159265f);

  // Per-state targets; easing morphs between them (state changes glide
  // in over ~100-200ms instead of popping). lift/boost/gaze are native
  // panel pixels.
  float lidTargetL = 1.0f, lidTargetR = 1.0f;
  float liftTarget = 0.0f, boostTarget = 0.0f;
  switch (persona) {
    case 0:   // sleep (peek: a boop cracks the right eye open)
      lidTargetL = 0.10f;
      lidTargetR = boopActive ? 0.75f : 0.10f;
      break;
    case 2: lidTargetL = lidTargetR = 0.62f; break;             // busy focus
    case 3: liftTarget = -12.0f; boostTarget = 16.0f; break;    // attention
    default: break;
  }
  // Being petted settles the lids into a contented half-blink. Sleep keeps
  // its own peek behaviour, and attention must stay wide — a decision is
  // owed and the buddy is not relaxing about it (doctrine #12).
  if (opt.petting && persona != 0 && persona != 3) {
    lidTargetL = lidTargetR = 0.66f;
  }
  // Holding a gift out for you: eyes open a little wider and lift, the
  // face-first equivalent of raised brows. Deliberately small — the gold
  // orb is the signal, this is the tell you notice second.
  if (opt.expectant && (persona == 1 || persona == 2)) {
    liftTarget -= 4.0f;
    boostTarget += 5.0f;
  }
  // Busy theater (§11): the activity verb selects HOW the buddy works, not
  // just what it says it's doing. Someone glancing over should be able to
  // tell reading from testing without reading the word.
  float busyNod = 0.0f;
  float busySaccade = 0.0f;
  if (persona == 2) {
    const char* a = activity ? activity : "";
    if (strcmp(a, "read") == 0 || strcmp(a, "web") == 0) {
      // Line-by-line saccades: hold, jump, hold — reading is not a smooth
      // sweep, and the discreteness is what makes it read as reading.
      float ph = fmodf((float)now / 1900.0f, 1.0f);
      int step = (int)(ph * 4.0f);
      busySaccade = -9.0f + (float)step * 6.0f;
      if (ph > 0.93f) busySaccade = -9.0f;      // carriage return
    } else if (strcmp(a, "verify") == 0) {
      lidTargetL = lidTargetR = 0.46f;          // squinted concentration
      // ...with an occasional determined blink.
      if (((now / 2600) & 3) == 0 && (now % 2600) < 130) lidTargetL = lidTargetR = 0.08f;
    } else if (strcmp(a, "write") == 0) {
      lidTargetL = lidTargetR = 0.58f;
      busyNod = 2.2f * sinf((float)now * (6.2831853f / 1500.0f));   // tiny nods
    }
  }

  // Micro-idle effects. Each is small and each is over in under two
  // seconds; the point is that you catch them out of the corner of an eye.
  float miTilt = 0.0f, miWiggle = 0.0f, miGaze = 0.0f;
  bool  miYawn = false;
  if (_miKind == MI_YAWN) {
    miYawn = miT > 0.2f && miT < 0.8f;
    if (miYawn) lidTargetL = lidTargetR = 0.30f;
  } else if (_miKind == MI_ORB_CHASE) {
    // Eyes follow something all the way around, once.
    miGaze = 17.0f * sinf(miT * 6.2831853f);
  } else if (_miKind == MI_WIGGLE) {
    miWiggle = 9.0f * miEnv * sinf(miT * 6.2831853f * 2.5f);
  } else if (_miKind == MI_LOOK_AT_YOU) {
    // Dead centre, one slow deliberate blink. The stillness is the effect.
    miGaze = 0.0f;
    if (miT > 0.45f && miT < 0.62f) lidTargetL = lidTargetR = 0.06f;
  } else if (_miKind == MI_HEAD_TILT) {
    miTilt = miEnv;     // applied as opposed vertical eye offsets below
  }

  if (blinking && (persona == 1 || persona == 2)) lidTargetL = lidTargetR = 0.08f;
  float gazeTarget = (glancing && (persona == 1 || persona == 2)) ? glanceDir * 8.0f : 0.0f;
  if (persona == 2) gazeTarget = busySaccade;
  if (_miKind == MI_ORB_CHASE || _miKind == MI_LOOK_AT_YOU) gazeTarget = miGaze;
  // An explicit target wins over the ambient drift, and reaches further —
  // a deliberate look should be visibly bigger than idle wandering.
  if (opt.gazeBias != 0.0f) gazeTarget = opt.gazeBias * 18.0f;

  // Lids close fast, open slower — the asymmetry is what reads as alive.
  lidL = _easeToward(lidL, lidTargetL, lidTargetL < lidL ? 26.0f : 11.0f, dt);
  lidR = _easeToward(lidR, lidTargetR, lidTargetR < lidR ? 26.0f : 11.0f, dt);
  lift = _easeToward(lift, liftTarget, 14.0f, dt);
  boost = _easeToward(boost, boostTarget, 18.0f, dt);
  gaze = _easeToward(gaze, gazeTarget, 8.0f, dt);

  uint16_t accent = opt.color ? opt.color : buddySpeciesColor();
  const uint16_t BG = opt.bg;
  const uint16_t PINK = 0xFB56;

  // Slow continuous whole-face bob: life at a glance plus constant
  // micro-motion for the AMOLED. Sleep breathes slower and deeper.
  float bobF = (persona == 0)
      ? 5.0f * sinf((float)now * (6.2832f / 4500.0f))
      : 4.0f * sinf((float)now * (6.2832f / 6000.0f));
  int bob = _px(bobF);

  // Ring the squish spring down toward rest. Higher frequency than the
  // card springs — a squish is a quick physical wobble, not a slide.
  _faceSquish.step(0.0f, 5.2f, 0.30f, dt);
  float sq = animClamp(_faceSquish.pos, -0.9f, 0.9f);

  const int cx = HAL_W / 2;
  // Squish conserves rough area: the face flattens and widens, then rings
  // back through the other side. Everything shifts down slightly with it,
  // as if the boop pressed it into the desk.
  int eyeY = 92 + bob + _px(lift) - opt.lift + _px(sq * 7.0f) + opt.dangleY
             + _px(busyNod);
  int eyeDX = _px(76 * (1.0f + sq * 0.10f));
  int mouthY = 144 + bob - opt.lift + _px(sq * 4.0f) + opt.dangleY + _px(busyNod);
  int gazeI = _px(gaze) + opt.dangleX + _px(miWiggle);
  // Head tilt as opposed vertical eye offsets: rotating the whole sprite
  // would cost a resample every frame, and at this geometry the eyes going
  // opposite ways reads as a tilt anyway.
  int tiltL = _px(miTilt * 7.0f), tiltR = _px(miTilt * -7.0f);
  // Stroke weight (§2.1.2): light shapes on a dark field optically expand
  // (halation), dark shapes on a light field don't. Reusing the glow
  // geometry unchanged makes the ink face read heavy and clumsy, so every
  // filled dimension thins with the mood.
  const float wt = opt.weight * opt.scale;
  int eyeHL = _px((e.h * 2.0f * lidL + boost) * wt * (1.0f - sq * 0.30f));
  int eyeHR = _px((e.h * 2.0f * lidR + boost) * wt * (1.0f - sq * 0.30f));
  int eyeW = _px((e.w * 2.0f + (boost > 2.0f ? 4.0f : 0.0f)) * wt * (1.0f + sq * 0.22f));
  int eyeR = _px(e.r * 2 * wt);

  // The field is already painted (moodDrawField) — the face draws onto it.

  switch (persona) {
    case 0: {  // sleep — lids (peek eased via lidR), drifting z's
      _faceEye(cx - eyeDX, eyeY, eyeW, eyeHL, eyeR, accent);
      _faceEye(cx + eyeDX, eyeY, eyeW, eyeHR, eyeR, accent);
      spr.setTextSize(2);
      spr.setTextColor(accent, BG);
      for (int i = 0; i < 3; i++) {
        float ph = fmodf((float)now / 600.0f + i * 2.0f, 6.0f);
        spr.setCursor(cx + 104 + i * 20 + _px(ph * 2.0f), eyeY - 36 - _px(ph * 8.0f));
        spr.print(i == 1 ? "Z" : "z");
      }
      break;
    }
    case 2: {  // busy — half-lidded focus, flat mouth, working dots
      _faceEye(cx - eyeDX + gazeI, eyeY, eyeW, eyeHL, eyeR, accent);
      _faceEye(cx + eyeDX + gazeI, eyeY, eyeW, eyeHR, eyeR, accent);
      spr.fillSmoothRoundRect(cx - 16, mouthY, 32, 6, 3, accent);
      int active = (now / 350) % 3;
      for (int i = 0; i < 3; i++) {
        uint16_t c = (i == active) ? accent : (uint16_t)((accent >> 2) & 0x39E7);
        spr.fillSmoothCircle(cx + 40 + i * 18, mouthY + 3, 4, c);
      }
      // What the agent is actually doing, small and dim above the eyes —
      // the `activity` wire field finally rendered somewhere.
      spr.setTextSize(2);
      spr.setTextDatum(TC_DATUM);
      spr.setTextColor((uint16_t)((accent >> 1) & 0x7BEF), BG);
      spr.drawString(_faceActivityVerb(activity), cx, 24);
      spr.setTextDatum(TL_DATUM);
      break;
    }
    case 3: {  // attention — wide eyes raised toward the boop button
      // Tallest species (h=30*2) with full boost (+16) and lift (-12)
      // tops out just under the armed-prompt band (rows 0..39); the band
      // draws after the face, so it wins any overlap.
      _faceEye(cx - eyeDX, eyeY, eyeW, eyeHL, eyeR, accent);
      _faceEye(cx + eyeDX, eyeY, eyeW, eyeHR, eyeR, accent);
      spr.fillArc(cx, mouthY, 8, 14, 0, 360, accent);   // small "o"
      break;
    }
    case 4: {  // celebrate — happy arcs, big smile, falling confetti
      _faceEyeHappy(cx - eyeDX, eyeY, accent);
      _faceEyeHappy(cx + eyeDX, eyeY, accent);
      spr.fillArc(cx, mouthY - 12, 24, 32, 25, 155, accent);
      static const uint16_t CONF[5] = { 0xF800, 0x07E0, 0x001F, 0xFFE0, 0xF81F };
      for (int i = 0; i < 12; i++) {
        uint32_t h = _faceHash(i * 7919u);
        // Per-particle fall speed (120-220 px/s) so the rain has depth.
        float speed = 0.120f + (h % 50) * 0.002f;
        int px = (int)(h % (HAL_W - 3));
        // Full-height fall: the resting HUD is gone on this board, so
        // there's no longer a strip at the bottom to stop short of.
        int py = _px(fmodf(h / 331.0f + (float)now * speed, (float)(HAL_H - 3)));
        spr.fillRect(px, py, 3, 3, CONF[i % 5]);
      }
      break;
    }
    case 5: {  // dizzy — X eyes, continuous wobble
      int tilt = _px(5.0f * sinf((float)now * (6.2832f / 800.0f)));
      _faceEyeX(cx - eyeDX, eyeY + tilt, accent);
      _faceEyeX(cx + eyeDX, eyeY - tilt, accent);
      for (int i = 0; i < 4; i++) {
        spr.fillRect(cx - 24 + i * 12, mouthY + ((i & 1) ? 4 : 0), 12, 4, accent);
      }
      break;
    }
    case 6: {  // heart — heart eyes, blush, smile, drifting mini-hearts
      // Hearts track the finger too. Touch is what produces this face in
      // the first place, so not following the hand that's petting it would
      // be the one place the gaze conspicuously fails to work.
      _faceEyeHeart(cx - eyeDX + gazeI, eyeY, PINK, 1.0f + sq * 0.22f, 1.0f - sq * 0.30f);
      _faceEyeHeart(cx + eyeDX + gazeI, eyeY, PINK, 1.0f + sq * 0.22f, 1.0f - sq * 0.30f);
      spr.fillArc(cx, mouthY - 10, 20, 26, 25, 155, accent);
      spr.fillSmoothRoundRect(cx - eyeDX - 44 + gazeI, eyeY + 32, 26, 10, 5, PINK);
      spr.fillSmoothRoundRect(cx + eyeDX + 18 + gazeI, eyeY + 32, 26, 10, 5, PINK);
      // Little hearts rise past the cheeks while affection lasts — the
      // sustained-petting payoff. Deterministic per-slot phase (no rand).
      // Sizing note: this is a ~340 PPI panel — anything under ~25px reads
      // as a speck from arm's length (the first cut used r=4..6 and was
      // physically invisible). r=9..12 makes each heart ~3-4mm on glass.
      for (int i = 0; i < 4; i++) {
        uint32_t h = _faceHash(0xB005u + i * 7919u);
        float ph = fmodf((float)now / 1600.0f + (float)(h % 997) / 997.0f, 1.0f);
        int hx = ((i & 1) ? cx + eyeDX + 70 : cx - eyeDX - 70) +
                 (int)((h >> 8) % 20) - 10;
        int hy = eyeY + 64 - _px(ph * 140.0f);
        int r = 9 + i;
        if (hy < 20) continue;
        spr.fillSmoothCircle(hx - r + 1, hy - r / 2, r, PINK);
        spr.fillSmoothCircle(hx + r - 1, hy - r / 2, r, PINK);
        spr.fillTriangle(hx - 2 * r + 1, hy, hx + 2 * r - 1, hy,
                         hx, hy + 2 * r - 1, PINK);
      }
      break;
    }
    default: {  // idle — open eyes, blinks, glances, soft smile
      _faceEye(cx - eyeDX + gazeI, eyeY + tiltL, eyeW, eyeHL, eyeR, accent);
      _faceEye(cx + eyeDX + gazeI, eyeY + tiltR, eyeW, eyeHR, eyeR, accent);
      if (opt.yawn || miYawn) {
        // A yawn is a big open O, not a wider smile. Squashed slightly so
        // it reads as a mouth rather than a hole.
        spr.fillEllipse(cx, mouthY + 6, 20, 26, accent);
        spr.fillEllipse(cx, mouthY + 8, 13, 18, BG);
      } else {
        spr.fillArc(cx, mouthY - 10, 16, 22, 30, 150, accent);
      }
      break;
    }
  }
}
