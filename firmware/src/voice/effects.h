// Sound effects (plan/VOICE.md §10): the animation pack's clips and each
// design's timeline, from assets/sfx.h, and a small mixer that adds them
// to the voice. Pure C++: the board mixes into the DAC's samples, and
// tests render into memory. When each event plays is app/effect_track.h's.
#pragma once
#include <cstddef>
#include <cstdint>

namespace voice {

// When a design's events play: never, every loop, the design's first loop
// only, or its first loop and then at most once per `intervalMs`.
enum class Policy : uint8_t { kSilent, kLoop, kEntry, kSparse };

// One event of a timeline: a clip at a time into the design's loop.
struct FxEvent {
  uint16_t atMs = 0;
  uint8_t clip = 0;
  uint8_t gain = 255;     // 255 plays the clip as loud as a syllable
  uint16_t pitch = 1000;  // permille: 1000 plays the clip as made
};

// A design's timeline. `mood`, `state` and `variant` (from 0) number the
// designs as faces.h does (render/anim.h, render/scene.h); a variation out
// of range takes the first, as the screen does, and anything else unknown
// is silent.
struct Score {
  Policy policy = Policy::kSilent;
  uint32_t intervalMs = 0;
  int first = 0, n = 0;  // its events: fxEvent(first) .. fxEvent(first + n - 1), by time
};
Score score(int mood, int state, int variant);
FxEvent fxEvent(int i);

int effectCount();
const char* effectName(int clip);
int effectIndex(const char* name);  // -1 if unknown
// The needs-you signal's clips, which a mumble never turns down.
bool effectAlert(int clip);
const char* effectsVersion();
uint32_t effectsBytes();

// An event to play now, at the state's volume.
struct Effect {
  int clip = -1;
  uint8_t gain = 255;
  uint16_t pitch = 1000;
  uint8_t vol = 6;  // 0–10, as Line::vol
};

class Effects {
 public:
  static constexpr int kVoices = 4;  // effects at once; a fifth replaces the oldest
  static constexpr int kDuck = 128;  // of 256: under a mumble, half as loud (VOICE.md §10)

  void play(const Effect& e);
  // Every effect fades out over 4 ms, so the cut doesn't click.
  void stop();
  bool playing() const;
  // Adds the effects into `out`, unsigned 8-bit samples at 22.05 kHz with
  // 128 as silence, turned down by kDuck while `duck` unless they're alerts.
  void mix(uint8_t* out, size_t n, bool duck);

 private:
  struct Voice {
    int clip = -1;
    uint32_t src = 0;   // 16.16 source samples
    uint32_t step = 0;  // 16.16 source samples per output sample
    int gain = 0;       // of 65536
    bool alert = false;
    uint32_t fade = 0;  // cut: samples left of the fade, or 0
    uint32_t seq = 0;
  };
  Voice voices_[kVoices];
  uint32_t seq_ = 0;
};

}  // namespace voice
