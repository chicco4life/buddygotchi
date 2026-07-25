#include "hal/hal.h"
#include <esp_log.h>
#include <esp_system.h>
#if __has_include(<esp_mac.h>)
#include <esp_mac.h>   // esp_read_mac moved here in IDF5 (Arduino core 3.x)
#endif
#include "guard.h"
#include "ble_bridge.h"
#include "data.h"
SET_LOOP_TASK_STACK_SIZE(16384);
#include "buddy.h"

#ifndef FW_VERSION
#define FW_VERSION "dev"
#endif

#ifndef GIT_SHA
#define GIT_SHA "unknown"
#endif

BuddyCanvas spr(HAL_CANVAS_PARENT);

// Advertise as "Buddy-XXXX" (last two BT MAC bytes) so multiple sticks
// in one room are distinguishable in the desktop picker. Name persists in
// btName for debug state dumps.
static char btName[16] = "Buddy";
static void startBt() {
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(btName, sizeof(btName), "Buddy-%02X%02X", mac[4], mac[5]);
  bleInit(btName);
}

#include "character.h"
#include "stats.h"
#include "menu.h"
#include "anim.h"
#include "mood.h"
#include "halo.h"
#include "orbs.h"
#include "bubble.h"
#include "ritual.h"
#include "face.h"
#include "glance.h"
const int W = HAL_W, H = HAL_H;
const int CX = W / 2;
const int CY_BASE = H / 2;
// UI scale: text sizes and row offsets multiply by S so the same layout
// code renders 1:1 on the M5 and at matching physical size on the
// native-resolution Pebble panel.
const int S = HAL_UI_SCALE;

// Colors used across multiple UI surfaces.
const uint16_t HOT   = MOOD_HOT;   // red-orange: warnings, impatience, deny

enum PersonaState { P_SLEEP, P_IDLE, P_BUSY, P_ATTENTION, P_CELEBRATE, P_DIZZY, P_HEART };
const char* personaNames[] = { "P_SLEEP", "P_IDLE", "P_BUSY", "P_ATTENTION", "P_CELEBRATE", "P_DIZZY", "P_HEART" };

TamaState    tama;
PersonaState baseState   = P_SLEEP;
PersonaState activeState = P_SLEEP;
unsigned long t = 0;

char     lastPromptId[40] = "";
bool     screenOff = false;
bool     manualScreenOff = false;
bool     buddyMode = true;
bool     gifAvailable = false;
uint32_t promptArrivedMs = 0;
// Was the panel dark when this prompt landed? Drives the lantern's
// night-aware entry (§2.1.4) — waking a dark room with a full-brightness
// cream field is the one way the mood system turns hostile.
bool     promptArrivedDark = false;
bool     responseSent = false;

const uint8_t BRIGHT_DIM = 40;
const uint8_t BRIGHT_MEDIUM = 120;
const uint8_t BRIGHT_FULL = 220;
const uint32_t SLEEP_DIM_MS = 60000;
const uint32_t SLEEP_OFF_MS = 600000;
const uint32_t BTN_A_LONG_MS = 1500;
// Keep holding BOOP past the screen-sleep threshold and the pet powers
// all the way down (halDeepSleep). Physical presses only.
const uint32_t BTN_A_DEEPSLEEP_MS = 4000;
// "Look" (MENU) is now two verbs: a tap summons the glance card, a hold
// opens the menu carousel. Short enough that the menu still feels reachable,
// long enough that a glance never opens the menu by accident.
const uint32_t BTN_M_LONG_MS = 500;
// How far the face rides up to present the glance card (§6) — enough to
// clear the mouth above the card's top edge without shoving the eyes off.
const int FACE_GLANCE_LIFT = 30;
const uint32_t BOOP_REACT_MS = 2500;
// A press only counts as an approval if it *started* after the prompt had
// been on screen this long — otherwise a tickle already in flight could
// approve a prompt the user never saw. The "btn a|b" debug shortcut and
// mockprompt (which backdates its arrival) bypass this on purpose.
const uint32_t PROMPT_ARM_MS = 600;
// Synthetic touchscreen contact ("touch down|up" serial cmds) — lets HIL
// exercise the tap/boop/petting paths without a finger on the glass.
static bool synthTouch = false;
// Synthetic contact point in sprite coordinates, so HIL can drive the
// touch-tracked gaze without a finger on the glass ("touch down X Y").
// Defaults to screen centre, which produces no gaze deflection.
static int  synthTouchX = HAL_W / 2;
static int  synthTouchY = HAL_H / 2;

// The live contact point, real or injected. Returns false when nothing is
// touching. Sprite coordinates — the HAL already undoes the panel rotation.
static bool touchPoint(int* x, int* y) {
  if (synthTouch) { *x = synthTouchX; *y = synthTouchY; return true; }
  return halTouchPoint(x, y);
}
// Draw-pass counter, exposed in `state`: two samples a second apart give
// frames-per-second; a stalled loop or draw gate shows as a collapse.
static uint32_t drawCount = 0;
// Latched raw-touch telemetry (see handleButtons): edge count + longest
// continuous contact ms since boot.
static uint32_t touchEdges = 0;
static uint32_t touchContactMaxMs = 0;
// AMOLED kindness: a long-idle pet dims until the next state change or
// button press. Attention still forces full brightness.
const uint32_t IDLE_DIM_MS = 300000;
static uint8_t currentBrightness = 0xFF;
static uint32_t boopUntil = 0;
static uint32_t lastInputMs = 0;      // last physical/synthetic button edge
static bool lastDecisionApprove = false;

// Single source of truth for the prompt predicates — the button handler,
// dumpState, and the draw path must never disagree on these.
static bool promptPending() {
  return tama.promptId[0] && tama.promptApproval && !responseSent;
}
static bool promptArmed(uint32_t now) {
  return promptPending() && (int32_t)(now - (promptArrivedMs + PROMPT_ARM_MS)) >= 0;
}

struct SyntheticPress {
  bool active = false;
  uint32_t releaseAt = 0;
};

// Indexed by HalButton; names match the serial "press a|b|m" protocol.
static SyntheticPress synth[HAL_BTN_COUNT];
static const char SYNTH_NAMES[HAL_BTN_COUNT] = { 'a', 'b', 'm' };

static void beep(uint16_t freq, uint16_t dur) {
  if (settings().sound && !tama.muted) halTone(freq, dur);
}

// Non-blocking chirp scheduler. halTone starts a note and returns; the
// old delay()-spaced jingles froze the loop (and the animation) for up
// to ~200ms right at the emotional beats. Notes fire from tuneTick.
struct TuneNote { uint16_t freq; uint16_t ms; uint16_t at; };   // at = offset from start
static TuneNote _tune[4];
static uint8_t  _tuneN = 0, _tuneI = 0;
static uint32_t _tuneT0 = 0;

static void playTune(const TuneNote* notes, uint8_t count) {
  if (count > 4) count = 4;
  memcpy(_tune, notes, count * sizeof(TuneNote));
  _tuneN = count;
  _tuneI = 0;
  _tuneT0 = millis();
}

static void tuneTick(uint32_t now) {
  while (_tuneI < _tuneN && (int32_t)(now - (_tuneT0 + _tune[_tuneI].at)) >= 0) {
    beep(_tune[_tuneI].freq, _tune[_tuneI].ms);
    _tuneI++;
  }
}

// Rolling cost of one upstream send, split serial vs BLE (EMA + lifetime
// max each). Diagnostic for animation hiccups: a boop is sent on the
// touch/press edge, so a blocking transmit shows up as a freeze exactly on
// release — the split says which channel to blame. A 4-second single-send
// stall was caught in the field with only the combined number; never again.
static uint32_t txUs = 0, txMaxUs = 0;
static uint32_t txSerMaxUs = 0, txBleMaxUs = 0;

static void sendCmd(const char* json) {
  size_t n = strlen(json);
  uint32_t t0 = micros();
  Serial.println(json);
  uint32_t t1 = micros();
  // Skip the radio until the link is fully authed: a notify fired while
  // LE Secure Connections is still handshaking can block for seconds on
  // the NimBLE-backed core-3 stack. Boops are decorative and permissions
  // only exist once a prompt has already arrived over a settled link, so
  // nothing of value is lost by staying quiet mid-handshake.
  if (bleConnected() && bleSecure()) {
    bleWrite((const uint8_t*)json, n);
    bleWrite((const uint8_t*)"\n", 1);
  }
  uint32_t t2 = micros();
  if (t1 - t0 > txSerMaxUs) txSerMaxUs = t1 - t0;
  if (t2 - t1 > txBleMaxUs) txBleMaxUs = t2 - t1;
  uint32_t d = t2 - t0;
  txUs += (int32_t)(d - txUs) >> 3;
  if (d > txMaxUs) txMaxUs = d;
}

uint32_t _clkLastRead = 0;   // retained for data.h time-sync compatibility

static void setDisplayBrightness(uint8_t brightness);

static void wakeDisplay() {
  if (screenOff) {
    halDisplayWake();
    screenOff = false;
    currentBrightness = 0xFF;
  }
  manualScreenOff = false;
  setDisplayBrightness(BRIGHT_MEDIUM);
  buddyInvalidate();
  characterInvalidate();
}

static void sleepDisplay(bool manual) {
  if (!screenOff) {
    halDisplaySleep();
    screenOff = true;
  }
  manualScreenOff = manual;
}

static uint8_t targetBrightness = BRIGHT_MEDIUM;

static void setDisplayBrightness(uint8_t brightness) {
  if (screenOff) return;
  targetBrightness = brightness;
  // Fresh wake (0xFF sentinel): snap — the panel just restored its own
  // level in halDisplayWake, and fading from a stale value reads as a
  // flicker rather than a glow.
  if (currentBrightness == 0xFF) {
    currentBrightness = brightness;
    halSetBrightness(brightness);
  }
}

// Runs every loop (~16ms): steps toward the target so dim/undim glides
// instead of snapping. Full range ≈ 440ms; the common medium<->full hop
// ≈ 200ms.
static void brightnessTick() {
  if (screenOff || currentBrightness == 0xFF || currentBrightness == targetBrightness) return;
  int delta = (int)targetBrightness - (int)currentBrightness;
  int step = delta > 0 ? (delta > 8 ? 8 : delta) : (delta < -8 ? -8 : delta);
  currentBrightness = (uint8_t)((int)currentBrightness + step);
  halSetBrightness(currentBrightness);
}

