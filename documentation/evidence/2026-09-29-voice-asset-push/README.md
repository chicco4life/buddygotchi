# Voice asset publication checks

2026-09-29. User explicitly requested branch verification, an agent voice-selection
README, an asset-folder push, and actual recording/storage counts.

## Branch and scope

The audition checkout is on local `main` at `3b94994`, behind origin/main, with
uncommitted review work. It was not switched, reset, pulled into, staged or committed.
The existing clean worktree for `codex/boop-mood-spectrum-v4` was used instead. Its
starting commit is `72ca30d`, based on current origin/main `7059294`; both
`git log HEAD..main` and `git log HEAD..origin/main` were empty after fetch.

Only `internal/boop-design/assets/boop-voice-v1/`, its parent navigation documentation,
`internal/README.md`, `plan/VERIFICATION.md` and this evidence file belong to this
publication. No PR, merge, new paid generation, app, firmware, voice protocol,
animation runtime or mood-graph changes are authorized or made.

## Recorded inventory and package boundaries

Forty distinct saved MP3 masters: twenty from robot-language-v2 and twenty from
robot-dictionary-v1. Three local DSP WAV profiles per take, 120 WAV files. All use
the selected Robot Minion voice; the six early Robot Minion experiments, other
voices and decoded intermediates remain only in the original audition checkout.
The 387-entry dictionary and 7,123 proposed performance slots are not recorded audio.

Each processed WAV is mono PCM16 at 44,100 Hz. Total distinct recording duration:
58.488163 seconds. Each 40-file profile is 5,160,416 bytes; all 120 WAVs total
15,481,248 bytes. Original MP3 masters total 954,270 bytes. The package's
`storage-report.json` is the authoritative whole-folder size, including documentation,
index, compact dictionary, selector/tests, provenance and the report itself.

Importer copies an explicit allowlist, verifies original master hashes and retains
relative filenames. No environment files, API keys, account counters, raw request
ledgers, execution logs or workstation paths appear in generated manifests.

## Offline checks

- `node internal/boop-design/assets/boop-voice-v1/tools/check.mjs`: passed.
  All 160 audio files verified by SHA-256; 40 master hashes are distinct; WAV header,
  sample count, duration and level checks passed. Peak ≤ .551, RMS ≤ .0701.
- Index reconstructed from dictionary and recordings matches exactly.
- Selector tests: strict mood/state/fact/topic eligibility; review gate;
  explicit/rare/phrase controls; silence for invalid/stale/missing evidence; no
  success word on failure; recent-take/family exclusion; one option per meaning;
  maximum eight candidates plus silence; invalid Jev choice falls back to silence.
- Assembly: real happy Phew→Yatta pair fits, duplicate anchors are rejected,
  longer Phew→Finish pair and Mwahaha routine take are rejected by duration budget.
- CLI starting/excited/task_started fixture offers silence and new.d02.
- `node internal/boop-design/boop-mood-spectrum-v2/validate.mjs`: passed, 13 moods,
  98 directed edges, ordinary strong connectivity, maximum nine choices with hold.
- `cmp CLAUDE.md AGENTS.md` and `git diff --check`: passed.

No subjective listening or hardware integration is claimed. Every exported take
remains `unreviewed-by-ear`; explicit audition mode is needed to select it until
listening approval is recorded. These tests do not contact ElevenLabs or Jev.
