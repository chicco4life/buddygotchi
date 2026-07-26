#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "buddy.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp).
//
// Face-first renderer for the landscape board: the screen IS the
// character's face — big glowing eyes on pure black (black pixels are off
// on the AMOLED, which is both the product look and the burn-in strategy).
// There is deliberately no mouth: the eyes carry every state. Species
// differ by accent color (their procedural bodyColor); the ASCII body art
// stays the M5/portrait renderer.
//
// faceTick(persona) uses the same 0..6 persona indices as the Species
// state table: 0=sleep 1=idle 2=busy 3=attention 4=celebrate 5=dizzy
// 6=affection. It redraws every frame; the present throttle in halPresent
// decides what reaches glass.

extern BuddyCanvas spr;

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

// Face geometry. The product idea is that this screen IS the face of a
// creature with a body somewhere behind it, so the face wants to fill the
// panel rather than float in the middle of it. FACE_K scales the per-species
// eye table (which is in the original 135x240-era logical units) up to
// native panel pixels; the first native-res cut used a flat 2.0 and left the
// face reading as a small mask on a large black field.
static const float FACE_K = 3.10f;
// Eye centre line. With no mouth the eyes ARE the composition, so they sit
// centred in the panel above the bottom status strip rather than in the
// upper third where the mouth used to balance them.
static const int   FACE_EYE_Y   = 126;
static const int   FACE_EYE_DX  = 106;   // eye separation from centre

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
  spr.fillArc(cx, cy + 16, 27, 37, 180, 360, c);         // ∩ arc
}

// Dizzy eyes: an Archimedean spiral, drawn as overlapping dots so it reads
// as a stroke without needing a polyline primitive. `grow` 0..1 morphs it in
// from nothing (radius scales), and `rot` spins it — the spin is what sells
// dizzy, so it keeps turning for as long as the state lasts.
static void _faceEyeSpiral(int cx, int cy, float grow, float rot, uint16_t c) {
  if (grow <= 0.02f) return;
  // Sampled uniformly in ARC LENGTH, not in angle. An Archimedean spiral's
  // radius grows with t, so a uniform-t sweep bunches samples near the
  // centre (the innermost were spaced well under a pixel and just redrew
  // the same disc) and spreads them at the rim, where the gaps actually
  // show. Because arc length grows as t^2, t = TURNS*sqrt(u) spaces the
  // dots evenly. Total arc is ~290px, so N sets the gap directly: 52 gives
  // 5.6px against an 8px dot and the stroke visibly scallops; 68 gives
  // 4.3px and reads smooth, still a third fewer fills than the uniform-t
  // 104 it replaces.
  const int N = 68;
  const float TURNS = 4.2f * 3.14159265f;
  int thick = animPx(2.5f + 1.5f * grow);
  for (int i = 0; i <= N; i++) {
    float t = TURNS * sqrtf((float)i / (float)N);
    float r = 44.0f * grow * (t / TURNS);
    spr.fillSmoothCircle(cx + animPx(cosf(t + rot) * r), cy + animPx(sinf(t + rot) * r),
                         thick, c);
  }
}

// A furrowed brow: one short angled stroke above an eye, inner end dragged
// down. Only ever drawn while actually furrowing — the face has no brows at
// rest, so this appears with the effort and leaves with it rather than being
// a permanent feature that flattens.
//
// `side` is the direction from the OUTER end toward the inner one in x: +1
// for the left eye, -1 for the right. Same overlapping-dots stroke as the
// arch and the spiral, so it inherits their anti-aliasing.
static void _faceBrow(int cx, int cy, int w, int side, float amt, uint16_t c) {
  if (amt <= 0.02f) return;
  // 13 samples across ~63px is ~5px apart against a dot up to 10px wide, so
  // the stroke is solid. At 7 it came out visibly beaded.
  const int N = 13;
  int thick = animPx(3.0f + 2.0f * amt);
  float drop = 16.0f * amt;
  for (int i = 0; i <= N; i++) {
    float u = (float)i / (float)N;                 // 0 = outer, 1 = inner
    spr.fillSmoothCircle(cx + side * animPx((u - 0.5f) * (float)w),
                         cy + animPx(u * drop), thick, c);
  }
}

// The happy "^" eye. A parabolic arch drawn as overlapping dots, where
// `rise` is the whole morph: 0 is a flat closed lid, and raising it arches
// the same stroke upward. That means going happy is just the existing lid
// animation plus a rising arch — the transition eases in and out for free,
// the same way waking from sleep does, instead of cutting between two
// different eye drawings.
static void _faceEyeArch(int cx, int cy, int w, float rise, int thick, uint16_t c) {
  // 16, not fewer. Sampling is uniform in X but the parabola's arc length
  // exceeds its chord, so the dots spread out toward the ends where the
  // curve is steepest — dropping to 8 left the arch visibly beaded. At 34
  // fills a frame this is not worth trading appearance for.
  const int N = 16;
  for (int i = 0; i <= N; i++) {
    float u = (float)i / (float)N * 2.0f - 1.0f;      // -1..1
    spr.fillSmoothCircle(cx + animPx(u * (float)w * 0.5f),
                         cy - animPx(rise * (1.0f - u * u)),
                         thick, c);
  }
}

