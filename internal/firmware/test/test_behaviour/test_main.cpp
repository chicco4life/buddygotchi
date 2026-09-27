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
using app::Model;
using app::MomentIn;
using app::Screen;
using render::Anim;
using render::SceneShow;
using render::SceneState;
using render::loopMs;

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
  m.base = app::baseFromName(b);
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

// BEHAVIORS.md §3.2: a different request shown chirps once more, even with
// the same agent and project (two worktrees of one repo): the Mac numbers
// each request in `attn.id` (PROTOCOL.md §3). More waiting behind it, a
// resent state, or a Mac too old to send a number, doesn't.
static void test_a_different_request_with_the_same_names_chirps() {
  Rig r;
  r.at(1000);
  Model a = attn();
  a.attnId = 7;
  r.state(a);
  TEST_ASSERT_EQUAL_STRING("chirp@1000", r.sfx().c_str());
  r.at(2000);
  Model more = a;
  more.more = 1;
  r.state(more);  // another waits behind it: "+1" only
  r.state(more);  // resent
  TEST_ASSERT_EQUAL_STRING("chirp@1000", r.sfx().c_str());
  r.at(3000);
  Model b = attn();
  b.attnId = 8;
  r.state(b);  // the first answered: the other request is shown
  TEST_ASSERT_EQUAL_STRING("chirp@3000", r.sfx().c_str());
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  r.at(4000);
  r.state(attn());  // no number: agent and project alone, as before
  r.at(5000);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("chirp@4000", r.sfx().c_str());
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
  r.b.pressUp();
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
      TEST_ASSERT_TRUE(!r.b.show(r.t).eyesShut || r.b.blinking(r.t));
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
  r.b.pressUp();
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
  r.at(loopMs(render::Mood::kHappy, SceneState::kTaskComplete));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.say();  // a mumble doesn't change the face
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL_STRING("idle", r.b.faceName(r.t));
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("needs_you", r.b.faceName(r.t));
}

