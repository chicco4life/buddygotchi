// The face renderer: integer maths, the rasterizer, poses, blends, fonts
// and the palette ramps (plan/PLAN.md F2, L0).
#include <unity.h>

#include <cstring>
#include <vector>

#include "render/anim.h"
#include "render/face.h"
#include "render/font.h"
#include "render/palette.h"
#include "render/raster.h"
#include "render/screens.h"

using namespace render;

void setUp() {}
void tearDown() {}

namespace {
// Where screens.cpp puts the face alone on the 320×240 screen: centred in
// the space above the strip, the eyes kFaceDrop above the middle.
constexpr int kFaceCy = kStripTop / 2 - kFaceDrop;
constexpr int kFaceCx = kWidth / 2;
constexpr int kEyeRows = kFaceCy + 36;  // rows above this hold only the eyes and cheeks (the mouth hangs 45 below)

struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  int count(uint8_t v) const {
    int n = 0;
    for (uint8_t p : px) n += p == v;
    return n;
  }
};

Buf face(const Pose& p) {
  Buf b;
  drawFace(b.c, p, kFaceCx, kFaceCy, 1000);
  return b;
}

// One eye, from the rows above the mouth: the left eye is in the left half.
// The heart, the sweat drop and the cheeks aren't eye.
bool notEye(int v) {
  for (int ink : {int(kInkRose), int(kInkSky), int(kInkBlush)}) {
    if (v >= inkAt(ink, 1) && v <= inkAt(ink, kLevels)) return true;
  }
  return false;
}
struct EyeBox {
  int n = 0, x0 = kWidth, x1 = -1, y0 = kHeight, y1 = -1;
  int cx() const { return (x0 + x1) / 2; }
  int w() const { return x1 - x0 + 1; }
  int h() const { return y1 - y0 + 1; }
};
EyeBox eyeBox(const Buf& b, bool right) {
  EyeBox e;
  for (int y = 0; y < kEyeRows; ++y) {
    for (int x = right ? kWidth / 2 : 0; x < (right ? kWidth : kWidth / 2); ++x) {
      if (b.c.get(x, y) == kBlack || notEye(b.c.get(x, y))) continue;
      ++e.n;
      if (x < e.x0) e.x0 = x;
      if (x > e.x1) e.x1 = x;
      if (y < e.y0) e.y0 = y;
      if (y > e.y1) e.y1 = y;
    }
  }
  return e;
}

// The face is pixel art (UX.md §2): every lit pixel of an eye is its ink at
// full strength, with no anti-aliased edge.
bool eyeIsCrisp(const Buf& b, bool right, int ink) {
  for (int y = 0; y < kEyeRows; ++y) {
    for (int x = right ? kWidth / 2 : 0; x < (right ? kWidth : kWidth / 2); ++x) {
      int v = b.c.get(x, y);
      if (v != kBlack && !notEye(v) && v != inkAt(ink, kLevels)) return false;
    }
  }
  return true;
}

// The top row of an eye's lit pixels in column x, or -1.
int topAt(const Buf& b, int x) {
  for (int y = 0; y < kEyeRows; ++y) {
    int v = b.c.get(x, y);
    if (v != kBlack && !notEye(v)) return y;
  }
  return -1;
}
}  // namespace

static void test_isqrt_is_exact() {
  for (uint64_t v : {0ull, 1ull, 2ull, 3ull, 4ull, 99ull, 100ull, 4294967295ull, 4294967296ull, 1000000000000ull}) {
    uint64_t r = isqrt(v);
    TEST_ASSERT_TRUE(r * r <= v);
    TEST_ASSERT_TRUE((r + 1) * (r + 1) > v);
  }
}

static void test_isin_hits_the_quadrants() {
  TEST_ASSERT_EQUAL_INT(0, isin(0));
  TEST_ASSERT_EQUAL_INT(1024, isin(256));
  TEST_ASSERT_EQUAL_INT(0, isin(512));
  TEST_ASSERT_EQUAL_INT(-1024, isin(768));
  TEST_ASSERT_EQUAL_INT(724, isin(128));  // sin 45°
  TEST_ASSERT_EQUAL_INT(1024, icos(0));
}

