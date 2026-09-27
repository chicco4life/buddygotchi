// The mood designs' player (render/scene.h) against facegen's own drawing
// of them, which facegen --check holds to Chrome's drawing of the SVGs
// (plan/UX.md §2, plan/VERIFICATION.md L0).
#include <unity.h>

#include <cstdio>
#include <vector>

#include "app/codec.h"
#include "frames.h"
#include "render/palette.h"
#include "render/scene.h"

using namespace render;

void setUp() {}
void tearDown() {}

namespace {

constexpr int kColors = 7;  // faces::Color, with the black field

struct Buf {
  std::vector<uint8_t> px = std::vector<uint8_t>(size_t(kWidth) * kHeight, 0);
  Canvas c{px.data()};
  // Draws the show on black, as facegen does.
  Buf& draw(const SceneShow& s) {
    c.fill(kBlack);
    drawScene(c, s);
    return *this;
  }
  uint8_t at(int x, int y) const { return px[size_t(y) * kWidth + x]; }
};

SceneShow show(Mood m, SceneState s, uint32_t t = 0) {
  SceneShow v;
  v.mood = m, v.state = s, v.t = t;
  return v;
}

const uint8_t kInkFull = sceneInk(1);

}  // namespace

// Every sampled moment of every design draws facegen's pixels exactly.
static void test_every_scene_matches_facegen() {
  uint8_t colorOf[256] = {};
  for (int c = 1; c < kColors; ++c) colorOf[sceneInk(c)] = uint8_t(c);
  Buf b;
  std::vector<uint8_t> colors(b.px.size());
  int failed = 0;
  for (const FacegenFrame& f : kFacegenFrames) {
    b.draw(show(Mood(f.mood), SceneState(f.state), f.t));
    for (size_t i = 0; i < b.px.size(); ++i) colors[i] = colorOf[b.px[i]];
    uint32_t crc = app::crc32(colors.data(), colors.size());
    if (crc != f.crc) {
      char msg[64];
      std::snprintf(msg, sizeof msg, "mood %d state %d at %u ms", f.mood, f.state, unsigned(f.t));
      TEST_MESSAGE(msg);
      ++failed;
    }
  }
  TEST_ASSERT_EQUAL_INT(0, failed);
  TEST_ASSERT_TRUE(sizeof(kFacegenFrames) / sizeof(kFacegenFrames[0]) > 300);
}

// UX.md §2: asleep and with no app, Boop looks the same in every mood.
static void test_asleep_and_no_app_ignore_the_mood() {
  for (int m = 0; m < int(Mood::kCount); ++m) {
    TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kHappy, SceneState::kAsleep), sceneOf(Mood(m), SceneState::kAsleep));
    TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kHappy, SceneState::kNoApp), sceneOf(Mood(m), SceneState::kNoApp));
    if (m) TEST_ASSERT_NOT_EQUAL(sceneOf(Mood::kHappy, SceneState::kIdle), sceneOf(Mood(m), SceneState::kIdle));
  }
}

// A blink shows the design's closed eyes, a bar across each eye at y 99–103.
static void test_a_blink_shows_the_closed_eyes() {
  Buf open, shut;
  open.draw(show(Mood::kHappy, SceneState::kIdle));
  SceneShow s = show(Mood::kHappy, SceneState::kIdle);
  s.eyesShut = true;
  shut.draw(s);
  TEST_ASSERT_EQUAL(kInkFull, open.at(70, 72));    // the left eye's top-left pane
  TEST_ASSERT_EQUAL(kBlack, open.at(88, 101));     // its cross
  TEST_ASSERT_EQUAL(kBlack, shut.at(70, 72));
  TEST_ASSERT_EQUAL(kInkFull, shut.at(88, 101));   // the closed bar
  TEST_ASSERT_EQUAL(kInkFull, shut.at(232, 101));  // and the right eye's
}

