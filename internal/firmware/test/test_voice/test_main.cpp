// The voice player: the take tables, a take played whole at its recorded
// pitch (11.025 kHz resampled 2× to 22.05 kHz), volume, the cut's fade, and
// the mouth (plan/VOICE.md, plan/DEVICE.md §4–5).
#include <unity.h>

#include <cstdlib>
#include <cstring>
#include <vector>

#include "voice.h"
#include "voice/player.h"

void setUp() {}
void tearDown() {}

namespace {

voice::Line line(const char* id, uint8_t vol = 6) {
  voice::Line l;
  l.take = voice::takeIndex(id);
  l.vol = vol;
  return l;
}

std::vector<uint8_t> renderAll(voice::Player& p, size_t extra = 0) {
  std::vector<uint8_t> out(p.total() + extra);
  size_t made = p.render(out.data(), out.size());
  TEST_ASSERT_EQUAL_UINT32(p.total(), made);
  return out;
}

int peak(const std::vector<uint8_t>& v) {
  int m = 0;
  for (uint8_t s : v) m = std::abs(int(s) - 128) > m ? std::abs(int(s) - 128) : m;
  return m;
}

}  // namespace

// The Mac's Takes.swift comes from the same voicegen run: the same takes by
// the same ids. The voice's flash budget is 480,000 bytes (DEVICE.md §5).
void test_the_takes_and_their_budget() {
  TEST_ASSERT_EQUAL(40, voice::takeCount());
  TEST_ASSERT_EQUAL(0, voice::takeIndex("previous.go"));
  TEST_ASSERT_EQUAL_STRING("Go", voice::takeText(0));
  TEST_ASSERT_EQUAL_STRING("previous.go", voice::takeId(0));
  int boom = voice::takeIndex("new.d15");
  TEST_ASSERT_TRUE(boom >= 0);
  TEST_ASSERT_EQUAL_STRING("Bada bing bada boom", voice::takeText(boom));
  TEST_ASSERT_EQUAL(-1, voice::takeIndex("banana"));
  TEST_ASSERT_EQUAL(-1, voice::takeIndex(nullptr));
  TEST_ASSERT_NULL(voice::takeText(-1));
  TEST_ASSERT_NULL(voice::takeId(40));
  TEST_ASSERT_EQUAL_UINT32(0, voice::takeMs(-1));
  TEST_ASSERT_TRUE(voice::assetsBytes() <= 480000u);
  uint32_t samples = 0;
  for (int i = 0; i < voice::takeCount(); ++i) {
    samples += voice_assets::kTake[i].len;
    // The bubble's font has printable ASCII only (DEVICE.md §4).
    for (const char* c = voice::takeText(i); *c; ++c) TEST_ASSERT_TRUE(*c >= 0x20 && *c <= 0x7E);
  }
  TEST_ASSERT_EQUAL_UINT32(voice_assets::kBytes, samples);
}

// A take plays whole: two output samples for each of its own, so its
// length in ms is the recording's (640 ms for "Go", 7056 samples).
void test_a_take_plays_whole_at_its_pitch() {
  voice::Line l = line("previous.go");
  TEST_ASSERT_EQUAL_UINT32(2 * 7056, voice::lineSamples(l));
  TEST_ASSERT_EQUAL_UINT32(640, voice::takeMs(l.take));
  voice::Player p;
  p.start(l);
  TEST_ASSERT_TRUE(p.playing());
  TEST_ASSERT_EQUAL(l.take, p.take());
  TEST_ASSERT_EQUAL_UINT32(2 * 7056, p.total());
  l.vol = 10;
  p.start(l);
  std::vector<uint8_t> out = renderAll(p, 500);
  TEST_ASSERT_FALSE(p.playing());
  // Even samples are the recording's; odd ones the midpoint of two.
  const uint8_t* d = voice_assets::kSamples + voice_assets::kTake[l.take].at;
  for (uint32_t i = 0; i + 2 < p.total(); i += 2) {
    TEST_ASSERT_INT_WITHIN(1, d[i / 2], out[i]);
    TEST_ASSERT_INT_WITHIN(1, (int(d[i / 2]) + d[i / 2 + 1]) / 2, out[i + 1]);
  }
  for (size_t i = p.total(); i < out.size(); ++i) TEST_ASSERT_EQUAL_UINT8(128, out[i]);  // then silence
  TEST_ASSERT_EQUAL_UINT32(0, p.render(out.data(), 10));
}

