#include "render/face.h"

#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

// Full-size geometry, in pixels. The eyes are solid rounded rectangles, a
// bit taller than wide and set wide apart, with a small mouth tucked in
// low between them (plan/UX.md §2).
constexpr int kEyeW = 60, kEyeH = 80, kEyeR = 22;
constexpr int kEyeGap = 67;              // eye centre to face centre: 134 px apart, 42% of the screen
constexpr int kLookX = 26, kLookY = 16;  // a full look moves the whole eye this far
constexpr int kTurn = 110;               // permille: a full sideways look grows the near eye this much
                                         // and shrinks the far one, like a head turning (Cozmo)
constexpr int kLidRound = 8;             // radius where a lid meets the outline (smaller where 8 won't fit)
constexpr int kMouthFollow = 450;        // permille of the eyes' move the mouth follows
constexpr int kMouthY = 54;              // mouth centre below the eye centres
constexpr int kMouthHalfW = 14, kMouthThick = 4, kMouthBend = 7, kMouthDrop = 14;

// The middle of the face (from the eye tops to the mouth) lies kFaceDrop
// below the eye centres; screens.cpp centres the face on that.
static_assert(kFaceDrop == (kMouthY + kMouthThick / 2 - kEyeH / 2) / 2, "face.h kFaceDrop follows the geometry");

int lerp(int a, int b, int t) { return a + (b - a) * t / 1024; }
int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

// A soft corner where the upper lid meets the outline of an eye, so a lid
// never leaves a sharp point. Near the corner the shape becomes a circle of
// radius q about (vx, vy), over the directions between the outline's outward
// normal where the circle touches it (n2) and the lid's (n1 = (m, -1000)).
// Worked out for the eye's left end; the right end is the same in a mirrored
// frame.
struct Fillet {
  bool on = false;
  int q = 0, vx = 0, vy = 0, n2x = 0, n2y = 0;
};

int64_t cross(int64_t ax, int64_t ay, int64_t bx, int64_t by) { return ax * by - ay * bx; }

// The fillet of radius q at the left end of the lid line through (lx, ly)
// with slope m/1000, on the rounded rectangle whose left side is x0, top y0,
// bottom y1 and corner radius r. Its centre is where the lid line, moved q
// into the eye, meets the outline moved q in: on the straight side, or on
// the top or bottom corner's arc. Off when the lid meets the flat top (an
// obtuse corner, left as it is), misses the eye, or leaves no room for q.
Fillet lidFillet(int x0, int y0, int y1, int r, int lx, int ly, int m, int q) {
  Fillet f;
  if (q <= 0 || q > r) return f;
  int shift = int(int64_t(q) * int64_t(isqrt(uint64_t(1000000 + int64_t(m) * m))) / 1000);
  auto lineY = [&](int x) { return ly + shift + int(int64_t(m) * (x - lx) / 1000); };
  int vx = x0 + q, vy = lineY(vx);
  if (vy >= y0 + r && vy <= y1 - r) {  // on the straight side
    f.n2x = -1, f.n2y = 0;
  } else {  // on a corner's arc: radius r - q about (x0 + r, y0 + r) or (x0 + r, y1 - r)
    int cx = x0 + r, cy = vy < y0 + r ? y0 + r : y1 - r, rad = r - q;
    int64_t e = lineY(cx) - cy, a = 1000000 + int64_t(m) * m;
    int64_t disc = a * rad * rad - 1000000 * e * e;
    if (disc <= 0) return f;
    int u = int(-1000 * (m * e + int64_t(isqrt(uint64_t(disc)))) / a);  // the left crossing
    if (u >= 0) return f;  // past the arc: the lid meets the flat top or bottom
    vx = cx + u, vy = lineY(vx);
    f.n2x = u, f.n2y = vy - cy;
  }
  if (cross(f.n2x, f.n2y, m, -1000) <= 0) return f;  // no corner to soften
  f.on = true, f.q = q, f.vx = vx, f.vy = vy;
  return f;
}

// The lid corner at the left end, at radius q where it fits. Where it
// doesn't (a nearly shut eye, or a tilted lid that comes down low at the
// end), the largest radius that does, a pixel at a time down to 2 px,
// still takes the point off.
Fillet lidCorner(int x0, int y0, int y1, int r, int lx, int ly, int m, int q) {
  for (;;) {
    Fillet f = lidFillet(x0, y0, y1, r, lx, ly, m, q);
    if (f.on || q <= px(2)) return f;
    q = q - px(1) > px(2) ? q - px(1) : px(2);
  }
}

// Narrows [lo, hi) on sub-scanline sy to the fillet's circle where the
// circle is the edge.
void applyFillet(const Fillet& f, int m, int sy, int& lo, int& hi) {
  const int q = f.q;
  int dy = sy - f.vy;
  if (!f.on || dy >= q) return;
  auto inCone = [&](int dx, int ddy) {
    return cross(f.n2x, f.n2y, dx, ddy) >= 0 && cross(dx, ddy, m, -1000) >= 0;
  };
  if (dy <= -q) {  // above the circle: nothing, if the circle's top is the shape's top
    if (inCone(0, -1)) hi = lo;
    return;
  }
  int s = int(isqrt(uint64_t(int64_t(q) * q - int64_t(dy) * dy)));
  if (inCone(-s, dy) && f.vx - s > lo) lo = f.vx - s;
  if (inCone(s, dy) && f.vx + s < hi) hi = f.vx + s;
}

