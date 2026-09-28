// The animation pack's player (render/scene.h) against facegen's own
// drawing of the designs, which facegen --check holds to Chrome's drawing
// of the SVGs (plan/VERIFICATION.md L0).
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

SceneShow show(Mood m, SceneState s, uint32_t t = 0, int variant = 0) {
  SceneShow v;
  v.mood = m, v.state = s, v.t = t, v.variant = uint8_t(variant);
  return v;
}

// Where two drawings differ: the box around every pixel that does, or none.
struct Box {
  int x0 = kWidth, y0 = kHeight, x1 = -1, y1 = -1;
  bool empty() const { return x1 < 0; }
};
Box differ(const Buf& a, const Buf& b) {
  Box d;
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      if (a.at(x, y) == b.at(x, y)) continue;
      if (x < d.x0) d.x0 = x;
      if (y < d.y0) d.y0 = y;
      if (x > d.x1) d.x1 = x;
      if (y > d.y1) d.y1 = y;
    }
  }
  return d;
}

}  // namespace

// Every sampled moment of every design, every variation, draws facegen's
// pixels exactly: the same palette index everywhere.
static void test_every_scene_matches_facegen() {
  Buf b;
  int failed = 0;
  for (const FacegenFrame& f : kFacegenFrames) {
    b.draw(show(Mood(f.mood), SceneState(f.state), f.t, f.variant));
    uint32_t crc = app::crc32(b.px.data(), b.px.size());
    if (crc != f.crc) {
      char msg[64];
      std::snprintf(msg, sizeof msg, "mood %d state %d variant %d at %u ms", f.mood, f.state, f.variant + 1,
                    unsigned(f.t));
      TEST_MESSAGE(msg);
      ++failed;
    }
  }
  TEST_ASSERT_EQUAL_INT(0, failed);
  TEST_ASSERT_TRUE(sizeof(kFacegenFrames) / sizeof(kFacegenFrames[0]) > 1000);
}

// Each state has its variations, each a design of its own; one out of range
// draws the first. Asleep and with no app, Boop looks the same in every mood.
static void test_variations_and_shared_designs() {
  const int want[] = {3, 5, 3, 3, 3, 3, 3};  // idle, working, needs you, the cheer, asleep, no app, listening
  for (int s = 0; s < int(SceneState::kCount); ++s) {
    TEST_ASSERT_EQUAL_INT(want[s], variants(SceneState(s)));
    for (int v = 1; v < variants(SceneState(s)); ++v) {
      TEST_ASSERT_NOT_EQUAL(sceneOf(Mood::kHappy, SceneState(s), 0), sceneOf(Mood::kHappy, SceneState(s), v));
    }
    TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kHappy, SceneState(s), 0), sceneOf(Mood::kHappy, SceneState(s), 9));
  }
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int v = 0; v < 3; ++v) {
      TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kHappy, SceneState::kAsleep, v), sceneOf(Mood(m), SceneState::kAsleep, v));
      TEST_ASSERT_EQUAL_INT(sceneOf(Mood::kHappy, SceneState::kNoApp, v), sceneOf(Mood(m), SceneState::kNoApp, v));
    }
    if (m) TEST_ASSERT_NOT_EQUAL(sceneOf(Mood::kHappy, SceneState::kIdle), sceneOf(Mood(m), SceneState::kIdle));
  }
}

// A blink shows the design's closed eyes: only the face changes.
static void test_a_blink_shows_the_closed_eyes() {
  for (int m = 0; m < int(Mood::kCount); ++m) {
    Buf open, shut;
    open.draw(show(Mood(m), SceneState::kIdle));
    SceneShow s = show(Mood(m), SceneState::kIdle);
    s.eyesShut = true;
    shut.draw(s);
    Box d = differ(open, shut);
    TEST_ASSERT_FALSE(d.empty());
    TEST_ASSERT_TRUE(d.y0 >= 40 && d.y1 < 130);  // the eyes, above the mouth
  }
}

// The bubble takes the props' room: the working props go, the face stays.
static void test_the_prop_can_make_room() {
  for (int v = 0; v < variants(SceneState::kWorking); ++v) {
    Buf with, without;
    with.draw(show(Mood::kHappy, SceneState::kWorking, 0, v));
    SceneShow s = show(Mood::kHappy, SceneState::kWorking, 0, v);
    s.hideProp = true;
    without.draw(s);
    Box d = differ(with, without);
    TEST_ASSERT_FALSE(d.empty());
    TEST_ASSERT_TRUE(d.y0 >= 144);  // the props' band (render/screens.h kBubbleTop)
  }
}