// --- Motion (IMU) -----------------------------------------------------
// Display-only, same doctrine as touch: motion can change what the pet
// shows (nap, dizzy) but can never answer a prompt.
//   Face-down ≥2s  → nap: screen off, napSeconds accrues until face-up.
//   Shake          → brief dizzy wobble (suppressed while a prompt is up).
// Synthetic injection ("imu set x y z" over serial) overlays the sensor
// so HIL can exercise both detectors without a hand on the board.
static bool     napping = false;
static uint32_t napStartMs = 0;
static uint32_t dizzyUntil = 0;
static bool     imuInjected = false;
static float    injAx = 0, injAy = 0, injAz = 0;
static float    imuAx = 0, imuAy = 0, imuAz = 0;
static bool     imuSeen = false;      // at least one good read (or injection)
static uint32_t imuSampleMs = 0;      // when the last good sample landed
static float    shakeEnergy = 0.0f;

// Sign convention verified on hardware: resting panel-up reads az ≈ +1g.
static const float FACE_DOWN_G = -0.75f;

static uint32_t faceDownSince = 0;
static uint32_t faceUpSince = 0;

// --- Gift loop (§8) --------------------------------------------------------
// A completed task is a gift the buddy is holding for you. It waits as a gold
// twinkling orb until you tap the crown to collect it, then it hands over the
// summary. Device-local state, deliberately: uncollected gifts survive
// dim/off and sleep but NOT a reboot — the desktop remains the source of
// truth for history, and a pet that hoards stale news is worse than one that
// forgets.
//
// Exactly one slot. A newer completion REPLACES the pending one rather than
// queueing: the device only ever promises to hand you the latest thing, and
// the glance card reports whatever the desktop says is really outstanding.
static bool giftPending = false;
static char giftMsg[40] = "";

// --- Pick-up / dangle mode (§10.2) -----------------------------------------
// A lift and the start of a shake look nearly identical to an accelerometer:
// both are "the vector moved". What separates them is persistence without
// energy — a lift changes the orientation and KEEPS it changed, while a
// shake is high-frequency and returns to where it started. So dangle is
// gated on a sustained tilt away from a slow reference orientation, with the
// shake accumulator explicitly below its threshold.
static bool     dangling = false;
static uint32_t dangleTiltSince = 0;
static uint32_t dangleStillSince = 0;
static float    gRefX = 0.0f, gRefY = 0.0f, gRefZ = 1.0f;   // resting orientation
static bool     gRefInit = false;
static float    motionEnergy = 0.0f;     // slower cousin of shakeEnergy
static float    dangleTilt = 0.0f;       // radians from the reference, for `imu`
// Springs so the eyes jiggle with real motion rather than snapping to the
// raw sample (doctrine #10).
static AnimSpring dangleSprX, dangleSprY;

static const float DANGLE_TILT_RAD   = 0.38f;   // ~22 degrees
static const uint32_t DANGLE_HOLD_MS = 400;     // sustained before it counts
static const float DANGLE_SHAKE_MAX  = 1.2f;    // must be calm to be a lift
static const float DANGLE_STILL_MAX  = 0.30f;
static const uint32_t DANGLE_END_MS  = 1000;    // ~1s of stillness ends it

static void napEnd(uint32_t now) {
  if (!napping) return;
  napping = false;
  statsOnNapEnd((now - napStartMs) / 1000);
  lastInputMs = now;
  // Restart the face-down debounce: a button-press escape must buy a
  // fresh 2s of lit screen even if the device (or a stuck sensor) still
  // reads face-down — otherwise the very next 50ms poll re-naps.
  faceDownSince = 0;
  wakeDisplay();
}

static void motionTick(uint32_t now) {
  static uint32_t nextPoll = 0;
  if ((int32_t)(now - nextPoll) < 0) return;
  nextPoll = now + 50;

  float ax, ay, az;
  if (imuInjected) {
    ax = injAx; ay = injAy; az = injAz;
  } else if (!halImuRead(&ax, &ay, &az)) {
    // Fail open: a sensor that goes silent must never trap the pet in a
    // nap — the nap gate forces the screen off and ignores touch, which
    // reads as a bricked device. 5s without a sample ends the nap.
    if (napping && imuSeen && now - imuSampleMs > 5000) napEnd(now);
    return;
  }
  imuAx = ax; imuAy = ay; imuAz = az;
  imuSeen = true;
  imuSampleMs = now;

  // Shake: leaky accumulator over the high-passed magnitude. Rest noise
  // (~0.02g/sample) stays near zero; a real shake (>1g deviations) crosses
  // the threshold within a few samples.
  float mag = sqrtf(ax * ax + ay * ay + az * az);
  shakeEnergy = shakeEnergy * 0.8f + fabsf(mag - 1.0f);
  if (shakeEnergy > 2.5f && !promptPending() && !napping) {
    shakeEnergy = 0.0f;
    dizzyUntil = now + 3000;
  }

  // Pick-up / dangle. The reference orientation tracks slowly (~2s) so a
  // deliberate lift registers as tilt, and freezes entirely while airborne
  // so it can't creep up to meet the new pose and cancel the state.
  if (!gRefInit) { gRefX = ax; gRefY = ay; gRefZ = az; gRefInit = true; }
  if (!dangling) {
    const float k = 0.03f;
    gRefX += (ax - gRefX) * k;
    gRefY += (ay - gRefY) * k;
    gRefZ += (az - gRefZ) * k;
  }
  {
    float mRef = sqrtf(gRefX * gRefX + gRefY * gRefY + gRefZ * gRefZ);
    float c = (mag > 0.01f && mRef > 0.01f)
                ? (ax * gRefX + ay * gRefY + az * gRefZ) / (mag * mRef) : 1.0f;
    if (c > 1.0f) c = 1.0f; else if (c < -1.0f) c = -1.0f;
    dangleTilt = acosf(c);
  }
  motionEnergy = motionEnergy * 0.90f + fabsf(mag - 1.0f);

  if (!dangling) {
    // Suppressed while a prompt pends, exactly as shake is: affection and
    // play may never delay a decision the human owes (doctrine #12).
    bool calm = shakeEnergy < DANGLE_SHAKE_MAX;
    if (dangleTilt > DANGLE_TILT_RAD && calm && !promptPending() && !napping) {
      if (dangleTiltSince == 0) dangleTiltSince = now;
      if (now - dangleTiltSince >= DANGLE_HOLD_MS) {
        dangling = true;
        dangleStillSince = 0;
        Serial.println("<<DANGLE start>>");
      }
    } else {
      dangleTiltSince = 0;
    }
  } else {
    // Ends after ~1s of stillness — being set down, or simply held steady.
    if (motionEnergy < DANGLE_STILL_MAX) {
      if (dangleStillSince == 0) dangleStillSince = now;
      if (now - dangleStillSince >= DANGLE_END_MS) {
        dangling = false;
        dangleTiltSince = 0;
        Serial.println("<<DANGLE end>>");
      }
    } else {
      dangleStillSince = 0;
    }
    // A prompt arriving mid-air takes the screen back immediately.
    if (promptPending()) { dangling = false; dangleTiltSince = 0; }
  }

  // Face-down nap. Entry is debounced 2s so a wobbly pickup doesn't nap;
  // exit needs 700ms face-up so one bounce doesn't end it. Entry is
  // blocked while a prompt is pending (mirrors the no-dim rule).
  bool faceDown = az < FACE_DOWN_G;
  if (faceDown) {
    faceUpSince = 0;
    if (faceDownSince == 0) faceDownSince = now;
    if (!napping && !promptPending() && now - faceDownSince >= 2000) {
      napping = true;
      napStartMs = now;
      sleepDisplay(false);
    }
  } else {
    faceDownSince = 0;
    if (faceUpSince == 0) faceUpSince = now;
    if (napping && now - faceUpSince >= 700) napEnd(now);
  }
}

static void playStateChirp(PersonaState state) {
  if (tama.muted || !settings().sound) return;
  static const TuneNote ATTN[] = { {880, 90, 0}, {1245, 90, 110} };
  static const TuneNote CELE[] = { {988, 70, 0}, {1175, 70, 85}, {1397, 80, 170} };
  static const TuneNote DIZZ[] = { {330, 180, 0} };
  switch (state) {
    case P_ATTENTION: playTune(ATTN, 2); break;
    case P_CELEBRATE: if (tama.celebrate) playTune(CELE, 3); break;
    case P_DIZZY:     playTune(DIZZ, 1); break;
    default: break;
  }
}

static void updateDisplayPower(PersonaState state) {
  static PersonaState prevState = P_SLEEP;
  static uint32_t sleepSince = 0;
  static uint32_t stateSince = 0;
  uint32_t now = millis();
  bool changed = state != prevState;

  if (changed) {
    prevState = state;
    stateSince = now;
    playStateChirp(state);
    // Celebrate fires the halo's one-shot green->warm ripple. It stays in
    // Night mood on purpose: spending the lantern on a happy state would
    // cost the lantern its meaning (§2.1).
    if (state == P_CELEBRATE) haloCelebrate(now);
    if (state == P_SLEEP) {
      sleepSince = now;
    } else if (!napping) {
      wakeDisplay();
    }
  }

  // Face-down nap owns the screen: state changes still chirp (above) but
  // never light a panel that's pressed against the desk.
  if (napping) {
    sleepDisplay(false);
    return;
  }

  if (state == P_SLEEP) {
    if (sleepSince == 0) sleepSince = now;
    // Measure from the LAST user input, not just the state change — a
    // button press or screen tap restarts the dim/off ladder. Without
    // this, waking a long-asleep pet relapsed to screen-off on the very
    // next frame (asleepFor was still past SLEEP_OFF_MS), so a tap lit
    // the screen for a single frame.
    uint32_t ref = ((int32_t)(lastInputMs - sleepSince) > 0) ? lastInputMs : sleepSince;
    uint32_t asleepFor = now - ref;
    if (!manualScreenOff && asleepFor >= SLEEP_OFF_MS) {
      sleepDisplay(false);
    } else if (!screenOff && asleepFor >= SLEEP_DIM_MS) {
      setDisplayBrightness(BRIGHT_DIM);
    } else if (!screenOff) {
      setDisplayBrightness(BRIGHT_MEDIUM);
    }
    return;
  }

  if (state == P_ATTENTION || state == P_DIZZY) {
    setDisplayBrightness(BRIGHT_FULL);
    return;
  }
  // Long-idle dim (burn-in kindness on the AMOLED board; harmless on LCD).
  // Never while a prompt is pending — the approval card must stay readable
  // even if the persona has settled to idle.
  if (state == P_IDLE && now - stateSince >= IDLE_DIM_MS &&
      now - lastInputMs >= IDLE_DIM_MS && !menuActive() && !promptPending()) {
    setDisplayBrightness(BRIGHT_DIM);
    return;
  }
  setDisplayBrightness(BRIGHT_MEDIUM);
}

