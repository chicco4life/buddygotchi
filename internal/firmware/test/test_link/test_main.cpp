// Line reassembly (USB and BLE packets), screenshot encoding, the clock and button gestures.
#include <unity.h>

#include <cstring>
#include <algorithm>
#include <string>
#include <vector>

#include "app/clock.h"
#include "app/codec.h"
#include "app/gesture.h"
#include "app/line_reader.h"
#include "app/link_silence.h"
#include "app/packets.h"

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

// BLE: packets of any size, split anywhere, come back as the same lines.
static void test_ble_packets_reassemble_through_the_ring() {
  const std::string msg = "{\"t\":\"state\",\"base\":\"working\",\"busy\":2}\n{\"t\":\"moment\",\"anim\":\"cheer\"}\n";
  for (size_t size : {1, 3, 20, 61, 182, 244}) {
    app::ByteRing<1024> ring;
    app::LineReader r;
    std::vector<std::string> got;
    for (size_t at = 0; at < msg.size(); at += size) {
      size_t k = std::min(size, msg.size() - at);
      TEST_ASSERT_EQUAL_UINT32(k, ring.put(reinterpret_cast<const uint8_t*>(msg.data()) + at, k));
      uint8_t c;
      while (ring.take(c))
        if (r.feed(char(c))) got.emplace_back(r.line(), r.length());
    }
    TEST_ASSERT_EQUAL_INT(2, int(got.size()));
    TEST_ASSERT_EQUAL_STRING("{\"t\":\"state\",\"base\":\"working\",\"busy\":2}", got[0].c_str());
    TEST_ASSERT_EQUAL_STRING("{\"t\":\"moment\",\"anim\":\"cheer\"}", got[1].c_str());
  }
}

static void test_ring_drops_what_does_not_fit_and_wraps() {
  app::ByteRing<8> ring;
  const uint8_t a[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
  TEST_ASSERT_EQUAL_UINT32(8, ring.put(a, 10));
  TEST_ASSERT_EQUAL_UINT32(2, ring.dropped());
  uint8_t c = 0;
  for (int i = 0; i < 5; ++i) ring.take(c);
  TEST_ASSERT_EQUAL_UINT8(5, c);
  TEST_ASSERT_EQUAL_UINT32(5, ring.put(a, 5));  // wraps around the end
  std::vector<uint8_t> rest;
  while (ring.take(c)) rest.push_back(c);
  TEST_ASSERT_EQUAL_INT(8, int(rest.size()));
  TEST_ASSERT_EQUAL_UINT8(6, rest[0]);
  TEST_ASSERT_EQUAL_UINT8(1, rest[3]);
  TEST_ASSERT_EQUAL_UINT8(5, rest[7]);
}

static void collect(void* ctx, const uint8_t* data, size_t n) {
  static_cast<std::vector<std::string>*>(ctx)->emplace_back(reinterpret_cast<const char*>(data), n);
}

static void test_packet_writer_sends_whole_lines_in_payload_chunks() {
  std::vector<std::string> pkts;
  app::PacketWriter w(collect, &pkts);
  w.setPayload(20);
  const std::string line = "{\"t\":\"status\",\"v\":1,\"id\":\"b00p-7f3a\",\"fw\":\"0.4.0\",\"bat\":0,\"usb\":1}";
  w.write(line.data(), 30);
  TEST_ASSERT_EQUAL_INT(0, int(pkts.size()));  // nothing until the newline
  w.write(line.data() + 30, line.size() - 30);
  w.write("\n", 1);
  std::string joined;
  for (auto& p : pkts) {
    TEST_ASSERT_TRUE(p.size() <= 20);
    joined += p;
  }
  TEST_ASSERT_EQUAL_INT(int((line.size() + 1 + 19) / 20), int(pkts.size()));
  TEST_ASSERT_EQUAL_STRING((line + "\n").c_str(), joined.c_str());

  pkts.clear();
  w.setPayload(244);  // a negotiated MTU of 247
  const char* two = "{\"t\":\"input\",\"k\":\"tap\"}\n{\"t\":\"status\",\"fw\":\"t\"}\n";
  w.write(two, std::strlen(two));
  TEST_ASSERT_EQUAL_INT(2, int(pkts.size()));
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"status\",\"fw\":\"t\"}\n", pkts[1].c_str());
}

static void test_packet_writer_drops_overlong_lines_and_clears() {
  std::vector<std::string> pkts;
  app::PacketWriter w(collect, &pkts);
  std::string big(app::LineReader::kMax + 5, 'x');
  w.write(big.data(), big.size());
  w.write("\nok\n", 4);
  TEST_ASSERT_EQUAL_INT(1, int(pkts.size()));
  TEST_ASSERT_EQUAL_STRING("ok\n", pkts[0].c_str());
  w.write("half", 4);
  w.clear();
  w.write("new\n", 4);
  TEST_ASSERT_EQUAL_STRING("new\n", pkts.back().c_str());
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

// plan/UX.md §4: any press is a tap, however long, sent on release.
static void test_long_press_is_a_tap_too() {
  ButtonGesture g;
  g.update(true, 0);
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 400));
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(true, 5000));
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 5000));
  TEST_ASSERT_FALSE(g.down());
}

static void test_bounces_are_ignored() {
  ButtonGesture g;
  g.update(true, 0);
  TEST_ASSERT_EQUAL(ButtonGesture::kNone, g.update(false, 5));  // bounce
  TEST_ASSERT_TRUE(g.down());
  TEST_ASSERT_EQUAL(ButtonGesture::kTap, g.update(false, 60));
}

// plan/PROTOCOL.md §2, "Reconnecting": a Bluetooth link silent for 30 s is
// dropped, and if that didn't take, dropped again 30 s later.
static void test_a_quiet_link_is_dropped_after_30_s() {
  TEST_ASSERT_EQUAL_UINT32(30000, app::LinkSilence::kDropMs);
  app::LinkSilence s;
  s.heard(1000);
  TEST_ASSERT_FALSE(s.drop(30999));
  s.heard(20000);  // the Mac's 10 s keepalive
  TEST_ASSERT_FALSE(s.drop(49999));
  TEST_ASSERT_TRUE(s.drop(50000));
  TEST_ASSERT_FALSE(s.drop(50001));
  TEST_ASSERT_TRUE(s.drop(80000));
  s.heard(0xFFFFF000u);  // millis() wraps
  TEST_ASSERT_FALSE(s.drop(0x00001000u));
  TEST_ASSERT_TRUE(s.drop(0xFFFFF000u + 30000));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_lines_reassemble_across_chunks);
  RUN_TEST(test_overlong_lines_are_dropped_whole);
  RUN_TEST(test_ble_packets_reassemble_through_the_ring);
  RUN_TEST(test_ring_drops_what_does_not_fit_and_wraps);
  RUN_TEST(test_packet_writer_sends_whole_lines_in_payload_chunks);
  RUN_TEST(test_packet_writer_drops_overlong_lines_and_clears);
  RUN_TEST(test_base64_matches_rfc4648);
  RUN_TEST(test_crc32_matches_zlib);
  RUN_TEST(test_clock_freezes_steps_and_runs);
  RUN_TEST(test_short_press_is_a_tap);
  RUN_TEST(test_long_press_is_a_tap_too);
  RUN_TEST(test_bounces_are_ignored);
  RUN_TEST(test_a_quiet_link_is_dropped_after_30_s);
  return UNITY_END();
}
