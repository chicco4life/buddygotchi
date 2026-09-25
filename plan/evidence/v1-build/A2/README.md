# A2: Memory, Voice and actions — evidence

2026-09-26. Mac-only milestone; no device or webcam checks apply.

## What was built

- **`app/BoopKit/Memory/`**: `LongTerm` and `ShortTerm` parse and render
  the ARCHITECTURE §4 formats exactly (round-trip tested on the spec's own
  examples). `MemoryStore` is the only code that touches the files. It
  writes atomically, snapshots both files to `history/<date>/` at setup
  and when a new day starts (dated the day being reflected on), keeps
  that day's short-term text for the reflection, and starts short-term
  fresh. It reads a file again when it changes on disk, so hand edits
  survive. A broken file is kept as `.broken`. Long-term memory comes back
  from the newest snapshot that reads. Short-term memory starts fresh and
  keeps its date, so the day isn't started or reflected on twice. The
  store applies the core's `.happened`, `.growth` and `.newDay` effects,
  and its `lastActiveDay` feeds `Core.init`.
- **`app/BoopKit/Voice/`**: 64 syllables, a 40-word vocabulary, a
  16-syllable dialect from the seed, feeling-shaped syllable pools,
  grouping with doubling, word placement, the tune from the feeling, and
  the tempo from pace and feeling. `Unintelligible` checks against
  `/usr/share/dict/words`, rude words in the launch languages and Minion
  words. A failing gibberish word is re-rolled while the line is built,
  then the whole line gets up to 5 retries, then the safe hum `mm-nn`.
- **`app/BoopKit/Actions/`**: `say`, `face`, `quiet`, `note`, `remember`,
  `forget`, `temperament` and `moment`. Each one owns its `ToolDefinition`
  (`app/BoopKit/Harness/Tool.swift`, the contract A3's harness uses) and
  checks its own arguments against it. Each drops bad input with a logged
  reason. `DeviceMoment` builds the `moment` line. `face.play` is the rule
  path for the core's `.moment` effects.
- **`boopdev memory --state-dir`** and **`boopdev voice`** (with `--why`
  to show each rejected try).

## Checks (Done when)

| Check | Result |
| --- | --- |
| L0: every memory limit is enforced | **Passed.** `MemoryTests` covers: notes 10 × 80 (oldest drops), Happened last 40, About you 30 and Preferences 15 (refused when full), 100-character facts, temperament once a day with 5 sentences at most, moments one per day with 20 at most, both byte budgets, limits on hand-edited files, and the privacy checks |
| L0: snapshots and restore work | **Passed.** Snapshots at setup and on a new day; long-term restored from a snapshot, both live and on restart; broken short-term keeps its date; `.broken` copies kept; the core-plus-memory restart doesn't start the day twice. See `memory-restore.txt` for a run through `boopdev` |
| Voice is deterministic | **Passed.** `testLinesAreDeterministic`, `testTheDialectComesFromTheSeedAndNeverChanges` |
| 10,000-line property test, zero dictionary hits | **Passed, under the rule as now specified** (see below). 10,000 lines across 25 dialects, all 8 feelings and a range of moods: 0 hits, and 4 came out as the safe hum. The test checks independently of Voice's own check |
| Every action drops invalid input and logs why | **Passed.** `ActionTests`: bad choices, missing or unknown arguments, overlong or private text, say in quiet, rule anims through `face`, calls sent to the wrong action. Each drop logs exactly one line with its reason |
| `make test` | 117/117, three runs in a row |
| `make build` | Builds |

## The one change to the check

VOICE.md §7 as first written would have failed every doubled syllable
(`ki-ki`, `pi-pi`, `ba-ba`), because the Mac's word list (web2, 235,000
words) contains most of them. That includes the spec's own examples of
doubling, which it calls the Minion bounce. So doubles now skip the big
word list, but a list of doubles people hear as words (`mama`, `papa`,
`nana`, `yoyo` and others) still fails, and so do nursery toilet words.
In the 10,000 lines, 904 doubled groups were in web2 and were allowed
under this rule. Every other group, and every whole line, had zero hits.
It's in VOICE.md §7 and the decision log.

Before the per-word re-roll, dialect `7f3a` hummed 5% of excited lines,
because its favourites `pi pa la ki` make `pipi`, `papa` and `paki`. After
it, all 8 feelings on two dialects came out at 0–0.35% over 2,000 lines
each.

## Samples

`voice-samples.txt` shows six lines per feeling for dialect `7f3a` and four
dialects' favourites. Reviewed by eye: happy and excited are bright
`a`/`i` with doubles; proud ends on long `gom`/`a`/`o`; curious ends in
`i`/`e` and asks; hopeful is soft `o`/`u`; annoyed is clipped `t`/`k`/`p`;
sad trails off on `u`/`o`; sleepy hums.

## Spec changes

VOICE.md §3, §4, §5, §6, §7; ARCHITECTURE.md §4, §4.2, §4.3 and six
decision-log rows; HARNESS.md §6 (all eight tool definitions);
VERIFICATION.md §2 (`boopdev memory`, `boopdev voice`).

## Not done here (belongs to later milestones)

- Wiring actions to the real device link and the core's effects in the app
  (A4). The `ActionContext` closures are the seam.
- The reflect prompt reading `MemoryStore.reflectionText` (A3).
- The mood on the Today line only updates if the app calls `setMood` (A4).
