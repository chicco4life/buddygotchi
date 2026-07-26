#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "anim.h"
#include "buddy.h"
#include "stats.h"
#include "data.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after data.h / buddy.h / stats.h.
//
// The glance card — the *summoned* information tier (PEBBLE-UX §6). The
// resting screen carries no text at all, so this is the one place the
// literal diagnostics live: link state, session counts, battery, firmware,
// species. It is asked for (a tap on the "look" button), it answers, and it
// gets out of the way after 4s.
//
// Motion: springs up from the bottom edge to ~55% of screen height with a
// small overshoot, and the face lifts to make room rather than being
// covered — the buddy is *presenting* the card. Any demanded-tier event
// (prompt, error, OTA, passkey) dismisses it instantly.
//
// Landscape board only. The portrait M5 keeps its permanent HUD and stays
// the regression rig, so nothing here is reachable there.

static const uint32_t GLANCE_TIMEOUT_MS = 4000;
static const uint8_t  GLANCE_PAGES = 2;

static bool     _glOpen = false;
static uint8_t  _glPage = 0;
static uint32_t _glLastInput = 0;
static AnimSpring _glSpring;    // 0 = fully below the bottom edge, 1 = out

inline bool  glanceActive() { return _glOpen; }
// How much of the card is on screen (0..1). Drives both the draw and the
// face lift, and stays non-zero through the slide-out so the dismissal
// animates instead of popping.
inline float glanceCover() { return animClamp(_glSpring.pos, 0.0f, 1.2f); }
inline bool  glanceVisible() { return _glSpring.pos > 0.01f; }

inline const char* glanceStateName() {
  if (!_glOpen) return glanceVisible() ? "closing" : "closed";
  return _glPage == 0 ? "page1" : "page2";
}

// A tap on "look": open the card, or turn to the next page if it's already
// up. Past the last page it closes — tapping through is how you put it away
// without reaching for the other button.
inline void glanceOpen(uint32_t now) {
  _glLastInput = now;
  if (!_glOpen) {
    _glOpen = true;
    _glPage = 0;
    Serial.println("<<GLANCE open page=1>>");
    return;
  }
  _glPage++;
  if (_glPage >= GLANCE_PAGES) {
    _glOpen = false;
    Serial.println("<<GLANCE close (paged past end)>>");
    return;
  }
  Serial.printf("<<GLANCE page=%u>>\n", (unsigned)(_glPage + 1));
}

inline void glanceClose() {
  if (!_glOpen) return;
  _glOpen = false;
  Serial.println("<<GLANCE close>>");
}

// Auto-dismiss after 4s of no input. Called every loop; dt drives the
// spring so the slide is frame-rate independent.
inline void glanceTick(uint32_t now, float dt) {
  if (_glOpen && (now - _glLastInput) >= GLANCE_TIMEOUT_MS) {
    _glOpen = false;
    Serial.println("<<GLANCE close (timeout)>>");
  }
  // Out springs (playful); back down is a plain ease — a card leaving
  // shouldn't bounce, it should just go.
  if (_glOpen) _glSpring.step(1.0f, 3.9f, 0.65f, dt);
  else _glSpring.retract(14.0f, dt);
}

// The Bluetooth rune, drawn from lines so it scales with the panel. Also
// used by the link-lost dream bubble (§9.1), hence the `crossed` variant.
inline void glanceBtGlyph(BuddyCanvas& spr, int x, int y, int h, uint16_t c, bool crossed) {
  int w = h / 2;
  spr.drawLine(x, y - h, x, y + h, c);
  spr.drawLine(x, y - h, x + w, y - h / 2, c);
  spr.drawLine(x + w, y - h / 2, x - w, y + h / 2, c);
  spr.drawLine(x - w, y - h / 2, x + w, y + h / 2, c);
  spr.drawLine(x + w, y + h / 2, x, y + h, c);
  if (crossed) {
    for (int t = -1; t <= 1; t++) {
      spr.drawLine(x - w - 3, y + h + t, x + w + 3, y - h + t, c);
    }
  }
}

// Rough Li-ion state of charge from resting voltage. Deliberately coarse —
// this board has no coulomb counter and the ADC is noisy, so a percentage
// with one significant figure is the honest resolution.
inline int glanceBatteryPct() {
  int mv = halBatteryVoltage_mV();
  if (mv <= 0) return -1;
  int pct = (mv - 3300) * 100 / (4200 - 3300);
  return pct < 0 ? 0 : (pct > 100 ? 100 : pct);
}

// Link state as a sentence. The resting screen never says "disconnected"
// (that shows as behavior — §9.1); this is where the fact lives.
//   linked               data flowing
//   connected, no data   radio up, app hung or quiet — the debugging tell
//   link lost · 12m      bonded but the laptop went away
//   unpaired             never adopted
inline void glanceLinkWord(char* out, size_t n, bool bonded, uint32_t lastLiveMs, uint32_t now) {
  if (dataConnected()) { snprintf(out, n, "linked"); return; }
  if (bleConnected())  { snprintf(out, n, "connected, no data"); return; }
  if (!bonded)         { snprintf(out, n, "unpaired"); return; }
  if (lastLiveMs == 0) { snprintf(out, n, "link lost"); return; }
  uint32_t age = (now - lastLiveMs) / 1000;
  if (age < 90)     snprintf(out, n, "link lost - %lus", (unsigned long)age);
  else if (age < 5400) snprintf(out, n, "link lost - %lum", (unsigned long)(age / 60));
  else              snprintf(out, n, "link lost - %luh", (unsigned long)(age / 3600));
}

