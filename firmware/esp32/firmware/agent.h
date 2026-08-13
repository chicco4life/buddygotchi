#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "mood.h"
#include "data.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h and data.h.
//
// The agent-expression overlay (System E — research/eng/personality-and-
// embodiment.md). While a connected agent holds an expression lease, the
// panel carries an unmistakable AGENT CHANNEL: a slow-breathing border in
// the agent's identity color, plus a small name chip along the bottom edge
// carrying its short line of speech (or its emotion word). Provenance, not
// warning — the border says WHO is speaking; no red, no hazard styling.
//
// Security posture, mirrored from the desktop invariants:
//   S1  never drawn while a prompt is up. The desktop guarantees the frames
//       never overlap; the call site re-checks promptVisible()/cardVisible()
//       anyway, so even a buggy bridge can't put agent content next to a
//       trust decision.
//   S2  this surface touches no input path — buttons and touch stay
//       boop-only outside a real armed approval (main.cpp owns that rule).
//   S3  the approval card's chrome (lantern field + ink rule, bubble.h)
//       never uses this styling, and this styling never renders text
//       anywhere near the card's geometry. The two channels cannot imitate
//       each other.
//   S8  content is byte-capped upstream (say ≤ 40) and expires with the
//       lease: the desktop drops the agent* keys from the heartbeat, the
//       parser clears the fields, and the spring retracts.

static AnimSpring _agSpring;      // entry/exit — the one fixed transition (§S3)
static char _agKey[80] = "";      // src|emotion|say fingerprint for arrival edges

// Identity palette. Names must match AgentVocabulary.colors on the desktop.
// Values sit on the RGB332 lattice (anim.h) so the 8bpp canvas renders them
// without drift.
struct _AgColor { const char* name; uint16_t c; };
static const _AgColor _AG_COLORS[] = {
  {"coral",    animRGB(255, 109,  82)},
  {"amber",    animRGB(255, 182,  36)},
  {"mint",     animRGB(109, 219, 146)},
  {"sky",      animRGB( 73, 146, 255)},
  {"lavender", animRGB(182, 146, 255)},
  {"rose",     animRGB(255, 109, 173)},
  {"sand",     animRGB(219, 182, 109)},
  {"teal",     animRGB( 36, 182, 173)},
};

inline uint16_t agentColor565(const char* name) {
  if (name && name[0]) {
    for (const auto& e : _AG_COLORS) {
      if (strcmp(e.name, name) == 0) return e.c;
    }
  }
  // An agent that never introduced itself speaks in neutral grey — still
  // unmistakably the agent channel, just anonymous.
  return LIGHTGREY;
}

inline bool agentOverlayVisible() { return _agSpring.pos > 0.02f; }

// ---------------------------------------------------------------------------
// Agent drawings (E4)
//
// The desktop sends a fresh held-up drawing as one dedicated JSON line
// ({"cmd":"drawing","src":…,"color":…,"cap":…,"rows":[…]}) over the same
// transport as heartbeats — a full 32×32 drawing is ~1.3KB, inside the
// 2048-byte line buffer. The device runs its own 12s show window and the
// render is suppressed under anything that owns the screen (S1); no clear
// message exists or is needed.
// ---------------------------------------------------------------------------

static uint8_t  _agDrawW = 0, _agDrawH = 0;
static uint8_t  _agDrawPix[32][32];
static char     _agDrawSrc[16] = "";
static char     _agDrawCap[44] = "";
static char     _agDrawColorName[12] = "";
static uint32_t _agDrawUntil = 0;

// The fixed drawing palette — MUST mirror AgentVocabulary.palette on the
// desktop (index 0 = transparent, never drawn).
static const uint16_t AG_DRAW_PALETTE[16] = {
  0,
  animRGB(0x1A, 0x1A, 0x1A), animRGB(0xFF, 0xF6, 0xE5), animRGB(0x8A, 0x85, 0x78),
  animRGB(0xF4, 0x71, 0x59), animRGB(0xF5, 0xB0, 0x42), animRGB(0xFF, 0xD9, 0x4A),
  animRGB(0x6D, 0xDB, 0x92), animRGB(0x3E, 0x9B, 0x5C), animRGB(0x49, 0x92, 0xE8),
  animRGB(0x24, 0xB6, 0xB0), animRGB(0xB6, 0x92, 0xFF), animRGB(0xEB, 0x80, 0xAD),
  animRGB(0xDB, 0xB6, 0x6D), animRGB(0x7A, 0x4E, 0x2E), animRGB(0xE0, 0x39, 0x3E),
};

