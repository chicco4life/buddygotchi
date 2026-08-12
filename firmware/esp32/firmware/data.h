#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include "hal/hal.h"
#include "ble_bridge.h"
#include "xfer.h"
#include "ota.h"

struct TamaState {
  char     pet[12];           // "sleep","idle","busy","attention","celebrate"
  char     species[16];
  char     desktop[16];       // "connected" or "disconnected"
  uint8_t  sessionsTotal;
  uint8_t  sessionsRunning;
  uint8_t  sessionsWaiting;
  bool     celebrate;
  uint32_t lastUpdated;
  char     msg[24];
  char     activity[10];      // what the agent is doing: verify/read/write/shell/web/work
  bool     muted;
  bool     connected;
  char     lines[6][81];
  uint8_t  nLines;
  uint16_t lineGen;          // bumps when lines change — lets UI reset scroll
  // Pending permission request ID; empty = no prompt. Echoed back verbatim
  // with the decision, and the desktop matches it by exact equality — so a
  // silent truncation here is a decision the Mac will never recognise. It
  // used to be [40], which a "<36-char session uuid>_<12>" id overran by 9
  // chars: the crown worked, the card latched "yes!", and the reply was
  // dropped desk-side. The desktop now sends ~21, so this is pure headroom.
  char     promptId[64];
  char     promptTool[24];
  char     promptHint[64];
  char     promptSource[16];
  bool     promptApproval;
  char     promptLabel[24];
  // Personality (desktop System P). All optional on the wire — absent keys
  // mean the state is over, so each parse clears what it doesn't see.
  bool     greet;             // return-greeting window is live
  uint8_t  greetLevel;        // 1 = glad, 2 = the big missed-you
  char     moodStr[12];       // "expectant" / "surprised" / ""
  char     effort[10];        // light/normal/hard/grinding, busy only
  uint8_t  celebrateLevel;    // 1..3 payoff size, 0 = not celebrating
  // Agent embodiment overlay (desktop System E). agentEmotion[0] == 0 means
  // no overlay. The desktop guarantees these never ride a frame that also
  // carries a prompt (S1); the renderer still re-checks before drawing.
  char     agentSrc[16];
  char     agentColor[12];
  char     agentEmotion[20];
  char     agentIntensity[8];
  char     agentMotion[16];
  char     agentSay[44];
  char     agentDelivery[10];
};

// ---------------------------------------------------------------------------
// Three modes, checked in priority order:
//   demo   → auto-cycle fake scenarios every 8s, ignore live data
//   live   → JSON arrived in the last 15s over USB or BT
//   asleep → no data, all zeros, "no agents awake"
// ---------------------------------------------------------------------------

static uint32_t _lastLiveMs = 0;
static uint32_t _lastBtByteMs = 0;   // hasClient() lies; track actual BT traffic
static bool     _demoMode   = false;
static uint8_t  _demoIdx    = 0;
static uint32_t _demoNext   = 0;

struct _Fake { const char* n; const char* pet; uint8_t t,r,w; };
static const _Fake _FAKES[] = {
  {"asleep","sleep",0,0,0}, {"one idle","idle",1,0,0},
  {"busy","busy",4,3,0}, {"attention","attention",2,1,1},
  {"completed","celebrate",1,0,0},
};

inline void dataSetDemo(bool on) {
  _demoMode = on;
  if (on) { _demoIdx = 0; _demoNext = millis(); }
}
inline bool dataDemo() { return _demoMode; }

// The desktop keepalive is 10s; 1.5x headroom, same rationale as
// dataBtActive(). This used to be 30s, which left a dead desktop's approval
// card on glass and ANSWERABLE for up to 30s — a press in that window
// latched "yes!" while the decision went nowhere.
inline bool dataConnected() {
  return _lastLiveMs != 0 && (millis() - _lastLiveMs) <= 15000;
}

// millis() of the last live frame, 0 if none since boot. The glance card
// turns this into "link lost - 12m"; the resting screen never says it out
// loud (link loss shows as a nap — PEBBLE-UX §9.1).
inline uint32_t dataLastLiveMs() { return _lastLiveMs; }

