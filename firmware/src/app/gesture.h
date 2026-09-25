// Turns a button's raw up/down level into taps and holds (plan/UX.md §4):
// shorter than 400 ms is a tap; 400 ms or more is push-to-talk until
// release. Pure C++, driven by the device clock.
#pragma once
#include <cstdint>

namespace app {

class ButtonGesture {
 public:
  enum Event : uint8_t { kNone, kDown, kTap, kHoldStart, kHoldEnd };

  static constexpr uint32_t kHoldMs = 400;
  static constexpr uint32_t kDebounceMs = 15;

  // Call often with the current level. Returns at most one event per call.
  // kDown comes on the press itself, so the screen can react at once.
  Event update(bool down, uint32_t now);

  bool down() const { return down_; }
  bool holding() const { return holding_; }

 private:
  bool down_ = false;
  bool holding_ = false;
  bool changed_ = false;  // at least one edge seen, so debounce applies
  uint32_t since_ = 0;
};

}  // namespace app
