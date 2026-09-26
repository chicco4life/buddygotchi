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
constexpr int kEyeRows = kFaceCy + 46;  // rows above this hold only the eyes

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
      if (b.c.get(x, y) == kBlack) continue;
      ++e.n;
      if (x < e.x0) e.x0 = x;
      if (x > e.x1) e.x1 = x;
      if (y < e.y0) e.y0 = y;
      if (y > e.y1) e.y1 = y;
    }
  }
  return e;
}

// An eye is one convex shape in one ink: every pixel is on the eye ink's
// ramp, and along every row and column the coverage only rises, then only
// falls. A pupil, a hole or a sliver left where a lid meets the side would
// all show as a dip.
bool unimodal(const int* v, int n) {
  int i = 0;
  while (i + 1 < n && v[i + 1] >= v[i]) ++i;
  while (i + 1 < n && v[i + 1] <= v[i]) ++i;
  return i == n - 1;
}
bool eyeIsConvex(const Buf& b, bool right, int ink) {
  const int x0 = right ? kWidth / 2 : 0, x1 = right ? kWidth : kWidth / 2;
  static int cover[kHeight][kWidth];
  for (int y = 0; y < kEyeRows; ++y) {
    for (int x = x0; x < x1; ++x) {
      int v = b.c.get(x, y);
      if (v != kBlack && (v < inkAt(ink, 1) || v > inkAt(ink, kLevels))) return false;
      cover[y][x] = v == kBlack ? 0 : v - inkAt(ink, 1) + 1;
    }
    if (!unimodal(&cover[y][x0], x1 - x0)) return false;
  }
  int col[kHeight];
  for (int x = x0; x < x1; ++x) {
    for (int y = 0; y < kEyeRows; ++y) col[y] = cover[y][x];
    if (!unimodal(col, kEyeRows)) return false;
  }
  return true;
}

// Pixels of the eyes that no disk of radius rho inside them can reach. A
// shape whose corners all have a radius of at least rho has none; a sharp
// point, where a lid meets the outline, leaves a few in its tip. The face is
// drawn at 1.5× so the corners are big enough to measure, and an eye pixel
// is one at least half covered. The mouth (a thin line with the mouth shut)
// is left out: only the two biggest blobs count. Single stray pixels are
// the stair-steps of an edge, so only ones next to another count.
int sharpPoints(const Pose& pose, int rho) {
  Pose p = pose;
  p.mouthOpen = 0, p.dx = 0, p.dy = 0, p.size = 1000, p.raise = 0;
  Buf b;
  drawFace(b.c, p, kWidth / 2, 110, 1500);
  const int ink = eyeInk(p);
  static bool eye[kHeight][kWidth], fits[kHeight][kWidth], tip[kHeight][kWidth];
  static int blob[kHeight][kWidth];
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      int v = b.c.get(x, y);
      eye[y][x] = v >= inkAt(ink, (kLevels + 1) / 2) && v <= inkAt(ink, kLevels);
      blob[y][x] = 0;
    }
  }
  std::vector<int> size(1, 0);
  std::vector<int> stack;
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      if (!eye[y][x] || blob[y][x]) continue;
      int id = int(size.size());
      size.push_back(0);
      blob[y][x] = id;
      stack.push_back(y * kWidth + x);
      while (!stack.empty()) {
        int at = stack.back();
        stack.pop_back();
        ++size[id];
        for (int dy = -1; dy <= 1; ++dy) {
          for (int dx = -1; dx <= 1; ++dx) {
            int yy = at / kWidth + dy, xx = at % kWidth + dx;
            if (yy < 0 || yy >= kHeight || xx < 0 || xx >= kWidth || !eye[yy][xx] || blob[yy][xx]) continue;
            blob[yy][xx] = id;
            stack.push_back(yy * kWidth + xx);
          }
        }
      }
    }
  }
  int big = 0, next = 0;
  for (int i = 1; i < int(size.size()); ++i) {
    if (size[i] > size[big]) next = big, big = i;
    else if (size[i] > size[next]) next = i;
  }
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) eye[y][x] = eye[y][x] && (blob[y][x] == big || blob[y][x] == next);
  }
  auto inDisk = [rho](int dx, int dy) { return dx * dx + dy * dy <= rho * rho; };
  for (int y = 0; y < kHeight; ++y) {  // where a whole disk fits (past the screen's edge counts as eye)
    for (int x = 0; x < kWidth; ++x) {
      bool ok = eye[y][x];
      for (int dy = -rho; ok && dy <= rho; ++dy) {
        for (int dx = -rho; ok && dx <= rho; ++dx) {
          int yy = y + dy, xx = x + dx;
          if (inDisk(dx, dy)) ok = yy < 0 || yy >= kHeight || xx < 0 || xx >= kWidth || eye[yy][xx];
        }
      }
      fits[y][x] = ok;
    }
  }
  for (int y = 0; y < kHeight; ++y) {  // eye pixels no fitting disk covers
    for (int x = 0; x < kWidth; ++x) {
      bool reached = !eye[y][x];
      for (int dy = -rho; !reached && dy <= rho; ++dy) {
        for (int dx = -rho; !reached && dx <= rho; ++dx) {
          int yy = y + dy, xx = x + dx;
          reached = inDisk(dx, dy) && yy >= 0 && yy < kHeight && xx >= 0 && xx < kWidth && fits[yy][xx];
        }
      }
      tip[y][x] = !reached;
    }
  }
  int n = 0;
  for (int y = 1; y < kHeight - 1; ++y) {
    for (int x = 1; x < kWidth - 1; ++x) {
      if (!tip[y][x]) continue;
      int around = 0;
      for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) around += (dx || dy) && tip[y + dy][x + dx];
      }
      n += around > 0;
    }
  }
  return n;
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
  TEST_ASSERT_EQUAL_HEX16(rgb565(kOatRgb), paletteAt(inkAt(kInkOat, kLevels)));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kAmberRgb), paletteAt(inkAt(kInkAmber, kLevels)));
  TEST_ASSERT_EQUAL_INT(kBlack, inkAt(kInkOat, 0));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kHollowRgb), paletteAt(hollowAt(kInkOat, kLevels)));
  TEST_ASSERT_EQUAL_INT(inkAt(kInkGlow4, kLevels), hollowAt(kInkGlow4, 0));
  TEST_ASSERT_TRUE(kPaletteUsed <= 256);
  TEST_ASSERT_EQUAL_HEX16(rgb565(255, 0, 0), paletteAt(kRed));  // the bring-up pattern's colours stay
}

