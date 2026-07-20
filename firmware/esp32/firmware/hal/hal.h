#pragma once
#include <stdint.h>
#include <Arduino.h>
#include <time.h>

// Board HAL. Everything hardware-specific — display, buttons, power,
// sound, wall clock — goes through this header so the rest of the
// firmware compiles unchanged for every board. Exactly two boards exist:
//
//   (default)            M5StickC Plus 2 — ST7789 135x240 via M5GFX,
//                        two GPIO buttons (A=37, B=39), AXP power, RTC,
//                        buzzer. The original dev board / regression rig.
//
//   BOARD_WS_AMOLED_164  Waveshare ESP32-S3-Touch-AMOLED-1.64 — CO5300
//                        280x456 QSPI AMOLED, FT3168 touch, external
//                        buttons on header GPIOs, battery ADC only.
//                        The production "Boop Pebble" board. Renders the
//                        135x240-era layout on a 140x228 logical canvas,
//                        pixel-doubled to fill 280x456 exactly.
//
// The shared render target stays a LovyanGFX sprite on both boards
// (M5Canvas is an LGFX_Sprite subclass), so buddy/species/character code
// keeps its draw API everywhere. Boards differ only in how the sprite
// reaches glass: pushSprite on M5, 2x expand + QSPI flush on Waveshare.

#ifdef BOARD_WS_AMOLED_164
  #define LGFX_USE_V1
  #include <LovyanGFX.hpp>
  using BuddyCanvas = lgfx::v1::LGFX_Sprite;
  #define HAL_CANVAS_PARENT nullptr
  #define HAL_BOARD_NAME "ws-amoled164"
  // The Pebble mounts the portrait 280x456 panel sideways: the product
  // screen is LANDSCAPE. Logical canvas is 228x140; halPresent doubles
  // and rotates it into the panel's portrait framebuffer (the CO5300 has
  // no hardware rotation).
  const int HAL_W = 228;
  const int HAL_H = 140;
  // TFT_eSPI-style color names come from M5GFX on the M5 build; LovyanGFX
  // standalone doesn't define them.
  #ifndef BLACK
    #define BLACK     0x0000
    #define WHITE     0xFFFF
    #define LIGHTGREY 0xC618
    #define GREEN     0x07E0
  #endif
#else
  #include <M5StickCPlus2.h>
  using BuddyCanvas = M5Canvas;
  #define HAL_CANVAS_PARENT (&StickCP2.Display)
  #define HAL_BOARD_NAME "m5stickc-plus2"
  const int HAL_W = 135;
  const int HAL_H = 240;
#endif

// Orientation-derived layout facts shared by every draw surface. The
// landscape board runs the face-first layout with a shorter HUD strip;
// the portrait M5 keeps the original 70px block.
const bool HAL_LANDSCAPE = HAL_W > HAL_H;
const int  HAL_HUD_H = HAL_LANDSCAPE ? 52 : 70;

// Logical buttons. Physical mapping per board:
//   M5:  BOOP = BtnA (GPIO37), REJECT = BtnB (GPIO39), MENU absent
//   WS:  BOOP = header IO1 + on-board BOOT (IO0) + any touch on the panel
//        REJECT = header IO2, MENU = header IO5
enum HalButton : uint8_t { HAL_BTN_BOOP = 0, HAL_BTN_REJECT = 1, HAL_BTN_MENU = 2 };
const int HAL_BTN_COUNT = 3;

// Board + display + input bring-up. Call first thing in setup(), before
// guardInit — nothing here depends on guard state and the WDT isn't armed yet.
void halInit();

// Per-loop upkeep: M5.update() on M5, touch poll on Waveshare.
void halUpdate();

// Push the logical canvas to the panel. M5: pushSprite. WS: RGB332->RGB565
// 2x expand into a PSRAM framebuffer + full-frame QSPI flush (full-frame
// keeps every window write even-aligned, which the CO5300 requires, and
// sidesteps tearing — the panel's TE pin isn't routed). Internally
// throttled on WS; safe to call every loop iteration.
void halPresent(BuddyCanvas& spr);

void halDisplaySleep();
void halDisplayWake();
void halSetBrightness(uint8_t b);   // 0-255. WS: DCS 0x51 over QSPI (no backlight pin)
int  halDisplayRotation();

bool halButtonDown(HalButton b);    // raw debounce-free physical state, true = held
bool halHasButton(HalButton b);     // MENU is absent on M5

int  halBatteryVoltage_mV();
int  halBatteryCurrent_mA();        // 0 where unmeasurable (WS has no coulomb counter)
// WS has no charge-status GPIO: heuristic (vbat at charger CV level). The
// OTA gate wants "safe to flash", and USB-present is what it really asks.
bool halIsCharging();
void halSetLed(bool on);            // no-op on WS (no user LED)
void halTone(uint16_t freq, uint16_t ms);   // no-op on WS (no speaker)

// Set the wall clock from the bridge's time sync. M5: BM8563 RTC (survives
// reboot on coin cell). WS: settimeofday only (no RTC chip — time is lost
// on reset and re-synced on next bridge connect).
void halSetLocalTime(const struct tm& lt);
