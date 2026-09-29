#include "render/raster.h"

namespace render {

uint32_t isqrt(uint32_t v) {
  uint32_t r = 0, bit = uint32_t(1) << 30;
  while (bit > v) bit >>= 2;
  while (bit) {
    if (v >= r + bit) {
      v -= r + bit;
      r = (r >> 1) + bit;
    } else {
      r >>= 1;
    }
    bit >>= 2;
  }
  return r;
}

int ease(int t, int dur) {
  if (dur <= 0 || t >= dur) return 1024;
  if (t <= 0) return 0;
  int64_t u = int64_t(t) * 1024 / dur;  // 0..1024
  return int(u * u * (3 * 1024 - 2 * u) / (1024 * 1024));
}

void Spans::cut(int lo, int hi) {
  if (hi <= lo) return;
  Spans out;
  for (int i = 0; i < n; ++i) {
    out.add(s[i].a, s[i].b < lo ? s[i].b : lo);
    out.add(s[i].a > hi ? s[i].a : hi, s[i].b);
  }
  *this = out;
}

bool circleRow(int cx, int cy, int r, int sy, int& lo, int& hi) {
  int dy = sy - cy;
  if (r <= 0 || dy <= -r || dy >= r) return false;
  int hw = int(isqrt(uint32_t(r * r - dy * dy)));
  lo = cx - hw, hi = cx + hw;
  return hw > 0;
}

Spans circle(int cx, int cy, int r, int sy) {
  Spans out;
  int lo, hi;
  if (circleRow(cx, cy, r, sy, lo, hi)) out.add(lo, hi);
  return out;
}

}  // namespace render
