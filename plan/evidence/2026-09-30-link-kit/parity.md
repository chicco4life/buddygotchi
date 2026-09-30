# Parity with main, and B's costs after a day

The parity lane of the 2026-09-30 overnight run ([PLAN.md](PLAN.md), step 4).
The owner's rule: the refactor behaves like main (4bea7b21), with main's
quality: no performance bugs, crashes or leaks. B's design stays: the log
is the only state, the next event is worked out from the log, 10 s at
most, holds asked at an event's turn.

Everything here was measured on debug builds, on this Mac, in scratch
checkouts: main (4bea7b21), the branch's HEAD 18d9a0a0 ("before"), and
HEAD with this lane's changes ("after").

## What changed

- **The log lets go of old events in batches.** An event older than a
  day drops out of view at once, as before, but its memory and index
  entries go only once they're an eighth of what's kept. Before, every
  append and every tick copied the whole day (a slice kept the array
  shared, so removing the first event copied the rest) and rebuilt every
  index. `jharness/Sources/JHarness/Log.swift`.
- **HISTORY finds its window by bisection** on `at`, instead of filtering
  the whole day on every pass. `Log.events(before:from:)`, used by
  `Harness.history`. An older app's lines, whose times can go back (main
  timed a hook as it came and a tick as it ran), are bisected on the
  latest `at` so far (`Log.maxAt`), so only the lines out of order inside
  the window are filtered one by one, even when main's newest line is
  one of them (review fix; `LogTests.testStepsBackUpToTheNewestLineOnlyCostTheirOwnStretch`).
- **A mood or a reaction is found without reading every `did`.** The log
  indexes `did`s by their action, and `LogView.lastDid` reads only that
  action's. `Choice.latest` (the mood, six times a pass), the working
  heartbeat's check (every tick) and the poke hold use it. Before, a
  mood unchanged for hours meant reading every `did` since, on every pass.
- **Lines of events that have aged out are let go** every thousand
  events; before, they stayed until they outnumbered the day's events by
  a thousand.
- **The mood after an upgrade.** The first launch after the log took
  over reads the old `mood` file when the log's last day has no change,
  however old the file is, as main did, logs it as a change by `upgrade`
  with no message (HISTORY doesn't show it, and no "Boop has been … for"
  counts from it), and deletes the file. `MoodAction.carryOver`, one line
  in `Runtime.init` after the read-back.
- **The device follows the log when a mood ages out** (review fix). A mood
  whose latest change is over a day old reads calm in the log, the menu
  bar and MOOD; the core kept the old one, so the device drew it until the
  next change or launch. That was certain for a carried-over mood with no
  key for the brain. `Runtime.tick` now hands the core the log's mood when
  they differ (two lines in the Mac lane's file, and a clause in
  harness/DECISIONS.md §2).
  `ParityTests.testACarriedMoodThatAgesOutGoesFromTheDeviceToo`.
- **A reaction your tap cut short outlasts react's 90 s** while the
  pokes hold it. JHarness's `output(_:openFor:keepOpen:)` lets an output
  keep a `did` open past `openFor`; react's is `TranscriptView.heldByPokes`
  (a poke came after it, and nothing since has stopped the pokes). One
  line in `Runtime.harness`, which the ParityTests case now goes through
  (review fix: it registered a stand-in output of its own before, so
  dropping `keepOpen:` from the app passed every suite).
- **agent-hooks' `HookServer` no longer keeps itself alive.** Its accept
  thread held the server, so a server let go without `stop()` never
  closed its socket. The thread now holds only what it needs, as
  JHarness's `EventServer` does.

## Performance

`SoakTests.testTwoDaysOfEvents` (`BOOP_SOAK=1`, `BOOP_SOAK_TURNS`, off by
default): two synthetic days in the transcript, about 25,000 events a
day, four times the owner's busiest real day (6,826 lines on 2026-09-29):
four Claude sessions taking turns around the clock, each turn a prompt,
eight tool calls and a finish, with a pass for each prompt and finish, a
mood change every fourth finish and a reaction to each finish. Then a
launch at the end, and the live part: 1,500 more turns (27,000 hooks,
32 hours, so the whole read-back ages out) through `Runtime.hook` with a
tick every simulated second and the scripted brain. main's port writes the
same work in main's line shape (no passes, which main didn't log). To run
it: `BOOP_SOAK=1 BOOP_SOAK_TURNS=1500 BOOP_TEST_FILTER=testTwoDaysOfEvents
.build/debug/BoopTests` after `make -C internal test` has built it.

