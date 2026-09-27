// The device core's debug channel and inputs, through the same Hal the
// simulator uses.
#include <unity.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "app/device.h"
#include "app/line_reader.h"
#include "render/palette.h"

void setUp() {}
void tearDown() {}

namespace {

struct FakeHal : app::Hal {
  uint32_t real = 0;
  bool boot = false;
  uint32_t led = 0;
  uint8_t bl = 255;
  uint32_t realMs() override { return real; }
  void setBacklight(uint8_t level) override { bl = level; }
  bool bootDown() override { return boot; }
  void setLed(uint32_t rgb) override { led = rgb; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "abc"; }
  std::vector<voice::Line> said;
  std::vector<voice::Cue> cues;
  int hushes = 0;
  void say(const voice::Line& l) override { said.push_back(l); }
  void cue(voice::Cue c, uint8_t vol) override {
    (void)vol;
    cues.push_back(c);
  }
  void hush() override { ++hushes; }
  bool touching = false;  // the panel, at the middle of the face
  bool touch(int& x, int& y) override {
    if (touching) x = 160, y = 100;
    return touching;
  }
  app::TouchCal cal;
  void setTouchCal(const app::TouchCal& c) override { cal = c; }
  app::TouchCal touchCal() override { return cal; }
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
  TEST_ASSERT_TRUE(has(r.usb.text, "\"w\":320,\"h\":240"));  // the screen, for boopctl calibrate
}

static void test_touch_calibration_maps_raw_to_screen() {
  // Raw y runs 250 → 3750 across the width, raw x 3800 → 300 down the height.
  app::TouchCal c;
  c.bx = int32_t(320.0 / 3500 * 65536), c.cx = int32_t(-250 * 320.0 / 3500 * 65536);
  c.ay = int32_t(-240.0 / 3500 * 65536), c.cy = int32_t(3800 * 240.0 / 3500 * 65536);
  int x, y;
  c.map(3800, 250, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  c.map(2050, 2000, x, y);
  TEST_ASSERT_INT_WITHIN(1, 160, x);
  TEST_ASSERT_INT_WITHIN(1, 120, y);
  c.map(0, 4095, x, y);  // past the edge: clamped to the screen
  TEST_ASSERT_EQUAL(319, x);
  TEST_ASSERT_EQUAL(239, y);
}

// The default map turns with the picture. Raw (x_min, y_min) is the panel's
// own top-left pixel (portrait, USB-C at the bottom), and raw y runs down
// the panel's 320 px side, towards USB-C.
static void test_default_touch_map_follows_the_rotation() {
  const int lo = app::kTouchRawMin, hi = app::kTouchRawMax;
  int x, y;
  // Rotation 1, USB-C on the right (a quarter turn anticlockwise from
  // portrait): the panel's top-left is the screen's bottom-left, and the
  // USB-C end is the right edge.
  app::TouchCal r1 = app::defaultTouchCal(1);
  TEST_ASSERT_TRUE(r1.valid);
  r1.map(lo, lo, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 239, y);
  r1.map(hi, lo, x, y);  // the panel's top-right: the screen's top-left
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  r1.map(lo, hi, x, y);  // the panel's bottom-left, by USB-C: the bottom-right
  TEST_ASSERT_INT_WITHIN(1, 319, x);
  TEST_ASSERT_INT_WITHIN(1, 239, y);
  r1.map((lo + hi) / 2, (lo + hi) / 2, x, y);
  TEST_ASSERT_INT_WITHIN(1, 160, x);
  TEST_ASSERT_INT_WITHIN(1, 120, y);
  // Rotation 3, USB-C on the left (a quarter turn clockwise): the panel's
  // top-left is the screen's top-right.
  app::TouchCal r3 = app::defaultTouchCal(3);
  r3.map(lo, lo, x, y);
  TEST_ASSERT_INT_WITHIN(1, 319, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  r3.map(lo, hi, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 0, y);
  r3.map(hi, hi, x, y);
  TEST_ASSERT_INT_WITHIN(1, 0, x);
  TEST_ASSERT_INT_WITHIN(1, 239, y);
}

// A calibration is kept with the screen it was fitted on; one fitted on
// another screen (the portrait build's) or another rotation is ignored.
static void test_saved_touch_calibration_must_match_the_screen() {
  app::TouchCal c;
  c.ax = 11, c.bx = 22, c.cx = 33, c.ay = 44, c.by = 55, c.cy = 66, c.valid = true;
  app::SavedTouchCal saved = app::saveTouchCal(c, 1);
  TEST_ASSERT_EQUAL(320, saved.w);
  TEST_ASSERT_EQUAL(240, saved.h);
  app::TouchCal out;
  TEST_ASSERT_TRUE(app::loadTouchCal(&saved, sizeof(saved), 1, out));
  TEST_ASSERT_EQUAL(11, out.ax);
  TEST_ASSERT_EQUAL(66, out.cy);
  TEST_ASSERT_TRUE(out.valid);

  app::TouchCal none;
  TEST_ASSERT_FALSE(app::loadTouchCal(&saved, sizeof(saved), 3, none));  // kRotation flipped since
  TEST_ASSERT_FALSE(none.valid);
  app::SavedTouchCal portrait = saved;
  portrait.w = 240, portrait.h = 320, portrait.rotation = 0;
  TEST_ASSERT_FALSE(app::loadTouchCal(&portrait, sizeof(portrait), 1, none));
  // The portrait build stored the bare map, with no screen: a different size.
  TEST_ASSERT_FALSE(app::loadTouchCal(&c, sizeof(c), 1, none));
  TEST_ASSERT_FALSE(app::loadTouchCal(&saved, 0, 1, none));
  TEST_ASSERT_FALSE(app::loadTouchCal(nullptr, sizeof(saved), 1, none));
  app::SavedTouchCal cleared = app::saveTouchCal(app::TouchCal{}, 1);
  TEST_ASSERT_FALSE(app::loadTouchCal(&cleared, sizeof(cleared), 1, none));
  TEST_ASSERT_FALSE(none.valid);
}

static void test_touchcal_sets_reads_and_clears() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.touchcal\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"cal\":null"));
  r.usbLine("{\"t\":\"dbg.touchcal\",\"set\":[-4494,0,15630336,0,5991,-1497965]}");
  TEST_ASSERT_TRUE(r.hal.cal.valid);
  TEST_ASSERT_EQUAL(-4494, r.hal.cal.ax);
  TEST_ASSERT_EQUAL(-1497965, r.hal.cal.cy);
  TEST_ASSERT_TRUE(has(r.usb.text, "\"cal\":[-4494,0,15630336,0,5991,-1497965]"));
  r.usbLine("{\"t\":\"dbg.touchcal\",\"clear\":true}");
  TEST_ASSERT_FALSE(r.hal.cal.valid);
}

