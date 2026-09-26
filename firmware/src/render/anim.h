// The looks and the animation set (plan/BEHAVIORS.md §2, §5) as poses over
// time, plus the eased, interruptible blend between whatever is showing and
// whatever should show next. Everything is a function of the clock, so a
// frozen clock gives the same frame on the board and in the simulator.
#pragma once
#include <cstdint>

#include "render/face.h"

namespace render {

enum class Anim : uint8_t {
  kNone,
  kCheer,
  kWiggle,
  kListening,
  kCount,
};

Anim animFromName(const char* name);  // kNone if unknown
const char* animName(Anim a);
// How long a moment plays, in ms.
uint32_t animDuration(Anim a);
// The pose `t` ms into the animation.
Pose animPose(Anim a, uint32_t t);

// What the face shows when no moment plays.
enum class Look : uint8_t { kIdle, kWorking, kAsleep, kNeedsYou };
const char* lookName(Look look);
// `busy` is the working count.
Pose lookPose(Look look, int busy);

// The longest blend between two expressions (plan/UX.md §2).
constexpr uint32_t kBlendMs = 150;

// Eases from the pose showing when the source changed to the new source's
// pose over kBlendMs. A change during a blend starts from wherever the
// blend had got to, so nothing ever cuts hard.
class Blend {
 public:
  // The source changes at `at`; `showing` is what was on screen then.
  void start(uint32_t at, const Pose& showing) {
    from_ = showing;
    at_ = at;
    active_ = true;
  }
  // What to show at `now`, given the new source's pose at `now`.
  Pose apply(uint32_t now, const Pose& target) const;
  bool blending(uint32_t now) const { return active_ && int32_t(now - at_) < int32_t(kBlendMs); }

 private:
  Pose from_;
  uint32_t at_ = 0;
  bool active_ = false;
};

}  // namespace render