| 1,500 live turns | before (HEAD) | after | main |
| --- | --- | --- | --- |
| Launch | 1,155 ms, 24,961 events kept | 1,129 ms, 24,961 events kept | 1,247 ms, 39,760 events folded, none kept |
| Memory: before launch → after → after the live part | 39 → 89 → 81 MB | 45 → 95 → 66 MB | 88 → 91 → 75 MB |
| Per event: mean, p50, p95, p99, max | 1.72, 0.18, 12.15, 13.37, 42.39 ms | 0.34, 0.15, 1.34, 1.41, 15.19 ms | 0.31, 0.14, 1.24, 1.29, 7.42 ms |
| Per tick: mean, p50, p95, p99, max | 0.22, 0.06, 0.76, 1.02, 6.02 ms | 0.05, 0.05, 0.08, 0.10, 2.56 ms | 0.05, 0.04, 0.07, 0.10, 0.25 ms |
| The live part, all told | 71.9 s | 15.1 s | 13.8 s |

At 300 live turns before was 1.03 ms a mean event (p95 6.11) and after
0.35 (p95 1.33): before got slower the longer it ran, since the mood's
look-up read every `did` since its last change. After stays flat, within
10% of main. An event's time includes its pass, when it has one.

- **Memory** holds a day of events by design (about 50 MB for this
  synthetic day, so about 15 MB for a real one); it doesn't grow while
  running. main kept none.
- **The launch** takes as long as main's: it parses about 37,000 lines
  and keeps the last day's 25,000, where main folded two days' 40,000.
- **The largest tick** (2.6 ms) is a batch let go; **the largest event**
  (15 ms) is the first pass after the launch, once.
- **The view's fold never starts over** in the live loop (its transforms
  come in order), so `catchUp`'s restart costs nothing there. The soak and
  `ParityTests` pin it (`TranscriptView.refolds == 0`).

## A whole day against main

`boopctl workday run --brain scripted` (seed 1) on main and on HEAD with
these changes, each in its own scratch checkout, then `workday report`:

- **What the brain heard:** the same 414 lines, in the same order, once
  the working heartbeats are set aside. Their times are drawn at random
  from each state directory's random seed.
- **What it was told:** 405 of the 410 states are the same byte for byte,
  once the takes Voice drew at random and the heartbeats are set aside.
  The other 5 differ by a minute in a line's age (the runner paces the
  day in real time).
- **Passes:** 428 on main and 429 here, the difference all heartbeats (18
  and 19). A second main run had 427, 17 of them heartbeats: they vary
  from run to run on main too. The same 193 turns, 192 starts and 34
  notable lines were reacted to on both, with no mood changes on either
  (the scripted brain always stays).

## The first launch after upgrading

