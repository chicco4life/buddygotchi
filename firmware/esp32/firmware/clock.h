#pragma once
#include <Arduino.h>
// Presentation clock. Only animation, model deadlines and the state reply
// read it; transport, watchdog and physical press timing stay on millis().
//
// It is a virtual clock: freezing stops it, clearing resumes it from where
// it stopped (a skew absorbs the frozen span), and `clock <ms>` jumps it to
// an absolute virtual time so HIL can time-travel past a deadline. Because
// the epoch never changes, recorded deadlines stay valid across all three.
static bool clockFrozen = false;
static uint32_t frozenMs = 0, clockSkew = 0;
inline uint32_t nowMs() { return clockFrozen ? frozenMs : millis() - clockSkew; }
inline void clockFreezeAt(uint32_t ms) { frozenMs = ms; clockFrozen = true; }
inline void clockFreeze() { clockFreezeAt(nowMs()); }
inline void clockClear() { if (clockFrozen) { clockSkew = millis() - frozenMs; clockFrozen = false; } }
inline bool before(uint32_t now, uint32_t deadline) {
  return deadline != 0 && (int32_t)(deadline - now) > 0;
}
