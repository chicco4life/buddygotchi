# Compact 8-bit voice distribution

Date: 2026-09-29. Scope: design voice assets and handover, not production
firmware integration. Owner approved unsigned 8-bit PCM after the AAC/PCM audition
and requested a normal commit/push to `codex/boop-mood-spectrum-v4`.

## Checks performed

- Verified all 10,888 original audio files (8,166 16-bit WAVs and 2,722 paid MP3
  masters) against manifest hashes in a local archive outside the repository.
- Converted all three profiles using high-quality 11.025 kHz mono resampling
  and round-to-nearest unsigned 8-bit quantization. No paid generation, additional
  effects, gain boost, pitch shift, dither or altered performances.
- All **40 accepted preview PCM8 renders are byte-identical** to the corresponding
  release robot-soft files. The default treatment is still robot-soft.
- `node internal/boop-design/assets/boop-voice-v1/tools/check.mjs` passed. It
  independently verifies file hashes, actual WAV headers/samples, 8-bit precision,
  11.025 kHz mono rate, block alignment, duration, peak/RMS, index consistency,
  2,702/4,421 slot partition, review paths and selection/assembly guards.
- Peak inspection: four grain-treatment files exceeded the initial conservative
  0.57 threshold after resampling; measured values were 0.5703125 (three) and
  0.578125 (one), not clipping. The documented/checker ceiling is 0.59; the recipe
  was not changed or renormalized. Bank maximum RMS is approximately 0.07003.
- Three Python unit tests passed: signed-to-unsigned sample mapping including
  silence and extrema, original preservation, wrong-rate rejection, and archive
  path rejection inside the repository.
- Compared all 2,722 records with the archive: take IDs, paid-take hashes,
  generation metadata, scripts, intended moods, original durations and review
  statuses unchanged. Index, dictionary and both slot plans are byte-identical.
- Repeated finalization reused all converted files, moved zero additional AAC
  files and produced an identical manifest SHA-256; no duplicate generation.
- Browser loaded all 2,702 first-pass entries at the portable review URL. The
  default non-explicit queue had 2,687 entries; playback advanced from entry 9
  to 26. Alternate grain and dry textures played successfully, then the player
  was paused on robot-soft. No browser warnings/errors appeared. This is an integration
  check, not individual listening approval or a device benchmark.
- `git diff --check` passed and `cmp CLAUDE.md AGENTS.md` was silent.

## Storage and recoverability

See the exact [storage report](../../../internal/boop-design/assets/boop-voice-v1/storage-report.json).
Each profile is **42,900,440 bytes**; all three total **128,701,320 bytes**.
The full folder is approximately 146 MB including metadata/code, versus about
1.10 GB previously. Original WAVs and MP3s were removed from the active package
only after archive hash verification. Interrupted AAC experiment files were
also moved into that local archive, not published or destroyed.

This is a normal follow-up commit: old large audio remains in Git history.
The smaller checkout is not a claim that existing clones or GitHub's historical
object storage shrink. Main and firmware are untouched.

## Playback boundary

The board's existing unsigned 8-bit sample representation is compatible, but
the current compiled-in syllable player does not load this dictionary from SD.
The handoff requires chunk-aware WAV parsing, SD bus integration, bounded
prefetch/ring buffering off the real-time task, 11.025-to-22.05 kHz resampling,
wide intermediate mixing, clipping/fades, whole-clip durations and event timing.
Existing output buffering is not zero-latency. No flashing, Bluetooth, speaker
recording, SD playback or onset-latency measurement was performed.
