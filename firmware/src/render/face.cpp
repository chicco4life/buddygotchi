#include "render/face.h"

#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

// The face is pixel art (plan/UX.md §2): every part is built from square
// blocks of kBlock screen pixels on one grid, with no anti-aliasing. The
// geometry below is in screen pixels at full size; positions snap to the
// grid, so the face moves a block at a time.
constexpr int kBlock = 3;
// Eyes: square windows of 2×2 panes split by a one-block cross, 13 blocks
// a side, their centres 144 px apart. Closed, squeezed or thin enough
// that a pane would vanish, an eye is a solid bar.
constexpr int kEyeW = 39, kEyeH = 39;
constexpr int kEyeGap = 72;              // eye centre to face centre
constexpr int kLookX = 24, kLookY = 15;  // a full look moves the whole eye this far
constexpr int kTurn = 110;               // permille: a full sideways look grows the near eye this much
                                         // and shrinks the far one, like a head turning
constexpr int kPaneMin = 3;              // blocks: a pane thinner than this and the eye is one bar
constexpr int kMouthFollow = 450;        // permille of the eyes' move the mouth follows
// The mouth: a flat bar as wide as an eye, two blocks thick, level with the
// cheeks; it bends into a smile or frown and drops open into a D.
constexpr int kMouthY = 45;
constexpr int kMouthHalfW = 20, kMouthThick = 6, kMouthBend = 9, kMouthDrop = 12;
constexpr int kSmileWiden = 250;         // permille: a full smile is this much wider
// Happy eyes (lidBot): up to kArchFrom the eye squeezes towards a
// kLidLine bar; from there the bar bends up into a "^" arch, fully raised
// at kArchFull.
constexpr int kArchFrom = 450, kArchFull = 650;
constexpr int kLidLine = 6, kArchRise = 12, kArchThick = 9;
// The cheeks: two pink blocks side by side under each eye, towards the
// outside, level with the mouth.
constexpr int kBlushDx = 22, kBlushDy = 40, kBlushW = 12, kBlushH = 9;
// Around the right eye's centre: where the heart, the sweat drop and the
// "zzZZ" go.
constexpr int kHeartDx = 36, kHeartDy = -30;
constexpr int kSweatDx = 30, kSweatDy = -22, kSweatSlide = 12;
constexpr uint32_t kZzzStep = 220;  // permille of the cycle between letters

// The middle of the face (from the eye tops to the mouth) lies kFaceDrop
// below the eye centres; screens.cpp centres the face on that.
static_assert(kFaceDrop == (kMouthY + kMouthThick / 2 - kEyeH / 2) / 2, "face.h kFaceDrop follows the geometry");

int lerp(int a, int b, int t) { return a + (b - a) * t / 1024; }
int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

constexpr int kB = px(kBlock);  // a block, in sub-pixels
// The block holding sub-pixel v (floor division).
int blockOf(int v) { return v >= 0 ? v / kB : -((-v + kB - 1) / kB); }
// The nearest odd number of blocks to a length in sub-pixels, at least `min`.
int oddBlocks(int len, int min) {
  int n = 2 * (len / (2 * kB)) + 1;  // 12.x blocks → 13, 13.x → 13, 14.x → 15
  return n < min ? min : n;
}
// The centre of block b, in sub-pixels.
int centreOf(int b) { return b * kB + kB / 2; }

void block(Canvas& c, int bx, int by, uint8_t color) { c.fillRect(bx * kBlock, by * kBlock, kBlock, kBlock, color); }

