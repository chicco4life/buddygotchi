// The screen: the face, drawn as its mood design, and in the bottom lane
// the status strip, or the bubble while there's a mumble. The same drawing
// serves the face, needs-you and no-app screens; only what it shows differs.
// Pure drawing: the device core decides what to show and passes it in.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/scene.h"

namespace render {

// Screen bands on the 320×240 screen, in pixels. The animation bank's
// designs leave the bottom 48 px, the lane, for text: the strip sits in it,
// and the bubble takes the whole lane while a line plays, in the strip's
// place. The first pack's looks and its successes for the finish draw into
// the lane too; the bubble blanks it.
constexpr int kLaneTop = 192;   // the bottom lane: the bubble's
constexpr int kStripTop = 204;  // the status strip, the bottom 36 px

struct Strip {
  // While something needs you (amber; null when nothing does): who, the
  // oldest waiting session, and how many more are waiting. Its thread's
  // name shows in the project's place when there is one.
  const char* agent = nullptr;
  const char* project = "";
  const char* name = "";
  int more = 0;
  // While the brain's finish plays, whose turn it was (null for none),
  // after a tick for a success, a cross for a failure, or dots for a
  // reply. Needs you's names win: the finish doesn't play then.
  const char* doneAgent = nullptr;
  const char* doneThread = "";
  Outcome doneOutcome = Outcome::kNone;
  int busy = 0;  // sessions working (grey; hidden at zero)
  bool noApp = false;
};

// A mumble in the bubble: squiggles for the gibberish, and the one real
// word in amber at its place among the syllables.
struct Mumble {
  int syllables = 0;
  int at = -1;          // index of the word among the syllables; -1 for none
  const char* word = nullptr;
};

// The face as its design shows it, and the bubble when there's a mumble,
// else the strip. The face is a frame sceneFrame made, or a show for the
// tests, as drawScene takes it.
void drawFaceScreen(Canvas& c, const SceneFrame& face, const Mumble* mumble, const Strip& s);
inline void drawFaceScreen(Canvas& c, const SceneShow& face, const Mumble* mumble, const Strip& s) {
  drawFaceScreen(c, sceneFrame(face), mumble, s);
}
void drawStrip(Canvas& c, const Strip& s);

}  // namespace render
