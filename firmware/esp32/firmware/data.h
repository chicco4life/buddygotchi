#pragma once
// plan/WIRE-V2.md: bump together with the encoder and the tools.
#define WIRE_CONTRACT 2
#include <ArduinoJson.h>
#include <Preferences.h>
#include "clock.h"
#include "hal/hal.h"
#include "ble_bridge.h"
#include "ota.h"

struct Snapshot {
  char name[64] = "", biggest[64] = "";
  uint32_t level = 0, xp = 0, xpNext = 0, streak = 0, best = 0;
  uint32_t days = 0, tasks = 0, today = 0;
  uint32_t rest = 0;
};
struct Cosmetics { char skin[16] = "", accessory[16] = "", silhouette[16] = ""; };
struct Card {
  char id[24] = "", tool[24] = "", gloss[64] = "", stakes[8] = "";
  char kind[7] = "", text[64] = "";
  int n = 0, of = 0;
  bool approval = false;
  bool present() const { return id[0] || kind[0]; }
};
struct TamaState {
  char state[9] = "asleep", effort[9] = "", cheer[6] = "", uhoh[7] = "";
  char overlay[6] = "", posture[7] = "";
  uint8_t greetLevel = 0, dots = 0, mute = 0;
  int8_t dotAlert = -1;
  Card card;
  char bubble[64] = "", giftLine[41] = "";
  bool gift = false, focus = false;
  Cosmetics cosmetic;
  Snapshot snap;
  char agentSrc[24] = "", agentColor[16] = "", agentEmotion[24] = "", agentSay[64] = "";
};
static uint32_t badFrames = 0, _parseFailCount = 0, _lineOverflowCount = 0;
static uint32_t _lastLiveMs = 0;
static bool haveFrame = false, _rtcValid = false, firstWake = false;
inline bool dataConnected() { return haveFrame && nowMs() - _lastLiveMs <= 60000; }
inline uint32_t dataLastLiveMs() { return _lastLiveMs; }
inline bool dataRtcValid() { return _rtcValid; }

// Reject oversize strings rather than truncating IDs or splitting UTF-8.
template<size_t N> bool readText(JsonVariantConst v, char (&dst)[N]) {
  if (v.isNull()) { dst[0] = 0; return true; }
  if (!v.is<const char*>()) return false;
  JsonString s = v.as<JsonString>();
  if (s.size() >= N || strlen(s.c_str()) != s.size()) return false;
  memcpy(dst, s.c_str(), s.size() + 1);
  return true;
}
template<size_t N> bool readEnum(JsonVariantConst v, char (&dst)[N], const char* values,
                                const char* previous) {
  if (v.isNull()) { dst[0] = 0; return true; }
  char candidate[N];
  if (!readText(v, candidate)) return false;
  char token[N + 2];
  snprintf(token, sizeof(token), "|%s|", candidate);
  // Bad enum retains that field's last good value, per architecture §9.
  strlcpy(dst, strstr(values, token) ? candidate : previous, N);
  return true;
}
inline bool readInt(JsonVariantConst v, int& dst, int lo, int hi) {
  if (v.isNull()) return true;
  if (!v.is<int>()) return false;
  dst = v.as<int>();
  return dst >= lo && dst <= hi;
}
inline bool readBool(JsonVariantConst v, bool& dst) {
  if (v.isNull()) return true;
  if (!v.is<bool>()) return false;
  dst = v.as<bool>(); return true;
}
inline void loadPersistent(TamaState& s) {
  Preferences p;
  if (!p.begin("creature-v2", false)) return;
  if (p.getBytesLength("snap") == sizeof(s.snap)) p.getBytes("snap", &s.snap, sizeof(s.snap));
  if (p.getBytesLength("cosmetic") == sizeof(s.cosmetic)) p.getBytes("cosmetic", &s.cosmetic, sizeof(s.cosmetic));
  s.mute = p.getUChar("volume", 1);
  firstWake = !p.getBool("awoke", false);
  // Mark complete only after the first signal color reveal.
  p.end();
}
inline void persist(const TamaState& old, const TamaState& next, bool snap, bool cosmetic) {
  bool a = snap && memcmp(&old.snap, &next.snap, sizeof(Snapshot));
  bool b = cosmetic && memcmp(&old.cosmetic, &next.cosmetic, sizeof(Cosmetics));
  if (!a && !b && old.mute == next.mute) return;
  Preferences p;
  if (!p.begin("creature-v2", false)) return;
  if (a) p.putBytes("snap", &next.snap, sizeof(Snapshot));
  if (b) p.putBytes("cosmetic", &next.cosmetic, sizeof(Cosmetics));
  if (old.mute != next.mute) p.putUChar("volume", next.mute);
  p.end();
}
inline void saveFirstWake(bool armed) {
  firstWake = armed;
  Preferences p;
  if (p.begin("creature-v2", false)) { p.putBool("awoke", !armed); p.end(); }
}
extern void beginRetire();
extern bool retiring;
extern void onFrame(const TamaState& next, bool firstSignal);
extern void handleSerialCommand(const char* line);
extern void sendStatus();
void sendUnpairAck();

