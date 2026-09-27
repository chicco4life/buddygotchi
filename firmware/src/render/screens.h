// The screen (plan/UX.md §2–3): the face, drawn as its mood design, with
// the bubble when there's a mumble and the status strip at the bottom. The
// same drawing serves the face, needs-you and no-app screens; only what it
// shows differs. Pure drawing: the device core decides what to show and
// passes it in.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/scene.h"

namespace render {

// Screen bands on the 320×240 screen, in pixels (UX.md §2). The face's
// design has everything above the strip; its props (the keyboard, the
// sign, the card) sit in the band the bubble takes when it shows.
constexpr int kStripTop = 204;   // the status strip, the bottom 36 px
constexpr int kBubbleTop = 144;  // the bubble, the 60 px above the strip

struct Strip {
  // While something needs you (amber; null when nothing does): who, the
  // oldest waiting session, and how many more are waiting (UX.md §3).
  const char* agent = nullptr;
  const char* project = "";
  int more = 0;
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

// The face as its design shows it, the bubble when there's a mumble (the
// face's show hides its prop to make room), and the strip.
void drawFaceScreen(Canvas& c, const SceneShow& face, const Mumble* mumble, const Strip& s);
void drawStrip(Canvas& c, const Strip& s);

}  // namespace render
