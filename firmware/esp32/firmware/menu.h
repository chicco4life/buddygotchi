#pragma once
#include <Arduino.h>
#include "hal/hal.h"
#include "buddy.h"
#include "character.h"

// Header-only with file-static state: include from exactly one translation
// unit (main.cpp), after character.h and stats.h — the menu reads the
// character palette and persists choices via settings().
//
// On-device mini-menu, opened with the MENU button. Every screen shares
// one button grammar, and each action's hint is drawn at the screen edge
// nearest its physical button, so the hardware itself is the legend:
//
//   MENU (bottom-left) = next    BOOP (top) = pick    REJECT (bottom-right) = back
//
// Screens: root carousel -> character / sound / stats. The buddy keeps
// animating behind the menu (the menu only owns the top hint band and the
// HUD block), so the character screen doubles as a live preview. Auto-
// closes after 10s of no input; an armed approval prompt closes it
// immediately — the prompt owns the buttons. Deliberately shallow: the
// Mac app is the brain, this is only what you want without reaching for
// the desktop.

static void beep(uint16_t freq, uint16_t dur);   // defined later in main.cpp (same TU)
static void sendCmd(const char* json);           // ditto

enum MenuScreen : uint8_t { MENU_CLOSED = 0, MENU_ROOT, MENU_CHARACTER, MENU_SOUND, MENU_STATS };

static const char* MENU_ROOT_ITEMS[] = { "character", "sound", "stats" };
static const uint8_t  MENU_ROOT_N = 3;
static const uint32_t MENU_TIMEOUT_MS = 10000;

static MenuScreen _menuScreen = MENU_CLOSED;
static uint8_t    _menuIdx = 0;
static uint8_t    _menuEntrySpecies = 0;   // to revert an unadopted preview
static uint32_t   _menuLastInput = 0;

inline bool menuActive() { return _menuScreen != MENU_CLOSED; }

inline const char* menuScreenName() {
  switch (_menuScreen) {
    case MENU_ROOT:      return "root";
    case MENU_CHARACTER: return "character";
    case MENU_SOUND:     return "sound";
    case MENU_STATS:     return "stats";
    default:             return "closed";
  }
}

static void _menuEvent() {
  if (_menuScreen == MENU_ROOT)
    Serial.printf("<<MENU screen=root item=%s>>\n", MENU_ROOT_ITEMS[_menuIdx]);
  else
    Serial.printf("<<MENU screen=%s>>\n", menuScreenName());
}

static void _menuPersistSpecies() {
  // Skip the NVS write when nothing changed — sectors have finite cycles.
  if (strcmp(settings().species, buddySpeciesName()) == 0) return;
  strncpy(settings().species, buddySpeciesName(), sizeof(settings().species) - 1);
  settings().species[sizeof(settings().species) - 1] = 0;
  settingsSave();
  Serial.printf("<<MENU species=%s kept=1>>\n", buddySpeciesName());
  // Tell the desktop, which mirrors it into its own species preference —
  // otherwise its next heartbeat (and every reconnect) stomps the choice.
  // Species names are internal table constants, safe to printf into JSON.
  char msg[48];
  snprintf(msg, sizeof(msg), "{\"cmd\":\"species\",\"name\":\"%s\"}", buddySpeciesName());
  sendCmd(msg);
}

inline void menuOpen(uint32_t now) {
  _menuScreen = MENU_ROOT;
  _menuIdx = 0;
  _menuLastInput = now;
  _menuEvent();
}

// keep=false reverts an unadopted character preview; keep=true adopts it.
inline void menuClose(bool keep) {
  if (_menuScreen == MENU_CLOSED) return;
  if (_menuScreen == MENU_CHARACTER) {
    if (keep) {
      _menuPersistSpecies();
    } else {
      buddySetSpeciesIdx(_menuEntrySpecies);
      buddyInvalidate();
    }
  }
  _menuScreen = MENU_CLOSED;
  Serial.println("<<MENU close>>");
}

inline void menuNext(uint32_t now) {
  _menuLastInput = now;
  switch (_menuScreen) {
    case MENU_ROOT:
      _menuIdx = (uint8_t)((_menuIdx + 1) % MENU_ROOT_N);
      _menuEvent();
      break;
    case MENU_CHARACTER:
      buddyNextSpecies();
      buddyInvalidate();
      Serial.printf("<<MENU species=%s>>\n", buddySpeciesName());
      break;
    default:
      break;   // nothing to cycle on sound/stats
  }
}

inline void menuSelect(uint32_t now) {
  _menuLastInput = now;
  switch (_menuScreen) {
    case MENU_ROOT:
      if (_menuIdx == 0) { _menuScreen = MENU_CHARACTER; _menuEntrySpecies = buddySpeciesIdx(); }
      else if (_menuIdx == 1) _menuScreen = MENU_SOUND;
      else                    _menuScreen = MENU_STATS;
      _menuEvent();
      break;
    case MENU_CHARACTER:
      beep(988, 50);
      menuClose(true);   // adopt: persist + close
      break;
    case MENU_SOUND:
      settings().sound = !settings().sound;
      settingsSave();
      if (settings().sound) beep(1175, 60);   // audible proof it's back on
      Serial.printf("<<MENU sound=%s>>\n", settings().sound ? "on" : "off");
      break;
    case MENU_STATS:
      menuClose(true);   // nothing to pick — treat as done
      break;
    default:
      break;
  }
}