static void test_ease_is_monotonic_from_0_to_1024() {
  TEST_ASSERT_EQUAL_INT(0, ease(0, 150));
  TEST_ASSERT_EQUAL_INT(512, ease(75, 150));
  TEST_ASSERT_EQUAL_INT(1024, ease(150, 150));
  int last = 0;
  for (int t = 0; t <= 150; ++t) {
    TEST_ASSERT_TRUE(ease(t, 150) >= last);
    last = ease(t, 150);
  }
}

static void test_spans_cut_and_intersect() {
  Spans s;
  s.add(0, 100);
  s.cut(40, 60);
  TEST_ASSERT_EQUAL_INT(2, s.n);
  TEST_ASSERT_EQUAL_INT(40, s.s[0].b);
  TEST_ASSERT_EQUAL_INT(60, s.s[1].a);
  Spans o;
  o.add(30, 70);
  s.intersect(o);
  TEST_ASSERT_EQUAL_INT(2, s.n);
  TEST_ASSERT_EQUAL_INT(30, s.s[0].a);
  TEST_ASSERT_EQUAL_INT(70, s.s[1].b);
}

static void test_fill_shape_antialiases_only_the_edges() {
  Buf b;
  // A rectangle from x = 10.5 to 20 px, rows 5..10: column 10 is half covered.
  fillShape(5, 10, [](int sy) {
    Spans s;
    s.add(px(10) + 8, px(20));
    (void)sy;
    return s;
  }, [&](int x, int y, int level) { b.px[y * kWidth + x] = uint8_t(level); });
  TEST_ASSERT_EQUAL_INT(4, b.c.get(10, 7));
  TEST_ASSERT_EQUAL_INT(8, b.c.get(11, 7));
  TEST_ASSERT_EQUAL_INT(8, b.c.get(19, 7));
  TEST_ASSERT_EQUAL_INT(0, b.c.get(20, 7));
  TEST_ASSERT_EQUAL_INT(0, b.c.get(15, 10));
}

static void test_palette_ramps_run_from_black_to_the_ink() {
  TEST_ASSERT_EQUAL_HEX16(rgb565(kEyeRgb), paletteAt(inkAt(kInkEye, kLevels)));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kOatRgb), paletteAt(inkAt(kInkText, kLevels)));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kRoseRgb), paletteAt(inkAt(kInkRose, kLevels)));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kAmberRgb), paletteAt(inkAt(kInkAmber, kLevels)));
  TEST_ASSERT_EQUAL_INT(kBlack, inkAt(kInkEye, 0));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kHollowRgb), paletteAt(hollowAt(kInkEye, kLevels)));
  TEST_ASSERT_EQUAL_INT(inkAt(kInkGlow4, kLevels), hollowAt(kInkGlow4, 0));
  TEST_ASSERT_TRUE(kPaletteUsed <= 256);
  TEST_ASSERT_EQUAL_HEX16(rgb565(255, 0, 0), paletteAt(kRed));  // the bring-up pattern's colours stay
}

static void test_neutral_face_is_symmetric() {
  Buf b = face(Pose{});
  TEST_ASSERT_TRUE(b.count(inkAt(kInkEye, kLevels)) > 2000);
  // The face is its own mirror image about the middle of its middle block
  // (x = 160, the middle of the block from 159 to 161).
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 1; x < kWidth / 2; ++x) TEST_ASSERT_EQUAL_INT(b.c.get(x, y), b.c.get(320 - x, y));
  }
  // The eyes are about 45% of the screen apart (plan/UX.md §2).
  int apart = eyeBox(b, true).cx() - eyeBox(b, false).cx();
  TEST_ASSERT_INT_WITHIN(6, kWidth * 45 / 100, apart);
  // Pink cheeks sit under each eye, towards the outside.
  int left = 0, right = 0;
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      if (b.c.get(x, y) != inkAt(kInkBlush, kLevels)) continue;
      (x < kWidth / 2 ? left : right)++;
      TEST_ASSERT_TRUE(y > eyeBox(b, x >= kWidth / 2).y1);
    }
  }
  TEST_ASSERT_TRUE(left > 100);
  TEST_ASSERT_EQUAL_INT(left, right);
}