// Exclusive expression channels — the lids and the horizontal gaze — resolve
// by DECLARED RANK rather than by which line happens to run last.
//
// Both used to be plain locals assigned from a dozen places, so "which
// expression outranks which" lived entirely in statement order. Every new
// channel then had to hand-code guards restating its neighbours' business
// (`persona != 0 && persona != 3`, `opt.drowse <= 0.0f`, `!= 0.0f` used as
// an activation test), and one channel had already been silently dead for
// it: a `case 2` busy-focus lid value that every busy beat overwrote.
//
// A bid keeps the winner explicit. Adding an expression now means choosing
// its rank, not finding the right line to sit on.
struct FaceBid {
  float value = 0.0f;
  int   rank = -1;
  void bid(int r, float v) { if (r >= rank) { rank = r; value = v; } }
  float get(float fallback) const { return rank >= 0 ? value : fallback; }
};

// Low to high. Blink beats a micro-idle (you can blink mid-yawn) but loses
// to the drift back to sleep, which owns the lids all the way down.
enum FaceLidRank : int {
  LR_BASE = 0,   // the persona's own resting lids
  LR_PET,        // a finger on the glass
  LR_BUSY,       // working beats
  LR_MICRO,      // micro-idles
  LR_YAWN,       // the morning stretch's yawn
  LR_BLINK,      // ordinary blinking
  LR_DROWSE      // falling asleep
};

// Low to high. A finger outranks anything ambient; the descent outranks
// even that, because the eyes are closing.
enum FaceGazeRank : int {
  GR_DRIFT = 0,  // ambient idle glancing
  GR_BUSY,       // saccades / sweeps
  GR_MICRO,      // orb-chase, look-at-you
  GR_TOUCH,      // finger on the glass, or a newly spawned session
  GR_DROWSE      // the look-away descent
};

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
  // Whether gazeBias means anything this frame. Without it, "look dead
  // centre" and "nothing to look at" are the same value.
  bool     hasGazeTarget = false;
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
  // 0..1 through the drift back to sleep. A boop wakes the buddy properly
  // rather than for a single blink, so it needs a way back DOWN — this is
  // that descent, and drowseKind picks how it does it.
  float    drowse = 0.0f;
  uint8_t  drowseKind = 0;
};

// --- Going back to sleep ---------------------------------------------------
// Waking up used to be the only half of the transaction: a boop cracked an
// eye, then the face snapped back to sleeping lids the instant the reaction
// timer expired. Falling asleep is at least as expressive as waking up, so
// the descent gets the same treatment the boop reactions got — several
// variants, chosen at random, all ~1.6s.
enum DrowseKind : uint8_t {
  DK_SLOW_BLINK = 0,   // lids just drift shut
  DK_NOD_OFF,          // head dips, catches itself once, then goes
  DK_YAWN_OFF,         // one last yawn on the way down
  DK_LOOK_AWAY,        // glances off to one side, then settles
  DK_COUNT
};

inline const char* faceDrowseName(uint8_t k) {
  switch (k) {
    case DK_SLOW_BLINK: return "slow-blink";
    case DK_NOD_OFF:    return "nod-off";
    case DK_YAWN_OFF:   return "yawn-off";
    case DK_LOOK_AWAY:  return "look-away";
    default:            return "none";
  }
}

// A boop wakes the buddy PROPERLY, not for a single blink: it stays awake
// for this long after the last attention, then drifts back down. Being
// poked and immediately re-shutting your eyes reads as a screensaver
// dismissing an event; staying up for a few seconds reads as a creature
// that noticed you.
static const uint32_t FACE_ROUSE_MS  = 5000;
static const uint32_t FACE_DROWSE_MS = 1600;   // the descent itself

static uint32_t _rousedUntil = 0;
static uint32_t _drowseUntil = 0;
static uint8_t  _drowseKind = 0;

// Any affection: restart the clock.
inline void faceRouse(uint32_t now) {
  _rousedUntil = now + FACE_ROUSE_MS;
  _drowseUntil = _rousedUntil + FACE_DROWSE_MS;
}

inline void faceRouseClear() { _rousedUntil = 0; _drowseUntil = 0; }
inline bool faceRoused(uint32_t now) { return (int32_t)(_rousedUntil - now) > 0; }

// Advance the descent. Called once per frame while the buddy would
// otherwise be asleep; picks how it goes down on the edge where the rouse
// lapses — exactly once, so the no-immediate-repeat rule compares against
// the PREVIOUS DESCENT rather than against the previous frame.
inline void faceRouseTick(uint32_t now) {
  static bool wasRoused = false;
  bool roused = faceRoused(now);
  if (!roused && wasRoused) {
    uint8_t pick = (uint8_t)(animHash(now ^ 0x51EED0u) % DK_COUNT);
    if (pick == _drowseKind) pick = (uint8_t)((pick + 1u) % DK_COUNT);
    _drowseKind = pick;
  }
  wasRoused = roused;
}

