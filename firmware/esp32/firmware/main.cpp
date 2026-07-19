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
const int W = HAL_W, H = HAL_H;
const int CX = W / 2;
const int CY_BASE = H / 2;

// Colors used across multiple UI surfaces.
const uint16_t HOT   = 0xFA20;   // red-orange: warnings, impatience, deny

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
bool     responseSent = false;

const uint8_t BRIGHT_DIM = 40;
const uint8_t BRIGHT_MEDIUM = 120;
const uint8_t BRIGHT_FULL = 220;
const uint32_t SLEEP_DIM_MS = 60000;
const uint32_t SLEEP_OFF_MS = 600000;
const uint32_t BTN_A_LONG_MS = 1500;
const uint32_t BOOP_REACT_MS = 2500;
static uint8_t currentBrightness = 0xFF;
static uint32_t boopUntil = 0;

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

static void sendCmd(const char* json) {
  Serial.println(json);
  size_t n = strlen(json);
  bleWrite((const uint8_t*)json, n);
  bleWrite((const uint8_t*)"\n", 1);
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

static void setDisplayBrightness(uint8_t brightness) {
  if (screenOff || currentBrightness == brightness) return;
  halSetBrightness(brightness);
  currentBrightness = brightness;
}

static void playStateChirp(PersonaState state) {
  if (tama.muted || !settings().sound) return;
  switch (state) {
    case P_ATTENTION:
      beep(880, 90); delay(110);
      beep(1245, 90);
      break;
    case P_CELEBRATE:
      if (!tama.celebrate) break;
      beep(988, 70); delay(85);
      beep(1175, 70); delay(85);
      beep(1397, 80);
      break;
    case P_DIZZY:
      beep(330, 180);
      break;
    default:
      break;
  }
}

static void updateDisplayPower(PersonaState state) {
  static PersonaState prevState = P_SLEEP;
  static uint32_t sleepSince = 0;
  uint32_t now = millis();
  bool changed = state != prevState;

  if (changed) {
    prevState = state;
    playStateChirp(state);
    if (state == P_SLEEP) {
      sleepSince = now;
    } else {
      wakeDisplay();
    }
  }

  if (state == P_SLEEP) {
    if (sleepSince == 0) sleepSince = now;
    uint32_t asleepFor = now - sleepSince;
    if (!manualScreenOff && asleepFor >= SLEEP_OFF_MS) {
      sleepDisplay(false);
    } else if (!screenOff && asleepFor >= SLEEP_DIM_MS) {
      setDisplayBrightness(BRIGHT_DIM);
    } else if (!screenOff) {
      setDisplayBrightness(BRIGHT_MEDIUM);
    }
    return;
  }

  setDisplayBrightness((state == P_ATTENTION || state == P_DIZZY) ? BRIGHT_FULL : BRIGHT_MEDIUM);
}

void drawPasskey() {
  const Palette& p = characterPalette();
  spr.fillSprite(p.bg);
  spr.setTextSize(1);
  spr.setTextColor(p.textDim, p.bg);
  spr.setCursor(8, 56);  spr.print("BLUETOOTH PAIRING");
  spr.setCursor(8, H - 56); spr.print("enter on desktop:");
  spr.setTextSize(3);
  spr.setTextColor(p.text, p.bg);
  char b[8]; snprintf(b, sizeof(b), "%06lu", (unsigned long)blePasskey());
  spr.setCursor((W - 18 * 6) / 2, CY_BASE - 10);
  spr.print(b);
}

PersonaState derive(const TamaState& s) {
  if (!s.connected) return P_SLEEP;
  if (strcmp(s.pet, "sleep") == 0)     return P_SLEEP;
  if (strcmp(s.pet, "busy") == 0)      return P_BUSY;
  if (strcmp(s.pet, "attention") == 0) return P_ATTENTION;
  if (strcmp(s.pet, "celebrate") == 0) return P_CELEBRATE;
  if (strcmp(s.pet, "error") == 0)     return P_DIZZY;   // Gap C: explicit StopFailure
  if (strcmp(s.pet, "thinking") == 0)  return P_BUSY;    // calm working face; avoids heart-eyes for thought.
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
}

// Pet-affection reaction: a short heart-face flash when the BOOP button is
// pressed outside of a pending approval. Device-local for now — the desktop
// doesn't hear about boops yet.
static void boopPet() {
  boopUntil = millis() + BOOP_REACT_MS;
  beep(1245, 60);
  buddyInvalidate();
}

// Three logical buttons (see hal.h for the physical mapping):
//   BOOP   — approve when a prompt is armed; boop the pet otherwise.
//            Long-press (outside a prompt) toggles screen sleep.
//   REJECT — deny on press when a prompt is armed.
//   MENU   — cycle to the next species (absent on M5; synthetic "press m"
//            still exercises it there).
// Any press wakes the screen; a wake-press never doubles as an action.
static void __attribute__((noinline)) handleButtons() {
  static bool prevBoop = false, prevRej = false, prevMenu = false;
  static uint32_t boopDownAt = 0;
  static bool suppressBoopRelease = false;
  static bool boopLongHandled = false;

  bool boop = readBtn(HAL_BTN_BOOP);
  bool rej  = readBtn(HAL_BTN_REJECT);
  bool menu = readBtn(HAL_BTN_MENU);
  bool armed = tama.promptId[0] && tama.promptApproval && !responseSent;
  uint32_t now = millis();
  bool wasOff = screenOff;

  if ((!prevBoop && boop) || (!prevRej && rej) || (!prevMenu && menu)) {
    wakeDisplay();
    if (!prevBoop && boop) {
      boopDownAt = now;
      suppressBoopRelease = wasOff;
      boopLongHandled = false;
    }
  }

  if (prevBoop && boop && !armed && !boopLongHandled && !suppressBoopRelease &&
      now - boopDownAt >= BTN_A_LONG_MS) {
    sleepDisplay(true);
    suppressBoopRelease = true;
    boopLongHandled = true;
  }

  bool boopRelease = prevBoop && !boop;
  bool rejPress = !prevRej && rej;
  bool menuPress = !prevMenu && menu;
  if (boopRelease) {
    if (now - boopDownAt >= BTN_A_LONG_MS) suppressBoopRelease = true;
    if (!suppressBoopRelease) {
      if (armed) sendApproval(true);
      else boopPet();
    }
    suppressBoopRelease = false;
    boopLongHandled = false;
  }
  if (rejPress && armed) sendApproval(false);
  if (menuPress && !wasOff) {
    buddyNextSpecies();
    buddyInvalidate();
    Serial.printf("<<MENU species=%s>>\n", buddySpeciesName());
  }

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
  Serial.printf("<<PONG {\"fw\":\"%s\",\"git\":\"%s\",\"board\":\"" HAL_BOARD_NAME "\","
                "\"up\":%lu,\"heap\":%lu,\"heapMin\":%lu,\"heapBig\":%lu,"
                "\"reset\":\"%s\",\"panics\":%lu,\"early\":%lu,\"safe\":%d}>>\n",
                FW_VERSION, GIT_SHA, (unsigned long)millis(), (unsigned long)ESP.getFreeHeap(),
                (unsigned long)ESP.getMinFreeHeap(), (unsigned long)ESP.getMaxAllocHeap(),
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
  doc["promptId"] = tama.promptId;
  doc["promptTool"] = tama.promptTool;
  doc["promptHint"] = tama.promptHint;
  doc["promptSource"] = tama.promptSource;
  doc["promptApproval"] = tama.promptApproval;
  doc["responseSent"] = responseSent;
  doc["muted"] = tama.muted;
  doc["screenOff"] = screenOff;
  doc["brightness"] = currentBrightness == 0xFF ? 0 : currentBrightness;
  doc["persona"] = personaNames[derive(tama)];
  doc["activePersona"] = personaNames[activeState];
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
// (135*2=270 is, 140*2=280 isn't) — concatenated chunks still form one
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

  int rot = halDisplayRotation();
  int w   = spr.width();
  int h   = spr.height();
  if (w <= 0 || w > 256 || h <= 0) {
    Serial.println("<<SCR_ERR bad-dims>>");
    restoreLogLevel();
    return;
  }

  Serial.printf("\n<<SCR_BEGIN W=%d H=%d ROT=%d FMT=RGB565LE>>\n", w, h, rot);

  uint8_t bytes[2 + 256 * 2];   // carried remainder + one row
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

  // Debug: high-level approval shortcut. Use "press a|b [ms]" when a test
  // needs to exercise the GPIO-level edge detector.
  if (strncmp(line, "btn ", 4) == 0) {
    bool armed = tama.promptId[0] && tama.promptApproval && !responseSent;
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
  if (strcmp(line, "mockprompt") == 0) {
    strncpy(tama.promptId, "DEBUG", sizeof(tama.promptId)-1);
    tama.promptId[sizeof(tama.promptId)-1] = 0;
    tama.promptApproval = true;
    responseSent = false;
    promptArrivedMs = millis();
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
  halInit();   // board + display + input bring-up (rotation, speaker, LED)
  // On M5, M5Unified leaves cfg.serial_baudrate=0, so begin() doesn't call
  // Serial.begin() — without it Arduino-level reads (Serial.read in
  // dataPoll) silently fail. On the S3 board this maps to native USB CDC
  // and the baud rate is cosmetic. Init explicitly so the USB command
  // channel — JSON daemon pushes, "screenshot" — actually works.
  Serial.begin(115200);
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

  // BLE stays always-on; settings().bt is stored as a preference only.
  //
  // 8-bit sprite, not 16: full-screen 135x240 at 16bpp costs 64.8KB of
  // heap, which starved Bluedroid on the M5 so badly that a bonded BLE
  // reconnect OOMed inside GATT setup and panicked (fixed_queue_new →
  // vQueueDelete(NULL) assert → bootloop). At 8bpp the sprite costs
  // ~32KB; LGFX converts RGB565 draw sources automatically, and the buddy
  // art is flat-color so RGB332 is visually indistinguishable. The S3
  // board has headroom to spare but keeps 8bpp so both boards render the
  // exact same bytes (halPresent widens to RGB565 on the way out).
  spr.setColorDepth(8);
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
    spr.setTextSize(2);
    if (ownerName()[0]) {
      char line[40];
      snprintf(line, sizeof(line), "%s's", ownerName());
      spr.setTextColor(p.text, p.bg);   spr.drawString(line, W/2, H/2 - 12);
      spr.setTextColor(p.body, p.bg);   spr.drawString(petName(), W/2, H/2 + 12);
    } else {
      // First boot, no owner pushed yet — say hi.
      spr.setTextColor(p.body, p.bg);   spr.drawString("Hello!", W/2, H/2 - 12);
      spr.setTextSize(1);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString("a buddy appears", W/2, H/2 + 12);
    }
    if (safeTier > 0) {
      spr.setTextSize(1);
      spr.setTextColor(HOT, p.bg);
      spr.drawString("safe mode", W/2, H - 28);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString(safeTier >= 2 ? "connect via USB" : "buddy needs help", W/2, H - 16);
    }
    spr.setTextDatum(TL_DATUM); spr.setTextSize(1);
    halPresent(spr);
    delay(1800);
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

  baseState = derive(tama);
  activeState = baseState;
  // Recent boop: flash the heart face unless something urgent is on screen.
  if ((int32_t)(boopUntil - millis()) > 0 && baseState != P_ATTENTION && baseState != P_DIZZY) {
    activeState = P_HEART;
  }
  updateDisplayPower(activeState);

  if (strcmp(tama.promptId, lastPromptId) != 0) {
    strncpy(lastPromptId, tama.promptId, sizeof(lastPromptId)-1);
    lastPromptId[sizeof(lastPromptId)-1] = 0;
    responseSent = false;
    promptArrivedMs = millis();
  }
  handleButtons();

  if (blePasskey()) {
    wakeDisplay();
    drawPasskey();
  } else if (otaActive()) {
    wakeDisplay();
    // Take over the screen during OTA — buddy redraws would race with
    // ble_bridge writes anyway, and the user wants to see real progress.
    spr.fillSprite(BLACK);
    spr.setTextDatum(TC_DATUM);
    spr.setTextSize(2);
    spr.setTextColor(WHITE, BLACK);
    spr.drawString("Updating", CX, 40);
    spr.setTextSize(1);
    spr.setTextColor(LIGHTGREY, BLACK);
    spr.drawString("firmware…", CX, 70);

    uint32_t total = otaTotal();
    uint32_t done = otaProgress();
    int pct = total > 0 ? (int)((done * 100) / total) : 0;
    if (pct > 100) pct = 100;
    int barX = 12, barY = 110, barW = W - 24, barH = 14;
    spr.drawRoundRect(barX, barY, barW, barH, 3, WHITE);
    int fillW = (barW - 4) * pct / 100;
    if (fillW > 0) spr.fillRoundRect(barX + 2, barY + 2, fillW, barH - 4, 2, WHITE);

    char pctBuf[8];
    snprintf(pctBuf, sizeof(pctBuf), "%d%%", pct);
    spr.setTextSize(2);
    spr.setTextColor(WHITE, BLACK);
    spr.drawString(pctBuf, CX, 140);

    spr.setTextSize(1);
    spr.setTextColor(LIGHTGREY, BLACK);
    spr.drawString("keep nearby", CX, 180);
    spr.drawString("device will restart", CX, 195);
  } else {
    buddyTick(activeState);
    const Palette& p = characterPalette();
    int y = H - 70;   // HUD block: status + sessions + prompt lines
    spr.fillRect(0, y, W, H - y, p.bg);
    spr.setTextSize(1);
    spr.setTextColor(tama.connected ? p.text : p.textDim, p.bg);
    spr.setCursor(4, y);
    spr.print(tama.connected ? "connected" : "disconnected");
    spr.setTextColor(p.body, p.bg);
    spr.setCursor(4, y + 12);
    spr.printf("%s | %s", tama.pet[0] ? tama.pet : "-", tama.species[0] ? tama.species : "-");
    spr.setTextColor(p.textDim, p.bg);
    spr.setCursor(4, y + 24);
    spr.printf("sessions: %u r%u w%u", tama.sessionsTotal, tama.sessionsRunning, tama.sessionsWaiting);
    if (tama.promptId[0] && tama.promptApproval) {
      // Surface the tool + hint so the user can decide without alt-tabbing.
      // The desktop popover is the primary approval UI; this mirrors enough to glance.
      uint32_t waited = (millis() - promptArrivedMs) / 1000;
      spr.setTextColor(waited >= 10 ? HOT : p.text, p.bg);
      spr.setCursor(4, y + 36);
      spr.printf("APPROVE? %lus", (unsigned long)waited);
      if (tama.promptTool[0]) {
        spr.setTextColor(p.text, p.bg);
        spr.setCursor(4, y + 48);
        spr.printf("%.18s", tama.promptTool);
      }
      if (tama.promptHint[0]) {
        spr.setTextColor(p.textDim, p.bg);
        spr.setCursor(4, y + 60);
        spr.printf("%.21s", tama.promptHint);
      }
    } else if (tama.msg[0] && (strcmp(tama.pet, "celebrate") == 0 || strcmp(tama.pet, "idle") == 0)) {
      // Surface the "Done: …" completion summary on the bottom line during
      // celebrate/idle when the desktop has populated msg with a completion.
      spr.setTextColor(GREEN, p.bg);
      spr.setCursor(4, y + 36);
      spr.printf("%.21s", tama.msg);
    }
  }
  if (!screenOff) halPresent(spr);

  delay(16);
}