static void test_neutral_face_is_symmetric() {
  Buf b = face(Pose{});
  TEST_ASSERT_TRUE(b.count(inkAt(kInkOat, kLevels)) > 7000);
  // Solid eyes and a centred mouth: the face is its own mirror image.
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth / 2; ++x) TEST_ASSERT_EQUAL_INT(b.c.get(x, y), b.c.get(kWidth - 1 - x, y));
  }
  // The eyes are about 42% of the screen apart (plan/UX.md §2).
  int apart = eyeBox(b, true).cx() - eyeBox(b, false).cx();
  TEST_ASSERT_INT_WITHIN(6, kWidth * 42 / 100, apart);
}

static void test_eyes_are_solid_with_no_pupils() {
  Pose looks[8];
  looks[1].lookX = 1000;
  looks[2].lookX = -700, looks[2].lookY = -800;
  looks[3].eyeSize = 1250;
  looks[4].lidTop = 400, looks[4].lidTilt = 600;
  looks[5] = animPose(Anim::kWorried, 1, 0);
  looks[6] = animPose(Anim::kSideEye, 1, 0);
  looks[7] = animPose(Anim::kOops, 2, 300);
  for (Pose p : looks) {
    p.mouthOpen = 0;  // nothing dark anywhere: an open mouth is the only hollow
    p.dx = 0, p.dy = 0;
    Buf b = face(p);
    TEST_ASSERT_EQUAL_INT(0, b.count(kHollow));
    TEST_ASSERT_TRUE(eyeIsConvex(b, false, eyeInk(p)));
    TEST_ASSERT_TRUE(eyeIsConvex(b, true, eyeInk(p)));
    // The middle of each eye is solid ink.
    EyeBox l = eyeBox(b, false), r = eyeBox(b, true);
    int ink = inkAt(eyeInk(p), kLevels);
    TEST_ASSERT_EQUAL_INT(ink, b.c.get(l.cx(), l.y1 - l.h() / 3));
    TEST_ASSERT_EQUAL_INT(ink, b.c.get(r.cx(), r.y1 - r.h() / 3));
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
  TEST_ASSERT_TRUE(l.w() - nl.w() >= 6 && l.h() - nl.h() >= 8);
  TEST_ASSERT_INT_WITHIN(1, nl.cx(), l.cx());  // it grows about its own centre
  for (int y = kEyeRows + 2; y < kHeight; ++y) {  // the mouth doesn't change
    for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL_INT(n.c.get(x, y), b.c.get(x, y));
  }
}

static void test_lid_corners_are_rounded() {
  Pose p;
  p.lidTop = 400;
  Buf b = face(p);
  EyeBox e = eyeBox(b, false);
  // A sharp lid would leave the rows just under it nearly as wide as the
  // eye; the rounded corners pull them in.
  auto width = [&](int y) {
    int n = 0;
    for (int x = 0; x < kWidth / 2; ++x) n += b.c.get(x, y) != kBlack;
    return n;
  };
  TEST_ASSERT_TRUE(width(e.y0 + 1) <= e.w() - 6);
  TEST_ASSERT_TRUE(width(e.y0 + e.h() / 2) == e.w());
  // Tilted lids too: every lid pose leaves each eye one clean convex shape.
  const Anim lidded[] = {Anim::kWorried, Anim::kSulky, Anim::kSideEye, Anim::kShrug, Anim::kZip, Anim::kSmug};
  for (Anim a : lidded) {
    Pose q = animPose(a, 1, 400);
    q.mouthOpen = 0, q.dx = 0, q.dy = 0;  // keep the mouth below the eye rows
    Buf c = face(q);
    TEST_ASSERT_TRUE_MESSAGE(eyeIsConvex(c, false, eyeInk(q)), animName(a));
    TEST_ASSERT_TRUE_MESSAGE(eyeIsConvex(c, true, eyeInk(q)), animName(a));
  }
}

static void test_a_lid_never_leaves_a_sharp_point() {
  // Held looks, where the full 8 px corner fits: low tilted lids (the
  // working and idle faces at night while starving, as app/behaviour.cpp
  // colours them), a low lid on its own, every phase of a yawn, and every
  // expression with lids.
  struct Case {
    const char* name;
    Pose p;
    bool blink;  // also check it mid-blink
  };
  std::vector<Case> cases;
  for (Look look : {Look::kWorking, Look::kIdle}) {
    Pose p = lookPose(look, 1, 0);
    p.lidTop = int16_t(p.lidTop + 180 + 250), p.lidTilt = -200;
    cases.push_back({look == Look::kWorking ? "working, night, starving" : "idle, night, starving", p, true});
  }
  Pose low;
  low.lidTop = 600, low.lidTilt = -200;
  cases.push_back({"low tilted lid", low, true});
  for (uint32_t t : {300u, 600u, 900u, 1250u}) cases.push_back({"yawn", animPose(Anim::kYawn, 1, t), false});
  for (Anim a : {Anim::kWorried, Anim::kSulky, Anim::kSideEye, Anim::kShrug, Anim::kZip, Anim::kSmug, Anim::kSleepy,
                 Anim::kThinking, Anim::kCurious, Anim::kListening}) {
    cases.push_back({animName(a), animPose(a, 1, 400), true});
  }
  for (const Case& c : cases) {
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, sharpPoints(c.p, 4), c.name);
    if (!c.blink) continue;
    // Mid-blink the eye narrows and the corner radius with it, down to
    // 2 px, but there is still no point.
    for (int open : {500, 300}) {
      Pose b = c.p;
      b.open = int16_t(open);
      TEST_ASSERT_EQUAL_INT_MESSAGE(0, sharpPoints(b, 3), c.name);
    }
  }
}