`Fixtures/parity-upgrade` is a state directory main itself wrote
(4bea7b21, driven through its runtime): two days of its transcript, a
mood changed to proud 29 hours before the relaunch, alpha's turn still
running, beta idle after a permission prompt, gamma's session a day old.
Relaunched on it at 18:00, main shows proud, sessions `claude alpha
working` and `claude beta idle`, no line on how long Boop has been proud,
and numbers the next turns "turn 3" on alpha and "turn 2" on beta.
`ParityTests.testAnUpgradeComesBackAsMainDid` checks the branch shows
exactly that, then that a relaunch an hour later is still proud (from the
log) and one a day later with no change is calm (the design's).

## Each risk in the parity map

| Risk | Verdict |
| --- | --- |
| The mood after an upgrade: the first launch dropped the saved mood unless the last day's lines had a change | **Regression, fixed**: the old file fills the gap, then goes (above) |
| A reaction your tap cut short, and a run of pokes longer than react's 90 s `openFor` | **Regression, fixed.** It was wider than the map said: a few pokes and then 90 s with nothing else happening also dropped the reaction from HISTORY (the tick ended it failed before the next event could end it done), and a run over 90 s let its next poke wake the brain again. Main held it however long. `ParityTests.testATapCutReactionOutlastsReactsOpenForWhileThePokesGoOn`, `KeepOpenTests` |
| Performance after 24 h: `Log.trim`, `history()`, `catchUp` | **Regression, fixed** (above) |
| `HookServer` kept itself alive | **Bug, fixed**: `HookServerTests.testLettingGoOfTheServerStopsIt` failed before (the server outlived its last reference and kept its socket) |
| `use(brain)` answers an event under 10 s old that came before the key | **Not user-visible.** Only hooks in the moments between the launch and the key read (or a Keychain prompt) can be answered late, by up to 10 s, where main never answered them; a relaunch answers nothing it read back. It's the agreed design, which JHarness's `testAnEventWaitsTenSecondsAtMost` pins |
| Restart wording, `restarted` where main wrote `Boop restarted` | **Not user-visible**: a failed end isn't shown in HISTORY, and nothing reads the why |
| `at` clamped between the last event's and the clock | **Not user-visible**: Boop stamps every event from one clock; a hook's time moves by at most the milliseconds it waited for the queue |
| The brain woken at the end of the input batch, before the step's device effects | **Not user-visible**: the effects log nothing the prompt reads, and the brain's answer comes back on the same queue after them, so the device's order is main's |
| A 0 gives way to any newer waking event, even one then held | **Not user-visible in practice**: it needs a routine event waiting behind a pass, then a poke that opens a thread or a poke of a run already answered |
| Events older than 10 s never answered, holds at an event's turn | **Intended by the agreed design** |
| The read-back window, 24 h where main read two days' files | **Intended by the agreed design**: only a thread busy for over a day numbers its turns from the window's start; sessions are forgotten after a day's silence on both |
| A day of events in memory | **Intended by the agreed design**; measured flat (above) |
| Every pass is an event; `debug.jsonl`'s order | **Intended by the agreed design**, dev tools only |
| The goldens pin B against A, not main | Checked by the orchestrator: main builds the same 387 states ([golden-states-on-main.txt](golden-states-on-main.txt)) |
| A and B together not compared with main on a whole day | **Checked**: the same lines and states (above) |
| What the device receives, in order, on the board (L4) | Not run here: this lane doesn't touch the board. The Mac lane's LinkKit changes the wire anyway |

## Checks run

- `BoopTests`, all of them, GoldenStateTests included: 285 passed and the
  soak skipped on HEAD with these changes; 266 passed on the worktree as
  it stood with the Mac lane's LinkKit work (same build command, own
  scratch path).
- `swift test --package-path jharness`: 34 passed (31 before, plus
  `LogTests`' two, which hold the batched log against filtering every
  event through 6,000 appends and against out-of-order times read back,
  and `KeepOpenTests`).
- `swift test --package-path agent-hooks`: 77 passed (with
  `HookServerTests`).
- The soak, above, on all three builds; the scripted workday on main and
  after.

After the review fixes, on the worktree as it stood (HEAD baf548d1 with
the Mac lane's work), own scratch paths:

- `BoopTests`: 269 passed, the soak skipped (four ParityTests among them).
- `swift test --package-path jharness`: 35 passed (with the new
  `LogTests` case); agent-hooks: 77 passed. Each package's first build
  hit the "plugin for module 'TestingMacros' not found" flake and passed
  when run again.
- The soak at 1,500 turns: launch 1,118 ms; memory 39 → 89 → 65 MB; per
  event 0.33, 0.15, 1.30, 1.33, 13.90 ms; per tick 0.05, 0.05, 0.08,
  0.10, 2.67 ms; the live part 15.1 s. The same as "after" above, the
  tick's mood check included.
- Mutations, on a scratch copy of the tree: without `keepOpen:` in
  `Runtime.harness`, the tap-cut ParityTests case fails ("Boop is
  answering these pokes"); without the tick's mood check, the aged-out
  case fails ("the device follows the log"). Both pass unmutated.