// Softens a filled rectangle of screen pixels [x0, x1] × [y0, y1]: each
// corner pixel that sticks out (both its outward neighbours are background)
// goes black, so panes and bars read as slightly rounded.
void roundCorners(Canvas& c, int x0, int y0, int x1, int y1, uint8_t color) {
  if (x1 - x0 < 3 || y1 - y0 < 3) return;
  const int xs[2] = {x0, x1}, ys[2] = {y0, y1};
  for (int i = 0; i < 2; ++i) {
    for (int j = 0; j < 2; ++j) {
      int x = xs[i], y = ys[j], ox = i ? x + 1 : x - 1, oy = j ? y + 1 : y - 1;
      if (x < 0 || y < 0 || x >= kWidth || y >= kHeight || c.get(x, y) != color) continue;
      bool outX = ox < 0 || ox >= kWidth || c.get(ox, y) != color;
      bool outY = oy < 0 || oy >= kHeight || c.get(x, oy) != color;
      if (outX && outY) c.pixels()[y * kWidth + x] = kBlack;
    }
  }
}

// A round-capped stroke of radius r along the parabola from (x - hw, y)
// through (x, y + bend) to (x + hw, y), in sub-pixels: a "^" eye when bend
// is negative, the mouth's line when it is positive or zero. `band` gives
// its top and bottom at column sx: the union of discs of radius r along the
// curve, sampled across their reach.
struct Stroke {
  static constexpr int kSamples = 12;
  int x, y, hw, bend, r;

  int curveY(int cx) const {
    if (hw <= 0) return y;
    int64_t u = int64_t(cx - x) * 1024 / hw;
    return y + int(int64_t(bend) * (1024 - u * u / 1024) / 1024);
  }

  bool band(int sx, int& top, int& bottom) const {
    int lo = sx - r > x - hw ? sx - r : x - hw, hi = sx + r < x + hw ? sx + r : x + hw;
    if (lo > hi) return false;
    bool any = false;
    for (int i = 0; i <= kSamples; ++i) {
      int cx = lo + (hi - lo) * i / kSamples, d = sx - cx;
      if (d <= -r || d >= r) continue;
      int h = int(isqrt(uint64_t(int64_t(r) * r - int64_t(d) * d)));
      int cy = curveY(cx);
      if (!any || cy - h < top) top = cy - h;
      if (!any || cy + h > bottom) bottom = cy + h;
      any = true;
    }
    return any;
  }
};

// Fills every block whose centre is inside the stroke.
void strokeBlocks(Canvas& c, const Stroke& st, uint8_t color) {
  for (int bx = blockOf(st.x - st.hw - st.r); bx <= blockOf(st.x + st.hw + st.r); ++bx) {
    int top, bottom;
    if (!st.band(centreOf(bx), top, bottom)) continue;
    for (int by = blockOf(top); by <= blockOf(bottom); ++by) {
      int cy = centreOf(by);
      if (cy >= top && cy <= bottom) block(c, bx, by, color);
    }
  }
}

struct Eye {
  int x, y;              // centre, sub-pixels (unsnapped, for what sits beside the eye)
  int bx, by, wb, hb;    // centre block and size in blocks (odd)
  int lidY, lidM;        // upper lid line through (x, lidY) with slope lidM/1000, sub-pixels
  bool arch;             // happy: drawn as a "^" stroke instead
  Stroke archStroke;
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
  int h = len(kEyeH) * (1000 - sq * 6 / 10) / 1000 * size / 1000 * clampi(p.open, 0, 1000) / 1000;
  int happy = clampi(p.lidBot, 0, 1000);
  int bar = len(kLidLine) * size / 1000;
  if (happy < kArchFrom && h > bar) h = h - (h - bar) * happy / kArchFrom;  // squeezing
  e.x = cx + (right ? len(kEyeGap) : -len(kEyeGap)) + len(kLookX) * lookX / 1000;
  e.y = cy + len(kLookY) * lookY / 1000;
  e.bx = blockOf(e.x), e.by = blockOf(e.y);
  e.wb = oddBlocks(w, 3), e.hb = oddBlocks(h, 1);

  int lid = p.lidTop + (right ? (p.wink > 0 ? p.wink : 0) : (p.wink < 0 ? -p.wink : 0));
  lid = clampi(lid, 0, 1000);
  int top = (e.by - e.hb / 2) * kB, hs = e.hb * kB;
  e.lidY = top + hs * lid / 1000;
  int m = clampi(p.lidTilt, -1000, 1000) * 7 / 10;
  e.lidM = right ? -m : m;

