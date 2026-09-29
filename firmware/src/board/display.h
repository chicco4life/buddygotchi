// The screen and touch panel through LovyanGFX (plan/DEVICE.md §4). This is
// the only code that knows the display library: it pushes the 8-bit canvas
// to the panel and reads raw touches.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace board {

// Panel settings, confirmed on the real panel at bring-up (DEVICE.md §4).
constexpr uint32_t kSpiWriteHz = 40000000;
constexpr bool kInvert = true;
constexpr bool kBgr = false;

// The panel as it's built: 240×320, portrait. LovyanGFX needs these, not
// the canvas size.
constexpr int kPanelWidth = 240, kPanelHeight = 320;

// Which way up Boop is. LovyanGFX rotation, in quarter turns of the picture
// clockwise; the panel controller does the turning, so it costs no CPU.
// Boop sits sideways with USB-C on the LEFT, seen from the front, and the
// test pattern's USB-C bar and the webcam check assume it. Rotation 0 is
// portrait with USB-C at the bottom (confirmed at bring-up), so 3 should be
// that landscape; 1, half a turn from it, put USB-C on the right until
// 2026-09-29. If the board shows the pattern upside down (the UP arrow at
// the bottom, the bar away from the port), 3 was the wrong way round: change
// this to 1. The default touch map follows it, and a touch calibration saved
// for another rotation is ignored, so run `boopctl calibrate` again after
// changing it. Don't use 4–7: mirrored.
constexpr uint8_t kRotation = 3;

static_assert((kRotation & 1 ? kPanelHeight : kPanelWidth) == render::kWidth &&
                  (kRotation & 1 ? kPanelWidth : kPanelHeight) == render::kHeight,
              "kRotation must turn the panel to the canvas's shape");

bool displayBegin();
// Pushes the rows that changed since the last push, a band of rows per DMA
// batch.
void displayPush(const render::Canvas& canvas);
void displayBacklight(uint8_t level);

// The XPT2046's raw reading (no mapping) and the interrupt line. BoardHal
// maps it to screen pixels (app/touch_cal.h).
void touchRaw(int& x, int& y, int& z, bool& irq);

}  // namespace board
