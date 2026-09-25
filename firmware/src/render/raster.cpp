#include "render/raster.h"

namespace render {

uint32_t isqrt(uint64_t v) {
  if (v < (uint64_t(1) << 32)) {  // the usual case, in 32-bit maths
    uint32_t x = uint32_t(v), r = 0, bit = uint32_t(1) << 30;
    while (bit > x) bit >>= 2;
    while (bit) {
      if (x >= r + bit) {
        x -= r + bit;
        r = (r >> 1) + bit;
      } else {
        r >>= 1;
      }
      bit >>= 2;
    }
    return r;
  }
  uint64_t r = 0, bit = uint64_t(1) << 62;
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
  return uint32_t(r);
}

namespace {
// sin(i/64 of a quarter turn) × 1024, for i = 0..64.
constexpr int16_t kQuarterSin[65] = {
    0,    25,   50,   75,   100,  125,  150,  175,  200,  224,  249,  273,  297,
    321,  345,  369,  392,  415,  438,  460,  483,  505,  526,  548,  569,  590,
    610,  630,  650,  669,  688,  706,  724,  742,  759,  775,  792,  807,  822,
    837,  851,  865,  878,  891,  903,  915,  926,  936,  946,  955,  964,  972,
    980,  987,  993,  999,  1004, 1009, 1013, 1016, 1019, 1021, 1023, 1024, 1024,
};
}  // namespace

int isin(int turn) {
  turn &= 1023;
  int quadrant = turn >> 8, i = (turn & 255) >> 2, frac = turn & 3;
  auto at = [](int k) { return int(kQuarterSin[k]); };
  int v;
  if (quadrant == 0 || quadrant == 2) {
    v = at(i) + (at(i + 1) - at(i)) * frac / 4;
  } else {
    v = at(64 - i) + (at(63 - i < 0 ? 0 : 63 - i) - at(64 - i)) * frac / 4;
  }
  return quadrant < 2 ? v : -v;
}

int ease(int t, int dur) {
  if (dur <= 0 || t >= dur) return 1024;
  if (t <= 0) return 0;
  int64_t u = int64_t(t) * 1024 / dur;  // 0..1024
  return int(u * u * (3 * 1024 - 2 * u) / (1024 * 1024));
}

void Spans::clip(int lo, int hi) {
  int m = 0;
  for (int i = 0; i < n; ++i) {
    int a = s[i].a < lo ? lo : s[i].a, b = s[i].b > hi ? hi : s[i].b;
    if (b > a) s[m++] = {a, b};
  }
  n = m;
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

void Spans::intersect(const Spans& other) {
  Spans out;
  for (int i = 0; i < n; ++i) {
    for (int j = 0; j < other.n; ++j) {
      int a = s[i].a > other.s[j].a ? s[i].a : other.s[j].a;
      int b = s[i].b < other.s[j].b ? s[i].b : other.s[j].b;
      out.add(a, b);
    }
  }
  *this = out;
}

Spans roundRect(int x0, int y0, int x1, int y1, int r, int sy) {
  Spans out;
  if (sy < y0 || sy >= y1 || x1 <= x0) return out;
  int maxR = (x1 - x0 < y1 - y0 ? x1 - x0 : y1 - y0) / 2;
  if (r > maxR) r = maxR;
  int d = 0;
  if (sy < y0 + r) d = y0 + r - sy;
  else if (sy >= y1 - r) d = sy - (y1 - r) + 1;
  int inset = d > 0 ? r - int(isqrt(uint64_t(int64_t(r) * r - int64_t(d > r ? r : d) * (d > r ? r : d)))) : 0;
  out.add(x0 + inset, x1 - inset);
  return out;
}

bool ellipseRow(int cx, int cy, int rx, int ry, int sy, int& lo, int& hi) {
  int dy = sy - cy;
  if (rx <= 0 || ry <= 0 || dy <= -ry || dy >= ry) return false;
  int64_t q = (int64_t(ry) * ry - int64_t(dy) * dy) * rx * rx / (int64_t(ry) * ry);
  int hw = int(isqrt(uint64_t(q)));
  lo = cx - hw, hi = cx + hw;
  return hw > 0;
}

Spans ellipse(int cx, int cy, int rx, int ry, int sy) {
  Spans out;
  int lo, hi;
  if (ellipseRow(cx, cy, rx, ry, sy, lo, hi)) out.add(lo, hi);
  return out;
}

void keepBelow(Spans& s, int lx, int ly, int m, int sy) {
  if (m == 0) {
    if (sy < ly) s.n = 0;
    return;
  }
  int bound = lx + int(int64_t(sy - ly) * 1000 / m);
  if (m > 0) {
    s.clip(-(1 << 20), bound);
  } else {
    s.clip(bound, 1 << 20);
  }
}

}  // namespace render
