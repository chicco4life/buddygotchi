// The voice player: the asset tables, the line's timeline, and resampling
// for pitch, tempo and volume (plan/PLAN.md F5, L0).
#include <unity.h>

#include <cstdlib>
#include <cstring>
#include <vector>

#include "voice/player.h"

void setUp() {}
void tearDown() {}

namespace {

voice::Line line(const char* const* syl, int n, int word = -1, int at = 0) {
  voice::Line l;
  for (int i = 0; i < n; ++i) l.syl[i] = uint8_t(voice::syllableIndex(syl[i], std::strlen(syl[i])));
  l.n = n;
  l.word = word;
  l.at = at;
  return l;
}

std::vector<uint8_t> renderAll(voice::Player& p, size_t extra = 0) {
  std::vector<uint8_t> out(p.total() + extra);
  size_t made = p.render(out.data(), out.size());
  TEST_ASSERT_EQUAL_UINT32(p.total(), made);
  return out;
}

int sounding(const std::vector<uint8_t>& v) {
  int n = 0;
  for (uint8_t s : v) n += s != 128;
  return n;
}

int peak(const std::vector<uint8_t>& v) {
  int m = 0;
  for (uint8_t s : v) m = std::abs(int(s) - 128) > m ? std::abs(int(s) - 128) : m;
  return m;
}

const char* const kFour[] = {"bi", "do", "ba", "na"};

}  // namespace

void test_assets_match_sounds_swift() {
  TEST_ASSERT_EQUAL(64, voice::syllableCount());
  TEST_ASSERT_EQUAL(40, voice::wordCount());
  TEST_ASSERT_EQUAL(0, voice::syllableIndex("ba", 2));
  TEST_ASSERT_TRUE(voice::syllableIndex("mm", 2) >= 0);
  TEST_ASSERT_TRUE(voice::syllableIndex("pum", 3) >= 0);
  TEST_ASSERT_EQUAL(-1, voice::syllableIndex("sha", 3));
  TEST_ASSERT_EQUAL(0, voice::wordIndex("tests"));
  TEST_ASSERT_TRUE(voice::wordIndex("done") >= 0);
  TEST_ASSERT_EQUAL(-1, voice::wordIndex("banana"));
  // About 360 KB was budgeted (VOICE.md §8).
  TEST_ASSERT_TRUE(voice::assetsBytes() < 360u * 1024);
}

void test_line_length_is_beats_times_ms() {
  voice::Line l = line(kFour, 4);
  l.ms = 120;
  TEST_ASSERT_EQUAL_UINT32(4 * 120 * 22050 / 1000, voice::lineSamples(l));
  l.word = voice::wordIndex("done");
  l.at = 4;
  TEST_ASSERT_EQUAL_UINT32(6 * 120 * 22050 / 1000, voice::lineSamples(l));  // a word is two beats
}

void test_timing_jitter_keeps_the_total_exact() {
  for (uint32_t seed = 1; seed < 40; ++seed) {
    for (int n = 1; n <= 8; ++n) {
      voice::Line l = line(kFour, n > 4 ? 4 : n);
      l.n = n;
      for (int i = 4; i < n; ++i) l.syl[i] = l.syl[i - 4];
      l.word = seed % 2 ? voice::wordIndex("tests") : -1;
      l.at = int(seed % uint32_t(n + 1));
      l.seed = seed;
      voice::Player p;
      p.start(l);
      TEST_ASSERT_EQUAL_UINT32(voice::lineSamples(l), p.total());
      TEST_ASSERT_EQUAL(n + (l.word >= 0 ? 1 : 0), p.slots());
      renderAll(p);
      TEST_ASSERT_FALSE(p.playing());
      TEST_ASSERT_EQUAL(p.slots(), p.slotsStarted());
    }
  }
}

void test_render_pads_with_silence_after_the_line() {
  voice::Line l = line(kFour, 2);
  voice::Player p;
  p.start(l);
  std::vector<uint8_t> out(p.total() + 500);
  TEST_ASSERT_EQUAL_UINT32(p.total(), p.render(out.data(), out.size()));
  for (size_t i = p.total(); i < out.size(); ++i) TEST_ASSERT_EQUAL_UINT8(128, out[i]);
  TEST_ASSERT_EQUAL_UINT32(0, p.render(out.data(), 10));
}

void test_a_higher_tune_plays_the_clip_faster() {
  // A long beat, so the whole clip fits. A lone syllable is 0.98× flat and
  // 1.25× with the lift (VOICE.md §5), so lifted it's done in 0.784 the time.
  const char* const one[] = {"ba"};
  voice::Line l = line(one, 1);
  l.ms = 400;
  l.seed = 7;
  voice::Player p;
  l.tune = voice::Tune::kFlat;
  p.start(l);
  int slow = sounding(renderAll(p));
  l.tune = voice::Tune::kLift;
  p.start(l);
  int fast = sounding(renderAll(p));
  int ratio = fast * 1000 / slow;
  TEST_ASSERT_INT_WITHIN(60, 784, ratio);
}

