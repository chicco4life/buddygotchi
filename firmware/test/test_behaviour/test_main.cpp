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
  // The empty moment, {"t":"moment","ttl":5} (PROTOCOL.md §3).
  void stop() {
    MomentIn m;
    m.empty = true;
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

// BEHAVIORS.md §3.2: a tap while something needs you is the press squash
// only, with no moment, and it stays amber.
static void test_tap_during_needs_you_is_only_the_squash_and_stays_amber() {
  Rig r;
  r.state(attn());
  r.at(10000);
  const render::Pose before = r.b.pose(r.t);
  r.b.pressDown(r.t);
  r.at(10100);
  TEST_ASSERT_TRUE(r.b.pose(r.t).squash > before.squash);  // the press shows
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

// BEHAVIORS.md §3.2: answered on the Mac, the face blends back to the
// base look with no moment.
static void test_answering_on_the_mac_blends_back() {
  Rig r;
  r.state(attn());
  r.at(5000);
  r.state(base("working"));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  TEST_ASSERT_EQUAL_STRING("working", r.b.faceName(r.t));
  TEST_ASSERT_TRUE(r.b.moving(r.t));  // blending
  TEST_ASSERT_EQUAL(0u, r.b.momentSeq());
}

// BEHAVIORS.md §1: while something needs you, only listening plays, and
// no mumble shows.
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
  say.anim = Anim::kListening, say.syllables = 3;
  r.b.onMoment(say, r.t);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());  // push-to-talk still works
  TEST_ASSERT_NULL(r.b.mumble(r.t));               // but never a mumble
  // A mumble that was showing goes when something starts needing you.
  Rig m;
  m.state(base("idle"));
  TEST_ASSERT_TRUE(m.say());
  m.at(100);
  m.state(attn());
  TEST_ASSERT_NULL(m.b.mumble(m.t));
}

// UX.md §2: nothing cuts hard. A change the Mac makes mid-animation starts
// its blend from exactly the frame that was showing: attention arriving
// under a cheer (which it ends) or under listening (which it raises), and a
// working count crossing 3 (the busier pace).
static void test_changes_mid_motion_blend_from_what_was_showing() {
  struct Case {
    Model from;
    Anim anim;
    Model to;
    int raise;  // where the face ends up
  };
  Model busy3 = base("working");
  busy3.busy = 3;
  const Case cases[] = {
      {base("working"), Anim::kCheer, attn(), 1000},
      {base("working"), Anim::kListening, attn(), 1000},
      {base("working"), Anim::kNone, busy3, 0},
  };
  for (const Case& c : cases) {
    for (uint32_t when : {300u, 950u, 2100u}) {
      Rig r;
      r.state(c.from);
      if (c.anim != Anim::kNone) r.moment(c.anim);
      r.at(when);
      render::Pose before = r.b.pose(r.t);
      r.state(c.to);
      TEST_ASSERT_TRUE(before == r.b.pose(r.t));  // the same frame at the change
      render::Pose half = r.b.pose(r.t + render::kBlendMs / 2);
      TEST_ASSERT_TRUE(half.raise >= before.raise && half.raise <= c.raise);
      r.at(r.t + render::kBlendMs);
      TEST_ASSERT_EQUAL(c.raise, r.b.pose(r.t).raise);
    }
  }
}

