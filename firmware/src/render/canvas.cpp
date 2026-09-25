#include "render/canvas.h"

#include <cstring>

#include "render/font5x7.h"

namespace render {

void Canvas::fill(uint8_t color) { std::memset(px_, color, size_t(kWidth) * kHeight); }

void Canvas::fillRect(int x, int y, int w, int h, uint8_t color) {
  int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
  int x1 = x + w > kWidth ? kWidth : x + w, y1 = y + h > kHeight ? kHeight : y + h;
  for (int row = y0; row < y1; ++row) {
    if (x1 > x0) std::memset(px_ + row * kWidth + x0, color, size_t(x1 - x0));
  }
}

static int64_t edge(int ax, int ay, int bx, int by, int px, int py) {
  return int64_t(bx - ax) * (py - ay) - int64_t(by - ay) * (px - ax);
}

void Canvas::fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint8_t color) {
  if (edge(x0, y0, x1, y1, x2, y2) < 0) {  // make the winding consistent
    int tx = x1, ty = y1;
    x1 = x2, y1 = y2, x2 = tx, y2 = ty;
  }
  int minX = x0 < x1 ? (x0 < x2 ? x0 : x2) : (x1 < x2 ? x1 : x2);
  int maxX = x0 > x1 ? (x0 > x2 ? x0 : x2) : (x1 > x2 ? x1 : x2);
  int minY = y0 < y1 ? (y0 < y2 ? y0 : y2) : (y1 < y2 ? y1 : y2);
  int maxY = y0 > y1 ? (y0 > y2 ? y0 : y2) : (y1 > y2 ? y1 : y2);
  if (minX < 0) minX = 0;
  if (minY < 0) minY = 0;
  if (maxX >= kWidth) maxX = kWidth - 1;
  if (maxY >= kHeight) maxY = kHeight - 1;
  for (int y = minY; y <= maxY; ++y) {
    for (int x = minX; x <= maxX; ++x) {
      if (edge(x0, y0, x1, y1, x, y) >= 0 && edge(x1, y1, x2, y2, x, y) >= 0 &&
          edge(x2, y2, x0, y0, x, y) >= 0) {
        px_[y * kWidth + x] = color;
      }
    }
  }
}

int Canvas::drawText(int x, int y, const char* text, uint8_t color, int scale) {
  for (const char* p = text; *p; ++p) {
    unsigned char c = static_cast<unsigned char>(*p);
    if (c < 0x20 || c > 0x7E) c = '?';
    const uint8_t* glyph = kFont5x7[c - 0x20];
    for (int col = 0; col < 5; ++col) {
      for (int row = 0; row < 7; ++row) {
        if (glyph[col] & (1 << row)) fillRect(x + col * scale, y + row * scale, scale, scale, color);
      }
    }
    x += 6 * scale;
  }
  return x;
}

int Canvas::textWidth(const char* text, int scale) {
  int n = int(std::strlen(text));
  return n == 0 ? 0 : (6 * n - 1) * scale;
}

uint8_t Canvas::get(int x, int y) const {
  if (x < 0 || y < 0 || x >= kWidth || y >= kHeight) return 0;
  return px_[y * kWidth + x];
}

uint32_t Canvas::rowHash(int y) const {
  uint32_t h = 2166136261u;  // FNV-1a
  const uint8_t* row = px_ + y * kWidth;
  for (int x = 0; x < kWidth; ++x) h = (h ^ row[x]) * 16777619u;
  return h;
}

}  // namespace render
