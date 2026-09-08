#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "data.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h and data.h.
//
// The agent-expression overlay (System E — archived/research/eng/personality-and-
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
static char _agKey[128] = "";      // src|emotion|say fingerprint for arrival edges

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
    snprintf(key, sizeof(key), "%.23s|%.23s|%.63s", s.agentSrc, s.agentEmotion, s.agentSay);
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
  char line[128];
  if (s.agentSay[0]) snprintf(line, sizeof(line), "%.23s: %.63s", s.agentSrc, s.agentSay);
  else               snprintf(line, sizeof(line), "%.23s · %.23s", s.agentSrc, s.agentEmotion);
  spr.setFont(&fonts::efontKR_16); spr.setTextSize(1.0f);
  while (spr.textWidth(line) > W - 40 * S && line[0]) {
    size_t end = strlen(line) - 1;
    while (end && ((uint8_t)line[end] & 0xc0) == 0x80) --end;
    line[end] = 0;
  }
  int tw = spr.textWidth(line);
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
    spr.setTextSize(1.0f);
    spr.setTextColor(c, BLACK);
    spr.drawString(line, dotX + 6 * S, cy);
    spr.setTextDatum(TL_DATUM);
  }
}
