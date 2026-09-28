// The face's sound effects (plan/VOICE.md §10): the pack's clips and
// timelines as assets/sfx.h has them, the mixer, and when each event plays.
#include <unity.h>

#include <cstdlib>
#include <cstring>
#include <vector>

#include "app/effect_track.h"
#include "render/scene.h"
#include "voice/effects.h"
#include "voice/player.h"

void setUp() {}
void tearDown() {}

namespace {

using render::Mood;
using render::SceneState;

int peak(const std::vector<uint8_t>& v) {
  int m = 0;
  for (uint8_t s : v) m = std::abs(int(s) - 128) > m ? std::abs(int(s) - 128) : m;
  return m;
}

// The mixer's output for one effect, alone, from silence.
std::vector<uint8_t> mixed(voice::Effect e, bool duck = false, size_t n = 22050) {
  voice::Effects fx;
  fx.play(e);
  std::vector<uint8_t> out(n, 128);
  fx.mix(out.data(), out.size(), duck);
  return out;
}

size_t lastSounding(const std::vector<uint8_t>& v) {
  size_t last = 0;
  for (size_t i = 0; i < v.size(); ++i)
    if (v[i] != 128) last = i;
  return last;
}

voice::Effect effect(const char* name, uint8_t gain = 255, uint16_t pitch = 1000, uint8_t vol = 6) {
  voice::Effect e;
  e.clip = voice::effectIndex(name);
  e.gain = gain, e.pitch = pitch, e.vol = vol;
  return e;
}

render::SceneShow face(Mood m, SceneState s, uint8_t variant, uint32_t t) {
  render::SceneShow f;
  f.mood = m, f.state = s, f.variant = variant, f.t = t;
  return f;
}

// Follows one design from its start to `until` in 10 ms steps, noting when
// (on its clock) each event came out.
struct Heard {
  std::vector<uint32_t> at;
  std::vector<voice::FxEvent> ev;
  int changes = 0;
};
Heard follow(app::EffectTrack& track, Mood m, SceneState s, uint8_t variant, uint32_t from, uint32_t until,
             uint32_t t0 = 0) {
  Heard h;
  for (uint32_t t = from; t <= until; t += 10) {
    render::SceneShow f = face(m, s, variant, t);
    voice::FxEvent out[app::EffectTrack::kMaxOut];
    bool changed;
    int n = track.follow(&f, t0 + t, out, changed);
    h.changes += changed;
    for (int i = 0; i < n; ++i) h.at.push_back(t), h.ev.push_back(out[i]);
  }
  return h;
}

}  // namespace

// Every design the device draws has a timeline, with clips it has.
void test_every_design_has_a_timeline() {
  TEST_ASSERT_EQUAL(47, voice::effectCount());
  // About 180 KB was budgeted (VOICE.md §10).
  TEST_ASSERT_TRUE(voice::effectsBytes() < 180u * 1024);
  for (int m = 0; m < int(Mood::kCount); ++m)
    for (int s = 0; s < int(SceneState::kCount); ++s)
      for (int v = 0; v < render::variants(SceneState(s)); ++v) {
        voice::Score sc = voice::score(m, s, v);
        uint32_t loop = render::loopMs(Mood(m), SceneState(s), v);
        uint16_t prev = 0;
        for (int i = 0; i < sc.n; ++i) {
          voice::FxEvent e = voice::fxEvent(sc.first + i);
          TEST_ASSERT_TRUE(e.clip < voice::effectCount());
          TEST_ASSERT_TRUE(e.atMs >= prev);  // by time
          TEST_ASSERT_TRUE(e.atMs < loop);   // inside the design's loop
          TEST_ASSERT_TRUE(e.gain > 0);
          TEST_ASSERT_TRUE(e.pitch >= 900 && e.pitch <= 1150);
          prev = e.atMs;
        }
      }
  // A variation out of range takes the first, as the screen does.
  voice::Score a = voice::score(0, int(SceneState::kWorking), 0);
  voice::Score b = voice::score(0, int(SceneState::kWorking), 9);
  TEST_ASSERT_EQUAL(a.first, b.first);
  TEST_ASSERT_EQUAL(0, voice::score(9, 0, 0).n);
}

