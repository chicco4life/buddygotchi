#include "voice/player.h"

#include <cmath>
#include <cstring>

#include "voice.h"  // assets/voice.h: included here only

namespace voice {

namespace {

using voice_assets::Clip;

constexpr uint32_t kFadeOut = kOutRate * 5 / 1000;  // a clip cut short fades over 5 ms
// A line or cue cut short (hushed, or replaced) fades from where it was to
// silence over 4 ms, under whatever comes next: a step in one sample clicks.
constexpr uint32_t kCutFade = kOutRate * 4 / 1000;

const Clip& clipAt(int i) {
  return i < voice_assets::kSyllables ? voice_assets::kSyllable[i] : voice_assets::kWord[i - voice_assets::kSyllables];
}

uint32_t xorshift(uint32_t& s) {
  s ^= s << 13;
  s ^= s >> 17;
  s ^= s << 5;
  return s;
}
int jitter(uint32_t& s, int span) { return int(xorshift(s) % uint32_t(2 * span + 1)) - span; }

// The tune's pitch at slot i of n, in permille (VOICE.md §5).
int contour(Tune t, int i, int n) {
  int u = n > 1 ? i * 1000 / (n - 1) : 0;
  bool last = i == n - 1;
  switch (t) {
    case Tune::kUp: return 1000 + 250 * u / 1000 + (last ? 100 : 0);
    case Tune::kDown: return 1100 - 300 * u / 1000;
    case Tune::kBounce: return i % 2 ? 950 : 1100;
    case Tune::kLift: return last ? 1250 : 1000;
    case Tune::kFlat: break;
  }
  return 980;
}

}  // namespace

Tune tuneFromName(const char* s) {
  if (!s) return Tune::kFlat;
  if (!std::strcmp(s, "up")) return Tune::kUp;
  if (!std::strcmp(s, "down")) return Tune::kDown;
  if (!std::strcmp(s, "bounce")) return Tune::kBounce;
  if (!std::strcmp(s, "lift")) return Tune::kLift;
  return Tune::kFlat;
}

Cue cueFromName(const char* s) {
  if (!s) return Cue::kNone;
  if (!std::strcmp(s, "chirp")) return Cue::kChirp;
  return Cue::kNone;
}

int syllableIndex(const char* s, size_t n) {
  for (int i = 0; i < voice_assets::kSyllables; ++i) {
    const char* name = voice_assets::kSyllable[i].name;
    if (std::strlen(name) == n && !std::strncmp(name, s, n)) return i;
  }
  return -1;
}

int wordIndex(const char* s) {
  if (!s) return -1;
  for (int i = 0; i < voice_assets::kWords; ++i)
    if (!std::strcmp(voice_assets::kWord[i].name, s)) return i;
  return -1;
}

int syllableCount() { return voice_assets::kSyllables; }
int wordCount() { return voice_assets::kWords; }
const char* assetsVersion() { return voice_assets::kVersion; }
uint32_t assetsBytes() { return voice_assets::kBytes; }

uint32_t lineSamples(const Line& l) {
  int beats = l.n + (l.word >= 0 ? 2 : 0);
  return uint32_t(beats) * l.ms * kOutRate / 1000;
}

void Player::plan(const Line& l) {
  uint32_t seed = l.seed ? l.seed : 1;
  uint32_t beat = uint32_t(l.ms) * kOutRate / 1000;
  int n = l.n < 0 ? 0 : l.n > kMaxSyllables ? kMaxSyllables : l.n;
  int at = l.word >= 0 ? (l.at < 0 ? 0 : l.at > n ? n : l.at) : -1;
  nSlots_ = 0;
  bool wordSlot[kMaxSyllables + 1] = {};
  for (int i = 0; i <= n; ++i) {
    if (i == at) {
      wordSlot[nSlots_] = true;
      slots_[nSlots_++] = Slot{voice_assets::kSyllables + l.word, 0, 2 * beat, 0};
    }
    if (i < n) slots_[nSlots_++] = Slot{l.syl[i] == kSilent ? -1 : int(l.syl[i]), 0, beat, 0};
  }
  // Timing: ±10% per beat, moved within pairs so the line's length is exact.
  for (int i = 0; i + 1 < nSlots_; i += 2) {
    uint32_t shorter = slots_[i].len < slots_[i + 1].len ? slots_[i].len : slots_[i + 1].len;
    int d = jitter(seed, int(shorter / 10));
    slots_[i].len = uint32_t(int(slots_[i].len) + d);
    slots_[i + 1].len = uint32_t(int(slots_[i + 1].len) - d);
  }
  uint32_t start = 0;
  for (int i = 0; i < nSlots_; ++i) {
    Slot& s = slots_[i];
    s.start = start;
    start += s.len;
    int c = contour(l.tune, i, nSlots_);
    if (wordSlot[i]) c = 1000 + (c - 1000) / 2;  // the word keeps closer to its own voice
    int rate = c * (1000 + jitter(seed, 50)) / 1000;  // permille, ±5%
    // Clips are 11.025 kHz and the output 22.05 kHz: half a source sample per step.
    s.step = uint32_t(rate) * 32768u / 1000u;
    if (wordSlot[i] && s.clip >= 0) {  // a long word speeds up to fit, up to 1.6×
      uint32_t fit = uint32_t((uint64_t(clipAt(s.clip).len) << 16) / (s.len ? s.len : 1));
      uint32_t most = s.step * 16 / 10;
      if (fit > s.step) s.step = fit < most ? fit : most;
    }
  }
  total_ = start;
}

void Player::start(const Line& l) {
  stop();
  plan(l);
  gain_ = (l.vol > 10 ? 10 : l.vol) * 256 / 10;
  if (gain_ == 0) total_ = 0;  // muted: nothing to play
}

void Player::cue(Cue c, uint8_t vol) {
  stop();
  if (c == Cue::kNone || vol == 0) return;
  cue_ = c;
  gain_ = (vol > 10 ? 10 : vol) * 256 / 10;
  total_ = kOutRate * 90 / 1000;
}

void Player::stop() {
  fadeFrom_ = playing() || fade_ ? last_ : 0;
  fade_ = fadeFrom_ ? kCutFade : 0;
  nSlots_ = slotAt_ = 0;
  pos_ = total_ = src_ = 0;
  cue_ = Cue::kNone;
}

int16_t Player::lineSample(uint32_t i) {
  // slotAt_ counts slots begun, so slots_[slotAt_] is the next one.
  while (slotAt_ < nSlots_ && i >= slots_[slotAt_].start) ++slotAt_, src_ = 0;
  const Slot& s = slots_[slotAt_ - 1];
  if (s.clip < 0) return 0;
  const Clip& c = clipAt(s.clip);
  uint32_t k = src_ >> 16, f = src_ & 0xFFFF;
  src_ += s.step;
  if (k + 1 >= c.len) return 0;
  const uint8_t* d = voice_assets::kSamples + c.at;
  int a = int(d[k]) - 128, b = int(d[k + 1]) - 128;
  int v = a + int((int64_t(b - a) * f) >> 16);
  uint32_t left = s.start + s.len - i;  // cut short at the slot's end: fade
  if (left < kFadeOut) v = v * int(left) / int(kFadeOut);
  return int16_t(v);
}

int16_t Player::cueSample(uint32_t i) const {
  float t = float(i) / kOutRate;
  float T = float(total_) / kOutRate;
  const float f0 = 1200, f1 = 2400;  // rising, like a question
  float phase = f0 * t + (f1 - f0) * t * t / (2 * T);  // in cycles
  float x = phase - std::floor(phase);
  float tri = x < 0.5f ? 4 * x - 1 : 3 - 4 * x;
  float env = t < 0.003f ? t / 0.003f : 1 - t / T;
  return int16_t(100 * tri * env);
}

size_t Player::render(uint8_t* out, size_t n) {
  size_t made = 0;
  for (size_t j = 0; j < n; ++j) {
    int v = 0;
    if (pos_ < total_) {
      v = cue_ != Cue::kNone ? cueSample(pos_) : lineSample(pos_);
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