// Is msg a completion summary rather than status chatter? Knowing that the
// bridge marks completions with a "Done" prefix is wire-format knowledge,
// which is data.h's job — loop() and the portrait HUD were each matching
// the string themselves.
//
// Deliberately only the PREFIX test. Callers pair it with their own pet
// gate, because they are asking different questions: arming a gift keys on
// the celebrate *transition*, while the HUD line lingers through idle too.
// Folding both into one predicate quietly let a plain idle heartbeat arm a
// gift.
inline bool dataHasDoneSummary(const TamaState& s) {
  return strncmp(s.msg, "Done", 4) == 0;
}

inline bool dataBtActive() {
  // Desktop's idle keepalive is ~10s; give it 1.5x headroom.
  return _lastBtByteMs != 0 && (millis() - _lastBtByteMs) <= 15000;
}

inline const char* dataScenarioName() {
  if (_demoMode) return _FAKES[_demoIdx].n;
  if (dataConnected()) return dataBtActive() ? "bt" : "usb";
  return "none";
}

// Set true once the bridge sends a time sync — until then the RTC may
// hold whatever was on the coin cell (or 2000-01-01 if it lost power).
static bool _rtcValid = false;
inline bool dataRtcValid() { return _rtcValid; }

// Frame-loss telemetry, surfaced in the `state` reply alongside bleDrops.
// A healthy link shows both at 0 forever; a climbing parseFails with a
// napping pet is the "desktop sends frames the device can't read" failure
// the Swift-side size cap exists to prevent.
static uint32_t _parseFailCount = 0;     // deserializeJson rejected a line
static uint32_t _lineOverflowCount = 0;  // line outgrew its buffer, discarded
inline uint32_t dataParseFails() { return _parseFailCount; }
inline uint32_t dataLineOverflows() { return _lineOverflowCount; }

static void __attribute__((noinline)) _parsePrompt(JsonDocument& doc, TamaState* out) {
  const char* pid = doc["promptId"];
  const char* pt = doc["promptTool"];
  const char* ph = doc["promptHint"];
  const char* ps = doc["promptSource"];
  const char* pl = doc["promptLabel"];
  if (pid) {
    strncpy(out->promptId, pid, sizeof(out->promptId)-1); out->promptId[sizeof(out->promptId)-1]=0;
    strncpy(out->promptTool, pt ? pt : "", sizeof(out->promptTool)-1); out->promptTool[sizeof(out->promptTool)-1]=0;
    strncpy(out->promptHint, ph ? ph : "", sizeof(out->promptHint)-1); out->promptHint[sizeof(out->promptHint)-1]=0;
    strncpy(out->promptSource, ps ? ps : "", sizeof(out->promptSource)-1); out->promptSource[sizeof(out->promptSource)-1]=0;
    strncpy(out->promptLabel, pl ? pl : "", sizeof(out->promptLabel)-1); out->promptLabel[sizeof(out->promptLabel)-1]=0;
    out->promptApproval = doc["promptApproval"] | false;
  } else {
    out->promptId[0] = 0; out->promptTool[0] = 0; out->promptApproval = false;
    out->promptHint[0] = 0; out->promptSource[0] = 0; out->promptLabel[0] = 0;
  }
}

static void __attribute__((noinline)) _parsePersonality(JsonDocument& doc, TamaState* out) {
  // Unlike `activity` (omitted-means-unchanged), every field here is
  // omitted-means-over: the desktop sends full state each frame with nils
  // dropped, so a key's absence IS the expiry signal (greet window closed,
  // agent lease lapsed).
  out->greet = doc["greet"] | false;
  out->greetLevel = out->greet ? (uint8_t)(doc["greetLevel"] | 1) : 0;
  auto cpy = [](char* dst, size_t n, const char* src) {
    strncpy(dst, src ? src : "", n - 1);
    dst[n - 1] = 0;
  };
  cpy(out->moodStr, sizeof(out->moodStr), doc["mood"]);
  cpy(out->effort, sizeof(out->effort), doc["effort"]);
  out->celebrateLevel = doc["celebrateLevel"] | 0;
  cpy(out->agentEmotion, sizeof(out->agentEmotion), doc["agentEmotion"]);
  if (out->agentEmotion[0]) {
    cpy(out->agentSrc, sizeof(out->agentSrc), doc["agentSrc"]);
    cpy(out->agentColor, sizeof(out->agentColor), doc["agentColor"]);
    cpy(out->agentIntensity, sizeof(out->agentIntensity), doc["agentIntensity"]);
    cpy(out->agentMotion, sizeof(out->agentMotion), doc["agentMotion"]);
    cpy(out->agentSay, sizeof(out->agentSay), doc["agentSay"]);
    cpy(out->agentDelivery, sizeof(out->agentDelivery), doc["agentDelivery"]);
  } else {
    out->agentSrc[0] = 0; out->agentColor[0] = 0; out->agentIntensity[0] = 0;
    out->agentMotion[0] = 0; out->agentSay[0] = 0; out->agentDelivery[0] = 0;
  }
}

