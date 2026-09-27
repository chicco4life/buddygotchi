#include "app/gesture.h"

namespace app {

ButtonGesture::Event ButtonGesture::update(bool down, uint32_t now) {
  if (down == down_) return kNone;
  if (changed_ && now - since_ < kDebounceMs) return kNone;  // bounce
  down_ = down;
  changed_ = true;
  since_ = now;
  return down ? kDown : kTap;
}

}  // namespace app
