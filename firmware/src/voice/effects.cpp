#include "voice/effects.h"

#include <cstring>

#include "sfx.h"  // assets/sfx.h: included here only
#include "voice/player.h"

namespace voice {

namespace {

constexpr uint32_t kCutFade = kOutRate * 4 / 1000;

static_assert(sfx_assets::kRate * 2 == kOutRate, "clips are half the output rate, as the voice's are");

int scoreIndex(int mood, int state, int variant) {
  if (mood < 0 || mood >= sfx_assets::kMoods || state < 0 || state >= sfx_assets::kStates) return -1;
  if (variant < 0 || variant >= sfx_assets::kVariants[state]) variant = 0;
  int i = 0;
  for (int s = 0; s < sfx_assets::kStates; ++s) i += sfx_assets::kVariants[s];
  i *= mood;
  for (int s = 0; s < state; ++s) i += sfx_assets::kVariants[s];
  return i + variant;
}

}  // namespace

Score score(int mood, int state, int variant) {
  int i = scoreIndex(mood, state, variant);
  if (i < 0) return {};
  const sfx_assets::Score& s = sfx_assets::kScore[i];
  Score out;
  out.policy = Policy(s.policy);
  out.intervalMs = s.intervalMs;
  out.first = s.first;
  out.n = s.n;
  return out;
}

FxEvent fxEvent(int i) {
  const sfx_assets::Event& e = sfx_assets::kEvent[i];
  FxEvent out;
  out.atMs = e.atMs;
  out.clip = e.clip;
  out.gain = e.gain;
  out.pitch = e.pitch;
  return out;
}

int effectCount() { return sfx_assets::kClips; }
const char* effectName(int clip) { return clip >= 0 && clip < sfx_assets::kClips ? sfx_assets::kClip[clip].name : ""; }
int effectIndex(const char* name) {
  for (int i = 0; i < sfx_assets::kClips; ++i)
    if (name && std::strcmp(name, sfx_assets::kClip[i].name) == 0) return i;
  return -1;
}
bool effectAlert(int clip) { return clip >= 0 && clip < sfx_assets::kClips && sfx_assets::kClip[clip].alert; }
const char* effectsVersion() { return sfx_assets::kVersion; }
uint32_t effectsBytes() { return sfx_assets::kBytes; }

void Effects::play(const Effect& e) {
  if (e.clip < 0 || e.clip >= sfx_assets::kClips || e.vol == 0 || e.gain == 0) return;
  Voice* v = &voices_[0];  // a free voice, or else the oldest
  for (Voice& c : voices_) {
    if (c.clip < 0) {
      v = &c;
      break;
    }
    if (c.seq < v->seq) v = &c;
  }
  v->clip = e.clip;
  v->src = 0;
  // Clips are 11.025 kHz and the output 22.05 kHz: half a source sample per step.
  v->step = uint32_t(e.pitch) * 32768u / 1000u;
  v->gain = int(e.gain) * (int(e.vol > 10 ? 10 : e.vol) * 256 / 10);
  v->alert = effectAlert(e.clip);
  v->fade = 0;
  v->seq = ++seq_;
}

void Effects::stop() {
  for (Voice& v : voices_)
    if (v.clip >= 0 && !v.fade) v.fade = kCutFade;
}

bool Effects::playing() const {
  for (const Voice& v : voices_)
    if (v.clip >= 0) return true;
  return false;
}

void Effects::mix(uint8_t* out, size_t n, bool duck) {
  if (!playing()) return;
  for (size_t j = 0; j < n; ++j) {
    int sum = 0;
    for (Voice& v : voices_) {
      if (v.clip < 0) continue;
      const sfx_assets::Clip& c = sfx_assets::kClip[v.clip];
      uint32_t k = v.src >> 16, f = v.src & 0xFFFF;
      if (k + 1 >= c.len) {
        v.clip = -1;
        continue;
      }
      const uint8_t* d = sfx_assets::kSamples + c.at;
      int a = int(d[k]) - 128, b = int(d[k + 1]) - 128;
      int s = a + int((int64_t(b - a) * f) >> 16);
      int g = duck && !v.alert ? v.gain * kDuck / 256 : v.gain;
      s = int((int64_t(s) * g) >> 16);
      if (v.fade) {
        s = s * int(v.fade) / int(kCutFade);
        if (--v.fade == 0) v.clip = -1;
      }
      sum += s;
      v.src += v.step;
    }
    int o = int(out[j]) + sum;
    out[j] = uint8_t(o < 0 ? 0 : o > 255 ? 255 : o);
  }
}

}  // namespace voice