// True while the buddy should render awake despite a sleeping heartbeat —
// covers both the rouse and the descent that follows it.
inline bool faceAwake(uint32_t now) {
  return faceRoused(now) || (int32_t)(_drowseUntil - now) > 0;
}

// 0 while awake, ramping to 1 across the descent.
inline float faceDrowse01(uint32_t now) {
  if (faceRoused(now) || (int32_t)(_drowseUntil - now) <= 0) return 0.0f;
  return 1.0f - (float)(_drowseUntil - now) / (float)FACE_DROWSE_MS;
}

inline uint8_t faceDrowseKind() { return _drowseKind; }

// The descent currently running, or "none". For `state`.
inline const char* faceDrowseNow(uint32_t now) {
  return faceDrowse01(now) > 0.0f ? faceDrowseName(_drowseKind) : "none";
}

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

// --- Boop reactions --------------------------------------------------------
// Being booped awake used to have exactly one answer: crack the right eye
// open. One canned response to the product's most-repeated interaction is
// the fastest way to make a pet feel like a device, so a boop now picks one
// of several at random. They're all the same shape — a ~1.4s beat layered
// over whatever the face was doing — and they differ in personality, not in
// mechanism.
enum BoopReact : uint8_t {
  BR_PEEK = 0,     // one eye cracks open, unimpressed
  BR_SHAKE,        // shakes itself awake and looks alert
  BR_STARTLE,      // both eyes snap wide, then settle
  BR_YAWN,         // opens slowly with a big yawn
  BR_SQUINT,       // opens straight into a happy squint
  BR_COUNT
};
static const uint32_t BOOP_REACT_LEN_MS = 1400;
static uint8_t  _boopReact = BR_PEEK;
static uint32_t _boopReactAt = 0;

inline const char* faceBoopReactName() {
  switch (_boopReact) {
    case BR_PEEK:    return "peek";
    case BR_SHAKE:   return "shake";
    case BR_STARTLE: return "startle";
    case BR_YAWN:    return "yawn";
    case BR_SQUINT:  return "squint";
    default:         return "none";
  }
}

// Pick a fresh reaction. Avoids repeating the previous one — with only five
// options a plain uniform draw repeats often enough to read as "it's stuck"
// rather than "it varies".
inline void faceBoopReact(uint32_t now) {
  uint8_t prev = _boopReact;
  uint8_t pick = (uint8_t)(animHash(now ^ 0xB00Fu) % BR_COUNT);
  if (pick == prev) pick = (uint8_t)((pick + 1u) % BR_COUNT);
  _boopReact = pick;
  _boopReactAt = now;
}

// Debug/HIL: force one, so a test doesn't have to boop until chance obliges.
inline void faceForceBoopReact(uint8_t kind, uint32_t now) {
  if (kind >= BR_COUNT) return;
  _boopReact = kind;
  _boopReactAt = now;
}

// Everything the draw half of the face needs, and nothing else.
//
// faceTick had grown to ~380 lines in which a dozen independent expression
// channels all funnelled into a handful of shared locals, and the draw
// switch at the bottom silently depended on whichever of them happened to
// be in scope. Naming that contract is the point: the compute half now has
// to say what it produces, and the draw half cannot reach for anything it
// wasn't given.
struct FacePose {
  uint8_t  persona = 1;
  uint32_t now = 0;
  int      cx = 0, eyeY = 0, eyeDX = 0, gazeI = 0;
  int      eyeW = 0, eyeHL = 0, eyeHR = 0, eyeR = 0;
  int      tiltL = 0, tiltR = 0;      // head tilt, as opposed eye offsets
  uint16_t accent = 0, bg = 0;
  float    sq = 0.0f;                 // boop squish, drives the arch scaling
  float    sleepy = 0.0f;             // z fade-in
  float    dizzyAmt = 0.0f, spiralRot = 0.0f;
  float    happyAmt = 0.0f;
  // Effort tell (busy only): 0 = no bead, else 0..1 through one bead's
  // swell-and-slide. sweatSide picks which temple it runs down.
  float    sweat01 = 0.0f;
  int      sweatSide = 1;
  float    brow = 0.0f;               // 0..1 furrow, eased
};