static void test_pattern_target_draws_a_cross() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.pattern\",\"target\":[20,220]}");  // bottom left, as boopctl calibrate puts it
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(20, 220));
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(29, 220));
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(20, 211));
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(20, 229));
  TEST_ASSERT_EQUAL(render::kBlack, r.dev.canvas().get(40, 200));
  TEST_ASSERT_EQUAL(render::kBlack, r.dev.canvas().get(160, 120));
  r.usbLine("{\"t\":\"dbg.pattern\",\"target\":[300,20]}");  // top right
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(300, 20));
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(310, 20));
  TEST_ASSERT_EQUAL(render::kBlack, r.dev.canvas().get(20, 220));
  r.usbLine("{\"t\":\"dbg.pattern\",\"target\":[2147483647,-9]}");  // off the screen: kept on it
  TEST_ASSERT_EQUAL(render::kAmber, r.dev.canvas().get(319, 0));
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
  r.dev.connected();
  TEST_ASSERT_TRUE(has(r.ble.text, "{\"t\":\"status\",\"v\":1,\"id\":\"b00p-0000\",\"fw\":\"t\"}\n"));
  r.dev.handleLine("{\"t\":\"state\",\"base\":\"idle\"}", 28, app::Link::kBle);
  r.hal.real = 60999;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.ble.text, "\"status\""));
  r.hal.real = 61000;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"status\""));
  // Input goes to the Mac on Bluetooth; nothing leaks onto USB.
  r.hal.boot = true;
  r.dev.tick();
  r.hal.boot = false;
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.ble.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"input\""));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"status\""));
  r.dev.disconnected();
  r.hal.real = 200000;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.ble.text, "\"status\""));
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"link\":\"none\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"ble\":\"off\""));
}

