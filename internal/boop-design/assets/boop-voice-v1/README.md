# Boop voice bank v1 — agent integration handoff

Updated 2026-09-29. **Recorded audition assets, not a production voice engine.**
Robot Minion 1 only: voice ID `rErOatUrNIU3vfNcLl6Z`, generation model `eleven_v4`.
This package sits beside the V4 animation bank; it does not change the app, firmware,
mood graph, generic harness, or approval rules. Publication is not listening approval.

## Start here: find an actual recording in seconds

Read [manifest.json](manifest.json) and [index.json](index.json), not every proposed
dictionary performance. The manifest lists **2,752 actual recordings** with
**8,196 unsigned 8-bit PCM WAV files** (2,722 original takes × three treatments,
plus 30 new **robot-soft-only** takes).
Original 16-bit renders and paid MP3 masters are preserved in local archives
outside this checkout, not included in the compact distribution.
Their hashes remain in the manifest for provenance and recording-slot deduplication.
The completed first pass has **2,702 slots: 2,682 newly generated + 20 reused pilot
takes**. Another 20 historical short-language takes are preserved outside that
first-pass slot count. Six superseded early Robot Minion experiments remain excluded.

All **387 entries** are represented. Words and nonverbals have one take per
compatible mood; phrases have one selected mood. The original design has **7,123 slots**:
2,702 completed and **4,421 deferred**. The supplemental swear batch adds 30 new
slots, giving **7,153 planned / 2,732 completed slots**, plus 20 historical takes.
Never fabricate
a path or silently substitute a mood when no suitable recorded take exists.

## Listen to the bank

From the repository root:

```sh
python3 -m http.server 4177 --bind 127.0.0.1 --directory internal/boop-design/assets/boop-voice-v1
```

Open <http://127.0.0.1:4177/review/>. No dependencies, API key or generation calls.
The continuous audition plays first-pass and supplemental clips with on-screen state/mood/keyword
labels. Filter into chapters, skip/replay, mark Keep/Rework and export the review JSON.
Adult expressions are off by default. Review marks stay in the browser and include
the exact master hash; they do not automatically change the package manifest.
The original first-pass audio totals 64.22 minutes (about 80 minutes with default gaps).
For the new takes: choose **Batch → NEW · 30 sad / wounded / whiny swears**,
**Texture → Soft circuit**, and enable **Include adult expressions**. Other textures
exclude unavailable takes; neither the player nor selector silently substitutes a profile.
This portable voice-only page does not depend on the original author's localhost
or audition checkout. Animation/SFX previews remain in the sibling V4 review bank.

| File/folder | Purpose |
| --- | --- |
| `manifest.json` | Recorded IDs, entry ID, intended mood, duration, review status, original script, voice/model, encoding, paths and SHA-256 hashes |
| `index.json` | Recorded IDs indexed by state, mood, intent and dictionary entry; cheap shortlist lookup |
| `dictionary.json` | 387 meanings, context guards, compatible moods, variation directions, audience/rarity and proposed pacing policy; no massive Cartesian matrix |
| `audio-pcm8/robot-soft/` | Recommended quiet electronic texture; 2,752 mono 8-bit/11.025 kHz WAVs |
| `audio-pcm8/original/` | Dry, quiet-level-matched 8-bit comparison; not untouched provider output |
| `audio-pcm8/robot-grain/` | More electronic alternative; same takes, not extra performances |
| `manifest.json → recordings[].master` | Archived paid-take identity/hash; not a playable path or a shipped file |
| `select.mjs` | Dependency-free host-side reference selector and assembly guard; see commands below |
| `tools/check.mjs` | Integrity, audio format/level, eligibility and assembly tests; writes exact storage report |
| `tools/compress.py` | Offline, resumable conversion from the verified local 16-bit archive; never calls ElevenLabs |
| `provenance.json` | Batch/model/processing provenance, with no credentials or account data |
| `storage-report.json` | Exact logical bytes, durations, category counts and recorded mood coverage |
| `plans/phase1.json` | Completed slot IDs mapped to actual recording IDs; includes reused pilot mappings |
| `plans/deferred.json` | Disjoint remaining 4,421 slots; not authorized for automatic generation |
| `plans/swear-expansion-v1.json` | 30 supplemental slots, scripts, seeds and acting intentions; disjoint from both old plans |
| `tools/swear_expansion.py` | Explicitly invoked, bounded batch generator and offline importer; private cache required |
| `review/` | Self-contained continuous audition; serve the package root as above |