struct Eye {
  int x, y, w, h, r;    // centre and size, sub-pixels; h is the open height
  int lidY, lidM;       // upper lid line through (x, lidY) with slope lidM/1000
  Fillet left, right;   // the lid corners; right is in the frame mirrored about x
  bool squint;          // lower lid arc
  int sqCy, sqRx, sqRy;

  Spans shape(int sy) const {
    Spans s = roundRect(x - w / 2, y - h / 2, x + w / 2, y + h / 2, r, sy);
    keepBelow(s, x, lidY, lidM, sy);
    if (s.n == 1 && (left.on || right.on)) {
      int lo = s.s[0].a, hi = s.s[0].b;
      applyFillet(left, lidM, sy, lo, hi);
      int mlo = 2 * x - hi, mhi = 2 * x - lo;
      applyFillet(right, -lidM, sy, mlo, mhi);
      lo = 2 * x - mhi, hi = 2 * x - mlo;
      s.n = 0;
      s.add(lo, hi);
    }
    int lo, hi;
    if (squint && ellipseRow(x, sqCy, sqRx, sqRy, sy, lo, hi)) s.cut(lo, hi);
    return s;
  }
};

Eye makeEye(const Pose& p, int cx, int cy, int s, bool right) {
  auto len = [s](int pixels) { return px(pixels) * s / 1000; };
  Eye e{};
  int lookX = clampi(p.lookX, -1000, 1000), lookY = clampi(p.lookY, -1000, 1000);
  // Perspective: the eye on the side being looked towards is nearer.
  int turn = 1000 + (right ? kTurn : -kTurn) * lookX / 1000;
  int size = clampi(p.eyeSize, 800, 1250) * turn / 1000;
  int sq = clampi(p.squash, -600, 600);
  int w = len(kEyeW) * (1000 + sq * 4 / 10) / 1000 * size / 1000;
  int fullH = len(kEyeH) * (1000 - sq * 6 / 10) / 1000 * size / 1000;
  int open = clampi(p.open, 0, 1000);
  e.w = w / 2 * 2;
  e.h = fullH * open / 1000 / 2 * 2;
  if (e.h < len(4)) e.h = len(4) / 2 * 2;
  e.r = len(kEyeR) * size / 1000;
  if (e.r > e.w / 2) e.r = e.w / 2;
  if (e.r > e.h / 2) e.r = e.h / 2;
  e.x = cx + (right ? len(kEyeGap) : -len(kEyeGap)) + len(kLookX) * lookX / 1000;
  e.y = cy + len(kLookY) * lookY / 1000;

  int lid = p.lidTop + (right ? (p.wink > 0 ? p.wink : 0) : (p.wink < 0 ? -p.wink : 0));
  lid = clampi(lid, 0, 1000);
  e.lidY = e.y - e.h / 2 + e.h * lid / 1000;
  int m = clampi(p.lidTilt, -1000, 1000) * 7 / 10;
  e.lidM = right ? -m : m;
  int q = len(kLidRound) * size / 1000;
  if (q > e.r) q = e.r;
  int x0 = e.x - e.w / 2, y0 = e.y - e.h / 2, y1 = e.y + e.h / 2;
  e.left = lidCorner(x0, y0, y1, e.r, e.x, e.lidY, e.lidM, q);
  e.right = lidCorner(x0, y0, y1, e.r, e.x, e.lidY, -e.lidM, q);  // mirrored about e.x

  e.squint = p.lidBot > 0;
  e.sqRx = w * 55 / 100;
  e.sqRy = e.h / 2;
  e.sqCy = e.y + e.h / 2 + e.sqRy - e.h * clampi(p.lidBot, 0, 1000) / 1000;
  return e;
}

void drawEye(Canvas& c, const Eye& e, int ink) {
  uint8_t* px = c.pixels();
  int y0 = (e.y - e.h / 2) / kSub - 1, y1 = (e.y + e.h / 2) / kSub + 2;
  fillShape(y0, y1, [&](int sy) { return e.shape(sy); },
            [&](int x, int y, int level) { px[y * kWidth + x] = inkAt(ink, level); });
}

struct Mouth {
  int x, y, hw, th, bend, drop;  // sub-pixels

  // Top and bottom of the mouth band at sx, or false outside it.
  bool band(int sx, int inset, int& top, int& bottom) const {
    int w = hw - inset;
    if (w <= 0) return false;
    int u = (sx - x) * 1024 / w;
    if (u <= -1024 || u >= 1024) return false;
    int arch = 1024 - u * u / 1024;
    int yc = y + bend * arch / 1024;
    int t = th * (512 + arch / 2) / 1024;
    top = yc - t + inset;
    // A rounded bottom: the drop follows sqrt(arch), not the arch itself.
    bottom = yc + t + drop * int(isqrt(uint64_t(arch) * 1024)) / 1024 - inset;
    return bottom > top;
  }
};