// PROTOCOL.md §4: a real press goes to every live Mac link. A tool's
// moment over USB while the app is on Bluetooth (boopctl mumble) doesn't
// take the taps away from the app; USB gets a copy while
// the Mac spoke there in the last 30 s.
static void test_input_reaches_every_live_link() {
  Rig r;
  auto step = [&](int ms) {
    std::string s = "{\"t\":\"dbg.clock\",\"step\":" + std::to_string(ms) + "}";
    r.usbLine(s.c_str());
  };
  auto press = [&](int ms, int every) {  // BOOT, held for `ms`
    step(50);  // past BOOT's debounce
    r.hal.boot = true;
    r.dev.tick();
    for (int at = every; at <= ms; at += every) step(every);
    r.hal.boot = false;
    step(every);
  };
  const char* tap = "{\"t\":\"input\",\"k\":\"tap\"}";
  r.dev.connected();
  r.dev.handleLine("{\"t\":\"state\",\"base\":\"idle\"}", 28, app::Link::kBle);
  r.hal.real = 1000;
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  press(100, 100);  // a tap
  press(800, 500);  // a long press: a tap too
  for (const std::string* out : {&r.ble.text, &r.usb.text}) {
    TEST_ASSERT_EQUAL_INT(2, count(*out, tap));
  }
  // 30 s after the tool's last word, only Bluetooth hears.
  r.hal.real = 31000;
  press(100, 100);
  TEST_ASSERT_EQUAL_INT(3, count(r.ble.text, tap));
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, tap));
  // Disconnected, Bluetooth hears nothing more.
  r.dev.disconnected();
  press(100, 100);
  TEST_ASSERT_EQUAL_INT(3, count(r.ble.text, tap));
}

// PROTOCOL.md §4: input a tool injects (dbg.press, dbg.touch) goes back
// only over USB, where the tool is, even while the everyday app is on
// Bluetooth, so a test run never reaches the everyday app.
static void test_injected_input_stays_on_usb() {
  Rig r;
  r.dev.connected();
  r.dev.handleLine("{\"t\":\"state\",\"base\":\"idle\"}", 28, app::Link::kBle);
  r.usbLine("{\"t\":\"dbg.reset\"}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":800}");
  for (int ms = 0; ms <= 900; ms += 10) r.usbLine("{\"t\":\"dbg.clock\",\"step\":10}");
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":200}");
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"input\""));
  // With only dbg.* traffic from the tool, too.
  r.hal.real = 60000;
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":200}");
  TEST_ASSERT_EQUAL_INT(3, count(r.usb.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"input\""));
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

// PROTOCOL.md §3: `state` carries the mood, and like every field it's a
// snapshot: a state without one, or with one the device doesn't know, is
// happy again.
static void test_state_carries_the_mood() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"mood\":\"happy\""));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"determined\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\",\"mood\":\"determined\""));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"sulky\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"mood\":\"happy\""));
  r.usbLine("{\"t\":\"state\",\"mood\":\"sad\"}");
  r.usbLine("{\"t\":\"state\",\"base\":\"napping\"}");  // a base it doesn't know is idle
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"idle\",\"mood\":\"happy\""));
}

static void test_injected_tap_reaches_the_mac() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");  // the Mac is on USB
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
}

// UX.md §4: the resistive panel misses readings under a light press, so a
// panel touch ends only after 50 ms without contact. A press that flickers
// is one tap; a new press after a real lift is another.
static void test_a_flickering_touch_is_one_tap() {
  TEST_ASSERT_EQUAL_UINT32(50, app::Device::kTouchReleaseMs);
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  const char* tap = "{\"t\":\"input\",\"k\":\"tap\"}";
  for (uint32_t ms = 0; ms < 300; ms += 2) {  // 10 ms in contact, 10 ms not; last contact at 288
    r.hal.real = ms;
    r.hal.touching = ms / 10 % 2 == 0;
    r.dev.tick();
  }
  r.hal.touching = false;
  r.hal.real = 337;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(0, count(r.usb.text, tap));
  r.hal.real = 338;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, tap));
  r.hal.real = 400;
  r.hal.touching = true;
  r.dev.tick();
  r.hal.real = 450;
  r.hal.touching = false;
  r.dev.tick();
  r.hal.real = 500;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(2, count(r.usb.text, tap));
}

// UX.md §4: the 50 ms runs on real time, so a panel touch still ends, and
// taps at once, while a tool has the clock frozen.
static void test_a_touch_ends_while_the_clock_is_frozen() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1000}");
  const char* tap = "{\"t\":\"input\",\"k\":\"tap\"}";
  for (uint32_t ms = 200; ms <= 400; ms += 5) {
    r.hal.real = ms;
    r.hal.touching = ms < 300;  // last contact at 295
    r.dev.tick();
    if (ms == 340) {
      TEST_ASSERT_EQUAL_INT(0, count(r.usb.text, tap));
      r.usbLine("{\"t\":\"dbg.state\"}");
      TEST_ASSERT_TRUE(has(r.usb.text, "\"touch\":{\"down\":true"));
    }
  }
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, tap));
  TEST_ASSERT_EQUAL_UINT32(1000, r.dev.now());  // still frozen
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"touch\":{\"down\":false"));
}