// UX.md §2, every way round: whatever state Boop is in, whatever is
// playing, and whatever arrives (any message or input), the frame just
// after the change is the frame just before it. Motion only ever starts
// from what was showing.
static void test_no_change_ever_cuts_hard() {
  Model busy3 = base("working");
  busy3.busy = 3;
  Model quiet = base("idle");
  quiet.quiet = 30;
  const Model states[] = {base("idle"), base("working"), busy3, base("asleep"), attn(), attn("jetpack"), quiet};
  enum Playing { kNothing, kCheer, kWiggle, kListening, kSay, kCheerSay, kReplyWait, kNoApp, kPlayingCount };
  const int kEvents = 7 + 6;  // every state, then the moments and inputs
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
            case kListening: r.b.talkOn(r.t); break;
            case kSay: r.say(6); break;
            case kCheerSay: {
              MomentIn m;
              m.anim = Anim::kCheer, m.syllables = 4, m.ms = 120;
              r.b.onMoment(m, r.t);
              break;
            }
            case kReplyWait:
              r.b.talkOn(r.t);
              r.at(900);
              r.b.talkOff(r.t);
              break;
            case kNoApp: r.at(500 + Behaviour::kNoAppMs); break;
            default: break;
          }
          r.at(r.t + when);
          render::Pose before = r.b.pose(r.t);
          if (event < 7) {
            r.state(states[event]);
          } else {
            switch (event - 7) {
              case 0: r.moment(Anim::kCheer); break;
              case 1: r.b.tap(r.t); break;
              case 2: r.b.talkOn(r.t); break;
              case 3: r.b.talkOff(r.t); break;
              case 4: r.say(3); break;
              default: r.stop(); break;
            }
          }
          render::Pose after = r.b.pose(r.t);
          if (!(before == after)) {
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
// asleep face, no old mumble, press squish or backlight fade.
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
  const render::Pose asleep = r.b.pose(start);
  TEST_ASSERT_EQUAL_INT(0, asleep.open);
  // The clock moves on a minute at a time, as the ticks would take it.
  uint64_t now = start;
  auto walk = [&](uint64_t to) {
    while (now + 60000 < to) now += 60000, r.at(uint32_t(now));
    now = to;
    r.at(uint32_t(now));
  };
  // The asleep face repeats every 12 s (breathing 4 s, zzZZ 2.4 s).
  walk(start + 12000ull * 178957);  // 2^31 ms and a little after the blend to asleep
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_TRUE(asleep == r.b.pose(r.t));
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  walk(0x100000000ull + 1150);  // 2^32 ms after the release, 150 after the mumble started
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  // No mumble raising the face: only breathing's bob, at this moment's phase.
  TEST_ASSERT_EQUAL_INT(asleep.squash, r.b.pose(r.t).squash);
  TEST_ASSERT_EQUAL_INT(asleep.dy - render::bob(start, 4000) + render::bob(r.t, 4000), r.b.pose(r.t).dy);
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

static void test_mumble_moves_the_mouth_and_respects_quiet() {
  Rig r;
  r.state(base("idle"));
  MomentIn m;
  m.anim = Anim::kCheer, m.syllables = 4, m.word = "done", m.at = 4, m.ms = 100;
  r.b.onMoment(m, r.t);
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
  r.b.onMoment(m, r.t);
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
  r.b.tap(r.t);
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());
  TEST_ASSERT_NULL(r.b.mumble(r.t));

  // An empty mumble is nothing.
  Rig e;
  e.state(base("idle"));
  TEST_ASSERT_FALSE(e.say(0));
  TEST_ASSERT_EQUAL(0u, e.b.momentSeq());
}

