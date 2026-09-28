// The face's sound effects (plan/VOICE.md §10): the bank's clips and
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
Heard follow(app::EffectTrack& track, Mood m, SceneState s, uint8_t variant, uint32_t from, uint32_t until) {
  Heard h;
  for (uint32_t t = from; t <= until; t += 10) {
    render::SceneShow f = face(m, s, variant, t);
    voice::FxEvent out[app::EffectTrack::kMaxOut];
    bool changed;
    int n = track.follow(&f, out, changed);
    h.changes += changed;
    for (int i = 0; i < n; ++i) h.at.push_back(t), h.ev.push_back(out[i]);
  }
  return h;
}

}  // namespace

// The events one loop of a design plays (VOICE.md §10): list n % kLoops of
// a routine design's baked picks.
std::vector<voice::FxEvent> loopEvents(const voice::Score& sc, uint32_t loop) {
  voice::Events l = voice::events(sc, loop);
  std::vector<voice::FxEvent> out;
  for (int i = 0; i < l.n; ++i) out.push_back(voice::fxEvent(l.first + i));
  return out;
}

bool same(const std::vector<voice::FxEvent>& a, const std::vector<voice::FxEvent>& b) {
  if (a.size() != b.size()) return false;
  for (size_t i = 0; i < a.size(); ++i)
    if (a[i].atMs != b[i].atMs || a[i].clip != b[i].clip || a[i].gain != b[i].gain) return false;
  return true;
}

bool guarded(int s) {
  return s == int(SceneState::kNeedsYou) || s == int(SceneState::kTaskComplete) || s == int(SceneState::kError);
}

// Every design the device draws has a timeline, with clips it has: the
// bank's 46 that the timelines use and its 3 newer ones (brake,
// failedAttempt and the new moods' knock).
void test_every_design_has_a_timeline() {
  TEST_ASSERT_EQUAL(49, voice::effectCount());
  for (const char* name : {"brake", "failedAttempt", "knock", "alertDing", "trophyA"}) {
    TEST_ASSERT_TRUE_MESSAGE(voice::effectIndex(name) >= 0, name);
  }
  // About 180 KB was budgeted (VOICE.md §10).
  TEST_ASSERT_TRUE(voice::effectsBytes() < 180u * 1024);
  for (int m = 0; m < int(Mood::kCount); ++m)
    for (int s = 0; s < int(SceneState::kCount); ++s)
      for (int v = 0; v < render::variants(Mood(m), SceneState(s)); ++v) {
        voice::Score sc = voice::score(m, s, v);
        TEST_ASSERT_TRUE(sc.lists == 1 || sc.lists == voice::kLoops);
        uint32_t loop = render::loopMs(Mood(m), SceneState(s), v);
        TEST_ASSERT_TRUE(sc.voiceMs > 0 && sc.voiceMs < 8000);
        for (uint32_t n = 0; n < uint32_t(voice::kLoops); ++n) {
          uint16_t prev = 0;
          for (const voice::FxEvent& e : loopEvents(sc, n)) {
            TEST_ASSERT_TRUE(e.clip < voice::effectCount());
            TEST_ASSERT_TRUE(e.atMs >= prev);  // by time
            TEST_ASSERT_TRUE(e.atMs < loop);   // inside the design's loop
            TEST_ASSERT_TRUE(e.gain > 0);
            TEST_ASSERT_TRUE(e.pitch >= 900 && e.pitch <= 1150);
            prev = e.atMs;
          }
        }
      }
  // A variation out of range takes the first, as the screen does; a mood
  // the device doesn't know is silent.
  voice::Score a = voice::score(0, int(SceneState::kWorking), 0);
  voice::Score b = voice::score(0, int(SceneState::kWorking), 9);
  TEST_ASSERT_EQUAL(a.loop0, b.loop0);
  TEST_ASSERT_EQUAL(0, voice::events(voice::score(int(Mood::kCount), 0, 0), 0).n);
}

