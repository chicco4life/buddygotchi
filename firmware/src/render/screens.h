// Whole-screen drawings (plan/UX.md §2–3): the face with its bubble, needs
// you, threads, stats and no app, each with the status strip at the bottom.
// Pure drawing: the device core decides what to show and passes it in.
#pragma once
#include <cstdint>

#include "render/canvas.h"
#include "render/face.h"

namespace render {

// Screen bands, in pixels (UX.md §2).
constexpr int kStripTop = 280;   // the status strip, 40 px
constexpr int kBubbleTop = 200;  // the bubble, when it shows, 80 px

struct Strip {
  int wait = 0;  // sessions that need you (amber; hidden at zero)
  int busy = 0;  // sessions working (grey)
  bool noApp = false, quiet = false, focus = false, lowBattery = false;
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

struct Thread {
  char agent[12];
  char project[24];
  char status;  // 'w' needs you, 'b' working, 'i' idle
};

struct Stats {
  const char* name = "";
  int level = 1, prog = 0, days = 0;
};

// The face screen, with the bubble when there's a mumble. The face's place
// comes from the pose (Pose::raise), so moving up for the bubble is eased.
void drawFaceScreen(Canvas& c, const Pose& p, const Mumble* mumble, const Strip& s);
void drawNeedsYou(Canvas& c, const Pose& p, const Attention& a, const Strip& s);
void drawThreads(Canvas& c, const Thread* threads, int n, const Strip& s);
void drawStats(Canvas& c, const Stats& st, const Strip& s);
void drawStrip(Canvas& c, const Strip& s);

}  // namespace render
