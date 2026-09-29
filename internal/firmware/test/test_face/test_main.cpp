// The renderer: integer maths, the rasterizer, the names of the
// animations and moods, the strip and the bubble, fonts and the palette ramps (the v1 build plan's F2, L0).
#include <unity.h>

#include <cstring>
#include <utility>
#include <vector>

#include "render/anim.h"
#include "render/font.h"
#include "render/palette.h"
#include "render/raster.h"
#include "render/scene.h"
#include "render/screens.h"
#include "voice/player.h"

using namespace render;

void setUp() {}
void tearDown() {}

namespace {
struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  int count(uint8_t v) const {
    int n = 0;
    for (uint8_t p : px) n += p == v;
    return n;
  }
};

}  // namespace

static void test_isqrt_is_exact() {
  for (uint32_t v : {0u, 1u, 2u, 3u, 4u, 99u, 100u, 6399u, 6400u, 4294836225u, 4294967295u}) {
    uint64_t r = isqrt(v);
    TEST_ASSERT_TRUE(r * r <= v);
    TEST_ASSERT_TRUE((r + 1) * (r + 1) > v);
  }
}

static void test_ease_is_monotonic_from_0_to_1024() {
  TEST_ASSERT_EQUAL_INT(0, ease(0, 150));
  TEST_ASSERT_EQUAL_INT(512, ease(75, 150));
  TEST_ASSERT_EQUAL_INT(1024, ease(150, 150));
  int last = 0;
  for (int t = 0; t <= 150; ++t) {
    TEST_ASSERT_TRUE(ease(t, 150) >= last);
    last = ease(t, 150);
  }
}

static void test_spans_cut() {
  Spans s;
  s.add(0, 100);
  s.cut(40, 60);
  TEST_ASSERT_EQUAL_INT(2, s.n);
  TEST_ASSERT_EQUAL_INT(40, s.s[0].b);
  TEST_ASSERT_EQUAL_INT(60, s.s[1].a);
}

static void test_fill_shape_antialiases_only_the_edges() {
  Buf b;
  // A rectangle from x = 10.5 to 20 px, rows 5..10: column 10 is half covered.
  fillShape(5, 10, [](int sy) {
    Spans s;
    s.add(px(10) + 8, px(20));
    (void)sy;
    return s;
  }, [&](int x, int y, int level) { b.px[y * kWidth + x] = uint8_t(level); });
  TEST_ASSERT_EQUAL_INT(4, b.c.get(10, 7));
  TEST_ASSERT_EQUAL_INT(8, b.c.get(11, 7));
  TEST_ASSERT_EQUAL_INT(8, b.c.get(19, 7));
  TEST_ASSERT_EQUAL_INT(0, b.c.get(20, 7));
  TEST_ASSERT_EQUAL_INT(0, b.c.get(15, 10));
}

static void test_palette_ramps_run_from_black_to_the_ink() {
  TEST_ASSERT_EQUAL_HEX16(rgb565(kEyeRgb), paletteAt(inkAt(kInkEye, kLevels)));
  TEST_ASSERT_EQUAL_HEX16(rgb565(kAmberRgb), paletteAt(inkAt(kInkAmber, kLevels)));
  TEST_ASSERT_EQUAL_INT(kBlack, inkAt(kInkEye, 0));
  TEST_ASSERT_TRUE(kPaletteUsed <= 256);
  TEST_ASSERT_EQUAL_HEX16(rgb565(255, 0, 0), paletteAt(kRed));  // the bring-up pattern's colours stay
}

// BEHAVIORS.md §5: the animations, each by its design's state's name, and
// nothing else: the brain's finish (task_complete, reply_ready), the rules'
// one-shots (starting, stopped, error, helper_return), a tap's (poked,
// tap_spam) and listening. The older names read as the new: "cheer" is the
// finish, "wiggle" the poke. Each plays its own design, and every design
// has a loop (PROTOCOL.md §3).
static void test_every_anim_has_a_name_and_ends() {
  TEST_ASSERT_EQUAL_INT(10, int(Anim::kCount));  // with kNone
  const char* names[] = {"task_complete", "reply_ready", "starting", "stopped", "error",
                         "helper_return", "poked",       "tap_spam", "listening"};
  for (int i = 1; i < int(Anim::kCount); ++i) {
    Anim a = Anim(i);
    TEST_ASSERT_EQUAL_STRING(names[i - 1], animName(a));
    TEST_ASSERT_TRUE(animFromName(animName(a)) == a);
    TEST_ASSERT_EQUAL_STRING(animName(a), stateName(animState(a)));  // its own design
  }
  TEST_ASSERT_TRUE(animFromName("cheer") == Anim::kTaskComplete);
  TEST_ASSERT_TRUE(animFromName("wiggle") == Anim::kPoked);
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int s = 0; s < int(SceneState::kCount); ++s) TEST_ASSERT_TRUE(loopMs(Mood(m), SceneState(s)) > 0);
  }
  for (const char* gone : {"dance", "oops", "side_eye", "stretch", "yawn", "zip", "gobble", "rumble", "levelup",
                           "happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love", "nod",
                           "thinking", "shrug", "idle", "working", "terminal", "needs_you", "no_app", "none"}) {
    TEST_ASSERT_TRUE_MESSAGE(animFromName(gone) == Anim::kNone, gone);
  }
}

