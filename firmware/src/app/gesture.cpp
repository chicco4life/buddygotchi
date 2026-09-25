#include "app/gesture.h"

namespace app {

ButtonGesture::Event ButtonGesture::update(bool down, uint32_t now) {
  if (down != down_) {
    if (changed_ && now - since_ < kDebounceMs) return kNone;  // bounce
    down_ = down;
    changed_ = true;
    since_ = now;
    if (down) return kDown;
    if (holding_) {
      holding_ = false;
      return kHoldEnd;
    }
    return kTap;
  }
  if (down_ && !holding_ && now - since_ >= kHoldMs) {
    holding_ = true;
    return kHoldStart;
  }
  return kNone;
}

}  // namespace app