  e.arch = happy >= kArchFrom;
  if (e.arch) {
    int rise = clampi((happy - kArchFrom) * 1000 / (kArchFull - kArchFrom), 0, 1000);
    int r = len(kArchThick) * size / 1000 / 2;
    int wx = e.wb * kB / 2;
    e.archStroke = Stroke{centreOf(e.bx), centreOf(e.by), wx - r, -len(kArchRise) * size / 1000 * rise / 1000, r};
  }
  return e;
}

// An open eye is four panes around a one-block cross; the upper lid cuts
// whole rows of blocks from the top of each half. Too thin for panes, it's one
// solid bar. Each pane, or the bar, gets softened corners.
void drawEye(Canvas& c, const Eye& e, uint8_t color) {
  if (e.arch) return strokeBlocks(c, e.archStroke, color);
  const int x0 = e.bx - e.wb / 2, x1 = e.bx + e.wb / 2, y0 = e.by - e.hb / 2, y1 = e.by + e.hb / 2;
  const bool panes = e.hb >= 2 * kPaneMin + 1 && e.wb >= 2 * kPaneMin + 1;
  for (int bx = x0; bx <= x1; ++bx) {
    if (panes && bx == e.bx) continue;
    // Each half is cut flat where the lid crosses its middle, so a tilted
    // lid steps once between the panes instead of jagging every column.
    int half = bx < e.bx ? (x0 + e.bx - 1) / 2 : bx > e.bx ? (e.bx + 1 + x1 + 1) / 2 : e.bx;
    int lidAt = e.lidY + int(int64_t(e.lidM) * (centreOf(half) - e.x) / 1000);
    for (int by = y0; by <= y1; ++by) {
      if (panes && by == e.by) continue;
      if (centreOf(by) < lidAt) continue;
      block(c, bx, by, color);
    }
  }
  auto soften = [&](int bx0, int by0, int bx1, int by1) {
    roundCorners(c, bx0 * kBlock, by0 * kBlock, (bx1 + 1) * kBlock - 1, (by1 + 1) * kBlock - 1, color);
  };
  if (!panes) return soften(x0, y0, x1, y1);
  soften(x0, y0, e.bx - 1, e.by - 1);
  soften(e.bx + 1, y0, x1, e.by - 1);
  soften(x0, e.by + 1, e.bx - 1, y1);
  soften(e.bx + 1, e.by + 1, x1, y1);
}

// The mouth: a flat round-ended bar that bends into a "u" smile (a little
// wider) or a frown. Open, it drops into a D with a dark inside, a block in
// from the edge.
void drawMouth(Canvas& c, const Pose& p, int cx, int cy, int s, uint8_t color) {
  auto len = [s](int pixels) { return px(pixels) * s / 1000; };
  int lookX = clampi(p.lookX, -1000, 1000), lookY = clampi(p.lookY, -1000, 1000);
  int curve = clampi(p.mouthCurve, -1000, 1000);
  int x = cx + len(p.mouthX) + len(kLookX) * lookX / 1000 * kMouthFollow / 1000;
  int y = cy + len(kMouthY) + len(kLookY) * lookY / 1000 * kMouthFollow / 1000;
  x = centreOf(blockOf(x));                   // on a block's middle, like the eyes
  y = blockOf(y + kB / 2) * kB;               // on a line between blocks: two rows thick
  int hw = len(kMouthHalfW) * clampi(p.mouthWide, 200, 2000) / 1000 * (1000 + (curve > 0 ? curve : 0) * kSmileWiden / 1000) / 1000;
  int th = len(kMouthThick) / 2;
  int bend = len(kMouthBend) * curve / 1000;
  int drop = len(kMouthDrop) * clampi(p.mouthOpen, 0, 1000) / 1000;
  // Open: the D's blocks, then the ones with all four neighbours inside
  // are its dark inside, leaving a one-block outline.
  auto inD = [&](int bx, int by) {
    int sx = centreOf(bx), u = (sx - x) * 1024 / hw;
    if (u <= -1024 || u >= 1024) return false;
    int arch = 1024 - u * u / 1024;
    int yc = y + bend * arch / 1024;
    int top = yc - th, bottom = yc + th + drop * int(isqrt(uint64_t(arch) * 1024)) / 1024;
    int cy = centreOf(by);
    return cy >= top && cy <= bottom;
  };
  if (drop < kB || hw <= 0) {
    Stroke st{x, y, hw - th, bend, th};
    strokeBlocks(c, st, color);
    int t, b;
    if (bend == 0 && st.band(x, t, b)) {
      int bx0 = blockOf(x - hw + th / 2), bx1 = blockOf(x + hw - th / 2);
      roundCorners(c, bx0 * kBlock, blockOf(t + kB / 2) * kBlock, (bx1 + 1) * kBlock - 1, blockOf(b - kB / 2) * kBlock + kBlock - 1, color);
    }
    return;
  }
  const int bx0 = blockOf(x - hw), bx1 = blockOf(x + hw);
  const int by0 = blockOf(y - th - (bend < 0 ? -bend : 0)), by1 = blockOf(y + th + drop + (bend > 0 ? bend : 0));
  for (int bx = bx0; bx <= bx1; ++bx) {
    for (int by = by0; by <= by1; ++by) {
      if (!inD(bx, by)) continue;
      bool inside = inD(bx - 1, by) && inD(bx + 1, by) && inD(bx, by - 1) && inD(bx, by + 1);
      block(c, bx, by, inside ? kHollow : color);
    }
  }
}

