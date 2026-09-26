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
  uint32_t realMs() override { return real; }
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

// The stretch and the yawn left the set (BEHAVIORS.md §7), so an older Mac
// app's `stretch` or `yawn` is an unknown animation, ignored like any other:
// nothing plays, its mumble is dropped with it, and a moment already playing
// carries on.
static void test_stretch_and_yawn_are_unknown_and_ignored() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  for (const char* anim : {"stretch", "yawn"}) {
    std::string m = std::string("{\"t\":\"moment\",\"anim\":\"") + anim +
                    "\",\"size\":2,\"say\":{\"syl\":\"ba po\",\"ms\":100},\"ttl\":5}";
    r.usbLine(m.c_str());
    r.usb.text.clear();
    r.usbLine("{\"t\":\"dbg.state\"}");
    TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":null"));
  }
  TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
  r.usbLine("{\"t\":\"moment\",\"anim\":\"nod\",\"size\":1,\"ttl\":5}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"yawn\",\"size\":1,\"ttl\":5}");
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"moment\":{\"anim\":\"nod\",\"left_ms\":600}"));
}

static void test_strip_taps_cycle_the_screens() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  const app::Screen order[] = {app::Screen::kThreads, app::Screen::kStats, app::Screen::kFace};
  uint32_t t = 0;
  for (app::Screen want : order) {
    r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":100}");
    t += 200;
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
    TEST_ASSERT_EQUAL(want, r.dev.screen());
  }
  // A touch on the face doesn't change the screen.
  r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":100}");
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

// F5: a moment's mumble reaches the player with its syllables, word, tune
// and tempo, and the player follows volume, quiet and needs you.
static void test_say_reaches_the_player() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":7,\"mood\":{\"pitch\":120}}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":1,\"say\":{\"syl\":\"bi-do ba zz\",\"word\":\"done\",\"at\":4,\"tune\":\"up\",\"ms\":110},\"ttl\":5}");
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
  TEST_ASSERT_EQUAL(120, l.pitch);
  TEST_ASSERT_EQUAL(7, l.vol);
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"syllables\":4,\"out\":{"));
  // A tap's wiggle replaces the moment, and with it the line.
  r.usbLine("{\"t\":\"dbg.press\",\"ms\":50}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":100}");
  TEST_ASSERT_EQUAL(1, r.hal.hushes);
}

static void test_mute_quiet_and_needs_you_keep_it_silent() {
  const char* states[] = {
      "{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}",
      "{\"t\":\"state\",\"base\":\"idle\",\"quiet\":30}",
      "{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}",
  };
  for (const char* st : states) {
    Rig r;
    r.usbLine(st);
    r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":2,\"say\":{\"syl\":\"ba\",\"ms\":100}}");
    TEST_ASSERT_EQUAL(0, int(r.hal.said.size()));
  }
  // Muted, the mouth still moves: only the sound goes.
  Rig r;
  r.usbLine(states[0]);
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":1,\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"audio\":{\"playing\":true,\"syllables\":2"));
  // A line stops when quiet arrives mid-line.
  Rig q;
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  q.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":1,\"say\":{\"syl\":\"ba po\",\"ms\":100}}");
  TEST_ASSERT_EQUAL(1, int(q.hal.said.size()));
  q.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"quiet\":30}");
  TEST_ASSERT_EQUAL(1, q.hal.hushes);
}

// Focus mode is gone. An older Mac app may still send `focus` in `state`;
// like any unknown field it's ignored (PROTOCOL.md §2): Boop still mumbles,
// plays the jingle and chirps for "needs you", and shows and reports exactly
// what it would without it.
static void test_focus_from_an_older_mac_is_ignored() {
  auto play = [](Rig& r, bool focus) {
    std::string f = focus ? ",\"focus\":true" : "";
    r.usbLine(("{\"t\":\"state\",\"base\":\"idle\"" + f + "}").c_str());
    r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":2,\"say\":{\"syl\":\"ba po\",\"ms\":100},\"ttl\":5}");
    r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":3000}");
    r.usbLine(("{\"t\":\"state\",\"base\":\"idle\"" + f + ",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}").c_str());
    r.usbLine("{\"t\":\"dbg.state\"}");
  };
  Rig older, plain;
  play(older, true);
  play(plain, false);
  TEST_ASSERT_EQUAL(1, int(older.hal.said.size()));  // the mumble
  TEST_ASSERT_EQUAL(2, int(older.hal.cues.size()));
  TEST_ASSERT_TRUE(older.hal.cues[0] == voice::Cue::kJingle);  // once the line ends
  TEST_ASSERT_TRUE(older.hal.cues[1] == voice::Cue::kChirp);   // needs you
  TEST_ASSERT_FALSE(has(older.usb.text, "focus"));
  TEST_ASSERT_EQUAL_STRING(plain.usb.text.c_str(), older.usb.text.c_str());
  TEST_ASSERT_EQUAL_MEMORY(plain.px.data(), older.px.data(), plain.px.size());
}

static void test_cues_follow_the_behaviour() {
  Rig r;
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  r.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":2}");
  TEST_ASSERT_EQUAL(1, int(r.hal.cues.size()));
  TEST_ASSERT_TRUE(r.hal.cues[0] == voice::Cue::kJingle);
  // Needs you: the chirp at 45 s.
  r.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  r.usbLine("{\"t\":\"dbg.clock\",\"step\":45000}");
  TEST_ASSERT_EQUAL(2, int(r.hal.cues.size()));
  TEST_ASSERT_TRUE(r.hal.cues[1] == voice::Cue::kChirp);
  // With a line playing, the jingle waits it out.
  Rig s;
  s.usbLine("{\"t\":\"state\",\"base\":\"idle\"}");
  s.usbLine("{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":2,\"say\":{\"syl\":\"ba\",\"ms\":100}}");
  TEST_ASSERT_EQUAL(1, int(s.hal.said.size()));
  TEST_ASSERT_EQUAL(0, int(s.hal.cues.size()));
}

