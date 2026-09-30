#include "render/anim.h"

#include <cstring>

#include "faces.h"
#include "render/scene.h"

namespace render {

Anim animFromName(const char* name) {
  if (!name) return Anim::kNone;
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
    if (!std::strcmp(name, faces::kMoodNames[i])) return out = Mood(i), true;
  }
  return false;
}

const char* moodName(Mood m) { return faces::kMoodNames[int(m) < int(Mood::kCount) ? int(m) : 0]; }

}  // namespace render
