// The bring-up test pattern (plan/PLAN.md F1, plan/DEVICE.md §7): six
// colour blocks, labelled corners and a big UP arrow on a grey background.
// boopctl's webcam check samples the blocks at the rectangles below.
#pragma once
#include "render/canvas.h"
#include "render/palette.h"

namespace render {

struct PatternBlock {
  int x, y, w, h;
  Color color;
  const char* name;
};

constexpr PatternBlock kPatternBlocks[6] = {
    {8, 122, 108, 56, kRed, "red"},     {124, 122, 108, 56, kGreen, "green"},
    {8, 182, 108, 56, kBlue, "blue"},   {124, 182, 108, 56, kWhite, "white"},
    {8, 242, 108, 56, kBlack, "black"}, {124, 242, 108, 56, kAmber, "amber"},
};

void drawPattern(Canvas& c);

}  // namespace render
