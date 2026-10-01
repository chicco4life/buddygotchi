# Checking the tune lane (tune-check, 2026-09-28)

An independent check of the tune lane's three commits (`02ffc447`,
`667d0222`, `e337c3d1` on `ovn2/tune`, on top of main at `7f5d10ff`):
did the tuning go through the steering, are the budgets kept, do its
numbers hold on a rerun, and is anything absurd. Everything ran on the
lane's worktree with fresh state under `/tmp`, a throwaway `HOME`, and
the fake USB device of `workday.py`. Nothing touched the board, the
webcam, Bluetooth or the everyday app.

## What the tuning changed, and whether it's steering

- **Steering text:** the guide, all seven mood files and the `boop`
  personality. `plan/steering/` and the app's copy
  `app/Boop/Resources/steering/` are identical (`diff -r` is silent,
  and `RuntimeTests` checks it too).
- **Code, two option texts:** `MoodAction.moods`' `excited` and
  `grumpy`, each with a `not_for`. They are the `mood` question's
  criteria, so they're steering in all but place; the lane says why
  (the text alone didn't stop a turn of a few minutes reading as
  "several wins in a row") in the decision log
  ([ARCHITECTURE.md](../../../ARCHITECTURE.md) §11) and in
  [DECISIONS.md](../../../harness/DECISIONS.md) §2.3's table.
- **Code, one line of UI:** the Settings pane's line for `boop`, to say
  what it does now.
- **Budgets** (bytes ÷ 4, comments and front matter left out): guide
  275 of 300, `boop` 582 of 600, `chatter` 297 of 300, moods 111–150
  of 150 (happy is at exactly 150). `testTheSteeringFitsItsBudgetsAndSettings`
  passes.

## The evals

`BOOP_JEV_KEY=… make eval`, once: **12/12 passed in all 3 runs**,
median 225 ms, slowest 324 ms. Scenario 04's picks were the same as in
[harness/EXAMPLE.md](../../../harness/EXAMPLE.md) in all three runs
(determined once, grumpy twice, grumpy twice, proud three times).

**EXAMPLE.md and HARNESS.md §9 are real output.** Every one of
EXAMPLE.md's 19 JSON lines matches run 1 of the lane's
[eval-04-debug.jsonl](../tune/eval-04-debug.jsonl) field for field
(probabilities within the stated rounding, `…` only where marked), every
line of its state block appears in that run's state for entry 12 in
order, and its story table's picks, probabilities and 191–428 ms are
that run's. HARNESS.md §9's pass line (191 ms, grumpy 0.93 · grumpy 0.99
· twice 0.88 · tests 0.98 · again 0.99) is entry 12's pass.

## The working day, rerun

Seed 1, `jev:jev-latest`, warm (the eval ran just before). Rerun 1 is
the tool as the lane committed it; rerun 2 is after the fix below. The
lane's final runs are "after-1, after-2" in
[its README](../tune/README.md). Full reports: [day-reports.md](day-reports.md).

| | Lane after-1, after-2 | Rerun 1 | Rerun 2 |
| --- | --- | --- | --- |
| Mood changes a day | 16, 16 | 14 | 16 |
| Most in one hour | 5 | 5 | 5 |
| On a routine line: fades back to happy / any other | 4 / 1, 4 / 1 | 4 / 1 | 4 / 1 |
| Reactions (per finished turn) | 157, 155 (0.81) | 150 (0.78) | 156 (0.81) |
| Notable lines reacted to | 26/26, 26/26 | 25/26 | 26/26 |
| Clean finishes of 1–10 min | 26/26, 26/26 | 27/27 | 26/26 |
| Clean finishes under a minute | 105/157, 103/157 | 98/156 | 104/157 |
| Turn starts | 0/192 | 0/192 | 0/192 |
| Passes dropped | 0, 0 | 8 | 2 |
| Reactions the device "never said ended" | 7, 8 | 12 | 0 |

Per hour it holds too: 0–5 mood changes an hour, the same 5 in the
10:00 hour (determined, grumpy, proud at the test fight, back to happy,
grumpy at the poke streak). Rerun 1 is 2 changes short because the 17:20
16-minute docs finish was one of its dropped passes, so neither its
excited mood nor the evening's fade back came.

**Time in each mood** (rerun 2): happy 369 min, excited 81, proud 68,
grumpy 51, sad 7, determined 4. Faces: happy 104, excited 24, grumpy
12, proud 11, determined 4, sad 1.

**Nothing absurd:**

- No reaction on routine tool uses: with `tool_uses: notable` only the
  14 failures and fixes woke the brain, and each got a fitting face
  (determined or grumpy at a failure, proud at a fix).
- Sad only once a day, at the 14-minute turn that ended failing, held
  three times; never at a routine finish.
- One mood change a day on a single routine line that isn't a fade, the
  same in every run of the lane's and mine: at 11:08 a grumpy Boop (from
  the first poke streak) turns proud a line after a build comeback. It
  comes from the poke streak (below).
- Holds: routine finishes of 1–10 min are held once 21, twice 2, three
  times 3 (rerun 2); those three are while Boop is proud, after a fix.
  Notable lines: once 10, twice 8, three times 8.

