#include "voice/player.h"

#include <cstring>

#include "voice.h"  // assets/voice.h: included here only

namespace voice {

namespace {

using voice_assets::Take;

// A line cut short (hushed, or replaced) fades from where it was to
// silence over 4 ms, under whatever comes next: a step in one sample clicks.
constexpr uint32_t kCutFade = kOutRate * 4 / 1000;
// The mouth's frames are this many source samples (voicegen's MOUTH_MS).
constexpr uint32_t kMouthSamples = voice_assets::kRate * voice_assets::kMouthMs / 1000;
static_assert(kOutRate == 2 * voice_assets::kRate, "the takes play at half a source sample per output sample");

bool valid(int i) { return i >= 0 && i < voice_assets::kTakes; }

}  // namespace

int takeIndex(const char* id) {
  if (!id) return -1;
  for (int i = 0; i < voice_assets::kTakes; ++i)
    if (!std::strcmp(voice_assets::kTake[i].id, id)) return i;
  return -1;
}

int takeCount() { return voice_assets::kTakes; }
const char* takeId(int i) { return valid(i) ? voice_assets::kTake[i].id : nullptr; }
const char* takeText(int i) { return valid(i) ? voice_assets::kTake[i].text : nullptr; }

uint32_t takeMs(int i) {
  if (!valid(i)) return 0;
  return uint32_t(voice_assets::kTake[i].len) * 1000 / voice_assets::kRate;  // as the Mac's Take.ms
}

bool mouthOpen(int i, uint32_t ms) {
  if (!valid(i)) return false;
  const Take& k = voice_assets::kTake[i];
  uint32_t frame = uint32_t(uint64_t(ms) * voice_assets::kRate / 1000) / kMouthSamples;
  uint32_t frames = (k.len + kMouthSamples - 1) / kMouthSamples;
  return frame < frames && voice_assets::kMouth[k.mouth + frame];
}

const char* assetsVersion() { return voice_assets::kVersion; }
uint32_t assetsBytes() { return voice_assets::kBytes; }

uint32_t lineSamples(const Line& l) { return valid(l.take) ? 2u * voice_assets::kTake[l.take].len : 0; }

void Player::start(const Line& l) {
  stop();
  gain_ = l.vol * 256 / 10;
  take_ = valid(l.take) && gain_ ? l.take : -1;  // muted, or no take: nothing to play
  total_ = take_ >= 0 ? lineSamples(l) : 0;
}

void Player::stop() {
  fadeFrom_ = playing() || fade_ ? last_ : 0;
  fade_ = fadeFrom_ ? kCutFade : 0;
  take_ = -1;
  pos_ = total_ = 0;
}

size_t Player::render(uint8_t* out, size_t n) {
  size_t made = 0;
  for (size_t j = 0; j < n; ++j) {
    int v = 0;
    if (pos_ < total_) {
      // Half a source sample per output sample: every other one is the
      // midpoint of two neighbours (linear interpolation, 16.16 step 32768).
      const Take& k = voice_assets::kTake[take_];
      const uint8_t* d = voice_assets::kSamples + k.at;
      uint32_t s = pos_ >> 1;
      int a = int(d[s]) - 128;
      int b = s + 1 < k.len ? int(d[s + 1]) - 128 : 0;
      v = pos_ & 1 ? (a + b) / 2 : a;
      ++pos_;
      ++made;
    }
    v = 128 + ((v * gain_) >> 8);
    if (fade_) v += fadeFrom_ * int(fade_--) / int(kCutFade);  // what was cut, fading out
    out[j] = uint8_t(v < 0 ? 0 : v > 255 ? 255 : v);
    last_ = out[j] - 128;
  }
  return made;
}

}  // namespace voice
