// The device core's debug channel and inputs, through the same Hal the
// simulator uses.
#include <unity.h>

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "app/device.h"
#include "app/line_reader.h"
#include "board/pins.h"
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

// VERIFICATION.md §3: a clock a tool froze runs again after 60 s with no
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
// 16 ms of real time, however fast the loop runs. A frozen clock redraws
// on every step, so scenario frames stay exact.
static void test_motion_redraws_at_most_every_16ms() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"asleep\"}");  // breathing: always moving
  r.usbLine("{\"t\":\"dbg.clock\",\"run\":true}");
  r.dev.takeFrame();
  int frames = 0;
  for (int ms = 0; ms < 1000; ++ms) {
    ++r.hal.real;
    r.dev.tick();
    frames += r.dev.takeFrame();
  }
  TEST_ASSERT_EQUAL(1000 / 16, frames);
  frames = 0;
  for (int step = 0; step < 20; ++step) {
    r.usbLine("{\"t\":\"dbg.clock\",\"step\":1}");
    frames += r.dev.takeFrame();
  }
  TEST_ASSERT_EQUAL(20, frames);
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
    TEST_ASSERT_TRUE_MESSAGE(frozen > 0, base);
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

// PROTOCOL.md §3: the empty moment {"t":"moment","ttl":5} ends listening
// and does nothing else; an unknown anim alone isn't the empty moment.
static void test_the_empty_moment_ends_listening() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"listening\",\"ttl\":5}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"shrug\",\"ttl\":5}");  // removed: ignored
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"listening\""));
  r.usbLine("{\"t\":\"moment\",\"ttl\":5}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rx\":{\"state\":1,\"moment\":3}"));
  // It never ends a cheer.
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"ttl\":5}");
  r.usbLine("{\"t\":\"moment\",\"ttl\":5}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"cheer\""));
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
// and tempo, and the player follows volume, quiet and needs you.
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

static void test_mute_quiet_and_needs_you_keep_it_silent() {
  const char* states[] = {
      "{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"idle\",\"quiet\":30}",
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
  // A line stops when quiet arrives mid-line.
  Rig q;
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  q.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  TEST_ASSERT_EQUAL(1, int(q.hal.said.size()));
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"quiet\":30}");
  TEST_ASSERT_EQUAL(1, q.hal.hushes);
}

// BEHAVIORS.md §4: the chirp is the only cue. A cheer plays none.
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

// dbg.state carries nothing for the parked features (the cut, 2026-09-26).
static void test_state_has_no_parked_fields() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"mood\":{\"energy\":40},\"focus\":true,\"night\":true,\"hungry\":2,"
            "\"level\":3,\"threads\":[[\"claude\",\"x\",\"work\"]]}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"screen\":\"face\""));
  for (const char* gone : {"\"rung\"", "\"hushed\"", "\"focus\"", "\"night\"", "\"hungry\"", "\"mood\"", "\"level\""}) {
    TEST_ASSERT_FALSE_MESSAGE(has(r.usb.text, gone), gone);
  }
  TEST_ASSERT_EQUAL(255, r.hal.bl);  // no night dimming
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

// PROTOCOL.md §4 and DEVICE.md §3: the v1 board has no battery, so `bat` is
// 0 (not a reading of the floating sense pin), and the field is still sent.
// BoardHal::batteryMv only builds for the board; this pins the setting it
// follows and the messages that carry it.
static void test_no_battery_reports_bat_0() {
  TEST_ASSERT_FALSE(pins::kHasBattery);
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");  // the Mac speaks: a status
  TEST_ASSERT_TRUE(has(r.usb.text, "\"bat\":0,\"usb\":1}"));
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"bat\":0,"));
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
  RUN_TEST(test_pattern_until_next_state);
  RUN_TEST(test_injected_tap_reaches_the_mac);
  RUN_TEST(test_physical_hold_sends_talk_on_and_off);
  RUN_TEST(test_a_frozen_clock_runs_again_after_60s_without_debug);
  RUN_TEST(test_shot_is_header_then_base64);
  RUN_TEST(test_light_sets_the_led);
  RUN_TEST(test_motion_redraws_at_most_every_16ms);
  RUN_TEST(test_the_redraw_cap_doesnt_delay_a_press);
  RUN_TEST(test_attention_shows_needs_you_and_chirps_once);
  RUN_TEST(test_no_app_after_30s_of_silence);
  RUN_TEST(test_moment_plays_then_ends_and_a_new_one_replaces_it);
  RUN_TEST(test_the_empty_moment_ends_listening);
  RUN_TEST(test_a_strip_touch_is_a_tap);
  RUN_TEST(test_reset_forgets_the_mac_and_freezes_at_0);
  RUN_TEST(test_say_reaches_the_player);
  RUN_TEST(test_a_say_on_its_own_plays_the_mumble);
  RUN_TEST(test_mute_quiet_and_needs_you_keep_it_silent);
  RUN_TEST(test_only_needs_you_chirps);
  RUN_TEST(test_state_has_no_parked_fields);
  RUN_TEST(test_lines_over_512_bytes_are_dropped);
  RUN_TEST(test_no_battery_reports_bat_0);
  return UNITY_END();
}