// harness/DECISIONS.md §2.3: the thirteen moods of the mood graph, by the
// names the Mac sends, in faces.h's order, the first seven keeping their
// numbers (PROTOCOL.md §3); a missing or unknown one is happy.
static void test_every_mood_has_a_name() {
  TEST_ASSERT_EQUAL_INT(13, int(Mood::kCount));
  for (int i = 0; i < int(Mood::kCount); ++i) TEST_ASSERT_TRUE(moodFromName(moodName(Mood(i))) == Mood(i));
  const char* names[] = {"happy", "excited", "proud",     "curious", "determined", "grumpy", "sad",
                         "calm",  "engaged", "annoyed", "irritated", "whiny",      "wounded"};
  for (int i = 0; i < 13; ++i) TEST_ASSERT_EQUAL_STRING(names[i], moodName(Mood(i)));
  for (const char* other : {"cheerful", "sleepy", "angry", "", "Happy", "Calm"}) {
    TEST_ASSERT_TRUE_MESSAGE(moodFromName(other) == Mood::kHappy, other);
    Mood m = Mood::kSad;
    TEST_ASSERT_FALSE_MESSAGE(parseMood(other, m), other);
    TEST_ASSERT_TRUE(m == Mood::kSad);  // untouched
  }
  TEST_ASSERT_TRUE(moodFromName(nullptr) == Mood::kHappy);
}

// PROTOCOL.md §3: the designs' 22 states by name, in faces.h's order, the
// first seven keeping their numbers; a missing or unknown one is idle.
static void test_every_state_has_a_name() {
  TEST_ASSERT_EQUAL_INT(22, int(SceneState::kCount));
  const char* names[] = {"idle",      "working",   "needs_you",  "task_complete", "asleep",  "no_app",
                         "listening", "starting",  "planning",   "terminal",      "tool_use", "searching",
                         "analyzing", "testing",   "delegating", "helper_return", "waiting", "reply_ready",
                         "error",     "stopped",   "poked",      "tap_spam"};
  for (int i = 0; i < 22; ++i) {
    TEST_ASSERT_EQUAL_STRING(names[i], stateName(SceneState(i)));
    TEST_ASSERT_TRUE(stateFromName(names[i]) == SceneState(i));
  }
  for (const char* other : {"cheer", "busy", "", "Idle"}) TEST_ASSERT_TRUE_MESSAGE(stateFromName(other) == SceneState::kIdle, other);
  TEST_ASSERT_TRUE(stateFromName(nullptr) == SceneState::kIdle);
}

static void test_an_empty_strip_is_bare_glass() {
  // With nothing to count or flag, the strip shows nothing, not even its
  // divider; with anything, the divider is there.
  auto lit = [](const Strip& s) {
    Buf b;
    drawStrip(b.c, s);
    int n = 0;
    for (uint8_t v : b.px) n += v != kBlack;
    return n;
  };
  TEST_ASSERT_EQUAL_INT(0, lit(Strip{}));
  Strip busy, noApp, needsYou;
  busy.busy = 1, noApp.noApp = true, needsYou.agent = "codex";
  for (const Strip& s : {busy, noApp, needsYou}) {
    Buf b;
    drawStrip(b.c, s);
    TEST_ASSERT_EQUAL_INT(inkAt(kInkDim, kLevels), b.c.get(kWidth / 2, kStripTop));
  }
}

