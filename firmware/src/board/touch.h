// The XPT2046 touch controller (plan/DEVICE.md §2), read by bit-banged SPI
// on its own pins, so the second hardware SPI bus is free for the microSD
// card (board/card.h).
#pragma once

namespace board {

void touchBegin();
// The XPT2046's raw reading (no mapping) and the interrupt line; z is 0
// with no press. BoardHal maps it to screen pixels (app/touch_cal.h).
void touchRaw(int& x, int& y, int& z, bool& irq);

}  // namespace board