// BEHAVIORS.md §5: the cheer plays its loops of the mood's task-complete
// design, one unless the moment says more, with no light and no sound; a
// new moment replaces the one playing.
static void test_moments_end_and_replace() {
  Rig r;
  r.state(base("idle"));
  r.moment(Anim::kCheer);
  const uint32_t loop = loopMs(render::Mood::kHappy, SceneState::kTaskComplete);
  r.at(loop - 1);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL_STRING("", r.sfx().c_str());
  r.at(loop);
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

// PROTOCOL.md §3: a cheer's `loops` is how many times its design plays,
// each time from its start, timed by the design of the mood it's drawn
// in. A wiggle ignores it.
static void test_a_cheer_plays_its_loops() {
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kProud;
  r.state(m);
  r.at(1000);
  MomentIn in;
  in.anim = Anim::kCheer, in.loops = 3;
  r.b.onMoment(in, r.t);
  const uint32_t loop = loopMs(render::Mood::kProud, SceneState::kTaskComplete);
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kCheer, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(3 * loop, left);
  TEST_ASSERT_EQUAL_UINT32(loop - 1, r.b.show(1000 + loop - 1).t);
  SceneShow s = r.b.show(1000 + loop + 100);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_EQUAL_UINT32(100, s.t);  // the design starts over
  r.at(1000 + 3 * loop - 1);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  r.at(1000 + 3 * loop);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // Drawn in a reaction's mood, the cheer's loops are that mood's design's.
  r.at(20000);
  r.state(m);
  in.loops = 1, in.expr = true, in.mood = render::Mood::kSad;
  r.b.onMoment(in, r.t);
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kSad, SceneState::kTaskComplete), left);
  MomentIn w;
  w.anim = Anim::kWiggle, w.loops = 4;
  r.b.onMoment(w, r.t);
  r.b.moment(r.t, left);
  TEST_ASSERT_EQUAL_UINT32(render::kWiggleMs, left);
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
  TEST_ASSERT_EQUAL_UINT32(loopMs(render::Mood::kHappy, SceneState::kTaskComplete) - 500, left);
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
  bool prev = false;
  for (uint32_t t = 1; t <= to; ++t) {
    if (mac && t % 10000 == 0) r.at(t), r.state(m);
    r.at(t);
    bool blink = r.b.blinking(t);
    if (blink) TEST_ASSERT_TRUE(r.b.show(t).eyesShut);
    if (blink && !prev) starts.push_back(t);
    prev = blink;
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
// PROTOCOL.md §3: a moment's `mood` is its expression. With no animation,
// the look is drawn in that mood for the moment's loops of the design it's
// drawn in, ending on a loop boundary of that design's clock (so the first
// loop ends at the next boundary), and at least as long as the mumble and
// its bubble; then it goes back to the state's mood behind a blink. A look
// change meanwhile keeps the expression and its end; a new moment, a tap
// or "needs you" ends it.
static MomentIn expressive(render::Mood mood, int syl = 4, int loops = 1) {
  MomentIn m;
  m.syllables = syl, m.ms = 100;
  m.expr = true, m.mood = mood, m.loops = loops;
  return m;
}

static void test_an_expression_holds_its_loops() {
  Rig r;
  Model m = base("working");  // happy, the working design's clock from 0
  r.state(m);
  const uint32_t loop = loopMs(render::Mood::kGrumpy, SceneState::kWorking);
  r.at(1000);
  TEST_ASSERT_TRUE(r.b.onMoment(expressive(render::Mood::kGrumpy), r.t));
  render::Mood e;
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(e == render::Mood::kGrumpy);
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kGrumpy);
  TEST_ASSERT_TRUE(s.eyesShut);  // it blinks into the expression
  TEST_ASSERT_EQUAL_UINT32(1000, s.t);  // the look's clock goes on
  // 4 syllables × 100 ms, then the bubble's 1.2 s: the mumble is over
  // first, and the face holds to the design's next boundary.
  const uint32_t said = 1000 + 400 + Behaviour::kBubbleReadMs;
  TEST_ASSERT_TRUE(said < loop);
  r.at(said);
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kGrumpy);
  r.at(loop - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(loop);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);  // back to the state's mood
  TEST_ASSERT_TRUE(s.state == SceneState::kWorking);
  TEST_ASSERT_TRUE(s.eyesShut);  // behind a blink

  // Three loops, from partway into one: to the third boundary.
  r.at(2 * loop + 300);
  r.state(m);
  r.b.onMoment(expressive(render::Mood::kGrumpy, 2, 3), r.t);
  r.at(5 * loop - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(5 * loop);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));

  // A mumble longer than its loop: the face holds as long as it plays.
  r.at(6 * loop);
  r.state(m);
  MomentIn in = expressive(render::Mood::kExcited, 8);
  in.ms = 400;
  r.b.onMoment(in, r.t);
  const uint32_t end = r.t + 8 * 400 + Behaviour::kBubbleReadMs;
  TEST_ASSERT_TRUE(end - r.t > loopMs(render::Mood::kExcited, SceneState::kWorking));
  r.at(end - 1);
  TEST_ASSERT_TRUE(r.b.expression(r.t, e));
  r.at(end);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
}

static void test_an_expression_over_the_cheer_and_across_a_look_change() {
  Rig r;
  Model m = base("working");
  m.mood = render::Mood::kCurious;
  r.state(m);
  r.at(1000);
  r.moment(Anim::kCheer);  // the rule's cheer, in curious
  const uint32_t cheer = loopMs(render::Mood::kCurious, SceneState::kTaskComplete);
  const uint32_t proud = loopMs(render::Mood::kProud, SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kCurious);
  r.at(1200);
  m.base = SceneState::kIdle;  // the turn is over
  r.state(m);
  r.b.onMoment(expressive(render::Mood::kProud, 3), r.t);  // Jev: proud
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  TEST_ASSERT_EQUAL_UINT32(200, s.t);  // the cheer keeps its clock
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kCheer, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(cheer - 200, left);  // a mumble doesn't cut the cheer
  // The face holds one loop of the cheer's design in proud, on the
  // cheer's clock: to 1000 + proud's loop, after the mumble (1200 + 300 +
  // 1200) and the cheer have ended, so the idle look shows in proud until
  // then.
  TEST_ASSERT_TRUE(1200 + 300 + Behaviour::kBubbleReadMs < 1000 + proud);
  TEST_ASSERT_TRUE(cheer < proud);
  r.at(1000 + cheer);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kProud);
  r.at(1000 + proud - 1);
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kProud);
  r.at(1000 + proud);
  s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kCurious);

  // A look change while it plays: the expression goes with the new look,
  // and ends where it would have, at the working design's boundary.
  Rig l;
  l.state(base("working"));
  l.at(1000);
  l.b.onMoment(expressive(render::Mood::kGrumpy), l.t);
  l.at(1500);
  l.state(base("idle"));
  s = l.b.show(l.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kIdle);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kGrumpy);
  const uint32_t working = loopMs(render::Mood::kGrumpy, SceneState::kWorking);
  l.at(working - 1);
  TEST_ASSERT_TRUE(l.b.show(l.t).mood == render::Mood::kGrumpy);
  l.at(working);
  TEST_ASSERT_TRUE(l.b.show(l.t).mood == render::Mood::kHappy);

  // With an animation in the same moment, it lasts the longer of the two:
  // here the cheer, a loop of excited's design.
  Rig a;
  a.state(base("idle"));
  a.at(1000);
  MomentIn in = expressive(render::Mood::kExcited, 2);
  in.anim = Anim::kCheer;
  a.b.onMoment(in, a.t);
  const uint32_t excited = loopMs(render::Mood::kExcited, SceneState::kTaskComplete);
  TEST_ASSERT_TRUE(200 + Behaviour::kBubbleReadMs < excited);
  a.at(1000 + excited - 1);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kExcited);
  a.at(1000 + excited);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kHappy);
  // An animation alone with a mood: as long as it plays.
  a.at(5000);
  MomentIn wig;
  wig.anim = Anim::kWiggle, wig.expr = true, wig.mood = render::Mood::kSad;
  a.b.onMoment(wig, a.t);
  a.at(5699);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kSad);
  a.at(5700);
  TEST_ASSERT_TRUE(a.b.show(a.t).mood == render::Mood::kHappy);
}