// Claims any {"cmd":"drawing"} line. A malformed one is claimed AND dropped:
// it must not fall through to the state parser, and half a drawing is worse
// than none.
bool agentDrawingCommand(JsonDocument& doc) {
  const char* cmd = doc["cmd"];
  if (!cmd || strcmp(cmd, "drawing") != 0) return false;
  JsonArray rows = doc["rows"];
  if (rows.isNull()) return true;

  uint8_t pix[32][32];
  uint8_t h = 0, w = 0;
  for (JsonVariant v : rows) {
    if (h >= 32) return true;
    const char* row = v.as<const char*>();
    if (!row) return true;
    size_t len = strnlen(row, 33);
    if (len == 0 || len > 32) return true;
    if (h == 0) w = (uint8_t)len;
    else if (len != w) return true;
    for (uint8_t x = 0; x < w; x++) {
      char c = row[x];
      int idx = (c >= '0' && c <= '9') ? c - '0'
              : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
      if (idx < 0) return true;
      pix[h][x] = (uint8_t)idx;
    }
    h++;
  }
  if (h == 0) return true;

  memcpy(_agDrawPix, pix, sizeof(pix));
  _agDrawW = w;
  _agDrawH = h;
  auto cpy = [](char* d, size_t n, const char* s) {
    strncpy(d, s ? s : "", n - 1);
    d[n - 1] = 0;
  };
  cpy(_agDrawSrc, sizeof(_agDrawSrc), doc["src"]);
  cpy(_agDrawCap, sizeof(_agDrawCap), doc["cap"]);
  cpy(_agDrawColorName, sizeof(_agDrawColorName), doc["color"]);
  _agDrawUntil = millis() + 12000;
  return true;
}

inline bool agentDrawingActive(uint32_t now) {
  return _agDrawW > 0 && (int32_t)(_agDrawUntil - now) > 0;
}

// The pet holds the drawing up: chunky pixels on a dark panel, framed in the
// agent's identity color, name chip below. Same channel styling as speech —
// nothing the system draws looks like this (S3).
inline void agentDrawingDraw(BuddyCanvas& spr, uint32_t now) {
  if (!agentDrawingActive(now)) return;
  const int S = HAL_UI_SCALE;
  const int W = HAL_W, H = HAL_H;
  uint16_t c = agentColor565(_agDrawColorName);

  int cell = (H - 76 * S) / _agDrawH;
  int cellW = (W - 40 * S) / _agDrawW;
  if (cellW < cell) cell = cellW;
  if (cell < 1) cell = 1;
  int gw = cell * _agDrawW, gh = cell * _agDrawH;
  int gx = (W - gw) / 2, gy = (H - 30 * S - gh) / 2;

  float breathe = 0.45f + 0.55f * animPulse01(now, 2100.0f);
  uint16_t edge = animMix(BLACK, c, breathe);
  spr.fillSmoothRoundRect(gx - 6 * S, gy - 6 * S, gw + 12 * S, gh + 12 * S, 6 * S, BLACK);
  spr.drawRoundRect(gx - 6 * S, gy - 6 * S, gw + 12 * S, gh + 12 * S, 6 * S, edge);
  spr.drawRoundRect(gx - 6 * S + 1, gy - 6 * S + 1, gw + 12 * S - 2, gh + 12 * S - 2, 6 * S - 1, edge);

  for (uint8_t y = 0; y < _agDrawH; y++) {
    for (uint8_t x = 0; x < _agDrawW; x++) {
      uint8_t idx = _agDrawPix[y][x];
      if (idx == 0 || idx > 15) continue;
      spr.fillRect(gx + x * cell, gy + y * cell, cell, cell, AG_DRAW_PALETTE[idx]);
    }
  }

  char line[64];
  if (_agDrawCap[0]) snprintf(line, sizeof(line), "%.15s: %.40s", _agDrawSrc, _agDrawCap);
  else               snprintf(line, sizeof(line), "%.15s", _agDrawSrc);
  int tw = (int)strlen(line) * 6 * S;
  int chipW = tw + 22 * S, chipH = 16 * S;
  int cx = W / 2, cy = H - 14 * S;
  spr.fillSmoothRoundRect(cx - chipW / 2, cy - chipH / 2, chipW, chipH, 6 * S, BLACK);
  spr.drawRoundRect(cx - chipW / 2, cy - chipH / 2, chipW, chipH, 6 * S, edge);
  int dotX = cx - chipW / 2 + 8 * S;
  spr.fillSmoothCircle(dotX, cy, 3 * S, c);
  spr.setTextDatum(ML_DATUM);
  spr.setTextSize(S);
  spr.setTextColor(c, BLACK);
  spr.drawString(line, dotX + 6 * S, cy);
  spr.setTextDatum(TL_DATUM);
}

