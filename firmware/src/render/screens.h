// Whole-screen drawings (plan/UX.md §2–3): the face with its bubble (also
// the no-app screen) and needs you, each with the status strip at the bottom.
// Pure drawing: the device core decides what to show and passes it in.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/face.h"

namespace render {

// Screen bands on the 320×240 screen, in pixels (UX.md §2). The face has
// everything above the strip; when the bubble shows, the face moves up into
// the space above it.
constexpr int kStripTop = 204;   // the status strip, the bottom 36 px
constexpr int kBubbleTop = 144;  // the bubble, the 60 px above the strip

struct Strip {
  int wait = 0;  // sessions that need you (amber; hidden at zero)
  int busy = 0;  // sessions working (grey)
  bool noApp = false;
};

// A mumble in the bubble: squiggles for the gibberish, and the one real
// word in amber at its place among the syllables.
struct Mumble {
  int syllables = 0;
  int at = -1;          // index of the word among the syllables; -1 for none
  const char* word = nullptr;
};

struct Attention {
  const char* agent = "";
  const char* project = "";
  int more = 0;
};

// The face as both screens place it: its layout depends on the pose alone.
FaceLayout faceLayout(const Pose& p);

// The face screen, with the bubble when there's a mumble. The face's place
// comes from the pose (Pose::raise), so moving up for the bubble is eased.
// Both screens take the face as faceLayout lays it out, or its pose.
void drawFaceScreen(Canvas& c, const FaceLayout& f, const Mumble* mumble, const Strip& s);
void drawNeedsYou(Canvas& c, const FaceLayout& f, const Attention& a, const Strip& s);
inline void drawFaceScreen(Canvas& c, const Pose& p, const Mumble* mumble, const Strip& s) {
  drawFaceScreen(c, faceLayout(p), mumble, s);
}
inline void drawNeedsYou(Canvas& c, const Pose& p, const Attention& a, const Strip& s) {
  drawNeedsYou(c, faceLayout(p), a, s);
}
void drawStrip(Canvas& c, const Strip& s);

}  // namespace render
