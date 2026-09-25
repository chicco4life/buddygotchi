// The face (plan/UX.md §2): two big rounded eyes with pupils and lids, and
// a small mouth, drawn procedurally from a Pose. Every field blends
// linearly, so any two poses can be eased into each other.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace render {

// Fields are permille unless noted: 1000 is "fully" or "normal".
struct Pose {
  int16_t open = 1000;      // eye openness; 0 is a closed line
  int16_t lookX = 0;        // pupil position, -1000 left .. 1000 right
  int16_t lookY = 0;        // -1000 up .. 1000 down
  int16_t pupil = 1000;     // pupil size
  int16_t lidTop = 0;       // how far the upper lids come down
  int16_t lidTilt = 0;      // > 0 inner corners down (cross), < 0 outer down (sad)
  int16_t lidBot = 0;       // happy squint: the lower lids push up in an arc
  int16_t wink = 0;         // extra upper lid on one eye: > 0 right, < 0 left
  int16_t squash = 0;       // > 0 wide and short, < 0 tall and narrow
  int16_t mouthCurve = 0;   // -1000 frown .. 1000 smile
  int16_t mouthOpen = 0;    // 0 closed .. 1000 wide open
  int16_t mouthWide = 1000; // mouth width
  int16_t mouthX = 0;       // mouth sideways, in pixels (a smirk)
  int16_t dx = 0, dy = 0;   // whole face offset, in pixels
  int16_t size = 1000;      // whole face scale (a lean in is > 1000)
  int16_t glow = 0;         // eye tint towards the cheer glow
  int16_t oops = 0;         // eye tint towards the oops red
  int16_t raise = 0;        // 1000: moved up and smaller, to make room for the bubble
};

// a + (b - a) × t / 1024, field by field.
Pose blend(const Pose& a, const Pose& b, int t);
bool operator==(const Pose& a, const Pose& b);
inline bool operator!=(const Pose& a, const Pose& b) { return !(a == b); }

// Draws the face centred on (cx, cy), at `scale` permille of full size.
void drawFace(Canvas& c, const Pose& p, int cx, int cy, int scale);

// The eye ink for a pose's tint (palette.h).
int eyeInk(const Pose& p);

}  // namespace render
