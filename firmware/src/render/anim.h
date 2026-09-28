// The animation set (plan/BEHAVIORS.md §5) by name, and Boop's mood. What
// each look and animation looks like in each mood is its mood design, which
// render/scene.h draws.
#pragma once
#include <cstdint>

namespace render {

enum class Anim : uint8_t {
  kNone,
  kCheer,
  kWiggle,
  kListening,  // push-to-talk: the listening design, until the reply
  kCount,
};

Anim animFromName(const char* name);  // kNone if unknown
const char* animName(Anim a);
// A tap's wiggle is always this long. The cheer lasts its loops of its
// design (render/scene.h loopMs, plan/BEHAVIORS.md §5), and listening until
// the reply (app/behaviour.h).
constexpr uint32_t kWiggleMs = 700;

// Boop's mood, which picks the set of designs every look and animation is
// drawn in (plan/PROTOCOL.md §3, plan/harness/DECISIONS.md §2.3), in
// faces.h's order: the first seven keep the numbers they had before the rest
// came.
enum class Mood : uint8_t {
  kHappy, kExcited, kProud, kCurious, kDetermined, kGrumpy, kSad,
  kCalm, kEngaged, kAnnoyed, kIrritated, kWhiny, kWounded,
  kCount
};
Mood moodFromName(const char* name);  // kHappy if missing or unknown
bool parseMood(const char* name, Mood& out);  // false, and `out` untouched, if missing or unknown
const char* moodName(Mood m);

// A switch from one design to another shuts the eyes this long, which hides
// the cut, and the backlight eases over the same time.
constexpr uint32_t kBlendMs = 150;

}  // namespace render
