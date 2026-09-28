// Turns a button's raw up/down level into presses and taps:
// any press is a tap, sent on release. Debounced; pure C++, driven by the
// device clock.
#pragma once
#include <cstdint>

namespace app {

class ButtonGesture {
 public:
  enum Event : uint8_t { kNone, kDown, kTap };

  static constexpr uint32_t kDebounceMs = 15;

  // Call often with the current level. Returns at most one event per call.
  // kDown comes on the press itself, so the screen can react at once;
  // kTap on the release, however long the press.
  Event update(bool down, uint32_t now);

  bool down() const { return down_; }

 private:
  bool down_ = false;
  bool changed_ = false;  // at least one edge seen, so debounce applies
  uint32_t since_ = 0;
};

}  // namespace app