// The pack's policies, by state (VOICE.md §10).
void test_each_state_sounds_as_the_pack_says() {
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int v = 0; v < 3; ++v) {
      TEST_ASSERT_TRUE(voice::score(m, int(SceneState::kAsleep), v).policy == voice::Policy::kSilent);
      TEST_ASSERT_TRUE(voice::score(m, int(SceneState::kNoApp), v).policy == voice::Policy::kSilent);
      TEST_ASSERT_TRUE(voice::score(m, int(SceneState::kTaskComplete), v).policy == voice::Policy::kEntry);
      voice::Score ny = voice::score(m, int(SceneState::kNeedsYou), v);
      TEST_ASSERT_TRUE(ny.policy == voice::Policy::kEntry);
      bool ding = false;  // every needs-you performance ends in the ding
      for (int i = 0; i < ny.n; ++i) ding |= voice::fxEvent(ny.first + i).clip == voice::effectIndex("alertDing");
      TEST_ASSERT_TRUE(ding);
    }
    TEST_ASSERT_TRUE(voice::score(m, int(SceneState::kIdle), 0).policy == voice::Policy::kSilent);
    for (int v = 1; v < 3; ++v) {
      voice::Score idle = voice::score(m, int(SceneState::kIdle), v);
      TEST_ASSERT_TRUE(idle.policy == voice::Policy::kSparse);
      TEST_ASSERT_EQUAL_UINT32(45000, idle.intervalMs);
    }
    for (int v = 0; v < 5; ++v) {
      voice::Score w = voice::score(m, int(SceneState::kWorking), v);
      TEST_ASSERT_TRUE(w.policy == voice::Policy::kLoop);
      TEST_ASSERT_TRUE(w.n > 0);
    }
  }
}

// A clip plays once, as loud as its gain and the volume say, and a higher
// pitch plays it faster.
void test_an_effect_plays_its_clip_once() {
  std::vector<uint8_t> full = mixed(effect("key"));
  TEST_ASSERT_TRUE(peak(full) > 60);  // 255 at volume 6: as loud as a syllable, about 0.6 of full
  TEST_ASSERT_TRUE(peak(full) <= 77);
  TEST_ASSERT_INT_WITHIN(2, peak(full) / 2, peak(mixed(effect("key", 128))));
  TEST_ASSERT_EQUAL(0, peak(mixed(effect("key", 255, 1000, 0))));  // muted
  size_t normal = lastSounding(mixed(effect("cloth")));
  size_t fast = lastSounding(mixed(effect("cloth", 255, 2000)));
  TEST_ASSERT_INT_WITHIN(int(normal / 50), int(normal / 2), int(fast));
}

// Your rule (VOICE.md §10): under a mumble, effects are half as loud, but
// the needs-you signal never is.
void test_a_mumble_turns_effects_down_but_not_the_ding() {
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("key"))) / 2, peak(mixed(effect("key"), true)));
  TEST_ASSERT_EQUAL(peak(mixed(effect("alertDing"))), peak(mixed(effect("alertDing"), true)));
  TEST_ASSERT_TRUE(voice::effectAlert(voice::effectIndex("alertKnock")));
  TEST_ASSERT_FALSE(voice::effectAlert(voice::effectIndex("trophyA")));
}

// Four at once; a fifth replaces the oldest. Stopping fades out in 4 ms.
void test_voices_and_stopping() {
  voice::Effects fx;
  for (int i = 0; i < voice::Effects::kVoices + 1; ++i) fx.play(effect("victoryPodium", 40));
  std::vector<uint8_t> out(2205, 128);
  fx.mix(out.data(), out.size(), false);
  TEST_ASSERT_TRUE(fx.playing());
  fx.stop();
  std::vector<uint8_t> tail(200, 128);
  fx.mix(tail.data(), tail.size(), false);
  TEST_ASSERT_FALSE(fx.playing());
  TEST_ASSERT_TRUE(lastSounding(tail) < size_t(voice::kOutRate * 4 / 1000));
}

// A working design's events play every loop, each kLeadMs ahead of its
// frame, and nothing is doubled.
void test_a_working_design_sounds_every_loop() {
  app::EffectTrack track;
  voice::Score sc = voice::score(int(Mood::kHappy), int(SceneState::kWorking), 0);
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kWorking, 0);
  Heard h = follow(track, Mood::kHappy, SceneState::kWorking, 0, 0, 3 * loop - app::EffectTrack::kLeadMs - 10);
  TEST_ASSERT_EQUAL(3 * sc.n, int(h.ev.size()));
  TEST_ASSERT_EQUAL(0, h.changes);
  for (size_t i = 0; i < h.ev.size(); ++i) {
    uint32_t due = uint32_t(i / sc.n) * loop + voice::fxEvent(sc.first + int(i % sc.n)).atMs;
    uint32_t sent = h.at[i] + app::EffectTrack::kLeadMs;
    if (h.at[i] == 0) TEST_ASSERT_TRUE(due < sent);  // due before the lead: at once
    else TEST_ASSERT_TRUE(sent > due && sent <= due + 10);  // within one 10 ms step
  }
}

// The cheer and needs you play their sounds on their first loop only.
void test_entry_designs_sound_once() {
  for (SceneState s : {SceneState::kTaskComplete, SceneState::kNeedsYou}) {
    app::EffectTrack track;
    voice::Score sc = voice::score(int(Mood::kProud), int(s), 1);
    uint32_t loop = render::loopMs(Mood::kProud, s, 1);
    Heard h = follow(track, Mood::kProud, s, 1, 0, 4 * loop);
    TEST_ASSERT_EQUAL(sc.n, int(h.ev.size()));
  }
}

