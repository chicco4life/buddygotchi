// The device core's debug channel and inputs, through the same Hal the
// simulator uses.
#include <unity.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "app/device.h"

void setUp() {}
void tearDown() {}

namespace {

struct FakeHal : app::Hal {
  uint32_t real = 0;
  bool boot = false;
  uint32_t led = 0;
  uint32_t realMs() override { return real; }
  bool bootDown() override { return boot; }
  void setLed(uint32_t rgb) override { led = rgb; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "abc"; }
};

struct Capture : app::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};

struct Rig {
  FakeHal hal;
  Capture usb, ble;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
  app::Device dev{hal, px.data(), true};
  Rig() {
    dev.setOut(app::Link::kUsb, &usb);
    dev.setOut(app::Link::kBle, &ble);
    dev.tick();
  }
  void usbLine(const char* s) {
    dev.handleLine(s, std::strlen(s), app::Link::kUsb);
    dev.tick();
  }
};

bool has(const std::string& s, const char* needle) { return s.find(needle) != std::string::npos; }

}  // namespace

static void test_ping_reports_version_and_link() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"sha\":\"abc\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"none\""));  // dbg.* doesn't count as the Mac
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"usb\""));
}

static void test_debug_is_ignored_over_ble() {
  Rig r;
  r.dev.handleLine("{\"t\":\"dbg.ping\"}", 16, app::Link::kBle);
  TEST_ASSERT_TRUE(r.ble.text.empty());
}

static int count(const std::string& s, const char* needle) {
  int n = 0;
  for (size_t at = s.find(needle); at != std::string::npos; at = s.find(needle, at + 1)) ++n;
  return n;
}

// PROTOCOL.md §4–5: status on connect and every 60 s, on the Mac's link.
static void test_status_on_connect_and_every_minute() {
  Rig r;
  r.hal.real = 1000;
  r.dev.connected(app::Link::kBle);
  TEST_ASSERT_TRUE(has(r.ble.text, "{\"t\":\"status\",\"v\":1,\"id\":\"b00p-0000\",\"fw\":\"t\",\"bat\":0,\"usb\":1}\n"));
  r.dev.handleLine("{\"t\":\"state\",\"base\":\"idle\"}", 28, app::Link::kBle);
  r.hal.real = 60999;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.ble.text, "\"status\""));
  r.hal.real = 61000;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"status\""));
  // Input goes to the Mac on Bluetooth; nothing leaks onto USB.
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  r.hal.real += 100;
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.ble.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"status\""));
  r.dev.disconnected(app::Link::kBle);
  r.hal.real = 200000;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"status\""));
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"none\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"ble\":\"off\""));
}

// USB has no connect event: the Mac's first word, or its first after 30 s
// of silence, counts as connecting.
static void test_usb_status_when_the_mac_first_speaks() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_FALSE(has(r.usb.text, "\"status\""));  // tools don't count
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"status\""));
  r.hal.real = 20000;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"status\""));
  r.hal.real = 50000;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, "\"status\""));
}

static void test_pattern_until_next_state() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.pattern\"}");
  TEST_ASSERT_EQUAL(app::Screen::kPattern, r.dev.screen());
  TEST_ASSERT_TRUE(r.dev.takeFrame());
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\""));
}

static void test_injected_tap_reaches_the_mac() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");  // the Mac is on USB
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
}

static void test_physical_hold_sends_talk_on_and_off() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  r.hal.boot = true;
  r.dev.tick();
  r.hal.real = 450;
  r.dev.tick();
  TEST_ASSERT_TRUE(has(r.usb.text, "\"k\":\"talk_on\""));
  r.hal.boot = false;
  r.hal.real = 900;
  r.dev.tick();
  TEST_ASSERT_TRUE(has(r.usb.text, "\"k\":\"talk_off\""));
}

static void test_shot_is_header_then_base64() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.shot\"}");
  size_t nl = r.usb.text.find('\n');
  TEST_ASSERT_TRUE(has(r.usb.text.substr(0, nl), "\"bytes\":77312"));
  std::string body = r.usb.text.substr(nl + 1);
  TEST_ASSERT_EQUAL_UINT32(77312 / 3 * 4 + 4 + 1, body.size());  // padded, plus the newline
}

static void test_light_sets_the_led() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.light\",\"led\":\"#FFB000\"}");
  TEST_ASSERT_EQUAL_UINT32(0xFFB000, r.hal.led);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"led\":\"#FFB000\""));
}

static void test_attention_shows_needs_you_and_climbs_the_ladder() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  TEST_ASSERT_EQUAL(app::Screen::kNeedsYou, r.dev.screen());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":20000}");
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":45000}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rung\":2"));
  // A different project restarts the ladder.
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"site\"}}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rung\":1"));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
}

static void test_no_app_after_30s_of_silence() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":29999}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":30000}");
  TEST_ASSERT_EQUAL(app::Screen::kNoApp, r.dev.screen());
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
}

static void test_moment_plays_then_ends_and_a_new_one_replaces_it() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"nod\",\"size\":1,\"ttl\":5}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"nod\",\"left_ms\":600}"));
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":2,\"ttl\":5}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"cheer\""));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  r.usbLine("{\"t\":\"moment\",\"anim\":\"moonwalk\"}");  // unknown: ignored
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
}

static void test_strip_taps_cycle_the_screens() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  const app::Screen order[] = {app::Screen::kThreads, app::Screen::kStats, app::Screen::kFace};
  uint32_t t = 0;
  for (app::Screen want : order) {
    r.usbLine("{\"t\":\"dbg.touch\",\"x\":120,\"y\":300,\"ms\":100}");
    t += 200;
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
    TEST_ASSERT_EQUAL(want, r.dev.screen());
  }
  // A touch on the face doesn't change the screen.
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":120,\"y\":100,\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1000}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
}

static void test_reset_forgets_the_mac_and_freezes_at_0() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"x\"}}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_EQUAL(0u, r.dev.now());
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"idle\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"attn\":null"));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_ping_reports_version_and_link);
  RUN_TEST(test_debug_is_ignored_over_ble);
  RUN_TEST(test_status_on_connect_and_every_minute);
  RUN_TEST(test_usb_status_when_the_mac_first_speaks);
  RUN_TEST(test_pattern_until_next_state);
  RUN_TEST(test_injected_tap_reaches_the_mac);
  RUN_TEST(test_physical_hold_sends_talk_on_and_off);
  RUN_TEST(test_shot_is_header_then_base64);
  RUN_TEST(test_light_sets_the_led);
  RUN_TEST(test_attention_shows_needs_you_and_climbs_the_ladder);
  RUN_TEST(test_no_app_after_30s_of_silence);
  RUN_TEST(test_moment_plays_then_ends_and_a_new_one_replaces_it);
  RUN_TEST(test_strip_taps_cycle_the_screens);
  RUN_TEST(test_reset_forgets_the_mac_and_freezes_at_0);
  return UNITY_END();
}