// UX.md §4: a long BOOT press is a tap, sent on release.
static void test_a_physical_long_press_is_a_tap() {
  Rig r;
  r.usbLine("{\"t\":\"state\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  r.hal.boot = true;
  r.dev.tick();
  r.hal.real = 2000;
  r.dev.tick();
  TEST_ASSERT_FALSE(has(r.usb.text, "\"t\":\"input\""));
  r.hal.boot = false;
  r.hal.real = 2100;
  r.dev.tick();
  TEST_ASSERT_EQUAL_INT(1, count(r.usb.text, "\"t\":\"input\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
}

// PROTOCOL.md §5: a clock a tool froze runs again after 60 s with no
// dbg.* message, from where it stopped, so a tool that dies mid-run can't
// leave the board still: no-app, blinks and BOOT all need a moving clock.
// Traffic from the Mac doesn't count; the simulator's own start stays frozen.
static void test_a_frozen_clock_runs_again_after_60s_without_debug() {
  Rig r;
  r.hal.real = 100000;
  r.dev.tick();
  TEST_ASSERT_EQUAL_UINT32(0, r.dev.now());  // started frozen: not a tool's doing
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  r.hal.real = 130000;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.hal.real = 159999;
  r.dev.tick();
  TEST_ASSERT_EQUAL_UINT32(5000, r.dev.now());
  r.hal.real = 160000;
  r.dev.tick();
  r.hal.real = 160250;
  TEST_ASSERT_EQUAL_UINT32(5250, r.dev.now());
  // dbg.reset freezes it too, and any dbg.* message holds it another 60 s.
  r.usbLine("{\"t\":\"dbg.reset\"}");
  r.hal.real = 200000;
  r.usbLine("{\"t\":\"dbg.state\"}");
  r.hal.real = 259999;
  r.dev.tick();
  TEST_ASSERT_EQUAL_UINT32(0, r.dev.now());
  r.hal.real = 260000;
  r.dev.tick();
  r.hal.real = 261000;
  TEST_ASSERT_EQUAL_UINT32(1000, r.dev.now());
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

// DEVICE.md §6: with the clock running, motion redraws at most every
// 16 ms of real time, however fast the loop runs. A frozen clock checks
// on every step, so scenario frames stay exact. The excited working
// design's sparks and keys step 3 ms apart (810 and 813 ms), so uncapped
// its picture changes faster.
static void test_motion_redraws_at_most_every_16ms() {
  for (bool running : {true, false}) {
    Rig r;
    r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"excited\"}");
    if (running) r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
    r.dev.takeFrame();
    int frames = 0, last = 0, gap = 1000;
    for (int ms = 1; ms <= 2000; ++ms) {
      if (running) ++r.hal.real, r.dev.tick();
      else r.usbLine("{\"t\":\"dbg.clock\",\"step\":1}");
      if (!r.dev.takeFrame()) continue;
      ++frames;
      if (ms - last < gap) gap = ms - last;
      last = ms;
    }
    TEST_ASSERT_TRUE(frames > 10);
    if (running) TEST_ASSERT_GREATER_OR_EQUAL(16, gap);
    else TEST_ASSERT_LESS_THAN(16, gap);
  }
}

// DEVICE.md §6: a frame is drawn only when the picture changes. The
// designs step a few times a second, so with the clock running every frame
// drawn is a new picture, fewer than one a second asleep. And the screen always
// shows what drawing afresh would: stepping a frozen clock, which checks
// on every step, it matches a second rig that takes a dbg.shot (which
// draws afresh) after every step, pixel for pixel.
static void test_a_still_picture_isnt_redrawn() {
  struct Case {
    const char* base;
    const char* moment;
    int ms;
    int most;  // frames in 3 s; 3000 / 16 = 187 without the check
  };
  const Case cases[] = {
      {"{\"t\":\"state\",\"base\":\"asleep\"}", nullptr, 2400, 20},
      {"{\"t\":\"state\",\"base\":\"working\",\"busy\":3}", nullptr, 1200, 40},
      {"{\"t\":\"state\",\"base\":\"working\"}", "{\"t\":\"moment\",\"anim\":\"cheer\"}", 1200, 90},
  };
  for (const Case& c : cases) {
    const std::string name = std::string(c.base) + (c.moment ? c.moment : "");
    Rig r, fresh;
    for (Rig* x : {&r, &fresh}) {
      x->usbLine(c.base);
      if (c.moment) x->usbLine(c.moment);
    }
    for (int ms = 2; ms <= c.ms + 2; ms += 2) {
      r.usbLine("{\"t\":\"dbg.clock\",\"step\":2}");
      fresh.usbLine("{\"t\":\"dbg.clock\",\"step\":2}");
      fresh.usb.text.clear();
      fresh.usbLine("{\"t\":\"dbg.shot\"}");
      if (r.px != fresh.px) TEST_FAIL_MESSAGE(("stale frame at " + std::to_string(ms) + " ms: " + name).c_str());
    }
    if (c.moment) r.usbLine(c.moment);  // from the start again, with the clock running
    r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
    r.dev.takeFrame();
    std::vector<uint8_t> last = r.px;
    int frames = 0, pictures = 0;
    for (int ms = 0; ms < 3000; ++ms) {
      ++r.hal.real;
      r.dev.tick();
      if (!r.dev.takeFrame()) continue;
      ++frames;
      if (r.px != last) ++pictures, last = r.px;
    }
    TEST_ASSERT_EQUAL_MESSAGE(pictures, frames, name.c_str());
    TEST_ASSERT_TRUE_MESSAGE(frames > 0 && frames <= c.most, name.c_str());
  }
}

// ARCHITECTURE.md §9, UX.md §4: a press shows within 20 ms, and the 16 ms
// cap (DEVICE.md §6) doesn't hold it back. With the clock running and a
// loop pass every ms, the first frame that differs from the unpressed face
// after a BOOT press comes on the same ms as with a frozen clock, which
// draws every step.
static void test_the_redraw_cap_doesnt_delay_a_press() {
  const int n = int(app::Behaviour::kPressEaseMs);
  for (const char* base : {"idle", "working"}) {
    // Frames from ms 0 to n after a press at t = 500 (or none), each
    // checked against `ref`; returns them, or the first ms that differs.
    auto run = [&](bool press, bool running, const std::vector<std::vector<uint8_t>>* ref, int& first) {
      std::vector<std::vector<uint8_t>> frames;
      Rig r;
      std::string state = std::string("{\"t\":\"state\",\"base\":\"") + base + "\"}";
      r.usbLine(state.c_str());
      r.usbLine("{\"t\":\"dbg.clock\",\"step\":500}");
      if (running) r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
      r.hal.boot = press;
      first = -1;
      for (int ms = 0; ms < n; ++ms) {
        if (ms == 0 || running) {
          r.dev.tick();
        } else {
          r.usbLine("{\"t\":\"dbg.clock\",\"step\":1}");
        }
        if (r.dev.takeFrame() && ref && first < 0 && r.px != (*ref)[size_t(ms)]) first = ms;
        frames.push_back(r.px);
        ++r.hal.real;
      }
      return frames;
    };
    int frozen = -1, running = -1;
    std::vector<std::vector<uint8_t>> still = run(false, false, nullptr, frozen);
    run(true, false, &still, frozen);
    run(true, true, &still, running);
    TEST_ASSERT_TRUE_MESSAGE(frozen >= 0, base);  // the dip shows on the press's own ms
    TEST_ASSERT_EQUAL_INT_MESSAGE(frozen, running, base);
  }
}

// BEHAVIORS.md §3.2: one chirp per request, amber at half, nothing more
// while it waits; a different request chirps again.
static void test_attention_shows_needs_you_and_chirps_once() {
  Rig r;
  const char* landing = "{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}";
  r.usbLine(landing);
  TEST_ASSERT_EQUAL(app::Screen::kNeedsYou, r.dev.screen());
  TEST_ASSERT_EQUAL_UINT32(0x805800, r.hal.led);
  TEST_ASSERT_EQUAL(1, int(r.hal.cues.size()));
  TEST_ASSERT_TRUE(r.hal.cues[0] == voice::Cue::kChirp);
  for (uint32_t t : {20000u, 40000u, 60000u, 80000u, 100000u, 120000u, 140000u}) {
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
    r.usbLine(landing);
  }
  TEST_ASSERT_EQUAL(1, int(r.hal.cues.size()));
  TEST_ASSERT_EQUAL_UINT32(0x805800, r.hal.led);
  // A different project chirps again.
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"site\"}}");
  TEST_ASSERT_EQUAL(2, int(r.hal.cues.size()));
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  TEST_ASSERT_EQUAL_UINT32(0, r.hal.led);
  // Muted, no chirp.
  Rig m;
  m.usbLine("{\"t\":\"state\",\"base\":\"working\",\"vol\":0,\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  TEST_ASSERT_EQUAL(0, int(m.hal.cues.size()));
}

// BEHAVIORS.md §3.4: no app after 30 s of silence. dbg.state still says
// "no_app", the backlight dims to 60 and the face is asleep.
static void test_no_app_after_30s_of_silence() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":29999}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":30000}");
  TEST_ASSERT_EQUAL(app::Screen::kNoApp, r.dev.screen());
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":30150}");  // dimmed over the blend
  TEST_ASSERT_EQUAL(60, r.hal.bl);
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"screen\":\"no_app\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"bl\":60"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
}