void drawMouth(Canvas& c, const Pose& p, int cx, int cy, int s, int ink) {
  auto len = [s](int pixels) { return px(pixels) * s / 1000; };
  Mouth m{};
  int lookX = clampi(p.lookX, -1000, 1000), lookY = clampi(p.lookY, -1000, 1000);
  m.x = cx + len(p.mouthX) + len(kLookX) * lookX / 1000 * kMouthFollow / 1000;
  m.y = cy + len(kMouthY) + len(kLookY) * lookY / 1000 * kMouthFollow / 1000;
  m.hw = len(kMouthHalfW) * clampi(p.mouthWide, 200, 2000) / 1000;
  m.th = len(kMouthThick) / 2;
  m.bend = len(kMouthBend) * clampi(p.mouthCurve, -1000, 1000) / 1000;
  m.drop = len(kMouthDrop) * clampi(p.mouthOpen, 0, 1000) / 1000;
  int x0 = (m.x - m.hw) / kSub - 1, x1 = (m.x + m.hw) / kSub + 2;
  uint8_t* px = c.pixels();
  fillBands(x0, x1, [&](int sx, int& top, int& bottom) { return m.band(sx, 0, top, bottom); },
            [&](int x, int y, int level) { px[y * kWidth + x] = inkAt(ink, level); });
  int lip = len(3);
  if (m.drop <= lip) return;
  fillBands(x0, x1, [&](int sx, int& top, int& bottom) { return m.band(sx, lip, top, bottom); },
            [&](int x, int y, int level) { px[y * kWidth + x] = hollowAt(ink, level); });
}

}  // namespace

Pose blend(const Pose& a, const Pose& b, int t) {
  Pose o;
  o.open = int16_t(lerp(a.open, b.open, t));
  o.lookX = int16_t(lerp(a.lookX, b.lookX, t));
  o.lookY = int16_t(lerp(a.lookY, b.lookY, t));
  o.eyeSize = int16_t(lerp(a.eyeSize, b.eyeSize, t));
  o.lidTop = int16_t(lerp(a.lidTop, b.lidTop, t));
  o.lidTilt = int16_t(lerp(a.lidTilt, b.lidTilt, t));
  o.lidBot = int16_t(lerp(a.lidBot, b.lidBot, t));
  o.wink = int16_t(lerp(a.wink, b.wink, t));
  o.squash = int16_t(lerp(a.squash, b.squash, t));
  o.mouthCurve = int16_t(lerp(a.mouthCurve, b.mouthCurve, t));
  o.mouthOpen = int16_t(lerp(a.mouthOpen, b.mouthOpen, t));
  o.mouthWide = int16_t(lerp(a.mouthWide, b.mouthWide, t));
  o.mouthX = int16_t(lerp(a.mouthX, b.mouthX, t));
  o.dx = int16_t(lerp(a.dx, b.dx, t));
  o.dy = int16_t(lerp(a.dy, b.dy, t));
  o.size = int16_t(lerp(a.size, b.size, t));
  o.glow = int16_t(lerp(a.glow, b.glow, t));
  o.oops = int16_t(lerp(a.oops, b.oops, t));
  o.raise = int16_t(lerp(a.raise, b.raise, t));
  return o;
}

bool operator==(const Pose& a, const Pose& b) {
  return a.open == b.open && a.lookX == b.lookX && a.lookY == b.lookY && a.eyeSize == b.eyeSize &&
         a.lidTop == b.lidTop && a.lidTilt == b.lidTilt && a.lidBot == b.lidBot && a.wink == b.wink &&
         a.squash == b.squash && a.mouthCurve == b.mouthCurve && a.mouthOpen == b.mouthOpen &&
         a.mouthWide == b.mouthWide && a.mouthX == b.mouthX && a.dx == b.dx && a.dy == b.dy &&
         a.size == b.size && a.glow == b.glow && a.oops == b.oops && a.raise == b.raise;
}

int eyeInk(const Pose& p) {
  if (p.glow >= p.oops) {
    int step = (clampi(p.glow, 0, 1000) * 4 + 500) / 1000;
    return step ? kInkGlow1 + step - 1 : kInkOat;
  }
  int step = (clampi(p.oops, 0, 1000) * 4 + 500) / 1000;
  return step ? kInkOops1 + step - 1 : kInkOat;
}

void drawFace(Canvas& c, const Pose& p, int cx, int cy, int scale) {
  int s = scale * clampi(p.size, 500, 1500) / 1000;
  int x = px(cx) + px(p.dx) * scale / 1000, y = px(cy) + px(p.dy) * scale / 1000;
  int ink = eyeInk(p);
  drawEye(c, makeEye(p, x, y, s, false), ink);
  drawEye(c, makeEye(p, x, y, s, true), ink);
  drawMouth(c, p, x, y, s, ink);
}

}  // namespace render