// The bank's voice-first mix, by state (VOICE.md §10): the quiet states
// are silent; needs you's knocks end in the ding, and it, the finish and
// an error play on their first loop only and never duck under a mumble;
// routine designs sound a few of their contacts, picked afresh each loop.
void test_each_state_sounds_as_the_bank_says() {
  int working = 0, varied = 0;
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int s = 0; s < int(SceneState::kCount); ++s) {
      for (int v = 0; v < render::variants(Mood(m), SceneState(s)); ++v) {
        voice::Score sc = voice::score(m, s, v);
        TEST_ASSERT_EQUAL(!guarded(s), sc.duck);
        switch (SceneState(s)) {
          case SceneState::kIdle:
          case SceneState::kAsleep:
          case SceneState::kNoApp:
          case SceneState::kListening:
          case SceneState::kWaiting:
            TEST_ASSERT_TRUE(sc.policy == voice::Policy::kSilent);
            break;
          case SceneState::kNeedsYou: {
            TEST_ASSERT_TRUE(sc.policy == voice::Policy::kEntry);
            bool ding = false;  // every needs-you performance ends in the ding
            for (const voice::FxEvent& e : loopEvents(sc, 0)) ding |= e.clip == voice::effectIndex("alertDing");
            TEST_ASSERT_TRUE(ding);
            break;
          }
          case SceneState::kTaskComplete:
          case SceneState::kError:
            TEST_ASSERT_TRUE(sc.policy == voice::Policy::kEntry);
            TEST_ASSERT_TRUE(voice::events(sc, 0).n > 0);
            break;
          case SceneState::kWorking: {
            TEST_ASSERT_TRUE(sc.policy == voice::Policy::kLoop || sc.policy == voice::Policy::kSparse);
            TEST_ASSERT_EQUAL(voice::kLoops, sc.lists);
            ++working;
            bool differ = false;
            for (uint32_t n = 0; n < uint32_t(voice::kLoops); ++n) {
              int k = voice::events(sc, n).n;
              TEST_ASSERT_TRUE(k >= 1 && k <= 8);  // thinned: at most four gestures a loop
              differ |= !same(loopEvents(sc, n), loopEvents(sc, 0));
            }
            varied += differ;
            break;
          }
          default: break;
        }
      }
    }
  }
  TEST_ASSERT_EQUAL(working, varied);  // no working design sounds the same every loop
  // A failed finish never plays a trophy.
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int v = 0; v < render::variants(Mood(m), SceneState::kTaskComplete); ++v) {
      if (render::variantOutcome(Mood(m), SceneState::kTaskComplete, v) != render::Outcome::kFailure) continue;
      for (const voice::FxEvent& e : loopEvents(voice::score(m, int(SceneState::kTaskComplete), v), 0)) {
        TEST_ASSERT_FALSE(std::strncmp(voice::effectName(e.clip), "trophy", 6) == 0);
      }
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

// VOICE.md §10: under a mumble, effects are a quarter as loud, the bank's
// level, but needs you's, the finish's and an error's never are: the design
// decides, not the clip.
void test_a_mumble_turns_effects_down_but_not_the_attention_cues() {
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("key"))) / 4, peak(mixed(effect("key"), true)));
  voice::Effect ding = effect("alertDing");
  ding.duck = false;
  TEST_ASSERT_EQUAL(peak(mixed(ding)), peak(mixed(ding, true)));
  TEST_ASSERT_INT_WITHIN(2, peak(mixed(effect("alertDing"))) / 4, peak(mixed(effect("alertDing"), true)));
  // The track hands each event its design's rule.
  for (SceneState s : {SceneState::kNeedsYou, SceneState::kWorking}) {
    app::EffectTrack track;
    Heard h = follow(track, Mood::kCalm, s, 0, 0, 6000);
    TEST_ASSERT_TRUE(h.ev.size() > 0);
    for (const voice::FxEvent& e : h.ev) TEST_ASSERT_EQUAL(s != SceneState::kNeedsYou, e.duck);
  }
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

// A working design sounds every loop, each loop its own few contacts (the
// bank's picks for that loop), each kLeadMs ahead of its frame, and nothing
// is doubled; after kLoops loops the picks come round again.
void test_a_working_design_sounds_every_loop() {
  app::EffectTrack track;
  voice::Score sc = voice::score(int(Mood::kHappy), int(SceneState::kWorking), 0);
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kWorking, 0);
  const uint32_t loops = voice::kLoops + 2;
  Heard h = follow(track, Mood::kHappy, SceneState::kWorking, 0, 0, loops * loop - app::EffectTrack::kLeadMs - 10);
  std::vector<uint32_t> due;
  for (uint32_t n = 0; n < loops; ++n) {
    for (const voice::FxEvent& e : loopEvents(sc, n)) due.push_back(n * loop + e.atMs);
  }
  TEST_ASSERT_EQUAL(int(due.size()), int(h.ev.size()));
  TEST_ASSERT_EQUAL(0, h.changes);
  for (size_t i = 0; i < h.ev.size(); ++i) {
    uint32_t sent = h.at[i] + app::EffectTrack::kLeadMs;
    if (h.at[i] == 0) TEST_ASSERT_TRUE(due[i] < sent);  // due before the lead: at once
    else TEST_ASSERT_TRUE(sent > due[i] && sent <= due[i] + 10);  // within one 10 ms step
  }
  TEST_ASSERT_TRUE(same(loopEvents(sc, voice::kLoops), loopEvents(sc, 0)));
  TEST_ASSERT_FALSE(same(loopEvents(sc, 1), loopEvents(sc, 0)) && same(loopEvents(sc, 2), loopEvents(sc, 0)));
}

// The finish, needs you, an error and the other one-shots play their sounds
// on their first loop only.
void test_entry_designs_sound_once() {
  for (Mood m : {Mood::kProud, Mood::kWounded}) {
    for (SceneState s : {SceneState::kTaskComplete, SceneState::kNeedsYou, SceneState::kError, SceneState::kPoked}) {
      app::EffectTrack track;
      voice::Score sc = voice::score(int(m), int(s), 1);
      TEST_ASSERT_TRUE(sc.policy == voice::Policy::kEntry);
      uint32_t loop = render::loopMs(m, s, 1);
      Heard h = follow(track, m, s, 1, 0, 4 * loop);
      TEST_ASSERT_EQUAL(voice::events(sc, 0).n, int(h.ev.size()));
    }
  }
}