// VOICE.md §8: a cue that arrives during a line waits it out, then plays
// once. A newer cue replaces a waiting one, and mute drops it.
static void test_a_cue_during_a_line_waits_it_out() {
  const char* idle = "{\"t\":\"state\",\"base\":\"idle\"}";
  // Two beats of 100 ms: the line plays from 0 to 200 ms.
  const char* cheer = "{\"t\":\"moment\",\"anim\":\"cheer\",\"size\":2,\"say\":{\"syl\":\"ba po\",\"ms\":100}}";
  Rig r;
  r.usbLine(idle);
  r.usbLine(cheer);
  TEST_ASSERT_EQUAL(1, int(r.hal.said.size()));
  TEST_ASSERT_EQUAL(0, int(r.hal.cues.size()));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":199}");
  TEST_ASSERT_EQUAL(0, int(r.hal.cues.size()));
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":200}");
  TEST_ASSERT_EQUAL(1, int(r.hal.cues.size()));
  TEST_ASSERT_TRUE(r.hal.cues[0] == voice::Cue::kJingle);
  TEST_ASSERT_EQUAL(0, r.hal.hushes);  // the line wasn't cut for it
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":3000}");
  TEST_ASSERT_EQUAL(1, int(r.hal.cues.size()));  // once

  // Needs you arrives mid-line: its chirp replaces the waiting jingle.
  Rig n;
  n.usbLine(idle);
  n.usbLine(cheer);
  n.usbLine("{\"t\":\"dbg.clock\",\"freeze\":100}");
  n.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"attn\":{\"agent\":\"claude\",\"project\":\"x\"}}");
  n.usbLine("{\"t\":\"dbg.clock\",\"freeze\":3000}");
  TEST_ASSERT_EQUAL(1, int(n.hal.cues.size()));
  TEST_ASSERT_TRUE(n.hal.cues[0] == voice::Cue::kChirp);

  // Mute arrives mid-line: the waiting jingle is dropped.
  Rig m;
  m.usbLine(idle);
  m.usbLine(cheer);
  m.usbLine("{\"t\":\"dbg.clock\",\"freeze\":100}");
  m.usbLine("{\"t\":\"state\",\"base\":\"idle\",\"vol\":0}");
  m.usbLine("{\"t\":\"dbg.clock\",\"freeze\":3000}");
  TEST_ASSERT_EQUAL(0, int(m.hal.cues.size()));
}

// PROTOCOL.md §3 and the ARCHITECTURE.md §11 decision log: the Mac clips
// `name` to 23 bytes on a character boundary, for 24-byte fields on the
// device. A 23-byte name reaches the stats screen whole. This one is 18
// glyphs (five 2-byte "·"), the most the stats name area holds (UX.md §3).
static void test_a_23_byte_name_reaches_the_stats_screen_whole() {
  const char* name = "Pip\xC2\xB7" "Bo\xC2\xB7" "Kit\xC2\xB7" "Mo\xC2\xB7" "Ze\xC2\xB7" "D";
  TEST_ASSERT_EQUAL(23, int(std::strlen(name)));
  Rig r;
  std::string st = std::string("{\"t\":\"state\",\"base\":\"idle\",\"name\":\"") + name + "\"}";
  r.usbLine(st.c_str());
  for (uint32_t t : {200u, 400u}) {  // two strip taps: threads, then stats
    r.usbLine("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":100}");
    char step[64];
    std::snprintf(step, sizeof(step), "{\"t\":\"dbg.clock\",\"freeze\":%u}", unsigned(t));
    r.usbLine(step);
  }
  TEST_ASSERT_EQUAL(app::Screen::kStats, r.dev.screen());
  std::vector<uint8_t> px(size_t(render::kWidth) * render::kHeight);
  render::Canvas want(px.data());
  render::Stats stats;
  stats.name = name;
  render::drawStats(want, stats, render::Strip{});
  TEST_ASSERT_EQUAL_MEMORY(px.data(), r.dev.canvas().pixels(), px.size());
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
  RUN_TEST(test_shot_is_header_then_base64);
  RUN_TEST(test_light_sets_the_led);
  RUN_TEST(test_attention_shows_needs_you_and_climbs_the_ladder);
  RUN_TEST(test_no_app_after_30s_of_silence);
  RUN_TEST(test_moment_plays_then_ends_and_a_new_one_replaces_it);
  RUN_TEST(test_stretch_and_yawn_are_unknown_and_ignored);
  RUN_TEST(test_strip_taps_cycle_the_screens);
  RUN_TEST(test_reset_forgets_the_mac_and_freezes_at_0);
  RUN_TEST(test_say_reaches_the_player);
  RUN_TEST(test_mute_quiet_and_needs_you_keep_it_silent);
  RUN_TEST(test_focus_from_an_older_mac_is_ignored);
  RUN_TEST(test_cues_follow_the_behaviour);
  RUN_TEST(test_a_cue_during_a_line_waits_it_out);
  RUN_TEST(test_a_23_byte_name_reaches_the_stats_screen_whole);
  RUN_TEST(test_lines_over_512_bytes_are_dropped);
  RUN_TEST(test_no_battery_reports_bat_0);
  return UNITY_END();
}
