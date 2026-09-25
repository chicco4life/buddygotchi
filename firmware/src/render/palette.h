// The canvas palette: index → RGB565 (plan/DEVICE.md §6). Every colour on
// the screen comes from this one table. F1 has the bring-up colours; F2
// adds "Warm Terminal".
#pragma once
#include <cstdint>

namespace render {

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return uint16_t(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}

enum Color : uint8_t {
  kBlack = 0,
  kWhite,
  kRed,
  kGreen,
  kBlue,
  kAmber,
  kGrey,
  kDarkGrey,
  kOat,
  kColorCount,
};

// Native-endian RGB565 for each index; unused entries are black.
constexpr uint16_t kPalette[kColorCount] = {
    rgb565(0, 0, 0),        // black
    rgb565(255, 255, 255),  // white
    rgb565(255, 0, 0),      // red
    rgb565(0, 255, 0),      // green
    rgb565(0, 0, 255),      // blue
    rgb565(255, 176, 0),    // amber
    rgb565(128, 128, 128),  // grey
    rgb565(64, 64, 64),     // dark grey
    rgb565(232, 220, 196),  // oat
};

// The full 256-entry table as sent in a screenshot.
inline uint16_t paletteAt(int index) { return index < kColorCount ? kPalette[index] : 0; }

}  // namespace render
