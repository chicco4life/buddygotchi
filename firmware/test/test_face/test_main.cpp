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

using namespace render;

void setUp() {}
void tearDown() {}

namespace {
struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  int count(uint8_t v) const {
    int n = 0;
    for (uint8_t p : px) n += p == v;
    return n;
  }
};
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
  TEST_ASSERT_EQUAL_HEX16(rgb565(kPupilRgb), paletteAt(pupilAt(kInkOat, kLevels)));
  TEST_ASSERT_EQUAL_INT(inkAt(kInkGlow4, kLevels), pupilAt(kInkGlow4, 0));
  TEST_ASSERT_TRUE(kPaletteUsed <= 256);
  TEST_ASSERT_EQUAL_HEX16(rgb565(255, 0, 0), paletteAt(kRed));  // the bring-up pattern's colours stay
}

static void test_neutral_face_is_symmetric() {
  Buf b;
  drawFace(b.c, Pose{}, kWidth / 2, 122, 1000);
  int oat = b.count(inkAt(kInkOat, kLevels)), pupil = b.count(kPupil);
  TEST_ASSERT_TRUE(oat > 5000);
  TEST_ASSERT_TRUE(pupil > 1000);
  // Pupils and glints sit up-left in both eyes, so compare only the whites'
  // outline: each row has the same number of eye pixels on both sides.
  for (int y = 0; y < kHeight; ++y) {
    int left = 0, right = 0;
    for (int x = 0; x < kWidth / 2; ++x) left += b.c.get(x, y) != kBlack;
    for (int x = kWidth / 2; x < kWidth; ++x) right += b.c.get(x, y) != kBlack;
    if (y < 180) TEST_ASSERT_EQUAL_INT(left, right);
  }
}

static void test_closed_eyes_have_no_pupils() {
  Buf b;
  Pose p;
  p.open = 0;
  drawFace(b.c, p, kWidth / 2, 122, 1000);
  TEST_ASSERT_EQUAL_INT(0, b.count(kPupil));
  TEST_ASSERT_TRUE(b.count(inkAt(kInkOat, kLevels)) > 100);  // but a line is there
}

static void test_happy_eyes_have_no_pupils_and_cheer_glows() {
  Buf b;
  Pose p = animPose(Anim::kHappy, 1, 0);
  Pose eyesOnly = p;
  eyesOnly.mouthOpen = 0;
  drawFace(b.c, eyesOnly, kWidth / 2, 122, 1000);
  TEST_ASSERT_EQUAL_INT(0, b.count(kPupil));
  TEST_ASSERT_EQUAL_INT(kInkGlow4, eyeInk(animPose(Anim::kCheer, 3, 0)));
  TEST_ASSERT_TRUE(eyeInk(animPose(Anim::kOops, 1, 0)) >= kInkOops1);
}

static void test_blend_is_eased_interruptible_and_150ms() {
  Pose a, b;
  b.lookX = 1000;
  Blend bl;
  bl.start(1000, a);
  TEST_ASSERT_EQUAL_INT(0, bl.apply(1000, b).lookX);
  TEST_ASSERT_EQUAL_INT(500, bl.apply(1075, b).lookX);
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
  RUN_TEST(test_closed_eyes_have_no_pupils);
  RUN_TEST(test_happy_eyes_have_no_pupils_and_cheer_glows);
  RUN_TEST(test_blend_is_eased_interruptible_and_150ms);
  RUN_TEST(test_every_anim_has_a_name_and_ends);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  return UNITY_END();
}
