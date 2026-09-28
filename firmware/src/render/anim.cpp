#include "render/anim.h"

#include <cstring>

namespace render {

namespace {

const char* const kNames[] = {"none", "cheer", "wiggle", "listening"};
static_assert(sizeof(kNames) / sizeof(kNames[0]) == size_t(Anim::kCount), "one name per anim");
const char* const kMoods[] = {"happy", "excited", "proud", "curious", "determined", "grumpy", "sad"};
static_assert(sizeof(kMoods) / sizeof(kMoods[0]) == size_t(Mood::kCount), "one name per mood");

}  // namespace

Anim animFromName(const char* name) {
  if (!name) return Anim::kNone;
  for (int i = 1; i < int(Anim::kCount); ++i) {
    if (!std::strcmp(name, kNames[i])) return Anim(i);
  }
  return Anim::kNone;
}

const char* animName(Anim a) { return kNames[int(a) < int(Anim::kCount) ? int(a) : 0]; }

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