// Proportional layout so the same code fits both the portrait M5 and the
// landscape Pebble canvas.
void drawPasskey() {
  const Palette& p = characterPalette();
  // Landscape wears the Lantern mood (§2 priority 2): a passkey is the
  // purest "a human must act right now" state in the product — the code has
  // to be read off the glass and typed before anything else can happen.
  uint16_t bg = p.bg, primary = p.text, secondary = p.textDim;
  if (HAL_LANDSCAPE) {
    uint32_t nowMs = millis();
    moodDrawField(spr, nowMs);
    bg = moodBackdrop(nowMs);
    primary = _moodMix(p.text, MOOD_INK, moodInkBlend());
    secondary = _moodMix(p.textDim, MOOD_INK_DIM, moodInkBlend());
  } else {
    spr.fillSprite(p.bg);
  }
  spr.setTextDatum(TC_DATUM);
  spr.setTextSize(S);
  spr.setTextColor(secondary, bg);
  spr.drawString("BLUETOOTH PAIRING", W / 2, 8 * S);
  spr.setTextSize(3 * S);
  spr.setTextColor(primary, bg);
  char b[8]; snprintf(b, sizeof(b), "%06lu", (unsigned long)blePasskey());
  spr.drawString(b, W / 2, CY_BASE - 12 * S);
  spr.setTextSize(S);
  spr.setTextColor(secondary, bg);
  spr.drawString("enter on desktop", W / 2, H - 16 * S);
  spr.setTextDatum(TL_DATUM);
}

PersonaState derive(const TamaState& s) {
  if (!s.connected) return P_SLEEP;
  if (strcmp(s.pet, "sleep") == 0)     return P_SLEEP;
  if (strcmp(s.pet, "busy") == 0)      return P_BUSY;
  if (strcmp(s.pet, "attention") == 0) return P_ATTENTION;
  if (strcmp(s.pet, "celebrate") == 0) return P_CELEBRATE;
  if (strcmp(s.pet, "error") == 0)     return P_DIZZY;   // Gap C: explicit StopFailure
  if (strcmp(s.pet, "thinking") == 0)  return P_BUSY;    // calm working face; avoids heart-eyes for thought.
  if (strcmp(s.pet, "heart") == 0)     return P_HEART;   // desktop mirrors a boop back
  return P_IDLE;
}

static void updateSyntheticPresses() {
  uint32_t now = millis();
  for (int i = 0; i < HAL_BTN_COUNT; i++) {
    if (synth[i].active && (int32_t)(now - synth[i].releaseAt) >= 0) {
      synth[i].active = false;
      Serial.printf("<<PRESS %c up>>\n", SYNTH_NAMES[i]);
    }
  }
}

// true = held. Synthetic (serial-injected) presses overlay the physical
// state so HIL tests exercise the same edge detector as real fingers.
static bool readBtn(HalButton b) {
  updateSyntheticPresses();
  if (synth[b].active) return true;
  return halButtonDown(b);
}

// Two-row text with a word-aware break: split at the last space within
// reach of the row width instead of mid-word. Rows are capped at cpl
// chars; anything past two rows is dropped.
static void drawWrapped2(const char* s, int x, int y1, int y2, int cpl) {
  int len = (int)strlen(s);
  if (len <= cpl) {
    spr.setCursor(x, y1);
    spr.print(s);
    return;
  }
  int brk = cpl;
  for (int i = cpl; i > cpl - 12 && i > 0; i--) {
    if (s[i] == ' ') { brk = i; break; }
  }
  spr.setCursor(x, y1);
  spr.printf("%.*s", brk, s);
  const char* rest = s + brk + (s[brk] == ' ' ? 1 : 0);
  spr.setCursor(x, y2);
  spr.printf("%.*s", cpl, rest);
}

// Emit the permission decision for the current prompt. Shared by the
// physical buttons and the debug "btn" serial command so both produce the
// exact same wire format and trip the same responseSent latch.
static void sendApproval(bool approve) {
  char cmd[96];
  snprintf(cmd, sizeof(cmd), "{\"cmd\":\"permission\",\"id\":\"%s\",\"decision\":\"%s\"}",
           tama.promptId, approve ? "allow" : "deny");
  sendCmd(cmd);
  if (approve) statsOnApproval();
  else statsOnDenial();
  responseSent = true;
  lastDecisionApprove = approve;
  // Resolve the field (§2.1.3). Approve snuffs — the light contracts back
  // into the face behind a green ripple, deliberately faster than the
  // bloom, because resolution should feel decisive. Deny fades evenly to
  // black: neutral and unhurried. Denial is responsible, not punished, so
  // it gets no ripple and no contraction.
  if (HAL_LANDSCAPE) {
    if (approve) { cardPop(); moodSnuff(); }
    else         { cardDismiss(); moodFade(); }
  }
  // Approve gets a bright "mm-hm!"; deny a single neutral note. Deny must
  // never sound (or look) sad — guilt-tripping users into approving is a
  // product bug, not a personality.
  static const TuneNote YES[] = { {988, 60, 0}, {1319, 90, 70} };
  static const TuneNote NO[]  = { {523, 80, 0} };
  if (approve) playTune(YES, 2);
  else         playTune(NO, 1);
}

// Tell the desktop the pet was booped so the Mac blob reacts in kind.
// Rate-limited: sustained petting refreshes the local heart every loop but
// only needs a wire frame every ~1.5s to keep the desktop's affection
// window alive (its window is 2.5s, matching BOOP_REACT_MS).
static uint32_t lastBoopSentMs = 0;
static void sendBoopUpstream() {
  uint32_t now = millis();
  if (lastBoopSentMs != 0 && now - lastBoopSentMs < 1500) return;
  lastBoopSentMs = now;
  sendCmd("{\"cmd\":\"boop\"}");
}

// Pet-affection reaction: a short heart-face flash when the BOOP button is
// pressed outside of a pending approval, mirrored to the desktop pet.
static void boopPet() {
  boopUntil = millis() + BOOP_REACT_MS;
  beep(1245, 60);
  buddyInvalidate();
  // Physical reaction to being booped (§10.1). The spring rings down on
  // its own, so repeated boops compound into a bigger wobble instead of
  // restarting the same canned animation.
  if (HAL_LANDSCAPE) faceBoopSquish();
  sendBoopUpstream();
}

// Collect the pending gift: the orb pops, the buddy giggles, and the
// completion summary appears in a bubble for 4s. Nothing goes upstream in
// v1 — that's a deliberate choice rather than a limit, since boops already
// round-trip, so a {"cmd":"collect"} is a small addition whenever the
// desktop wants to mirror it.
static void collectGift(uint32_t now) {
  if (!giftPending) return;
  giftPending = false;
  bubbleShow(giftMsg[0] ? giftMsg : "all done!", now, 4000, GREEN);
  faceBoopSquish();          // the giggle
  haloCelebrate(now);        // sparkle burst, reusing the celebrate ripple
  beep(1319, 70);
  Serial.printf("<<GIFT collect %.30s>>\n", giftMsg);
}

// Power the pet all the way down. Never returns — halDeepSleep restarts
// the firmware on wake (BOOP button; timerWakeMs lets HIL prove the
// round-trip without a finger on the board).
static void goodNight(uint32_t timerWakeMs) {
  Serial.println("<<DEEPSLEEP entering>>");
  statsSave();
  // The 1.5s hold already blanked the panel — light it for one beat so
  // "night night" reads as an acknowledgment, then sleep for real.
  wakeDisplay();
  const Palette& p = characterPalette();
  spr.fillSprite(BLACK);
  spr.setTextDatum(MC_DATUM);
  spr.setTextSize(2 * S);
  spr.setTextColor(p.body, BLACK);
  spr.drawString("night night", CX, CY_BASE);
  spr.setTextDatum(TL_DATUM);
  spr.setTextSize(S);
  delay(30);   // clear the present throttle so this frame reaches glass
  halPresent(spr);
  delay(900);
  // The 4s hold that got us here is still down — entering sleep now would
  // wake (WS: level trigger) or bounce straight back (M5: EXT1) on the
  // same press. Sleep only once the finger lifts.
  while (halButtonDown(HAL_BTN_BOOP)) {
    guardFeed();
    delay(10);
  }
  bleStop();
  halDeepSleep(timerWakeMs);
}

// Three logical buttons (see hal.h for the physical mapping):
//   BOOP   — approve when a prompt is armed; pick when the menu is open;
//            boop the pet otherwise. Long-press (outside a prompt)
//            toggles screen sleep.
//   REJECT — deny on press when a prompt is armed; back when the menu is
//            open.
//   MENU   — open the on-device menu; next item once it's open. (Absent
//            on M5; synthetic "press m" still exercises it there.)
// Panel touch is affection-only: it wakes the screen and boops the pet,
// and is deliberately powerless while a prompt is pending or the menu is
// open — only physical buttons may act on those.
// Any press wakes the screen; a wake-press never doubles as an action.
// Approvals additionally require the press to have STARTED after the
// prompt was armed (PROMPT_ARM_MS) so a tickle in flight can't approve a
// prompt that appeared under the user's finger.
// Long-press ladder stage flag. File-scope so `state` can report it —
// HIL proves the ladder arms even when the hold began on a dark screen.
static bool boopLongHandled = false;

