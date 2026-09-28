// The animation bank's designs as the device draws them: a scene for each
// mood, state and variation, from firmware/assets/faces.h, which
// internal/tools/facegen/facegen.py generates from the designs' SVGs. A
// scene is rectangles in groups that move, show and change colour in
// steps on the scene's own clock, so the device draws each design as the
// SVG does. The few things the device adds of its own are in SceneShow.
#pragma once
#include <cstdint>

#include "render/anim.h"
#include "render/canvas.h"

namespace render {

// The designs' states, in faces.h's order (plan/PROTOCOL.md §3): the first
// seven keep the numbers they had before the rest came. The task_complete
// design shows the cheer and the listening design push-to-talk's listening;
// the other five of the first seven are the looks, what the face shows when
// no moment plays. Nothing asks for the states after listening yet.
enum class SceneState : uint8_t {
  kIdle, kWorking, kNeedsYou, kTaskComplete, kAsleep, kNoApp, kListening,
  kStarting, kPlanning, kTerminal, kToolUse, kSearching, kAnalyzing, kTesting,
  kDelegating, kHelperReturn, kWaiting, kReplyReady, kError, kStopped, kPoked, kTapSpam,
  kCount
};
// "idle", "working", "needs_you", "task_complete", "asleep", "no_app",
// "listening", "starting", "planning", "terminal", "tool_use", "searching",
// "analyzing", "testing", "delegating", "helper_return", "waiting",
// "reply_ready", "error", "stopped", "poked", "tap_spam".
const char* stateName(SceneState s);
SceneState stateFromName(const char* name);  // kIdle if missing or unknown

// Each mood has its own variations of each state's design, 1 to kMaxVariants
// of them; a variation is 0..variants(m, s) - 1 here, and 1..variants(m, s)
// on the wire (PROTOCOL.md §3). One out of range draws the first.
constexpr int kMaxVariants = 9;  // faces.h checks it
int variants(Mood m, SceneState s);

// The host fact a variation is for, when it's for one: task_complete's
// outcome and starting's context (plan/PROTOCOL.md §3). kNone on a design
// is for any; as a filter, it takes any.
enum class Outcome : uint8_t { kNone, kSuccess, kFailure };
enum class StartCtx : uint8_t { kNone, kNewTask, kSession, kContinuation };
Outcome outcomeFromName(const char* name);  // "success" or "failure"; kNone otherwise
StartCtx ctxFromName(const char* name);     // "new_task", "session" or "continuation"; kNone otherwise
const char* outcomeName(Outcome o);         // "" for kNone
const char* ctxName(StartCtx c);            // "" for kNone
Outcome variantOutcome(Mood m, SceneState s, int variant);  // the first's for one out of range
StartCtx variantCtx(Mood m, SceneState s, int variant);
// The variations (from 0) of m's design for s that fit an outcome and a
// context, kNone fitting any, in order into `out` (room for kMaxVariants),
// and how many; every variation when none fits, as the Mac's
// FaceLoops.variants does.
int fitting(Mood m, SceneState s, Outcome o, StartCtx c, uint8_t* out);

struct SceneShow {
  Mood mood = Mood::kHappy;
  SceneState state = SceneState::kIdle;
  uint8_t variant = 0;     // from 0; one out of range draws the first
  uint32_t t = 0;          // ms since the scene started
  bool eyesShut = false;   // a blink: the design's closed eyes instead of its open ones
  bool hideProp = false;   // the bubble has the prop's room: no props
  bool mouthOpen = false;  // talking: a small "o" instead of the mouth
  int16_t dx = 0, dy = 0;  // the face moved: a tap's sway, a press
  uint8_t heart = 0;       // a tap: a coral heart by the right eye, 1 small or 2 full size
};

// Everything a scene's pixels depend on: the scene, the additions, and
// where each group sits, whether it shows and its fill. Two shows with the
// same frame draw the same pixels, so the device skips drawing one whose
// frame hasn't changed (plan/DEVICE.md §6). A step to the same place (the
// designs often hold a value over several steps) leaves the frame as it was.
struct SceneFrame {
  static constexpr int kMaxGroups = 288;  // groups in a scene; faces.h checks it
  uint16_t scene = 0xFFFF;
  uint8_t flags = 0;
  int16_t x[kMaxGroups] = {}, y[kMaxGroups] = {};  // 0 while the group doesn't show
  uint8_t on[kMaxGroups] = {};
  uint8_t fill[kMaxGroups] = {};
};
bool operator==(const SceneFrame& a, const SceneFrame& b);
inline bool operator!=(const SceneFrame& a, const SceneFrame& b) { return !(a == b); }

// The scene a mood, state and variation show: some are shared, such as
// asleep and no app, which look the same in every mood.
int sceneOf(Mood m, SceneState s, int variant = 0);
// How long that design takes to play once through, in ms (faces.h's
// loopMs): what a moment's loops count (plan/PROTOCOL.md §3).
uint32_t loopMs(Mood m, SceneState s, int variant = 0);
SceneFrame sceneFrame(const SceneShow& s);
// Draws the scene over what's on the canvas; the screen clears it first.
void drawScene(Canvas& c, const SceneShow& s);
// Where the tap's heart is centred, before the face moves.
constexpr int kHeartX = 268, kHeartY = 60;
// The palette entry for a design colour (faces::kColors), for the tests.
uint8_t sceneInk(int color);

}  // namespace render