// Page 1 = presence + inventory, page 2 = the old stats screen. The buddy's
// eyes dart toward the card as pages turn (driven from main.cpp's gaze
// priority, not here).
inline void glanceDraw(BuddyCanvas& spr, uint32_t now, const TamaState& s,
                       bool bonded, uint32_t lastLiveMs, uint8_t gifts) {
  float cover = glanceCover();
  if (cover <= 0.01f) return;

  const int W = HAL_W, H = HAL_H;
  const int S = HAL_UI_SCALE;
  const int cardH = (H * 55) / 100;          // ~55% of screen height
  const int margin = 5 * S;
  const int radius = 7 * S;
  // Slide: fully hidden sits one card-height below the bottom edge.
  int top = H - animPx(cardH * cover);

  const uint16_t accent = buddySpeciesColor();
  const uint16_t DIM    = animRGB(182, 182, 173);   // RGB332 lattice near-neutral
  const uint16_t FAINT  = animRGB(109, 109, 82);

  // Black panel with an accent hairline: black pixels are free on this
  // panel, so the card is a *hole* in the face rather than a slab of grey.
  // The +2*radius height pushes the bottom rounding off-screen, leaving
  // only the top corners rounded. The border is an accent fill with a black
  // inset rather than a stroke — LovyanGFX has no anti-aliased round-rect
  // outline, and two smooth fills give a cleaner edge than a jaggy one.
  // Only the top cap and two side rails of the accent fill ever survive the
  // black inset, so draw just those. Filling the whole card in accent first
  // threw away ~77k pixel writes per frame for a 2px border.
  const int bw = 2;
  const int cw = W - 2 * margin;
  spr.fillSmoothRoundRect(margin, top, cw, 2 * radius, radius, accent);
  spr.fillRect(margin, top + radius, bw, cardH + radius, accent);
  spr.fillRect(margin + cw - bw, top + radius, bw, cardH + radius, accent);
  spr.fillSmoothRoundRect(margin + bw, top + bw, cw - 2 * bw,
                          cardH + 2 * radius - 2 * bw, radius - bw, BLACK);

  const int x = margin + 7 * S;
  const int rowH = 11 * S;
  int y = top + 6 * S;
  spr.setTextSize(S);
  spr.setTextDatum(TL_DATUM);

  if (_glPage == 0) {
    char buf[48];
    // Row 1 — link, with the radio glyph so the state reads pre-attentively.
    bool linked = dataConnected();
    glanceLinkWord(buf, sizeof(buf), bonded, lastLiveMs, now);
    glanceBtGlyph(spr, x + 3 * S, y + 4 * S, 4 * S, linked ? accent : FAINT, !linked && bonded);
    spr.setTextColor(linked ? accent : DIM, BLACK);
    spr.setCursor(x + 11 * S, y);
    spr.print(buf);
    y += rowH;

    // Row 2 — sessions. Orbs on the resting screen are anonymous and capped
    // at 6; the exact numbers live here.
    spr.setTextColor(DIM, BLACK);
    spr.setCursor(x, y);
    if (s.sessionsTotal == 0) spr.print("no sessions");
    else spr.printf("%u session%s - %u running - %u waiting",
                    s.sessionsTotal, s.sessionsTotal == 1 ? "" : "s",
                    s.sessionsRunning, s.sessionsWaiting);
    y += rowH;

    // Row 3 — gifts. Only ever one is held device-side; the count is what
    // the desktop says is uncollected.
    spr.setCursor(x, y);
    if (gifts > 0) {
      spr.setTextColor(animRGB(255, 219, 82), BLACK);   // gold
      spr.printf("gifts: %u waiting", (unsigned)gifts);
    } else {
      spr.setTextColor(FAINT, BLACK);
      spr.print("gifts: none");
    }
    y += rowH;

    // Row 4 — battery.
    int pct = glanceBatteryPct();
    spr.setTextColor(DIM, BLACK);
    spr.setCursor(x, y);
    if (pct < 0) spr.print("battery: --");
    else spr.printf("battery: %d%%%s", pct, halIsCharging() ? " (charging)" : "");
    y += rowH;

    // Row 5 — species (what it is), row 6 — firmware (what it runs).
    spr.setTextColor(accent, BLACK);
    spr.setCursor(x, y);
    spr.printf("%s", buddySpeciesName());
    y += rowH;

    spr.setTextColor(FAINT, BLACK);
    spr.setCursor(x, y);
    spr.printf("%.16s  %s", FW_VERSION, HAL_BOARD_NAME);
  } else {
    // Page 2 — the stats the menu used to own.
    spr.setTextColor(DIM, BLACK);
    spr.setCursor(x, y);
    spr.printf("approved %u", stats().approvals);
    y += rowH;
    spr.setCursor(x, y);
    spr.printf("denied %u", stats().denials);
    y += rowH;
    spr.setCursor(x, y);
    spr.printf("naps %lum", (unsigned long)(stats().napSeconds / 60));
    y += rowH;
    if (s.msg[0]) {
      spr.setTextColor(FAINT, BLACK);
      spr.setCursor(x, y);
      spr.printf("%.34s", s.msg);
    }
  }

  // Page dots, bottom-right of the card — the only affordance on it.
  int dotY = top + cardH - 6 * S;
  for (int i = 0; i < GLANCE_PAGES; i++) {
    int dx = W - margin - 9 * S - (GLANCE_PAGES - 1 - i) * 6 * S;
    if (i == _glPage) spr.fillSmoothCircle(dx, dotY, 2 * S, accent);
    else              spr.fillSmoothCircle(dx, dotY, 1 * S, FAINT);
  }
  spr.setTextDatum(TL_DATUM);
}
