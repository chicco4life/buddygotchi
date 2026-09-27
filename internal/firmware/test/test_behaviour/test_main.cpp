// The behaviour state machine (plan/BEHAVIORS.md, plan/UX.md §3–4), with
// every timing checked to the millisecond.
#include <unity.h>

#include <cstdio>
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
using render::SceneShow;
using render::SceneState;

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
  void state(Model m) { b.onState(m, t); }
  void moment(Anim a) {
    MomentIn m;
    m.anim = a;
    b.onMoment(m, t);
  }
  // A mumble on its own: `syl` syllables of 100 ms, no word.
  bool say(int syl = 4) {
    MomentIn m;
    m.syllables = syl, m.ms = 100;
    return b.onMoment(m, t);
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
  r.at(3000);  // the design's lean toward you has played out (1.6 s)
  SceneShow first = r.b.show(r.t);
  TEST_ASSERT_TRUE(first.state == SceneState::kNeedsYou);
  first.eyesShut = false;
  for (uint32_t t = 10000; t <= 300000; t += 10000) {
    r.at(t);
    r.state(attn());  // the same request: no second chirp
    TEST_ASSERT_EQUAL_STRING("chirp@1000", r.sfx().c_str());
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t));
    TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(t + 5000));
    SceneShow now = r.b.show(t);
    now.eyesShut = false;  // blinks go on
    TEST_ASSERT_TRUE(render::sceneFrame(first) == render::sceneFrame(now));  // nothing else moves
  }
  // A different request chirps once more.
  r.state(attn("other"));
  TEST_ASSERT_EQUAL_STRING("chirp@300000", r.sfx().c_str());
}

// BEHAVIORS.md §3.2: a tap while something needs you is the press dip
// only, with no moment, and it stays amber.
static void test_tap_during_needs_you_is_only_the_dip_and_stays_amber() {
  Rig r;
  r.state(attn());
  r.at(10000);
  const SceneShow before = r.b.show(r.t);
  r.b.pressDown(r.t);
  r.at(10100);
  TEST_ASSERT_EQUAL_INT(before.dy + Behaviour::kPressPx, r.b.show(r.t).dy);  // the press shows
  r.b.pressUp(r.t);
  r.b.tap(r.t);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(0u, r.b.momentSeq());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  keepAlive(r, attn(), 125000);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0x805800, r.b.led(r.t));
  TEST_ASSERT_EQUAL_STRING("chirp@0", r.sfx().c_str());
}

// BEHAVIORS.md §3.2: answered on the Mac, the face blinks back to the
// base look with no moment.
static void test_answering_on_the_mac_blinks_back() {
  Rig r;
  r.state(attn());
  r.at(5000);
  r.state(base("working"));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).eyesShut);  // a blink hides the switch
  TEST_ASSERT_TRUE(r.b.show(r.t).state == SceneState::kWorking);
  TEST_ASSERT_EQUAL(0u, r.b.momentSeq());
}

// BEHAVIORS.md §1: while something needs you, no animation plays and no
// mumble shows.
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
  say.anim = Anim::kCheer, say.syllables = 3;
  TEST_ASSERT_FALSE(r.b.onMoment(say, r.t));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  // A mumble that was showing goes when something starts needing you.
  Rig m;
  m.state(base("idle"));
  TEST_ASSERT_TRUE(m.say());
  m.at(100);
  m.state(attn());
  TEST_ASSERT_NULL(m.b.mumble(m.t));
}

// UX.md §2: nothing cuts hard. Attention arriving under a cheer (which it
// ends) or a wiggle shows the needs-you design behind a blink of
// kBlendMs, and the design's clock starts at the change.
static void test_changes_mid_motion_blink_into_the_new_design() {
  const Anim anims[] = {Anim::kCheer, Anim::kWiggle};
  const char* const bases[] = {"working", "idle"};
  for (int i = 0; i < 2; ++i) {
    for (uint32_t when : {300u, 650u}) {
      Rig r;
      r.state(base(bases[i]));
      r.moment(anims[i]);
      r.at(when);
      r.state(attn());
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == SceneState::kNeedsYou);
      TEST_ASSERT_TRUE(s.eyesShut);
      TEST_ASSERT_EQUAL_UINT32(0, s.t);
      TEST_ASSERT_TRUE(r.b.show(r.t + render::kBlendMs - 1).eyesShut);
      r.at(r.t + render::kBlendMs);
      TEST_ASSERT_TRUE(!r.b.show(r.t).eyesShut || r.b.life(r.t) == Life::kBlink);
    }
  }
}

