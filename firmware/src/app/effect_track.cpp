#include "app/effect_track.h"

namespace app {

void EffectTrack::reset() { *this = EffectTrack{}; }

int EffectTrack::follow(const render::SceneShow* s, uint32_t t, voice::FxEvent* out, bool& changed) {
  changed = false;
  if (!s) {
    changed = on_;
    on_ = false;
    return 0;
  }
  uint8_t variant = s->variant < render::variants(s->state) ? s->variant : 0;  // as the screen draws it
  if (!on_ || s->mood != mood_ || s->state != state_ || variant != variant_ || s->t < lastT_) {
    // Another design, or the same one starting over: its timeline picks up
    // where its clock is, so a mood changing mid-loop doesn't replay what
    // the loop already passed.
    changed = on_;
    on_ = true;
    mood_ = s->mood, state_ = s->state, variant_ = variant;
    score_ = voice::score(int(mood_), int(state_), variant_);
    loopMs_ = render::loopMs(mood_, state_, variant_);
    if (loopMs_ == 0) loopMs_ = 1;
    covered_ = s->t;
    cycle_ = -1;
  }
  lastT_ = s->t;
  if (s->t > covered_ + kLateMs) covered_ = s->t;  // stalled: what's that late would only jar
  uint32_t until = s->t + kLeadMs;
  int n = 0;
  while (covered_ < until) {
    int64_t cycle = covered_ / loopMs_;
    uint32_t start = uint32_t(cycle) * loopMs_;
    uint32_t end = start + loopMs_ < until ? start + loopMs_ : until;
    if (cycle != cycle_) {
      cycle_ = cycle;
      switch (score_.policy) {
        case voice::Policy::kLoop: cycleOn_ = true; break;
        case voice::Policy::kEntry: cycleOn_ = cycle == 0; break;
        case voice::Policy::kSparse:
          cycleOn_ = score_.n > 0 && (!sparseEver_ || t - sparseAt_ >= score_.intervalMs);
          if (cycleOn_) sparseEver_ = true, sparseAt_ = t;
          break;
        case voice::Policy::kSilent: cycleOn_ = false; break;
      }
    }
    if (cycleOn_) {
      for (int i = 0; i < score_.n; ++i) {
        voice::FxEvent e = voice::fxEvent(score_.first + i);
        uint32_t at = start + e.atMs;
        if (at < covered_ || at >= end) continue;
        if (n < kMaxOut) out[n++] = e;  // more at once than that would only be noise
      }
    }
    covered_ = end;
  }
  return n;
}

}  // namespace app
