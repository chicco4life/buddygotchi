# F5: Voice on the device — evidence (2026-09-26)

## What was built

- `tools/voicegen/voicegen.py`: macOS `say` → `afconvert` → trim, pitch up,
  saturate, normalise → 8-bit unsigned at 11.025 kHz →
  `firmware/assets/voice.h`. The syllable set and vocabulary are read from
  `app/BoopKit/Voice/Sounds.swift`. 64 syllables (Italian voice, 84–163 ms,
  90 KB) and 40 words (English voice, 125–481 ms, 136 KB): 226 KB against a
  360 KB budget. Two runs give byte-identical output (version `4ece01b8548c`).
- `firmware/src/voice/player.{h,cpp}`: the player. It resamples each clip
  to 22.05 kHz for pitch and tempo, with one beat per syllable and two for
  the word, and the tune, ±5% pitch and ±10% timing jitter (kept within
  pairs of beats). It follows volume, and plays the chirp and jingle cues.
  Pure C++, so it builds on `native`.
- `firmware/src/board/audio.{h,cpp}`: a task on core 0 streams the player
  into ESP-IDF's continuous DAC on GPIO26 and switches the amp (GPIO4,
  active low) on only while something plays.
- Device core: `moment.say` → `voice::Line` (syllable indices, word, `at`,
  tune, `ms`, mood pitch, volume). Needs you, quiet, focus and volume 0
  keep it silent. A new moment (a tap's wiggle, too) hushes a line. Cues
  follow `sfx`. `dbg.state` gains `audio.out`, and `dbg.ping` gains `voice`.
- `boopctl voice`: the L2 check.

## Checks

| Check | Result |
| --- | --- |
| L0: resampler and player tests (`test_voice`, 10) and device voice tests (3 in `test_device`) | Pass; `make fw-test` 74/74 |
| L2: audio timeline vs `say` (`boopctl voice --count 2`: 32 lines from the Mac's real Voice, 8 feelings, with and without a word) | 32/32. Syllable count and word match; `out_ms` within 1 ms of beats × `ms`; the DAC's measured duration is within 0.4% (the limit is 10%); the amp is on during each line. See `voice-l2.txt` |
| Mute (volume 0) | The mouth moves, no line plays, the amp stays off |
| App slot at least 15% free | 1,094,283 of 1,966,080 bytes (55.7%), so 44% free |
| Heap | 73 KB free after start-up (it was 84 KB before F5); the 60 KB target holds |
| Regression: `boopctl sim` | 10 scenarios, 0 expect failures, 0 changed pictures |
| Regression: `boopctl run` on the board | 10 scenarios, 0 expect failures, 0 pictures differ from the simulator |
| Regression: `boopctl perf --motion` (15 s) | fps min 44, mean 56.8, no reset |
| `boopctl soak --minutes 5` (random traffic with mumbles) | No reset, no heap drift (min 72.5 KB), final screen face; 0 DAC errors afterwards. See `soak-5min.json` |
| `make test` (Swift) | 163/163 |
| Hearing it | **Not done**: there's no speaker (DEVICE.md §3). It's in the morning checklist once one is attached |

Webcam: F5 changes nothing on screen, and the milestone has no L3 item, so
no clip was taken.

## Found on the way

The first version enabled the DAC per line and wrote a 110-sample lead-in.
The DMA played one buffer, ran dry, and from then on every
`dac_continuous_write` timed out (`ESP_ERR_TIMEOUT`; the DMA interrupts had
fired: `on_convert_done` 1, `on_stop` 2). Now the task writes a full
512-sample buffer without a break, with silence when idle, so the DMA never
runs dry. A write that still times out restarts the DAC and is counted in
`audio.out.errors`. This is recorded in DEVICE.md §6 and the decision log.

## Not checked

- The sound itself: whether the syllables read as Minion-like, whether the
  words are clear, and the loudness at volume 6. This needs a speaker and
  ears.
- `wall_ms` is the DAC's pace measured with `esp_timer` across the line's
  chunks. A sync write returns only when the DMA frees a buffer, so it
  measures real playback, but only to within one chunk (23 ms) before
  scaling to the line's samples.
