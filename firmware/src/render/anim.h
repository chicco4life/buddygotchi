// The animation set (documentation/BEHAVIORS.md §5) by name, and Boop's mood. Each
// animation plays a design of its own in a mood (render/scene.h animState),
// which render/scene.h draws.
#pragma once
#include <cstdint>

namespace render {

enum class Anim : uint8_t {
  kNone,
  kTaskComplete,  // the brain's finish: a turn done or failed
  kReplyReady,    // the brain's finish: an answer, or a question back
  kStarting,      // the rules' one-shots (documentation/PROTOCOL.md §3)
  kStopped,
  kError,
  kHelperReturn,
  kPoked,      // a tap
  kTapSpam,    // the third tap in a row and on
  kListening,  // push-to-talk: the listening design, until the reply
  kCount,
};

// By its design's state's name, as Boop's do names it: kNone if unknown.
Anim animFromName(const char* name);
const char* animName(Anim a);  // its design's state's name, such as "task_complete"; "none" for kNone

// Boop's mood, which picks the set of designs every look and animation is
// drawn in (documentation/PROTOCOL.md §3, documentation/harness/DECISIONS.md §2.3), in
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
