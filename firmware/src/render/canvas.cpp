#include "render/canvas.h"

#include <cstring>

namespace render {

void Canvas::fill(uint8_t color) { std::memset(px_, color, size_t(kWidth) * kHeight); }

void Canvas::fillRect(int x, int y, int w, int h, uint8_t color) {
  int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
  int x1 = x + w > kWidth ? kWidth : x + w, y1 = y + h > kHeight ? kHeight : y + h;
  for (int row = y0; row < y1; ++row) {
    if (x1 > x0) std::memset(px_ + row * kWidth + x0, color, size_t(x1 - x0));
  }
}

uint8_t Canvas::get(int x, int y) const {
  if (x < 0 || y < 0 || x >= kWidth || y >= kHeight) return 0;
  return px_[y * kWidth + x];
}

}  // namespace render
