#include <M5StickCPlus2.h>
#include <esp_log.h>
#include <esp_system.h>
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

M5Canvas spr(&StickCP2.Display);

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
const int W = 135, H = 240;
const int CX = W / 2;
const int CY_BASE = 120;
          // red LED, active-low

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
static uint8_t currentBrightness = 0xFF;

struct SyntheticPress {
  bool active = false;
  uint32_t releaseAt = 0;
};

static SyntheticPress synthA;
static SyntheticPress synthB;

static void beep(uint16_t freq, uint16_t dur) {
  if (settings().sound && !tama.muted) StickCP2.Speaker.tone(freq, dur);
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
    StickCP2.Display.wakeup();
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
    StickCP2.Display.sleep();
    screenOff = true;
  }
  manualScreenOff = manual;
}

static void setDisplayBrightness(uint8_t brightness) {
  if (screenOff || currentBrightness == brightness) return;
  StickCP2.Display.setBrightness(brightness);
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
  spr.setCursor(8, 184); spr.print("enter on desktop:");
  spr.setTextSize(3);
  spr.setTextColor(p.text, p.bg);
  char b[8]; snprintf(b, sizeof(b), "%06lu", (unsigned long)blePasskey());
  spr.setCursor((W - 18 * 6) / 2, 110);
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
  if (synthA.active && (int32_t)(now - synthA.releaseAt) >= 0) {
    synthA.active = false;
    Serial.println("<<PRESS a up>>");
  }
  if (synthB.active && (int32_t)(now - synthB.releaseAt) >= 0) {
    synthB.active = false;
    Serial.println("<<PRESS b up>>");
  }
}

