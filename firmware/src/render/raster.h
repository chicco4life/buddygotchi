// Anti-aliased shape filling for the bubble and the strip (the face itself
// is pixel art), in integer maths only, so the board and the simulator draw
// the same pixels (plan/PROTOCOL.md §5).
//
// Coordinates are in sub-pixels: 1/16 px (kSub). A shape is a function from
// a sub-scanline's y to a few horizontal spans. Each pixel row samples 4
// sub-scanlines and adds up exact horizontal coverage, which gives 64 steps
// of coverage per pixel, quantised to the palette's 8 ramp levels.
#pragma once
#include <cstdint>
#include <cstring>

#include "render/canvas.h"

namespace render {

constexpr int kSub = 16;
constexpr int kSubRows = 4;

constexpr int px(int pixels) { return pixels * kSub; }

// Integer square root, rounded down.
uint32_t isqrt(uint32_t v);

// sin of `turn` (1024 per full turn), scaled to ±1024.
int isin(int turn);

// Smoothstep ease-in-out: t of `dur` → 0..1024.
int ease(int t, int dur);

// v, held within [lo, hi].
constexpr int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// Up to four half-open spans [a, b) on one sub-scanline.
struct Spans {
  struct Span {
    int a, b;
  };
  Span s[4];
  int n = 0;

  void add(int a, int b) {
    if (b > a && n < 4) s[n++] = {a, b};
  }
  // Removes x in [lo, hi), which may split a span.
  void cut(int lo, int hi);
};

// A circle.
Spans circle(int cx, int cy, int r, int sy);
// The part of the circle's row inside it, as [lo, hi); false if none.
bool circleRow(int cx, int cy, int r, int sy, int& lo, int& hi);

// Fills pixel rows [y0, y1) from `shape(sy) -> Spans`, calling
// `plot(x, y, level)` with level 1..8 for every pixel it touches.
template <class Shape, class Plot>
void fillShape(int y0, int y1, Shape shape, Plot plot) {
  if (y0 < 0) y0 = 0;
  if (y1 > kHeight) y1 = kHeight;
  uint8_t acc[kWidth];
  for (int y = y0; y < y1; ++y) {
    int minX = kWidth, maxX = -1;
    std::memset(acc, 0, sizeof(acc));
    for (int r = 0; r < kSubRows; ++r) {
      Spans sp = shape(px(y) + (2 * r + 1) * kSub / (2 * kSubRows));
      for (int i = 0; i < sp.n; ++i) {
        int a = sp.s[i].a < 0 ? 0 : sp.s[i].a;
        int b = sp.s[i].b > px(kWidth) ? px(kWidth) : sp.s[i].b;
        if (b <= a) continue;
        int p0 = a / kSub, p1 = (b - 1) / kSub;
        if (p0 < minX) minX = p0;
        if (p1 > maxX) maxX = p1;
        if (p0 == p1) {
          acc[p0] = uint8_t(acc[p0] + (b - a));
        } else {
          acc[p0] = uint8_t(acc[p0] + (px(p0 + 1) - a));
          for (int x = p0 + 1; x < p1; ++x) acc[x] = uint8_t(acc[x] + kSub);
          acc[p1] = uint8_t(acc[p1] + (b - px(p1)));
        }
      }
    }
    for (int x = minX; x <= maxX; ++x) {
      int level = (acc[x] * 8 + 32) / (kSub * kSubRows);
      if (level > 0) plot(x, y, level);
    }
  }
}

// Fills a shape that is one vertical band per x: `band(sx, top, bottom)`
// gives the band [top, bottom) at sample column sx, or false for none. Tests
// 4×4 samples per pixel, asking for each column once, which is what makes
// the bubble's squiggles cheap on the board. `plot(x, y, level)` as above.
template <class Band, class Plot>
void fillBands(int x0, int x1, Band band, Plot plot) {
  if (x0 < 0) x0 = 0;
  if (x1 > kWidth) x1 = kWidth;
  for (int x = x0; x < x1; ++x) {
    int top[4], bottom[4], lo = 1 << 30, hi = -(1 << 30);
    bool any = false;
    for (int i = 0; i < 4; ++i) {
      if (!band(px(x) + 2 + 4 * i, top[i], bottom[i])) top[i] = bottom[i] = 0;
      if (bottom[i] > top[i]) {
        any = true;
        if (top[i] < lo) lo = top[i];
        if (bottom[i] > hi) hi = bottom[i];
      }
    }
    if (!any) continue;
    int y0 = lo / kSub - 1, y1 = hi / kSub + 1;
    if (y0 < 0) y0 = 0;
    if (y1 > kHeight) y1 = kHeight;
    for (int y = y0; y < y1; ++y) {
      int n = 0;
      for (int j = 0; j < 4; ++j) {
        int sy = px(y) + 2 + 4 * j;
        for (int i = 0; i < 4; ++i) n += sy >= top[i] && sy < bottom[i];
      }
      if (n) plot(x, y, (n + 1) / 2);
    }
  }
}

}  // namespace render