static void __attribute__((noinline)) handleButtons() {
  static bool prevBoop = false, prevRej = false, prevMenu = false;
  static uint32_t boopDownAt = 0;
  static bool suppressBoopRelease = false;
  static uint32_t menuDownAt = 0;
  static bool menuLongHandled = false;
  static bool suppressMenuRelease = false;

  bool boop = readBtn(HAL_BTN_BOOP);
  bool rej  = readBtn(HAL_BTN_REJECT);
  bool menu = readBtn(HAL_BTN_MENU);
  uint32_t now = millis();
  bool pending = promptPending();
  uint32_t armedAt = promptArrivedMs + PROMPT_ARM_MS;
  bool armed = promptArmed(now);
  bool wasOff = screenOff;

  if ((!prevBoop && boop) || (!prevRej && rej) || (!prevMenu && menu)) {
    wakeDisplay();
    lastInputMs = now;
    // A physical press always ends a nap — the escape hatch if the
    // accelerometer wedges while the nap gate holds the screen dark.
    napEnd(now);
    // ...and skips a ritual. A ritual is a gift, not a toll.
    ritualSkip();
    if (!prevBoop && boop) {
      boopDownAt = now;
      suppressBoopRelease = wasOff;
      boopLongHandled = false;
    }
    if (!prevMenu && menu) {
      menuDownAt = now;
      suppressMenuRelease = wasOff;
      menuLongHandled = false;
    }
  }

  // 1.5s stage. A hold that began as a wake-press skips the screen-off
  // step (it just lit the panel) but still arms the 4s power-down stage:
  // holding from a dark screen is exactly how a sleeping pet gets powered
  // down, so the wake-press guard must only eat taps, never holds.
  // (Found on hardware: overnight screen-off made the 4s hold a no-op.)
  if (prevBoop && boop && !armed && !boopLongHandled &&
      now - boopDownAt >= BTN_A_LONG_MS) {
    if (!suppressBoopRelease) {
      menuClose(false);
      sleepDisplay(true);
    }
    suppressBoopRelease = true;
    boopLongHandled = true;
  }

  // Keep holding: at 4s the pet powers down entirely. Physical fingers
  // only — a scripted "press a --ms 5000" must never be able to strand
  // the device asleep mid-HIL (use "deepsleep <ms>" to test this path).
  if (prevBoop && boop && boopLongHandled && !synth[HAL_BTN_BOOP].active &&
      now - boopDownAt >= BTN_A_DEEPSLEEP_MS) {
    goodNight(0);   // never returns
  }

  // "Look" hold opens the menu carousel. Like the crown ladder, the hold
  // survives a wake-press (only taps are eaten) — reaching for the menu on
  // a dark screen should just work.
  if (prevMenu && menu && !menuLongHandled && !pending &&
      now - menuDownAt >= BTN_M_LONG_MS) {
    menuLongHandled = true;
    suppressMenuRelease = true;
    if (!menuActive()) {
      glanceClose();   // the card is the tap verb; the hold supersedes it
      menuOpen(now);
    }
  }

  bool boopRelease = prevBoop && !boop;
  bool rejPress = !prevRej && rej;
  bool menuRelease = prevMenu && !menu;
  if (boopRelease) {
    if (now - boopDownAt >= BTN_A_LONG_MS) suppressBoopRelease = true;
    if (!suppressBoopRelease) {
      // Crown tap resolution order (§5), first match wins. Keeping this a
      // single ordered chain is what makes "crown = yes" one reliable verb.
      if (armed && (int32_t)(boopDownAt - armedAt) >= 0) sendApproval(true);
      else if (pending) {
        // Press raced the arming window of a fresh prompt: swallow it.
        // A boop reaction here would read as "approved" — worse than
        // nothing. The card stays up; the next press counts.
      }
      else if (menuActive()) {
        // Adopting a character earns a small celebration — it's the one
        // menu action that changes who the buddy IS.
        bool adopting = HAL_LANDSCAPE && strcmp(menuScreenName(), "character") == 0;
        menuSelect(now);
        if (adopting) { faceBoopSquish(); haloCelebrate(now); }
      }
      // Pending gift outranks a plain boop: the buddy is holding something
      // out for you and the crown is how you take it.
      else if (giftPending && HAL_LANDSCAPE) collectGift(now);
      // A displayed error is a demanded-tier fact — the crown acknowledges
      // it (the buddy shakes it off) rather than booping past it. Nothing
      // goes upstream; this only clears the display.
      else if (HAL_LANDSCAPE && (int32_t)(dizzyUntil - now) > 0) {
        dizzyUntil = now;
        faceBoopSquish();
      }
      else if (glanceActive()) {
        // Dismiss the card with a giggle rather than in silence — the
        // crown is affirmative even when there's nothing to affirm.
        glanceClose();
        boopPet();
      }
      else boopPet();
    }
    suppressBoopRelease = false;
    boopLongHandled = false;
  }
  // !wasOff on both: a tap that wakes the screen must never also act —
  // especially not deny a prompt the user hasn't seen yet.
  if (rejPress && !wasOff) {
    if (armed) sendApproval(false);
    else if (glanceActive()) glanceClose();
    else if (menuActive()) menuBack(now);
  }
  // "Look" tap: summon the glance card, or turn its pages. Once the menu is
  // open the tap keeps its existing meaning (next item).
  if (menuRelease) {
    if (!suppressMenuRelease && !pending) {
      if (menuActive()) menuNext(now);
      else if (HAL_LANDSCAPE) glanceOpen(now);
      else menuOpen(now);   // portrait M5 has no glance card — tap still opens
    }
    suppressMenuRelease = false;
    menuLongHandled = false;
  }

  static bool prevTouch = false;
  // Raw-contact telemetry, latched for post-hoc reading over serial: how
  // many touch-down edges the FT3168 has reported and the longest single
  // continuous contact. Diagnoses the chip's stationary-finger behavior
  // (suspected monitor-mode dropout) without live coordination — the
  // user gestures whenever, the evidence waits in `state`.
  {
    static bool prevRaw = false;
    static uint32_t rawDownAt = 0;
    bool raw = halTouchDown();
    if (!prevRaw && raw) { touchEdges++; rawDownAt = now; }
    if (raw && now - rawDownAt > touchContactMaxMs) touchContactMaxMs = now - rawDownAt;
    prevRaw = raw;
  }
  // A face-down panel can press its own touchscreen against the surface —
  // ignore contact entirely while napping so the couch can't boop the pet
  // into a wake/chirp loop. synthTouch ("touch down|up" over serial)
  // overlays the panel so HIL can drive the tap/pet paths.
  bool touch = !napping && (halTouchDown() || synthTouch);
  if (!prevTouch && touch) {
    wakeDisplay();
    lastInputMs = now;
    if (!wasOff && !pending && !menuActive()) boopPet();
  } else if (prevTouch && touch && !screenOff && !pending && !menuActive()) {
    // Petting: sustained contact keeps the heart (or the sleep-peek) alive
    // for the whole stroke, and keeps the desktop's affection window
    // refreshed. No chirp — the boop edge already played it.
    boopUntil = now + BOOP_REACT_MS;
    lastInputMs = now;
    sendBoopUpstream();
  }
  prevTouch = touch;

  prevBoop = boop;
  prevRej = rej;
  prevMenu = menu;
}

static void restoreLogLevel() {
#if defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL >= 5
  esp_log_level_set("*", ESP_LOG_VERBOSE);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 4
  esp_log_level_set("*", ESP_LOG_DEBUG);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 3
  esp_log_level_set("*", ESP_LOG_INFO);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 2
  esp_log_level_set("*", ESP_LOG_WARN);
#elif defined(CORE_DEBUG_LEVEL) && CORE_DEBUG_LEVEL == 1
  esp_log_level_set("*", ESP_LOG_ERROR);
#else
  esp_log_level_set("*", ESP_LOG_NONE);
#endif
}

static uint32_t crc32Update(uint32_t crc, const uint8_t* data, size_t len) {
  crc = ~crc;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ (0xEDB88320UL & (-(int32_t)(crc & 1)));
    }
  }
  return ~crc;
}

static const char* currentScreenName() {
  if (screenOff) return "off";
  if (blePasskey()) return "passkey";
  if (otaActive()) return "ota";
  return "buddy";
}

static const char* currentDataMode() {
  if (dataDemo()) return "demo";
  if (dataConnected()) return "live";
  return "asleep";
}

static void dumpPing() {
  // heapMin/heapBig: low-water mark and largest free block. A BLE connect
  // needs several contiguous KB; if heapBig is small the Bluedroid connect
  // path OOMs and asserts (fixed_queue_new → vQueueDelete(NULL)).
  // frameUs/frameMaxUs: measured cost of one present (0 on M5) — the
  // ground truth for animation cadence tuning.
  uint32_t fAvg = 0, fMax = 0;
  halFrameStats(&fAvg, &fMax);
  Serial.printf("<<PONG {\"fw\":\"%s\",\"git\":\"%s\",\"board\":\"" HAL_BOARD_NAME "\","
                "\"up\":%lu,\"heap\":%lu,\"heapMin\":%lu,\"heapBig\":%lu,"
                "\"frameUs\":%lu,\"frameMaxUs\":%lu,"
                "\"reset\":\"%s\",\"panics\":%lu,\"early\":%lu,\"safe\":%d}>>\n",
                FW_VERSION, GIT_SHA, (unsigned long)millis(), (unsigned long)ESP.getFreeHeap(),
                (unsigned long)ESP.getMinFreeHeap(), (unsigned long)ESP.getMaxAllocHeap(),
                (unsigned long)fAvg, (unsigned long)fMax,
                guardResetReason(), (unsigned long)guardPanicsTotal(),
                (unsigned long)guardEarlyCrashes(), guardSafeTier());
}