static void _applyJson(const char* line, TamaState* out) {
  JsonDocument doc;
  if (deserializeJson(doc, line)) { _parseFailCount++; return; }
  if (otaCommand(doc)) { _lastLiveMs = millis(); return; }
  if (xferCommand(doc)) { _lastLiveMs = millis(); return; }

  // Bridge sends {"time":[epoch_sec, tz_offset_sec]}; gmtime_r on the
  // adjusted epoch yields local components including weekday.
  JsonArray t = doc["time"];
  if (!t.isNull() && t.size() == 2) {
    time_t local = (time_t)t[0].as<uint32_t>() + (int32_t)t[1];
    struct tm lt; gmtime_r(&local, &lt);
    halSetLocalTime(lt);
    extern uint32_t _clkLastRead;
    _clkLastRead = 0;   // force re-read so _clkDt and _rtcValid agree
    _rtcValid = true;
    _lastLiveMs = millis();
    return;
  }

  out->sessionsTotal     = doc["total"]     | out->sessionsTotal;
  out->sessionsRunning   = doc["running"]   | out->sessionsRunning;
  out->sessionsWaiting   = doc["waiting"]   | out->sessionsWaiting;
  const char* petStr = doc["pet"];
  if (petStr) { strncpy(out->pet, petStr, sizeof(out->pet)-1); out->pet[sizeof(out->pet)-1]=0; }
  const char* specStr = doc["species"];
  if (specStr) { strncpy(out->species, specStr, sizeof(out->species)-1); out->species[sizeof(out->species)-1]=0; }
  const char* deskStr = doc["desktop"];
  if (deskStr) { strncpy(out->desktop, deskStr, sizeof(out->desktop)-1); out->desktop[sizeof(out->desktop)-1]=0; }
  if (doc["celebrate"].is<bool>()) out->celebrate = doc["celebrate"] | false;
  if (doc["mute"].is<bool>()) out->muted = doc["mute"] | false;
  const char* m = doc["msg"];
  if (m) { strncpy(out->msg, m, sizeof(out->msg)-1); out->msg[sizeof(out->msg)-1]=0; }
  // Omitted means unchanged (the desktop only sends it while working);
  // stale values are harmless — the face only shows it in the busy state.
  const char* act = doc["activity"];
  if (act) { strncpy(out->activity, act, sizeof(out->activity)-1); out->activity[sizeof(out->activity)-1]=0; }
  JsonArray la = doc["entries"];
  if (!la.isNull()) {
    uint8_t n = 0;
    for (JsonVariant v : la) {
      if (n >= 6) break;
      const char* s = v.as<const char*>();
      strncpy(out->lines[n], s ? s : "", 80); out->lines[n][80]=0;
      n++;
    }
    if (n != out->nLines || (n > 0 && strcmp(out->lines[n-1], out->msg) != 0)) {
      out->lineGen++;
    }
    out->nLines = n;
  }
  _parsePrompt(doc, out);
  _parsePersonality(doc, out);
  out->lastUpdated = millis();
  _lastLiveMs = millis();
}

// Defined in main.cpp. Called for non-JSON lines so debug commands
// ("screenshot") can co-exist on the same serial channel as the daemon's
// JSON state pushes.
extern void handleSerialCommand(const char* line);

template<size_t N>
struct _LineBuf {
  char buf[N];
  uint16_t len = 0;
  bool overflowed = false;
  uint32_t lastByteMs = 0;
  void feed(Stream& s, TamaState* out) {
    // A host killed mid-line (session ended, cable replugged) leaves a
    // fragment here that would be glued onto the next session's first line,
    // costing both. Bytes within one line arrive in milliseconds, so a long
    // silent gap over a partial line means the line is never finishing.
    if (len > 0 && lastByteMs != 0 && millis() - lastByteMs > 2000) {
      len = 0;
      overflowed = false;
    }
    while (s.available()) {
      char c = s.read();
      lastByteMs = millis();
      if (c == '\n' || c == '\r') {
        if (overflowed) {
          // Never parse the truncated prefix of an oversize line — count it
          // so the failure is visible in `state`, and resync on this newline.
          _lineOverflowCount++;
          overflowed = false;
          len = 0;
        } else if (len > 0) {
          buf[len]=0;
          if (buf[0]=='{') _applyJson(buf, out);
          else             handleSerialCommand(buf);
          len=0;
        }
      } else if (len < N-1) {
        buf[len++] = c;
      } else {
        overflowed = true;
      }
    }
  }
};