static void test_moment_plays_then_ends_and_a_new_one_replaces_it() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"wiggle\",\"ttl\":5}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"wiggle\",\"left_ms\":700}"));
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":3,\"ttl\":5}");  // an old `size` is ignored
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"cheer\",\"left_ms\":2000"));  // one size, 2 s
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":5000}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  // Unknown animations, the removed ones among them: ignored.
  for (const char* gone : {"moonwalk", "oops", "happy", "levelup", "yawn", "nod", "thinking", "shrug"}) {
    std::string line = std::string("{\"t\":\"moment\",\"anim\":\"") + gone + "\"}";
    r.usbLine(line.c_str());
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  }
  TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
  // An unknown animation with a mumble: the mumble plays on its own.
  r.usbLine("{\"t\":\"moment\",\"anim\":\"oops\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
}

// PROTOCOL.md §3: a moment with neither `anim` nor `say`, or with only
// an unknown anim, is ignored: whatever is playing carries on.
static void test_a_moment_with_nothing_to_play_is_ignored() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"ttl\":5}");
  r.usbLine("{\"t\":\"moment\",\"ttl\":5}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"shrug\",\"ttl\":5}");  // removed: ignored
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"cheer\""));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rx\":{\"state\":1,\"moment\":3}"));
  TEST_ASSERT_EQUAL(0, r.hal.hushes);
}

