#include "render/face.h"

#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

// Full-size geometry, in pixels.
constexpr int kEyeW = 62, kEyeH = 84, kEyeR = 24;
constexpr int kEyeGap = 48;       // eye centre to face centre
constexpr int kLookShift = 7;     // eyes follow the pupils this far
constexpr int kMouthY = 66;       // mouth centre below the eye centres
constexpr int kMouthHalfW = 16, kMouthThick = 5, kMouthBend = 9, kMouthDrop = 24;

int lerp(int a, int b, int t) { return a + (b - a) * t / 1024; }
int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

struct Eye {
  int x, y, w, h, r;    // centre and size, sub-pixels; h is the open height
  int lidY, lidM;       // upper lid line through (x, lidY) with slope lidM/1000
  bool squint;          // lower lid arc
  int sqCy, sqRx, sqRy;
  int pupX, pupY, pupR, pupRy;  // the pupil flattens as the eye closes
  int glX, glY, glR;

  Spans shape(int sy) const {
    Spans s = roundRect(x - w / 2, y - h / 2, x + w / 2, y + h / 2, r, sy);
    keepBelow(s, x, lidY, lidM, sy);
    int lo, hi;
    if (squint && ellipseRow(x, sqCy, sqRx, sqRy, sy, lo, hi)) s.cut(lo, hi);
    return s;
  }
  Spans pupil(int sy) const {
    Spans s = ellipse(pupX, pupY, pupR, pupRy, sy);
    s.intersect(shape(sy));
    return s;
  }
  Spans glint(int sy) const {
    Spans s = ellipse(glX, glY, glR, glR, sy);
    s.intersect(pupil(sy));
    return s;
  }
};

Eye makeEye(const Pose& p, int cx, int cy, int s, bool right) {
  auto len = [s](int pixels) { return px(pixels) * s / 1000; };
  Eye e{};
  int sq = clampi(p.squash, -600, 600);
  int w = len(kEyeW) * (1000 + sq * 4 / 10) / 1000;
  int fullH = len(kEyeH) * (1000 - sq * 6 / 10) / 1000;
  int open = clampi(p.open, 0, 1000);
  e.w = w;
  e.h = fullH * open / 1000;
  if (e.h < len(4)) e.h = len(4);
  e.r = len(kEyeR);
  e.x = cx + (right ? len(kEyeGap) : -len(kEyeGap)) + len(kLookShift) * p.lookX / 1000;
  e.y = cy + len(kLookShift) * p.lookY / 1000 * 2 / 3;

  int lid = p.lidTop + (right ? (p.wink > 0 ? p.wink : 0) : (p.wink < 0 ? -p.wink : 0));
  lid = clampi(lid, 0, 1000);
  e.lidY = e.y - e.h / 2 + e.h * lid / 1000;
  int m = clampi(p.lidTilt, -1000, 1000) * 7 / 10;
  e.lidM = right ? -m : m;

  e.squint = p.lidBot > 0;
  e.sqRx = w * 7 / 10;
  e.sqRy = e.h * 6 / 10;
  e.sqCy = e.y + e.h / 2 + e.sqRy - e.h * clampi(p.lidBot, 0, 1000) / 1000;

  // Happy arc eyes have no pupils: they shrink away as the lower lids rise.
  int hide = 1000 - clampi(p.lidBot, 0, 300) * 1000 / 300;
  e.pupR = w * 3 / 10 * clampi(p.pupil, 200, 1600) / 1000 * hide / 1000;
  int roamX = w / 2 - e.pupR - len(3), roamY = fullH / 2 - e.pupR - len(3);
  if (roamX < 0) roamX = 0;
  if (roamY < 0) roamY = 0;
  e.pupX = e.x + roamX * clampi(p.lookX, -1000, 1000) / 1000;
  e.pupY = e.y + roamY * clampi(p.lookY, -1000, 1000) / 1000;
  e.pupRy = e.h / 2 - len(4);
  if (e.pupRy > e.pupR) e.pupRy = e.pupR;
  if (e.pupY < e.y - e.h / 2 + e.pupRy) e.pupY = e.y - e.h / 2 + e.pupRy;
  if (e.pupY > e.y + e.h / 2 - e.pupRy) e.pupY = e.y + e.h / 2 - e.pupRy;
  e.glR = e.pupRy * 28 / 100;
  e.glX = e.pupX - e.pupR * 35 / 100;
  e.glY = e.pupY - e.pupR * 40 / 100;
  return e;
}

void drawEye(Canvas& c, const Eye& e, int ink) {
  uint8_t* px = c.pixels();
  int y0 = (e.y - e.h / 2) / kSub - 1, y1 = (e.y + e.h / 2) / kSub + 2;
  fillShape(y0, y1, [&](int sy) { return e.shape(sy); },
            [&](int x, int y, int level) { px[y * kWidth + x] = inkAt(ink, level); });
  if (e.pupRy < render::px(3) || e.pupR < render::px(3)) return;  // too small to read as a pupil
  y0 = (e.pupY - e.pupRy) / kSub - 1, y1 = (e.pupY + e.pupRy) / kSub + 2;
  // Where the eye's own edge is soft (a lid line), the near-black pupil just
  // darkens it, so the edge stays clean.
  auto overEye = [&](int x, int y, int level) {
    uint8_t& at = px[y * kWidth + x];
    int eye = at >= inkAt(ink, 1) && at <= inkAt(ink, kLevels) ? at - inkAt(ink, 1) + 1 : kLevels;
    at = eye == kLevels ? pupilAt(ink, level) : inkAt(ink, eye * (kLevels - level) / kLevels);
  };
  fillShape(y0, y1, [&](int sy) { return e.pupil(sy); }, overEye);
  y0 = (e.glY - e.glR) / kSub - 1, y1 = (e.glY + e.glR) / kSub + 2;
  fillShape(y0, y1, [&](int sy) { return e.glint(sy); },
            [&](int x, int y, int level) { px[y * kWidth + x] = pupilAt(ink, kLevels - level); });
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
  m.x = cx + len(p.mouthX);
  m.y = cy + len(kMouthY);
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
            [&](int x, int y, int level) { px[y * kWidth + x] = pupilAt(ink, level); });
}

}  // namespace

Pose blend(const Pose& a, const Pose& b, int t) {
  Pose o;
  o.open = int16_t(lerp(a.open, b.open, t));
  o.lookX = int16_t(lerp(a.lookX, b.lookX, t));
  o.lookY = int16_t(lerp(a.lookY, b.lookY, t));
  o.pupil = int16_t(lerp(a.pupil, b.pupil, t));
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
  return o;
}

bool operator==(const Pose& a, const Pose& b) {
  return a.open == b.open && a.lookX == b.lookX && a.lookY == b.lookY && a.pupil == b.pupil &&
         a.lidTop == b.lidTop && a.lidTilt == b.lidTilt && a.lidBot == b.lidBot && a.wink == b.wink &&
         a.squash == b.squash && a.mouthCurve == b.mouthCurve && a.mouthOpen == b.mouthOpen &&
         a.mouthWide == b.mouthWide && a.mouthX == b.mouthX && a.dx == b.dx && a.dy == b.dy &&
         a.size == b.size && a.glow == b.glow && a.oops == b.oops;
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
