#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "mood.h"
#include "data.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after mood.h and data.h.
//
// Two surfaces that both sit above the face:
//
//   the CARD    the approval request (PEBBLE-UX §7) — a rounded panel that
//               rises from the bottom edge while the field is lantern-lit
//   the BUBBLE  short-lived speech ("yes!", "okay", a gift summary, the
//               dangle readout) — small, centred, auto-expiring
//
// The card is drawn as ink on the lantern field rather than as a filled
// panel. The field IS its background (§2.1), so a fill here would punch a
// hole in the product's alert channel. What gives it card-ness instead is a
// thin INK_DIM rule inset from the screen edge, leaving a cream margin
// outside it — the matted-print quality §2.1.2 asks for.
//
// The face never leaves the screen while either is up. That is the whole
// point of the redesign: you are answering your buddy, not a dialog box.

// ---------------------------------------------------------------------------
// Approval card
// ---------------------------------------------------------------------------

static const int   CARD_H_PCT = 40;        // §7: ~40% of screen height
static const int   CARD_MARGIN = 5 * HAL_UI_SCALE;
static const int   CARD_RULE_INSET = 3 * HAL_UI_SCALE;   // cream margin outside the rule

// The panel's glass is ROUNDED, so the extreme corners physically are not
// there. Anything anchored to a corner needs this much clearance or it gets
// its outermost characters shaved off — first caught with "3 tasks" losing
// its 3 and "waiting" losing its g. Lifting off the bottom edge buys most
// of it, since the corner radius eats far less horizontally once you are a
// couple of text-heights up.
static const int CORNER_SAFE_X = 13 * HAL_UI_SCALE;
static const int CORNER_SAFE_Y = 9 * HAL_UI_SCALE;

static AnimSpring _cardSpring;
static bool  _cardWanted = false;
static float _cardPop = 0.0f;      // >0 while the approve scale-out runs

inline float cardCover() { return animClamp(_cardSpring.pos, 0.0f, 1.3f); }
inline bool  cardVisible() { return _cardSpring.pos > 0.01f; }

// Approve: the card pops (scale-out, ~150ms) ahead of the field's snuff, so
// the panel leaves before the light does and the answer feels like it
// landed rather than faded.
inline void cardPop() {
  if (!_cardWanted) return;
  _cardWanted = false;
  _cardPop = 1.0f;
}

// Deny: no pop. The card simply slides back down while the field fades
// evenly — denial is responsible, not punished, so it gets no flourish.
inline void cardDismiss() { _cardWanted = false; _cardPop = 0.0f; }

inline void cardTick(uint32_t now, float dt, bool wanted) {
  if (wanted && !_cardWanted) { _cardWanted = true; _cardPop = 0.0f; }
  else if (!wanted && _cardWanted) { _cardWanted = false; }
  if (_cardWanted) {
    _cardSpring.step(1.0f, 3.6f, 0.68f, dt);
  } else if (_cardPop > 0.0f) {
    _cardPop = animEase(_cardPop, 0.0f, 16.0f, dt);
    _cardSpring.pos = animEase(_cardSpring.pos, 0.0f, 20.0f, dt);
    _cardSpring.vel = 0.0f;
    if (_cardSpring.pos < 0.01f) { _cardSpring.pos = 0.0f; _cardPop = 0.0f; }
  } else {
    _cardSpring.pos = animEase(_cardSpring.pos, 0.0f, 12.0f, dt);
    _cardSpring.vel = 0.0f;
    if (_cardSpring.pos < 0.004f) _cardSpring.pos = 0.0f;
  }
  (void)now;
}

