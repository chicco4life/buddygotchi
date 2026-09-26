// When to drop a Bluetooth link the Mac has gone quiet on (plan/PROTOCOL.md
// §2, "Reconnecting"). The Mac sends a `state` at least every 10 s, so a link
// that's been silent for Behaviour::kNoAppMs is left over from an app that
// was killed. While it's up the device doesn't advertise, and a restarted
// app couldn't find it. Pure C++.
#pragma once
#include <cstdint>

#include "app/behaviour.h"

namespace app {

class LinkSilence {
 public:
  static constexpr uint32_t kDropMs = Behaviour::kNoAppMs;

  // The link came up, or bytes arrived on it.
  void heard(uint32_t t) { at_ = t; }
  // True once kDropMs have passed since the last heard(); it then waits
  // another kDropMs, in case dropping the link didn't take.
  bool drop(uint32_t t) {
    if (t - at_ < kDropMs) return false;
    at_ = t;
    return true;
  }

 private:
  uint32_t at_ = 0;
};

}  // namespace app
