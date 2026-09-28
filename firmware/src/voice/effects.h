// Sound effects (plan/VOICE.md §10): the animation bank's clips and each
// design's timeline, from assets/sfx.h, and a small mixer that adds them
// to the voice. Pure C++: the board mixes into the DAC's samples, and
// tests render into memory. When each event plays is app/effect_track.h's.
#pragma once
#include <cstddef>
#include <cstdint>

namespace voice {

// When a design's events play: never, every loop, the design's first loop
// only, or its first loop and every `every`th after it, as the bank's player
// counts them.
enum class Policy : uint8_t { kSilent, kLoop, kEntry, kSparse };

// One event of a timeline: a clip at a time into the design's loop.
struct FxEvent {
  uint16_t atMs = 0;
  uint8_t clip = 0;
  uint8_t gain = 255;     // 255 plays the clip as loud as a syllable
  uint16_t pitch = 1000;  // permille: 1000 plays the clip as made
  bool duck = true;       // its design's: a mumble turns it down (Score::duck)
};

// A design's timeline. `mood`, `state` and `variant` (from 0) number the
// designs as faces.h does (render/anim.h, render/scene.h); a variation out
// of range takes the first, as the screen does, and anything else unknown
// is silent. A routine design's loops don't all sound alike: the bank's mix
// picks a few of its contacts afresh each loop, and sfx.h keeps its picks
// for kLoops loops, so loop n plays list n % kLoops.
struct Score {
  Policy policy = Policy::kSilent;
  int every = 1;          // sparse: the loops that sound are 0, every, 2 × every…
  bool duck = true;       // a mumble turns it down; never needs you's, the finish's or an error's
  uint16_t voiceMs = 0;   // its voice window's start: a mumble over the design starts no sooner
  int lists = 0, loop0 = 0;  // its loops' event lists (1, or kLoops), for events()
};
constexpr int kLoops = 8;
Score score(int mood, int state, int variant);
// The events of a design's loop `loop` (from 0), when that loop sounds:
// fxEvent(first) .. fxEvent(first + n - 1), by time.
struct Events {
  int first = 0, n = 0;
};
Events events(const Score& s, uint32_t loop);
FxEvent fxEvent(int i);

int effectCount();
const char* effectName(int clip);
int effectIndex(const char* name);  // -1 if unknown
const char* effectsVersion();
uint32_t effectsBytes();

// An event to play now, at the state's volume.
struct Effect {
  int clip = -1;
  uint8_t gain = 255;
  uint16_t pitch = 1000;
  uint8_t vol = 6;    // 0–10, as Line::vol
  bool duck = true;   // a mumble turns it down (Score::duck)
};

class Effects {
 public:
  static constexpr int kVoices = 4;  // effects at once; a fifth replaces the oldest
  static constexpr int kDuck = 64;   // of 256: under a mumble, a quarter as loud, the bank's level (VOICE.md §10)

  void play(const Effect& e);
  // Every effect fades out over 4 ms, so the cut doesn't click.
  void stop();
  bool playing() const;
  // Adds the effects into `out`, unsigned 8-bit samples at 22.05 kHz with
  // 128 as silence, turned down by kDuck while `duck`, but for those whose
  // design a mumble never turns down.
  void mix(uint8_t* out, size_t n, bool duck);

 private:
  struct Voice {
    int clip = -1;
    uint32_t src = 0;   // 16.16 source samples
    uint32_t step = 0;  // 16.16 source samples per output sample
    int gain = 0;       // of 65536
    bool duck = true;
    uint32_t fade = 0;  // cut: samples left of the fade, or 0
    uint32_t seq = 0;
  };
  Voice voices_[kVoices];
  uint32_t seq_ = 0;
};

}  // namespace voice
