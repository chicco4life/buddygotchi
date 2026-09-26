#include "render/pattern.h"

namespace render {

void drawPattern(Canvas& c) {
  c.fill(kGrey);

  // The UP arrow, pointing at the top edge.
  const int ax = kWidth / 2;
  c.fillTriangle(ax, 14, ax - 56, 70, ax + 56, 70, kWhite);
  c.fillRect(ax - 22, 70, 44, 44, kWhite);
  c.drawText(ax - Canvas::textWidth("UP", 2) / 2, 85, "UP", kBlack, 2);

  for (const PatternBlock& b : kPatternBlocks) c.fillRect(b.x, b.y, b.w, b.h, b.color);

  // The USB-C side: a black bar down the right edge, and a label pointing at it.
  c.fillRect(kWidth - kPatternUsbW, kPatternUsbTop, kPatternUsbW, kPatternUsbBottom - kPatternUsbTop, kBlack);
  const int tipX = kWidth - kPatternUsbW - 4, ty = 42;
  c.fillTriangle(tipX, ty + 7, tipX - 8, ty, tipX - 8, ty + 14, kBlack);
  c.drawText(tipX - 12 - Canvas::textWidth("USB-C", 2), ty, "USB-C", kBlack, 2);

  // Labelled corners.
  c.drawText(3, 3, "TL", kBlack);
  c.drawText(kWidth - 3 - Canvas::textWidth("TR"), 3, "TR", kBlack);
  c.drawText(3, kHeight - 10, "BL", kBlack);
  c.drawText(kWidth - 3 - Canvas::textWidth("BR"), kHeight - 10, "BR", kBlack);
}

}  // namespace render
