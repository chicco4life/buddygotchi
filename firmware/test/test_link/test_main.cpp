// Line reassembly, screenshot encoding, the clock and button gestures.
#include <unity.h>

#include <cstring>
#include <string>

#include "app/clock.h"
#include "app/codec.h"
#include "app/gesture.h"
#include "app/line_reader.h"

using app::ButtonGesture;

void setUp() {}
void tearDown() {}

static int feedAll(app::LineReader& r, const char* s, std::string* last) {
  int lines = 0;
  for (const char* p = s; *p; ++p) {
    if (r.feed(*p)) {
      ++lines;
      *last = std::string(r.line(), r.length());
    }
  }
  return lines;
}

static void test_lines_reassemble_across_chunks() {
  app::LineReader r;
  std::string last;
  TEST_ASSERT_EQUAL_INT(0, feedAll(r, "{\"t\":\"st", &last));
  TEST_ASSERT_EQUAL_INT(1, feedAll(r, "ate\"}\r\n{\"t\"", &last));
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"state\"}", last.c_str());
  TEST_ASSERT_EQUAL_INT(1, feedAll(r, ":1}\n\n", &last));  // empty lines are skipped
  TEST_ASSERT_EQUAL_STRING("{\"t\":1}", last.c_str());
}

static void test_overlong_lines_are_dropped_whole() {
  app::LineReader r;
  std::string last, big(app::LineReader::kMax + 10, 'x');
  big += "\nok\n";
  TEST_ASSERT_EQUAL_INT(1, feedAll(r, big.c_str(), &last));
  TEST_ASSERT_EQUAL_STRING("ok", last.c_str());
}

static void sink(void* ctx, const char* text, size_t n) { static_cast<std::string*>(ctx)->append(text, n); }

static void test_base64_matches_rfc4648() {
  const char* cases[][2] = {{"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"}, {"foobar", "Zm9vYmFy"}};
  for (auto& c : cases) {
    std::string out;
    app::Base64Writer w(sink, &out);
    // Split the input to check chunking doesn't matter.
    size_t n = std::strlen(c[0]);
    w.write(reinterpret_cast<const uint8_t*>(c[0]), n / 2);
    w.write(reinterpret_cast<const uint8_t*>(c[0]) + n / 2, n - n / 2);
    w.finish();
    TEST_ASSERT_EQUAL_STRING(c[1], out.c_str());
  }
}

static void test_crc32_matches_zlib() {
  const uint8_t data[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
  TEST_ASSERT_EQUAL_UINT32(0xCBF43926u, app::crc32(data, sizeof(data)));
  TEST_ASSERT_EQUAL_UINT32(0xCBF43926u, app::crc32(data + 4, 5, app::crc32(data, 4)));
}

static void test_clock_freezes_steps_and_runs() {
  app::Clock c;
  c.start(false, 1000);
  TEST_ASSERT_EQUAL_UINT32(500, c.now(1500));
  c.freeze(42);
  TEST_ASSERT_EQUAL_UINT32(42, c.now(9999));
  c.step(8, 9999);
  TEST_ASSERT_EQUAL_UINT32(50, c.now(12345));
  c.run(20000);
  TEST_ASSERT_EQUAL_UINT32(60, c.now(20010));
}

static void test_short_press_is_a_tap() {
  ButtonGesture g;
  TEST_ASSERT_EQUAL(ButtonGesture::kDown, g.update(true, 1000));
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 1399));
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 1399));
}

static void test_hold_is_push_to_talk_until_release() {
  ButtonGesture g;
  g.update(true, 0);
  TEST_ASSERT_EQUAL(ButtonGesture::kHoldStart, g.update(true, 400));
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 2000));
  TEST_ASSERT_EQUAL(ButtonGesture::kHoldEnd, g.update(false, 2500));
  TEST_ASSERT_FALSE(g.holding());
}

static void test_bounces_are_ignored() {
  ButtonGesture g;
  g.update(true, 0);
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(false, 5));  // bounce
  TEST_ASSERT_TRUE(g.down());
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 60));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_lines_reassemble_across_chunks);
  RUN_TEST(test_overlong_lines_are_dropped_whole);
  RUN_TEST(test_base64_matches_rfc4648);
  RUN_TEST(test_crc32_matches_zlib);
  RUN_TEST(test_clock_freezes_steps_and_runs);
  RUN_TEST(test_short_press_is_a_tap);
  RUN_TEST(test_hold_is_push_to_talk_until_release);
  RUN_TEST(test_bounces_are_ignored);
  return UNITY_END();
}
