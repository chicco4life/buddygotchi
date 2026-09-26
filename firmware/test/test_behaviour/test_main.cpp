// The behaviour state machine (plan/BEHAVIORS.md, plan/UX.md §3–4), with
// every timing checked to the millisecond.
#include <unity.h>

#include <cstring>
#include <string>
#include <vector>

#include "app/behaviour.h"
#include "app/device.h"

void setUp() {}
void tearDown() {}

using app::Behaviour;
using app::Life;
using app::Model;
using app::MomentIn;
using app::Screen;
using render::Anim;

namespace {

struct Rig {
  Behaviour b;
  app::Rng rng;
  uint32_t t = 0;
  Rig() { b.reset(0, rng); }
  void at(uint32_t to) {
    t = to;
    b.advance(t, rng);
  }
  void state(Model m) { b.onState(m, t, rng); }
  void moment(Anim a, int size = 1) {
    MomentIn m;
    m.anim = a, m.size = size;
    b.onMoment(m, t, rng);
  }
  Anim anim() {
    uint32_t left;
    return b.moment(t, left);
  }
  std::string sfx() {
    uint32_t at;
    const char* k = b.sfx(at);
    return k ? std::string(k) + "@" + std::to_string(at) : "";
  }
};

Model base(const char* b) {
  Model m;
  std::strcpy(m.base, b);
  return m;
}

Model attn(const char* project = "landing") {
  Model m = base("working");
  m.attn = true;
  std::strcpy(m.agent, "codex");
  std::strcpy(m.project, project);
  return m;
}

// Keeps the Mac talking every 10 s up to `to`, so "no app" stays away.
void keepAlive(Rig& r, const Model& m, uint32_t to) {
  while (r.t + 10000 <= to) {
    r.at(r.t + 10000);
    r.state(m);
  }
  r.at(to);
}

}  // namespace

static void test_ladder_rungs_chirps_and_pulses() {
  Rig r;
  r.at(1000);
  r.state(attn());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(1, r.b.rung(r.t));
  TEST_ASSERT_EQUAL_STRING("chirp@1000", r.sfx().c_str());
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));  // amber
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  keepAlive(r, attn(), 45999);
  TEST_ASSERT_EQUAL(1, r.b.rung(r.t));
  r.at(46000);
  TEST_ASSERT_EQUAL(2, r.b.rung(r.t));
  TEST_ASSERT_EQUAL_STRING("chirp@46000", r.sfx().c_str());
  keepAlive(r, attn(), 120999);
  TEST_ASSERT_EQUAL(2, r.b.rung(r.t));
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  r.at(121000);
  TEST_ASSERT_EQUAL(3, r.b.rung(r.t));
  TEST_ASSERT_EQUAL_STRING("pulse@121000", r.sfx().c_str());
  // Three strong pulses: on 200 ms, off 200 ms.
  uint32_t on[] = {121000, 121199, 121400, 121800, 121999};
  uint32_t off[] = {121200, 121399, 121600, 122000, 122199};
  for (uint32_t t : on) TEST_ASSERT_EQUAL_HEX32(0xFFB000, r.b.led(t));
  for (uint32_t t : off) TEST_ASSERT_EQUAL_HEX32(0, r.b.led(t));
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(122200));  // then stays amber, quietly
}

static void test_tap_hushes_nudges_and_nods() {
  Rig r;
  r.state(attn());
  r.at(10000);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_TRUE(r.b.hushed());
  TEST_ASSERT_EQUAL(Anim::kNod, r.anim());
  keepAlive(r, attn(), 125000);
  TEST_ASSERT_EQUAL(1, r.b.rung(r.t));  // the lean stopped climbing
  TEST_ASSERT_EQUAL_STRING("chirp@0", r.sfx().c_str());
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(121000));  // stays amber, no pulses
  // A new "needs you" starts again.
  r.state(attn("other"));
  TEST_ASSERT_FALSE(r.b.hushed());
  TEST_ASSERT_EQUAL(1, r.b.rung(r.t));
  TEST_ASSERT_EQUAL_STRING("chirp@125000", r.sfx().c_str());
}