static void dumpState() {
  JsonDocument doc;
  doc["pet"] = tama.pet;
  doc["species"] = tama.species;
  doc["desktop"] = tama.desktop;
  doc["connected"] = tama.connected;
  doc["total"] = tama.sessionsTotal;
  doc["running"] = tama.sessionsRunning;
  doc["waiting"] = tama.sessionsWaiting;
  doc["msg"] = tama.msg;
  doc["activity"] = tama.activity;
  doc["promptId"] = tama.promptId;
  doc["promptTool"] = tama.promptTool;
  doc["promptHint"] = tama.promptHint;
  doc["promptSource"] = tama.promptSource;
  doc["promptApproval"] = tama.promptApproval;
  doc["responseSent"] = responseSent;
  doc["armed"] = promptArmed(millis());
  doc["menu"] = menuScreenName();
  doc["glance"] = glanceStateName();
  doc["bonded"] = bleBonded();
  doc["mood"] = moodName();
  doc["card"] = cardVisible();
  doc["gift"] = giftPending;
  doc["ritual"] = ritualName();
  doc["orbs"] = orbsAlive();
  doc["orbsOverflow"] = orbsOverflow();
  // Field luminance 0..1 — the screenshot oracle asserts on the corner
  // pixel, this is the same fact for a cheap non-visual assertion.
  doc["moodLit"] = (int)(moodLit() * 100.0f + 0.5f);
  doc["moodInk"] = (int)(moodInkBlend() * 100.0f + 0.5f);
  doc["muted"] = tama.muted;
  doc["screenOff"] = screenOff;
  doc["brightness"] = currentBrightness == 0xFF ? 0 : currentBrightness;
  doc["persona"] = personaNames[derive(tama)];
  doc["activePersona"] = personaNames[activeState];
  doc["boop"] = (int32_t)(boopUntil - millis()) > 0;
  doc["napping"] = napping;
  doc["dizzy"] = (int32_t)(dizzyUntil - millis()) > 0;
  doc["dangling"] = dangling;
  doc["ladder"] = boopLongHandled;
  doc["touchOk"] = halTouchReady();
  doc["touchDown"] = halTouchDown();
  doc["touchEdges"] = touchEdges;
  doc["touchContactMaxMs"] = touchContactMaxMs;
  doc["imuOk"] = halImuReady();
  doc["tick"] = (uint32_t)t;
  doc["draws"] = drawCount;
  doc["txUs"] = txUs;
  doc["txMaxUs"] = txMaxUs;
  doc["txSerMaxUs"] = txSerMaxUs;
  doc["txBleMaxUs"] = txBleMaxUs;
  {
    uint32_t tpAvg = 0, tpMax = 0;
    halTouchStats(&tpAvg, &tpMax);
    doc["tpUs"] = tpAvg;
    doc["tpMaxUs"] = tpMax;
  }
  doc["screen"] = currentScreenName();
  doc["rot"] = halDisplayRotation();
  doc["board"] = HAL_BOARD_NAME;
  doc["speciesLocal"] = buddySpeciesName();
  doc["mode"] = currentDataMode();
  doc["rtcValid"] = dataRtcValid();
  doc["nLines"] = tama.nLines;
  doc["btName"] = btName;
  doc["bleConnected"] = bleConnected();
  doc["bleSecure"] = bleSecure();
  doc["lineGen"] = tama.lineGen;
  doc["reset"] = guardResetReason();
  doc["panics"] = guardPanicsTotal();
  doc["earlyCrashes"] = guardEarlyCrashes();
  doc["safeTier"] = guardSafeTier();
  doc["bleDrops"] = bleRxDropped();

  Serial.print("<<STATE ");
  serializeJson(doc, Serial);
  Serial.println(">>");
}

static void schedulePress(char which, uint32_t ms) {
  if (ms == 0) ms = 1;
  if (ms > 5000) ms = 5000;
  uint32_t releaseAt = millis() + ms;
  int idx = -1;
  if (which == 'a' || which == 'A') idx = HAL_BTN_BOOP;
  else if (which == 'b' || which == 'B') idx = HAL_BTN_REJECT;
  else if (which == 'm' || which == 'M') idx = HAL_BTN_MENU;
  if (idx < 0) {
    Serial.println("<<PRESS err (use a|b|m)>>");
    return;
  }
  synth[idx].active = true;
  synth[idx].releaseAt = releaseAt;
  Serial.printf("<<PRESS %c down>>\n", SYNTH_NAMES[idx]);
}

// Dump the logical canvas as base64 RGB565 over USB serial. Reads from
// the sprite, not panel RAM: everything the firmware draws goes through
// the sprite on every board, and the AMOLED board's QSPI panel has no
// readback path at all. Triggered by sending the line "screenshot\n" on
// USB serial; framed with sentinels so the host can ignore unrelated log
// lines on the same channel.
//
// The sprite is 8bpp RGB332; pixels are widened to RGB565LE to keep the
// wire format the host tooling already speaks. Up to two leftover bytes
// carry across rows so the row width doesn't have to be a multiple of 3
// (e.g. 228*2=456 is, 140*2=280 isn't) — concatenated chunks still form one
// valid base64 stream, padded only at the very end.
static inline uint16_t rgb332to565(uint8_t c) {
  uint16_t r5 = (((c >> 5) & 7) * 31 + 3) / 7;
  uint16_t g6 = (((c >> 2) & 7) * 63 + 3) / 7;
  uint16_t b5 = ((c & 3) * 31 + 1) / 3;
  return (uint16_t)((r5 << 11) | (g6 << 5) | b5);
}

static void dumpScreenshot() {
  static const char b64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  esp_log_level_set("*", ESP_LOG_NONE);
#ifdef BOARD_WS_AMOLED_164
  // The dump streams ~450KB and the host is actively reading it — restore
  // back-pressure for its duration, else the 0-timeout policy (which keeps
  // taps from freezing the pet) silently drops rows mid-stream.
  Serial.setTxTimeoutMs(250);
#endif

  int rot = halDisplayRotation();
  int w   = spr.width();
  int h   = spr.height();
  if (w <= 0 || w > 512 || h <= 0) {
    Serial.println("<<SCR_ERR bad-dims>>");
    restoreLogLevel();
    return;
  }

  Serial.printf("\n<<SCR_BEGIN W=%d H=%d ROT=%d FMT=RGB565LE>>\n", w, h, rot);

  uint8_t bytes[2 + 512 * 2];   // carried remainder + one row
  char enc[((sizeof(bytes) / 3) + 1) * 4];
  int nc = 0;                   // bytes carried from the previous row
  uint32_t crc = 0;
  uint32_t rawLen = 0;
  for (int y = 0; y < h; y++) {
    guardFeed();   // full dump takes several seconds of loop() time
    int n = nc;
    for (int x = 0; x < w; x++) {
      uint16_t px = rgb332to565((uint8_t)spr.readPixelValue(x, y));
      bytes[n++] = (uint8_t)(px & 0xFF);
      bytes[n++] = (uint8_t)(px >> 8);
    }
    crc = crc32Update(crc, bytes + nc, n - nc);
    rawLen += n - nc;
    int usable = (n / 3) * 3;
    int o = 0;
    for (int i = 0; i < usable; i += 3) {
      uint32_t v = ((uint32_t)bytes[i] << 16) | ((uint32_t)bytes[i+1] << 8) | (uint32_t)bytes[i+2];
      enc[o++] = b64[(v >> 18) & 0x3F];
      enc[o++] = b64[(v >> 12) & 0x3F];
      enc[o++] = b64[(v >>  6) & 0x3F];
      enc[o++] = b64[ v        & 0x3F];
    }
    Serial.write((const uint8_t*)enc, o);
    nc = n - usable;
    if (nc) memmove(bytes, bytes + usable, nc);
  }
  if (nc) {
    uint32_t v = ((uint32_t)bytes[0] << 16) | (nc > 1 ? ((uint32_t)bytes[1] << 8) : 0);
    char tail[4];
    tail[0] = b64[(v >> 18) & 0x3F];
    tail[1] = b64[(v >> 12) & 0x3F];
    tail[2] = nc > 1 ? b64[(v >> 6) & 0x3F] : '=';
    tail[3] = '=';
    Serial.write((const uint8_t*)tail, 4);
  }
  Serial.println();
  Serial.printf("<<SCR_END LEN=%lu CRC32=%08lx>>\n", (unsigned long)rawLen, (unsigned long)crc);
#ifdef BOARD_WS_AMOLED_164
  Serial.setTxTimeoutMs(0);
#endif
  restoreLogLevel();
}

