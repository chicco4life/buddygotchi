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
  void moment(Anim a) {
    MomentIn m;
    m.anim = a;
    b.onMoment(m, t, rng);
  }
  // A mumble on its own: `syl` syllables of 100 ms, no word.
  bool say(int syl = 4) {
    MomentIn m;
    m.syllables = syl, m.ms = 100;
    return b.onMoment(m, t, rng);
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

// BEHAVIORS.md §3.2: one chirp when a request starts, amber at half until
// it's answered, and nothing grows or nudges while it waits.
static void test_needs_you_chirps_once_and_stays_amber() {
  Rig r;
  r.at(1000);
  r.state(attn());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_STRING("chirp@1000", r.sfx().c_str());
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  r.at(2000);
  const render::Pose first = r.b.pose(r.t);
  for (uint32_t t = 10000; t <= 300000; t += 10000) {
    r.at(t);
    r.state(attn());  // the same request: no second chirp
    TEST_ASSERT_EQUAL_STRING("chirp@1000", r.sfx().c_str());
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t));
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t + 5000));
    TEST_ASSERT_EQUAL(first.size, r.b.pose(t).size);  // the lean doesn't grow
    TEST_ASSERT_EQUAL(first.dy, r.b.pose(t).dy);
  }
  // A different request chirps once more.
  r.state(attn("other"));
  TEST_ASSERT_EQUAL_STRING("chirp@300000", r.sfx().c_str());
}

static void test_tap_during_needs_you_nods_and_stays_amber() {
  Rig r;
  r.state(attn());
  r.at(10000);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kNod, r.anim());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  keepAlive(r, attn(), 125000);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  TEST_ASSERT_EQUAL_STRING("chirp@0", r.sfx().c_str());
}

static void test_answering_on_the_mac_nods_and_goes_back() {
  Rig r;
  r.state(attn());
  r.at(5000);
  r.state(base("working"));
  TEST_ASSERT_EQUAL(Anim::kNod, r.anim());
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  r.at(5000 + render::animDuration(Anim::kNod));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

// BEHAVIORS.md §1: while something needs you, only nod, listening,
// thinking and shrug play, and no mumble shows.
static void test_attention_wins_over_moments() {
  Rig r;
  r.state(base("working"));
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  r.at(100);
  r.state(attn());  // attention cuts the cheer
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kWiggle);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_FALSE(r.say());  // a mumble on its own is ignored
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  MomentIn say;
  say.anim = Anim::kShrug, say.syllables = 3;
  r.b.onMoment(say, r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());  // a reply to you gets through
  TEST_ASSERT_NULL(r.b.mumble(r.t));           // but never a mumble
  // A mumble that was showing goes when something starts needing you.
  Rig m;
  m.state(base("idle"));
  TEST_ASSERT_TRUE(m.say());
  m.at(100);
  m.state(attn());
  TEST_ASSERT_NULL(m.b.mumble(m.t));
}

// The debug label's name (UX.md §2): the animation playing, else the look.
static void test_face_name_is_the_moment_or_the_look() {
  Rig r;
  r.state(base("working"));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL_STRING("cheer", r.b.faceName(r.t));
  r.at(render::animDuration(Anim::kCheer));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.say();  // a mumble doesn't change the face
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL_STRING("idle", r.b.faceName(r.t));
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.faceName(r.t));
}

// BEHAVIORS.md §5: the cheer is one size and lasts 2 s, with no light and
// no sound; a new moment replaces the one playing.
static void test_moments_end_and_replace() {
  Rig r;
  r.state(base("idle"));
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL_UINT32(2000, render::animDuration(Anim::kCheer));
  r.at(1999);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL_STRING("", r.sfx().c_str());
  r.at(2000);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  r.moment(Anim::kCheer);
  r.at(r.t + 10);
  r.moment(Anim::kWiggle);  // a new moment replaces the old one
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());
  const uint32_t start = r.t;
  r.at(start + 699);
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());
  r.at(start + 700);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

static void test_mumble_moves_the_mouth_and_respects_quiet() {
  Rig r;
  r.state(base("idle"));
  MomentIn m;
  m.anim = Anim::kCheer, m.syllables = 4, m.word = "done", m.at = 4, m.ms = 100;
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
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_FALSE(r.say());
}

