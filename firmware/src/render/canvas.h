// The 8-bit indexed canvas every frame is drawn into (plan/DEVICE.md §6).
// Pure C++: it builds for the board and for the Mac simulator.
#pragma once
#include <cstdint>
#include <cstddef>

namespace render {

constexpr int kWidth = 240;
constexpr int kHeight = 320;

class Canvas {
 public:
  // Takes a buffer of kWidth * kHeight bytes that outlives the canvas.
  explicit Canvas(uint8_t* pixels) : px_(pixels) {}

  uint8_t* pixels() { return px_; }
  const uint8_t* pixels() const { return px_; }

  void fill(uint8_t color);
  void fillRect(int x, int y, int w, int h, uint8_t color);
  // Filled triangle; pixel centres inside or on an edge are drawn.
  void fillTriangle(int x0, int y0, int x1, int y1, int x2, int y2, uint8_t color);
  // 5x7 ASCII text, each font pixel drawn as a scale × scale block, with one
  // blank column between glyphs. Returns the x just past the last glyph.
  int drawText(int x, int y, const char* text, uint8_t color, int scale = 1);
  static int textWidth(const char* text, int scale = 1);
  uint8_t get(int x, int y) const;

  // A hash of one row, so the pusher can skip rows that didn't change.
  uint32_t rowHash(int y) const;

 private:
  uint8_t* px_;
};

}  // namespace render
