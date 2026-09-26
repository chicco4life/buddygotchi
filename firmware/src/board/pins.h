// Pin map for the MicroTech MTR024QV01A (plan/DEVICE.md §2) and what's
// attached on this bench (§3).
#pragma once

namespace pins {
// Screen, ST7789 on SPI2 (HSPI).
constexpr int kLcdSclk = 14;
constexpr int kLcdMosi = 13;
constexpr int kLcdCs = 15;
constexpr int kLcdDc = 2;
constexpr int kBacklight = 21;  // high is on

// Touch, XPT2046 on SPI3 (VSPI), remapped.
constexpr int kTouchSclk = 25;
constexpr int kTouchMosi = 32;
constexpr int kTouchMiso = 39;
constexpr int kTouchCs = 33;
constexpr int kTouchIrq = 36;  // low while pressed

// RGB LED, common anode: low is on.
constexpr int kLedRed = 22;
constexpr int kLedGreen = 16;
constexpr int kLedBlue = 17;

// Audio: DAC channel 2 into the amp; amp enable is active low.
constexpr int kDac = 26;
constexpr int kAmpEnable = 4;

constexpr int kBattery = 34;  // ADC, divider assumed 2:1
// No battery on the v1 bench, so the sense pin floats: `status` reports
// `bat` 0 rather than a reading of nothing (plan/PROTOCOL.md §4).
constexpr bool kHasBattery = false;

// The main button. BOOT (IO0) on the v1 bench; an external button on IO35 later.
constexpr int kMainButton = 0;
}  // namespace pins
