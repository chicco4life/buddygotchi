// The voice player (plan/VOICE.md): plays one recorded take from
// assets/voice.h, whole and at its recorded pitch, as 8-bit samples at
// 22.05 kHz for the DAC. The takes are 11.025 kHz; each is resampled 2×
// with linear interpolation as it plays. Pure C++: the board feeds the DAC
// from it, and tests and the simulator render it into memory.
#pragma once
#include <cstddef>
#include <cstdint>

namespace voice {

constexpr uint32_t kOutRate = 22050;

// The takes, from the tables in assets/voice.h. An index of -1 (or out of
// range) is no take: no text, 0 ms, the mouth shut.
int takeIndex(const char* id);  // -1 if unknown or null
int takeCount();
const char* takeId(int i);    // null for no take
const char* takeText(int i);  // the bubble's text; null for no take
uint32_t takeMs(int i);       // how long it plays, rounded down, as the Mac's Take.ms
// Whether the mouth is open `ms` into take i (the take's loud frames, one
// per kMouthMs); shut before and after it.
bool mouthOpen(int i, uint32_t ms);
const char* assetsVersion();
uint32_t assetsBytes();

// One line, as `moment.say` gave it (PROTOCOL.md §3), plus the volume
// from `state`.
struct Line {
  int take = -1;    // the take's index, or -1: nothing plays
  uint8_t vol = 6;  // 0–10, held in range by the device
};

// How long a line takes, in output samples: two for each of the take's.
uint32_t lineSamples(const Line& l);

class Player {
 public:
  void start(const Line& l);
  void stop();
  bool playing() const { return total_ > 0 && pos_ < total_; }

  // Fills `n` unsigned 8-bit samples (128 is silence). Returns how many
  // came from the line; the rest are silence.
  size_t render(uint8_t* out, size_t n);

  // The take playing (-1 for none) and its length in output samples.
  int take() const { return take_; }
  uint32_t total() const { return total_; }

 private:
  int take_ = -1;
  uint32_t pos_ = 0;
  uint32_t total_ = 0;
  int gain_ = 0;       // 0–256
  int last_ = 0;       // the last sample out, around 0
  int fadeFrom_ = 0;   // what was cut, fading out over the next fade_ samples
  uint32_t fade_ = 0;
};

}  // namespace voice