static void test_eyes_are_four_crisp_panes() {
  Pose looks[8];
  looks[1].lookX = 1000;
  looks[2].lookX = -700, looks[2].lookY = -800;
  looks[3].eyeSize = 1250;
  looks[4].lidTop = 400, looks[4].lidTilt = 600;
  looks[5].lidTop = 150, looks[5].lidTilt = -500, looks[5].dy = -7, looks[5].squash = -120;
  looks[6] = animPose(Anim::kWiggle, 150);
  looks[7] = animPose(Anim::kListening, 0);
  for (Pose p : looks) {
    p.mouthOpen = 0;  // nothing dark anywhere: an open mouth is the only hollow
    p.dx = 0, p.dy = 0;
    Buf b = face(p);
    TEST_ASSERT_EQUAL_INT(0, b.count(kHollow));
    TEST_ASSERT_TRUE(eyeIsCrisp(b, false, eyeInk(p)));
    TEST_ASSERT_TRUE(eyeIsCrisp(b, true, eyeInk(p)));
  }
  // Open, an eye is four panes split by a one-block cross: the middle
  // column and row are dark, the middle of each pane is lit.
  Buf b = face(Pose{});
  const int ink = inkAt(kInkEye, kLevels);
  for (bool right : {false, true}) {
    EyeBox e = eyeBox(b, right);
    int mx = e.x0 + e.w() / 2, my = e.y0 + e.h() / 2;
    TEST_ASSERT_TRUE(e.w() >= 36 && e.w() <= 42 && e.h() >= 36 && e.h() <= 42);  // 13 blocks of 3 px
    TEST_ASSERT_EQUAL_INT(kBlack, b.c.get(mx, my - 8));
    TEST_ASSERT_EQUAL_INT(kBlack, b.c.get(mx - 8, my));
    for (int qx : {e.x0 + e.w() / 4, e.x1 - e.w() / 4}) {
      for (int qy : {e.y0 + e.h() / 4, e.y1 - e.h() / 4}) TEST_ASSERT_EQUAL_INT(ink, b.c.get(qx, qy));
    }
    // Each pane's outer corners are softened by a pixel.
    TEST_ASSERT_EQUAL_INT(kBlack, b.c.get(e.x0, e.y0));
    TEST_ASSERT_EQUAL_INT(ink, b.c.get(e.x0 + 1, e.y0));
    TEST_ASSERT_EQUAL_INT(ink, b.c.get(e.x0, e.y0 + 1));
  }
}

static void test_a_look_moves_the_whole_eye_with_perspective() {
  Buf n = face(Pose{});
  EyeBox nl = eyeBox(n, false), nr = eyeBox(n, true);
  TEST_ASSERT_EQUAL_INT(nl.n, nr.n);
  Pose p;
  p.lookX = 1000;
  Buf b = face(p);
  EyeBox l = eyeBox(b, false), r = eyeBox(b, true);
  TEST_ASSERT_TRUE(l.cx() - nl.cx() >= 20);  // both eyes move right, far more than a pupil did
  TEST_ASSERT_TRUE(r.cx() - nr.cx() >= 20);
  TEST_ASSERT_TRUE(r.n * 100 >= l.n * 125);  // the near eye is bigger, the far one smaller
  TEST_ASSERT_TRUE(r.n > nr.n && l.n < nl.n);
  p.lookX = -1000;
  Buf m = face(p);
  TEST_ASSERT_TRUE(eyeBox(m, false).n * 100 >= eyeBox(m, true).n * 125);
  // Up and down move the eyes too.
  Pose up, down;
  up.lookY = -1000, down.lookY = 1000;
  TEST_ASSERT_TRUE(nl.y0 - eyeBox(face(up), false).y0 >= 12);
  TEST_ASSERT_TRUE(eyeBox(face(down), false).y0 - nl.y0 >= 12);
}

static void test_eye_size_changes_only_the_eyes() {
  Buf n = face(Pose{});
  Pose p;
  p.eyeSize = 1150;
  Buf b = face(p);
  EyeBox nl = eyeBox(n, false), l = eyeBox(b, false);
  TEST_ASSERT_TRUE(l.w() - nl.w() >= 6 && l.h() - nl.h() >= 6);
  TEST_ASSERT_INT_WITHIN(2, nl.cx(), l.cx());  // it grows about its own centre
  for (int y = kEyeRows + 2; y < kHeight; ++y) {  // the mouth doesn't change
    for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL_INT(n.c.get(x, y), b.c.get(x, y));
  }
}

