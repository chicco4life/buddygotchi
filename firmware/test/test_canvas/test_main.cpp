#include <unity.h>

#include <vector>

#include "render/canvas.h"

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

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_fill_rect_clips_to_canvas);
  RUN_TEST(test_fill_covers_everything);
  return UNITY_END();
}