// UX.md §2, every way round: whatever state Boop is in, whatever is
// playing, and whatever arrives (any message or input), the design just
// after the change is the design just before it, at the same moment of
// its clock, or else the eyes are shut to hide the switch.
static void test_no_change_ever_cuts_hard() {
  Model busy3 = base("working");
  busy3.busy = 3;
  Model muted = base("idle");
  muted.vol = 0;
  const Model states[] = {base("idle"), base("working"), busy3, base("asleep"), attn(), attn("jetpack"), muted};
  enum Playing { kNothing, kCheer, kWiggle, kSay, kCheerSay, kNoApp, kPlayingCount };
  const int kEvents = 7 + 4;  // every state, then the moments and inputs
  int checked = 0;
  for (int from = 0; from < 7; ++from) {
    for (int playing = 0; playing < kPlayingCount; ++playing) {
      for (int event = 0; event < kEvents; ++event) {
        for (uint32_t when : {40u, 333u, 1210u}) {
          Rig r;
          r.state(states[from]);
          r.at(500);
          switch (playing) {
            case kCheer: r.moment(Anim::kCheer); break;
            case kWiggle: r.b.tap(r.t); break;
            case kSay: r.say(6); break;
            case kCheerSay: {
              MomentIn m;
              m.anim = Anim::kCheer, m.syllables = 4, m.ms = 120;
              r.b.onMoment(m, r.t);
              break;
            }
            case kNoApp: r.at(500 + Behaviour::kNoAppMs); break;
            default: break;
          }
          r.at(r.t + when);
          SceneShow before = r.b.show(r.t);
          if (event < 7) {
            r.state(states[event]);
          } else {
            switch (event - 7) {
              case 0: r.moment(Anim::kCheer); break;
              case 1: r.b.tap(r.t); break;
              case 2: r.say(3); break;
              default: r.moment(Anim::kWiggle); break;
            }
          }
          SceneShow after = r.b.show(r.t);
          bool same = before.state == after.state && before.mood == after.mood && before.t == after.t;
          if (!same && !after.eyesShut) {
            char why[96];
            std::snprintf(why, sizeof(why), "from state %d, playing %d, event %d at +%u ms", from, playing, event,
                          unsigned(when));
            TEST_FAIL_MESSAGE(why);
          }
          ++checked;
        }
      }
    }
  }
  TEST_ASSERT_EQUAL(7 * kPlayingCount * kEvents * 3, checked);
}

// BEHAVIORS.md §3.4: no app holds however long the Mac stays away, even
// past the 24.9 days where the clock's differences wrap, and whatever had
// finished stays finished when they come round again at 49.7 days: the
// no-app design, no old mumble, press dip or backlight fade.
static void test_no_app_holds_for_weeks() {
  Rig r;
  r.state(base("working"));
  r.at(1000);
  TEST_ASSERT_TRUE(r.say(3));  // over by 2500
  r.b.pressDown(r.t);
  r.at(1100);
  r.b.pressUp(r.t);
  r.at(Behaviour::kNoAppMs);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  const uint32_t start = Behaviour::kNoAppMs + 200;
  r.at(start);
  const SceneShow noApp = r.b.show(start);
  TEST_ASSERT_TRUE(noApp.state == SceneState::kNoApp);
  // The clock moves on a minute at a time, as the ticks would take it.
  uint64_t now = start;
  auto walk = [&](uint64_t to) {
    while (now + 60000 < to) now += 60000, r.at(uint32_t(now));
    now = to;
    r.at(uint32_t(now));
  };
  // The no-app design repeats every 8 s, its breath.
  walk(start + 8000ull * 268436);  // 2^31 ms and a little after the switch to no app
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_TRUE(render::sceneFrame(noApp) == render::sceneFrame(r.b.show(r.t)));
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  walk(0x100000000ull + 1150);  // 2^32 ms after the release, 150 after the mumble started
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  // No mumble's bubble or mouth, no press, no blink: only the design.
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNoApp);
  TEST_ASSERT_FALSE(s.hideProp);
  TEST_ASSERT_FALSE(s.mouthOpen);
  TEST_ASSERT_FALSE(s.eyesShut);
  TEST_ASSERT_EQUAL_INT(0, s.dy);
  walk(0x100000000ull + Behaviour::kNoAppMs + 50);  // 2^32 ms after the dimming began
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
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

