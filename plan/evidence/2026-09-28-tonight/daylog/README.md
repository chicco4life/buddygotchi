# Daylog: a whole day in debug.jsonl, and `boopctl day`

2026-09-28, lane `daylog` (B1). The owner spends tomorrow with Boop
under `make debug`; this makes sure the state dir's logs can answer
"what did Boop do today, and why?" at the end of it.

## What changed

1. **Relaunching no longer loses the morning.** Debug mode still empties
   `debug.jsonl` in place at each launch (the dashboard and
   `boopdev watch` notice that), but first copies it to `debug.1.jsonl`
   and moves older copies up, keeping 10 launches
   (`DebugLog.keptLaunches`, [HARNESS.md](../../../harness/HARNESS.md) §9).
   An empty file isn't kept. `RuntimeTests.testDebugModeKeepsTheLastTenLaunches`
   pins the count and order.
2. **`boopctl day`** (`make day` for the everyday app) reads
   `debug.jsonl` and the kept launches, oldest first, and sums up one
   local day by the hour ([VERIFICATION.md](../../../VERIFICATION.md) §2;
   what it counts from which line is the table in HARNESS.md §9). It's a
   `boopctl` subcommand, not `boopdev`, because the dashboard's parsing
   of the same lines is Python in `boopctl_lib`, and its tests run on
   recorded headless logs in a second.

## Is debug.jsonl enough?

Yes, for every question the summary asks; nothing new had to be logged.

| The summary needs | The line that has it |
| --- | --- |
| Events, their kinds and lines | `event` (`kind`, `line`, `reaction`, `wakes_brain`) |
| Passes and their answers, dropped ones and why | `pass` (`answers`, `dropped`, `brain` or `by`, `latency_ms`) |
| Actions, started ones, and how they ended | `action` (`ok`, `message`, `pending`) and `settle` (`end`, `why`) |
| Cheers and chatter | `sent` moments (`anim`, `say`, `mood`) |
| The brain's reactions and their faces, forced ones apart | `react` actions (`by`), and their pass's `react` answer |
| Needs-you, chirps and mood changes | `sent` states (`attn`, `mood`), keepalives included |
| Brain, sessions, the device connected | `status` |

Two things aren't lines, and the summary infers them: an event replaced
while a pass ran (only `boop.log` says so; it's an `event` with
`wakes_brain` and no `pass`), and the device's own `ended` and `input`
(they show as `settle` lines and `tap`/`pokes` events). Sent lines are
logged whether or not the device is connected, so a chirp counted while
it was unplugged is one Boop would have made.

**Size.** The fixture's lines average 135 bytes for a `sent` state, 4.5
KB for a scripted pass (its whole state) and 90–320 bytes for the rest.
A 10-hour day adds about 3,600 keepalives (0.5 MB) and a few hundred Jev
passes, whose states grow with HISTORY: a few MB a day. `boopctl day`
read a 6 MB log in 0.12 s.

## The run

`drive_day.py` (this folder) drives `Boop --headless --brain scripted
--debug` on a fresh state dir in `/tmp/bdl`, with hooks through the real
`boop-hook`, dev lines for the clock, forced passes and moods, and a fake
board on the USB link that says who it is and answers each reaction's
`ended` (`done`, `cut` on a tap or needs-you, `skipped` while needs-you
shows, or never when told to). It launches the app twice on the same
state dir:

- **Launch 1**, about a minute of real time: a Claude turn with a failed
  and then passing test run, 12 s of needs-you, a cheer, and a proud
  reaction forced from the dashboard.
- **Launch 2**, relaunched, then 4.5 simulated hours: Codex and Claude
  working with chatter, both needing you at once (Codex first, then
  Claude, a second chirp), a reaction refused while needs-you shows, a
  tap cutting one short, three failed test runs and a rate-limited turn,
  a quiet midday with two heartbeats and the board unplugged for 20 min,
  a poke streak, forced moods and reactions (one the board never answers,
  one that waits too long), and a long Claude turn with 7 min of
  needs-you.

It took 2 min 24 s. The relaunch left `debug.1.jsonl` (44 lines, 28.6
KB) beside `debug.jsonl` (303 lines, 98.3 KB); both are the test fixture
in `internal/tools/boopctl_lib/tests/fixtures/day/`, as recorded. Neither
has a `PRIVATE_` marker, though every hook carried them.

The first launch starts at the real time and the second runs on an
advanced clock, so the second must start after the first ends: the
first launch uses real time only. A relaunched headless app starts its
clock at the real time again, so a simulated day can't be relaunched
after it has advanced (proposal 1 below).

## The sample summary

`internal/tools/boopctl day --state-dir internal/tools/boopctl_lib/tests/fixtures/day`
(Seoul time, exit 0):

