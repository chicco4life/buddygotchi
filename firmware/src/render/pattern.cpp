#include "render/pattern.h"

namespace render {

void drawPattern(Canvas& c) {
  c.fill(kGrey);

  // The UP arrow, pointing at the top edge.
  c.fillTriangle(120, 14, 64, 70, 176, 70, kWhite);
  c.fillRect(98, 70, 44, 44, kWhite);
  c.drawText(120 - Canvas::textWidth("UP", 2) / 2, 85, "UP", kBlack, 2);

  for (const PatternBlock& b : kPatternBlocks) c.fillRect(b.x, b.y, b.w, b.h, b.color);

  // Labelled corners.
  c.drawText(3, 3, "TL", kBlack);
  c.drawText(kWidth - 3 - Canvas::textWidth("TR"), 3, "TR", kBlack);
  c.drawText(3, kHeight - 10, "BL", kBlack);
  c.drawText(kWidth - 3 - Canvas::textWidth("BR"), kHeight - 10, "BR", kBlack);
  c.drawText(120 - Canvas::textWidth("USB-C this end") / 2, kHeight - 10, "USB-C this end", kBlack);
}

}  // namespace render
