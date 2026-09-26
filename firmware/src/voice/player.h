// The voice player (plan/VOICE.md §5, §8): turns a `say` line into 8-bit
// samples at 22.05 kHz for the DAC. Each syllable is one clip from
// assets/voice.h, resampled as it plays, so pitch and tempo change without
// new assets (the Animal Crossing trick). Pure C++: the board feeds the DAC
// from it, and tests and the simulator render it into memory.
#pragma once
#include <cstddef>
#include <cstdint>

namespace voice {

constexpr uint32_t kOutRate = 22050;
constexpr int kMaxSyllables = 12;
constexpr uint8_t kSilent = 0xFF;  // a syllable with no clip: its beat stays silent

enum class Tune : uint8_t { kFlat, kUp, kDown, kBounce, kLift };
Tune tuneFromName(const char* s);

// Clip lookup by name, from the tables in assets/voice.h. -1 if unknown.
int syllableIndex(const char* s, size_t n);
int wordIndex(const char* s);
int syllableCount();
int wordCount();
const char* assetsVersion();
uint32_t assetsBytes();

// One line, as `moment.say` gave it (PROTOCOL.md §3) plus the volume from
// `state`. It plays at the voice's own pitch.
struct Line {
  uint8_t syl[kMaxSyllables];  // syllable clip indices, or kSilent
  int n = 0;
  int word = -1;  // word clip index, or -1
  int at = 0;     // the word goes before syllable `at` (n: at the end)
  Tune tune = Tune::kFlat;
  uint16_t ms = 120;    // per syllable; the word takes two beats
  uint8_t vol = 6;      // 0–10
  uint32_t seed = 1;    // liveliness: ±5% pitch, ±10% timing per syllable
};

// Short sound cues (BEHAVIORS.md §4): a rising chirp.
enum class Cue : uint8_t { kNone, kChirp };
Cue cueFromName(const char* s);

// How long a line takes, in output samples: every beat plus two for the
// word. Timing jitter moves the boundaries inside pairs of beats, so the
// total is exact.
uint32_t lineSamples(const Line& l);

class Player {
 public:
  void start(const Line& l);
  void cue(Cue c, uint8_t vol);
  void stop();
  bool playing() const { return total_ > 0 && pos_ < total_; }

  // Fills `n` unsigned 8-bit samples (128 is silence). Returns how many
  // came from the line or cue; the rest are silence.
  size_t render(uint8_t* out, size_t n);

  // The timeline so far: slots (beats of syllables plus the word) that
  // started, of how many, and samples out of the total.
  int slotsStarted() const { return slotAt_; }
  int slots() const { return nSlots_; }
  uint32_t position() const { return pos_; }
  uint32_t total() const { return total_; }

 private:
  struct Slot {
    int clip = -1;          // index into the flat clip table: syllables, then words
    uint32_t start = 0;     // in output samples
    uint32_t len = 0;
    uint32_t step = 0;      // 16.16 source samples per output sample
  };
  void plan(const Line& l);
  int16_t lineSample(uint32_t i);
  int16_t cueSample(uint32_t i) const;

  Slot slots_[kMaxSyllables + 1];
  int nSlots_ = 0;
  int slotAt_ = 0;     // the slot `pos_` is in, plus one once it began
  uint32_t pos_ = 0;
  uint32_t total_ = 0;
  uint32_t src_ = 0;   // 16.16 read position in the current clip
  int gain_ = 0;       // 0–256
  Cue cue_ = Cue::kNone;
};

}  // namespace voice