static void test_an_expression_ends_with_its_moment() {
  render::Mood e;
  // A new mumble without a mood replaces the line, and the expression.
  Rig r;
  r.state(base("working"));
  r.at(1000);
  r.b.onMoment(expressive(render::Mood::kGrumpy), r.t);
  r.at(1500);
  r.say(2);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kHappy);
  // A tap's wiggle does too.
  r.at(5000);
  r.b.onMoment(expressive(render::Mood::kSad), r.t);
  r.at(5100);
  r.b.tap(r.t);
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kHappy);
  // "Needs you" stops the line, and the expression with it.
  r.at(9000);
  r.b.onMoment(expressive(render::Mood::kExcited), r.t);
  r.at(9100);
  r.state(attn());
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  SceneShow s = r.b.show(r.t);
  TEST_ASSERT_TRUE(s.state == SceneState::kNeedsYou);
  TEST_ASSERT_TRUE(s.mood == render::Mood::kHappy);
  // While something needs you, a moment with a mood plays nothing and
  // borrows no face.
  r.at(9500);
  TEST_ASSERT_FALSE(r.b.onMoment(expressive(render::Mood::kGrumpy), r.t));
  TEST_ASSERT_FALSE(r.b.expression(r.t, e));
  TEST_ASSERT_TRUE(r.b.show(r.t).mood == render::Mood::kHappy);
  // No expression: the state's mood, as before.
  Rig n;
  Model m = base("idle");
  m.mood = render::Mood::kDetermined;
  n.state(m);
  n.at(100);
  n.say(3);
  TEST_ASSERT_FALSE(n.b.expression(n.t, e));
  TEST_ASSERT_TRUE(n.b.show(n.t).mood == render::Mood::kDetermined);
}

// PROTOCOL.md §4: a moment the Mac waits on (one with an id) ends exactly
// once, when no part of it plays any more (the mumble and its bubble, an
// animation, the borrowed face): done when it played out, or when only the
// face it holds after its mumble was ended early; cut, and by what, when a
// tap's wiggle, a newer moment, "needs you" or dbg.reset stopped its
// animation or its mumble; skipped when none of it played.
static std::string ended(Rig& r) {
  std::string out;
  app::Ended e;
  while (r.b.takeEnded(e)) {
    if (!out.empty()) out += ", ";
    out += std::to_string(e.id) + " " + app::momentEndName(e.how);
    if (const char* by = app::cutByName(e.by)) out += std::string(" by ") + by;
  }
  return out;
}

static MomentIn waited(uint32_t id, int syl = 4) {
  MomentIn m = expressive(render::Mood::kProud, syl);
  m.id = id;
  return m;
}