static void _faceComputePose(uint8_t persona, const char* activity, bool boopActive,
                             const FaceOpts& opt, FacePose& P) {
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
    uint32_t h = animHash(now);
    nextBlinkAt = now + 2600 + (h % 2200);
    if ((h & 7) == 0) nextBlinkAt = now + 420;   // occasional double-blink
  }
  if ((int32_t)(now - nextGlanceAt) >= 0) {
    glanceUntil = now + 900;
    glanceDir = (animHash(now) & 1) ? 1 : -1;
    nextGlanceAt = now + 5500 + (animHash(now ^ 0x9E37) % 4500);
  }
  bool blinking = (int32_t)(blinkUntil - now) > 0;
  bool glancing = (int32_t)(glanceUntil - now) > 0;

  // Micro-idle scheduling. Only while genuinely idle, and only once the
  // human has left it alone for a while.
  bool miAllowed = (persona == 1) && opt.sinceInteractionMs > MI_QUIET_MS;
  if (_miKind == MI_NONE) {
    if (_miNextAt == 0) _miNextAt = now + MI_SPACING_MS;
    if (miAllowed && (int32_t)(now - _miNextAt) >= 0) {
      uint32_t h = animHash(now ^ 0x1D1Eu);
      _miKind = (uint8_t)(MI_YAWN + (h % (MI_COUNT - 1)));
      _miStart = now;
      _miEnd = now + 1200 + (h % 800);      // each <= 2s
    }
  }
  if (_miKind != MI_NONE && ((int32_t)(now - _miEnd) >= 0 || (!miAllowed && !_miForced))) {
    _miKind = MI_NONE;
    _miForced = false;
    _miNextAt = now + MI_SPACING_MS + (animHash(now) % 45000);
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
  FaceBid lidL_b, lidR_b;
  float liftTarget = 0.0f, boostTarget = 0.0f;
  switch (persona) {
    case 0: {  // sleep — a boop wakes it, differently each time
      float l = 0.10f, r = 0.10f;
      if (boopActive) {
        switch (_boopReact) {
          case BR_SHAKE:   l = r = 0.88f; break;
          case BR_STARTLE: l = r = 1.0f; boostTarget = 12.0f; break;
          case BR_YAWN:    l = r = 0.52f; break;
          case BR_SQUINT:  l = r = 0.34f; break;
          default:         r = 0.75f; break;   // BR_PEEK cracks one eye
        }
      }
      lidL_b.bid(LR_BASE, l);
      lidR_b.bid(LR_BASE, r);
      break;
    }
    case 3: liftTarget = -12.0f; boostTarget = 16.0f; break;    // attention
    default: break;
  }
  // Being petted settles the lids into a contented half-blink. Sleep keeps
  // its own peek behaviour, and attention must stay wide — a decision is
  // owed and the buddy is not relaxing about it (doctrine #12).
  // The persona test is a real rule, not a priority artifact: sleep keeps
  // its own peek and attention stays wide regardless of who is touching it.
  if (opt.petting && persona != 0 && persona != 3) {
    lidL_b.bid(LR_PET, 0.66f);
    lidR_b.bid(LR_PET, 0.66f);
  }
  // Holding a gift out for you: eyes open a little wider and lift, the
  // face-first equivalent of raised brows. Deliberately small — the gold
  // orb is the signal, this is the tell you notice second.
  if (opt.expectant && (persona == 1 || persona == 2)) {
    liftTarget -= 4.0f;
    boostTarget += 5.0f;
  }
  // The brow furrows on the beats that are meant to be hard and relaxes on
  // the ones that aren't, eased so it never snaps. Held slightly while a
  // bead is out, so the two tells reinforce rather than fight.
  static float brow = 0.0f;
  float browTarget = 0.0f;

  // Busy theater (§11). Five working beats on a ~2.8s clock.
  //
  // The first cut varied mostly LID HEIGHT between beats, which is exactly
  // what blinking is — so a working buddy read as a buddy blinking rather
  // than a buddy working. Motion is the dominant channel now: where the
  // eyes GO distinguishes the beats, and lids only move where narrowing is
  // part of the character (focus, effort). The activity verb offsets the
  // sequence rather than branching it, so reading and testing run the same
  // vocabulary in a different order and still feel unalike.
  float busyNod = 0.0f;       // vertical gaze, px
  float busySaccade = 0.0f;   // horizontal gaze, px
  if (persona == 2) {
    const char* a = activity ? activity : "";
    uint32_t off = 0;
    float squint = 0.0f;
    float rate = 2800.0f;
    if (strcmp(a, "read") == 0 || strcmp(a, "web") == 0) { off = 0; rate = 2200.0f; }
    else if (strcmp(a, "verify") == 0) { off = 2; squint = 0.16f; }
    else if (strcmp(a, "write") == 0)  { off = 3; }
    else if (strcmp(a, "shell") == 0)  { off = 1; }
    else                               { off = 4; }

    uint32_t beat = ((uint32_t)(now / (uint32_t)rate) + off) % 5;
    float bp = fmodf((float)now / rate, 1.0f);      // 0..1 within the beat
    switch (beat) {
      case 0: {   // scanning — discrete left-to-right saccades, then reset
        int step = (int)(bp * 4.0f);
        busySaccade = -14.0f + (float)step * 9.0f;
        if (bp > 0.92f) busySaccade = -14.0f;
        lidL_b.bid(LR_BUSY, 0.82f - squint); lidR_b.bid(LR_BUSY, 0.82f - squint);
        break;
      }
      case 1:     // pondering — drifts up and away, holds there
        busySaccade = -11.0f;
        busyNod = -7.0f;
        lidL_b.bid(LR_BUSY, 0.90f - squint); lidR_b.bid(LR_BUSY, 0.90f - squint);
        break;
      case 2:     // focused — dead centre, narrowed, with a strained tremor
        browTarget = 1.0f;
        // Faster and slightly wider than a drift: at this frequency it
        // reads as effort rather than as wandering.
        busySaccade = 2.1f * sinf((float)now * (ANIM_TAU / 190.0f));
        lidL_b.bid(LR_BUSY, 0.44f - squint * 0.5f); lidR_b.bid(LR_BUSY, 0.44f - squint * 0.5f);
        break;
      case 3: {   // checking — glances down, holds, comes back up
        browTarget = 0.6f;
        float d = (bp < 0.25f) ? (bp / 0.25f)
                : (bp < 0.70f) ? 1.0f
                : (1.0f - (bp - 0.70f) / 0.30f);
        busyNod = 9.0f * animClamp(d, 0.0f, 1.0f);
        lidL_b.bid(LR_BUSY, 0.74f - squint); lidR_b.bid(LR_BUSY, 0.74f - squint);
        break;
      }
      default:    // sweeping — one slow continuous pass across
        busySaccade = 13.0f * sinf(bp * ANIM_TAU);
        lidL_b.bid(LR_BUSY, 0.86f - squint); lidR_b.bid(LR_BUSY, 0.86f - squint);
        break;
    }
  }

  // Effort tell. A working face reads as "eyes doing something"; one bead of
  // sweat reads as "this is hard". Deliberately rare and singular — the
  // decorative particle systems (confetti, drifting hearts) came out of this
  // renderer on purpose, and a constant drip would be one of those. This is
  // an expression element attached to the face, like a blush.
  //
  // Deterministic off `now`, so a HIL screenshot of a given millisecond is
  // reproducible.
  float sweat01 = 0.0f;
  int   sweatSide = 1;
  if (persona == 2) {
    // 5s apart rather than 7: at a 21% duty cycle the bead was easy to
    // miss entirely, which makes it decoration rather than a signal.
    const uint32_t SWEAT_CYCLE = 5000, SWEAT_LEN = 1800;
    uint32_t sph = now % SWEAT_CYCLE;
    if (sph < SWEAT_LEN) {
      sweat01 = (float)sph / (float)SWEAT_LEN;
      sweatSide = ((now / SWEAT_CYCLE) & 1) ? 1 : -1;
    }
  }
  if (sweat01 > 0.0f && browTarget < 0.55f) browTarget = 0.55f;

  brow = animEase(brow, (persona == 2) ? browTarget : 0.0f, 4.0f, dt);

  // Micro-idle effects. Each is small and each is over in under two
  // seconds; the point is that you catch them out of the corner of an eye.
  float miTilt = 0.0f, miWiggle = 0.0f, miGaze = 0.0f;
  bool  miYawn = false;
  if (_miKind == MI_YAWN) {
    miYawn = miT > 0.2f && miT < 0.8f;
    if (miYawn) { lidL_b.bid(LR_MICRO, 0.30f); lidR_b.bid(LR_MICRO, 0.30f); }
  } else if (_miKind == MI_ORB_CHASE) {
    // Eyes follow something all the way around, once.
    miGaze = 17.0f * sinf(miT * ANIM_TAU);
  } else if (_miKind == MI_WIGGLE) {
    miWiggle = 9.0f * miEnv * sinf(miT * ANIM_TAU * 2.5f);
  } else if (_miKind == MI_LOOK_AT_YOU) {
    // Dead centre, one slow deliberate blink. The stillness is the effect.
    miGaze = 0.0f;
    if (miT > 0.45f && miT < 0.62f) { lidL_b.bid(LR_MICRO, 0.06f); lidR_b.bid(LR_MICRO, 0.06f); }
  } else if (_miKind == MI_HEAD_TILT) {
    miTilt = miEnv;     // applied as opposed vertical eye offsets below
  }

  // Boop reaction clock. BR_SHAKE is the only one that moves the whole head
  // rather than just the lids — a shake is a body motion, so it offsets the
  // whole face instead of sliding the gaze inside a still one.
  float brShake = 0.0f;
  if (boopActive && _boopReactAt != 0 && (now - _boopReactAt) < BOOP_REACT_LEN_MS) {
    float rp = (float)(now - _boopReactAt) / (float)BOOP_REACT_LEN_MS;
    float env = sinf(rp * 3.14159265f);
    if (_boopReact == BR_SHAKE) brShake = 13.0f * env * sinf(rp * ANIM_TAU * 3.0f);
  }

  // Drifting back to sleep. Runs on the IDLE face (main.cpp keeps the buddy
  // awake through the descent), so the lids close from wherever they were
  // rather than the face cutting to a sleeping one.
  float dwGaze = 0.0f, dwNod = 0.0f;
  bool  dwYawn = false;
  // With no mouth on the face, a yawn is entirely an eye gesture: the lids
  // squeeze most of the way shut and open again.
  if (opt.yawn) { lidL_b.bid(LR_YAWN, 0.24f); lidR_b.bid(LR_YAWN, 0.24f); }
  if (opt.drowse > 0.0f) {
    float d = animClamp(opt.drowse, 0.0f, 1.0f);
    float shut = 1.0f - d;                       // 1 awake -> 0 shut
    switch (opt.drowseKind) {
      case DK_NOD_OFF:
        // Dips, jerks back up once as if catching itself, then goes.
        dwNod = 16.0f * d * d;
        if (d > 0.45f && d < 0.62f) { dwNod *= 0.35f; shut = 0.55f; }
        break;
      case DK_YAWN_OFF:
        dwYawn = d > 0.10f && d < 0.55f;
        if (dwYawn) shut = 0.45f;                // eyes squeeze during a yawn
        break;
      case DK_LOOK_AWAY:
        dwGaze = 15.0f * sinf(d * 3.14159265f);
        break;
      default:
        break;                                   // DK_SLOW_BLINK: just shut
    }
    float target = 0.10f + 0.90f * animClamp(shut, 0.0f, 1.0f);
    lidL_b.bid(LR_DROWSE, target);
    lidR_b.bid(LR_DROWSE, target);
  }

  if (blinking && (persona == 1 || persona == 2)) {
    lidL_b.bid(LR_BLINK, 0.08f);
    lidR_b.bid(LR_BLINK, 0.08f);
  }
  float lidTargetL = lidL_b.get(1.0f);
  float lidTargetR = lidR_b.get(1.0f);

  FaceBid gaze_b;
  if (glancing && (persona == 1 || persona == 2)) gaze_b.bid(GR_DRIFT, glanceDir * 8.0f);
  if (persona == 2) gaze_b.bid(GR_BUSY, busySaccade);
  if (_miKind == MI_ORB_CHASE || _miKind == MI_LOOK_AT_YOU) gaze_b.bid(GR_MICRO, miGaze);
  // An explicit target wins over the ambient drift, and reaches further —
  // a deliberate look should be visibly bigger than idle wandering.
  if (opt.hasGazeTarget) gaze_b.bid(GR_TOUCH, opt.gazeBias * 18.0f);
  if (opt.drowseKind == DK_LOOK_AWAY && opt.drowse > 0.0f) gaze_b.bid(GR_DROWSE, dwGaze);
  float gazeTarget = gaze_b.get(0.0f);

  // Lids close fast, open slower — the asymmetry is what reads as alive.
  lidL = animEase(lidL, lidTargetL, lidTargetL < lidL ? 26.0f : 11.0f, dt);
  lidR = animEase(lidR, lidTargetR, lidTargetR < lidR ? 26.0f : 11.0f, dt);
  lift = animEase(lift, liftTarget, 14.0f, dt);
  boost = animEase(boost, boostTarget, 18.0f, dt);
  gaze = animEase(gaze, gazeTarget, 8.0f, dt);

  uint16_t accent = opt.color ? opt.color : buddySpeciesColor();
  const uint16_t BG = opt.bg;

  // Slow continuous whole-face bob: life at a glance plus constant
  // micro-motion for the AMOLED. Sleep breathes slower and deeper.
  //
  // The PHASE is integrated rather than derived from `now`, and the
  // amplitude and period are eased. Computing sin(now * 2pi/T) directly
  // means changing T also teleports the phase, so falling asleep (T 6000 ->
  // 4500, amp 4 -> 5) snapped the whole face vertically at the instant the
  // persona flipped — the visible hitch between "closing eyes" and
  // "asleep". Integrating dt keeps the wave continuous across the change.
  static float bobPhase = 0.0f;
  static float bobAmp = 4.0f;
  static float bobPeriod = 6.0f;          // seconds
  bobAmp = animEase(bobAmp, (persona == 0) ? 5.0f : 4.0f, 2.5f, dt);
  bobPeriod = animEase(bobPeriod, (persona == 0) ? 4.5f : 6.0f, 2.5f, dt);
  bobPhase += dt * ANIM_TAU / bobPeriod;
  if (bobPhase > ANIM_TAU) bobPhase -= ANIM_TAU;
  int bob = animPx(bobAmp * sinf(bobPhase));

  // How asleep the face is, eased. The z's fade in with it instead of
  // popping on at full brightness the moment the persona changes.
  static float sleepy = 0.0f;
  sleepy = animEase(sleepy, (persona == 0) ? 1.0f : 0.0f, 4.0f, dt);

  // Two eased morphs so dizzy and happy arrive and leave gracefully rather
  // than the renderer cutting between eye drawings. Both are driven purely
  // by easing the SHAPE, which is why they need no keyframes: the normal eye
  // shrinks out as the new shape grows in, over the same window.
  static float dizzyAmt = 0.0f, happyAmt = 0.0f, spiralRot = 0.0f;
  dizzyAmt = animEase(dizzyAmt, (persona == 5) ? 1.0f : 0.0f, 5.0f, dt);
  happyAmt = animEase(happyAmt, (persona == 6) ? 1.0f : 0.0f, 6.5f, dt);
  spiralRot += dt * 2.6f;                       // the spin is what sells dizzy
  if (spiralRot > ANIM_TAU) spiralRot -= ANIM_TAU;

  // Ring the squish spring down toward rest. Higher frequency than the
  // card springs — a squish is a quick physical wobble, not a slide.
  _faceSquish.step(0.0f, 5.2f, 0.30f, dt);
  float sq = animClamp(_faceSquish.pos, -0.9f, 0.9f);

  const int cx = HAL_W / 2;
  // Squish conserves rough area: the face flattens and widens, then rings
  // back through the other side. Everything shifts down slightly with it,
  // as if the boop pressed it into the desk.
  int eyeY = FACE_EYE_Y + bob + animPx(lift) - opt.lift + animPx(sq * 7.0f) + opt.dangleY
             + animPx(busyNod) + animPx(dwNod);
  int eyeDX = animPx(FACE_EYE_DX * (1.0f + sq * 0.10f));
  int headX = animPx(brShake);
  int gazeI = animPx(gaze) + opt.dangleX + animPx(miWiggle) + headX;
  // Head tilt as opposed vertical eye offsets: rotating the whole sprite
  // would cost a resample every frame, and at this geometry the eyes going
  // opposite ways reads as a tilt anyway.
  int tiltL = animPx(miTilt * 7.0f), tiltR = animPx(miTilt * -7.0f);
  // Stroke weight (§2.1.2): light shapes on a dark field optically expand
  // (halation), dark shapes on a light field don't. Reusing the glow
  // geometry unchanged makes the ink face read heavy and clumsy, so every
  // filled dimension thins with the mood.
  const float wt = opt.weight * opt.scale;
  int eyeHL = animPx((e.h * FACE_K * lidL + boost) * wt * (1.0f - sq * 0.30f));
  int eyeHR = animPx((e.h * FACE_K * lidR + boost) * wt * (1.0f - sq * 0.30f));
  int eyeW = animPx((e.w * FACE_K + (boost > 2.0f ? 5.0f : 0.0f)) * wt * (1.0f + sq * 0.22f));
  int eyeR = animPx(e.r * FACE_K * wt);

  P.persona = persona;
  P.now = now;
  P.cx = cx;          P.eyeY = eyeY;    P.eyeDX = eyeDX;  P.gazeI = gazeI;
  P.eyeW = eyeW;      P.eyeHL = eyeHL;  P.eyeHR = eyeHR;  P.eyeR = eyeR;
  P.tiltL = tiltL;    P.tiltR = tiltR;
  P.accent = accent;  P.bg = BG;
  P.sq = sq;          P.sleepy = sleepy;
  P.dizzyAmt = dizzyAmt;  P.spiralRot = spiralRot;  P.happyAmt = happyAmt;
  P.sweat01 = sweat01;    P.sweatSide = sweatSide;
  P.brow = brow;
}

