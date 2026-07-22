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
  // screen is LANDSCAPE at NATIVE resolution (456x280, ~340 PPI). The
  // sprite lives in PSRAM; halPresent rotates it 1:1 into the panel's
  // portrait scan order (the CO5300 has no hardware rotation). UI text
  // draws at 2x scale (HAL_UI_SCALE) to keep the chunky pixel-font
  // identity; the face draws anti-aliased at native resolution.
  const int HAL_W = 456;
  const int HAL_H = 280;
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
// the portrait M5 keeps the original 70px block. HAL_UI_SCALE multiplies
// text sizes and row offsets so shared UI code renders identically on
// the M5 (1x) and at matching physical size on the native-res WS (2x).
const bool HAL_LANDSCAPE = HAL_W > HAL_H;
const int  HAL_UI_SCALE = HAL_LANDSCAPE ? 2 : 1;
const int  HAL_HUD_H = HAL_LANDSCAPE ? 104 : 70;

// True when the present throttle would accept a frame now — the draw
// pass is gated on this so the (PSRAM) canvas isn't repainted on loop
// iterations whose frame would be dropped anyway. Always true on M5.
bool halPresentDue();

// Main-loop tick. The WS board runs an 8ms tick so its 24ms present
// throttle isn't quantized up to 32ms (measured present cost ~13ms →
// ~42fps at ~56% of the core). The M5 presents unthrottled every loop,
// so its tick stays 16ms to keep the ST7789 push off the critical path.
#ifdef BOARD_WS_AMOLED_164
const uint32_t HAL_LOOP_MS = 8;
#else
const uint32_t HAL_LOOP_MS = 16;
#endif

// Logical buttons. Physical mapping per board:
//   M5:  BOOP = BtnA (GPIO37), REJECT = BtnB (GPIO39), MENU absent
//   WS:  BOOP = header IO1 + on-board BOOT (IO0)
//        REJECT = header IO2, MENU = header IO5
// Panel touch is intentionally NOT part of BOOP — see halTouchDown().
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

// Rolling cost of one present (rotate+expand+flush), microseconds: EMA
// (alpha 1/8) and lifetime max. Zeros on M5 (pushSprite isn't measured).
// Surfaces in PONG so animation cadence is tuned against measured numbers.
void halFrameStats(uint32_t* avgUs, uint32_t* maxUs);

void halDisplaySleep();
void halDisplayWake();
void halSetBrightness(uint8_t b);   // 0-255. WS: DCS 0x51 over QSPI (no backlight pin)
int  halDisplayRotation();

bool halButtonDown(HalButton b);    // raw debounce-free physical state, true = held
bool halHasButton(HalButton b);     // MENU is absent on M5

// Touchscreen contact (WS only; always false on M5). Deliberately NOT a
// button: per the product doctrine only physical buttons may approve or
// deny — touch and IMU are affection/display-only, so a cat on the desk
// can never answer a permission prompt.
bool halTouchDown();

// Accelerometer sample in g (WS: QMI8658 on the touch I2C bus; M5: none —
// always false). Axes are the chip's own; motion logic in main.cpp only
// uses the vector magnitude and the panel-normal (z) axis, and is
// display-only per the same doctrine as touch.
bool halImuRead(float* ax, float* ay, float* az);

// Lowest safe sleep the board supports; never returns (the device restarts
// on wake). Wake = the BOOP button; timerWakeMs adds a timer wake so HIL
// can prove the round-trip without a human finger (0 = button only).
// WS: light sleep + esp_restart — GPIO0 is a strapping pin, so a true
// deep-sleep wake with the button still held would strap the ROM into
// download mode; light sleep wakes without a strap sample. M5: true deep
// sleep with EXT1 on BtnA (GPIO37, not a strapping pin).
void halDeepSleep(uint32_t timerWakeMs);

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