static void test_a_waited_moment_says_how_it_ended() {
  Rig r;
  r.state(base("idle"));  // the idle design's clock from 0
  r.at(1000);
  TEST_ASSERT_TRUE(r.b.onMoment(waited(7), r.t));
  // Its mumble is over at 1000 + 400 + 1.2 s, and its face at the idle
  // design's next boundary.
  const uint32_t end = loopMs(render::Mood::kProud, SceneState::kIdle);
  r.at(1000 + 400 + Behaviour::kBubbleReadMs);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end);
  TEST_ASSERT_EQUAL_STRING("7 done", ended(r).c_str());
  r.at(10000);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());  // once

  // Over the rules' cheer, which isn't part of it: its face holds a loop
  // of the cheer's design in proud, on the cheer's clock, and the cheer
  // plays on as it would have.
  r.moment(Anim::kCheer);
  r.at(10500);
  r.b.onMoment(waited(8, 2), r.t);
  r.at(10500 + 200 + Behaviour::kBubbleReadMs);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  r.at(10000 + loopMs(render::Mood::kProud, SceneState::kTaskComplete));
  TEST_ASSERT_EQUAL_STRING("8 done", ended(r).c_str());
  // A cheer the Mac waits on plays on under a newer mumble, which doesn't
  // stop it: done when the cheer is.
  r.at(20000);
  MomentIn cheer;
  cheer.anim = Anim::kCheer, cheer.id = 9;
  r.b.onMoment(cheer, r.t);
  r.at(20500);
  r.say(2);
  const uint32_t cheered = 20000 + loopMs(render::Mood::kHappy, SceneState::kTaskComplete);
  r.at(cheered - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(cheered);
  TEST_ASSERT_EQUAL_STRING("9 done", ended(r).c_str());

  // Cut short: by a tap's wiggle, by a newer moment (the rules' cheer, a
  // mumble, the Mac's next), and by "needs you".
  r.at(30000);
  r.b.onMoment(waited(10), r.t);
  r.at(30100);
  r.b.tap(r.t);
  TEST_ASSERT_EQUAL_STRING("10 cut by tap", ended(r).c_str());
  r.at(31000);
  r.b.onMoment(waited(11), r.t);
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL_STRING("11 cut by moment", ended(r).c_str());
  r.at(35000);
  r.b.onMoment(waited(12), r.t);
  r.at(35100);
  r.say(2);
  TEST_ASSERT_EQUAL_STRING("12 cut by moment", ended(r).c_str());
  r.at(40000);
  r.b.onMoment(waited(13), r.t);
  r.b.onMoment(waited(14), r.t);
  TEST_ASSERT_EQUAL_STRING("13 cut by moment", ended(r).c_str());
  r.at(40100);
  r.state(attn());
  TEST_ASSERT_EQUAL_STRING("14 cut by needs_you", ended(r).c_str());
  // Skipped: something needs you, so none of it plays.
  TEST_ASSERT_FALSE(r.b.onMoment(waited(15), r.t));
  TEST_ASSERT_EQUAL_STRING("15 skipped", ended(r).c_str());

  // Its face holds on after its mumble is over (PROTOCOL.md §3). A tap, a
  // newer moment or "needs you" then ends it at once, but doesn't cut the
  // moment: it was seen and heard, so it's done.
  Rig h;
  h.state(base("idle"));  // the idle design's clock from 0
  const uint32_t idle = loopMs(render::Mood::kProud, SceneState::kIdle);
  render::Mood face;
  h.at(1000);
  h.b.onMoment(waited(17), h.t);
  h.at(1000 + 400 + Behaviour::kBubbleReadMs + 100);
  TEST_ASSERT_TRUE(h.t < idle);
  TEST_ASSERT_NULL(h.b.mumble(h.t));
  TEST_ASSERT_TRUE(h.b.expression(h.t, face));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());
  h.b.tap(h.t);
  TEST_ASSERT_FALSE(h.b.expression(h.t, face));
  TEST_ASSERT_EQUAL_STRING("17 done", ended(h).c_str());
  h.at(2 * idle + 1000);
  h.state(base("idle"));
  h.b.onMoment(waited(18), h.t);
  h.at(2 * idle + 1000 + 400 + Behaviour::kBubbleReadMs + 100);
  TEST_ASSERT_NULL(h.b.mumble(h.t));
  TEST_ASSERT_EQUAL_STRING("", ended(h).c_str());
  h.state(attn());
  TEST_ASSERT_EQUAL_STRING("18 done", ended(h).c_str());
  h.at(4 * idle + 1000);
  h.state(base("idle"));
  h.b.onMoment(waited(19), h.t);
  h.at(4 * idle + 1000 + 400 + Behaviour::kBubbleReadMs + 100);
  h.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL_STRING("19 done", ended(h).c_str());
  h.at(6 * idle + 1000);
  h.state(base("idle"));
  h.b.onMoment(waited(20), h.t);
  h.at(6 * idle + 1000 + 400 + Behaviour::kBubbleReadMs + 100);
  h.say(2);  // a newer line
  TEST_ASSERT_EQUAL_STRING("20 done", ended(h).c_str());
  // During its bubble, after the last syllable, it's still its mumble.
  h.at(8 * idle + 1000);
  h.state(base("idle"));
  h.b.onMoment(waited(21), h.t);
  h.at(8 * idle + 1000 + 400 + Behaviour::kBubbleReadMs - 1);
  TEST_ASSERT_NOT_NULL(h.b.mumble(h.t));
  h.b.tap(h.t);
  TEST_ASSERT_EQUAL_STRING("21 cut by tap", ended(h).c_str());

  // dbg.reset forgets the moment, which the Mac is still told of.
  r.at(50000);
  r.state(base("idle"));
  r.b.onMoment(waited(16), r.t);
  r.b.reset(r.t, r.rng);
  TEST_ASSERT_EQUAL_STRING("16 cut by reset", ended(r).c_str());

  // A moment with no id never ends out loud.
  Rig n;
  n.state(base("idle"));
  n.say(3);
  n.b.tap(n.t);
  n.moment(Anim::kCheer);
  n.at(10000);
  TEST_ASSERT_EQUAL_STRING("", ended(n).c_str());
}