// UX.md §4: the strip is part of the screen; a touch on it is a tap.
static void test_a_strip_touch_is_a_tap() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":100}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":200}");
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"input\",\"k\":\"tap\"}"));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"anim\":\"wiggle\""));
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

// F5: a moment's mumble reaches the player with its syllables, word, tune
// and tempo, and the player follows volume and needs you.
static void test_say_reaches_the_player() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":7}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"say\":{\"syl\":\"bi-do ba zz\",\"word\":\"done\",\"at\":4,\"tune\":\"up\",\"ms\":110},\"ttl\":5}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  const voice::Line& l = r.hal.said[0];
  TEST_ASSERT_EQUAL(4, l.n);
  TEST_ASSERT_EQUAL(voice::syllableIndex("bi", 2), l.syl[0]);
  TEST_ASSERT_EQUAL(voice::syllableIndex("ba", 2), l.syl[2]);
  TEST_ASSERT_EQUAL(voice::kSilent, l.syl[3]);  // not a syllable Boop knows: a silent beat
  TEST_ASSERT_EQUAL(voice::wordIndex("done"), l.word);
  TEST_ASSERT_EQUAL(4, l.at);
  TEST_ASSERT_TRUE(l.tune == voice::Tune::kUp);
  TEST_ASSERT_EQUAL(110, l.ms);
  TEST_ASSERT_EQUAL(7, l.vol);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"syllables\":4,\"out\":{"));
  // A tap's wiggle replaces the moment, and with it the line.
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);
}

// PROTOCOL.md §3: a moment with only `say` plays the mumble, bubble and
// voice, over the face showing; no animation starts. The line stops when
// the bubble goes.
// PROTOCOL.md §3 and §5: a moment's `mood` is its expression, which
// dbg.state reports as `expr` while it plays; an unknown one is ignored,
// and the mumble plays as usual.
static void test_a_moment_carries_its_expression() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":0}");
  r.usbLine("{\"t\":\"state\",\"base\":\"working\",\"mood\":\"happy\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"mood\":\"grumpy\"}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"mood\":\"happy\""));  // the state's mood is kept
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":\"grumpy\""));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1399}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":\"grumpy\""));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1400}");  // 2 × 100 ms + 1.2 s
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  // Unknown: no expression, and the mumble still plays.
  size_t said = r.hal.said.size();
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"mood\":\"annoyed\"}");
  TEST_ASSERT_EQUAL(int(said + 1), int(r.hal.said.size()));
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"expr\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true"));
}