// DEVICE.md §4: listening is silent, so nothing competes with your voice.
void test_listening_is_silent() {
  for (int m = 0; m < int(Mood::kCount); ++m) {
    for (int v = 0; v < render::variants(Mood(m), SceneState::kListening); ++v) {
      app::EffectTrack track;
      TEST_ASSERT_TRUE(voice::score(m, int(SceneState::kListening), v).policy == voice::Policy::kSilent);
      Heard h = follow(track, Mood(m), SceneState::kListening, uint8_t(v), 0, 20000);
      TEST_ASSERT_EQUAL(0, int(h.ev.size()));
    }
  }
}

// A short busy loop sounds every other loop, counted in loops from the
// design's start as the bank's player counts them (score.mjs
// cycleHasSound), not by the clock; idle is silent.
void test_a_short_loop_sounds_every_other_loop() {
  app::EffectTrack track;
  voice::Score sc = voice::score(int(Mood::kExcited), int(SceneState::kWorking), 0);
  uint32_t loop = render::loopMs(Mood::kExcited, SceneState::kWorking, 0);
  TEST_ASSERT_TRUE(sc.policy == voice::Policy::kSparse);
  TEST_ASSERT_EQUAL(2, sc.every);
  TEST_ASSERT_TRUE(loop < 3500);
  Heard h = follow(track, Mood::kExcited, SceneState::kWorking, 0, 0, 12 * loop - app::EffectTrack::kLeadMs - 10);
  size_t k = 0;
  for (uint32_t n = 0; n < 12; ++n) {
    std::vector<voice::FxEvent> want = n % 2 ? std::vector<voice::FxEvent>{} : loopEvents(sc, n);
    for (const voice::FxEvent& e : want) {
      TEST_ASSERT_TRUE(k < h.ev.size());
      TEST_ASSERT_EQUAL(e.atMs, h.ev[k].atMs);
      TEST_ASSERT_EQUAL((h.at[k] + app::EffectTrack::kLeadMs) / loop, n);
      ++k;
    }
  }
  TEST_ASSERT_EQUAL(int(k), int(h.ev.size()));
  for (Mood m : {Mood::kHappy, Mood::kCalm}) {
    app::EffectTrack quiet;
    TEST_ASSERT_EQUAL(0, int(follow(quiet, m, SceneState::kIdle, 1, 0, 60000).ev.size()));
  }
}

// A new design stops the last one's sounds; a mood changing mid-loop picks
// its timeline up where the clock is, without replaying the loop so far.
void test_a_change_of_design_starts_where_its_clock_is() {
  app::EffectTrack track;
  uint32_t loop = render::loopMs(Mood::kHappy, SceneState::kWorking, 0);
  follow(track, Mood::kHappy, SceneState::kWorking, 0, 0, loop / 2);
  Heard h = follow(track, Mood::kProud, SceneState::kWorking, 0, loop / 2 + 10, loop - 200);
  TEST_ASSERT_EQUAL(1, h.changes);
  voice::Score g = voice::score(int(Mood::kProud), int(SceneState::kWorking), 0);
  uint32_t gl = render::loopMs(Mood::kProud, SceneState::kWorking, 0);
  int expect = 0;
  for (uint32_t start = 0, n = 0; start < loop; start += gl, ++n) {
    if (g.policy == voice::Policy::kSparse && n % g.every) continue;
    for (const voice::FxEvent& e : loopEvents(g, n)) {
      uint32_t at = start + e.atMs;
      expect += at >= loop / 2 + 10 && at < loop - 200 + app::EffectTrack::kLeadMs + 10;
    }
  }
  TEST_ASSERT_TRUE(expect > 0);
  TEST_ASSERT_EQUAL(expect, int(h.ev.size()));
  // A test pattern silences it.
  voice::FxEvent out[app::EffectTrack::kMaxOut];
  bool changed;
  TEST_ASSERT_EQUAL(0, track.follow(nullptr, out, changed));
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
  int n = track.follow(&f, out, changed);
  int window = 0;
  for (const voice::FxEvent& e : loopEvents(sc, 2)) window += e.atMs < app::EffectTrack::kLeadMs;
  TEST_ASSERT_EQUAL(window, n);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_every_design_has_a_timeline);
  RUN_TEST(test_each_state_sounds_as_the_bank_says);
  RUN_TEST(test_an_effect_plays_its_clip_once);
  RUN_TEST(test_a_mumble_turns_effects_down_but_not_the_attention_cues);
  RUN_TEST(test_voices_and_stopping);
  RUN_TEST(test_a_working_design_sounds_every_loop);
  RUN_TEST(test_entry_designs_sound_once);
  RUN_TEST(test_listening_is_silent);
  RUN_TEST(test_a_short_loop_sounds_every_other_loop);
  RUN_TEST(test_a_change_of_design_starts_where_its_clock_is);
  RUN_TEST(test_a_stall_drops_late_events);
  return UNITY_END();
}