// While something needs you, the strip says who in amber, cut to
// leave room for "+N" and the working count, which stay whole.
static void test_the_strip_says_who_needs_you() {
  auto amberCols = [](const Strip& s, int& last) {
    Buf b;
    drawStrip(b.c, s);
    int n = 0;
    last = -1;
    for (int x = 0; x < kWidth; ++x) {
      bool lit = false;
      for (int y = kStripTop + 1; y < kHeight; ++y) lit = lit || b.c.get(x, y) == inkAt(kInkAmber, kLevels);
      if (lit) ++n, last = x;
    }
    return n;
  };
  Strip who, longWho;
  who.agent = "codex", who.project = "landing", who.more = 1, who.busy = 1;
  longWho = who, longWho.project = "a-really-long-project..";
  int lastWho, lastLong;
  TEST_ASSERT_TRUE(amberCols(who, lastWho) > 0);
  amberCols(longWho, lastLong);
  TEST_ASSERT_TRUE(lastLong > lastWho);  // "codex · a-really-lo.." takes the room there is
  Buf b;
  drawStrip(b.c, longWho);
  bool grey = false;  // the working count still shows, in grey, at the right of the cut name
  for (int x = lastLong + 1; x < kWidth - 12; ++x) {
    for (int y = kStripTop + 1; y < kHeight; ++y) grey = grey || b.c.get(x, y) == inkAt(kInkGrey, kLevels);
  }
  TEST_ASSERT_TRUE(grey);
  TEST_ASSERT_TRUE(lastLong < kWidth - 12);
  // The thread's name shows in the project's place: "codex · a-really-lo.."
  // drawn as a name is the same pixels as drawn as a project.
  Strip named = who;
  named.name = longWho.project;
  Buf asName, asProject;
  drawStrip(asName.c, named);
  drawStrip(asProject.c, longWho);
  TEST_ASSERT_EQUAL_MEMORY(asProject.c.pixels(), asName.c.pixels(), kWidth * kHeight);
}

// DEVICE.md §4: the bubble shows the take's text, in amber, centred;
// every take's text fits whole inside the margins ("Bada bing bada boom" is
// the longest), and only text too long for the bubble ends "..".
static void test_the_bubble_fits_every_take() {
  auto draw = [](const char* text, int& left, int& right) {
    Buf b;
    drawFaceScreen(b.c, SceneShow{}, text, Strip{});
    int n = 0;
    left = kWidth, right = -1;
    for (int y = kLaneTop; y < kHeight; ++y) {
      for (int x = 0; x < kWidth; ++x) {
        if (b.c.get(x, y) != inkAt(kInkAmber, kLevels)) continue;
        ++n;
        if (x < left) left = x;
        if (x > right) right = x;
      }
      for (int x : {0, 11, kWidth - 12, kWidth - 1}) TEST_ASSERT_EQUAL_INT(kBlack, b.c.get(x, y));
    }
    return n;
  };
  for (int i = 0; i < voice::takeCount(); ++i) {
    const char* text = voice::takeText(i);
    TEST_ASSERT_TRUE(std::strlen(text) <= 20);
    int left, right;
    TEST_ASSERT_TRUE(draw(text, left, right) > 0);
    TEST_ASSERT_INT_WITHIN(kLarge.w, kWidth - 1 - right, left);  // centred
    // Whole: its last letter is drawn where the fitted width puts it.
    TEST_ASSERT_INT_WITHIN(kLarge.w, stringWidth(kLarge, text), right - left + 1);
  }
  int left, right;
  draw("a very long line that cannot fit", left, right);  // cut, but inside the margins
}

// DEVICE.md §4, decision D10: the bubble sits in the bottom lane, below
// y 192, which the animation bank's designs leave for text: it takes the
// strip's place while it shows and leaves the design above untouched. Over
// a design that draws to the bottom (the first pack's success), it blanks the
// lane first.
static void test_the_bubble_takes_the_lane() {
  const char* m = "Yay";
  Strip s;
  s.busy = 2, s.doneAgent = "codex", s.doneThread = "landing", s.doneOutcome = Outcome::kSuccess;
  for (SceneState st : {SceneState::kIdle, SceneState::kTaskComplete}) {
    SceneShow face;
    face.state = st;
    Buf with, without, face0;
    drawFaceScreen(with.c, face, m, s);
    drawFaceScreen(without.c, face, nullptr, s);
    drawFaceScreen(face0.c, face, nullptr, Strip{});
    for (int y = 0; y < kLaneTop; ++y) {  // the design, as it was
      for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(face0.c.get(x, y), with.c.get(x, y));
    }
    int amber = 0, eye = 0;
    for (int y = kLaneTop; y < kHeight; ++y) {
      for (int x = 0; x < kWidth; ++x) {
        uint8_t v = with.c.get(x, y);
        amber += v == inkAt(kInkAmber, kLevels);
        eye += v == inkAt(kInkEye, kLevels);
        TEST_ASSERT_TRUE(v < faces::kSceneBase);  // the design's colours are gone from the lane
      }
    }
    TEST_ASSERT_TRUE(amber > 20);   // the word
    TEST_ASSERT_EQUAL_INT(0, eye);  // not the strip's names, which show without it
    int names = 0;
    for (int y = kStripTop; y < kHeight; ++y) {
      for (int x = 0; x < kWidth; ++x) names += without.c.get(x, y) == inkAt(kInkEye, kLevels);
    }
    TEST_ASSERT_TRUE(names > 20);
  }
}