// PROTOCOL.md §3, BEHAVIORS.md §5: a mumble on its own plays over whatever
// face is showing and doesn't change it. The bubble stays for the syllables
// and 1.2 s to read.
static void test_a_mumble_alone_plays_over_the_face() {
  Rig r;
  r.state(base("working"));
  r.at(1000);
  TEST_ASSERT_TRUE(r.say(4));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  TEST_ASSERT_TRUE(r.b.speaking(1399));
  TEST_ASSERT_FALSE(r.b.speaking(1400));
  TEST_ASSERT_TRUE(r.b.pose(1050).mouthOpen > r.b.pose(1000).mouthOpen);
  TEST_ASSERT_TRUE(r.b.moving(1500));
  r.at(1000 + 400 + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  r.at(1000 + 400 + Behaviour::kBubbleReadMs);
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_EQUAL(0, r.b.pose(r.t + render::kBlendMs).raise);  // back down once the bubble goes

  // Over a cheer, the cheer keeps its own timing.
  r.at(10000);
  r.moment(Anim::kCheer);
  r.at(10500);
  r.say(2);
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kCheer, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(1500, left);
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  // A tap's wiggle replaces the moment, and the mumble with it.
  r.at(10600);
  r.b.tap(r.t, r.rng);
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());
  TEST_ASSERT_NULL(r.b.mumble(r.t));

  // An empty mumble is nothing.
  Rig e;
  e.state(base("idle"));
  TEST_ASSERT_FALSE(e.say(0));
  TEST_ASSERT_EQUAL(0u, e.b.momentSeq());
}

// BEHAVIORS.md §3.3: the reply to push-to-talk, a mumble on its own, ends
// listening or thinking, so no "hmm?" shrug follows.
static void test_a_reply_ends_thinking_without_a_shrug() {
  Rig r;
  r.state(base("idle"));
  r.b.talkOn(0, r.rng);
  r.at(1000);
  r.b.talkOff(1000, r.rng);
  r.at(3000);
  TEST_ASSERT_TRUE(r.say(3));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  keepAlive(r, base("idle"), 1000 + 8000 + 100);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // It ends listening too.
  r.b.talkOn(r.t, r.rng);
  r.at(r.t + 500);
  r.say(2);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

// Starts of blinks between 0 and `to` ms, with the Mac sending `m` every
// 10 s (or never, for no app).
std::vector<uint32_t> blinkStarts(const Model& m, bool mac, uint32_t to) {
  Rig r;
  r.state(m);
  std::vector<uint32_t> starts;
  Life prev = Life::kNone;
  for (uint32_t t = 1; t <= to; ++t) {
    if (mac && t % 10000 == 0) r.at(t), r.state(m);
    r.at(t);
    Life l = r.b.life(t);
    if (l != Life::kNone) TEST_ASSERT_TRUE(r.b.moving(t));
    if (l != Life::kNone && prev == Life::kNone) starts.push_back(t);
    TEST_ASSERT_TRUE(l == Life::kNone || l == Life::kBlink);
    prev = l;
  }
  return starts;
}

void checkGaps(const std::vector<uint32_t>& starts, uint32_t from, uint32_t lo, uint32_t hi) {
  int n = 0;
  for (size_t i = 1; i < starts.size(); ++i) {
    if (starts[i - 1] < from) continue;
    uint32_t gap = starts[i] - starts[i - 1];
    TEST_ASSERT_TRUE(gap >= lo + Behaviour::kBlinkMs);  // the gap follows the blink
    TEST_ASSERT_TRUE(gap <= hi + Behaviour::kBlinkMs);
    ++n;
  }
  TEST_ASSERT_TRUE(n >= 5);
}

// BEHAVIORS.md §2: idle and working life is blinks only, every 2–6 s idle,
// 2–5 s working (1.2–3.5 s with 3 or more busy), and 5–9 s with no app.
static void test_life_is_blinks_at_their_pace() {
  checkGaps(blinkStarts(base("idle"), true, 120000), 0, 2000, 6000);
  Model w = base("working");
  w.busy = 1;
  checkGaps(blinkStarts(w, true, 120000), 0, 2000, 5000);
  w.busy = 3;
  checkGaps(blinkStarts(w, true, 120000), 0, 1200, 3500);
  checkGaps(blinkStarts(base("idle"), false, 180000), 40000, 5000, 9000);
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

static void test_push_to_talk_listens_thinks_then_shrugs() {
  Rig r;
  r.state(base("idle"));
  r.b.talkOn(0, r.rng);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.at(2000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.b.talkOff(2000, r.rng);
  TEST_ASSERT_EQUAL(Anim::kThinking, r.anim());
  r.at(2000 + render::animDuration(Anim::kThinking));
  TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());  // no reply came
  // A moment from the Mac replaces thinking.
  r.state(base("idle"));
  r.b.talkOff(r.t, r.rng);
  r.moment(Anim::kNod);
  TEST_ASSERT_EQUAL(Anim::kNod, r.anim());
}

// BEHAVIORS.md §3.3: listening lasts until release, capped at 30 s, and the
// device ends thinking with a shrug after 8 s; the shrug lasts 1.2 s.
static void test_push_to_talk_timeouts() {
  Rig r;
  Model m = base("idle");
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
  r.at(start + 8000 + 1199);
  TEST_ASSERT_EQUAL(Anim::kShrug, r.anim());
  r.at(start + 8000 + 1200);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
}

static void test_press_shows_within_20ms() {
  Rig r;
  r.state(base("idle"));
  r.at(500);
  render::Pose before = r.b.pose(500);
  r.b.pressDown(500);
  TEST_ASSERT_TRUE(r.b.pose(516) != before);
  TEST_ASSERT_TRUE(r.b.moving(516));
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
  int count(const char* needle) const {
    int n = 0;
    for (size_t at = usb.text.find(needle); at != std::string::npos; at = usb.text.find(needle, at + 1)) ++n;
    return n;
  }
};

}  // namespace

const char* const kTap = "{\"t\":\"input\",\"k\":\"tap\"}";
const char* const kTalkOn = "{\"t\":\"input\",\"k\":\"talk_on\"}";
const char* const kTalkOff = "{\"t\":\"input\",\"k\":\"talk_off\"}";

// UX.md §4: BOOT tap is a tap and a hold is push-to-talk; a touch anywhere,
// the strip included, is a tap sent on release, however long it was held.
static void test_gestures_send_the_right_inputs() {
  DevRig r;
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":100}");  // tap the face
  r.clock(100);
  TEST_ASSERT_EQUAL(1, r.count(kTap));
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"anim\":\"wiggle\""));

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":2000}");  // a long touch on the face
  r.clock(1500);
  TEST_ASSERT_EQUAL(1, r.count(kTap));  // nothing yet
  r.clock(2100);
  TEST_ASSERT_EQUAL(2, r.count(kTap));  // a tap, on release

  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":222,\"ms\":800}");  // hold the strip
  r.clock(3000);
  TEST_ASSERT_EQUAL(3, r.count(kTap));
  TEST_ASSERT_EQUAL(app::Screen::kFace, r.dev.screen());

  r.line("{\"t\":\"dbg.press\",\"ms\":100}");  // BOOT tap
  r.clock(3200);
  TEST_ASSERT_EQUAL(4, r.count(kTap));
  r.clock(3300);
  r.line("{\"t\":\"dbg.press\",\"ms\":800}");  // BOOT hold
  r.clock(3700);
  TEST_ASSERT_TRUE(r.has(kTalkOn));
  r.clock(4100);
  TEST_ASSERT_TRUE(r.has(kTalkOff));
  // Only these three inputs exist (PROTOCOL.md §4).
  TEST_ASSERT_EQUAL(r.count("\"t\":\"input\""),
                    r.count(kTap) + r.count(kTalkOn) + r.count(kTalkOff));
}