// BEHAVIORS.md §3.3, PROTOCOL.md §3: the reply to push-to-talk, a mumble
// on its own, ends listening, while held or while waiting after release,
// and plays over the face. Nothing follows it.
static void test_a_reply_ends_listening() {
  Rig r;
  r.state(base("idle"));
  r.b.talkOn(0);
  r.at(1000);
  r.b.talkOff(1000);
  r.at(3000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  TEST_ASSERT_TRUE(r.say(3));
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  keepAlive(r, base("idle"), 1000 + Behaviour::kReplyWaitMs + 100);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // While held, too.
  r.b.talkOn(r.t);
  r.at(r.t + 500);
  r.say(2);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // A reply that can't show (needs you, or quiet) still ends it.
  Rig a;
  a.state(attn());
  a.b.talkOn(0);
  a.at(500);
  TEST_ASSERT_FALSE(a.say(2));
  TEST_ASSERT_EQUAL(Anim::kNone, a.anim());
  TEST_ASSERT_NULL(a.b.mumble(a.t));
}

// PROTOCOL.md §3: the empty moment {"t":"moment","ttl":5} ends listening
// and does nothing else. It never ends a cheer, a wiggle or a mumble.
static void test_the_empty_moment_ends_only_listening() {
  Rig r;
  r.state(base("idle"));
  r.moment(Anim::kListening);  // from the Mac: the popover's mic is on
  r.at(4000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_TRUE(r.b.moving(r.t));  // blending back
  // After the wait on release, too.
  r.b.talkOn(r.t);
  r.at(r.t + 1000);
  r.b.talkOff(r.t);
  r.at(r.t + 2000);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  // Nothing playing: nothing happens.
  const uint32_t seq = r.b.momentSeq();
  r.at(r.t + 1000);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());
  TEST_ASSERT_NULL(r.b.mumble(r.t));
  // A cheer, a wiggle and a mumble carry on.
  r.moment(Anim::kCheer);
  r.at(r.t + 100);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
  r.moment(Anim::kWiggle);
  r.stop();
  TEST_ASSERT_EQUAL(Anim::kWiggle, r.anim());
  r.at(r.t + 1000);
  TEST_ASSERT_TRUE(r.say(4));
  r.stop();
  TEST_ASSERT_NOT_NULL(r.b.mumble(r.t));
  TEST_ASSERT_TRUE(r.b.speaking(r.t));
  TEST_ASSERT_EQUAL(seq + 3, r.b.momentSeq());  // cheer, wiggle, mumble; the stops add none
  // A listening moment with a mumble: the stop ends the face, not the line.
  Rig m;
  m.state(base("idle"));
  MomentIn in;
  in.anim = Anim::kListening, in.syllables = 4, in.ms = 100;
  TEST_ASSERT_TRUE(m.b.onMoment(in, m.t));
  m.at(100);
  m.stop();
  TEST_ASSERT_EQUAL(Anim::kNone, m.anim());
  TEST_ASSERT_NOT_NULL(m.b.mumble(m.t));
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
// 2–5 s working (1.2–3.5 s with 3 or more busy). Asleep, as with no app
// (§3.4), never blinks.
static void test_life_is_blinks_at_their_pace() {
  checkGaps(blinkStarts(base("idle"), true, 120000), 0, 2000, 6000);
  Model w = base("working");
  w.busy = 1;
  checkGaps(blinkStarts(w, true, 120000), 0, 2000, 5000);
  w.busy = 3;
  checkGaps(blinkStarts(w, true, 120000), 0, 1200, 3500);
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
  TEST_ASSERT_TRUE(r.b.moving(r.t));
  // Breathing is a one-block bob every 4 s, not a size pulse (BEHAVIORS.md §2).
  TEST_ASSERT_EQUAL_INT(r.b.pose(3000).dy - render::kBobPx, r.b.pose(1000).dy);
  TEST_ASSERT_EQUAL_INT(r.b.pose(1000).size, r.b.pose(3000).size);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
}

// BEHAVIORS.md §2: working's strain and sweat drop move all the time, so
// the face counts as moving and the board keeps redrawing it, as asleep;
// idle only moves to blink.
static void test_working_keeps_moving_and_idle_rests() {
  Model w = base("working");
  for (int busy : {1, 3}) {
    w.busy = busy;
    Rig r;
    r.state(w);
    for (uint32_t t = 1000; t <= 20000; t += 7) {
      if (t % 10000 < 7) r.state(w);
      r.at(t);
      TEST_ASSERT_TRUE(r.b.moving(t));
    }
  }
  Rig i;
  i.state(base("idle"));
  int resting = 0;
  for (uint32_t t = 1000; t <= 20000; t += 7) {
    if (t % 10000 < 7) i.state(base("idle"));
    i.at(t);
    resting += !i.b.moving(t);
  }
  TEST_ASSERT_TRUE(resting > 2000);
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

// BEHAVIORS.md §3.4: with no state for 30 s the device shows the asleep
// look (breathing, zzZZ, backlight 60), with the unplugged icon in the
// strip; on reconnect the face blends to whatever the next state says.
static void test_no_app_at_30s_looks_asleep_and_reconnect_blends_back() {
  Rig r;
  r.at(1000);
  Model m = attn();  // even a stale "needs you" gives way
  m.wait = 1, m.busy = 2, m.quiet = 5;
  r.state(m);
  r.at(30999);
  TEST_ASSERT_EQUAL(Screen::kNeedsYou, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(1, r.b.strip(r.t).wait);
  r.at(31000);
  TEST_ASSERT_EQUAL(Screen::kNoApp, r.b.screen(r.t));
  TEST_ASSERT_EQUAL_STRING("asleep", r.b.faceName(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t));  // dimming with the face's blend
  TEST_ASSERT_TRUE(r.b.backlight(r.t + render::kBlendMs / 2) < 255);
  TEST_ASSERT_EQUAL_HEX32(0, r.b.led(r.t));
  // The strip keeps only the unplugged icon: the counts and quiet are stale.
  render::Strip strip = r.b.strip(r.t);
  TEST_ASSERT_TRUE(strip.noApp);
  TEST_ASSERT_EQUAL(0, strip.wait);
  TEST_ASSERT_EQUAL(0, strip.busy);
  TEST_ASSERT_FALSE(strip.quiet);
  r.at(31000 + render::kBlendMs);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  render::Pose p = r.b.pose(r.t);
  render::Pose asleep = render::lookPose(render::Look::kAsleep, 0);
  TEST_ASSERT_EQUAL_INT(asleep.open, p.open);
  TEST_ASSERT_TRUE(p.zzz > 0);
  TEST_ASSERT_TRUE(r.b.moving(r.t));  // breathing
  r.at(40000);
  const render::Pose before = r.b.pose(r.t);
  r.state(base("idle"));
  r.state(base("idle"));
  TEST_ASSERT_EQUAL(Screen::kFace, r.b.screen(r.t));
  TEST_ASSERT_EQUAL(Life::kNone, r.b.life(r.t));
  TEST_ASSERT_TRUE(r.b.pose(r.t) == before);  // from the asleep face, no cut
  TEST_ASSERT_TRUE(r.b.pose(r.t + render::kBlendMs / 2).open > 0);
  TEST_ASSERT_EQUAL_INT(render::lookPose(render::Look::kIdle, 0).open, r.b.pose(r.t + render::kBlendMs).open);
  TEST_ASSERT_EQUAL(60, r.b.backlight(r.t));
  TEST_ASSERT_EQUAL(255, r.b.backlight(r.t + render::kBlendMs));
}

// BEHAVIORS.md §3.3: push-to-talk listens at once on hold, and on release
// the same listening face carries on, with no new blend, while it waits for
// the reply. A moment from the Mac replaces it.
static void test_push_to_talk_listens_then_waits() {
  Rig r;
  r.state(base("idle"));
  r.b.talkOn(0);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.at(2000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  const render::Pose held = r.b.pose(r.t);
  const uint32_t seq = r.b.momentSeq();
  r.b.talkOff(2000);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  TEST_ASSERT_EQUAL(seq, r.b.momentSeq());          // the same moment
  TEST_ASSERT_TRUE(r.b.pose(r.t) == held);          // no jump
  TEST_ASSERT_EQUAL_STRING("listening", r.b.faceName(r.t));
  r.moment(Anim::kCheer);
  TEST_ASSERT_EQUAL(Anim::kCheer, r.anim());
}

// BEHAVIORS.md §3.3: listening lasts while held, capped at 30 s; after
// release it waits at most 8 s for the reply, then the face blends back
// quietly, with no other moment.
static void test_push_to_talk_timeouts() {
  TEST_ASSERT_EQUAL_UINT32(8000, Behaviour::kReplyWaitMs);
  TEST_ASSERT_EQUAL_UINT32(30000, render::animDuration(Anim::kListening));
  Rig r;
  Model m = base("idle");
  r.state(m);
  r.b.talkOn(0);
  keepAlive(r, m, 3000);
  r.b.talkOff(r.t);
  uint32_t left;
  TEST_ASSERT_EQUAL(Anim::kListening, r.b.moment(r.t, left));
  TEST_ASSERT_EQUAL_UINT32(8000, left);
  keepAlive(r, m, 3000 + 7999);
  TEST_ASSERT_EQUAL(Anim::kListening, r.anim());
  r.at(3000 + 8000);
  TEST_ASSERT_EQUAL(Anim::kNone, r.anim());  // no reply came
  TEST_ASSERT_EQUAL_STRING("idle", r.b.faceName(r.t));
  // Released late in the hold, the wait still runs its full 8 s past 30 s.
  Rig l;
  l.state(m);
  l.b.talkOn(0);
  keepAlive(l, m, 29000);
  l.b.talkOff(l.t);
  keepAlive(l, m, 29000 + 7999);
  TEST_ASSERT_EQUAL(Anim::kListening, l.anim());
  l.at(29000 + 8000);
  TEST_ASSERT_EQUAL(Anim::kNone, l.anim());
  // Held past the 30 s cap: listening ends then, and the release has
  // nothing left to wait on.
  Rig c;
  c.state(m);
  c.b.talkOn(0);
  keepAlive(c, m, 29999);
  TEST_ASSERT_EQUAL(Anim::kListening, c.anim());
  c.at(30000);
  TEST_ASSERT_EQUAL(Anim::kNone, c.anim());  // the cap
  c.at(31000);
  c.b.talkOff(c.t);
  TEST_ASSERT_EQUAL(Anim::kNone, c.anim());
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
  RUN_TEST(test_tap_during_needs_you_is_only_the_squash_and_stays_amber);
  RUN_TEST(test_answering_on_the_mac_blends_back);
  RUN_TEST(test_attention_wins_over_moments);
  RUN_TEST(test_changes_mid_motion_blend_from_what_was_showing);
  RUN_TEST(test_no_app_holds_for_weeks);
  RUN_TEST(test_no_change_ever_cuts_hard);
  RUN_TEST(test_face_name_is_the_moment_or_the_look);
  RUN_TEST(test_moments_end_and_replace);
  RUN_TEST(test_mumble_moves_the_mouth_and_respects_quiet);
  RUN_TEST(test_a_mumble_alone_plays_over_the_face);
  RUN_TEST(test_a_reply_ends_listening);
  RUN_TEST(test_the_empty_moment_ends_only_listening);
  RUN_TEST(test_life_is_blinks_at_their_pace);
  RUN_TEST(test_asleep_breathes_and_never_blinks);
  RUN_TEST(test_working_strains_and_sweats_and_asleep_says_zzz);
  RUN_TEST(test_working_keeps_moving_and_idle_rests);
  RUN_TEST(test_no_app_at_30s_looks_asleep_and_reconnect_blends_back);
  RUN_TEST(test_push_to_talk_listens_then_waits);
  RUN_TEST(test_push_to_talk_timeouts);
  RUN_TEST(test_press_shows_within_20ms);
  RUN_TEST(test_gestures_send_the_right_inputs);
  RUN_TEST(test_a_long_touch_during_needs_you_is_a_tap);
  return UNITY_END();
}