All paths in the manifest are relative to **this directory**, not the repository
root. Stable clip IDs such as `new.d02` and `previous.heh` are identifiers, not
filenames to guess. Always resolve through the manifest.

## 1. Selection pipeline

1. **Host resolves facts.** Determine the current state, persistent mood, topic,
   event/request identity and truthful outcome. Prefer specific states (terminal,
   searching, testing, delegating) to generic tool_use. Unknown result → reply_ready,
   not success. A tool ending is not necessarily a task finishing.
2. **Silence/pacing gate.** Check mute, interruptions, pending alert policy,
   event deduplication and recent voice usage before consulting Jev. Asleep and
   no_app remain silent. Heartbeats and Boop's own actions must not create a speech loop.
3. **Intersect indexes.** `byState[state] ∩ byMood[mood]` gives a tiny actual-audio
   pool. Apply the entry's required fact, optional topic, explicit setting, rarity,
   review status, duration and recency. Do not substitute a different mood silently.
4. **Jev chooses an ID.** Offer silence plus at most eight eligible recordings with
   short meanings. Jev returns one offered ID; it does not invent text, filenames,
   emotional facts, API requests, or words. Vector search is unnecessary at this size;
   if added later it can rank only the already-safe shortlist. The reference offers
   one take per dictionary entry, so alternate recordings do not crowd out meanings.
   Recent take IDs let the host offer another take of an otherwise eligible entry.
5. **Revalidate before playback.** Reject stale decision snapshots, cleared requests,
   invalid choice IDs, changed context or an intervening higher-priority alert. Invalid
   answers become silence. Jev must never approve, deny or clear an agent permission.
6. **Play one whole take**, normally. Rarely join two compatible units as below.
   Use the animation clock and protected-cue windows, not independent timers.

Mood selection is a separate decision governed by the
[approved graph](../../boop-mood-spectrum-v2/HANDOVER.md). A voice selection must not
reset mood on a tool/state change or bypass graph traversal for more sound variety.

### Actual reference command

From the repository root:

```sh
node internal/boop-design/assets/boop-voice-v1/select.mjs --state starting --mood excited --facts task_started --audition
```

This offers `silence` and up to eight context-compatible meanings, including
`new.d02` (“Go”, 1.149 seconds). `new.d02` resolves
to `audio-pcm8/robot-soft/new.d02.wav`. The JSON output is built from this package, not
from invented example filenames.

```js
import {loadBank, choices, resolveChoice, assemble} from './select.mjs';
const bank = loadBank(); // cache once in the host
const context = {
  state: 'starting', mood: 'excited', facts: ['task_started'],
  recentTakeIds: [], recentEntryIds: [], recentFamilies: [], stale: false
};
const offered = choices(bank, context, {audition: true});
// Send Jev just {id, label, intent, mood, kind}; keep paths/durations in the host.
// Capture your own decision/event token alongside the offered set.
const picked = resolveChoice(offered, 'new.d02'); // substitute the validated Jev answer
const line = picked.id === 'silence' ? null : assemble(bank, [picked.id], context, {audition:true});
// line: whole-clip timing plan, not audio playback or a live tool invocation.
```

`choices` filters factual/mood eligibility and local recency lists; it does **not**
implement the live event adapter, persistent history, Jev call, hourly rate gate,
audio scheduler or device transfer. Keep those responsibilities explicit. The
generic harness must not gain voice-language logic; the Voice action/service owns it.

### Review is an explicit gate

Every take remains `unreviewed-by-ear` at export. For intentional local previews,
`--audition` includes those candidates. Without it the selector returns silence
until actual listening-approved takes have `reviewStatus: "approved"` in the
manifest (with approval recorded in your normal release review). Do not pass
`--audition` in a production loop to bypass review. Intended mood tags, especially
legacy editorial aliases, are not acoustically verified mood classifications.
Aliases such as `weary`, `amused`, `relieved` and `unspecified` do not silently map to
one of the 13 persistent moods; those older takes need explicit review/relabeling.

Short phrases, borrowed words and explicit expressions are design proposals beyond
the current production one-English-word contract in `plan/VOICE.md`. Short phrases
require `--phrases`; rare entries also require `--rare`; swears additionally require
`--explicit`. These switches permit selection, not a change to production policy.

## 2. Fact vocabulary

`facts` are **host-normalized evidence**, not sentences for Jev to infer as true.
Pass only facts justified by the actual adapter/event. Defaults must fail closed.

