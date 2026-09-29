# Supplemental quiet swears — 2026-09-29

Scope: design voice bank only, on `codex/boop-mood-spectrum-v4`. No app, firmware,
SD loader, production policy, mood graph or approval behavior changes.

## Result

- Five existing explicit entries × sad/wounded/whiny × contained/trailing = 30.
- Robot Minion 1, `eleven_v4`; only robot-soft WAVs added.
- 763,368 audio bytes, 69.12 seconds total. All unsigned PCM8 mono 11,025 Hz.
- Full bank now 2,752 paid takes / 8,196 distributed WAVs. Default soft profile:
  43,663,808 bytes. No MP3 masters, dry or grain copies added for this batch.
- 30 disjoint new slot IDs; original 2,702 completed / 4,421 deferred partition
  unchanged. Dictionary now 7,153 planned slots / 2,732 completed slot IDs.
- All original 2,722 manifest recording objects compared equal to the parent
  commit; their audio hashes pass the full checker. Frozen old plans unchanged.
- Every new take remains `unreviewed-by-ear`; no native-speaker or owner listening
  approval inferred. No claim that generated delivery perfectly matches intent.
- Six trailing takes exceed 2.8 seconds and remain in audition, excluded by the
  existing routine-duration guard. No cropping or time stretching performed.

## Checks

Commands from repository root:

```sh
node internal/boop-design/assets/boop-voice-v1/tools/check.mjs
python3 -m unittest discover -s internal/boop-design/assets/boop-voice-v1/tools -p 'test_*.py'
git diff --check
cmp CLAUDE.md AGENTS.md
```

The independent Node checker reads every WAV, verifies hashes, format, duration,
sample levels, exact index and review paths. Supplemental tests exercise absent
failure evidence, adult opt-in, needs_you exclusion, review gating, and missing
original/grain profiles. The dictionary's complete mood × variant set equals
the disjoint union of all three plans. Four Python tests cover quantization,
source preservation, archive containment and expanded-bank migration refusal.

Browser QA at `/assets/boop-voice-v1/review/`:

- New batch selected, adult switch off: zero clips.
- Adult switch on, soft texture: 30 clips; wounded filter: 10 clips.
- Original texture: zero clips, no missing-file fallback.
- Returned to robot-soft; new wounded Crap WAV decoded with duration 1.645714 s,
  no media error. Continuous queue progressed to the next labelled clips.
- Paused and left the full new-batch queue ready for user review, no autoplay.

Generation was journaled before requests; a read-only subscription check returned
429 after 18 saved takes. Resuming reused those masters and paced the remaining
requests. No uncertain paid requests were retried. Accounting/request ledgers and
masters stay in the external private archive, never in this commit.

No on-device acoustic, latency or SD tests performed. No new cultural expressions
or optional grudging-good-news recordings are included in this batch.