static _LineBuf<2048> _usbLine, _btLine;

inline void dataPoll(TamaState* out) {
  uint32_t now = millis();

  if (_demoMode) {
    if (now >= _demoNext) { _demoIdx = (_demoIdx + 1) % 5; _demoNext = now + 8000; }
    const _Fake& s = _FAKES[_demoIdx];
    out->sessionsTotal=s.t; out->sessionsRunning=s.r; out->sessionsWaiting=s.w;
    strncpy(out->pet, s.pet, sizeof(out->pet)-1); out->pet[sizeof(out->pet)-1]=0;
    strncpy(out->desktop, "connected", sizeof(out->desktop)-1); out->desktop[sizeof(out->desktop)-1]=0;
    out->celebrate = (strcmp(s.pet, "celebrate") == 0);
    out->lastUpdated=now;
    out->connected = true;
    snprintf(out->msg, sizeof(out->msg), "demo: %s", s.n);
    return;
  }

  _usbLine.feed(Serial, out);
  // A dropped link leaves whatever arrived after the last newline sitting in
  // _btLine. Discard it rather than letting the next connection's first frame
  // be appended to a headless fragment — that costs BOTH frames, and the
  // first one after a reconnect is the one-shot time sync, which nothing
  // resends.
  static uint32_t _btLinkGen = 0;
  uint32_t gen = bleLinkGeneration();
  if (gen != _btLinkGen) { _btLinkGen = gen; _btLine.len = 0; _btLine.overflowed = false; }
  // BLE ring buffer is drained manually since it's not a Stream.
  while (bleAvailable()) {
    int c = bleRead();
    if (c < 0) break;
    _lastBtByteMs = millis();
    if (c == '\n' || c == '\r') {
      if (_btLine.overflowed) {
        // Same rule as _LineBuf::feed — a truncated prefix is not a frame.
        _lineOverflowCount++;
        _btLine.overflowed = false;
        _btLine.len = 0;
      } else if (_btLine.len > 0) {
        _btLine.buf[_btLine.len] = 0;
        if (_btLine.buf[0] == '{') _applyJson(_btLine.buf, out);
        _btLine.len = 0;
      }
    } else if (_btLine.len < sizeof(_btLine.buf) - 1) {
      _btLine.buf[_btLine.len++] = (char)c;
    } else {
      _btLine.overflowed = true;
    }
  }

  out->connected = dataConnected();
  if (!out->connected) {
    out->sessionsTotal=0; out->sessionsRunning=0; out->sessionsWaiting=0;
    strncpy(out->pet, "sleep", sizeof(out->pet)-1); out->pet[sizeof(out->pet)-1]=0;
    strncpy(out->desktop, "disconnected", sizeof(out->desktop)-1); out->desktop[sizeof(out->desktop)-1]=0;
    out->lastUpdated=now;
    strncpy(out->msg, "no agents awake", sizeof(out->msg)-1);
    out->msg[sizeof(out->msg)-1]=0;
    // Drop the prompt too. It used to survive here, so a card for a request
    // nobody is waiting on any more stayed on glass (and answerable) after the
    // link died — PEBBLE-UX §9.1 says link loss reads as a nap, not as a
    // pending decision. Reconnecting re-sends the id, which the change
    // detector then treats as a fresh arrival and re-arms.
    out->promptId[0]=0; out->promptTool[0]=0; out->promptHint[0]=0;
    out->promptSource[0]=0; out->promptLabel[0]=0; out->promptApproval=false;
    // Personality and agent overlay die with the link for the same reason:
    // a stale "missed you" or a dead agent's speech is a lie on glass.
    out->greet=false; out->greetLevel=0; out->moodStr[0]=0; out->effort[0]=0;
    out->celebrateLevel=0; out->agentSrc[0]=0; out->agentColor[0]=0;
    out->agentEmotion[0]=0; out->agentIntensity[0]=0; out->agentMotion[0]=0;
    out->agentSay[0]=0; out->agentDelivery[0]=0;
  }
}