static void test_thinking_looks_up_and_working_looks_down() {
  // With no pupils to roll, lids alone would make these the same hooded
  // eyes in two places. Working keeps flat lid tops and sits low; thinking
  // keeps round tops and sits high.
  auto rowWidth = [](const Buf& b, bool right, int y) {
    int w = 0;
    for (int x = right ? kWidth / 2 : 0; x < (right ? kWidth : kWidth / 2); ++x) w += b.c.get(x, y) != kBlack;
    return w;
  };
  Buf n = face(Pose{}), t = face(animPose(Anim::kThinking, 1, 0)), w = face(lookPose(Look::kWorking, 1, 0));
  for (bool right : {false, true}) {
    EyeBox ne = eyeBox(n, right), te = eyeBox(t, right), we = eyeBox(w, right);
    TEST_ASSERT_TRUE(ne.y0 - te.y0 >= 15);
    TEST_ASSERT_TRUE(we.y0 - ne.y0 >= 15);
    TEST_ASSERT_TRUE(rowWidth(t, right, te.y0 + 2) <= 45);  // under 3/4 of the 60 px eye: a round top
    TEST_ASSERT_TRUE(rowWidth(w, right, we.y0 + 2) >= 50);  // a lid's flat top
  }
}

static void test_closed_eyes_are_a_line() {
  Pose p;
  p.open = 0;
  Buf b = face(p);
  EyeBox e = eyeBox(b, false);
  TEST_ASSERT_TRUE(e.h() <= 6);
  TEST_ASSERT_TRUE(e.w() >= 50);
  TEST_ASSERT_TRUE(b.count(inkAt(kInkOat, kLevels)) > 100);  // but a line is there
}