// Word-aware wrap into up to two rows, capped at cpl chars each. Anything
// past two rows is dropped — a hint long enough to need three lines is one
// nobody is reading off a desk pet anyway.
static void _cardWrap(BuddyCanvas& spr, const char* s, int x, int y1, int y2, int cpl) {
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

inline void cardDraw(BuddyCanvas& spr, uint32_t now, const TamaState& s) {
  float cover = cardCover();
  if (cover <= 0.01f) return;

  const int W = HAL_W, H = HAL_H;
  const int S = HAL_UI_SCALE;
  const int cardH = (H * CARD_H_PCT) / 100;
  int top = H - animPx(cardH * cover);

  uint16_t bg  = moodBackdrop(now);
  uint16_t ink = _moodMix(WHITE, MOOD_INK, moodInkBlend());
  uint16_t dim = _moodMix(LIGHTGREY, MOOD_INK_DIM, moodInkBlend());

  // The rule, inset so cream shows outside it. Two nested rects give a
  // 2px stroke without an anti-aliased round-rect outline (LGFX has none).
  int rx = CARD_MARGIN + CARD_RULE_INSET;
  int rw = W - 2 * rx;
  int rh = cardH + 40;                     // bottom rounding falls off-screen
  spr.drawRoundRect(rx, top + CARD_RULE_INSET, rw, rh, 6 * S, dim);
  spr.drawRoundRect(rx + 1, top + CARD_RULE_INSET + 1, rw - 2, rh - 2, 6 * S - 1, dim);

  const int x = rx + 5 * S;
  const int cpl = (W - 2 * rx - 10 * S) / (6 * S);
  int y = top + CARD_RULE_INSET + 6 * S;
  spr.setTextSize(S);
  spr.setTextDatum(TL_DATUM);

  // Line 1: who is asking and for what. The full source name matters — a
  // decision you make on behalf of "claude-code" is not the same decision
  // you make on behalf of something you don't recognise.
  const char* tool = s.promptTool[0] ? s.promptTool : "approve?";
  spr.setTextColor(ink, bg);
  spr.setCursor(x, y);
  if (s.promptSource[0]) spr.printf("%.11s: %.23s", s.promptSource, tool);
  else spr.printf("%.*s", cpl, tool);
  y += 13 * S;

  // Lines 2-3: the hint, which is usually the actual command.
  if (s.promptHint[0]) {
    spr.setTextColor(dim, bg);
    _cardWrap(spr, s.promptHint, x, y, y + 12 * S, cpl);
  }

  // Link lost mid-prompt: a boop can't be delivered, so say so. The field
  // stays lantern — the human is still needed, just not answerable here.
  if (!s.connected) {
    spr.setTextColor(MOOD_HOT, bg);
    spr.setCursor(CORNER_SAFE_X, H - CORNER_SAFE_Y - 9 * S);
    spr.print("link lost!");
  }

  // The "no" chip sits over its physical button, so the hardware is the
  // legend. There is deliberately no matching "yes" affordance: the crown
  // is the affirmative verb everywhere in the product, and labelling it
  // here would imply it isn't.
  spr.setTextDatum(BR_DATUM);
  spr.setTextColor(ink, bg);
  spr.drawString("no >", W - CORNER_SAFE_X, H - CORNER_SAFE_Y);
  spr.setTextDatum(TL_DATUM);
}

// ---------------------------------------------------------------------------
// Dangle readout
// ---------------------------------------------------------------------------

// The airborne summary (§10.2). Deliberately NOT a bubble: while the buddy
// is in your hand the face is the thing you're looking at, and a bordered
// panel across the middle of it is chrome competing with the pet. Two short
// facts pinned to the bottom corners answer the question ("what's going
// on?") without taking the screen away from the thing you picked up.
static float _dangleTextGain = 0.0f;

inline void dangleSummaryDraw(BuddyCanvas& spr, uint32_t now, bool active, float dt,
                              uint8_t total, uint8_t waiting) {
  _dangleTextGain = animEase(_dangleTextGain, active ? 1.0f : 0.0f, 9.0f, dt);
  if (_dangleTextGain <= 0.03f) return;

  const int S = HAL_UI_SCALE;
  // Muted rather than bright: this is a caption, not an announcement.
  uint16_t bg = moodBackdrop(now);
  uint16_t c  = _moodMix(bg, moodIsInk() ? MOOD_INK_DIM : animRGB(182, 182, 173),
                         _dangleTextGain);

  char l[20], r[20];
  snprintf(l, sizeof(l), "%u task%s", (unsigned)total, total == 1 ? "" : "s");
  snprintf(r, sizeof(r), "%u waiting", (unsigned)waiting);

  spr.setTextSize(S);
  spr.setTextColor(c, bg);
  spr.setTextDatum(BL_DATUM);
  spr.drawString(l, CORNER_SAFE_X, HAL_H - CORNER_SAFE_Y);
  spr.setTextDatum(BR_DATUM);
  spr.drawString(r, HAL_W - CORNER_SAFE_X, HAL_H - CORNER_SAFE_Y);
  spr.setTextDatum(TL_DATUM);
}

// ---------------------------------------------------------------------------
// Speech bubble
// ---------------------------------------------------------------------------

static char     _bubText[40] = "";
static uint32_t _bubUntil = 0;
static uint16_t _bubTint = 0;
static AnimSpring _bubSpring;

inline void bubbleShow(const char* text, uint32_t now, uint32_t ms, uint16_t tint) {
  strncpy(_bubText, text ? text : "", sizeof(_bubText) - 1);
  _bubText[sizeof(_bubText) - 1] = 0;
  _bubUntil = now + ms;
  _bubTint = tint;
}

inline void bubbleClear() { _bubUntil = 0; }
inline bool bubbleActive() { return _bubText[0] && _bubSpring.pos > 0.01f; }

inline void bubbleTick(uint32_t now, float dt) {
  bool up = _bubText[0] && (int32_t)(_bubUntil - now) > 0;
  if (up) _bubSpring.step(1.0f, 4.4f, 0.6f, dt);
  else {
    _bubSpring.pos = animEase(_bubSpring.pos, 0.0f, 14.0f, dt);
    _bubSpring.vel = 0.0f;
    if (_bubSpring.pos < 0.01f) { _bubSpring.pos = 0.0f; _bubText[0] = 0; }
  }
}

// Centred under the face. Drawn as a filled rounded panel because a bubble
// can appear over ANY mood — unlike the card, it can't assume the field
// behind it is the colour it wants to write on.
inline void bubbleDraw(BuddyCanvas& spr, uint32_t now, int liftY) {
  if (!_bubText[0] || _bubSpring.pos <= 0.01f) return;
  const int S = HAL_UI_SCALE;
  float g = animClamp(_bubSpring.pos, 0.0f, 1.2f);

  int tw = (int)strlen(_bubText) * 6 * S;
  int bw = animPx((tw + 16 * S) * g);
  int bh = animPx(20 * S * g);
  if (bw < 8 || bh < 6) return;
  int cx = HAL_W / 2;
  // Below the mouth, not over it. The face never leaves the screen and it
  // must stay readable while it's talking — a bubble centred on the mouth
  // reads as the buddy being covered up rather than speaking.
  int by = HAL_H - 44 * S - liftY;

  uint16_t fill = moodIsInk() ? MOOD_INK : BLACK;
  uint16_t edge = _bubTint ? _bubTint : (moodIsInk() ? MOOD_INK_DIM : LIGHTGREY);
  spr.fillSmoothRoundRect(cx - bw / 2, by - bh / 2, bw, bh, 5 * S, edge);
  spr.fillSmoothRoundRect(cx - bw / 2 + 2, by - bh / 2 + 2, bw - 4, bh - 4, 5 * S - 2, fill);

  if (g > 0.7f) {
    spr.setTextDatum(MC_DATUM);
    spr.setTextSize(S);
    spr.setTextColor(edge, fill);
    spr.drawString(_bubText, cx, by);
    spr.setTextDatum(TL_DATUM);
  }
  (void)now;
}