static void test_answering_on_the_mac_nods_and_goes_back() {
  Rig r;
  r.state(attn());
  r.at(5000);
  r.state(base("working"));
  TEST_ASSERT_EQUAL(Anim::kNod, r.anim());
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  r.at(5000 + render::animDuration(Anim::kNod, 1));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

static void test_attention_wins_over_moments() {
  Rig r;
  r.state(base("working"));
  r.moment(Anim::kCheer, 3);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  r.at(100);
  r.state(attn());  // attention cuts the cheer
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kCheer, 2);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  MomentIn say;
  say.anim = Anim::kShrug, say.syllables = 3;
  r.b.onMoment(say, r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());  // a reply to you gets through
  TEST_ASSERT_NULL(r.b.mumble(r.t));           // but never a mumble
}

// The debug label's name (UX.md §2): the moment playing, else the look.
static void test_face_name_is_the_moment_or_the_look() {
  Rig r;
  r.state(base("working"));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL_STRING("cheer", r.b.faceName(r.t));
  r.at(render::animDuration(Anim::kCheer, 1));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL_STRING("idle", r.b.faceName(r.t));
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.faceName(r.t));
}

static void test_moments_end_replace_and_follow_pace_and_energy() {
  Rig r;
  r.state(base("idle"));
  r.moment(Anim::kOops);
  uint32_t d = render::animDuration(Anim::kOops, 1);
  r.at(d - 1);
  TEST_ASSERT_EQUAL(Anim::kOops, r.anim());
  r.at(d);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kCheer, 1);
  r.at(r.t + 10);
  r.moment(Anim::kWiggle);  // a new moment replaces the old one
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());

  Model fast = base("idle");
  fast.pace = 200, fast.energy = 150;  // pace clamps to 140
  r.state(fast);
  uint32_t start = r.t;
  r.moment(Anim::kCheer, 2);
  TEST_ASSERT_EQUAL_STRING(("jingle@" + std::to_string(start)).c_str(), r.sfx().c_str());
  uint32_t fastMs = render::animDuration(Anim::kCheer, 3) * 100 / 140;  // bigger and quicker
  r.at(start + fastMs - 1);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  TEST_ASSERT_EQUAL_HEX32(0xFF7020, r.b.led(r.t));  // warm light
  r.at(start + fastMs);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());

  Model tired = base("idle");
  tired.energy = 40;
  r.state(tired);
  start = r.t;
  r.moment(Anim::kCheer, 2);  // shrinks to size 1: no jingle, no light
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  r.at(start + render::animDuration(Anim::kCheer, 1));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

static void test_mumble_moves_the_mouth_and_respects_quiet() {
  Rig r;
  r.state(base("idle"));
  MomentIn m;
  m.anim = Anim::kHappy, m.syllables = 4, m.word = "done", m.at = 4, m.ms = 100;
  r.b.onMoment(m, r.t, r.rng);
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_EQUAL_STRING("done", r.b.mumble(r.t)->word);
  TEST_ASSERT_TRUE(r.b.speaking(599));  // (4 syllables + 2 for the word) × 100 ms
  TEST_ASSERT_FALSE(r.b.speaking(600));
  // Mid-syllable the mouth is open; between syllables it nearly closes.
  TEST_ASSERT_TRUE(r.b.pose(50).mouthOpen > r.b.pose(0).mouthOpen);
  TEST_ASSERT_TRUE(r.b.pose(150).mouthOpen > 500);

  Model q = base("idle");
  q.quiet = 5;
  r.at(5000);
  r.state(q);
  r.b.onMoment(m, r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kHappy, r.anim());
  TEST_ASSERT_NULL(r.b.mumble(r.t));
}

// Idle life: something every 2–6 s while idle, and blinks are the most common.
static void test_idle_life_every_2_to_6_seconds() {
  Rig r;
  r.state(base("idle"));
  std::vector<uint32_t> starts;
  int blinks = 0;
  Life prev = Life::kNone;
  for (uint32_t t = 1; t <= 120000; ++t) {
    if (t % 10000 == 0) r.at(t), r.state(base("idle"));
    r.at(t);
    Life l = r.b.life(t);
    if (l != Life::kNone) TEST_ASSERT_TRUE(r.b.moving(t));
    if (l != Life::kNone && prev == Life::kNone) {
      starts.push_back(t);
      blinks += l == Life::kBlink;
    }
    prev = l;
  }
  TEST_ASSERT_TRUE(starts.size() >= 20);
  TEST_ASSERT_TRUE(blinks * 2 >= int(starts.size()));
  for (size_t i = 1; i < starts.size(); ++i) {
    uint32_t gap = starts[i] - starts[i - 1];
    TEST_ASSERT_TRUE(gap >= 2000);
    TEST_ASSERT_TRUE(gap <= 6000 + 1600);  // the gap follows the last event
  }
}

