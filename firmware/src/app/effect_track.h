// When the face's sound effects play (plan/VOICE.md §10): each design has
// a timeline of events on its own clock, from assets/sfx.h, and this
// follows the face the screen shows, handing over each event as the
// design's clock reaches it. Pure C++ and a function of the device clock,
// like Behaviour, so a frozen clock gives the same events on the board and
// in the simulator. Device plays what it hands over.
#pragma once
#include <cstdint>

#include "render/scene.h"
#include "voice/effects.h"

namespace app {

class EffectTrack {
 public:
  // Events go out this far ahead of their frame: about what the DAC's DMA
  // holds (DEVICE.md §4), so the sound leaves the speaker with the frame.
  static constexpr uint32_t kLeadMs = 70;
  // An event this far behind the design's clock (a stalled loop) is dropped.
  static constexpr uint32_t kLateMs = 150;
  static constexpr int kMaxOut = 16;

  void reset();
  // Follows `s`, the face now, or silence when it's null (a test pattern).
  // Its `t` is the design's clock as Behaviour::designMs gives it, which
  // doesn't wrap: the timeline loops on its own, and its loops are counted
  // from the design's start. Fills `out` with the events now due, in order,
  // and returns how many. `changed` is true when the design changed or
  // started over: the last one's sounds stop before these play.
  int follow(const render::SceneShow* s, voice::FxEvent* out, bool& changed);
  // Whether a mumble turns down the events follow hands over: their
  // design's rule (voice::Score::duck).
  bool duck() const { return score_.duck; }

 private:
  bool on_ = false;  // following a design
  render::Mood mood_ = render::Mood::kHappy;
  render::SceneState state_ = render::SceneState::kIdle;
  uint8_t variant_ = 0;
  voice::Score score_;
  uint32_t loopMs_ = 1;
  uint32_t lastT_ = 0;    // the design's clock last time
  uint32_t covered_ = 0;  // events before this, on the design's clock, are handled
  int64_t cycle_ = -1;    // the loop covered_ is in, and its events: none when it doesn't sound
  voice::Events list_;
};

}  // namespace app