// The cheeks: two small pink blocks side by side under an eye, towards the
// outside, a block apart.
void drawBlush(Canvas& c, const Eye& e, int s, bool right) {
  auto len = [s](int pixels) { return px(pixels) * s / 1000; };
  auto blocks = [](int l) { return (l + kB / 2) / kB < 2 ? 2 : (l + kB / 2) / kB; };
  const uint8_t pink = inkAt(kInkBlush, kLevels);
  int cx = e.x + (right ? len(kBlushDx) : -len(kBlushDx)), cy = e.y + len(kBlushDy);
  int bw = blocks(len(kBlushW)), bh = blocks(len(kBlushH));
  int bx0 = blockOf(cx) - bw, by0 = blockOf(cy) - bh / 2;
  for (int k = 0; k < 2; ++k) {
    int sx = bx0 + k * (bw + 1);
    for (int bx = sx; bx < sx + bw; ++bx) {
      for (int by = by0; by < by0 + bh; ++by) block(c, bx, by, pink);
    }
    roundCorners(c, sx * kBlock, by0 * kBlock, (sx + bw) * kBlock - 1, (by0 + bh) * kBlock - 1, pink);
  }
}

// A small sprite of `rows`, one character per block ('X' filled), drawn
// with blocks of `b` pixels, its centre at sub-pixel (cx, cy).
void sprite(Canvas& c, const char* const* rows, int n, int cx, int cy, int b, uint8_t color) {
  int w = 0;
  while (rows[0][w]) ++w;
  int x0 = cx / kSub - w * b / 2, y0 = cy / kSub - n * b / 2;
  x0 -= x0 % b, y0 -= y0 % b;  // on the sprite's own grid
  for (int r = 0; r < n; ++r) {
    for (int i = 0; i < w; ++i) {
      if (rows[r][i] == 'X') c.fillRect(x0 + i * b, y0 + r * b, b, b, color);
    }
  }
}

// A pixel heart that pops in: small, then full size.
void drawHeart(Canvas& c, int hx, int hy, int grow) {
  static const char* const kSmall[] = {"XX.XX", "XXXXX", ".XXX.", "..X.."};
  static const char* const kFull[] = {".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."};
  const uint8_t rose = inkAt(kInkRose, kLevels);
  if (grow >= 650) sprite(c, kFull, 6, hx, hy, kBlock, rose);
  else if (grow >= 250) sprite(c, kSmall, 4, hx, hy, kBlock, rose);
}