inline void menuBack(uint32_t now) {
  _menuLastInput = now;
  switch (_menuScreen) {
    case MENU_ROOT:
      menuClose(true);
      break;
    case MENU_CHARACTER:
      buddySetSpeciesIdx(_menuEntrySpecies);
      buddyInvalidate();
      _menuScreen = MENU_ROOT;
      _menuEvent();
      break;
    case MENU_SOUND:
    case MENU_STATS:
      _menuScreen = MENU_ROOT;
      _menuEvent();
      break;
    default:
      break;
  }
}

// Timeout abandons an unconfirmed character preview — only an explicit
// pick (or the pick-shaped close paths) adopts and writes NVS. A timeout
// must never mutate persistent state.
inline void menuTick(uint32_t now) {
  if (!menuActive()) return;
  if (now - _menuLastInput < MENU_TIMEOUT_MS) return;
  menuClose(false);
}

inline void menuDraw(BuddyCanvas& spr, uint32_t now) {
  const Palette& p = characterPalette();
  const int W = HAL_W, H = HAL_H;
  const int y = H - 70;

  spr.setTextSize(1);

  // Top hint band: "pick" lives on the physical top button.
  spr.fillRect(0, 0, W, 12, p.bg);
  spr.setTextDatum(TC_DATUM);
  spr.setTextColor(((now / 500) & 1) ? p.text : p.textDim, p.bg);
  spr.drawString("^ pick", W / 2, 2);

  spr.fillRect(0, y, W, H - y, p.bg);
  switch (_menuScreen) {
    case MENU_ROOT: {
      spr.setTextDatum(TC_DATUM);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString("menu", W / 2, y + 2);
      spr.setTextSize(2);
      spr.setTextColor(p.text, p.bg);
      spr.drawString(MENU_ROOT_ITEMS[_menuIdx], W / 2, y + 16);
      spr.setTextSize(1);
      char dots[2 * MENU_ROOT_N];
      for (int i = 0; i < MENU_ROOT_N; i++) {
        dots[2 * i] = (i == _menuIdx) ? 'o' : '.';
        dots[2 * i + 1] = ' ';
      }
      dots[2 * MENU_ROOT_N - 1] = 0;
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString(dots, W / 2, y + 38);
      break;
    }
    case MENU_CHARACTER: {
      spr.setTextDatum(TC_DATUM);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString("character", W / 2, y + 2);
      spr.setTextSize(2);
      spr.setTextColor(p.body, p.bg);
      spr.drawString(buddySpeciesName(), W / 2, y + 16);
      spr.setTextSize(1);
      char pos[12];
      snprintf(pos, sizeof(pos), "%u/%u", buddySpeciesIdx() + 1, buddySpeciesCount());
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString(pos, W / 2, y + 38);
      break;
    }
    case MENU_SOUND: {
      spr.setTextDatum(TC_DATUM);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString("sound", W / 2, y + 2);
      spr.setTextSize(2);
      spr.setTextColor(p.text, p.bg);
      spr.drawString(settings().sound ? "on" : "off", W / 2, y + 16);
      spr.setTextSize(1);
      spr.setTextColor(p.textDim, p.bg);
      spr.drawString("pick = toggle", W / 2, y + 38);
      break;
    }
    case MENU_STATS: {
      // One stat per line — "approved 65535" is 14 chars, well inside the
      // 23-char row; a combined line clips off the 140px canvas.
      spr.setTextDatum(TL_DATUM);
      spr.setTextColor(p.text, p.bg);
      spr.setCursor(4, y + 2);
      spr.printf("approved %u", stats().approvals);
      spr.setCursor(4, y + 14);
      spr.printf("denied %u", stats().denials);
      spr.setCursor(4, y + 26);
      spr.printf("naps %lum", (unsigned long)(stats().napSeconds / 60));
      spr.setTextColor(p.textDim, p.bg);
      spr.setCursor(4, y + 38);
      spr.printf("fw %.20s", FW_VERSION);
      spr.setCursor(4, y + 50);
      spr.print(HAL_BOARD_NAME);
      break;
    }
    default:
      break;
  }

  // Bottom hint row: next/back live on the two buttons under these corners.
  spr.setTextSize(1);
  spr.setTextColor(p.textDim, p.bg);
  spr.setTextDatum(BL_DATUM);
  spr.drawString("< next", 2, H - 2);
  spr.setTextDatum(BR_DATUM);
  spr.drawString("back >", W - 2, H - 2);
  spr.setTextDatum(TL_DATUM);
}
