// The mood designs as the device draws them: a scene for
// each mood and state, from firmware/assets/faces.h, which
// internal/tools/facegen/facegen.py generates from the designs' SVGs. A
// scene is rectangles in groups that move and show in whole-pixel steps on
// the scene's own clock, so the device draws each design exactly as the
// SVG does. The few things the device adds of its own are in SceneShow.
#pragma once
#include <cstdint>

#include "render/anim.h"
#include "render/canvas.h"

namespace render {

// The designs' states, in faces.h's order. The task_complete design shows
// the cheer; the others are the looks, what the face shows when no moment
// plays.
enum class SceneState : uint8_t { kIdle, kWorking, kNeedsYou, kTaskComplete, kAsleep, kNoApp, kCount };
// "idle", "working", "needs_you", "task_complete", "asleep", "no_app".
const char* stateName(SceneState s);
SceneState stateFromName(const char* name);  // kIdle if missing or unknown

struct SceneShow {
  Mood mood = Mood::kHappy;
  SceneState state = SceneState::kIdle;
  uint32_t t = 0;          // ms since the scene started
  bool eyesShut = false;   // a blink: the design's closed eyes instead of its open ones
  bool hideProp = false;   // the bubble has the prop's room: no keyboard, sign or card
  bool mouthOpen = false;  // talking: a small "o" instead of the mouth
  int16_t dx = 0, dy = 0;  // the face moved: a tap's sway, a press
  uint8_t heart = 0;       // a tap: a coral heart by the right eye, 1 small or 2 full size
};

// Everything a scene's pixels depend on: the scene, the additions, and
// where each group sits and whether it shows. Two shows with the same frame
// draw the same pixels, so the device skips drawing one whose frame hasn't
// changed (plan/DEVICE.md §6). A step to the same place (the designs often
// hold a value over several steps) leaves the frame as it was.
struct SceneFrame {
  static constexpr int kMaxGroups = 40;  // groups in a scene; faces.h checks it
  uint8_t scene = 0xFF, flags = 0;
  int16_t x[kMaxGroups] = {}, y[kMaxGroups] = {};  // 0 while the group doesn't show
  uint8_t on[kMaxGroups] = {};
};
bool operator==(const SceneFrame& a, const SceneFrame& b);
inline bool operator!=(const SceneFrame& a, const SceneFrame& b) { return !(a == b); }

// The scene a mood and state show: every mood shares one asleep and one no-app scene.
int sceneOf(Mood m, SceneState s);
// How long that design takes to play once through, in ms (faces.h's
// loopMs): what a moment's loops count (plan/PROTOCOL.md §3).
uint32_t loopMs(Mood m, SceneState s);
SceneFrame sceneFrame(const SceneShow& s);
// Draws the scene over what's on the canvas; the screen clears it first.
void drawScene(Canvas& c, const SceneShow& s);
// Where the tap's heart is centred, before the face moves.
constexpr int kHeartX = 268, kHeartY = 60;
// The palette entry for a design colour (faces::Color), for the tests.
uint8_t sceneInk(int color);

}  // namespace render
