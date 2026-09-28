// The bring-up test pattern (the v1 build plan's F1, plan/DEVICE.md §7): six
// colour blocks, labelled corners, a big UP arrow and a black USB-C bar down
// the right edge, on a grey background. Seen upright, the arrow is at the
// top and the bar is on the side where the USB-C port is.
// boopctl's webcam check samples the rectangles below (internal/tools/boopctl_lib/cam.py).
#pragma once
#include "render/canvas.h"
#include "render/palette.h"

namespace render {

struct PatternBlock {
  int x, y, w, h;
  Color color;
  const char* name;
};

// Three across and two down, under the arrow and clear of the USB-C bar.
constexpr PatternBlock kPatternBlocks[6] = {
    {8, 122, 92, 50, kRed, "red"},     {108, 122, 92, 50, kGreen, "green"},  {208, 122, 92, 50, kBlue, "blue"},
    {8, 176, 92, 50, kWhite, "white"}, {108, 176, 92, 50, kBlack, "black"}, {208, 176, 92, 50, kAmber, "amber"},
};

// The USB-C bar: the right edge, between the corner labels.
constexpr int kPatternUsbW = 12, kPatternUsbTop = 14, kPatternUsbBottom = kHeight - 14;

void drawPattern(Canvas& c);

}  // namespace render