inline bool validate(JsonDocument& d, const TamaState& old, TamaState& s) {
  if (!d["v"].is<int>() || d["v"].as<int>() != WIRE_CONTRACT) return false;
  // Snap and cosmetics are caches; omission leaves the persisted cache intact.
  s.snap = old.snap; s.cosmetic = old.cosmetic;
  if (!readEnum(d["state"], s.state, "|asleep|idle|working|needsYou|done|uhoh|", old.state) ||
      !readEnum(d["effort"], s.effort, "|light|hard|grinding|", old.effort) ||
      !readEnum(d["cheer"], s.cheer, "|hop|cheer|dance|", old.cheer) ||
      !readEnum(d["uhoh"], s.uhoh, "|error|stuck|hungry|", old.uhoh) ||
      !readEnum(d["overlay"], s.overlay, "|greet|boop|", old.overlay) ||
      !readEnum(d["posture"], s.posture, "|desk|perch|travel|", old.posture)) return false;
  if (!s.state[0]) strlcpy(s.state, "asleep", sizeof(s.state));
  int greet = 0, dots = 0, alert = -1, volume = 0;
  if (!readInt(d["greetLevel"], greet, 0, 3) || !readInt(d["dots"], dots, 0, 5) ||
      !readInt(d["dotAlert"], alert, 0, 4) || !readInt(d["mute"], volume, 0, 3) ||
      !readBool(d["gift"], s.gift) || !readBool(d["focus"], s.focus) ||
      !readText(d["bubble"], s.bubble) || !readText(d["giftLine"], s.giftLine)) return false;
  if (alert >= dots) return false;
  s.greetLevel = greet; s.dots = dots; s.dotAlert = alert; s.mute = volume;
  if (!d["card"].isNull()) {
    if (!d["card"].is<JsonObject>()) return false;
    JsonVariantConst c = d["card"];
    if (!readEnum(c["kind"], s.card.kind, "|pair|update|", old.card.kind)) return false;
    if (s.card.kind[0]) {
      if (!readText(c["text"], s.card.text)) return false;
    } else {
      if (!readText(c["id"], s.card.id) || !s.card.id[0] ||
          !readText(c["tool"], s.card.tool) || !readText(c["gloss"], s.card.gloss) ||
          !readEnum(c["stakes"], s.card.stakes, "|fine|checkIt|careful|", old.card.stakes) ||
          !readInt(c["n"], s.card.n, 0, 1000000) || !readInt(c["of"], s.card.of, 0, 1000000) ||
          !readBool(c["approval"], s.card.approval)) return false;
    }
  }
  if (!d["cosmetic"].isNull()) {
    if (!d["cosmetic"].is<JsonObject>()) return false;
    auto c = d["cosmetic"];
    if (!readText(c["skin"], s.cosmetic.skin) || !readText(c["accessory"], s.cosmetic.accessory) ||
        !readText(c["silhouette"], s.cosmetic.silhouette)) return false;
  }
  if (!d["snap"].isNull()) {
    if (!d["snap"].is<JsonObject>()) return false;
    s.snap = Snapshot{};
    auto p = d["snap"];
    if (!readText(p["name"], s.snap.name) || !readText(p["biggest"], s.snap.biggest) ||
        (!p["rest"].isNull() && !p["rest"].is<uint32_t>())) return false;
    s.snap.rest = p["rest"] | 0u;
    const char* keys[] = {"level", "xp", "xpNext", "streak", "best", "days", "tasks", "today"};
    uint32_t* dest[] = {&s.snap.level, &s.snap.xp, &s.snap.xpNext, &s.snap.streak,
                       &s.snap.best, &s.snap.days, &s.snap.tasks, &s.snap.today};
    for (int i = 0; i < 8; ++i) {
      if (!p[keys[i]].isNull() && !p[keys[i]].is<uint32_t>()) return false;
      *dest[i] = p[keys[i]] | 0u;
    }
  }
  if (!d["agent"].isNull()) {
    if (!d["agent"].is<JsonObject>()) return false;
    auto a = d["agent"];
    if (!readText(a["name"], s.agentSrc) || !readText(a["color"], s.agentColor) ||
        !readText(a["emotion"], s.agentEmotion) || !readText(a["say"], s.agentSay)) return false;
    if (s.card.present()) s.agentSrc[0] = s.agentEmotion[0] = s.agentSay[0] = 0;
  }
  if (!d["t"].isNull() && !d["t"].is<uint64_t>()) return false;
  return true;
}
inline void applyJson(const char* line, TamaState& out) {
  JsonDocument d;
  if (deserializeJson(d, line)) { ++badFrames; ++_parseFailCount; return; }
  if (d["cmd"] == "retire") { beginRetire(); return; }
  if (retiring) return;
  if (otaCommand(d)) return;
  if (d["cmd"] == "status") { sendStatus(); return; }
  if (d["cmd"] == "unpair") { sendUnpairAck(); return; }
  if (!d["cmd"].isNull()) return; // unknown commands aren't state frames
  TamaState next;
  if (!validate(d, out, next)) { ++badFrames; return; }
  if (!d["t"].isNull()) {
    time_t seconds = d["t"].as<uint64_t>() / 1000;
    struct tm local; gmtime_r(&seconds, &local); halSetLocalTime(local); _rtcValid = true;
  }
  persist(out, next, !d["snap"].isNull(), !d["cosmetic"].isNull());
  onFrame(next, (d["cosmetic"]["skin"].is<const char*>() && d["cosmetic"]["skin"].as<const char*>()[0]) || strcmp(next.state,"asleep")); out = next;
  haveFrame = true; _lastLiveMs = nowMs();
}
struct LineBuffer {
  char buf[1537]; size_t len = 0; bool overflow = false; uint32_t lastByte = 0;
  void reset() { len = 0; overflow = false; }
  void feed(int c, TamaState& out, bool usb) {
    if ((len || overflow) && millis() - lastByte > 2000) reset();
    lastByte = millis();
    if (c == '\n' || c == '\r') {
      if (overflow) { ++badFrames; ++_lineOverflowCount; }
      else if (len) {
        buf[len] = 0;
        if (buf[0] == '{') applyJson(buf, out);
        else if (usb) handleSerialCommand(buf);
      }
      reset();
    } else if (len < sizeof(buf) - 1 && c != 0) buf[len++] = (char)c;
    else overflow = true;
  }
};
static LineBuffer usbLine, btLine;
inline void dataPoll(TamaState& s) {
  static uint32_t generation = 0;
  if (generation != bleLinkGeneration()) { generation = bleLinkGeneration(); btLine.reset(); }
  // Bound drain work even when a host floods either transport.
  for (int n = 0; n < 512 && Serial.available(); ++n) usbLine.feed(Serial.read(), s, true);
  for (int n = 0; n < 512 && bleAvailable(); ++n) btLine.feed(bleRead(), s, false);
}