static void test_lids_cut_each_half_flat() {
  // A lid takes whole rows of blocks off the top. Tilted, it cuts each half
  // of the eye flat at its own height, so the eye steps once between the
  // panes instead of jagging every column (UX.md §2).
  Pose sad, cross, flat;
  flat.lidTop = 400;
  sad.lidTop = 250, sad.lidTilt = -650;
  cross.lidTop = 450, cross.lidTilt = 450;
  struct Case {
    const char* name;
    Pose p;
  } lidded[] = {{"flat", flat},
                {"outer corners down, lifted", [] {
                   Pose p;
                   p.lidTop = 150, p.lidTilt = -500, p.dy = -7, p.squash = -120;
                   return p;
                 }()},
                {"working", lookPose(Look::kWorking, 1)},
                {"outer corners down", sad},
                {"inner corners down", cross}};
  for (const Case& c : lidded) {
    Pose q = c.p;
    q.mouthOpen = 0, q.dx = 0, q.dy = 0;
    Buf b = face(q);
    for (bool right : {false, true}) {
      EyeBox e = eyeBox(b, right);
      int mx = e.x0 + e.w() / 2;
      // Away from the softened corners, every column of a half starts on
      // the same row.
      for (int x0 : {e.x0 + 2, mx + 3}) {
        int top = topAt(b, x0);
        for (int x = x0; x < x0 + 12 && x < e.x1 - 1; ++x) TEST_ASSERT_EQUAL_INT_MESSAGE(top, topAt(b, x), c.name);
      }
    }
  }
  // Flat lids leave the two halves level; tilted ones don't.
  Buf f = face(flat), t = face(sad);
  EyeBox fe = eyeBox(f, false), te = eyeBox(t, false);
  TEST_ASSERT_EQUAL_INT(topAt(f, fe.x0 + 3), topAt(f, fe.x1 - 3));
  TEST_ASSERT_TRUE(topAt(t, te.x0 + 3) != topAt(t, te.x1 - 3));
}

static void test_a_look_up_keeps_full_panes_and_working_looks_down() {
  // With no pupils to roll, lids alone would make these the same hooded
  // eyes in two places. Working is lidded and sits low; a look up and
  // aside keeps its full top panes and sits high.
  auto rowWidth = [](const Buf& b, bool right, int y) {
    int w = 0;
    for (int x = right ? kWidth / 2 : 0; x < (right ? kWidth : kWidth / 2); ++x) w += b.c.get(x, y) != kBlack;
    return w;
  };
  Pose up;
  up.lookX = 650, up.lookY = -1000, up.dy = -6, up.squash = 100, up.mouthWide = 600, up.mouthX = 8;
  Buf n = face(Pose{}), t = face(up), w = face(lookPose(Look::kWorking, 1));
  for (bool right : {false, true}) {
    EyeBox ne = eyeBox(n, right), te = eyeBox(t, right), we = eyeBox(w, right);
    TEST_ASSERT_TRUE(ne.y0 - te.y0 >= 15);
    TEST_ASSERT_TRUE(we.y0 - ne.y0 >= 9);
    // How far down the cross is from the top: a full top pane is 5 or 6
    // blocks (the far eye is smaller), a lidded one less.
    auto crossAt = [](const Buf& b, const EyeBox& e) {
      int x = e.x0 + e.w() / 4, y = e.y0;
      while (y < kEyeRows && b.c.get(x, y) != kBlack) ++y;
      return y - e.y0;
    };
    // Looking up: all four panes (the left eye; looking up, the mouth rises
    // into the right eye's rows).
    if (!right) TEST_ASSERT_TRUE(crossAt(t, te) >= 15);
    TEST_ASSERT_TRUE(crossAt(w, we) <= 12);  // working: the lid takes the top off
    TEST_ASSERT_TRUE(rowWidth(w, right, we.y0 + 1) >= 30);  // cut straight across
  }
}