// BEHAVIORS.md §5: while the brain's finish plays, the strip names whose
// turn it was after a mark for its result: a tick for a success, a cross
// for a failure, three dots for a reply; each draws differently.
static void test_the_strip_marks_the_finish() {
  auto mark = [](Outcome o) {
    Strip s;
    s.doneAgent = "codex", s.doneThread = "landing", s.doneOutcome = o;
    Buf b;
    drawStrip(b.c, s);
    std::vector<uint8_t> icon;
    for (int y = kStripTop + 1; y < kHeight; ++y) {
      for (int x = 0; x < 28; ++x) icon.push_back(b.c.get(x, y));
    }
    return icon;
  };
  auto tick = mark(Outcome::kSuccess), cross = mark(Outcome::kFailure), dots = mark(Outcome::kNone);
  TEST_ASSERT_TRUE(tick != cross && cross != dots && tick != dots);
  for (const auto& icon : {tick, cross, dots}) {
    int lit = 0;
    for (uint8_t v : icon) lit += v == inkAt(kInkEye, kLevels);
    TEST_ASSERT_TRUE(lit > 0);
  }
}

static void test_fonts_are_monospaced_and_utf8_aware() {
  TEST_ASSERT_EQUAL_INT(3 * kSmall.w, stringWidth(kSmall, "abc"));
  TEST_ASSERT_EQUAL_INT(3 * kLarge.w, stringWidth(kLarge, "a\xC2\xB7" "b"));  // "·" is one glyph
  Buf b;
  int end = drawString(b.c, kSmall, 10, 10, "Hi", kInkAmber);
  TEST_ASSERT_EQUAL_INT(10 + 2 * kSmall.w, end);
  TEST_ASSERT_TRUE(b.count(inkAt(kInkAmber, kLevels)) > 10);
  Buf fit;
  int w = drawStringFit(fit.c, kSmall, 0, 0, "a-very-long-project-name", kInkAmber, 10 * kSmall.w);
  TEST_ASSERT_TRUE(w <= 10 * kSmall.w);
  // Accented letters show plain, anything else outside the font
  // as one "?" per character.
  Buf accented, plain, other, marks;
  TEST_ASSERT_EQUAL_INT(4 * kSmall.w, stringWidth(kSmall, "caf\xC3\xA9"));
  drawString(accented.c, kSmall, 0, 0, "caf\xC3\xA9 \xC3\x9C" "ber", kInkAmber);
  drawString(plain.c, kSmall, 0, 0, "cafe Uber", kInkAmber);
  TEST_ASSERT_TRUE(accented.px == plain.px);
  TEST_ASSERT_EQUAL_INT(2 * kSmall.w, stringWidth(kSmall, "\xED\x94\x84\xEB\xA1\x9C"));  // two Hangul syllables
  drawString(other.c, kSmall, 0, 0, "\xED\x94\x84\xEB\xA1\x9C", kInkAmber);
  drawString(marks.c, kSmall, 0, 0, "??", kInkAmber);
  TEST_ASSERT_TRUE(other.px == marks.px);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_isqrt_is_exact);
    RUN_TEST(test_ease_is_monotonic_from_0_to_1024);
  RUN_TEST(test_spans_cut);
  RUN_TEST(test_fill_shape_antialiases_only_the_edges);
  RUN_TEST(test_palette_ramps_run_from_black_to_the_ink);
  RUN_TEST(test_every_anim_has_a_name_and_ends);
  RUN_TEST(test_every_mood_has_a_name);
  RUN_TEST(test_every_state_has_a_name);
  RUN_TEST(test_an_empty_strip_is_bare_glass);
  RUN_TEST(test_the_strip_says_who_needs_you);
  RUN_TEST(test_the_bubble_fits_every_take);
  RUN_TEST(test_the_bubble_takes_the_lane);
  RUN_TEST(test_the_strip_marks_the_finish);
  RUN_TEST(test_fonts_are_monospaced_and_utf8_aware);
  return UNITY_END();
}