static void test_a_say_on_its_own_plays_the_mumble() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"working\"}");
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"ttl\":5}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"syllables\":2"));
  // (2 syllables × 100 ms) + 1.2 s: the bubble goes, and the line with it.
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1399}");
  TEST_ASSERT_EQUAL(0, r.hal.hushes);
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1400}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);
  // With no mumble and no animation, nothing happens.
  r.usbLine("{\"t\":\"moment\",\"ttl\":5}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
}

static void test_mute_and_needs_you_keep_it_silent() {
  const char* states[] = {
      "{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}",
  };
  for (const char* st : states) {
    for (const char* mo : {"{\"t\":\"moment\",\"anim\":\"cheer\",\"say\":{\"syl\":\"ba\",\"ms\":100}}",
                           "{\"t\":\"moment\",\"say\":{\"syl\":\"ba\",\"ms\":100}}"}) {
      Rig r;
      r.usbLine(st);
      r.usbLine(mo);
      TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
    }
  }
  // Muted, the mouth still moves: only the sound goes.
  Rig r;
  r.usbLine(states[0]);
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"syllables\":2"));
  // A line stops when mute arrives mid-line.
  Rig q;
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  q.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  TEST_ASSERT_EQUAL(1, int(q.hal.said.size()));
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}");
  TEST_ASSERT_EQUAL(1, q.hal.hushes);
}

// BEHAVIORS.md §4: the chirp is the only cue. A cheer plays none. Only
// mute silences it: it's the one thing Boop must say.
static void test_only_needs_you_chirps() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\"}");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":3000}");
  TEST_ASSERT_EQUAL(0, int(r.hal.cues.size()));
  // A line playing when something starts needing you is hushed for the chirp.
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":3100}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);
  TEST_ASSERT_EQUAL(1, int(r.hal.cues.size()));
  TEST_ASSERT_TRUE(r.hal.cues[0] == voice::Cue::kChirp);
}

// PROTOCOL.md §4: a moment with an `id` gets one `ended` once all of it
// is over, on the link it came in on, saying how: done, cut and why, or
// skipped. Muting doesn't stop it. A moment with no `id` gets none.
static void test_a_moment_with_an_id_is_answered_when_it_ends() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"mood\":\"proud\",\"id\":5}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}");  // hushed, but it plays on
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1399}");
  TEST_ASSERT_FALSE(has(r.usb.text, "\"ended\""));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1400}");  // 2 × 100 ms + 1.2 s
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ended\",\"id\":5,\"how\":\"done\"}\n"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"id\":6}");
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ended\",\"id\":6,\"how\":\"cut\",\"why\":\"tap\"}\n"));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":10000}");
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"id\":7}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ended\",\"id\":7,\"how\":\"cut\",\"why\":\"moment\"}\n"));
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"id\":8}");
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ended\",\"id\":8,\"how\":\"cut\",\"why\":\"needs_you\"}\n"));
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"id\":9}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ended\",\"id\":9,\"how\":\"skipped\"}\n"));
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"id\":10}");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"ended\",\"id\":10,\"how\":\"cut\",\"why\":\"reset\"}\n"));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":60000}");
  TEST_ASSERT_EQUAL_INT(6, count(r.usb.text, "\"ended\""));  // one each, and none without an id

  // Over Bluetooth: back over Bluetooth, and not on USB.
  Rig b;
  b.dev.connected();
  const char* state = "{\"t\":\"state\",\"base\":\"idle\"}";
  const char* moment = "{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"ms\":100},\"id\":3}";
  b.dev.handleLine(state, std::strlen(state), app::Link::kBle);
  b.dev.handleLine(moment, std::strlen(moment), app::Link::kBle);
  b.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1400}");
  TEST_ASSERT_TRUE(has(b.ble.text, "{\"t\":\"ended\",\"id\":3,\"how\":\"done\"}\n"));
  TEST_ASSERT_FALSE(has(b.usb.text, "\"ended\""));
}