static void test_closed_eyes_are_a_line() {
  Pose p;
  p.open = 0;
  Buf b = face(p);
  EyeBox e = eyeBox(b, false);
  TEST_ASSERT_TRUE(e.h() <= 6);
  TEST_ASSERT_TRUE(e.w() >= 36);
  TEST_ASSERT_TRUE(b.count(inkAt(kInkEye, kLevels)) > 80);  // but a line is there
}

// Pixels of one ink's ramp: how many, their mean row and leftmost column.
struct InkSpot {
  int n = 0, x0 = kWidth, y0 = kHeight, y1 = -1;
  long ySum = 0;
  int meanY() const { return n ? int(ySum / n) : -1; }
};
InkSpot inkSpot(const Buf& b, int ink) {
  InkSpot s;
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      int v = b.c.get(x, y);
      if (v < inkAt(ink, 1) || v > inkAt(ink, kLevels)) continue;
      ++s.n, s.ySum += y;
      if (x < s.x0) s.x0 = x;
      if (y < s.y0) s.y0 = y;
      if (y > s.y1) s.y1 = y;
    }
  }
  return s;
}

// A happy eye stays a boxy window: its top panes are whole and the same
// place as a neutral eye's, and its bottom has risen (the squint), so the
// eye is shorter but still has a lit bottom row under the cross. Never a
// "^" arch: on boxy eyes that read as uncanny (UX.md §2).
void checkSquint(const Buf& b, const Buf& n, bool right) {
  EyeBox e = eyeBox(b, right), ne = eyeBox(n, right);
  TEST_ASSERT_EQUAL_INT(ne.y0, e.y0);
  TEST_ASSERT_TRUE(e.y1 <= ne.y1 - 6);   // at least two blocks up
  TEST_ASSERT_TRUE(e.h() >= ne.h() / 2 + 3);  // but still more than the top panes
  TEST_ASSERT_TRUE(e.w() >= 36);
  TEST_ASSERT_TRUE(eyeIsCrisp(b, right, kInkEye));
}

static void test_happy_eyes_squint_and_the_smile_stays_small() {
  Pose p;  // boxy eyes squinting from the bottom, and a small "u" smile
  p.lidBot = 700, p.mouthCurve = 900;
  Buf b = face(p), n = face(Pose{});
  checkSquint(b, n, false);
  checkSquint(b, n, true);
  TEST_ASSERT_EQUAL_INT(0, inkSpot(b, kInkRose).n);  // squinting alone has no heart
  // The smile is narrower than the resting mouth, not a wide grin.
  auto mouthWidth = [](const Buf& b) {
    int x0 = kWidth, x1 = -1;
    for (int y = kEyeRows; y < kStripTop; ++y) {
      for (int x = kWidth / 2 - 40; x < kWidth / 2 + 40; ++x) {
        if (b.c.get(x, y) != inkAt(kInkEye, kLevels)) continue;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
      }
    }
    return x1 - x0 + 1;
  };
  TEST_ASSERT_TRUE(mouthWidth(b) <= 21);
  TEST_ASSERT_TRUE(mouthWidth(b) < mouthWidth(n));
  // The cheeks rise with the squint.
  TEST_ASSERT_TRUE(inkSpot(b, kInkBlush).y0 < inkSpot(n, kInkBlush).y0);
  // The cheer (BEHAVIORS.md §5): the squint, white eyes and a heart.
  Pose c = animPose(Anim::kCheer, 1500);  // landed, after the hops
  TEST_ASSERT_EQUAL_INT(kInkEye, eyeInk(c));
  TEST_ASSERT_EQUAL_INT(1000, c.heart);
  TEST_ASSERT_TRUE(c.lidBot >= 650);
  TEST_ASSERT_EQUAL_INT(0, c.dy);
  // Three hops, then still.
  int hops = 0;
  bool up = false;
  for (uint32_t t = 0; t < animDuration(Anim::kCheer); t += 10) {
    bool air = animPose(Anim::kCheer, t).dy < -7;
    hops += air && !up;
    up = air;
  }
  TEST_ASSERT_EQUAL_INT(3, hops);
}