// The bubble takes the prop's room: the keyboard goes, the face stays.
static void test_the_prop_can_make_room() {
  Buf with, without;
  with.draw(show(Mood::kHappy, SceneState::kWorking));
  SceneShow s = show(Mood::kHappy, SceneState::kWorking);
  s.hideProp = true;
  without.draw(s);
  TEST_ASSERT_EQUAL(sceneInk(5), with.at(100, 193));  // the keyboard's frame
  TEST_ASSERT_EQUAL(kBlack, without.at(100, 193));
  for (int y = 0; y < 150; ++y) {
    for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(with.at(x, y), without.at(x, y));
  }
  // The cheer's sparkles by the card, outside the card's own group, go too.
  Buf sparkles, none;
  sparkles.draw(show(Mood::kHappy, SceneState::kTaskComplete, 600));
  SceneShow t = show(Mood::kHappy, SceneState::kTaskComplete, 600);
  t.hideProp = true;
  none.draw(t);
  TEST_ASSERT_EQUAL(sceneInk(4), sparkles.at(129, 168));
  TEST_ASSERT_EQUAL(kBlack, none.at(129, 168));
}

// Talking, the mouth is a small "o" where it was, moving with the face.
static void test_the_mouth_opens_to_talk() {
  Buf closed, talking;
  closed.draw(show(Mood::kHappy, SceneState::kIdle));
  SceneShow s = show(Mood::kHappy, SceneState::kIdle);
  s.mouthOpen = true;
  talking.draw(s);
  TEST_ASSERT_EQUAL(kInkFull, closed.at(160, 134));  // the smile's bottom
  TEST_ASSERT_EQUAL(kBlack, closed.at(154, 129));
  TEST_ASSERT_EQUAL(kBlack, talking.at(160, 134));   // the o's hole
  TEST_ASSERT_EQUAL(kInkFull, talking.at(154, 129));  // its ring
  TEST_ASSERT_EQUAL(kBlack, talking.at(147, 134));   // the smile is gone
}

// A tap's sway or a press moves the whole face, props aside.
static void test_the_face_moves_as_one() {
  Buf still, moved;
  still.draw(show(Mood::kHappy, SceneState::kWorking));
  SceneShow s = show(Mood::kHappy, SceneState::kWorking);
  s.dx = 3, s.dy = 2;
  moved.draw(s);
  TEST_ASSERT_EQUAL(kInkFull, still.at(70, 80));  // an eye, below working's lowered lid
  TEST_ASSERT_EQUAL(kInkFull, moved.at(73, 82));
  TEST_ASSERT_EQUAL(kInkFull, moved.at(163, 136));  // the smile
  TEST_ASSERT_EQUAL(sceneInk(5), moved.at(100, 193));  // the keyboard stays
}

// DEVICE.md §6: a frame changes when a step or an addition does, and only then.
static void test_frames_change_only_when_the_picture_can() {
  SceneShow a = show(Mood::kExcited, SceneState::kWorking, 1000);
  SceneShow b = a;
  b.t = 1001;
  TEST_ASSERT_TRUE(sceneFrame(a) == sceneFrame(b));
  bool changed = false;
  for (uint32_t t = 1000; t < 3000 && !changed; t += 10) b.t = t, changed = sceneFrame(a) != sceneFrame(b);
  TEST_ASSERT_TRUE(changed);  // the keyboard's keys light in turn
  b = a;
  b.eyesShut = true;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.mood = Mood::kSad;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.dy = 1;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
}

// A gesture that plays once holds its last step: task_complete's card rises
// over 1.4 s and stays.
static void test_once_gestures_settle() {
  SceneShow a = show(Mood::kHappy, SceneState::kTaskComplete, 5000);
  SceneShow b = a;
  b.t = 60000;
  TEST_ASSERT_TRUE(sceneFrame(a) == sceneFrame(b));
  Buf start, settled;
  start.draw(show(Mood::kHappy, SceneState::kTaskComplete, 0));
  settled.draw(show(Mood::kHappy, SceneState::kTaskComplete, 5000));
  TEST_ASSERT_EQUAL(kBlack, start.at(160, 163));  // the card starts 6 px low
  TEST_ASSERT_EQUAL(kInkFull, settled.at(150, 163));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_every_scene_matches_facegen);
  RUN_TEST(test_asleep_and_no_app_ignore_the_mood);
  RUN_TEST(test_a_blink_shows_the_closed_eyes);
  RUN_TEST(test_the_prop_can_make_room);
  RUN_TEST(test_the_mouth_opens_to_talk);
  RUN_TEST(test_the_face_moves_as_one);
  RUN_TEST(test_frames_change_only_when_the_picture_can);
  RUN_TEST(test_once_gestures_settle);
  return UNITY_END();
}