static void test_mumble_moves_the_mouth() {
  Rig r;
  r.state(base("idle"));
  MomentIn m;
  m.anim = Anim::kCheer, m.syllables = 4, m.word = "done", m.at = 4, m.ms = 100;
  r.b.onMoment(m, r.t);
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_EQUAL_STRING("done", r.b.mumble(r.t)->word);
  TEST_ASSERT_TRUE(r.b.speaking(599));  // (4 syllables + 2 for the word) × 100 ms
  TEST_ASSERT_FALSE(r.b.speaking(600));
  // The mouth is an "o" for the first half of each syllable, and shut
  // for the second, until the line is said.
  TEST_ASSERT_TRUE(r.b.show(20).mouthOpen);
  TEST_ASSERT_FALSE(r.b.show(60).mouthOpen);
  TEST_ASSERT_TRUE(r.b.show(120).mouthOpen);
  TEST_ASSERT_FALSE(r.b.show(620).mouthOpen);
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
  TEST_ASSERT_TRUE(r.b.show(1020).mouthOpen);
  TEST_ASSERT_TRUE(r.b.show(1020).hideProp);  // the bubble has the keyboard's room
  TEST_ASSERT_TRUE(r.b.show(1500).state == SceneState::kWorking);  // the face goes on as it was
  r.at(1000 + 400 + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  r.at(1000 + 400 + Behaviour::kBubbleReadMs);
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_FALSE(r.b.show(r.t).hideProp);  // the keyboard is back once the bubble goes

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
  r.b.tap(r.t);
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());
  TEST_ASSERT_NULL(r.b.mumble(r.t));

  // An empty mumble is nothing.
  Rig e;
  e.state(base("idle"));
  TEST_ASSERT_FALSE(e.say(0));
  TEST_ASSERT_EQUAL(0u, e.b.momentSeq());
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
    if (l != Life::kNone) TEST_ASSERT_TRUE(r.b.show(t).eyesShut);
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
// 2–5 s working, however many agents are busy. Asleep, as with no app
// (§3.4), never blinks.
static void test_life_is_blinks_at_their_pace() {
  checkGaps(blinkStarts(base("idle"), true, 120000), 0, 2000, 6000);
  Model w = base("working");
  w.busy = 1;
  checkGaps(blinkStarts(w, true, 120000), 0, 2000, 5000);
  w.busy = 3;
  checkGaps(blinkStarts(w, true, 120000), 0, 2000, 5000);
  std::vector<uint32_t> none = blinkStarts(base("idle"), false, 180000);
  TEST_ASSERT_TRUE(none.empty() || none.back() < 30000);  // no app: no blinks after 30 s
}

static void test_asleep_breathes_and_never_blinks() {
  Rig r;
  r.state(base("asleep"));
  for (uint32_t t = 1; t <= 20000; t += 7) {
    if (t % 10000 < 7) r.state(base("asleep"));
    r.at(t);
    TEST_ASSERT_EQUAL(Life::kNone, r.b.life(t));
  }
  // Breathing is the asleep design's own 8 s breath (BEHAVIORS.md §2).
  TEST_ASSERT_TRUE(r.b.show(1000).state == SceneState::kAsleep);
  TEST_ASSERT_TRUE(render::sceneFrame(r.b.show(1000)) != render::sceneFrame(r.b.show(3000)));
  TEST_ASSERT_TRUE(render::sceneFrame(r.b.show(1000)) == render::sceneFrame(r.b.show(9000)));
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
}

// BEHAVIORS.md §2, UX.md §2: each look shows its design in the mood the Mac
// sent. A cheer shows the task_complete design on its own clock; the mood
// changing mid-cheer blinks to the new mood's design and keeps that clock.
static void test_each_look_shows_its_design_in_the_mood() {
  struct Case {
    const char* base;
    bool attn;
    SceneState state;
  };
  const Case cases[] = {{"idle", false, SceneState::kIdle},
                        {"working", false, SceneState::kWorking},
                        {"asleep", false, SceneState::kAsleep},
                        {"working", true, SceneState::kNeedsYou}};
  for (const Case& c : cases) {
    for (render::Mood mood : {render::Mood::kHappy, render::Mood::kGrumpy, render::Mood::kSad}) {
      Rig r;
      Model m = c.attn ? attn() : base(c.base);
      m.mood = mood;
      r.state(m);
      r.at(500);
      SceneShow s = r.b.show(r.t);
      TEST_ASSERT_TRUE(s.state == c.state);
      TEST_ASSERT_TRUE(s.mood == mood);
      TEST_ASSERT_EQUAL_UINT32(500, s.t);
    }
  }
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kDetermined;
  r.state(m);
  r.at(1000);
  r.moment(Anim::kCheer);
  r.at(1500);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_UINT32(500, s.t);
  m.mood = render::Mood::kProud;
  r.state(m);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_EQUAL_UINT32(500, s.t);
  TEST_ASSERT_TRUE(s.eyesShut);
  r.at(3000);  // the cheer is over: back to working, still proud
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
}

// BEHAVIORS.md §5: a tap's wiggle keeps the look's design and its clock,
// with no blink; the face sways a few pixels and a heart pops in, small
// then full size, for the 0.7 s it plays.
static void test_a_wiggle_sways_over_the_look() {
  Rig r;
  r.state(base("working"));
  r.at(1000);
  const SceneShow before = r.b.show(r.t);
  r.b.tap(r.t);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_EQUAL_UINT32(before.t, s.t);
  TEST_ASSERT_FALSE(s.eyesShut);
  TEST_ASSERT_EQUAL(1, s.heart);
  int lo = 0, hi = 0;
  for (uint32_t t = 1000; t < 1700; ++t) {
    s = r.b.show(t);
    if (s.dx < lo) lo = s.dx;
    if (s.dx > hi) hi = s.dx;
    if (t >= 1100) TEST_ASSERT_EQUAL(2, s.heart);
  }
  TEST_ASSERT_TRUE(lo <= -2 && lo >= -3);
  TEST_ASSERT_TRUE(hi >= 2 && hi <= 3);
  r.at(1700);
  s = r.b.show(r.t);
  TEST_ASSERT_EQUAL(0, s.heart);
  TEST_ASSERT_EQUAL(0, s.dx);
  TEST_ASSERT_FALSE(s.eyesShut && r.b.life(r.t) == Life::kNone);  // no blink when it ends either
}

// BEHAVIORS.md §3.4: with no state for 30 s the device shows the no-app
// design (backlight 60), with the unplugged icon in the strip; on
// reconnect the face blinks into whatever the next state says.
static void test_no_app_at_30s_and_reconnect_blinks_back() {
  Rig r;
  r.at(1000);
  Model m = attn();  // even a stale "needs you" gives way
  m.wait = 1, m.busy = 2;
  r.state(m);
  r.at(30999);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(1, r.b.strip(r.t).wait);
  r.at(31000);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_STRING("no_app", r.b.faceName(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));  // dimming over kBlendMs
  TEST_ASSERT_TRUE(r.b.backlight(r.t + render::kBlendMs / 2) < 255);
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  // The strip keeps only the unplugged icon: the counts are stale.
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_TRUE(strip.noApp);
  TEST_ASSERT_EQUAL(0, strip.wait);
  TEST_ASSERT_EQUAL(0, strip.busy);
  r.at(31000 + render::kBlendMs);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNoApp);
  TEST_ASSERT_FALSE(s.eyesShut);
  r.at(40000);
  r.state(base("idle"));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(Life::kNone, r.b.life(r.t));
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.eyesShut);  // a blink hides the switch
  TEST_ASSERT_FALSE(r.b.show(r.t + render::kBlendMs).eyesShut);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t + render::kBlendMs));
}