void handleSerialCommand(const char* line) {
  if (!line || !*line) return;
  if (strcmp(line, "ping") == 0) { dumpPing(); return; }
  if (strcmp(line, "state") == 0) { dumpState(); return; }
  if (strcmp(line, "reboot") == 0) {
    Serial.println("<<REBOOT ok>>");
    Serial.flush();
    delay(50);
    esp_restart();
  }
  if (strcmp(line, "screenshot") == 0 || strncmp(line, "screenshot ", 11) == 0) {
    dumpScreenshot();
    return;
  }
  // Recovery: drop all BLE bonds so a host with stale/broken pairing state
  // can start fresh without reflashing NVS.
  if (strcmp(line, "clearbonds") == 0) {
    bleClearBonds();
    Serial.println("<<CLEARBONDS ok>>");
    return;
  }
  // Debug: reset crash-loop bookkeeping. HIL tests trigger deliberate
  // watchdog resets and use this so repeated runs don't drift into safe
  // mode.
  if (strcmp(line, "guardclear") == 0) {
    guardClear();
    Serial.println("<<GUARDCLEAR {\"ok\":true}>>");
    return;
  }
  // Debug: wedge loop() on purpose so tests can prove the task watchdog
  // reboots a hung device. ~GUARD_WDT_TIMEOUT_S until recovery.
  if (strcmp(line, "hang") == 0) {
    Serial.println("<<HANG ok — task WDT should reboot in ~30s>>");
    Serial.flush();
    for (;;) delay(100);
  }

  if (strncmp(line, "press ", 6) == 0) {
    const char* p = line + 7;
    while (*p == ' ') p++;
    uint32_t ms = *p ? (uint32_t)strtoul(p, nullptr, 10) : 150;
    schedulePress(line[6], ms);
    return;
  }

  // Debug/HIL: motion. "imu" dumps the live sample and detector state;
  // "imu set x y z" (g, floats) overlays a synthetic sample so tests can
  // drive face-down/shake without touching the board; "imu clear" reverts.
  if (strcmp(line, "imu") == 0) {
    Serial.printf("<<IMU {\"present\":%s,\"injected\":%s,\"ax\":%.3f,\"ay\":%.3f,\"az\":%.3f,"
                  "\"shake\":%.2f,\"napping\":%s,\"dizzy\":%s,"
                  "\"tilt\":%.2f,\"energy\":%.2f,\"dangling\":%s}>>\n",
                  imuSeen ? "true" : "false", imuInjected ? "true" : "false",
                  imuAx, imuAy, imuAz, shakeEnergy,
                  napping ? "true" : "false",
                  ((int32_t)(dizzyUntil - millis()) > 0) ? "true" : "false",
                  dangleTilt, motionEnergy, dangling ? "true" : "false");
    return;
  }
  if (strncmp(line, "imu set ", 8) == 0) {
    char* end = nullptr;
    float x = strtof(line + 8, &end);
    float y = strtof(end, &end);
    float z = strtof(end, &end);
    injAx = x; injAy = y; injAz = z;
    imuInjected = true;
    Serial.printf("<<IMU inject %.3f %.3f %.3f>>\n", x, y, z);
    return;
  }
  if (strcmp(line, "imu clear") == 0) {
    imuInjected = false;
    shakeEnergy = 0.0f;
    Serial.println("<<IMU inject cleared>>");
    return;
  }

  // Debug/HIL: replay a ritual. Hatching is a once-per-device one-shot
  // (NVS), so without this it becomes untestable the moment a board has
  // booted once. "ritual clear" un-hatches for a full unboxing rehearsal.
  if (strncmp(line, "ritual", 6) == 0) {
    const char* a = line[6] ? line + 7 : "";
    if (strcmp(a, "hatch") == 0)        ritualStart(RITUAL_HATCH, millis());
    else if (strcmp(a, "stretch") == 0) ritualStart(RITUAL_STRETCH, millis());
    else if (strcmp(a, "skip") == 0)    ritualSkip();
    else if (strcmp(a, "clear") == 0) {
      _prefs.begin("buddy", false);
      _prefs.remove("hatched");
      _prefs.end();
      Serial.println("<<RITUAL unhatched>>");
      return;
    }
    Serial.printf("<<RITUAL now=%s>>\n", ritualName());
    return;
  }

  // Debug/HIL: synthetic touchscreen contact. Drives the same edge/hold
  // logic as a real finger on the glass (tap = boop, hold = petting).
  // "touch" with no argument reports the live contact — raw panel
  // coordinates and the sprite coordinates they map to. This is the tool
  // for confirming the rotation inverse by hand: touch a known corner and
  // check the sprite coordinate matches what's drawn there.
  if (strcmp(line, "touch") == 0) {
    int tx = -1, ty = -1;
    bool have = touchPoint(&tx, &ty);
    Serial.printf("<<TOUCH {\"down\":%s,\"synth\":%s,\"point\":%s,\"x\":%d,\"y\":%d,"
                  "\"edges\":%lu,\"maxContactMs\":%lu,\"ok\":%s}>>\n",
                  halTouchDown() ? "true" : "false",
                  synthTouch ? "true" : "false",
                  have ? "true" : "false", tx, ty,
                  (unsigned long)touchEdges, (unsigned long)touchContactMaxMs,
                  halTouchReady() ? "true" : "false");
    return;
  }
  if (strcmp(line, "touch down") == 0 || strncmp(line, "touch down ", 11) == 0) {
    synthTouch = true;
    if (line[10]) {
      char* end = nullptr;
      long x = strtol(line + 11, &end, 10);
      long y = strtol(end, nullptr, 10);
      synthTouchX = (int)(x < 0 ? 0 : (x >= HAL_W ? HAL_W - 1 : x));
      synthTouchY = (int)(y < 0 ? 0 : (y >= HAL_H ? HAL_H - 1 : y));
    } else {
      synthTouchX = HAL_W / 2;
      synthTouchY = HAL_H / 2;
    }
    Serial.printf("<<TOUCH down %d %d>>\n", synthTouchX, synthTouchY);
    return;
  }
  if (strcmp(line, "touch up") == 0) {
    synthTouch = false;
    Serial.println("<<TOUCH up>>");
    return;
  }

  // Debug/HIL: enter the power-down path with a timer wake so the
  // round-trip is provable without a finger on the button. Bare
  // "deepsleep" defaults to a 5s wake; "deepsleep 0" is button-only —
  // exactly what the 4s physical hold does.
  if (strcmp(line, "deepsleep") == 0 || strncmp(line, "deepsleep ", 10) == 0) {
    uint32_t ms = line[9] ? (uint32_t)strtoul(line + 10, nullptr, 10) : 5000;
    Serial.printf("<<DEEPSLEEP ok wake=%lums>>\n", (unsigned long)ms);
    goodNight(ms);   // never returns
  }

  // Debug: high-level approval shortcut. Use "press a|b [ms]" when a test
  // needs to exercise the GPIO-level edge detector. Deliberately skips the
  // arming delay — that guards human fingers, not scripts.
  if (strncmp(line, "btn ", 4) == 0) {
    bool armed = promptPending();
    char which = line[4];
    if (which == 'a' || which == 'A') {
      if (armed) { sendApproval(true);  Serial.println("<<BTN a approve sent>>"); }
      else       { Serial.println("<<BTN a noop (no prompt)>>"); }
    } else if (which == 'b' || which == 'B') {
      if (armed) { sendApproval(false); Serial.println("<<BTN b deny sent>>"); }
      else       { Serial.println("<<BTN b noop (no prompt)>>"); }
    } else {
      Serial.println("<<BTN err (use a|b)>>");
    }
    return;
  }

  // Debug: arm a fake approval prompt so the button path can be tested
  // offline with no daemon connected. Renders "APPROVE?" on-screen and
  // enables A/B until answered. A real daemon JSON push overwrites this.
  if (strcmp(line, "mockprompt") == 0 || strcmp(line, "mockprompt fresh") == 0) {
    strncpy(tama.promptId, "DEBUG", sizeof(tama.promptId)-1);
    tama.promptId[sizeof(tama.promptId)-1] = 0;
    tama.promptApproval = true;
    responseSent = false;
    // Plain mockprompt backdates past the arming delay: the delay guards
    // humans racing a real prompt's arrival; tests want "press a" to work
    // immediately. "mockprompt fresh" keeps the real arrival time so HIL
    // can prove the arming window actually swallows early presses.
    promptArrivedMs = millis() - (line[10] ? 0 : PROMPT_ARM_MS);
    // Pre-empt loop()'s promptId-change detector — it runs later this same
    // iteration and would otherwise stamp promptArrivedMs = now, silently
    // undoing the backdate above.
    strncpy(lastPromptId, tama.promptId, sizeof(lastPromptId)-1);
    lastPromptId[sizeof(lastPromptId)-1] = 0;
    Serial.println("<<BTN mockprompt armed>>");
    return;
  }
  // Unknown commands are silently ignored — the daemon writes lots of
  // non-JSON noise on this channel and we don't want to log-spam.
}

// Boot-stage heap breadcrumb: free + largest contiguous block. The BLE
// connect path needs several contiguous KB at runtime; these lines make
// regressions in headroom visible in any captured boot log.
static void logHeap(const char* stage) {
  Serial.printf("[heap] %s: free=%lu big=%lu\n", stage,
                (unsigned long)ESP.getFreeHeap(), (unsigned long)ESP.getMaxAllocHeap());
}

void setup() {
  // Serial FIRST: halInit logs its touch/IMU probe results, and prints
  // before Serial.begin are dropped on native USB CDC — that hid a failed
  // FT3168 probe (dead touch, no evidence) for a whole debugging session.
  // On M5, M5Unified leaves cfg.serial_baudrate=0, so begin() doesn't call
  // Serial.begin() — without it Arduino-level reads (Serial.read in
  // dataPoll) silently fail. On the S3 board this maps to native USB CDC
  // and the baud rate is cosmetic.
  Serial.begin(115200);
#ifdef BOARD_WS_AMOLED_164
  // Native USB CDC: never let a write block the loop. If the host has the
  // port open but stops draining it (or a stale session lingers), a
  // buffered write can otherwise stall for its full timeout — mid-tap,
  // that reads as the pet freezing. Dropped debug bytes are the right
  // trade; the protocol host reads greedily.
  Serial.setTxTimeoutMs(0);
#endif
  halInit();   // board + display + input bring-up (rotation, speaker, LED)
  logHeap("after halInit");
  guardInit();   // WDT + crash-loop breaker; decides safeTier for the rest of setup
  const int safeTier = guardSafeTier();
  if (safeTier < 2) {
    startBt();
    logHeap("after BLE init");
  } else {
    Serial.println("[guard] safe mode tier 2 — BLE disabled, USB rescue only");
  }

  setDisplayBrightness(BRIGHT_MEDIUM);
  statsLoad();
  settingsLoad();
  petNameLoad();
  buddyInit();
  // Restore the buddy adopted via the on-device menu. A desktop heartbeat
  // species *change* still overrides it (loop's lastSpecies tracker).
  if (settings().species[0]) buddySetSpecies(settings().species);

  // BLE stays always-on; settings().bt is stored as a preference only.
  //
  // 8-bit sprite, not 16: full-screen 135x240 at 16bpp costs 64.8KB of
  // heap, which starved Bluedroid on the M5 so badly that a bonded BLE
  // reconnect OOMed inside GATT setup and panicked (fixed_queue_new →
  // vQueueDelete(NULL) assert → bootloop). At 8bpp the sprite costs
  // ~32KB; LGFX converts RGB565 draw sources automatically, and the buddy
  // art is flat-color so RGB332 is visually indistinguishable. The
  // native-res Pebble canvas (456x280 = 128KB at 8bpp) lives in PSRAM —
  // internal heap stays reserved for Bluedroid.
  spr.setColorDepth(8);
  if (HAL_LANDSCAPE) spr.setPsram(true);
  spr.createSprite(W, H);
  logHeap("after sprite");
  if (safeTier == 0) {
    characterInit(nullptr);  // scan /characters/ for whatever is installed
    logHeap("after characterInit");
  } else {
    // Safe mode: a poisoned character asset is a plausible boot-crash
    // culprit, and the procedural blob buddy renders without it.
    Serial.println("[guard] safe mode — skipping character assets");
  }
  gifAvailable = characterLoaded();
  buddyMode = true;
  characterSetPeek(false);
  buddySetPeek(false);

  {
    const Palette& p = characterPalette();
    spr.fillSprite(p.bg);
    spr.setTextDatum(MC_DATUM);
    spr.setTextSize(2 * S);
    if (ownerName()[0]) {
      char line[40];
      snprintf(line, sizeof(line), "%s's", ownerName());
      spr.setTextColor(p.text, p.bg);   spr.drawString(line, W/2, H/2 - 12 * S);
      spr.setTextColor(p.body, p.bg);   spr.drawString(petName(), W/2, H/2 + 12 * S);
    } else {
      // First boot, no owner pushed yet — say hi.
      spr.setTextColor(p.body, p.bg);   spr.drawString("Hello!", W/2, H/2 - 12 * S);
      spr.setTextSize(S);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString("a buddy appears", W/2, H/2 + 12 * S);
    }
    if (safeTier > 0) {
      spr.setTextSize(S);
      spr.setTextColor(HOT, p.bg);
      spr.drawString("safe mode", W/2, H - 28 * S);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString(safeTier >= 2 ? "connect via USB" : "buddy needs help", W/2, H - 16 * S);
    }
    spr.setTextDatum(TL_DATUM); spr.setTextSize(S);
    halPresent(spr);
    delay(1800);
  }

  // First-ever boot: hatch (§13). One-shot per device, flagged in NVS
  // before the sequence runs — a crash mid-hatch must not re-run the
  // unboxing moment on every subsequent boot.
  if (HAL_LANDSCAPE && !statsHatched()) {
    statsSetHatched();
    ritualStart(RITUAL_HATCH, millis());
  }

  Serial.println("buddy: ASCII mode");
}