// Talking, the mouth is a small "o" where it was.
static void test_the_mouth_opens_to_talk() {
  Buf closed, talking;
  closed.draw(show(Mood::kHappy, SceneState::kIdle));
  SceneShow s = show(Mood::kHappy, SceneState::kIdle);
  s.mouthOpen = true;
  talking.draw(s);
  Box d = differ(closed, talking);
  TEST_ASSERT_FALSE(d.empty());
  TEST_ASSERT_TRUE(d.x0 >= 145 && d.x1 < 175 && d.y0 >= 125 && d.y1 < 142);
  TEST_ASSERT_EQUAL(sceneInk(1), talking.at(154, 129));  // the o's ring
  TEST_ASSERT_EQUAL(kBlack, talking.at(160, 134));       // its hole
}

// A tap's sway or a press moves the whole face; the props stay.
static void test_the_face_moves_as_one() {
  Buf still, moved, back;
  still.draw(show(Mood::kHappy, SceneState::kWorking));
  SceneShow s = show(Mood::kHappy, SceneState::kWorking);
  s.dx = 3, s.dy = 2;
  moved.draw(s);
  int same = 0, face = 0;
  for (int y = 40; y < 140; ++y) {
    for (int x = 40; x < 290; ++x) {
      if (still.at(x, y) == kBlack) continue;
      ++face;
      same += moved.at(x + 3, y + 2) == still.at(x, y);
    }
  }
  TEST_ASSERT_TRUE(face > 100);
  TEST_ASSERT_TRUE(same * 10 >= face * 9);  // the face, shifted
  for (int y = 180; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(still.at(x, y), moved.at(x, y));  // the props, not
  }
}

// Needs you's art stays above y 192: the bottom 48 px are the strip's.
static void test_needs_you_leaves_the_bottom_lane() {
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int v = 0; v < variants(SceneState::kNeedsYou); ++v) {
      for (uint32_t t : {0u, 700u, 1500u, 3000u}) {
        Buf b;
        b.draw(show(Mood(m), SceneState::kNeedsYou, t, v));
        for (int y = 192; y < kHeight; ++y) {
          for (int x = 0; x < kWidth; ++x) TEST_ASSERT_EQUAL(kBlack, b.at(x, y));
        }
      }
    }
  }
}

// DEVICE.md §6: a frame changes when a step or an addition does, and only then.
static void test_frames_change_only_when_the_picture_can() {
  SceneShow a = show(Mood::kExcited, SceneState::kWorking, 1000);
  SceneShow b = a;
  b.t = 1001;
  TEST_ASSERT_TRUE(sceneFrame(a) == sceneFrame(b));
  bool changed = false;
  for (uint32_t t = 1000; t < 3000 && !changed; t += 10) b.t = t, changed = sceneFrame(a) != sceneFrame(b);
  TEST_ASSERT_TRUE(changed);
  b = a;
  b.eyesShut = true;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.mood = Mood::kSad;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.variant = 1;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
  b = a;
  b.dy = 1;
  TEST_ASSERT_TRUE(sceneFrame(a) != sceneFrame(b));
}

// A cheer's gold fades show in the frame: the colour steps count as changes.
static void test_a_fade_changes_the_frame() {
  bool changed = false;
  SceneShow a = show(Mood::kHappy, SceneState::kTaskComplete, 0);
  for (uint32_t t = 0; t < 6400 && !changed; t += 20) {
    SceneShow b = a;
    b.t = t;
    SceneFrame fa = sceneFrame(a), fb = sceneFrame(b);
    for (int i = 0; i < SceneFrame::kMaxGroups; ++i) changed = changed || fa.fill[i] != fb.fill[i];
  }
  TEST_ASSERT_TRUE(changed);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_every_scene_matches_facegen);
  RUN_TEST(test_variations_and_shared_designs);
  RUN_TEST(test_a_blink_shows_the_closed_eyes);
  RUN_TEST(test_the_prop_can_make_room);
  RUN_TEST(test_the_mouth_opens_to_talk);
  RUN_TEST(test_the_face_moves_as_one);
  RUN_TEST(test_needs_you_leaves_the_bottom_lane);
  RUN_TEST(test_frames_change_only_when_the_picture_can);
  RUN_TEST(test_a_fade_changes_the_frame);
  return UNITY_END();
}