static void test_asleep_breathes_and_never_blinks() {
  Rig r;
  r.state(base("asleep"));
  for (uint32_t t = 1; t <= 20000; t += 7) {
    if (t % 10000 < 7) r.state(base("asleep"));
    r.at(t);
    TEST_ASSERT_EQUAL(Life::kNone, r.b.life(t));
  }
  TEST_ASSERT_TRUE(r.b.moving(r.t));
  TEST_ASSERT_TRUE(r.b.pose(1000).size != r.b.pose(2000).size);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
}

static void test_working_strains_and_sweats_and_asleep_says_zzz() {
  // Effort: over one 2.6 s cycle the working face strains for part of it
  // and rests the rest, with a sweat drop the whole time (BEHAVIORS.md §2).
  Rig r;
  r.state(base("working"));
  int strained = 0, resting = 0;
  for (uint32_t t = 3000; t < 3000 + 2600; t += 10) {
    r.at(t);
    render::Pose p = r.b.pose(t);
    TEST_ASSERT_TRUE(p.sweat > 0);
    strained += p.squash >= 200;
    resting += p.squash == 0;
  }
  TEST_ASSERT_TRUE(strained >= 30);  // 0.3 s or more at full strain
  TEST_ASSERT_TRUE(resting >= 120);  // and most of the cycle at rest
  // Asleep, the "zzZZ" runs the whole time.
  Rig s;
  s.state(base("asleep"));
  for (uint32_t t = 1000; t < 6000; t += 50) {
    s.at(t);
    TEST_ASSERT_TRUE(s.b.pose(t).zzz > 0);
  }
  // Idle has neither.
  Rig i;
  i.state(base("idle"));
  i.at(3000);
  TEST_ASSERT_EQUAL_INT(0, i.b.pose(3000).sweat);
  TEST_ASSERT_EQUAL_INT(0, i.b.pose(3000).zzz);
}

static void test_no_app_at_30s_dims_and_reconnect_blinks() {
  Rig r;
  r.at(1000);
  r.state(base("idle"));
  r.at(30999);
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  r.at(31000);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(70, r.b.backlight(r.t));
  TEST_ASSERT_TRUE(r.b.strip(r.t).noApp);
  r.at(40000);
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(Life::kBlink, r.b.life(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
}

static void test_night_dims_but_never_hides_needs_you() {
  Rig r;
  Model m = base("idle");
  m.night = true;
  r.state(m);
  TEST_ASSERT_EQUAL(110, r.b.backlight(r.t));
  m = base("asleep"), m.night = true;
  r.state(m);
  TEST_ASSERT_EQUAL(40, r.b.backlight(r.t));
  m = attn(), m.night = true;
  r.state(m);
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
}

static void test_threads_close_after_10s_untouched() {
  Rig r;
  r.state(base("idle"));
  r.b.stripTap(0);
  TEST_ASSERT_EQUAL(Screen::kThreads, r.b.screen(0));
  r.at(5000);
  r.b.stripTap(5000);
  TEST_ASSERT_EQUAL(Screen::kStats, r.b.screen(5000));
  r.at(14999);
  TEST_ASSERT_EQUAL(Screen::kStats, r.b.screen(r.t));
  r.state(base("idle"));
  r.at(15000);
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  r.b.stripTap(r.t);
  r.b.contentTap(r.t + 100);
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t + 100));
  r.b.stripTap(r.t);
  r.state(attn());  // a new "needs you" wins over threads
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
}

