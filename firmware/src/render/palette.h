// The canvas palette: index → RGB565 (plan/DEVICE.md §6). Every colour on
// the screen comes from this one table: "Warm Terminal", black glass with
// grey text and one amber accent, plus the bring-up colours; then the
// animation pack's colours, flat, which faces.h lists; and a stronger
// coral heart for a tap.
//
// Anti-aliased edges (text, the bubble and the strip) use ramps: 8 steps
// from black up to an ink colour. The face is pixel art, so it uses only
// each ink's full-strength step. The table is computed with integer maths at
// compile time, so the board and the simulator agree.
#pragma once
#include <cstdint>

#include "faces.h"

namespace render {

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return uint16_t(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}

struct Rgb {
  uint8_t r, g, b;
};

// The Warm Terminal colours.
constexpr Rgb kGlass = {0, 0, 0};          // the backlit black
// The face's inks are the mood designs' colours as near as RGB565 gets:
// the eyes' #F8F7EF shows as (247, 247, 239), the cheeks' #F1787D as
// (239, 121, 123), the tears' #7BB4EF as (123, 178, 239).
constexpr Rgb kEyeRgb = {246, 244, 238};   // the eyes and mouth: warm white
constexpr Rgb kAmberRgb = {255, 176, 0};   // the one accent: needs you, the word
constexpr Rgb kGreyRgb = {140, 132, 121};  // secondary text
constexpr Rgb kDimRgb = {74, 68, 62};      // faint text, dividers, rings
constexpr Rgb kRoseRgb = {255, 92, 110};   // the heart: a stronger cheek coral
constexpr Rgb kSkyRgb = {120, 176, 235};   // the tears: a soft sky
constexpr Rgb kBlushRgb = {236, 120, 124};  // the cheeks
// The mood designs' props (render/scene.h): the "needs you" sign's softer
// amber, and the keyboard's and the cards' two greys.
constexpr Rgb kSignRgb = {244, 188, 80};
constexpr Rgb kPropDimRgb = {104, 104, 94};
constexpr Rgb kPropRgb = {169, 169, 155};

// Fixed entries: the bring-up pattern's colours.
enum Color : uint8_t {
  kBlack = 0,
  kWhite,
  kRed,
  kGreen,
  kBlue,
  kAmber,
  kGrey,
  kFixedCount,
};

// Inks: colours drawn over black with an anti-aliased ramp.
enum Ink : uint8_t {
  kInkEye = 0,  // the eyes and mouth
  kInkAmber,
  kInkGrey,
  kInkDim,
  kInkRose,  // the heart
  kInkSky,   // the designs' tears
  kInkBlush, // the cheeks
  kInkSign,     // the mood designs' props: the sign,
  kInkPropDim,  // the keyboard's frame and keys,
  kInkProp,     // and the lighter grey of the cards
  kInkCount,
};

constexpr int kLevels = 8;          // coverage 1..8 of 8; 0 is the background
constexpr int kInkBase = 16;        // ink i, level k at kInkBase + i * 8 + k - 1
constexpr int kPaletteUsed = kInkBase + kInkCount * kLevels;
static_assert(kPaletteUsed == faces::kSceneBase, "the scene colours start after the ramps");
static_assert(faces::kSceneBase + faces::kColorCount - 1 <= 256, "palette overflow");

// The index for ink `ink` at coverage `level` (0..8) over black.
constexpr uint8_t inkAt(int ink, int level) {
  return level <= 0 ? kBlack : uint8_t(kInkBase + ink * kLevels + (level > kLevels ? kLevels : level) - 1);
}

constexpr Rgb mix(Rgb a, Rgb b, int num, int den) {
  return {uint8_t((a.r * (den - num) + b.r * num + den / 2) / den),
          uint8_t((a.g * (den - num) + b.g * num + den / 2) / den),
          uint8_t((a.b * (den - num) + b.b * num + den / 2) / den)};
}
constexpr uint16_t rgb565(Rgb c) { return rgb565(c.r, c.g, c.b); }

constexpr Rgb inkRgb(int ink) {
  if (ink == kInkEye) return kEyeRgb;
  if (ink == kInkAmber) return kAmberRgb;
  if (ink == kInkGrey) return kGreyRgb;
  if (ink == kInkRose) return kRoseRgb;
  if (ink == kInkSky) return kSkyRgb;
  if (ink == kInkBlush) return kBlushRgb;
  if (ink == kInkSign) return kSignRgb;
  if (ink == kInkPropDim) return kPropDimRgb;
  if (ink == kInkProp) return kPropRgb;
  return kDimRgb;
}

struct PaletteTable {
  uint16_t c[256];
};

constexpr PaletteTable makePalette() {
  PaletteTable p{};
  const Rgb fixed[kFixedCount] = {
      {0, 0, 0}, {255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {0, 0, 255},
      kAmberRgb, {128, 128, 128},
  };
  for (int i = 0; i < kFixedCount; ++i) p.c[i] = rgb565(fixed[i]);
  for (int ink = 0; ink < kInkCount; ++ink) {
    for (int k = 1; k <= kLevels; ++k) p.c[inkAt(ink, k)] = rgb565(mix(kGlass, inkRgb(ink), k, kLevels));
  }
  // The animation pack's colours, flat (render/scene.cpp), after the ramps.
  for (int i = 1; i < faces::kColorCount; ++i) {
    const faces::Color& c = faces::kColors[i];
    p.c[faces::kSceneBase + i - 1] = rgb565(c.r, c.g, c.b);
  }
  return p;
}

constexpr PaletteTable kPalette = makePalette();

// The full 256-entry table as sent in a screenshot; unused entries are black.
inline uint16_t paletteAt(int index) { return index >= 0 && index < 256 ? kPalette.c[index] : 0; }

}  // namespace render
