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
constexpr uint8_t kRotation = 0;

bool displayBegin();
// Pushes the rows that changed since the last push, 16 rows per DMA batch.
// Returns the number of rows sent.
int displayPush(const render::Canvas& canvas);
void displayBacklight(uint8_t level);

// Touch in screen coordinates, using the default raw range until
// calibration exists. False when nothing's pressed.
bool touchRead(int& x, int& y);
void touchRaw(int& x, int& y, int& z, bool& irq);

}  // namespace board
