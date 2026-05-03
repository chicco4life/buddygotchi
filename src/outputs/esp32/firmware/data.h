#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include "ble_bridge.h"
#include "xfer.h"

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
  bool     connected;
  char     lines[6][81];
  uint8_t  nLines;
  uint16_t lineGen;          // bumps when lines change — lets UI reset scroll
  char     promptId[40];     // pending permission request ID; empty = no prompt
  char     promptTool[24];
  char     promptHint[64];
  char     promptSource[16];
  bool     promptApproval;
  char     promptLabel[24];
};

// ---------------------------------------------------------------------------
// Three modes, checked in priority order:
//   demo   → auto-cycle fake scenarios every 8s, ignore live data
//   live   → JSON arrived in the last 10s over USB or BT
//   asleep → no data, all zeros, "No Claude connected"
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

inline bool dataConnected() {
  return _lastLiveMs != 0 && (millis() - _lastLiveMs) <= 30000;
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

static void _applyJson(const char* line, TamaState* out) {
  JsonDocument doc;
  if (deserializeJson(doc, line)) return;
  if (xferCommand(doc)) { _lastLiveMs = millis(); return; }

  // Bridge sends {"time":[epoch_sec, tz_offset_sec]}; gmtime_r on the
  // adjusted epoch yields local components including weekday.
  JsonArray t = doc["time"];
  if (!t.isNull() && t.size() == 2) {
    time_t local = (time_t)t[0].as<uint32_t>() + (int32_t)t[1];
    struct tm lt; gmtime_r(&local, &lt);
    m5::rtc_time_t tm;
    tm.hours = lt.tm_hour; tm.minutes = lt.tm_min; tm.seconds = lt.tm_sec;
    m5::rtc_date_t dt;
    dt.weekDay = lt.tm_wday; dt.month = lt.tm_mon + 1;
    dt.date = lt.tm_mday; dt.year = lt.tm_year + 1900;
    StickCP2.Rtc.setTime(&tm);
    StickCP2.Rtc.setDate(&dt);
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
  const char* m = doc["msg"];
  if (m) { strncpy(out->msg, m, sizeof(out->msg)-1); out->msg[sizeof(out->msg)-1]=0; }
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
  JsonObject pr = doc["prompt"];
  if (!pr.isNull()) {
    const char* pid = pr["id"]; const char* pt = pr["tool"]; const char* ph = pr["hint"];
    const char* psrc = pr["source"]; const char* plbl = pr["label"];
    strncpy(out->promptId,     pid  ? pid  : "", sizeof(out->promptId)-1);     out->promptId[sizeof(out->promptId)-1]=0;
    strncpy(out->promptTool,   pt   ? pt   : "", sizeof(out->promptTool)-1);   out->promptTool[sizeof(out->promptTool)-1]=0;
    strncpy(out->promptHint,   ph   ? ph   : "", sizeof(out->promptHint)-1);   out->promptHint[sizeof(out->promptHint)-1]=0;
    strncpy(out->promptSource, psrc ? psrc : "", sizeof(out->promptSource)-1); out->promptSource[sizeof(out->promptSource)-1]=0;
    strncpy(out->promptLabel,  plbl ? plbl : "", sizeof(out->promptLabel)-1);  out->promptLabel[sizeof(out->promptLabel)-1]=0;
    if (pr["approval"].is<bool>()) out->promptApproval = pr["approval"] | false;
  } else {
    out->promptId[0] = 0; out->promptTool[0] = 0; out->promptHint[0] = 0;
    out->promptSource[0] = 0; out->promptLabel[0] = 0; out->promptApproval = false;
  }
  out->lastUpdated = millis();
  _lastLiveMs = millis();
}

template<size_t N>
struct _LineBuf {
  char buf[N];
  uint16_t len = 0;
  void feed(Stream& s, TamaState* out) {
    while (s.available()) {
      char c = s.read();
      if (c == '\n' || c == '\r') {
        if (len > 0) { buf[len]=0; if (buf[0]=='{') _applyJson(buf, out); len=0; }
      } else if (len < N-1) {
        buf[len++] = c;
      }
    }
  }
};

static _LineBuf<1024> _usbLine, _btLine;

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
  // BLE ring buffer is drained manually since it's not a Stream.
  while (bleAvailable()) {
    int c = bleRead();
    if (c < 0) break;
    _lastBtByteMs = millis();
    if (c == '\n' || c == '\r') {
      if (_btLine.len > 0) {
        _btLine.buf[_btLine.len] = 0;
        if (_btLine.buf[0] == '{') _applyJson(_btLine.buf, out);
        _btLine.len = 0;
      }
    } else if (_btLine.len < sizeof(_btLine.buf) - 1) {
      _btLine.buf[_btLine.len++] = (char)c;
    }
  }

  out->connected = dataConnected();
  if (!out->connected) {
    out->sessionsTotal=0; out->sessionsRunning=0; out->sessionsWaiting=0;
    strncpy(out->pet, "sleep", sizeof(out->pet)-1); out->pet[sizeof(out->pet)-1]=0;
    strncpy(out->desktop, "disconnected", sizeof(out->desktop)-1); out->desktop[sizeof(out->desktop)-1]=0;
    out->lastUpdated=now;
    strncpy(out->msg, "No Claude connected", sizeof(out->msg)-1);
    out->msg[sizeof(out->msg)-1]=0;
  }
}
