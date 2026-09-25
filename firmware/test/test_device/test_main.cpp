// The device core's debug channel and inputs, through the same Hal the
// simulator uses.
#include <unity.h>

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

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_ping_reports_version_and_link);
  RUN_TEST(test_debug_is_ignored_over_ble);
  RUN_TEST(test_pattern_until_next_state);
  RUN_TEST(test_injected_tap_reaches_the_mac);
  RUN_TEST(test_physical_hold_sends_talk_on_and_off);
  RUN_TEST(test_shot_is_header_then_base64);
  RUN_TEST(test_light_sets_the_led);
  return UNITY_END();
}