// The field is already painted (moodDrawField) — the face draws onto it.
static void _faceDrawPose(const FacePose& P) {
  switch (P.persona) {
    case 0: {  // sleep — lids, drifting z's, and the boop reactions
      // P.gazeI, not headX: every other state draws with the full horizontal
      // offset, so using a different one here snapped the eyes sideways
      // whenever the gaze hadn't finished easing back to centre — which is
      // exactly the case at the end of the look-away descent.
      _faceEye(P.cx - P.eyeDX + P.gazeI, P.eyeY, P.eyeW, P.eyeHL, P.eyeR, P.accent);
      _faceEye(P.cx + P.eyeDX + P.gazeI, P.eyeY, P.eyeW, P.eyeHR, P.eyeR, P.accent);
      if (P.sleepy > 0.05f) {
        spr.setTextSize(2);
        spr.setTextColor(animMix(P.bg, P.accent, P.sleepy), P.bg);
        for (int i = 0; i < 3; i++) {
          float ph = fmodf((float)P.now / 600.0f + i * 2.0f, 6.0f);
          spr.setCursor(P.cx + 104 + i * 20 + animPx(ph * 2.0f), P.eyeY - 36 - animPx(ph * 8.0f));
          spr.print(i == 1 ? "Z" : "z");
        }
      }
      break;
    }
    case 2: {  // busy — the thinking beats drive the eyes; no dots
      _faceEye(P.cx - P.eyeDX + P.gazeI, P.eyeY, P.eyeW, P.eyeHL, P.eyeR, P.accent);
      _faceEye(P.cx + P.eyeDX + P.gazeI, P.eyeY, P.eyeW, P.eyeHR, P.eyeR, P.accent);
      if (P.brow > 0.02f) {
        // Sits clear of the eye: during the focused beat the lids are a flat
        // squint, and a brow tight against them reads as one thick shape.
        int browY = P.eyeY - P.eyeHL / 2 - animPx(28.0f - 5.0f * P.brow);
        int bw = animPx(P.eyeW * 0.92f);
        _faceBrow(P.cx - P.eyeDX + P.gazeI, browY, bw, +1, P.brow, P.accent);
        _faceBrow(P.cx + P.eyeDX + P.gazeI, browY, bw, -1, P.brow, P.accent);
      }
      if (P.sweat01 > 0.0f) {
        // Swells at the temple for the first third, then runs down and
        // shrinks out. Teardrop-shaped (bead plus a point) because a plain
        // circle beside the eye reads as a stray dot.
        float t = P.sweat01;
        float grow  = t < 0.30f ? (t / 0.30f) : 1.0f;
        float slide = t < 0.30f ? 0.0f : (t - 0.30f) / 0.70f;
        int r = animPx((3.4f + 5.2f * grow) * (1.0f - slide * 0.55f));
        if (r > 0) {
          int bx = P.cx + P.sweatSide * (P.eyeDX + P.eyeW / 2 + 21);
          int by = P.eyeY - P.eyeHL / 2 + animPx(slide * 58.0f);
          spr.fillSmoothCircle(bx, by, r, P.accent);
          if (r >= 3) {
            spr.fillTriangle(bx - r + 1, by - r + 1, bx + r - 1, by - r + 1,
                             bx, by - r - r, P.accent);
          }
        }
      }
      break;
    }
    case 3: {  // attention — wide eyes raised toward the boop button
      // Raised toward the crown button, which is the affordance being
      // asked for. The approval card rises from the BOTTOM edge (§7), so
      // there is nothing above to collide with — the old comment here
      // still described a top band that only the M5 portrait path draws.
      _faceEye(P.cx - P.eyeDX, P.eyeY, P.eyeW, P.eyeHL, P.eyeR, P.accent);
      _faceEye(P.cx + P.eyeDX, P.eyeY, P.eyeW, P.eyeHR, P.eyeR, P.accent);
      break;
    }
    case 4: {  // celebrate — happy arc eyes, nothing thrown
      _faceEyeHappy(P.cx - P.eyeDX, P.eyeY, P.accent);
      _faceEyeHappy(P.cx + P.eyeDX, P.eyeY, P.accent);
      break;
    }
    case 5: {  // dizzy — spiral eyes, counter-rotating, on a black field
      int tilt = animPx(7.0f * P.dizzyAmt * sinf((float)P.now * (ANIM_TAU / 800.0f)));
      // The normal eye shrinks away as the spiral winds in, so entering and
      // leaving dizzy is a morph rather than a swap.
      // Threshold above _faceEye's closed-lid cutoff (h<=10 draws a fixed
      // 8px bar): a shrinking eye must vanish, not collapse into a lid, or
      // the spiral ends up with a stripe through it.
      int fadeH = animPx(P.eyeHL * (1.0f - P.dizzyAmt));
      if (fadeH > 11) {
        _faceEye(P.cx - P.eyeDX, P.eyeY + tilt, P.eyeW, fadeH, P.eyeR, P.accent);
        _faceEye(P.cx + P.eyeDX, P.eyeY - tilt, P.eyeW, fadeH, P.eyeR, P.accent);
      }
      // Opposite spin per eye: same-direction spirals read as a pattern,
      // counter-rotating ones read as not being able to focus.
      _faceEyeSpiral(P.cx - P.eyeDX, P.eyeY + tilt, P.dizzyAmt,  P.spiralRot, P.accent);
      _faceEyeSpiral(P.cx + P.eyeDX, P.eyeY - tilt, P.dizzyAmt, -P.spiralRot, P.accent);
      break;
    }
    case 6: {  // affection — a happy "^ ^", morphed in from the open eye
      // The arch IS the closed lid with a rise on it, so the transition is
      // the lid easing shut plus the rise growing. Hearts were a separate
      // drawing that had to be cut to; this one arrives.
      int openH = animPx(P.eyeHL * (1.0f - P.happyAmt));
      if (openH > 11) {          // same closed-lid cutoff as above
        _faceEye(P.cx - P.eyeDX + P.gazeI, P.eyeY, P.eyeW, openH, P.eyeR, P.accent);
        _faceEye(P.cx + P.eyeDX + P.gazeI, P.eyeY, P.eyeW, openH, P.eyeR, P.accent);
      }
      if (P.happyAmt > 0.02f) {
        int w = animPx(P.eyeW * (0.86f + 0.14f * P.happyAmt) * (1.0f + P.sq * 0.22f));
        float rise = 26.0f * P.happyAmt * (1.0f - P.sq * 0.30f);
        int thick = animPx(5.0f + 2.0f * P.happyAmt);
        _faceEyeArch(P.cx - P.eyeDX + P.gazeI, P.eyeY + animPx(rise * 0.5f), w, rise, thick, P.accent);
        _faceEyeArch(P.cx + P.eyeDX + P.gazeI, P.eyeY + animPx(rise * 0.5f), w, rise, thick, P.accent);
      }
      break;
    }
    default: {  // idle — open eyes, blinks, glances
      _faceEye(P.cx - P.eyeDX + P.gazeI, P.eyeY + P.tiltL, P.eyeW, P.eyeHL, P.eyeR, P.accent);
      _faceEye(P.cx + P.eyeDX + P.gazeI, P.eyeY + P.tiltR, P.eyeW, P.eyeHR, P.eyeR, P.accent);
      break;
    }
  }
}

// Compute this frame's pose, then draw it.
inline void faceTick(uint8_t persona, const char* activity, bool boopActive,
                     const FaceOpts& opt) {
  FacePose P;
  _faceComputePose(persona, activity, boopActive, opt, P);
  _faceDrawPose(P);
}