static void test_happy_eyes_are_arcs_and_cheer_glows() {
  Pose p = animPose(Anim::kHappy, 1, 0);
  p.mouthOpen = 0;
  Buf b = face(p);
  EyeBox e = eyeBox(b, false);
  // Down the middle of the eye: ink at the top, and the lower lid's arc
  // leaves nothing below it.
  int top = 0, below = 0;
  for (int y = e.y0; y < e.y0 + 8; ++y) top += b.c.get(e.cx(), y) != kBlack;
  for (int y = kFaceCy; y < kEyeRows; ++y) below += b.c.get(e.cx(), y) != kBlack;
  TEST_ASSERT_TRUE(top >= 6);
  TEST_ASSERT_EQUAL_INT(0, below);
  TEST_ASSERT_EQUAL_INT(0, b.count(kHollow));
  TEST_ASSERT_EQUAL_INT(kInkGlow4, eyeInk(animPose(Anim::kCheer, 3, 0)));
  TEST_ASSERT_TRUE(eyeInk(animPose(Anim::kOops, 1, 0)) >= kInkOops1);
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

static void test_every_anim_has_a_name_and_ends() {
  for (int i = 1; i < int(Anim::kCount); ++i) {
    Anim a = Anim(i);
    TEST_ASSERT_TRUE(animFromName(animName(a)) == a);
    TEST_ASSERT_TRUE(animDuration(a, 2) > 0);
    TEST_ASSERT_TRUE(animDuration(a, 2) <= 30000);
  }
  TEST_ASSERT_TRUE(animFromName("dance") == Anim::kNone);
  TEST_ASSERT_TRUE(animDuration(Anim::kCheer, 3) > animDuration(Anim::kCheer, 1));
}

static void test_fonts_are_monospaced_and_utf8_aware() {
  TEST_ASSERT_EQUAL_INT(3 * kSmall.w, stringWidth(kSmall, "abc"));
  TEST_ASSERT_EQUAL_INT(3 * kLarge.w, stringWidth(kLarge, "a\xC2\xB7" "b"));  // "·" is one glyph
  Buf b;
  int end = drawString(b.c, kSmall, 10, 10, "Hi", kInkAmber);
  TEST_ASSERT_EQUAL_INT(10 + 2 * kSmall.w, end);
  TEST_ASSERT_TRUE(b.count(inkAt(kInkAmber, kLevels)) > 10);
  Buf fit;
  int w = drawStringFit(fit.c, kSmall, 0, 0, "a-very-long-project-name", kInkOat, 10 * kSmall.w);
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
  RUN_TEST(test_eyes_are_solid_with_no_pupils);
  RUN_TEST(test_a_look_moves_the_whole_eye_with_perspective);
  RUN_TEST(test_eye_size_changes_only_the_eyes);
  RUN_TEST(test_lid_corners_are_rounded);
  RUN_TEST(test_a_lid_never_leaves_a_sharp_point);
  RUN_TEST(test_thinking_looks_up_and_working_looks_down);
  RUN_TEST(test_closed_eyes_are_a_line);
  RUN_TEST(test_happy_eyes_are_arcs_and_cheer_glows);
  RUN_TEST(test_blend_is_eased_interruptible_and_150ms);
  RUN_TEST(test_every_anim_has_a_name_and_ends);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  return UNITY_END();
}