```
Boop's day: Monday 2026-09-28, 01:34–06:01, 2 launches
  debug.1.jsonl   01:34–01:35  brain scripted
  debug.jsonl     01:35–06:01  brain scripted
  running 4 h 26 min, the device connected for 4 h 06 min of it

hour  cheers  chatter  reacts  chirps  moods  passes  dropped  missed  taps  needs you  faces
01         1        4       5       3      2       5                      1      6 min  excited 5
02         1        4       5              2       5                1                   excited 5
03                          1                      1                1                   excited 1
04                  3       3              2       3                      4             excited 3
05         1        6       1       1              1                             7 min  excited 1
06
all        3       17      15       4      6      15        0       2     5     13 min  excited 15

reacts are the reactions the brain asked for, with their faces, and missed the ones of them that didn't happen (below);
chatter is the rules' working chatter; chirps are states bringing a new needs-you or a different one.

Brain: 15 passes (median 0 ms, slowest 0 ms), 0 dropped, 0 chose no reaction; and 9 forced from the dashboard, asking for 8 reactions

Mood changes: 6
  01:35  happy → proud  (forced from the dashboard)
  01:35  proud → happy  (turn_start: codex started turn 1 on "landing".)
  02:11  happy → determined  (forced from the dashboard)
  02:11  determined → happy  (turn_end: claude finished turn 1 on "jetpack": failed (rate limit) after 24 min, a very long turn, 19 tools (3 failed). Tests failing.)
  04:47  happy → grumpy  (forced from the dashboard)
  04:48  grumpy → happy  (turn_start: claude started turn 2 on "jetpack", after a long break.)

Needs you: 3 times, 13 min in all; cleared in 12 s to 7 min 2 s, median 6 min 4 s
  01:34  claude · jetpack                    12 s
  01:47  codex · landing → claude · jetpack  6 min 4 s, 2 chirps
  05:13  claude · jetpack                    7 min 2 s

Reactions that didn't happen: 2 of the brain's 15, and 5 of the 8 forced from the dashboard
  1× no device connected: 03:12
  1× no word it finished: 02:16
  1× cut short: you tapped Boop (forced): 01:53
  1× something needs you (forced): 01:48
  1× the device disconnected (forced): 02:52
  1× the device never said it ended (forced): 04:48
  1× waited too long (forced): 04:48
```

Read against the driver: 3 cheers (a Claude turn in each launch and the
Codex turn; the rate-limited turn doesn't cheer), 4 chirps (Claude in
launch 1, Codex, the switch to Claude, the afternoon's), the 6 mood
changes and their causes, and one of each way a reaction can fail. The
scripted brain always answers an excited "yay" and a happy mood, so its
15 reactions are all excited and every forced mood is undone by the next
pass. The other faces sent (proud, curious twice, determined, sad,
happy) were the dashboard's, counted apart since the
[independent check](../daylog-check/README.md).
Without `debug.1.jsonl` the morning's needs-you, cheer and proud mood
are gone (`test_the_relaunch_keeps_the_morning`).

## Found

- **A jump in the app's clock ends a waiting reaction by the harness's
  ceiling, not the schedule.** The rate-limited turn's reaction at 02:11
  waited behind the forced determined face (held twice), and the driver
  advanced the clock 5 min before the schedule's real-time timer fired:
  the 1 s tick's 60 s ceiling ended it `no word it finished` (02:16)
  instead of `waited too long`. The steady clock counts through Mac sleep
  and dispatch timers don't, so a sleep should do the same. Added to
  [PLAN.md](../../../PLAN.md) §3; not fixed here (it's the runtime's
  moment path).

## Checks that ran

- `make build`: passes.
- `make -C internal test`: 206 of 206 pass, the two debug-log tests
  (`testDebugModePrintsEverythingAndStartsItsLogAfresh`,
  `testDebugModeKeepsTheLastTenLaunches`) among them.
- `internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests`:
  42 tests pass, `test_day.py`'s 15 among them (the fixture's counts,
  chirp and needs-you rules, midnight, dropped passes, the CLI).
- `python3 -m unittest discover -s internal/tools/webcam/tests`: 3 pass.
- `make -C internal fw-test`: 111 of 111 pass. `make -C internal sim`:
  11 scenarios, no expect failures, no new or changed pictures. Nothing
  here touches the firmware.
- `make -n day` and `make -n day DATE=2026-09-28` print the commands the
  docs give.

## Proposals

1. **`Boop --headless --clock-ms N`**, starting the headless clock at a
   given wall time: simulated days could start at 09:00 and a relaunch
   could carry on from where the last launch's clock ended.
2. **`boopctl day --json`**, for evals or a later popover pane showing
   "today".
3. **Per-session time** (working, waiting on you, idle) from `status`
   lines' `sessions`, if the owner wants to see where the agents' day
   went and not only Boop's.
