// Touch calibration (plan/DEVICE.md §4): an affine map from the XPT2046's
// raw readings to screen pixels. `boopctl calibrate` fits it from 4 taps and
// sends it with dbg.touchcal; the board keeps it in NVS. Pure C++.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace app {

struct TouchCal {
  // x = (ax·rx + bx·ry + cx) / 65536, and the same for y.
  int32_t ax = 0, bx = 0, cx = 0;
  int32_t ay = 0, by = 0, cy = 0;
  bool valid = false;

  void map(int rx, int ry, int& x, int& y) const {
    int64_t fx = int64_t(ax) * rx + int64_t(bx) * ry + cx;
    int64_t fy = int64_t(ay) * rx + int64_t(by) * ry + cy;
    x = clamp(int((fx + 32768) >> 16), render::kWidth - 1);
    y = clamp(int((fy + 32768) >> 16), render::kHeight - 1);
  }

 private:
  static int clamp(int v, int hi) { return v < 0 ? 0 : v > hi ? hi : v; }
};

}  // namespace app
