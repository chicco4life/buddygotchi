#include "render/face.h"

#include "render/palette.h"
#include "render/raster.h"

namespace render {

namespace {

// The face is pixel art (plan/UX.md §2): every part is built from square
// blocks of kBlock screen pixels on one grid, with no anti-aliasing. The
// geometry below is in screen pixels at full size. The face's origin snaps
// to the grid once and every part sits a whole number of blocks from it, so
// the face moves a block at a time, as one sprite: no part lags a block
// behind the others mid-motion.
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
constexpr int kPaneRows = 2;             // blocks: a lid or squint leaving fewer rows of a pane takes it all
constexpr int kMouthFollow = 450;        // permille of the eyes' move the mouth follows
// The mouth: a flat bar as wide as an eye, two blocks thick, level with the
// cheeks. Past kMouthCurveAt it's a small smile, and past
// kMouthOpenAt a small "o" (or a "D" when smiling too). Kept small: a wide
// grin on boxy eyes reads as forced.
constexpr int kMouthY = 45;
constexpr int kMouthHalfW = 20, kMouthThick = 6;
constexpr int kMouthCurveAt = 300, kMouthOpenAt = 300;
// Happy eyes (lidBot) stay boxy: the bottom rises, as if the cheeks pushed
// it up, by kSquint of the eye at full happiness, and the cheeks rise
// kBlushLift with it.
constexpr int kSquint = 350, kBlushLift = 6;
// The cheeks: two pink blocks side by side under each eye, towards the
// outside, level with the mouth.
constexpr int kBlushDx = 21, kBlushDy = 39, kBlushW = 12, kBlushH = 9;
// Around the right eye's centre: where the heart, the sweat drop and the
// "zzZZ" go.
constexpr int kHeartDx = 36, kHeartDy = -30;
constexpr int kSweatDx = 34, kSweatDy = -21, kSweatSlide = 12;
constexpr int kZzzDx = 27, kZzzDy = -15;  // the first letter's top left
constexpr uint32_t kZzzStep = 220;        // permille of the cycle between letters
constexpr int kHeartSmallAt = 250, kHeartFullAt = 650;  // heart: it pops in small, then full size

// The middle of the face (from the eye tops to the mouth) lies kFaceDrop
// below the eye centres; screens.cpp centres the face on that.
static_assert(kFaceDrop == (kMouthY + kMouthThick / 2 - kEyeH / 2) / 2, "face.h kFaceDrop follows the geometry");

int lerp(int a, int b, int t) { return a + (b - a) * t / 1024; }
int clampi(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

constexpr int kB = px(kBlock);  // a block, in sub-pixels
// The block holding sub-pixel v (floor division).
int blockOf(int v) { return v >= 0 ? v / kB : -((-v + kB - 1) / kB); }
// A distance in sub-pixels as the nearest whole number of blocks, halves
// away from zero, so a part and its mirror image round alike.
int blocks(int v) { return v >= 0 ? (v + kB / 2) / kB : -((-v + kB / 2) / kB); }
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

// Where the face is drawn: its origin block (the middle between the eyes,
// on the eye line) and its scale in permille.
struct Frame {
  int ox, oy, s;
  int len(int pixels) const { return px(pixels) * s / 1000; }  // sub-pixels
  int off(int pixels) const { return blocks(len(pixels)); }    // whole blocks
};

struct Eye {
  int bx, by, wb, hb;    // centre block and size in blocks (odd)
  int lidY;              // rows above this are under the upper lid, sub-pixels
  int botY;              // happy: rows below this are cut (the squint), sub-pixels
  int happy;             // permille, for the cheeks
};

Eye makeEye(const Pose& p, const Frame& f, bool right) {
  auto len = [&f](int pixels) { return f.len(pixels); };
  Eye e{};
  int lookX = clampi(p.lookX, -1000, 1000), lookY = clampi(p.lookY, -1000, 1000);
  int size = clampi(p.eyeSize, 800, 1250);
  int sq = clampi(p.squash, -600, 600);
  int w = len(kEyeW) * (1000 + sq * 4 / 10) / 1000 * size / 1000;
  int h = len(kEyeH) * (1000 - sq * 6 / 10) / 1000 * size / 1000 * clampi(p.open, 0, 1000) / 1000;
  int happy = clampi(p.lidBot, 0, 1000);
  // Both eyes round the look alike, so they move together.
  e.bx = f.ox + (right ? f.off(kEyeGap) : -f.off(kEyeGap)) + blocks(len(kLookX) * lookX / 1000);
  e.by = f.oy + blocks(len(kLookY) * lookY / 1000);
  // Perspective: the eye on the side being looked towards is nearer. Both
  // eyes round from the same size, and the turn adds to one and takes from
  // the other the same whole pair of blocks, so a small look (working's)
  // never leaves them lopsided.
  const bool near = right == (lookX > 0);
  auto turned = [&](int n, int least) {
    int k = int((int64_t(n) * kTurn * (lookX < 0 ? -lookX : lookX) + 1000000) / 2000000);
    n += near ? 2 * k : -2 * k;
    return n < least ? least : n;
  };
  e.wb = turned(oddBlocks(w, 3), 3), e.hb = turned(oddBlocks(h, 1), 1);

  int lid = p.lidTop + (right ? (p.wink > 0 ? p.wink : 0) : (p.wink < 0 ? -p.wink : 0));
  lid = clampi(lid, 0, 1000);
  int top = (e.by - e.hb / 2) * kB, hs = e.hb * kB;
  e.lidY = top + hs * lid / 1000;

  e.happy = happy;
  e.botY = top + hs - int(int64_t(hs) * kSquint / 1000 * happy / 1000);
  return e;
}

// An open eye is four panes around a one-block cross; the upper lid cuts
// whole rows of blocks off the top, and the squint off the bottom. A pane
// they leave thinner than kPaneRows goes, so no sliver of it floats like a
// brow. Too thin for panes, the eye is one solid bar. Each pane, or the
// bar, gets softened corners where it's drawn.
void drawEye(Canvas& c, const Eye& e, uint8_t color) {
  const int x0 = e.bx - e.wb / 2, x1 = e.bx + e.wb / 2, y0 = e.by - e.hb / 2, y1 = e.by + e.hb / 2;
  const bool panes = e.hb >= 2 * kPaneMin + 1 && e.wb >= 2 * kPaneMin + 1;
  // Fills columns bx0..bx1 of rows by0..by1, less what the lids take.
  auto part = [&](int bx0, int by0, int bx1, int by1, int least) {
    while (by0 <= by1 && centreOf(by0) < e.lidY) ++by0;
    while (by1 >= by0 && centreOf(by1) > e.botY) --by1;
    if (by1 - by0 + 1 < least) return;
    for (int by = by0; by <= by1; ++by) {
      for (int bx = bx0; bx <= bx1; ++bx) block(c, bx, by, color);
    }
    roundCorners(c, bx0 * kBlock, by0 * kBlock, (bx1 + 1) * kBlock - 1, (by1 + 1) * kBlock - 1, color);
  };
  if (!panes) return part(x0, y0, x1, y1, 1);
  part(x0, y0, e.bx - 1, e.by - 1, kPaneRows);
  part(e.bx + 1, y0, x1, e.by - 1, kPaneRows);
  part(x0, e.by + 1, e.bx - 1, y1, kPaneRows);
  part(e.bx + 1, e.by + 1, x1, y1, kPaneRows);
}

// A small sprite of `rows`, one character per block ('X' filled), drawn
// with blocks of `b` pixels from the top left at pixel (x0, y0).
void sprite(Canvas& c, const char* const* rows, int n, int x0, int y0, int b, uint8_t color) {
  for (int r = 0; r < n; ++r) {
    for (int i = 0; rows[r][i]; ++i) {
      if (rows[r][i] == 'X') c.fillRect(x0 + i * b, y0 + r * b, b, b, color);
    }
  }
}
int spriteW(const char* const* rows) {
  int w = 0;
  while (rows[0][w]) ++w;
  return w;
}
// A sprite on the face's grid, centred on block (bx, by) (for an even size,
// the middle falls on that block's top or left edge).
void spriteAt(Canvas& c, const char* const* rows, int n, int bx, int by, uint8_t color) {
  sprite(c, rows, n, (bx - spriteW(rows) / 2) * kBlock, (by - n / 2) * kBlock, kBlock, color);
}

// The mouth, as pixel shapes rather than traced curves (UX.md §2): a flat
// bar at rest, a small "u" smile, a small "o" while talking, and a small
// filled cup when it's both happy and open.
void drawMouth(Canvas& c, const Pose& p, const Frame& f, uint8_t color) {
  static const char* const kSmile[] = {"X.....X", ".XXXXX."};
  static const char* const kO[] = {".XXX.", "X...X", ".XXX."};
  static const char* const kD[] = {"X...X", "XXXXX", ".XXX."};
  int lookX = clampi(p.lookX, -1000, 1000), lookY = clampi(p.lookY, -1000, 1000);
  int curve = clampi(p.mouthCurve, 0, 1000), open = clampi(p.mouthOpen, 0, 1000);
  // The middle column, and the bottom row every mouth shape sits on.
  int mx = f.ox + blocks(f.len(kLookX) * lookX / 1000 * kMouthFollow / 1000);
  int my = f.oy + f.off(kMouthY) + blocks(f.len(kLookY) * lookY / 1000 * kMouthFollow / 1000);
  auto shape = [&](const char* const* rows, int n) {
    sprite(c, rows, n, (mx - spriteW(rows) / 2) * kBlock, (my + 1 - n) * kBlock, kBlock, color);
  };
  if (open >= kMouthOpenAt) return shape(curve >= kMouthCurveAt ? kD : kO, 3);
  if (curve >= kMouthCurveAt) return shape(kSmile, 2);
  // The bar: two blocks thick, as wide as mouthWide makes it (an odd
  // number of blocks, so it centres).
  int hw = f.len(kMouthHalfW) * clampi(p.mouthWide, 200, 2000) / 1000;
  int wb = oddBlocks(2 * hw, 3);
  for (int b = mx - wb / 2; b <= mx + wb / 2; ++b) {
    block(c, b, my - 1, color);
    block(c, b, my, color);
  }
  roundCorners(c, (mx - wb / 2) * kBlock, (my - 1) * kBlock, (mx + wb / 2 + 1) * kBlock - 1, (my + 1) * kBlock - 1, color);
}

// The cheeks: two small pink blocks side by side under an eye, towards the
// outside, a block apart.
void drawBlush(Canvas& c, const Eye& e, const Frame& f, bool right) {
  auto size = [&f](int pixels) { return f.off(pixels) < 2 ? 2 : f.off(pixels); };
  const uint8_t pink = inkAt(kInkBlush, kLevels);
  int cx = e.bx + (right ? f.off(kBlushDx) : -f.off(kBlushDx));
  int cy = e.by + f.off(kBlushDy) - blocks(f.len(kBlushLift) * e.happy / 1000);
  int bw = size(kBlushW), bh = size(kBlushH);
  int bx0 = cx - bw, by0 = cy - bh / 2;
  for (int k = 0; k < 2; ++k) {
    int sx = bx0 + k * (bw + 1);
    for (int bx = sx; bx < sx + bw; ++bx) {
      for (int by = by0; by < by0 + bh; ++by) block(c, bx, by, pink);
    }
    roundCorners(c, sx * kBlock, by0 * kBlock, (sx + bw) * kBlock - 1, (by0 + bh) * kBlock - 1, pink);
  }
}

// A pixel heart that pops in: small, then full size. (hx, hy) is its
// centre block.
void drawHeart(Canvas& c, int hx, int hy, int grow) {
  static const char* const kSmall[] = {"XX.XX", "XXXXX", ".XXX.", "..X.."};
  static const char* const kFull[] = {".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."};
  const uint8_t rose = inkAt(kInkRose, kLevels);
  if (grow >= kHeartFullAt) spriteAt(c, kFull, 6, hx, hy, rose);
  else if (grow >= kHeartSmallAt) spriteAt(c, kSmall, 4, hx, hy, rose);
}

// A pixel sweat drop, centred on block (bx, by): it tapers from a point
// to a round bottom, with a pixel softened off every block corner on its
// outline (a flat-shouldered drop reads as a bottle).
void drawDrop(Canvas& c, int bx, int by) {
  constexpr int kW = 5, kH = 5;
  static const char* const kDrop[kH] = {"..X..", ".XXX.", "XXXXX", "XXXXX", ".XXX."};
  spriteAt(c, kDrop, kH, bx, by, inkAt(kInkSky, kLevels));
  auto on = [](int r, int i) { return r >= 0 && r < kH && i >= 0 && i < kW && kDrop[r][i] == 'X'; };
  const int x0 = (bx - kW / 2) * kBlock, y0 = (by - kH / 2) * kBlock;
  for (int r = 0; r < kH; ++r) {
    for (int i = 0; i < kW; ++i) {
      if (!on(r, i)) continue;
      for (int k = 0; k < 4; ++k) {  // each corner: left or right, top or bottom
        int sx = k & 1 ? 1 : -1, sy = k & 2 ? 1 : -1;
        if (on(r, i + sx) || on(r + sy, i)) continue;
        c.fillRect(x0 + i * kBlock + (sx > 0 ? kBlock - 1 : 0), y0 + r * kBlock + (sy > 0 ? kBlock - 1 : 0), 1, 1, kBlack);
      }
    }
  }
}

// Asleep's "zzZZ": two small z's side by side, then two big Z's side by
// side above them, up and to the right of the right eye, appearing one at a
// time through the cycle. The letters don't scale with the face, so neither
// does their layout: only where the first one sits does.
void drawZzz(Canvas& c, const Eye& e, const Frame& f, int phase, uint8_t color) {
  // Bold diagonals: a one-block one reads as an "I" this small.
  static const char* const kLittle[] = {"XXXX", "..XX", "XX..", "XXXX"};
  static const char* const kBig[] = {"XXXXX", "...XX", "..XX.", ".XX..", "XXXXX"};
  struct Letter {
    bool big;
    int bx, by;  // top left, in blocks from the first letter's
  };
  const Letter letters[] = {{false, 0, 0}, {false, 5, -2}, {true, 6, -8}, {true, 12, -10}};
  const int ax = e.bx + f.off(kZzzDx), ay = e.by + f.off(kZzzDy);
  for (int i = 0; i < 4; ++i) {
    if (uint32_t(phase) <= kZzzStep * uint32_t(i)) break;
    const Letter& l = letters[i];
    int x = (ax + l.bx) * kBlock, y = (ay + l.by) * kBlock;
    if (l.big) sprite(c, kBig, 5, x, y, kBlock, color);
    else sprite(c, kLittle, 4, x, y, kBlock, color);
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
  o.lidBot = int16_t(lerp(a.lidBot, b.lidBot, t));
  o.wink = int16_t(lerp(a.wink, b.wink, t));
  o.squash = int16_t(lerp(a.squash, b.squash, t));
  o.mouthCurve = int16_t(lerp(a.mouthCurve, b.mouthCurve, t));
  o.mouthOpen = int16_t(lerp(a.mouthOpen, b.mouthOpen, t));
  o.mouthWide = int16_t(lerp(a.mouthWide, b.mouthWide, t));
  o.dx = int16_t(lerp(a.dx, b.dx, t));
  o.dy = int16_t(lerp(a.dy, b.dy, t));
  o.size = int16_t(lerp(a.size, b.size, t));
  o.raise = int16_t(lerp(a.raise, b.raise, t));
  o.heart = int16_t(lerp(a.heart, b.heart, t));
  o.sweat = int16_t(lerp(a.sweat, b.sweat, t));
  o.zzz = int16_t(lerp(a.zzz, b.zzz, t));
  return o;
}

bool operator==(const Pose& a, const Pose& b) {
  return a.open == b.open && a.lookX == b.lookX && a.lookY == b.lookY && a.eyeSize == b.eyeSize &&
         a.lidTop == b.lidTop && a.lidBot == b.lidBot && a.wink == b.wink && a.squash == b.squash &&
         a.mouthCurve == b.mouthCurve && a.mouthOpen == b.mouthOpen && a.mouthWide == b.mouthWide &&
         a.dx == b.dx && a.dy == b.dy && a.size == b.size && a.raise == b.raise &&
         a.heart == b.heart && a.sweat == b.sweat && a.zzz == b.zzz;
}

void drawFace(Canvas& c, const Pose& p, int cx, int cy, int scale) {
  // The origin: the centre snapped to the grid, then moved by whole blocks.
  Frame f;
  f.s = scale * clampi(p.size, 500, 1500) / 1000;
  f.ox = blockOf(px(cx)) + blocks(px(p.dx) * scale / 1000);
  f.oy = blockOf(px(cy)) + blocks(px(p.dy) * scale / 1000);
  const uint8_t ink = inkAt(kInkEye, kLevels);
  Eye left = makeEye(p, f, false), right = makeEye(p, f, true);
  drawBlush(c, left, f, false);
  drawBlush(c, right, f, true);
  drawEye(c, left, ink);
  drawEye(c, right, ink);
  drawMouth(c, p, f, ink);
  int heart = clampi(p.heart, 0, 1000);
  if (heart > 0) drawHeart(c, right.bx + f.off(kHeartDx), right.by + f.off(kHeartDy), heart);
  // The drop sits where the heart does, so it goes once the heart shows
  // (working into a cheer).
  if (p.sweat > 0 && heart < kHeartSmallAt) {
    int slide = blocks(f.len(kSweatSlide) * clampi(p.sweat, 0, 1000) / 1000);
    drawDrop(c, right.bx + f.off(kSweatDx), right.by + f.off(kSweatDy) + slide);
  }
  if (p.zzz > 0) drawZzz(c, right, f, clampi(p.zzz, 0, 1000), ink);
}

}  // namespace render
