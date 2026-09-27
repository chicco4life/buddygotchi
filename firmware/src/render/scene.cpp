#include "render/scene.h"

#include <cstring>

#include "faces.h"
#include "render/palette.h"

namespace render {

namespace {

using namespace faces;

static_assert(kMaxTracks <= SceneFrame::kMaxSteps, "a scene's steps fit its frame");
static_assert(int(Mood::kCount) == 7 && int(SceneState::kCount) == 6, "faces.h's moods and states");

// The small "o" the mouth becomes on a syllable, from the curious design
// asking for you (curious--needs_you.svg), where it's the mouth.
struct Box {
  int16_t x, y, w, h;
};
constexpr Box kTalk[] = {{153, 128, 14, 4}, {153, 132, 4, 4}, {163, 132, 4, 4}, {153, 136, 14, 4}};

const Scene& scene(const SceneShow& s) { return kScenes[sceneOf(s.mood, s.state)]; }

// The step a track is on t ms into its scene.
int step(const Track& tr, uint32_t t) {
  if (tr.once && t >= tr.dur) return tr.n - 1;
  uint32_t lt = t % tr.dur;
  int k = 0;
  while (k + 1 < tr.n && kKeys[tr.key0 + k + 1] <= lt) ++k;
  return k;
}

// Where each group sits and whether it shows, parents first.
struct Placed {
  int16_t x[kMaxGroups], y[kMaxGroups];
  bool on[kMaxGroups];
  int mouth = -1;
};

void place(const Scene& sc, const SceneShow& s, Placed& p) {
  for (int i = 0; i < sc.groups; ++i) {
    const Group& g = kGroups[sc.group0 + i];
    int x = g.tx, y = g.ty;
    bool on = g.visible;
    if (g.parent >= 0) x += p.x[g.parent], y += p.y[g.parent];
    if (g.move >= 0) {
      const Track& tr = kTracks[sc.track0 + g.move];
      int k = tr.key0 + step(tr, s.t);
      x += kValues[2 * k], y += kValues[2 * k + 1];
    }
    if (g.show >= 0) {
      const Track& tr = kTracks[sc.track0 + g.show];
      on = kValues[2 * (tr.key0 + step(tr, s.t))] != 0;
    }
    switch (g.role) {
      case kRoleFace: x += s.dx, y += s.dy; break;
      case kRoleEyesOpen: on = !s.eyesShut; break;
      case kRoleEyesClosed: on = s.eyesShut; break;
      case kRoleProp: on = on && !s.hideProp; break;
      case kRoleMouth:
        p.mouth = i;
        on = on && !s.mouthOpen;
        break;
      default: break;
    }
    p.x[i] = int16_t(x), p.y[i] = int16_t(y);
    p.on[i] = on && (g.parent < 0 || p.on[g.parent]);
  }
}

}  // namespace

int sceneOf(Mood m, SceneState s) {
  int mi = int(m) < int(Mood::kCount) ? int(m) : 0;
  int si = int(s) < int(SceneState::kCount) ? int(s) : 0;
  return kSceneOf[mi][si];
}

uint8_t sceneInk(int color) {
  switch (color) {
    case faces::kInk: return inkAt(kInkEye, kLevels);
    case faces::kCheek: return inkAt(kInkBlush, kLevels);
    case faces::kBlue: return inkAt(kInkSky, kLevels);
    case faces::kAmber: return inkAt(kInkSign, kLevels);
    case faces::kDim: return inkAt(kInkPropDim, kLevels);
    case faces::kPropGrey: return inkAt(kInkProp, kLevels);
    default: return kBlack;
  }
}

bool operator==(const SceneFrame& a, const SceneFrame& b) { return std::memcmp(&a, &b, sizeof a) == 0; }

SceneFrame sceneFrame(const SceneShow& s) {
  SceneFrame f;
  std::memset(&f, 0, sizeof f);  // padding too, since frames compare as bytes
  f.scene = uint8_t(sceneOf(s.mood, s.state));
  f.flags = uint8_t(s.eyesShut | s.hideProp << 1 | s.mouthOpen << 2);
  f.dx = s.dx, f.dy = s.dy;
  const Scene& sc = kScenes[f.scene];
  for (int i = 0; i < sc.tracks; ++i) f.steps[i] = uint8_t(step(kTracks[sc.track0 + i], s.t));
  return f;
}

void drawScene(Canvas& c, const SceneShow& s) {
  const Scene& sc = scene(s);
  Placed p;
  place(sc, s, p);
  for (int i = 0; i < sc.rects; ++i) {
    const Rect& r = kRects[sc.rect0 + i];
    if (p.on[r.group]) c.fillRect(r.x + p.x[r.group], r.y + p.y[r.group], r.w, r.h, sceneInk(r.color));
  }
  if (s.mouthOpen && p.mouth >= 0 && kGroups[sc.group0 + p.mouth].parent >= 0) {
    int m = p.mouth, parent = kGroups[sc.group0 + m].parent;
    if (!p.on[parent]) return;
    for (const Box& b : kTalk) c.fillRect(b.x + p.x[m], b.y + p.y[m], b.w, b.h, sceneInk(faces::kInk));
  }
}

}  // namespace render
