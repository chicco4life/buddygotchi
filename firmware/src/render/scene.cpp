#include "render/scene.h"

#include <cstring>

#include "faces.h"
#include "render/palette.h"

namespace render {

namespace {

using namespace faces;

static_assert(kMaxGroups <= SceneFrame::kMaxGroups, "a scene's groups fit its frame");
static_assert(int(Mood::kCount) == 7 && int(SceneState::kCount) == 6, "faces.h's moods and states");

const char* const kStates[] = {"idle", "working", "needs_you", "task_complete", "asleep", "no_app"};
static_assert(sizeof(kStates) / sizeof(kStates[0]) == size_t(SceneState::kCount), "one name per state");

// The small "o" the mouth becomes on a syllable, from the curious design
// asking for you (curious--needs_you.svg), where it's the mouth.
struct Box {
  int16_t x, y, w, h;
};
constexpr Box kTalk[] = {{153, 128, 14, 4}, {153, 132, 4, 4}, {163, 132, 4, 4}, {153, 136, 14, 4}};

const Scene& scene(const SceneShow& s) { return kScenes[sceneOf(s.mood, s.state)]; }

// The tap's heart, in 3 px blocks, a stronger coral than the cheeks: it pops
// in small, then full size.
constexpr int kHeartBlock = 3;
const char* const kHeartSmall[] = {"XX.XX", "XXXXX", ".XXX.", "..X.."};
const char* const kHeartFull[] = {".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."};

template <int N>
void drawHeart(Canvas& c, const char* const (&rows)[N], int cx, int cy) {
  const uint8_t rose = inkAt(kInkRose, kLevels);
  int w = int(std::strlen(rows[0]));
  int x0 = cx - w * kHeartBlock / 2, y0 = cy - N * kHeartBlock / 2;
  for (int r = 0; r < N; ++r) {
    for (int i = 0; i < w; ++i) {
      if (rows[r][i] == 'X') c.fillRect(x0 + i * kHeartBlock, y0 + r * kHeartBlock, kHeartBlock, kHeartBlock, rose);
    }
  }
}

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
  int mouth = -1, face = -1;
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
      case kRoleFace:
        x += s.dx, y += s.dy;
        p.face = i;
        break;
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

const char* stateName(SceneState s) { return kStates[int(s) < int(SceneState::kCount) ? int(s) : 0]; }

SceneState stateFromName(const char* name) {
  if (!name) return SceneState::kIdle;
  for (int i = 0; i < int(SceneState::kCount); ++i) {
    if (!std::strcmp(name, kStates[i])) return SceneState(i);
  }
  return SceneState::kIdle;
}

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
  f.flags = uint8_t(s.mouthOpen | (s.heart > 2 ? 2 : s.heart) << 1);
  const Scene& sc = kScenes[f.scene];
  Placed p;
  place(sc, s, p);
  for (int i = 0; i < sc.groups; ++i) {
    // The talking "o" sits where the hidden mouth would.
    if (!p.on[i] && i != p.mouth && i != p.face) continue;
    f.x[i] = p.x[i], f.y[i] = p.y[i], f.on[i] = p.on[i];
  }
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
  if (s.mouthOpen && p.mouth >= 0 && p.on[kGroups[sc.group0 + p.mouth].parent]) {
    for (const Box& b : kTalk) c.fillRect(b.x + p.x[p.mouth], b.y + p.y[p.mouth], b.w, b.h, sceneInk(faces::kInk));
  }
  if (s.heart && p.face >= 0) {
    int cx = kHeartX + p.x[p.face], cy = kHeartY + p.y[p.face];
    if (s.heart >= 2) drawHeart(c, kHeartFull, cx, cy);
    else drawHeart(c, kHeartSmall, cx, cy);
  }
}

}  // namespace render