// PROTOCOL.md §3–4: each launch of the Mac app starts its ids at a random
// number, so a moment after a restart can, rarely, reuse an id the device
// still waits on from the launch before. That launch is gone: its moment
// is forgotten, unreported, and the new one's end is its own.
static void test_a_new_launchs_moment_is_its_own() {
  Rig r;
  r.state(base("idle"));  // the idle design's clock from 0
  r.at(1000);
  MomentIn old = waited(1);
  old.loops = 4;
  r.b.onMoment(old, r.t);
  r.at(4000);
  TEST_ASSERT_TRUE(r.b.onMoment(waited(1), r.t));  // the new launch's first
  const uint32_t idle = loopMs(render::Mood::kProud, SceneState::kIdle);
  uint32_t end = idle;
  while (end <= 4000 + 400 + Behaviour::kBubbleReadMs) end += idle;
  r.at(end - 1);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());
  r.at(end);
  TEST_ASSERT_EQUAL_STRING("1 done", ended(r).c_str());
  r.at(end + 4 * idle);
  TEST_ASSERT_EQUAL_STRING("", ended(r).c_str());  // once, and nothing of the old launch's
}

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
    TEST_ASSERT_FALSE(r.b.blinking(t));
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
  TEST_ASSERT_FALSE(s.eyesShut && !r.b.blinking(r.t));  // no blink when it ends either
}

// BEHAVIORS.md §3.4: with no state for 30 s the device shows the no-app
// design (backlight 60), with the unplugged icon in the strip; on
// reconnect the face blinks into whatever the next state says.
static void test_no_app_at_30s_and_reconnect_blinks_back() {
  Rig r;
  r.at(1000);
  Model m = attn();  // even a stale "needs you" gives way
  m.busy = 2;
  r.state(m);
  r.at(30999);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_STRING("codex", r.b.strip(r.t).agent);
  r.at(31000);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_STRING("no_app", r.b.faceName(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));  // dimming over kBlendMs
  TEST_ASSERT_TRUE(r.b.backlight(r.t + render::kBlendMs / 2) < 255);
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  // The strip keeps only the unplugged icon: the counts are stale.
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_TRUE(strip.noApp);
  TEST_ASSERT_NULL(strip.agent);
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
  TEST_ASSERT_FALSE(r.b.blinking(r.t));
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
  RUN_TEST(test_a_different_request_with_the_same_names_chirps);
  RUN_TEST(test_a_new_launchs_moment_is_its_own);
  RUN_TEST(test_tap_during_needs_you_is_only_the_dip_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_blinks_back);
  RUN_TEST(test_attention_wins_over_moments);
  RUN_TEST(test_changes_mid_motion_blink_into_the_new_design);
  RUN_TEST(test_no_app_holds_for_weeks);
  RUN_TEST(test_no_change_ever_cuts_hard);
  RUN_TEST(test_face_name_is_the_moment_or_the_look);
  RUN_TEST(test_moments_end_and_replace);
  RUN_TEST(test_a_cheer_plays_its_loops);
  RUN_TEST(test_mumble_moves_the_mouth);
  RUN_TEST(test_a_mumble_alone_plays_over_the_face);
  RUN_TEST(test_an_expression_holds_its_loops);
  RUN_TEST(test_an_expression_over_the_cheer_and_across_a_look_change);
  RUN_TEST(test_an_expression_ends_with_its_moment);
  RUN_TEST(test_a_waited_moment_says_how_it_ended);
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