// A pixel sweat drop.
void drawDrop(Canvas& c, int dx, int dy) {
  static const char* const kDrop[] = {"..X..", ".XXX.", "XXXXX", "XXXXX", ".XXX."};
  sprite(c, kDrop, 5, dx, dy, 2, inkAt(kInkSky, kLevels));
}

// Asleep's "zzZZ": two small z's then two big Z's climbing up and to the
// right of the right eye, appearing one at a time through the cycle.
void drawZzz(Canvas& c, int ex, int ey, int s, int phase, uint8_t color) {
  static const char* const kLittle[] = {"XXXX", "..X.", ".X..", "XXXX"};
  static const char* const kBig[] = {"XXXXX", "...X.", "..X..", ".X...", "XXXXX"};
  struct Letter {
    bool big;
    int dx, dy;  // the letter's centre, from the right eye's centre, in pixels
  };
  const Letter letters[] = {{false, 34, -24}, {false, 44, -38}, {true, 56, -58}, {true, 72, -84}};
  for (int i = 0; i < 4; ++i) {
    if (uint32_t(phase) <= kZzzStep * uint32_t(i)) break;
    const Letter& l = letters[i];
    int x = ex + px(l.dx) * s / 1000, y = ey + px(l.dy) * s / 1000;
    if (l.big) sprite(c, kBig, 5, x, y, kBlock, color);
    else sprite(c, kLittle, 4, x, y, 2, color);
  }
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
  o.raise = int16_t(lerp(a.raise, b.raise, t));
  o.heart = int16_t(lerp(a.heart, b.heart, t));
  o.sweat = int16_t(lerp(a.sweat, b.sweat, t));
  o.zzz = int16_t(lerp(a.zzz, b.zzz, t));
  return o;
}

bool operator==(const Pose& a, const Pose& b) {
  return a.open == b.open && a.lookX == b.lookX && a.lookY == b.lookY && a.eyeSize == b.eyeSize &&
         a.lidTop == b.lidTop && a.lidTilt == b.lidTilt && a.lidBot == b.lidBot && a.wink == b.wink &&
         a.squash == b.squash && a.mouthCurve == b.mouthCurve && a.mouthOpen == b.mouthOpen &&
         a.mouthWide == b.mouthWide && a.mouthX == b.mouthX && a.dx == b.dx && a.dy == b.dy &&
         a.size == b.size && a.glow == b.glow && a.raise == b.raise &&
         a.heart == b.heart && a.sweat == b.sweat && a.zzz == b.zzz;
}

int eyeInk(const Pose& p) {
  int step = (clampi(p.glow, 0, 1000) * 4 + 500) / 1000;
  return step ? kInkGlow1 + step - 1 : kInkEye;
}

void drawFace(Canvas& c, const Pose& p, int cx, int cy, int scale) {
  int s = scale * clampi(p.size, 500, 1500) / 1000;
  int x = px(cx) + px(p.dx) * scale / 1000, y = px(cy) + px(p.dy) * scale / 1000;
  const uint8_t ink = inkAt(eyeInk(p), kLevels);
  Eye left = makeEye(p, x, y, s, false), right = makeEye(p, x, y, s, true);
  drawBlush(c, left, s, false);
  drawBlush(c, right, s, true);
  drawEye(c, left, ink);
  drawEye(c, right, ink);
  drawMouth(c, p, x, y, s, ink);
  auto len = [s](int pixels) { return px(pixels) * s / 1000; };
  int heart = clampi(p.heart, 0, 1000);
  if (heart > 0) drawHeart(c, right.x + len(kHeartDx), right.y + len(kHeartDy), heart);
  if (p.sweat > 0) {
    int slide = len(kSweatSlide) * clampi(p.sweat, 0, 1000) / 1000;
    drawDrop(c, right.x + len(kSweatDx), right.y + len(kSweatDy) + slide);
  }
  if (p.zzz > 0) drawZzz(c, right.x, right.y, s, clampi(p.zzz, 0, 1000), ink);
}

}  // namespace render
