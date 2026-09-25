// The canvas palette: index → RGB565 (plan/DEVICE.md §6). Every colour on
// the screen comes from this one table: "Warm Terminal", black glass with
// light oat eyes and one amber accent, plus the bring-up colours.
//
// Anti-aliased edges use ramps: 8 steps from black up to an ink colour, and
// 7 steps from an eye colour down to the pupil. The table is computed with
// integer maths at compile time, so the board and the simulator agree.
#pragma once
#include <cstdint>

namespace render {

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return uint16_t(((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3));
}

struct Rgb {
  uint8_t r, g, b;
};

// The Warm Terminal colours.
constexpr Rgb kGlass = {0, 0, 0};          // the backlit black
constexpr Rgb kOatRgb = {232, 220, 196};   // eyes and main text
constexpr Rgb kAmberRgb = {255, 176, 0};   // the one accent: needs you, the word
constexpr Rgb kGlowRgb = {255, 206, 110};  // warm glow for cheers
constexpr Rgb kOopsRgb = {186, 72, 58};    // dim red for oops
constexpr Rgb kGreyRgb = {140, 132, 121};  // secondary text
constexpr Rgb kDimRgb = {74, 68, 62};      // faint text, dividers, rings
constexpr Rgb kPupilRgb = {30, 23, 18};    // pupils and open mouths

// Fixed entries. 0–8 are also the bring-up pattern's colours.
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
  kPupil,
  kFixedCount,
};

// Inks: colours drawn over black with an anti-aliased ramp. Eye tints come
// first, so an eye's ink is also its tint: oat, then four steps towards the
// cheer glow, then four towards the oops red.
enum Ink : uint8_t {
  kInkOat = 0,
  kInkGlow1,
  kInkGlow2,
  kInkGlow3,
  kInkGlow4,
  kInkOops1,
  kInkOops2,
  kInkOops3,
  kInkOops4,
  kInkAmber,
  kInkGrey,
  kInkDim,
  kInkCount,
};
constexpr int kEyeInks = kInkOops4 + 1;

constexpr int kLevels = 8;          // coverage 1..8 of 8; 0 is the background
constexpr int kInkBase = 16;        // ink i, level k at kInkBase + i * 8 + k - 1
constexpr int kPupilBase = kInkBase + kInkCount * kLevels;  // eye ink e, k 1..7
constexpr int kPaletteUsed = kPupilBase + kEyeInks * (kLevels - 1);
static_assert(kPaletteUsed <= 256, "palette overflow");

// The index for ink `ink` at coverage `level` (0..8) over black.
constexpr uint8_t inkAt(int ink, int level) {
  return level <= 0 ? kBlack : uint8_t(kInkBase + ink * kLevels + (level > kLevels ? kLevels : level) - 1);
}
// The index for pupil coverage `level` (0..8) over eye ink `eye`.
constexpr uint8_t pupilAt(int eye, int level) {
  return level <= 0 ? inkAt(eye, kLevels) : level >= kLevels ? kPupil : uint8_t(kPupilBase + eye * (kLevels - 1) + level - 1);
}

constexpr Rgb mix(Rgb a, Rgb b, int num, int den) {
  return {uint8_t((a.r * (den - num) + b.r * num + den / 2) / den),
          uint8_t((a.g * (den - num) + b.g * num + den / 2) / den),
          uint8_t((a.b * (den - num) + b.b * num + den / 2) / den)};
}
constexpr uint16_t rgb565(Rgb c) { return rgb565(c.r, c.g, c.b); }

constexpr Rgb inkRgb(int ink) {
  if (ink == kInkOat) return kOatRgb;
  if (ink <= kInkGlow4) return mix(kOatRgb, kGlowRgb, ink - kInkOat, 4);
  if (ink <= kInkOops4) return mix(kOatRgb, kOopsRgb, ink - kInkGlow4, 4);
  if (ink == kInkAmber) return kAmberRgb;
  if (ink == kInkGrey) return kGreyRgb;
  return kDimRgb;
}

struct PaletteTable {
  uint16_t c[256];
};

constexpr PaletteTable makePalette() {
  PaletteTable p{};
  const Rgb fixed[kFixedCount] = {
      {0, 0, 0}, {255, 255, 255}, {255, 0, 0}, {0, 255, 0}, {0, 0, 255},
      kAmberRgb, {128, 128, 128}, {64, 64, 64}, kOatRgb, kPupilRgb,
  };
  for (int i = 0; i < kFixedCount; ++i) p.c[i] = rgb565(fixed[i]);
  for (int ink = 0; ink < kInkCount; ++ink) {
    for (int k = 1; k <= kLevels; ++k) p.c[inkAt(ink, k)] = rgb565(mix(kGlass, inkRgb(ink), k, kLevels));
  }
  for (int eye = 0; eye < kEyeInks; ++eye) {
    for (int k = 1; k < kLevels; ++k) p.c[pupilAt(eye, k)] = rgb565(mix(inkRgb(eye), kPupilRgb, k, kLevels));
  }
  return p;
}

constexpr PaletteTable kPalette = makePalette();

// The full 256-entry table as sent in a screenshot; unused entries are black.
inline uint16_t paletteAt(int index) { return index >= 0 && index < 256 ? kPalette.c[index] : 0; }

}  // namespace render