// Advance the entry/exit spring and detect a fresh expression. Returns true
// exactly once per new expression so the caller can hang a physical
// reaction on it (a bounce/wiggle motion squishes the face).
inline bool agentTick(uint32_t now, float dt, const TamaState& s, bool suppressed) {
  bool want = s.agentEmotion[0] != 0 && !suppressed;
  if (want) _agSpring.step(1.0f, 4.0f, 0.65f, dt);
  else      _agSpring.retract(10.0f, dt);

  bool arrived = false;
  if (want) {
    char key[sizeof(_agKey)];
    snprintf(key, sizeof(key), "%.15s|%.19s|%.43s", s.agentSrc, s.agentEmotion, s.agentSay);
    if (strcmp(key, _agKey) != 0) {
      strncpy(_agKey, key, sizeof(_agKey) - 1);
      _agKey[sizeof(_agKey) - 1] = 0;
      arrived = true;
    }
  } else {
    _agKey[0] = 0;
  }
  (void)now;
  return arrived;
}

inline void agentDraw(BuddyCanvas& spr, uint32_t now, const TamaState& s) {
  float g = animClamp(_agSpring.pos, 0.0f, 1.15f);
  if (g <= 0.02f) return;
  const int S = HAL_UI_SCALE;
  const int W = HAL_W, H = HAL_H;
  uint16_t c = agentColor565(s.agentColor);

  // The breathing border (§S3's "unmistakable channel"): a ~2s luminance
  // pulse — motion is what peripheral vision notices; a static thin border
  // is invisible at arm's length. Entry/exit rides the spring.
  float breathe = 0.45f + 0.55f * animPulse01(now, 2100.0f);
  uint16_t edge = animMix(BLACK, c, breathe * animClamp(g, 0.0f, 1.0f));
  const int inset = 2 * S, thick = 2 * S, rad = 9 * S;
  for (int i = 0; i < thick; i++) {
    spr.drawRoundRect(inset + i, inset + i, W - 2 * (inset + i), H - 2 * (inset + i),
                      rad - i, edge);
  }

  // Name chip, bottom edge — deliberately far from the bubble band
  // (H - 44*S) and shaped nothing like the approval card. One line:
  // "src: say" when the agent spoke, "src · emotion" otherwise.
  char line[72];
  if (s.agentSay[0]) snprintf(line, sizeof(line), "%.15s: %.43s", s.agentSrc, s.agentSay);
  else               snprintf(line, sizeof(line), "%.15s · %.19s", s.agentSrc, s.agentEmotion);
  const int maxChars = (W - 40 * S) / (6 * S);
  if ((int)strlen(line) > maxChars && maxChars > 1) line[maxChars] = 0;

  int tw = (int)strlen(line) * 6 * S;
  int chipW = animPx((tw + 22 * S) * g);
  int chipH = animPx(16 * S * g);
  if (chipW < 8 || chipH < 6) return;
  int cx = W / 2;
  int cy = H - 14 * S;
  spr.fillSmoothRoundRect(cx - chipW / 2, cy - chipH / 2, chipW, chipH, 6 * S, BLACK);
  spr.drawRoundRect(cx - chipW / 2, cy - chipH / 2, chipW, chipH, 6 * S, edge);
  if (g > 0.7f) {
    // Identity dot, then the line — the dot is the agent's scarf.
    int dotX = cx - chipW / 2 + 8 * S;
    spr.fillSmoothCircle(dotX, cy, 3 * S, c);
    spr.setTextDatum(ML_DATUM);
    spr.setTextSize(S);
    spr.setTextColor(c, BLACK);
    spr.drawString(line, dotX + 6 * S, cy);
    spr.setTextDatum(TL_DATUM);
  }
}
