#include "render/anim.h"

#include <cstring>

#include "render/scene.h"

namespace render {

namespace {

// The older names the Mac may still send, and the animation each reads as:
// "cheer" is the finish's success, and the Mac's "wiggle" (the
// dashboard's) what a tap plays.
const char* const kOlder[][2] = {{"cheer", "task_complete"}, {"wiggle", "poked"}};
const char* const kMoods[] = {"happy", "excited", "proud",     "curious", "determined", "grumpy", "sad",
                              "calm",  "engaged", "annoyed", "irritated", "whiny",      "wounded"};
static_assert(sizeof(kMoods) / sizeof(kMoods[0]) == size_t(Mood::kCount), "one name per mood");

}  // namespace

Anim animFromName(const char* name) {
  if (!name) return Anim::kNone;
  for (const auto& older : kOlder) {
    if (!std::strcmp(name, older[0])) name = older[1];
  }
  for (int i = 1; i < int(Anim::kCount); ++i) {
    if (!std::strcmp(name, animName(Anim(i)))) return Anim(i);
  }
  return Anim::kNone;
}

const char* animName(Anim a) {
  return a != Anim::kNone && int(a) < int(Anim::kCount) ? stateName(animState(a)) : "none";
}

Mood moodFromName(const char* name) {
  Mood m = Mood::kHappy;
  parseMood(name, m);
  return m;
}

bool parseMood(const char* name, Mood& out) {
  if (!name) return false;
  for (int i = 0; i < int(Mood::kCount); ++i) {
    if (!std::strcmp(name, kMoods[i])) return out = Mood(i), true;
  }
  return false;
}

const char* moodName(Mood m) { return kMoods[int(m) < int(Mood::kCount) ? int(m) : 0]; }

}  // namespace render