| Fact(s) | Required evidence / meaning |
| --- | --- |
| `task_started` | A new task/turn actually began; not just planning to start |
| `planning_active`, `work_active`, `terminal_active`, `tool_active` | Corresponding activity is current; an arbitrary Bash command does not reveal every subtask |
| `search_active`, `analysis_active`, `tests_active` | Reliable tool/type/topic mapping, not a guess from mood |
| `analysis_or_search` | Derived OR of current analysis/search evidence |
| `success_confirmed` | Verified successful outcome; `turn.end:done` alone is insufficient |
| `failure_confirmed` | Confirmed failure at the scope shown by the animation; tool error is not automatically terminal task failure |
| `tests_passed`, `fix_confirmed`, `insight_confirmed` | More specific verified results; do not infer these from a generic zero exit code |
| `retry_started` | A retry is underway, not merely suggested; include its current activity fact too when appropriate |
| `friction_observed` | Observed failed/blocked/retried operation, not assumed user annoyance |
| `pending_request` | A real unresolved approval/input request; request identity must be deduplicated |
| `wait_active`, `stopped_confirmed`, `reply_ready` | Actual wait, interruption/stop, or reply readiness |
| `delegation_started`, `helper_returned` | Positive lifecycle evidence; an end-only hook does not prove a new spawn |
| `device_poke`, `awake_idle` | Actual poke, or awake idle/listening; never infer human emotional intent from taps |
| `success_or_poke` | Derived OR used for a small delighted reaction |

Topic constraints are exact matches, e.g. Compile requires `topic: "build"`.
The selector does not auto-expand composite facts; the host supplies them alongside
their source facts. Unsupported or unavailable facts mean no corresponding candidate.

## 3. Vocabulary and performance rules

- **Word:** usually one recognizable anchor, e.g. Go / Done / Again.
- **Phrase:** a rare whole performance, e.g. Mamma mia / Tiny genius; never stitch
  it together from independently spoken words or surround it with two mumbles.
- **Nonverbal:** a purposeful questioning, effort, frustration, relief or delight
  gesture; not filler syllables for their own sake.
- One compatible mood per performance; one voice identity and one DSP texture per
  assembled line. Do not choose both original and robot-soft copies as “new takes.”
- Entry ID, repeatFamily and recording ID have separate cooldowns. Persist all three
  across restarts so spelling variants and alternate EQ do not evade repetition rules.
- The silence-first design's exact proposed defaults live in `dictionary.json.policy`:
  randomized routine cooldown, per-hour caps, rare/explicit cooldowns, history depth,
  maximum unit count and duration. These still need real-workday tuning, not blind
  adherence as if already proven. An empty shortlist stays silent.
- No promise of a month without recognizable repetition; mood variants can still
  sound similar. Do not invoke TTS automatically to fill deferred slots.

The thirteen mood directions are in `dictionary.json.moods`; dictionary entries
list compatible `moods`, `variants` and `variantCount`. A full planned matrix is
the union of entry.moods × entry.variants, not word × every animation. This avoids
recording a new voice file for every visual variation.

## 4. Assembly and animation timing

Default to one take. Optional two-part shapes are nonverbal→anchor or anchor→tail,
with complementary intent. Never concatenate two lexical phrases, two anchors,
different mood takes, different voice identities, or explicit insults at a person.
`assemble` demonstrates these guards and requires both IDs to remain eligible.

Preserve complete breath-delimited clips. The reference uses a 180 ms gap and a
2.8-second combined routine budget. Apply short 25 ms attack / 45 ms release fades
in the player, clamped to short clip lengths; do not overlap consonants. Do not
speed up or cut words to fit. Longer items such as `new.d20` (Mwahaha, about 2.93 s)
remain available for manual hero-beat auditions, not ordinary automatic selection.

Get the selected animation's actual score and `voiceWindow` from the V4 bank's
generated manifest/runtime, not hard-coded times copied from the earlier voice
viewer. New-scene windows are suggestions; retained legacy designs may lack them.
If no validated room exists, use silence or a deliberate post-scene hold. Keep
needs-you knock/ding, task-complete and failure cues clear. Duck only routine
material effects, never the signature alert. Do not repeat speech on each SVG loop.
No extra background music; let the soundscape breathe.

## 5. Encoding, playback and storage

Recommended playback assets: `audio-pcm8/robot-soft/*.wav` — **RIFF WAV, PCM
format tag 1, unsigned 8-bit, 11,025 Hz, mono**. One sample is one byte; 128 is
silence, 0 is the negative extreme, and 255 the positive extreme. This is reduced
precision/rate PCM, not an AAC bitstream, not signed int8 and not procedural SFX.
The sample rate must remain in the metadata; playing these bytes at 22.05 kHz
without resampling would double both pitch and speed.