static void test_a_tap_is_a_squint_and_a_heart() {
  // A boop: the happy squint and a small smile, with a heart at the top
  // right of the face (UX.md §2, BEHAVIORS.md §3.3).
  Pose p = animPose(Anim::kWiggle, 0);
  p.dx = 0, p.squash = 0;
  Buf b = face(p), n = face(Pose{});
  checkSquint(b, n, false);
  checkSquint(b, n, true);
  EyeBox r = eyeBox(b, true);
  InkSpot heart = inkSpot(b, kInkRose);
  TEST_ASSERT_TRUE(heart.n > 150);
  TEST_ASSERT_TRUE(heart.x0 > r.x1);    // right of the right eye
  TEST_ASSERT_TRUE(heart.y1 < kFaceCy);  // and above the eyes' centre line
  // It pops in with the blend: halfway, a smaller heart.
  InkSpot half = inkSpot(face(blend(Pose{}, p, 512)), kInkRose);
  TEST_ASSERT_TRUE(half.n > 0 && half.n < heart.n);
  TEST_ASSERT_EQUAL_INT(0, inkSpot(face(Pose{}), kInkRose).n);
}

static void test_asleep_zzz_climbs_one_letter_at_a_time() {
  // Asleep, "zzZZ" climbs up from the right eye a letter at a time (UX.md §2).
  Pose p = lookPose(Look::kAsleep, 0);
  auto letters = [](const Buf& b) {  // lit pixels up and to the right of the right eye
    int n = 0;
    for (int y = 0; y < kFaceCy; ++y) {
      for (int x = kFaceCx + 72 + 24; x < kWidth; ++x) n += b.c.get(x, y) != kBlack;
    }
    return n;
  };
  TEST_ASSERT_EQUAL_INT(0, letters(face(p)));
  int last = 0;
  for (int z : {1, 300, 500, 700}) {  // z, z, Z, Z
    p.zzz = int16_t(z);
    Buf b = face(p);
    int n = letters(b);
    TEST_ASSERT_TRUE(n > last);
    last = n;
    for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL_INT(kBlack, b.c.get(x, 0));  // the last Z fits on screen
    for (int y = 0; y < kHeight; ++y) TEST_ASSERT_EQUAL_INT(kBlack, b.c.get(kWidth - 1, y));
  }
}

static void test_a_sweat_drop_sits_by_the_right_eye_and_slides_down() {
  // Working, a sweat drop slides down beside the right eye (UX.md §2).
  Pose p = lookPose(Look::kWorking, 1);
  TEST_ASSERT_EQUAL_INT(0, inkSpot(face(p), kInkSky).n);
  p.sweat = 1;
  Buf top = face(p);
  p.sweat = 1000;
  Buf low = face(p);
  InkSpot a = inkSpot(top, kInkSky), b = inkSpot(low, kInkSky);
  TEST_ASSERT_TRUE(a.n > 40);
  TEST_ASSERT_INT_WITHIN(4, a.n, b.n);
  TEST_ASSERT_TRUE(b.meanY() - a.meanY() >= 10);
  TEST_ASSERT_TRUE(a.x0 > eyeBox(top, true).x1);
}

static void test_a_happy_blend_squints_a_row_at_a_time() {
  // On the way to happy the bottom of the eye rises steadily and the top
  // stays put, so the change never jumps between two drawings (UX.md §2).
  int last = 1000;
  EyeBox n = eyeBox(face(Pose{}), false);
  for (int t = 0; t <= 1024; t += 64) {
    Pose happy;
    happy.lidBot = 700;
    Pose p = blend(Pose{}, happy, t);
    p.mouthCurve = 0;
    EyeBox e = eyeBox(face(p), false);
    TEST_ASSERT_EQUAL_INT(n.y0, e.y0);
    TEST_ASSERT_TRUE(e.w() >= 36);
    TEST_ASSERT_TRUE(e.y1 <= last);
    last = e.y1;
  }
}

static void test_blend_is_eased_interruptible_and_150ms() {
  Pose a, b;
  b.lookX = 1000, b.eyeSize = 1200;
  Blend bl;
  bl.start(1000, a);
  TEST_ASSERT_EQUAL_INT(0, bl.apply(1000, b).lookX);
  TEST_ASSERT_EQUAL_INT(500, bl.apply(1075, b).lookX);
  TEST_ASSERT_EQUAL_INT(1100, bl.apply(1075, b).eyeSize);
  TEST_ASSERT_TRUE(bl.apply(1075, b) != a);
  TEST_ASSERT_EQUAL_INT(1000, bl.apply(1150, b).lookX);
  TEST_ASSERT_FALSE(bl.blending(1150));
  // Interrupted halfway: the new blend starts from where the old one was.
  Pose mid = bl.apply(1075, b);
  Pose c;
  c.lookX = -1000;
  bl.start(1075, mid);
  TEST_ASSERT_EQUAL_INT(500, bl.apply(1075, c).lookX);
  TEST_ASSERT_EQUAL_INT(-1000, bl.apply(1225, c).lookX);
}