// A long touch during needs you is a tap too: a nod.
static void test_a_long_touch_during_needs_you_nods() {
  DevRig r;
  r.line("{\"t\":\"state\",\"base\":\"working\",\"attn\":{\"agent\":\"codex\",\"project\":\"landing\"}}");
  r.line("{\"t\":\"dbg.touch\",\"x\":160,\"y\":100,\"ms\":800}");
  r.clock(700);
  TEST_ASSERT_FALSE(r.has(kTap));
  r.clock(800);
  TEST_ASSERT_TRUE(r.has(kTap));
  r.usb.text.clear();
  r.line("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(r.has("\"screen\":\"needs_you\""));
  TEST_ASSERT_TRUE(r.has("\"moment\":{\"anim\":\"nod\""));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_needs_you_chirps_once_and_stays_amber);
  RUN_TEST(test_tap_during_needs_you_nods_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_nods_and_goes_back);
  RUN_TEST(test_attention_wins_over_moments);
  RUN_TEST(test_face_name_is_the_moment_or_the_look);
  RUN_TEST(test_moments_end_and_replace);
  RUN_TEST(test_mumble_moves_the_mouth_and_respects_quiet);
  RUN_TEST(test_a_mumble_alone_plays_over_the_face);
  RUN_TEST(test_a_reply_ends_thinking_without_a_shrug);
  RUN_TEST(test_life_is_blinks_at_their_pace);
  RUN_TEST(test_asleep_breathes_and_never_blinks);
  RUN_TEST(test_working_strains_and_sweats_and_asleep_says_zzz);
  RUN_TEST(test_no_app_at_30s_dims_and_reconnect_blinks);
  RUN_TEST(test_push_to_talk_listens_thinks_then_shrugs);
  RUN_TEST(test_push_to_talk_timeouts);
  RUN_TEST(test_press_shows_within_20ms);
  RUN_TEST(test_gestures_send_the_right_inputs);
  RUN_TEST(test_a_long_touch_during_needs_you_nods);
  return UNITY_END();
}
