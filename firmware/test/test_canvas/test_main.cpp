#include <unity.h>

#include <vector>

#include "render/canvas.h"
#include "render/palette.h"
#include "render/pattern.h"

using render::Canvas;

void setUp() {}
void tearDown() {}

static void test_fill_rect_clips_to_canvas() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  c.fillRect(-10, -10, 20, 20, 7);
  TEST_ASSERT_EQUAL_UINT8(7, c.get(0, 0));
  TEST_ASSERT_EQUAL_UINT8(7, c.get(9, 9));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(10, 10));
  c.fillRect(230, 310, 50, 50, 3);
  TEST_ASSERT_EQUAL_UINT8(3, c.get(239, 319));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(229, 319));
}

static void test_fill_covers_everything() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  c.fill(5);
  TEST_ASSERT_EQUAL_UINT8(5, c.get(0, 0));
  TEST_ASSERT_EQUAL_UINT8(5, c.get(239, 319));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(240, 0));  // out of range reads as 0
}

static void test_text_draws_glyph_pixels() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  int end = c.drawText(10, 10, "I", 9, 2);  // 'I' is 0x00,0x41,0x7F,0x41,0x00
  TEST_ASSERT_EQUAL_INT(22, end);
  TEST_ASSERT_EQUAL_UINT8(0, c.get(10, 10));   // column 0 is blank
  TEST_ASSERT_EQUAL_UINT8(9, c.get(14, 10));   // column 2, row 0, scaled ×2
  TEST_ASSERT_EQUAL_UINT8(9, c.get(15, 23));   // column 2, row 6
  TEST_ASSERT_EQUAL_UINT8(0, c.get(14, 24));   // row 7 is blank
  TEST_ASSERT_EQUAL_INT(11, Canvas::textWidth("UP"));
}

static void test_triangle_fills_inside_only() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  c.fillTriangle(100, 10, 50, 60, 150, 60, 4);
  TEST_ASSERT_EQUAL_UINT8(4, c.get(100, 10));  // the tip
  TEST_ASSERT_EQUAL_UINT8(4, c.get(100, 40));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(60, 20));   // outside the left edge
  TEST_ASSERT_EQUAL_UINT8(0, c.get(100, 61));  // below the base
}

static void test_row_hash_tracks_changes() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  uint32_t before = c.rowHash(5);
  TEST_ASSERT_EQUAL_UINT32(before, c.rowHash(6));
  c.fillRect(239, 5, 1, 1, 1);
  TEST_ASSERT_NOT_EQUAL(before, c.rowHash(5));
  TEST_ASSERT_EQUAL_UINT32(before, c.rowHash(6));
}

static void test_pattern_blocks_have_their_colours() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  render::drawPattern(c);
  for (const auto& b : render::kPatternBlocks) {
    TEST_ASSERT_EQUAL_UINT8(b.color, c.get(b.x + b.w / 2, b.y + b.h / 2));
  }
  TEST_ASSERT_EQUAL_UINT8(render::kWhite, c.get(120, 20));  // the arrow tip is at the top
  TEST_ASSERT_EQUAL_UINT8(render::kGrey, c.get(120, 305));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_fill_rect_clips_to_canvas);
  RUN_TEST(test_fill_covers_everything);
  RUN_TEST(test_text_draws_glyph_pixels);
  RUN_TEST(test_triangle_fills_inside_only);
  RUN_TEST(test_row_hash_tracks_changes);
  RUN_TEST(test_pattern_blocks_have_their_colours);
  return UNITY_END();
}