void loop() {
  guardLoop();   // feed the task WDT; mark boot healthy after stable uptime
  halUpdate();
  t++;

  dataPoll(&tama);
  updateSyntheticPresses();

  {
    static char lastSpecies[16] = "";
    if (tama.species[0] && strcmp(tama.species, lastSpecies) != 0) {
      strncpy(lastSpecies, tama.species, sizeof(lastSpecies)-1);
      lastSpecies[sizeof(lastSpecies)-1] = 0;
      buddySetSpecies(tama.species);
      buddyInvalidate();
    }
  }

  // Morning stretch (§13): the first link-up after a long absence. There is
  // no RTC on this board, so "long" is measured with millis while powered,
  // and after a reboot that history is gone entirely. The spec's call: show
  // the stretch on the first connect after boot anyway, because a fresh
  // boot feels like waking up regardless.
  if (HAL_LANDSCAPE) {
    static bool prevConn = false;
    static bool everConn = false;
    static uint32_t droppedAt = 0;
    const uint32_t SIX_HOURS_MS = 6UL * 3600UL * 1000UL;
    bool conn = dataConnected();
    uint32_t nowM = millis();
    if (conn && !prevConn) {
      bool longAbsence = !everConn ||
                         (droppedAt != 0 && (nowM - droppedAt) >= SIX_HOURS_MS);
      if (longAbsence && !ritualActive()) ritualStart(RITUAL_STRETCH, nowM);
      everConn = true;
    } else if (!conn && prevConn) {
      droppedAt = nowM;
    }
    prevConn = conn;
  }

  motionTick(millis());

  // A completion becomes a gift the buddy holds for you (§8). Gated on the
  // same "Done"-prefixed msg the old HUD line used, so ordinary status
  // chatter ("no agents awake") never counts as a completion. Keyed on the
  // message text so a celebrate state that lingers across heartbeats arms
  // exactly one gift.
  if (HAL_LANDSCAPE) {
    static char lastDone[40] = "";
    if (strcmp(tama.pet, "celebrate") == 0 && strncmp(tama.msg, "Done", 4) == 0 &&
        strcmp(tama.msg, lastDone) != 0) {
      strncpy(lastDone, tama.msg, sizeof(lastDone) - 1);
      lastDone[sizeof(lastDone) - 1] = 0;
      strncpy(giftMsg, tama.msg, sizeof(giftMsg) - 1);
      giftMsg[sizeof(giftMsg) - 1] = 0;
      giftPending = true;
      Serial.printf("<<GIFT pending %.30s>>\n", giftMsg);
    }
  }

  baseState = derive(tama);
  activeState = baseState;
  // Recent boop: flash the heart face unless something urgent is on
  // screen. A sleeping face board does a sleep-peek instead (one eye
  // cracks open — handled inside faceTick), so sleep stays sleep there.
  bool boopActive = (int32_t)(boopUntil - millis()) > 0;
  if (boopActive && baseState != P_ATTENTION && baseState != P_DIZZY &&
      !(HAL_LANDSCAPE && baseState == P_SLEEP)) {
    activeState = P_HEART;
  }
  // Being shaken beats being petted; attention still wins (the card and
  // its full brightness must survive a bumpy desk).
  if ((int32_t)(dizzyUntil - millis()) > 0 && baseState != P_ATTENTION) {
    activeState = P_DIZZY;
  }
  // Captured before updateDisplayPower, which wakes the panel on any state
  // change: by the time the prompt-arrival branch below runs, screenOff has
  // already been cleared. The lantern's night-aware entry needs to know how
  // dark the room was when the prompt landed, not after we lit it.
  bool screenWasOff = screenOff;
  updateDisplayPower(activeState);

  if (strcmp(tama.promptId, lastPromptId) != 0) {
    strncpy(lastPromptId, tama.promptId, sizeof(lastPromptId)-1);
    lastPromptId[sizeof(lastPromptId)-1] = 0;
    responseSent = false;
    promptArrivedMs = millis();
    promptArrivedDark = screenWasOff;
  }

  // Route the screen mood (§2.1). Field brightness encodes how much the
  // buddy needs you, so the lantern is spent ONLY where a human is
  // blocking something — a passkey that must be typed, or a decision that
  // must be made. Everything else, however visually eventful, stays Night.
  if (HAL_LANDSCAPE) {
    uint32_t nowM = millis();
    if (blePasskey()) {
      moodSet(MOOD_LANTERN, screenWasOff);
    } else if (promptPending()) {
      moodSet(MOOD_LANTERN, promptArrivedDark);
      // Escalation replaces the numeric "waiting Ns" counter entirely:
      // urgency is light and motion, which read peripherally far better
      // than a stopwatch nobody is looking at.
      float waited = (float)(nowM - promptArrivedMs) / 1000.0f;
      moodEscalation((waited - 10.0f) / 2.0f, (waited - 120.0f) / 3.0f);
    } else if (activeState == P_DIZZY) {
      moodSet(MOOD_EMBER_K, screenWasOff);
    } else {
      // moodSet no-ops when the target already matches, so an in-flight
      // snuff or fade (which both retarget to Night themselves) keeps
      // running rather than being restarted every loop.
      moodSet(MOOD_NIGHT, screenWasOff);
    }
  }
  // A pending approval owns the buttons — close the menu before the button
  // handler can route a press to it. keep=false: an interrupt the user
  // didn't ask for must not adopt a character they never picked.
  if (promptPending() && menuActive()) {
    menuClose(false);
  }
  handleButtons();
  menuTick(millis());
  tuneTick(millis());
  brightnessTick();

  // Skip the paint when the present throttle would drop the frame anyway
  // — repainting the PSRAM canvas costs a few ms per pass. Input, data,
  // menu, and tune handling above still ran this iteration. (Always due
  // on M5, which presents every loop.)
  if (!halPresentDue()) {
    delay(HAL_LOOP_MS);
    return;
  }

  // Frame delta for every eased surface in the draw path, measured once
  // above the screen-priority chain so the mood keeps blooming under the
  // passkey and OTA takeovers too — those are moods in their own right
  // (§2 priorities 1-2), not a pause in the animation.
  uint32_t frameMs = millis();
  static uint32_t lastDrawMs = 0;
  float dt = (frameMs - lastDrawMs) / 1000.0f;
  lastDrawMs = frameMs;
  if (dt <= 0.0f || dt > 0.05f) dt = 0.024f;
  if (HAL_LANDSCAPE) moodTick(frameMs, dt);

  if (blePasskey()) {
    wakeDisplay();
    drawPasskey();
  } else if (otaActive()) {
    wakeDisplay();
    // Take over the screen during OTA — buddy redraws would race with
    // ble_bridge writes anyway, and the user wants to see real progress.
    spr.fillSprite(BLACK);
    spr.setTextDatum(TC_DATUM);
    spr.setTextSize(2 * S);
    spr.setTextColor(WHITE, BLACK);
    spr.drawString("Updating", CX, H / 6);
    spr.setTextSize(S);
    spr.setTextColor(LIGHTGREY, BLACK);
    spr.drawString("firmware…", CX, H / 6 + 18 * S);

    uint32_t total = otaTotal();
    uint32_t done = otaProgress();
    int pct = total > 0 ? (int)((done * 100) / total) : 0;
    if (pct > 100) pct = 100;
    int barX = W / 8, barY = CY_BASE - 7 * S, barW = W - W / 4, barH = 14 * S;
    spr.drawRoundRect(barX, barY, barW, barH, 3 * S, WHITE);
    int fillW = (barW - 4 * S) * pct / 100;
    if (fillW > 0) spr.fillRoundRect(barX + 2 * S, barY + 2 * S, fillW, barH - 4 * S, 2 * S, WHITE);

    char pctBuf[8];
    snprintf(pctBuf, sizeof(pctBuf), "%d%%", pct);
    spr.setTextSize(2 * S);
    spr.setTextColor(WHITE, BLACK);
    spr.drawString(pctBuf, CX, CY_BASE + 12 * S);

    spr.setTextSize(S);
    spr.setTextColor(LIGHTGREY, BLACK);
    spr.drawString("keep nearby", CX, H - 26 * S);
    spr.drawString("device will restart", CX, H - 14 * S);
  } else {
    // Landscape board: the screen is the character's face. Portrait M5
    // keeps the ASCII species art (and GIF character packs, which are
    // portrait-sized — not yet supported on the landscape board).
    drawCount++;
    const Palette& p = characterPalette();
    uint32_t nowMs = frameMs;

    int faceLift = 0;
    if (HAL_LANDSCAPE) {
      // Demanded-tier events take the screen, so a summoned card gets out
      // of the way instantly (§6) — no fade, it was never the priority.
      if (promptPending() || otaActive() || blePasskey() ||
          (int32_t)(dizzyUntil - nowMs) > 0) {
        glanceClose();
      }
      glanceTick(nowMs, dt);
      haloTick(activeState, dt);
      cardTick(nowMs, dt, promptPending());
      bubbleTick(nowMs, dt);
      // Advance the ritual clock exactly once per frame — ritualProgress
      // ends the ritual when it reaches 1, so calling it twice would drop
      // a frame of the sequence.
      float rt = ritualProgress(nowMs);
      // Nothing has hatched yet, so nothing else is on screen either: no
      // halo, no orbs, no face until the shell breaks.
      bool eggPhase = ritualIsHatch() && rt < 0.78f;
      // Sleep shows no sky: a sleeping buddy isn't watching anything.
      bool orbsVisible = (activeState != P_SLEEP) && !eggPhase;
      // A waiting gift is SUPPRESSED, not cleared, while a prompt or error
      // owns the screen — it's still yours, it just isn't the thing that
      // matters this second.
      bool giftShown = giftPending && !promptPending() &&
                       (int32_t)(dizzyUntil - nowMs) <= 0;
      orbsTick(nowMs, dt,
               orbsVisible ? tama.sessionsRunning : 0,
               orbsVisible ? tama.sessionsWaiting : 0,
               (orbsVisible && giftShown) ? 1 : 0);
      faceLift = animPx(glanceCover() * (float)FACE_GLANCE_LIFT);

      // Draw order is the priority stack from the bottom up: the field
      // carries the alert channel, the halo is ambient light around the
      // face, the orbs are the session sky, the face is the product.
      // Overlays land after this block.
      uint16_t accent = buddySpeciesColor();
      moodDrawField(spr, nowMs);
      if (!eggPhase) haloDraw(spr, nowMs, activeState, accent);
      // Orbs yield to a lit field exactly as the halo does — under a
      // lantern the only thing that matters is the decision.
      orbsDraw(spr, nowMs, accent, moodHaloGain() * (1.0f - glanceCover()));
      FaceOpts fo;
      fo.lift = faceLift;
      fo.color = moodFaceColor(accent);
      fo.bg = moodBackdrop(nowMs);
      fo.weight = moodStrokeWeight();
      fo.expectant = giftShown;
      fo.scale = ritualStretchScale(rt);
      fo.yawn = ritualYawning(rt);
      // Gaze priority (§3.3): the finger on the glass outranks a newly
      // spawned orb, which outranks the ambient glance drift. Something
      // touching the buddy is the most specific thing in its world.
      int tx = 0, ty = 0;
      if (touchPoint(&tx, &ty)) {
        fo.petting = true;
        fo.gazeBias = animClamp((float)(tx - W / 2) / (float)(W / 2), -1.0f, 1.0f);
      } else {
        fo.gazeBias = orbsGazeNudge(nowMs);
      }

      // Dangle (§10.2): while held, the eyes swing with the accelerometer
      // through a spring, so the face reads as having weight. Off the
      // sample directly rather than through a canned wobble — the whole
      // point is that it moves with YOUR hand.
      if (dangling) {
        dangleSprX.step(animClamp(imuAx, -1.0f, 1.0f), 2.2f, 0.45f, dt);
        dangleSprY.step(animClamp(imuAy, -1.0f, 1.0f), 2.2f, 0.45f, dt);
        // Mini summary floats up while airborne — picking the buddy up is
        // a question ("what's going on?") and this is the answer.
        char sum[40];
        snprintf(sum, sizeof(sum), "%u tasks - %u waiting",
                 tama.sessionsTotal, tama.sessionsWaiting);
        bubbleShow(sum, nowMs, 400, 0);
      } else {
        dangleSprX.step(0.0f, 3.0f, 0.75f, dt);
        dangleSprY.step(0.0f, 3.0f, 0.75f, dt);
      }
      fo.dangleX = animPx(dangleSprX.pos * 22.0f);
      fo.dangleY = animPx(dangleSprY.pos * 15.0f);
      // The hatch owns the whole screen until the shell breaks; after that
      // the newborn face takes over mid-ritual, which is the point of the
      // sequence — you watch it become the thing you'll live with.
      if (eggPhase) {
        ritualDrawHatch(spr, nowMs, rt);   // egg only, nothing hatched yet
      } else {
        faceTick(activeState, tama.activity, boopActive, fo);
      }
    } else {
      buddyTick(activeState);
    }
    if (menuActive()) {
      menuDraw(spr, nowMs);
    } else {
      int y = H - HAL_HUD_H;   // HUD block: status + sessions + prompt lines
      const int CPL = (W - 8 * S) / (6 * S);   // chars per HUD row
      spr.setTextSize(S);
      if (promptPending()) {
        const char* tool = tama.promptTool[0] ? tama.promptTool : "approve?";
        if (HAL_LANDSCAPE) {
          // §7: a rounded panel of ink on the lantern field, drawn in
          // bubble.h. Everything about urgency is carried by the field
          // (warming, quickening breath) rather than by a counter.
          cardDraw(spr, nowMs, tama);
        } else {
          // Portrait M5 keeps the original card verbatim — it has no mood
          // system, and it is the regression rig.
          spr.fillRect(0, y, W, H - y, p.bg);
          uint32_t waited = (nowMs - promptArrivedMs) / 1000;
          bool hot = waited >= 10;
          uint16_t pulse = ((nowMs / 500) & 1) ? (hot ? HOT : p.text) : p.textDim;
          spr.fillRect(0, 0, W, 20 * S, p.bg);
          spr.setTextDatum(TC_DATUM);
          spr.setTextColor(pulse, p.bg);
          spr.drawString("^ ^ ^", W / 2, S);
          spr.drawString("boop = yes", W / 2, 10 * S);
          spr.setTextDatum(TL_DATUM);
          spr.setTextColor(p.textDim, p.bg);
          spr.setCursor(4, y);
          spr.printf("%.16s asks:", tama.promptSource[0] ? tama.promptSource : "agent");
          spr.setTextColor(p.text, p.bg);
          spr.setCursor(4, y + 12);
          spr.printf("%.*s", CPL, tool);
          if (tama.promptHint[0]) {
            spr.setTextColor(p.textDim, p.bg);
            drawWrapped2(tama.promptHint, 4, y + 24, y + 36, CPL);
          }
          if (!tama.connected) {
            spr.setTextColor(HOT, p.bg);
            spr.setCursor(4 * S, H - 10 * S);
            spr.print("link lost!");
          } else {
            spr.setTextColor(hot ? HOT : p.textDim, p.bg);
            spr.setCursor(4 * S, H - 10 * S);
            spr.printf("waiting %lus", (unsigned long)waited);
          }
          spr.setTextDatum(BR_DATUM);
          spr.setTextColor(hot ? HOT : p.text, p.bg);
          spr.drawString("no >", W - 2 * S, H - 2 * S);
          spr.setTextDatum(TL_DATUM);
        }
      } else if (tama.promptId[0] && tama.promptApproval && responseSent) {
        // Decision feedback until the desktop clears the prompt. Deny is
        // deliberately neutral — the pet approves of good catches too.
        if (HAL_LANDSCAPE) {
          // A small bubble in Night mode, refreshed each frame so it lasts
          // exactly as long as the prompt does (§7). The field is busy
          // snuffing or fading underneath; the bubble rides on top of it.
          bubbleShow(lastDecisionApprove ? "yes!" : "okay", nowMs, 400,
                     lastDecisionApprove ? GREEN : 0);
        } else {
          spr.fillRect(0, y, W, H - y, p.bg);
          spr.setTextDatum(MC_DATUM);
          spr.setTextSize(2 * S);
          if (lastDecisionApprove) {
            spr.setTextColor(GREEN, p.bg);
            spr.drawString("yes!", W / 2, y + 24 * S);
          } else {
            spr.setTextColor(p.text, p.bg);
            spr.drawString("okay", W / 2, y + 24 * S);
          }
          spr.setTextSize(S);
          spr.setTextColor(p.textDim, p.bg);
          spr.drawString("sent", W / 2, y + 48 * S);
          spr.setTextDatum(TL_DATUM);
        }
      } else if (HAL_LANDSCAPE) {
        // Face-first resting screen (§3, §14): no HUD, no status text, no
        // counters — the face is the whole product. Everything the old
        // 104px block used to say now lives one "look" tap away.
        glanceDraw(spr, nowMs, tama, bleBonded(), dataLastLiveMs(),
                   giftPending ? 1 : 0);
      } else {
        spr.fillRect(0, y, W, H - y, p.bg);
        spr.setTextColor(tama.connected ? p.text : p.textDim, p.bg);
        spr.setCursor(4 * S, y);
        spr.print(tama.connected ? "connected" : "disconnected");
        spr.setTextColor(p.body, p.bg);
        spr.setCursor(4 * S, y + 12 * S);
        spr.printf("%s | %s", tama.pet[0] ? tama.pet : "-", tama.species[0] ? tama.species : "-");
        spr.setTextColor(p.textDim, p.bg);
        spr.setCursor(4 * S, y + 24 * S);
        spr.printf("sessions: %u r%u w%u", tama.sessionsTotal, tama.sessionsRunning, tama.sessionsWaiting);
        // Surface the "Done: …" completion summary on the bottom line during
        // celebrate/idle. Gated on the prefix so status chatter (e.g. "no
        // agents awake") doesn't wear the completion green.
        if (strncmp(tama.msg, "Done", 4) == 0 &&
            (strcmp(tama.pet, "celebrate") == 0 || strcmp(tama.pet, "idle") == 0)) {
          spr.setTextColor(GREEN, p.bg);
          spr.setCursor(4 * S, y + 36 * S);
          spr.printf("%.*s", CPL, tama.msg);
        }
      }
    }
    // Speech sits above everything on the buddy screen — it is the buddy
    // answering, so nothing it says should end up behind a card.
    if (HAL_LANDSCAPE) bubbleDraw(spr, nowMs, faceLift);
  }
  if (!screenOff) halPresent(spr);

  delay(HAL_LOOP_MS);
}
