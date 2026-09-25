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
  uint8_t get(int x, int y) const;

 private:
  uint8_t* px_;
};

}  // namespace render