static void test_push_to_talk_listens_thinks_then_shrugs() {
  Rig r;
  r.state(base("idle"));
  r.b.talkOn(0, r.rng);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.at(2000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.b.talkOff(2000, r.rng);
  TEST_ASSERT_EQUAL(Anim::kThinking, r.anim());
  r.at(2000 + render::animDuration(Anim::kThinking, 1));
  TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());  // no reply came
  // A reply replaces thinking.
  r.state(base("idle"));
  r.b.talkOff(r.t, r.rng);
  r.moment(Anim::kZip);
  TEST_ASSERT_EQUAL(Anim::kZip, r.anim());
}

// BEHAVIORS.md §3.3: listening lasts until release, capped at 30 s, and the
// device ends thinking with a shrug after 8 s. Those are timeouts, so the
// mood's pace (§1) doesn't stretch or shrink them; it still paces the shrug.
static void test_push_to_talk_timeouts_ignore_pace() {
  for (int pace : {70, 140}) {
    Rig r;
    Model m = base("idle");
    m.pace = pace;
    r.state(m);
    r.b.talkOn(0, r.rng);
    keepAlive(r, m, 29999);
    TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
    r.at(30000);
    TEST_ASSERT_EQUAL(Anim::kNone, r.anim());  // the cap
    r.b.talkOff(r.t, r.rng);
    const uint32_t start = r.t;
    keepAlive(r, m, start + 7999);
    TEST_ASSERT_EQUAL(Anim::kThinking, r.anim());
    r.at(start + 8000);
    TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());  // no reply came
    uint32_t shrug = render::animDuration(Anim::kShrug, 1) * 100 / uint32_t(pace);
    r.at(start + 8000 + shrug - 1);
    TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());
    r.at(start + 8000 + shrug);
    TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  }
}

// PLAN.md §6, morning checklist row 4: the no-app screen ignores a strip
// tap, so threads doesn't open later when a `state` arrives within 10 s.
static void test_strip_tap_on_no_app_is_ignored() {
  Rig r;
  r.state(base("idle"));
  r.at(30000);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  r.b.stripTap(r.t);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  r.at(35000);
  r.state(base("idle"));  // the Mac is back, 5 s after the tap
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  r.b.stripTap(r.t);  // and a tap cycles again
  TEST_ASSERT_EQUAL(Screen::kThreads, r.b.screen(r.t));
}

// UX.md §4: a press squashes the face within 20 ms, while something needs
// you too.
static void test_press_shows_within_20ms() {
  for (const Model& m : {base("idle"), attn()}) {
    Rig r;
    r.state(m);
    r.at(500);
    render::Pose before = r.b.pose(500);
    r.b.pressDown(500);
    TEST_ASSERT_TRUE(r.b.pose(516) != before);
    TEST_ASSERT_TRUE(r.b.moving(516));
  }
}

static void test_hunger_rumbles_and_never_lights_or_sounds() {
  Rig r;
  Model m = base("idle");
  m.hungry = 2;
  r.state(m);
  int rumbles = 0;
  Life prev = Life::kNone;
  for (uint32_t t = 1; t <= 300000; t += 5) {
    if (t % 10000 < 5) r.at(t), r.state(m);
    r.at(t);
    Life l = r.b.life(t);
    rumbles += l == Life::kRumble && prev != Life::kRumble;
    prev = l;
    TEST_ASSERT_EQUAL_HEX32(0, r.b.led(t));
  }
  TEST_ASSERT_TRUE(rumbles >= 3);
  TEST_ASSERT_EQUAL_STRING("", r.sfx().c_str());
}

// ---- Through the device core: gestures and the input messages ------------

namespace {

struct FakeHal : app::Hal {
  uint32_t realMs() override { return 0; }
  const char* fwVersion() override { return "t"; }
  const char* gitSha() override { return "t"; }
};
struct Capture : app::Out {
  std::string text;
  void write(const char* s, size_t n) override { text.append(s, n); }
};
struct DevRig {
  FakeHal hal;
  Capture usb;
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(render::kWidth) * render::kHeight);
  app::Device dev{hal, px.data(), true};
  DevRig() {
    dev.setOut(app::Link::kUsb, &usb);
    line("{\"t\":\"state\",\"base\":\"idle\"}");
  }
  void line(const char* s) {
    dev.handleLine(s, std::strlen(s), app::Link::kUsb);
    dev.tick();
  }
  void clock(uint32_t t) {
    std::string s = "{\"t\":\"dbg.clock\",\"freeze\":" + std::to_string(t) + "}";
    line(s.c_str());
  }
  bool has(const char* needle) const { return usb.text.find(needle) != std::string::npos; }
  // How many times the device has sent `needle` so far.
  int count(const char* needle) const {
    int n = 0;
    for (size_t at = usb.text.find(needle); at != std::string::npos; at = usb.text.find(needle, at + 1)) ++n;
    return n;
  }
};