**Two things to know about the reactions:**

- They're **down against main on the same scripted day** (240–242 to
  150–156), by design: main made a curious face at a third of turn
  starts (about 60 a day) and faces at short finishes with nothing to
  show. **Against what the owner saw** they're up: 0.78–0.81 reactions
  per finished turn, each with a face, where the 2026-09-27 log had
  0.42–0.71 per cheer and 97 of its 102 reactions had no face.
- The word is "yay" in 124 of rerun 2's 156 reactions (80%; main 152 of
  240), since every routine finish gets a small happy face and the
  exclamation wins over the topic ([DECISIONS.md](../../../harness/DECISIONS.md)
  §5). It may read as repetitive on the device; a proposal below.

## Fixed here

- **`workday.py` could end a reaction as never played.** The app writes
  a pass's line before its actions' lines, in the same turn on its queue.
  `settle` read the file between them, found nothing waiting and let the
  next step's clock move go out. The app took that move before the fake
  device's `ended`, so a reaction whose deadline the move passed ended
  `failed: the device never said it ended`, and HISTORY showed it as
  not having happened. That was 7–12 reactions a run in the lane's runs
  and rerun 1, before and after tuning alike; it can't happen with a
  real board, whose `ended` comes after the moment plays. Found by
  tracing moment 81 in rerun 1's `boop.log` (`link brain → … "id":81`,
  then `dev: clock advanced 8849 ms`, then `device: moment 81 ended
  done`). Now, after any pass, `settle` moves the clock 1 ms as a
  barrier, which the app takes up only after the pass's actions, and
  looks again. `SettleTests` in `internal/tools/workday/tests/` pins
  it (it fails on the old code). Rerun 2: 156 reactions, 156 `done`.
- **The decision log's count.** ARCHITECTURE.md's 2026-09-28 row said
  mood changes on a routine line that weren't a fade went "from 30–31
  to 1"; 30–31 counted the fades too. It's 17–18 to 1.

## Tried and not kept

All with `boopdev eval --scenarios DIR --steering DIR`, 3 runs each, so
no rebuild was needed for text:

- **A first poke streak, to leave the mood happy.** A probe with two
  routine turns, then a streak: grumpy 0.68–0.76 with the lane's text.
  The guide's "a happy Boop makes a grumpy face at a failure or a poke
  and stays happy": 0.65–0.83. Happy's file saying "being poked once":
  0.89–0.91, worse. `grumpy`'s `not_for` quoting the line ("a poke
  streak that isn't again right after the last time", rebuilt, then
  reverted): 0.73–0.82. A streak "again right after the last time" was
  grumpy at 0.99–1.00 every time, as it should be. The text isn't the
  lever; PLAN.md §3 has the item, with this added.
- **Routine finishes held once.** A probe of three routine finishes
  while proud: the 1-minute one was once at 0.49–0.57 (three times
  0.17–0.24). "Routine finishes hold once, bigger moments longer" in
  the personality left it at 0.51. Not kept; it's 3 of 26 finishes.

## Also seen

- **Drops aren't only a cold start.** Rerun 1 dropped 8 passes, in two
  clusters of 4 (16:20–16:26 and 17:16–17:21 on the app's clock), and
  rerun 2 dropped 2 in a row at 09:47, all at 1277–1333 ms,
  with Jev warm on this steering. Their states weren't bigger than ones
  answered in 250 ms. One was the day's 16-minute finish. PLAN.md §3's
  drops item now says so.
- **The day drifts with the wall clock.** The app's clock also moves
  with real time, so over the 4–5 minute run the day shifts a few
  minutes late (the docs finish at 17:21 instead of 17:20), and a turn
  or two moves between hours (13:00 has 6 turns here, 7 in the lane's
  runs). The totals don't change.

## Checks that ran

On the lane's worktree, after the fix:

- `make build`: builds.
- `make -C internal test`: 205 of 205.
- `make -C internal fw-test`: 111 of 111.
- `make -C internal sim`: 11 scenarios, 0 expectation failures, 0
  changed pictures.
- Run directly (the `tools-test` and `faces` targets can't rebuild the
  venv in a lane worktree): `boopctl_lib` 27 OK, `workday` 9 OK (7
  before, and the 2 new), `webcam` 3 OK; `facegen.py --check` 337
  frames match Chrome, generated files unchanged.
- `BOOP_JEV_KEY=… make eval`: 12/12 in all 3 runs.
- `workday.py run` with Jev: twice (above).

## Proposals

- **A first poke streak shouldn't reach the `mood` question**, or its
  line should say it's the first. Five tries in text between the lane
  and this check didn't move Jev below 0.65.
- **Deadline against Jev's slow answers.** Every drop tonight sat at
  1.28–1.33 s, just past the 1.25 s deadline. Before a warm-up pass,
  measure how often a warm day drops and what a 1.5 s deadline would
  cost the reflexes (nothing waits on the brain, so perhaps nothing).
- **Fewer "yay"s.** Routine small faces could go without a word, or
  with the topic, keeping "yay" for bigger wins: one Example in
  `personality/boop.md` (its long-turn line), checked with the word
  counts from `workday.py report --json`.
