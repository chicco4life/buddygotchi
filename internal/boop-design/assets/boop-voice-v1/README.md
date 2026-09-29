# Boop voice bank v1 — agent integration handoff

Updated 2026-09-29. **Recorded audition assets, not a production voice engine.**
Robot Minion 1 only: voice ID `rErOatUrNIU3vfNcLl6Z`, generation model `eleven_v4`.
This package sits beside the V4 animation bank; it does not change the app, firmware,
mood graph, generic harness, or approval rules. Publication is not listening approval.

## Start here: find an actual recording in seconds

Read [manifest.json](manifest.json) and [index.json](index.json), not every proposed
dictionary performance. The manifest lists **2,722 actual recordings** with
**8,166 WAV files** (three local DSP treatments) and **2,722 original MP3 masters**.
The completed first pass has **2,702 slots: 2,682 newly generated + 20 reused pilot
takes**. Another 20 historical short-language takes are preserved outside that
first-pass slot count. Six superseded early Robot Minion experiments remain excluded.

All **387 entries** are represented. Words and nonverbals have one take per
compatible mood; phrases have one selected mood. The full design has **7,123 slots**:
2,702 completed and **4,421 deferred**, not 7,123 recorded files. Never fabricate
a path or silently substitute a mood when no suitable recorded take exists.

## Listen to the bank

From the repository root:

```sh
python3 -m http.server 4177 --bind 127.0.0.1 --directory internal/boop-design/assets/boop-voice-v1
```

Open <http://127.0.0.1:4177/review/>. No dependencies, API key or generation calls.
The continuous audition plays all first-pass clips with on-screen state/mood/keyword
labels. Filter into chapters, skip/replay, mark Keep/Rework and export the review JSON.
Adult expressions are off by default. Review marks stay in the browser and include
the exact master hash; they do not automatically change the package manifest.
The first-pass audio totals 64.22 minutes (about 80 minutes with default gaps).
This portable voice-only page does not depend on the original author's localhost
or audition checkout. Animation/SFX previews remain in the sibling V4 review bank.

| File/folder | Purpose |
| --- | --- |
| `manifest.json` | Recorded IDs, entry ID, intended mood, duration, review status, original script, voice/model, encoding, paths and SHA-256 hashes |
| `index.json` | Recorded IDs indexed by state, mood, intent and dictionary entry; cheap shortlist lookup |
| `dictionary.json` | 387 meanings, context guards, compatible moods, variation directions, audience/rarity and proposed pacing policy; no massive Cartesian matrix |
| `audio/robot-soft/` | Recommended quiet electronic texture; 2,722 mono WAVs |
| `audio/original/` | Dry, quiet-level-matched WAV comparison; not untouched provider output |
| `audio/robot-grain/` | More electronic alternative; same takes, not extra performances |
| `masters/` | Untouched provider MP3s, for future reprocessing; no API needed |
| `select.mjs` | Dependency-free host-side reference selector and assembly guard; see commands below |
| `tools/check.mjs` | Integrity, audio format/level, eligibility and assembly tests; writes exact storage report |
| `provenance.json` | Batch/model/processing provenance, with no credentials or account data |
| `storage-report.json` | Exact logical bytes, durations, category counts and recorded mood coverage |
| `plans/phase1.json` | Completed slot IDs mapped to actual recording IDs; includes reused pilot mappings |
| `plans/deferred.json` | Disjoint remaining 4,421 slots; not authorized for automatic generation |
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
to `audio/robot-soft/new.d02.wav`. The JSON output is built from this package, not
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

Recommended playback assets: `audio/robot-soft/*.wav` — RIFF WAV, signed 16-bit
little-endian PCM, **44,100 Hz, mono**. These are complete speech snippets, not
procedural sound effects. The WAV header must be parsed; do not send it as raw PCM.
Browser/desktop playback can use a normal decoder or Web Audio. Files are already
quiet-normalized (RMS ceiling .07, peak ceiling .55); begin at modest gain. Digital
ceilings do not establish acoustic loudness through the actual speaker.

The three texture folders have equal durations and are alternatives. A runtime
using only soft circuit does not need the two comparison WAV folders or MP3 masters.
The 2,702-slot first pass alone occupies approximately **340 MB** as soft-circuit
WAVs; its original MP3 masters occupy approximately **63 MB**. All treatments and
historical takes make this archival handover about **1.1 GB**; do not copy every
treatment to an SD card. [storage-report.json](storage-report.json) gives exact logical bytes
for each profile, all audio, metadata and the entire folder, plus duration totals.
Git checkout block allocation and compressed Git pack size can differ.

**ESP32 is not integrated here.** Existing firmware's short syllable/word format
is not a drop-in container for these WAVs. A downstream implementation must choose
its decoder/PCM sample rate, SD streaming/ring-buffer strategy, resampling, DAC/I²S
format, cancellation and volume/limiting under the device contract. Decode MP3 to
PCM on the host if the board lacks an MP3 decoder. Do not lower bit depth/pitch or
truncate phonemes without re-auditioning on the speaker. Keep the masters for that
future export; this publication does not modify the wire protocol or firmware.

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

For a deliberate re-import of the completed first pass from its preserved local
generation checkout (not from a fresh repository clone without paid masters):

```sh
node internal/boop-design/assets/boop-voice-v1/tools/import-phase1.mjs --source /absolute/path/to/audition-checkout
node internal/boop-design/assets/boop-voice-v1/tools/check.mjs
```

The importer reads a fixed allowlist under that source checkout, verifies provider
master hashes, refuses to overwrite different audio and strips accounting/request
IDs from provenance. It makes **no API calls** and never reads `.env` or credentials.
The extension preserves existing recording IDs/review status, verifies matching
slot/master hashes and never replaces different audio. The original `import.mjs`
is pilot-only and refuses to downgrade an expanded manifest. Do not generate new
recordings as part of normal app startup.

### Expand later without duplicate generation

Use `performanceId` as the stable recording-slot key, not a guessed filename or
script string. `plans/phase1.json` maps all completed slots to their actual recording
IDs, including the 20 reused pilot takes. `plans/deferred.json` is the disjoint
complement; checks prove the union equals the full 7,123-slot design. Before any
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