The conversion matches the accepted preview: high-quality anti-aliased resampling
from the existing 16-bit treatment, then nearest-level 8-bit quantization, without
extra effects, gain boosts, pitch changes or added dither. Source PCM hashes and
measured output levels are in each file entry. Quantization/resampling can slightly
change peaks and RMS; the checker measures actual bytes with limits of .59 peak
and .073 RMS. Start playback quietly; digital limits do not prove acoustic safety.
Format approval does not approve every individual take by ear.

**Why not AAC?** The board has an 8-bit DAC and no PSRAM. Its current firmware
already uses 8-bit/11.025 kHz source samples and a 22.05 kHz DAC stream, but has no
AAC decoder. AAC can be supported through software, but adds codec/parser memory,
CPU work and startup-buffering decisions. PCM avoids that additional work. It does
not guarantee zero latency: the existing DAC pipeline has four 512-sample buffers,
about 93 ms of total capacity. Actual onset latency depends on queue occupancy,
SD reads, scheduling and prefetching; it has not been measured for this new bank.

The original **2,722 takes** occupy about **43 MB per treatment**, or **129 MB for
all three** audio alternatives—approximately 87.5% smaller than corresponding
16-bit WAVs. The 30 supplemental takes add only their robot-soft WAVs; see the
storage report for the current exact total. Do not assume every take has three profiles.
Deploy only the chosen treatment, normally robot-soft. Metadata is additional;
[storage-report.json](storage-report.json) gives exact file lengths. Do not put
the archived originals or unused comparisons on the SD card.

### Downstream device playback requirements — not implemented by this package

1. **SD storage and whole-clip lookup:** add an SD/file reader and map stable take
   IDs to paths or indexed offsets. The existing firmware plays small compiled-in
   syllable/word arrays; it does not load these WAVs or use the SD slot. Its old
   beat-based duration caps must not clip, accelerate or pitch-shift these full
   performances. This bank exceeds the board's 4 MB flash, so do not bake all of
   it into `voice.h`. Check SD/touch SPI bus ownership and pin routing against
   `plan/DEVICE.md` before adding SD support.
2. **Read the container correctly:** validate RIFF/WAVE and PCM format, walk chunks
   to find `fmt ` and `data`, and honor odd-chunk padding. Never feed WAV headers
   into the DAC or assume every future WAV has a 44-byte header. Reject a missing,
   truncated or incompatible file safely rather than playing garbage.
3. **Prefetch off the real-time audio task:** use a bounded ring/double buffer and
   cache the beginning of likely next clips. No full-file allocation, file open,
   blocking SD read or heap churn in the DAC feed loop. Keep feeding silence (128)
   during gaps or underflow; do not starve DMA. Prefetch is a latency strategy,
   not a measured latency guarantee.
4. **Resample/mix:** interpolate 11.025 kHz mono PCM to the existing fixed 22.05 kHz
   output. Widen and subtract 128 before gain, fades and mixing with SFX; saturate
   safely and re-bias to 128 for the unsigned DAC buffer. Preserve short start/end
   and cancellation fades, modest gain, and the protected notification cues.
5. **Synchronize:** schedule from the shared animation/audio timeline; account for
   queued output and do not repeat voice on every animation loop. Keep cancellation
   and stale-event checks. Alert sounds remain independently available.
6. **Verify on the board:** measure cold/warm onset and jitter, worst-case free heap,
   underflows and animation/Bluetooth responsiveness; check end-of-clip, interruption,
   missing SD/file behavior and real-speaker loudness. This release includes no such
   hardware measurements or firmware/protocol changes.

Normal desktop/browser WAV decoding already handles this format. The original paid
MP3 identity stays in `master.sha256`; `master.storage` explicitly says local archive
and has no path. Use `files[texture]`, never `master`, for runtime playback.

**Git history:** this is a normal follow-up commit at the owner's request, not a
history rewrite. The latest checkout/download is smaller, but old large blobs remain
in repository history. A fresh `--depth 1 --branch codex/boop-mood-spectrum-v4` clone
or a current-branch archive avoids fetching old revisions; existing full clones
will not automatically shrink. Do not force-push or garbage-collect others' history.

## 6. Validation and regeneration

No dependency install or API key needed:

```sh
node internal/boop-design/assets/boop-voice-v1/tools/check.mjs
node internal/boop-design/assets/boop-voice-v1/select.mjs --help
node internal/boop-design/assets/boop-voice-v1/select.mjs --state starting --mood excited --facts task_started --audition
```

