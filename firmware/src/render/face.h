// The face (plan/UX.md §2): pixel art, after the owner's reference render.
// Two white window eyes, each four panes around a one-block cross, pink
// blush blocks under them and a flat bar mouth, all drawn from a Pose on
// one grid of square blocks. The eyes have no pupils: to look somewhere the
// whole eye moves, and the eye on that side grows a little, as if the head
// turned. Happy eyes are "^" arches; affection adds a pixel heart at the
// top right, effort a sweat drop, and sleep a rising "zzZZ". Every field
// blends linearly, so any two poses can be eased into each other.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace render {

// Fields are permille unless noted: 1000 is "fully" or "normal".
struct Pose {
  int16_t open = 1000;      // eye openness; 0 is a closed line
  int16_t lookX = 0;        // where the eyes look, -1000 left .. 1000 right (the
  int16_t lookY = 0;        // near eye grows), -1000 up .. 1000 down
  int16_t eyeSize = 1000;   // both eyes, without the mouth: > 1000 wide-eyed
  int16_t lidTop = 0;       // how far the upper lids come down
  int16_t lidTilt = 0;      // > 0 inner corners down (cross), < 0 outer down (sad)
  int16_t lidBot = 0;       // happy: the eyes squeeze to a line, then bend into "^" arches
  int16_t wink = 0;         // extra upper lid on one eye: > 0 right, < 0 left
  int16_t squash = 0;       // > 0 wide and short, < 0 tall and narrow
  int16_t mouthCurve = 0;   // -1000 frown .. 1000 smile
  int16_t mouthOpen = 0;    // 0 closed .. 1000 wide open
  int16_t mouthWide = 1000; // mouth width
  int16_t mouthX = 0;       // mouth sideways, in pixels (a smirk)
  int16_t dx = 0, dy = 0;   // whole face offset, in pixels
  int16_t size = 1000;      // whole face scale (a lean in is > 1000)
  int16_t glow = 0;         // eye tint towards the cheer glow
  int16_t raise = 0;        // 1000: moved up and smaller, to make room for the bubble
  int16_t heart = 0;        // a rose heart at the top right of the face, popping in with its size
  int16_t sweat = 0;        // > 0: a sweat drop by the right eye, slid down this far (permille)
  int16_t zzz = 0;          // > 0: asleep's "zzZZ", this far (permille) through its cycle
};

// At full size, the middle of the face (eye tops to mouth) lies this many
// pixels below the eye centres, because the mouth hangs below the eyes.
constexpr int kFaceDrop = 14;

// a + (b - a) × t / 1024, field by field.
Pose blend(const Pose& a, const Pose& b, int t);
bool operator==(const Pose& a, const Pose& b);
inline bool operator!=(const Pose& a, const Pose& b) { return !(a == b); }

// Draws the face centred on (cx, cy), at `scale` permille of full size.
void drawFace(Canvas& c, const Pose& p, int cx, int cy, int scale);

// The eye ink for a pose's tint (palette.h).
int eyeInk(const Pose& p);

}  // namespace render
