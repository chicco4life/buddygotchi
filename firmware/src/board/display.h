// The screen (documentation/DEVICE.md §4): each board's display.cpp is the only
// code that knows the display library, and pushes the 8-bit canvas to its
// panel. Touch is board/touch.h; the panel settings are in board/config.h.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace board {

bool displayBegin();
// Pushes what changed since the last push: of each band of rows, the
// columns that changed, in DMA batches (render::Changes).
void displayPush(const render::Canvas& canvas);
void displayBacklight(uint8_t level);
// The screen couldn't start: light what can be lit, so a person sees the
// board is on (main.cpp's fatal loop).
void displayFailed();

}  // namespace board
