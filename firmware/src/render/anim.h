// The animation set and the looks (plan/BEHAVIORS.md §2, §5) by name, and
// Boop's mood. What each one looks like in each mood is its mood design,
// which render/scene.h draws.
#pragma once
#include <cstdint>

namespace render {

enum class Anim : uint8_t {
  kNone,
  kCheer,
  kWiggle,
  kCount,
};

Anim animFromName(const char* name);  // kNone if unknown
const char* animName(Anim a);
// How long a moment plays, in ms.
uint32_t animDuration(Anim a);

// Boop's mood, which picks the set of designs every look and animation is
// drawn in (plan/PROTOCOL.md §3, plan/harness/DECISIONS.md §2.3).
enum class Mood : uint8_t { kHappy, kExcited, kProud, kCurious, kDetermined, kGrumpy, kSad, kCount };
Mood moodFromName(const char* name);  // kHappy if missing or unknown
const char* moodName(Mood m);

// What the face shows when no moment plays.
enum class Look : uint8_t { kIdle, kWorking, kAsleep, kNeedsYou, kNoApp };
const char* lookName(Look look);

// A switch from one design to another shuts the eyes this long, which hides
// the cut (plan/UX.md §2), and the backlight eases over the same time.
constexpr uint32_t kBlendMs = 150;

}  // namespace render