static bool readBtn(int pin) {
  updateSyntheticPresses();
  if (pin == 37 && synthA.active) return LOW;
  if (pin == 39 && synthB.active) return LOW;
  return digitalRead(pin);
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

static void __attribute__((noinline)) handleButtons() {
  static bool prevA = HIGH, prevB = HIGH;
  static uint32_t aDownAt = 0;
  static bool suppressARelease = false;
  static bool aLongHandled = false;

  bool a = readBtn(37);
  bool b = readBtn(39);
  bool armed = tama.promptId[0] && tama.promptApproval && !responseSent;
  uint32_t now = millis();

  if ((prevA == HIGH && a == LOW) || (prevB == HIGH && b == LOW)) {
    bool wasOff = screenOff;
    wakeDisplay();
    if (prevA == HIGH && a == LOW) {
      aDownAt = now;
      suppressARelease = wasOff;
      aLongHandled = false;
    }
  }

  if (prevA == LOW && a == LOW && !armed && !aLongHandled && !suppressARelease &&
      now - aDownAt >= BTN_A_LONG_MS) {
    sleepDisplay(true);
    suppressARelease = true;
    aLongHandled = true;
  }

  bool approve = prevA == LOW && a == HIGH;
  bool deny = prevB == HIGH && b == LOW;
  if (approve) {
    if (now - aDownAt >= BTN_A_LONG_MS) suppressARelease = true;
    if (armed && !suppressARelease) sendApproval(true);
    suppressARelease = false;
    aLongHandled = false;
  }
  if (deny && armed) sendApproval(false);

  prevA = a;
  prevB = b;
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
  Serial.printf("<<PONG {\"fw\":\"%s\",\"git\":\"%s\",\"up\":%lu,\"heap\":%lu}>>\n",
                FW_VERSION, GIT_SHA, (unsigned long)millis(), (unsigned long)ESP.getFreeHeap());
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
  doc["rot"] = StickCP2.Display.getRotation();
  doc["mode"] = currentDataMode();
  doc["rtcValid"] = dataRtcValid();
  doc["nLines"] = tama.nLines;
  doc["btName"] = btName;
  doc["bleConnected"] = bleConnected();
  doc["bleSecure"] = bleSecure();
  doc["lineGen"] = tama.lineGen;

  Serial.print("<<STATE ");
  serializeJson(doc, Serial);
  Serial.println(">>");
}

static void schedulePress(char which, uint32_t ms) {
  if (ms == 0) ms = 1;
  if (ms > 5000) ms = 5000;
  uint32_t releaseAt = millis() + ms;
  if (which == 'a' || which == 'A') {
    synthA.active = true;
    synthA.releaseAt = releaseAt;
    Serial.println("<<PRESS a down>>");
  } else if (which == 'b' || which == 'B') {
    synthB.active = true;
    synthB.releaseAt = releaseAt;
    Serial.println("<<PRESS b down>>");
  } else {
    Serial.println("<<PRESS err (use a|b)>>");
  }
}

// Dump the LCD as base64 RGB565 over USB serial. Reads from panel RAM
// (not the sprite) so direct-to-LCD draws — landscape clock, GIF frames,
// boot screen — are captured exactly as the user sees them. Triggered by
// sending the line "screenshot\n" on USB serial; framed with sentinels
// so the host can ignore unrelated log lines on the same channel.
//
// Per-row read keeps RAM use to ~700 bytes (vs. 64KB for full-frame).
// Each row is W*2 bytes; W=135 → 270 (90 b64 groups), W=240 → 480 (160
// groups). Both are multiples of 3, so per-row b64 chunks have no mid-
// stream padding — concatenated chunks form one valid base64 stream.
static void dumpScreenshot() {
  static const char b64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  esp_log_level_set("*", ESP_LOG_NONE);

  int rot = StickCP2.Display.getRotation();
  int w   = StickCP2.Display.width();
  int h   = StickCP2.Display.height();
  if (w <= 0 || w > 256 || h <= 0) {
    Serial.println("<<SCR_ERR bad-dims>>");
    restoreLogLevel();
    return;
  }

  Serial.printf("\n<<SCR_BEGIN W=%d H=%d ROT=%d FMT=RGB565LE>>\n", w, h, rot);

  uint16_t row[256];
  char enc[((256 * 2 + 2) / 3) * 4 + 4];
  uint32_t crc = 0;
  uint32_t rawLen = 0;
  for (int y = 0; y < h; y++) {
    StickCP2.Display.readRect(0, y, w, 1, row);
    const uint8_t* in = (const uint8_t*)row;
    int n = w * 2;
    crc = crc32Update(crc, in, n);
    rawLen += n;
    int o = 0;
    for (int i = 0; i + 2 < n; i += 3) {
      uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i+1] << 8) | (uint32_t)in[i+2];
      enc[o++] = b64[(v >> 18) & 0x3F];
      enc[o++] = b64[(v >> 12) & 0x3F];
      enc[o++] = b64[(v >>  6) & 0x3F];
      enc[o++] = b64[ v        & 0x3F];
    }
    Serial.write((const uint8_t*)enc, o);
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

void setup() {
  auto _cfg = M5.config(); StickCP2.begin(_cfg);
  // M5Unified leaves cfg.serial_baudrate=0, so StickCP2.begin() doesn't
  // call Serial.begin(). Without it, the framework's own debug logs still
  // reach the host (they go straight to UART), but Arduino-level reads
  // (Serial.read in dataPoll) silently fail. Init explicitly so USB
  // command channel — JSON daemon pushes, "screenshot" — actually works.
  Serial.begin(115200);
  StickCP2.Display.setRotation(0);
  StickCP2.Speaker.begin();
  startBt();
  
  StickCP2.Power.setLed(0);   // off
  setDisplayBrightness(BRIGHT_MEDIUM);
  statsLoad();
  settingsLoad();
  petNameLoad();
  buddyInit();

  // BLE stays always-on; settings().bt is stored as a preference only.
  spr.createSprite(W, H);
  characterInit(nullptr);  // scan /characters/ for whatever is installed
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
    spr.setTextDatum(TL_DATUM); spr.setTextSize(1);
    spr.pushSprite(0, 0);
    delay(1800);
  }

  Serial.println("buddy: ASCII mode");
}

void loop() {
  StickCP2.update();
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
    int y = 170;
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
      // docs/BUGS.md N1: surface the tool + hint so the user can decide without alt-tabbing.
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
  if (!screenOff) spr.pushSprite(0, 0);

  delay(16);
}
