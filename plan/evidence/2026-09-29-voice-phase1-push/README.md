# First-pass voice dictionary publication checks

Date: 2026-09-29. Scope: design asset handover on
`codex/boop-mood-spectrum-v4`; no app, firmware or production behavior changes.

The user explicitly requested publication to the mood-v4 branch. This does not
approve individual recordings by ear or authorize another generation batch.

## Checks run

- Offline `tools/import-phase1.mjs --source <audition-checkout>` imported 2,682
  new takes while retaining all 40 historical takes. A second import added zero
  takes, demonstrating resumable import without duplicate recordings.
- `node internal/boop-design/assets/boop-voice-v1/tools/check.mjs` passed:
  2,722 unique recordings, 8,166 WAV files, 2,722 MP3 masters, valid hashes,
  audio formats and levels, index references and selector fixtures. Production
  selection retains its per-clip approval gate; audition is explicitly opt-in.
- The immutable first-pass plan has 2,702 slots (2,682 new plus 20 reused
  pilot slots). Its 4,421 deferred slots are disjoint; together they cover all
  7,123 planned slots. Deferred generation remains unauthorized.
- The portable review manifest resolves all 2,702 slots to their packaged
  recording IDs and profiles, including reused pilot IDs.
- Served the package root on loopback port 4180. In-app browser loaded
  `/review/`, displayed 2,702 ready and 2,687 non-explicit clips, and continuous
  playback advanced from clip 1 to clip 9 before pausing. No missing-file error
  appeared. This is a playback integration check, not listening approval.
- Inspected the export for private accounting/request ledgers, environment
  files, absolute local paths and credential-like strings. None were exported;
  the checker itself contains an intentional absolute-path rejection pattern.
  No symlinks or files exceeding GitHub's per-file size limit were included.
- `git diff --check` passed; `cmp CLAUDE.md AGENTS.md` was silent.

## Storage and limitations

See the package's generated [storage report](../../../internal/boop-design/assets/boop-voice-v1/storage-report.json)
for exact sizes: approximately 1.10 GB including masters, all three DSP
profiles and metadata; one runtime WAV profile is approximately 342 MB.
Only one profile is needed on the device.

Recordings remain `unreviewed-by-ear`. Intended emotion tags are not guarantees
of perceived delivery. This publication neither claims every clip sounds good
nor enables automatic playback in the shipped app. No paid generation ran
during packaging, and no API key is needed to audition the package.