// BEHAVIORS.md §5: three animations, and nothing else.
static void test_every_anim_has_a_name_and_ends() {
  TEST_ASSERT_EQUAL_INT(4, int(Anim::kCount));
  for (int i = 1; i < int(Anim::kCount); ++i) {
    Anim a = Anim(i);
    TEST_ASSERT_TRUE(animFromName(animName(a)) == a);
    TEST_ASSERT_TRUE(animDuration(a) > 0);
    TEST_ASSERT_TRUE(animDuration(a) <= 30000);
  }
  for (const char* name : {"cheer", "wiggle", "listening"}) {
    TEST_ASSERT_TRUE_MESSAGE(animFromName(name) != Anim::kNone, name);
  }
  for (const char* gone : {"dance", "oops", "side_eye", "stretch", "yawn", "zip", "gobble", "rumble", "levelup",
                           "happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love", "nod",
                           "thinking", "shrug"}) {
    TEST_ASSERT_TRUE_MESSAGE(animFromName(gone) == Anim::kNone, gone);
  }
  TEST_ASSERT_EQUAL_UINT32(2000, animDuration(Anim::kCheer));
  TEST_ASSERT_EQUAL_UINT32(700, animDuration(Anim::kWiggle));
  TEST_ASSERT_EQUAL_UINT32(30000, animDuration(Anim::kListening));  // the hold cap
}

static void test_fonts_are_monospaced_and_utf8_aware() {
  TEST_ASSERT_EQUAL_INT(3 * kSmall.w, stringWidth(kSmall, "abc"));
  TEST_ASSERT_EQUAL_INT(3 * kLarge.w, stringWidth(kLarge, "a\xC2\xB7" "b"));  // "·" is one glyph
  Buf b;
  int end = drawString(b.c, kSmall, 10, 10, "Hi", kInkAmber);
  TEST_ASSERT_EQUAL_INT(10 + 2 * kSmall.w, end);
  TEST_ASSERT_TRUE(b.count(inkAt(kInkAmber, kLevels)) > 10);
  Buf fit;
  int w = drawStringFit(fit.c, kSmall, 0, 0, "a-very-long-project-name", kInkText, 10 * kSmall.w);
  TEST_ASSERT_TRUE(w <= 10 * kSmall.w);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_isqrt_is_exact);
  RUN_TEST(test_isin_hits_the_quadrants);
  RUN_TEST(test_ease_is_monotonic_from_0_to_1024);
  RUN_TEST(test_spans_cut_and_intersect);
  RUN_TEST(test_fill_shape_antialiases_only_the_edges);
  RUN_TEST(test_palette_ramps_run_from_black_to_the_ink);
  RUN_TEST(test_neutral_face_is_symmetric);
  RUN_TEST(test_eyes_are_four_crisp_panes);
  RUN_TEST(test_a_look_moves_the_whole_eye_with_perspective);
  RUN_TEST(test_eye_size_changes_only_the_eyes);
  RUN_TEST(test_lids_cut_each_half_flat);
  RUN_TEST(test_a_look_up_keeps_full_panes_and_working_looks_down);
  RUN_TEST(test_closed_eyes_are_a_line);
  RUN_TEST(test_happy_eyes_squint_and_the_smile_stays_small);
  RUN_TEST(test_a_tap_is_a_squint_and_a_heart);
  RUN_TEST(test_asleep_zzz_climbs_one_letter_at_a_time);
  RUN_TEST(test_a_sweat_drop_sits_by_the_right_eye_and_slides_down);
  RUN_TEST(test_a_happy_blend_squints_a_row_at_a_time);
  RUN_TEST(test_blend_is_eased_interruptible_and_150ms);
  RUN_TEST(test_every_anim_has_a_name_and_ends);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  return UNITY_END();
}