// PROTOCOL.md §2: a line is at most 512 bytes. The board and boop-sim both
// read their lines through LineReader, so a longer one is dropped whole on
// both, and the next line is read as usual.
static void test_lines_over_512_bytes_are_dropped() {
  auto state = [](const char* base, size_t bytes) {
    std::string s = std::string("{\"t\":\"state\",\"base\":\"") + base + "\",\"pad\":\"";
    s += std::string(bytes - s.size() - 2, 'x') + "\"}";
    return s;
  };
  Rig r;
  app::LineReader reader;
  auto feed = [&](const std::string& line) {
    TEST_ASSERT_TRUE(line.size() <= 520);
    for (char c : line + "\n") {
      if (reader.feed(c)) r.dev.handleLine(reader.line(), reader.length(), app::Link::kUsb);
    }
    r.dev.tick();
  };
  std::string at512 = state("working", 512), at513 = state("asleep", 513);
  TEST_ASSERT_EQUAL(512, int(at512.size()));
  TEST_ASSERT_EQUAL(513, int(at513.size()));
  feed(at512);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\""));
  r.usb.text.clear();
  feed(at513);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"working\""));  // dropped
  r.usb.text.clear();
  feed(state("asleep", 100));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"base\":\"asleep\""));
}

// VOICE.md §8, PROTOCOL.md §3: numbers out of range are held in range once,
// as they arrive, so the mouth and the voice agree: `ms` to 60–400, the
// word's `at` to the syllables, and `vol` to 0–10.
static void test_say_and_volume_are_held_in_range() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":15}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"vol\":10,"));
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"word\":\"done\",\"at\":9,\"ms\":1000}}");
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  TEST_ASSERT_EQUAL(400, r.hal.said[0].ms);
  TEST_ASSERT_EQUAL(2, r.hal.said[0].at);
  TEST_ASSERT_EQUAL(10, r.hal.said[0].vol);
  // The mouth keeps the same beat: (2 syllables + 2 for the word) × 400 ms.
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1599}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,"));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":1600}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":false,"));
  r.usbLine("{\"t\":\"moment\",\"say\":{\"syl\":\"ba po\",\"word\":\"done\",\"at\":-3,\"ms\":20}}");
  TEST_ASSERT_EQUAL(2, int(r.hal.said.size()));
  TEST_ASSERT_EQUAL(60, r.hal.said[1].ms);
  TEST_ASSERT_EQUAL(0, r.hal.said[1].at);
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":-3}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"vol\":0,"));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_ping_reports_version_and_link);
  RUN_TEST(test_debug_is_ignored_over_ble);
  RUN_TEST(test_touch_calibration_maps_raw_to_screen);
  RUN_TEST(test_default_touch_map_follows_the_rotation);
  RUN_TEST(test_saved_touch_calibration_must_match_the_screen);
  RUN_TEST(test_touchcal_sets_reads_and_clears);
  RUN_TEST(test_pattern_target_draws_a_cross);
  RUN_TEST(test_status_on_connect_and_every_minute);
  RUN_TEST(test_usb_status_when_the_mac_first_speaks);
  RUN_TEST(test_input_reaches_every_live_link);
  RUN_TEST(test_injected_input_stays_on_usb);
  RUN_TEST(test_pattern_until_next_state);
  RUN_TEST(test_injected_tap_reaches_the_mac);
  RUN_TEST(test_a_physical_long_press_is_a_tap);
  RUN_TEST(test_a_flickering_touch_is_one_tap);
  RUN_TEST(test_a_moment_carries_its_expression);
  RUN_TEST(test_a_touch_ends_while_the_clock_is_frozen);
  RUN_TEST(test_a_frozen_clock_runs_again_after_60s_without_debug);
  RUN_TEST(test_shot_is_header_then_base64);
  RUN_TEST(test_light_sets_the_led);
  RUN_TEST(test_motion_redraws_at_most_every_16ms);
  RUN_TEST(test_a_still_picture_isnt_redrawn);
  RUN_TEST(test_the_redraw_cap_doesnt_delay_a_press);
  RUN_TEST(test_attention_shows_needs_you_and_chirps_once);
  RUN_TEST(test_no_app_after_30s_of_silence);
  RUN_TEST(test_moment_plays_then_ends_and_a_new_one_replaces_it);
  RUN_TEST(test_a_moment_with_nothing_to_play_is_ignored);
  RUN_TEST(test_a_strip_touch_is_a_tap);
  RUN_TEST(test_reset_forgets_the_mac_and_freezes_at_0);
  RUN_TEST(test_say_reaches_the_player);
  RUN_TEST(test_a_say_on_its_own_plays_the_mumble);
  RUN_TEST(test_mute_and_needs_you_keep_it_silent);
  RUN_TEST(test_only_needs_you_chirps);
  RUN_TEST(test_state_carries_the_mood);
  RUN_TEST(test_lines_over_512_bytes_are_dropped);
  RUN_TEST(test_say_and_volume_are_held_in_range);
  RUN_TEST(test_a_moment_with_an_id_is_answered_when_it_ends);
  return UNITY_END();
}