// DEVICE.md §4: listening is silent, so nothing competes with your voice.
void test_listening_is_silent() {
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int v = 0; v < render::variants(SceneState::kListening); ++v) {
      app::EffectTrack track;
      TEST_ASSERT_TRUE(voice::score(m, int(SceneState::kListening), v).policy == voice::Policy::kSilent);
      Heard h = follow(track, Mood(m), SceneState::kListening, uint8_t(v), 0, 20000);
      TEST_ASSERT_EQUAL(0, int(h.ev.size()));
    }
  }
}

// Idle's sparse designs sound at most once every 45 s.
void test_idle_sounds_at_most_every_45_s() {
  app::EffectTrack track;
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kIdle, 1);
  voice::Score sc = voice::score(int(Mood::kHappy), int(SceneState::kIdle), 1);
  TEST_ASSERT_TRUE(sc.n > 0 && loop < 45000);
  Heard h = follow(track, Mood::kHappy, SceneState::kIdle, 1, 0, 100000);
  // The loops that sounded, by when they started: at least 45 s apart, and
  // the first loop that may sound does.
  std::vector<uint32_t> starts;
  for (size_t i = 0; i < h.at.size(); ++i) {
    uint32_t start = (h.at[i] + app::EffectTrack::kLeadMs) / loop * loop;
    if (starts.empty() || starts.back() != start) starts.push_back(start);
  }
  TEST_ASSERT_EQUAL(sc.n * int(starts.size()), int(h.ev.size()));
  TEST_ASSERT_TRUE(starts.size() >= 2);
  TEST_ASSERT_EQUAL_UINT32(0, starts[0]);
  for (size_t i = 1; i < starts.size(); ++i) {
    TEST_ASSERT_TRUE(starts[i] - starts[i - 1] >= 45000);
    TEST_ASSERT_TRUE(starts[i] - starts[i - 1] < 45000 + loop + app::EffectTrack::kLeadMs);
  }
}

// A new design stops the last one's sounds; a mood changing mid-loop picks
// its timeline up where the clock is, without replaying the loop so far.
void test_a_change_of_design_starts_where_its_clock_is() {
  app::EffectTrack track;
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kWorking, 0);
  follow(track, Mood::kHappy, SceneState::kWorking, 0, 0, loop / 2);
  Heard h = follow(track, Mood::kGrumpy, SceneState::kWorking, 0, loop / 2 + 10, loop - 200);
  TEST_ASSERT_EQUAL(1, h.changes);
  voice::Score g = voice::score(int(Mood::kGrumpy), int(SceneState::kWorking), 0);
  uint32_t gl = render::loopMs(Mood::kGrumpy, SceneState::kWorking, 0);
  int expect = 0;
  for (uint32_t start = 0; start < loop; start += gl)
    for (int i = 0; i < g.n; ++i) {
      uint32_t at = start + voice::fxEvent(g.first + i).atMs;
      expect += at >= loop / 2 + 10 && at < loop - 200 + app::EffectTrack::kLeadMs + 10;
    }
  TEST_ASSERT_TRUE(expect > 0);
  TEST_ASSERT_EQUAL(expect, int(h.ev.size()));
  // A test pattern silences it.
  voice::FxEvent out[app::EffectTrack::kMaxOut];
  bool changed;
  TEST_ASSERT_EQUAL(0, track.follow(nullptr, loop, out, changed));
  TEST_ASSERT_TRUE(changed);
}

// A stalled loop drops what's more than kLateMs behind, not plays a burst.
void test_a_stall_drops_late_events() {
  app::EffectTrack track;
  uint32_t loop = render::loopMs(Mood::kExcited, SceneState::kWorking, 0);
  voice::Score sc = voice::score(int(Mood::kExcited), int(SceneState::kWorking), 0);
  follow(track, Mood::kExcited, SceneState::kWorking, 0, 0, 0);
  render::SceneShow f = face(Mood::kExcited, SceneState::kWorking, 0, 2 * loop);
  voice::FxEvent out[app::EffectTrack::kMaxOut];
  bool changed;
  int n = track.follow(&f, 2 * loop, out, changed);
  int window = 0;
  for (int i = 0; i < sc.n; ++i) window += voice::fxEvent(sc.first + i).atMs < app::EffectTrack::kLeadMs;
  TEST_ASSERT_EQUAL(window, n);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_every_design_has_a_timeline);
  RUN_TEST(test_each_state_sounds_as_the_pack_says);
  RUN_TEST(test_an_effect_plays_its_clip_once);
  RUN_TEST(test_a_mumble_turns_effects_down_but_not_the_ding);
  RUN_TEST(test_voices_and_stopping);
  RUN_TEST(test_a_working_design_sounds_every_loop);
  RUN_TEST(test_entry_designs_sound_once);
  RUN_TEST(test_listening_is_silent);
  RUN_TEST(test_idle_sounds_at_most_every_45_s);
  RUN_TEST(test_a_change_of_design_starts_where_its_clock_is);
  RUN_TEST(test_a_stall_drops_late_events);
  return UNITY_END();
}
