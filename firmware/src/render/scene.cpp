#include "render/scene.h"

#include <cstring>

#include "faces.h"
#include "render/palette.h"

namespace render {

namespace {

using namespace faces;

static_assert(kMaxGroups <= SceneFrame::kMaxGroups, "a scene's groups fit its frame");
static_assert(int(Mood::kCount) == 7 && int(SceneState::kCount) == 7, "faces.h's moods and states");

const char* const kStates[] = {"idle", "working", "needs_you", "task_complete", "asleep", "no_app", "listening"};
static_assert(sizeof(kStates) / sizeof(kStates[0]) == size_t(SceneState::kCount), "one name per state");
constexpr uint16_t kNone = 0xFFFF;

// The small "o" the mouth becomes on a syllable, from the old curious
// design asking for you, where it was the mouth.
struct Box {
  int16_t x, y, w, h;
};
constexpr Box kTalk[] = {{153, 128, 14, 4}, {153, 132, 4, 4}, {163, 132, 4, 4}, {153, 136, 14, 4}};

const Scene& scene(const SceneShow& s) { return kScenes[sceneOf(s.mood, s.state, s.variant)]; }

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
  uint32_t lt = t % tr.dur;
  int k = 0;
  while (k + 1 < tr.n && kKeys[tr.key0 + k + 1] <= lt) ++k;
  return k;
}

// Where each group sits, whether it shows and the colour it fills with,
// parents first.
struct Placed {
  int16_t x[kMaxGroups], y[kMaxGroups];
  bool on[kMaxGroups];
  uint8_t fill[kMaxGroups];
  int mouth = -1, face = -1;
};

void place(const Scene& sc, const SceneShow& s, Placed& p) {
  for (int i = 0; i < sc.groups; ++i) {
    const Group& g = kGroups[sc.group0 + i];
    int x = g.tx, y = g.ty;
    bool on = g.visible;
    uint8_t fill = 0;
    if (g.parent != kNone) x += p.x[g.parent], y += p.y[g.parent], fill = p.fill[g.parent];
    if (g.move != kNone) {
      const Track& tr = kTracks[sc.track0 + g.move];
      uint32_t v = tr.val0 + 2 * uint32_t(step(tr, s.t));
      x += kValues[v], y += kValues[v + 1];
    }
    if (g.show != kNone) {
      const Track& tr = kTracks[sc.track0 + g.show];
      on = kValues[tr.val0 + step(tr, s.t)] != 0;
    }
    if (g.fill != kNone) {
      const Track& tr = kTracks[sc.track0 + g.fill];
      fill = uint8_t(kValues[tr.val0 + step(tr, s.t)]);
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
        if (p.mouth < 0) p.mouth = i;
        on = on && !s.mouthOpen;
        break;
      default: break;
    }
    p.x[i] = int16_t(x), p.y[i] = int16_t(y), p.fill[i] = fill;
    p.on[i] = on && (g.parent == kNone || p.on[g.parent]);
  }
}

// A scene colour as the canvas holds it, and back: the canvas's colours
// that aren't the scene's (text, the strip) read as black.
uint8_t toCanvas(int color) { return color == 0 ? kBlack : uint8_t(kSceneBase + color - 1); }
int fromCanvas(uint8_t px) { return px >= kSceneBase && px < kSceneBase + kColorCount - 1 ? px - kSceneBase + 1 : 0; }

// A translucent rectangle: each pixel it covers, within the clip, becomes
// the blend of its colour over what's there.
void blendRect(Canvas& c, int x, int y, int w, int h, int pair, const Scene& sc) {
  int x0 = x < sc.clipX ? sc.clipX : x, y0 = y < sc.clipY ? sc.clipY : y;
  int x1 = x + w, y1 = y + h;
  if (x1 > sc.clipX + sc.clipW) x1 = sc.clipX + sc.clipW;
  if (y1 > sc.clipY + sc.clipH) y1 = sc.clipY + sc.clipH;
  if (x0 < 0) x0 = 0;
  if (y0 < 0) y0 = 0;
  if (x1 > kWidth) x1 = kWidth;
  if (y1 > kHeight) y1 = kHeight;
  uint8_t* px = c.pixels();
  for (int yy = y0; yy < y1; ++yy) {
    for (int xx = x0; xx < x1; ++xx) {
      uint8_t& d = px[yy * kWidth + xx];
      d = toCanvas(kBlendOver[pair][fromCanvas(d)]);
    }
  }
}

// A rectangle cut to the scene's clip.
void clipRect(Canvas& c, int x, int y, int w, int h, uint8_t ink, const Scene& sc) {
  int x0 = x < sc.clipX ? sc.clipX : x, y0 = y < sc.clipY ? sc.clipY : y;
  int x1 = x + w, y1 = y + h;
  if (x1 > sc.clipX + sc.clipW) x1 = sc.clipX + sc.clipW;
  if (y1 > sc.clipY + sc.clipH) y1 = sc.clipY + sc.clipH;
  if (x1 > x0 && y1 > y0) c.fillRect(x0, y0, x1 - x0, y1 - y0, ink);
}

int clampVariant(SceneState s, int v) {
  int n = variants(s);
  return v >= 0 && v < n ? v : 0;
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

int variants(SceneState s) { return kVariants[int(s) < int(SceneState::kCount) ? int(s) : 0]; }

int sceneOf(Mood m, SceneState s, int variant) {
  int mi = int(m) < int(Mood::kCount) ? int(m) : 0;
  int si = int(s) < int(SceneState::kCount) ? int(s) : 0;
  return kSceneOf[mi][si][clampVariant(SceneState(si), variant)];
}

uint32_t loopMs(Mood m, SceneState s, int variant) { return kScenes[sceneOf(m, s, variant)].loopMs; }

uint8_t sceneInk(int color) { return color > 0 && color < kColorCount ? toCanvas(color) : kBlack; }

bool operator==(const SceneFrame& a, const SceneFrame& b) { return std::memcmp(&a, &b, sizeof a) == 0; }

SceneFrame sceneFrame(const SceneShow& s) {
  SceneFrame f;
  std::memset(&f, 0, sizeof f);  // padding too, since frames compare as bytes
  f.scene = uint16_t(sceneOf(s.mood, s.state, s.variant));
  f.flags = uint8_t(s.mouthOpen | (s.heart > 2 ? 2 : s.heart) << 1);
  const Scene& sc = kScenes[f.scene];
  Placed p;
  place(sc, s, p);
  for (int i = 0; i < sc.groups; ++i) {
    // The talking "o" sits where the hidden mouth would.
    if (!p.on[i] && i != p.mouth && i != p.face) continue;
    f.x[i] = p.x[i], f.y[i] = p.y[i], f.on[i] = p.on[i], f.fill[i] = p.fill[i];
  }
  return f;
}

void drawScene(Canvas& c, const SceneShow& s) {
  const Scene& sc = scene(s);
  Placed p;
  place(sc, s, p);
  for (int i = 0; i < sc.groups; ++i) {
    if (!p.on[i]) continue;
    const Group& g = kGroups[sc.group0 + i];
    for (int k = 0; k < g.rects; ++k) {
      const Rect& r = kRects[g.rect0 + k];
      int color = r.color == kInherit ? p.fill[i] : r.color;
      if (color >= kBlend) {
        blendRect(c, r.x + p.x[i], r.y + p.y[i], r.w, r.h, color - kBlend, sc);
      } else {
        clipRect(c, r.x + p.x[i], r.y + p.y[i], r.w, r.h, toCanvas(color), sc);
      }
    }
  }
  if (s.mouthOpen && p.mouth >= 0) {
    uint16_t parent = kGroups[sc.group0 + p.mouth].parent;
    if (parent == kNone || p.on[parent]) {
      for (const Box& b : kTalk) c.fillRect(b.x + p.x[p.mouth], b.y + p.y[p.mouth], b.w, b.h, sceneInk(1));
    }
  }
  if (s.heart && p.face >= 0) {
    int cx = kHeartX + p.x[p.face], cy = kHeartY + p.y[p.face];
    if (s.heart >= 2) drawHeart(c, kHeartFull, cx, cy);
    else drawHeart(c, kHeartSmall, cx, cy);
  }
}

}  // namespace render