void test_short_beats_cut_the_clip_with_a_fade() {
  const char* const one[] = {"pum"};
  voice::Line l = line(one, 1);
  l.ms = 60;  // shorter than the clip
  voice::Player p;
  p.start(l);
  std::vector<uint8_t> out = renderAll(p);
  // The last sample of the beat has faded to (almost) silence.
  TEST_ASSERT_INT_WITHIN(2, 128, out.back());
}

// VOICE.md §8: a line cut short, hushed or replaced by another line or the
// chirp, fades from where it was over 4 ms instead of stepping to silence
// in one sample, which clicks.
void test_a_cut_fades_instead_of_clicking() {
  for (int how = 0; how < 3; ++how) {
    voice::Line l = line(kFour, 4);
    l.vol = 10;
    voice::Player p;
    p.start(l);
    uint8_t s = 128;
    for (uint32_t i = 0; i < p.total() && std::abs(int(s) - 128) < 60; ++i) p.render(&s, 1);
    TEST_ASSERT_TRUE(std::abs(int(s) - 128) >= 60);  // cut at a loud sample
    voice::Line silent = line(kFour, 2);
    silent.syl[0] = silent.syl[1] = voice::kSilent;
    if (how == 0) p.stop();
    else if (how == 1) p.start(silent);
    else p.cue(voice::Cue::kChirp, 10);
    std::vector<uint8_t> out(200);
    p.render(out.data(), out.size());
    TEST_ASSERT_INT_WITHIN(2, s, out[0]);
    if (how == 2) continue;  // the chirp's own wave steps more than that
    for (size_t i = 1; i < out.size(); ++i) TEST_ASSERT_INT_WITHIN(2, out[i - 1], out[i]);
    TEST_ASSERT_EQUAL_UINT8(128, out[22050 * 4 / 1000]);  // gone after 4 ms
  }
}

void test_volume_scales_and_zero_mutes() {
  voice::Line l = line(kFour, 4);
  voice::Player p;
  l.vol = 10;
  p.start(l);
  int loud = peak(renderAll(p));
  l.vol = 5;
  p.start(l);
  int half = peak(renderAll(p));
  TEST_ASSERT_TRUE(loud > 90);
  TEST_ASSERT_INT_WITHIN(3, loud / 2, half);
  l.vol = 0;
  p.start(l);
  TEST_ASSERT_FALSE(p.playing());
  TEST_ASSERT_EQUAL_UINT32(0, p.total());
}

void test_same_seed_same_sound() {
  voice::Line l = line(kFour, 4, voice::wordIndex("done"), 4);
  l.tune = voice::Tune::kBounce;
  voice::Player p;
  l.seed = 42;
  p.start(l);
  std::vector<uint8_t> a = renderAll(p);
  p.start(l);
  std::vector<uint8_t> b = renderAll(p);
  TEST_ASSERT_TRUE(a == b);
  l.seed = 43;
  p.start(l);
  std::vector<uint8_t> c = renderAll(p);
  TEST_ASSERT_FALSE(a == c);
}

void test_unknown_syllables_keep_their_beat_silent() {
  voice::Line l = line(kFour, 2);
  l.syl[0] = voice::kSilent;
  l.syl[1] = voice::kSilent;
  voice::Player p;
  p.start(l);
  std::vector<uint8_t> out = renderAll(p);
  TEST_ASSERT_EQUAL_UINT32(voice::lineSamples(l), out.size());
  TEST_ASSERT_EQUAL(0, sounding(out));
}

void test_names_and_cues() {
  TEST_ASSERT_TRUE(voice::tuneFromName("up") == voice::Tune::kUp);
  TEST_ASSERT_TRUE(voice::tuneFromName("lift") == voice::Tune::kLift);
  TEST_ASSERT_TRUE(voice::tuneFromName(nullptr) == voice::Tune::kFlat);
  TEST_ASSERT_TRUE(voice::cueFromName("chirp") == voice::Cue::kChirp);
  TEST_ASSERT_TRUE(voice::cueFromName("jingle") == voice::Cue::kNone);  // the chirp is the only cue
  voice::Player p;
  p.cue(voice::Cue::kChirp, 6);
  TEST_ASSERT_EQUAL_UINT32(22050 * 90 / 1000, p.total());
  TEST_ASSERT_TRUE(sounding(renderAll(p)) > 1000);
  p.cue(voice::Cue::kChirp, 0);
  TEST_ASSERT_FALSE(p.playing());
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_assets_match_sounds_swift);
  RUN_TEST(test_line_length_is_beats_times_ms);
  RUN_TEST(test_timing_jitter_keeps_the_total_exact);
  RUN_TEST(test_render_pads_with_silence_after_the_line);
  RUN_TEST(test_a_higher_tune_plays_the_clip_faster);
  RUN_TEST(test_short_beats_cut_the_clip_with_a_fade);
  RUN_TEST(test_a_cut_fades_instead_of_clicking);
  RUN_TEST(test_volume_scales_and_zero_mutes);
  RUN_TEST(test_same_seed_same_sound);
  RUN_TEST(test_unknown_syllables_keep_their_beat_silent);
  RUN_TEST(test_names_and_cues);
  return UNITY_END();
}
