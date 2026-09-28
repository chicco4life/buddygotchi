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
  TEST_ASSERT_EQUAL_INT(320, render::kWidth);  // landscape
  TEST_ASSERT_EQUAL_INT(240, render::kHeight);
  c.fillRect(310, 230, 50, 50, 3);
  TEST_ASSERT_EQUAL_UINT8(3, c.get(319, 239));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(309, 239));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(319, 229));
}

static void test_fill_covers_everything() {
  std::vector<uint8_t> buf(render::kWidth * render::kHeight, 0);
  Canvas c(buf.data());
  c.fill(5);
  TEST_ASSERT_EQUAL_UINT8(5, c.get(0, 0));
  TEST_ASSERT_EQUAL_UINT8(5, c.get(319, 239));
  TEST_ASSERT_EQUAL_UINT8(0, c.get(320, 0));  // out of range reads as 0
  TEST_ASSERT_EQUAL_UINT8(0, c.get(0, 240));
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
  c.fillRect(render::kWidth - 1, 5, 1, 1, 1);
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
  for (const auto& b : render::kPatternBlocks) {  // on screen, clear of the USB-C bar and the labels
    TEST_ASSERT_TRUE(b.x >= 0 && b.x + b.w <= render::kWidth - render::kPatternUsbW);
    TEST_ASSERT_TRUE(b.y >= 0 && b.y + b.h <= render::kHeight - 12);
  }
  const int mid = render::kWidth / 2;
  TEST_ASSERT_EQUAL_UINT8(render::kWhite, c.get(mid, 20));  // the arrow tip is at the top
  TEST_ASSERT_EQUAL_UINT8(render::kGrey, c.get(mid, render::kHeight - 6));  // grey at the bottom
  // The USB-C bar is down the right edge, and the left edge is grey.
  TEST_ASSERT_EQUAL_UINT8(render::kBlack, c.get(render::kWidth - 1, render::kHeight / 2));
  TEST_ASSERT_EQUAL_UINT8(render::kBlack, c.get(render::kWidth - render::kPatternUsbW, render::kHeight / 2));
  TEST_ASSERT_EQUAL_UINT8(render::kGrey, c.get(0, render::kHeight / 2));
  TEST_ASSERT_EQUAL_UINT8(render::kGrey, c.get(render::kWidth - 1, 1));  // the bar stops short of the corners
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
