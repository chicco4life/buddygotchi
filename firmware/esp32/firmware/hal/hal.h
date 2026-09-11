#pragma once
#include <stdint.h>
#include <Arduino.h>
#include <time.h>

// Board HAL. Everything hardware-specific — display, buttons, power,
// sound, wall clock — goes through this header so the rest of the
// firmware stays board-agnostic in shape.
//
// ONE board: the Waveshare ESP32-S3-Touch-AMOLED-1.64, the production
// "Boop Pebble". CO5300 280x456 QSPI AMOLED, FT3168 touch, QMI8658 IMU,
// external buttons on header GPIOs, battery ADC only, no speaker, no RTC.
//
// The M5StickC Plus 2 was the original dev board and regression rig. It
// was retired on 2026-09-11 (owner: "the old device I no longer use").
// Its HAL, partition table, build envs and the portrait layout branches
// that existed only for its 135x240 screen are all gone. The previous
// generation is still readable under `archived/firmware/esp32/`.

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
using BuddyCanvas = lgfx::v1::LGFX_Sprite;
#define HAL_CANVAS_PARENT nullptr
#define HAL_BOARD_NAME "ws-amoled164"

// The Pebble mounts the portrait 280x456 panel sideways: the product
// screen is LANDSCAPE at NATIVE resolution (456x280, ~340 PPI). The
// sprite lives in PSRAM; halPresent rotates it 1:1 into the panel's
// portrait scan order (the CO5300 has no hardware rotation). The face
// draws anti-aliased at native resolution.
const int HAL_W = 456;
const int HAL_H = 280;

// TFT_eSPI-style colour names used to arrive via M5GFX; LovyanGFX
// standalone doesn't define them.
#ifndef BLACK
  #define BLACK     0x0000
  #define WHITE     0xFFFF
  #define LIGHTGREY 0xC618
  #define GREEN     0x07E0
#endif

// True when the present throttle would accept a frame now — the draw
// pass is gated on this so the (PSRAM) canvas isn't repainted on loop
// iterations whose frame would be dropped anyway.
bool halPresentDue();

// Main-loop tick: 8ms, so the 24ms present throttle isn't quantized up
// to 32ms (measured present cost ~13ms → ~42fps at ~56% of the core).
const uint32_t HAL_LOOP_MS = 8;

// Logical buttons: BOOP = header IO1 + on-board BOOT (IO0),
// REJECT = header IO2, MENU = header IO5.
// Panel touch is intentionally NOT part of BOOP — see halTouchDown().
enum HalButton : uint8_t { HAL_BTN_BOOP = 0, HAL_BTN_REJECT = 1, HAL_BTN_MENU = 2 };
const int HAL_BTN_COUNT = 3;

// Board + display + input bring-up. Call first thing in setup(), before
// guardInit — nothing here depends on guard state and the WDT isn't armed yet.
void halInit();

// Per-loop upkeep: touch poll.
void halUpdate();

// Push the logical canvas to the panel: RGB332->RGB565 2x expand into a
// PSRAM framebuffer + full-frame QSPI flush (full-frame keeps every window
// write even-aligned, which the CO5300 requires, and sidesteps tearing —
// the panel's TE pin isn't routed). Internally throttled; safe to call
// every loop iteration.
void halPresent(BuddyCanvas& spr);

// Rolling cost of one present (rotate+expand+flush), microseconds: EMA
// (alpha 1/8) and lifetime max. Surfaces in PONG so animation cadence is
// tuned against measured numbers.
void halFrameStats(uint32_t* avgUs, uint32_t* maxUs);

void halDisplaySleep();
void halDisplayWake();
void halSetBrightness(uint8_t b);   // 0-255. DCS 0x51 over QSPI (no backlight pin)
int  halDisplayRotation();

bool halButtonDown(HalButton b);    // raw debounce-free physical state, true = held
bool halHasButton(HalButton b);     // all three are present on this board

// Touchscreen contact. Deliberately NOT a
// button: per the product doctrine only physical buttons may approve or
// deny — touch and IMU are affection/display-only, so a cat on the desk
// can never answer a permission prompt.
bool halTouchDown();

// Contact point in SPRITE coordinates (0..HAL_W-1, 0..HAL_H-1), i.e. the
// same space the face is drawn in — callers should never have to know how
// the panel is mounted. False when there's no contact.
// Used for touch-tracked gaze: the eyes follow the finger.
bool halTouchPoint(int* x, int* y);

// Sensor health for the `state` dump — true once the FT3168 / QMI8658
// answered a probe. Probes retry in the background, so false is
// "currently unavailable", not "gone forever".
bool halTouchReady();
bool halImuReady();

// Rolling cost of one touch-poll I2C exchange, microseconds (EMA + max).
// A max in the tens of ms means the bus is stalling the
// loop under a finger — the "animation freezes when I tap" signature.
void halTouchStats(uint32_t* avgUs, uint32_t* maxUs);

// Accelerometer sample in g (QMI8658 on the touch I2C bus). Axes are the
// chip's own; motion logic in main.cpp only
// uses the vector magnitude and the panel-normal (z) axis, and is
// display-only per the same doctrine as touch.
bool halImuRead(float* ax, float* ay, float* az);

// Lowest safe sleep the board supports; never returns (the device restarts
// on wake). Wake = the BOOP button; timerWakeMs adds a timer wake so HIL
// can prove the round-trip without a human finger (0 = button only).
// Light sleep + esp_restart — GPIO0 is a strapping pin, so a true
// deep-sleep wake with the button still held would strap the ROM into
// download mode; light sleep wakes without a strap sample.
void halDeepSleep(uint32_t timerWakeMs);

int  halBatteryVoltage_mV();

// Rough Li-ion state of charge from resting voltage, 0..100, or -1 if the
// ADC gave nothing. Deliberately coarse — the board has no coulomb
// counter and the S3's ADC is noisy, so one significant figure is the
// honest resolution.
//
// ONE curve for the whole firmware. The glance card, the OTA "safe to
// flash" gate and the desktop status payload each carried their own, and
// two of them disagreed about where empty is. This keeps the established
// 3.2V-empty curve that the OTA gate has been shipping with rather than
// the newer 3.3V one, so a safety threshold doesn't move as a side effect
// of tidying a readout.
inline int halBatteryPct() {
  int mv = halBatteryVoltage_mV();
  if (mv <= 0) return -1;
  int pct = (mv - 3200) / 10;          // 3.2V empty, 4.2V full
  return pct < 0 ? 0 : (pct > 100 ? 100 : pct);
}
int  halBatteryCurrent_mA();        // always 0 — no coulomb counter on this board
// No charge-status GPIO: heuristic (vbat at charger CV level). The OTA
// gate wants "safe to flash", and USB-present is what it really asks.
bool halIsCharging();
void halSetLed(bool on);            // no-op (no user LED)
void halSilence();
void halTone(uint16_t freq, uint16_t ms);   // no-op (no speaker)

// Set the wall clock from the bridge's time sync: settimeofday only (no
// RTC chip — time is lost on reset and re-synced on next bridge connect).
void halSetLocalTime(const struct tm& lt);