const char* const kInput = "{\"t\":\"input\"";
const char* const kTap = "{\"t\":\"input\",\"k\":\"tap\"}";

}  // namespace

// UX.md §4: a touch acts when it's released, however long it was held. On
// the face it's a tap, sent to the Mac; on the strip it cycles the screens,
// and on threads or stats it goes back to the face, both without a word to
// the Mac.
static void test_gestures_send_the_right_inputs() {
  DevRig r;
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":100}");  // tap the face
  r.clock(100);
  TEST_ASSERT_EQUAL(1, r.count(kTap));
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"anim\":\"wiggle\""));

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":900}");  // a long touch on the face
  r.clock(999);
  TEST_ASSERT_EQUAL(1, r.count(kInput));  // nothing while it's held
  r.clock(1000);
  TEST_ASSERT_EQUAL(2, r.count(kTap));  // released: a tap, like a short one
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"moment\":{\"anim\":\"wiggle\",\"left_ms\":700}"));
  TEST_ASSERT_TRUE(r.has("\"last_input\":{\"k\":\"tap\",\"at\":1000}"));

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":900}");  // a long touch on the strip
  r.clock(1899);
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  r.clock(1900);
  TEST_ASSERT_EQUAL(app::Screen::kThreads, r.dev.screen());  // released: a strip tap

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":100}");  // tap the strip
  r.clock(2000);
  TEST_ASSERT_EQUAL(app::Screen::kStats, r.dev.screen());
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":100}");  // tap the stats
  r.clock(2100);
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());
  TEST_ASSERT_EQUAL(2, r.count(kInput));  // only the two taps on the face reached the Mac
}

// A long touch on the face while something needs you is a tap too: it
// quiets the nudges, Boop nods, and the Mac hears `tap` (BEHAVIORS.md §3.2).
static void test_a_long_touch_during_needs_you_is_a_tap() {
  DevRig r;
  r.line("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":1500}");
  r.clock(1499);
  TEST_ASSERT_EQUAL(0, r.count(kInput));
  r.clock(1500);
  TEST_ASSERT_EQUAL(1, r.count(kTap));
  r.usb.text.clear();
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"screen\":\"needs_you\""));
  TEST_ASSERT_TRUE(r.has("\"hushed\":true"));
  TEST_ASSERT_TRUE(r.has("\"moment\":{\"anim\":\"nod\""));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_ladder_rungs_chirps_and_pulses);
  RUN_TEST(test_tap_hushes_nudges_and_nods);
  RUN_TEST(test_answering_on_the_mac_nods_and_goes_back);
  RUN_TEST(test_attention_wins_over_moments);
  RUN_TEST(test_face_name_is_the_moment_or_the_look);
  RUN_TEST(test_moments_end_replace_and_follow_pace_and_energy);
  RUN_TEST(test_mumble_moves_the_mouth_and_respects_quiet);
  RUN_TEST(test_idle_life_every_2_to_6_seconds);
  RUN_TEST(test_asleep_breathes_and_never_blinks);
  RUN_TEST(test_working_strains_and_sweats_and_asleep_says_zzz);
  RUN_TEST(test_no_app_at_30s_dims_and_reconnect_blinks);
  RUN_TEST(test_night_dims_but_never_hides_needs_you);
  RUN_TEST(test_threads_close_after_10s_untouched);
  RUN_TEST(test_push_to_talk_listens_thinks_then_shrugs);
  RUN_TEST(test_push_to_talk_timeouts_ignore_pace);
  RUN_TEST(test_strip_tap_on_no_app_is_ignored);
  RUN_TEST(test_press_shows_within_20ms);
  RUN_TEST(test_hunger_rumbles_and_never_lights_or_sounds);
  RUN_TEST(test_gestures_send_the_right_inputs);
  RUN_TEST(test_a_long_touch_during_needs_you_is_a_tap);
  return UNITY_END();
}