void test_an_unknown_take_plays_nothing() {
  voice::Player p;
  p.start(line("banana"));
  TEST_ASSERT_FALSE(p.playing());
  TEST_ASSERT_EQUAL(-1, p.take());
  TEST_ASSERT_EQUAL_UINT32(0, voice::lineSamples(line("banana")));
  uint8_t s[16];
  TEST_ASSERT_EQUAL_UINT32(0, p.render(s, sizeof(s)));
  for (uint8_t v : s) TEST_ASSERT_EQUAL_UINT8(128, v);
}

// VOICE.md: a line cut short, hushed or replaced by another line, fades
// from where it was over 4 ms instead of stepping to silence in one
// sample, which clicks.
void test_a_cut_fades_instead_of_clicking() {
  for (int how = 0; how < 2; ++how) {
    voice::Player p;
    p.start(line("new.d14", 10));
    uint8_t s = 128;
    for (uint32_t i = 0; i < p.total() && std::abs(int(s) - 128) < 60; ++i) p.render(&s, 1);
    TEST_ASSERT_TRUE(std::abs(int(s) - 128) >= 60);  // cut at a loud sample
    if (how == 0) p.stop();
    else p.start(line("banana"));  // replaced by a line that plays nothing
    std::vector<uint8_t> out(200);
    p.render(out.data(), out.size());
    TEST_ASSERT_INT_WITHIN(2, s, out[0]);
    for (size_t i = 1; i < out.size(); ++i) TEST_ASSERT_INT_WITHIN(2, out[i - 1], out[i]);
    TEST_ASSERT_EQUAL_UINT8(128, out[22050 * 4 / 1000]);  // gone after 4 ms
  }
}

void test_volume_scales_and_zero_mutes() {
  voice::Player p;
  p.start(line("new.d14", 10));
  int loud = peak(renderAll(p));
  p.start(line("new.d14", 5));
  int half = peak(renderAll(p));
  TEST_ASSERT_TRUE(loud > 90);
  TEST_ASSERT_INT_WITHIN(3, loud / 2, half);
  p.start(line("new.d14", 0));
  TEST_ASSERT_FALSE(p.playing());
  TEST_ASSERT_EQUAL_UINT32(0, p.total());
}

// The mouth follows the take's loud frames, one per 20 ms (220 samples at
// 11.025 kHz), and is shut before, after and with no take.
void test_the_mouth_follows_the_take() {
  int go = voice::takeIndex("previous.go");
  const uint8_t* m = voice_assets::kMouth + voice_assets::kTake[go].mouth;
  int open = 0;
  for (uint32_t ms = 0; ms < voice::takeMs(go); ++ms) {
    uint32_t frame = ms * 11025 / 1000 / 220;
    TEST_ASSERT_EQUAL(m[frame] != 0, voice::mouthOpen(go, ms));
    open += voice::mouthOpen(go, ms);
  }
  TEST_ASSERT_TRUE(open > 0);
  TEST_ASSERT_FALSE(voice::mouthOpen(go, 0));  // "Go" starts quiet (kMouth's first frame)
  TEST_ASSERT_FALSE(voice::mouthOpen(go, 100000));
  TEST_ASSERT_FALSE(voice::mouthOpen(-1, 100));
  // Every take opens the mouth somewhere.
  for (int i = 0; i < voice::takeCount(); ++i) {
    bool any = false;
    for (uint32_t ms = 0; ms < voice::takeMs(i) && !any; ms += 10) any = voice::mouthOpen(i, ms);
    TEST_ASSERT_TRUE(any);
  }
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_the_takes_and_their_budget);
  RUN_TEST(test_a_take_plays_whole_at_its_pitch);
  RUN_TEST(test_an_unknown_take_plays_nothing);
  RUN_TEST(test_a_cut_fades_instead_of_clicking);
  RUN_TEST(test_volume_scales_and_zero_mutes);
  RUN_TEST(test_the_mouth_follows_the_take);
  return UNITY_END();
}