static void test_press_shows_within_20ms() {
  Rig r;
  r.state(base("idle"));
  r.at(500);
  const SceneShow before = r.b.show(500);
  r.b.pressDown(500);
  TEST_ASSERT_EQUAL_INT(before.dy + Behaviour::kPressPx, r.b.show(500).dy);  // at once
  TEST_ASSERT_TRUE(r.b.pressEasing(516));  // and the redraw cap lets it through
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

// UX.md §4: any BOOT press is a tap, and so is a touch anywhere, the strip
// included; each is sent on release, however long it was held.
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
  r.line("{\"t\":\"dbg.press\",\"ms\":800}");  // a long BOOT press
  r.clock(3700);
  TEST_ASSERT_EQUAL(4, r.count(kTap));  // nothing yet
  r.clock(4100);
  TEST_ASSERT_EQUAL(5, r.count(kTap));  // a tap, on release
  // Tap is the only input (PROTOCOL.md §4).
  TEST_ASSERT_EQUAL(r.count("\"t\":\"input\""), r.count(kTap));
}

// A long touch during needs you is a tap too: the squash, and no moment.
static void test_a_long_touch_during_needs_you_is_a_tap() {
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
  TEST_ASSERT_TRUE(r.has("\"moment\":null"));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_needs_you_chirps_once_and_stays_amber);
  RUN_TEST(test_tap_during_needs_you_is_only_the_dip_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_blinks_back);
  RUN_TEST(test_attention_wins_over_moments);
  RUN_TEST(test_changes_mid_motion_blink_into_the_new_design);
  RUN_TEST(test_no_app_holds_for_weeks);
  RUN_TEST(test_no_change_ever_cuts_hard);
  RUN_TEST(test_face_name_is_the_moment_or_the_look);
  RUN_TEST(test_moments_end_and_replace);
  RUN_TEST(test_mumble_moves_the_mouth);
  RUN_TEST(test_a_mumble_alone_plays_over_the_face);
  RUN_TEST(test_life_is_blinks_at_their_pace);
  RUN_TEST(test_asleep_breathes_and_never_blinks);
  RUN_TEST(test_a_wiggle_sways_over_the_look);
  RUN_TEST(test_each_look_shows_its_design_in_the_mood);
  RUN_TEST(test_no_app_at_30s_and_reconnect_blinks_back);
  RUN_TEST(test_press_shows_within_20ms);
  RUN_TEST(test_gestures_send_the_right_inputs);
  RUN_TEST(test_a_long_touch_during_needs_you_is_a_tap);
  return UNITY_END();
}
