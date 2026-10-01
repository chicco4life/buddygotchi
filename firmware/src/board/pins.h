// Pin map for the MicroTech MTR024QV01A (documentation/DEVICE.md §2) and what's
// attached on this bench (§3).
#pragma once

namespace pins {
// Screen, ST7789 on SPI2 (HSPI).
constexpr int kLcdSclk = 14;
constexpr int kLcdMosi = 13;
constexpr int kLcdCs = 15;
constexpr int kLcdDc = 2;
constexpr int kBacklight = 21;  // high is on

// Touch, XPT2046, bit-banged on its own pins (board/touch.cpp).
constexpr int kTouchSclk = 25;
constexpr int kTouchMosi = 32;
constexpr int kTouchMiso = 39;
constexpr int kTouchCs = 33;
constexpr int kTouchIrq = 36;  // low while pressed

// The microSD slot, on SPI3 (VSPI): the voice pack (board/card.cpp).
constexpr int kCardSclk = 18;
constexpr int kCardMiso = 19;
constexpr int kCardMosi = 23;
constexpr int kCardCs = 5;

// RGB LED, common anode: low is on.
constexpr int kLedRed = 22;
constexpr int kLedGreen = 16;
constexpr int kLedBlue = 17;

// Audio: DAC channel 2 into the amp; amp enable is active low.
constexpr int kDac = 26;
constexpr int kAmpEnable = 4;

// The main button. BOOT (IO0) on the v1 bench; an external button on IO35 later.
constexpr int kMainButton = 0;
}  // namespace pins