Tests check every audio hash/format/level, index consistency, state/fact/mood/topic
guards, silence fallback, review and explicit gating, recency and composition
limits. They do not claim subjective listening quality or device compatibility.

The historical converter targets only the original 2,722-take bank, from the
verified **original 16-bit archive** (macOS `afconvert`, Python standard library).
It now refuses an expanded manifest to prevent dropping supplemental takes.
Its help remains available; do not run its old `--finalize` migration on this release:

```sh
python3 internal/boop-design/assets/boop-voice-v1/tools/compress.py --help
```

The converter validates all archived master/PCM hashes first, caches by source hash
and conversion recipe, and validates every output before finalization. Original
recording IDs, scripts, paid-take hashes, slot partition and review status are
preserved. `--finalize` removes only exact hash-verified archived originals from
the active package. Its archive path stays local and is not embedded in the export.
It makes **no API calls** and never reads `.env`, credentials or account logs.
The legacy pilot importer refuses to downgrade an expanded manifest, and the
phase-one importer refuses to overwrite this compact distribution with 16-bit files.
Do not generate new recordings as part of normal app startup.

Unit test the conversion boundaries with:
`python3 -m unittest discover -s internal/boop-design/assets/boop-voice-v1/tools -p 'test_*.py'`.

### Expand later without duplicate generation

Use `performanceId` as the stable recording-slot key, not a guessed filename or
script string. `plans/phase1.json` maps all completed slots to their actual recording
IDs, including the 20 reused pilot takes. `plans/deferred.json` is the disjoint
complement of the original 7,123-slot design. The supplemental plan adds 30 disjoint
slots; checks prove all three plans match the 7,153-slot dictionary. Before any
future paid request, subtract **all** manifest performance IDs from the requested
slot IDs. An existing saved recording is reused, never automatically regenerated.
Similar wording in two deliberately different performance slots is not evidence
that their acting is interchangeable.

New generation requires separate authorization and a budget. Journal the intended
slot/request before sending it; save and hash the returned master before marking
success. Never blindly retry a timeout or uncertain request: reconcile provider
history first. A Rework mark is not retry authorization. Make a separately named
replacement revision and preserve the prior master/approval hash. The author's
private account/request ledger is intentionally excluded from this public handover;
the published completed-slot manifest suffices to avoid regenerating this batch.

Publication was explicitly authorized for this asset package on the V4 branch.
It does not authorize a PR, merge, new paid generation, or production policy changes.

### Supplemental sad / wounded / whiny swears

Five existing entries (`explicit.shit`, `.fuck`, `.damn`, `.crap`, `.shiba`) each
add sad, wounded and whiny × contained/trailing. Keep `explicit: true`, adult
opt-in, `requires: failure_confirmed`, error/task_complete eligibility and the
never-at-the-person rule. A sad face alone is not evidence of failure. No
approval nudge swears. Shiba remains a user-proposed truncation, not a verified
Korean translation. All new takes are `unreviewed-by-ear`; listen before shipping.

Contained takes ask for small, quiet delivery; trailing takes add a sigh and a
settling tail. Emotion tags are requests, not guarantees. Sad asks for deflation,
wounded a hushed wince, whiny soft self-pity rather than angry emphasis. There is
no new pitch effect or extra DSP: the accepted robot-soft chain and phase1 shared
normalization feed the same `tools/compress.py` resampling/quantization helpers.
The 2.8-second routine guard still applies; longer takes remain manual auditions.

`tools/swear_expansion.py plan` is offline. `import --cache /absolute/private/cache`
is offline, verifies the frozen plan/audio hashes, and refuses conflicting existing
performances. `generate` requires explicit `--execute`, an external `--cache` and
`--audition-tools` pointing to the existing author's audition pipeline (`audition.py`).
It is not a self-contained TTS client for fresh clones. Generation uses a private
pre-request journal and 2,500-credit stop guard, skips saved audio, never retries
uncertain paid requests, and keeps all MP3/intermediates outside Git. The completed
30-slot request text totals 851 characters; actual billing is checked separately.
No startup/background code invokes it. Never rerun merely because a take is disliked.

The optional grudging-good-news batch is **not generated**. “Fine.” and “Hmph, okay.”
can be acknowledgement with an appropriate event guard; “Finally.” and “About time.”
need an observed resolution/delay context. Do not label all four unconditional
`celebrate` clips: mood does not establish success and the selector fails closed
when a required fact is absent. Define those meanings before adding recordings.
