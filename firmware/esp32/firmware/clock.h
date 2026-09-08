#pragma once
#include <Arduino.h>
// Only presentation/model deadlines use this clock. Transport, watchdog and
// physical press durations stay on the monotonic hardware clock.
static bool clockFrozen = false;
static uint32_t frozenMs = 0;
inline uint32_t nowMs() { return clockFrozen ? frozenMs : millis(); }
inline bool before(uint32_t now, uint32_t deadline) {
  return deadline != 0 && (int32_t)(deadline - now) > 0;
}
