# Tuning Boop's brain for a real day (tune lane, 2026-09-28)

Tonight's goal: when the owner uses Boop tomorrow, the lasting **mood**
should change less, and only for something that lasts, while
**reactions** should be vivid, even a little too much. All of it through
steering text, so tomorrow's tuning is a text edit, plus two option
texts in code where the text alone didn't hold.

## What was wrong

In the owner's real log on 2026-09-27 (`boop.log`, summarised in
`/tmp/boop-baseline-real-log.txt`), Jev moved the mood 11 times in the
21:00 hour, between happy, proud, excited and grumpy, once after a
22-second turn, and 3 of those in 5 s look like the dashboard. It made
20 reactions for 28 cheers that hour, and 5 for 12 finished turns from
22:00 to 22:12, almost all without a face (faces were new). That run
used the steering from before the reaction-faces and loops changes.

To measure main as it is now (7f5d10ff) the same way before and after,
this lane wrote a scripted working day: `internal/tools/workday/`
([EVALS.md](../../../EVALS.md) §5). It replays an 8-hour day of hook
events (193 turns on four threads, tests failing and coming back, a
22-minute turn, a stopped turn, lunch with its heartbeat, poke streaks,
a 14-minute turn ending with failing tests, an hour of quick wins, a
16-minute docs turn) through `Boop --headless --brain jev` on a
compressed clock, with a fake device that plays each reaction, and
reports hour by hour. `workday.py plan` prints the story. Same seed
(1) before and after, and every side run twice, since Jev is
stochastic; the two runs of a side came out nearly the same.

Main on that day did what the owner saw, only more of it: 52 and 53 mood
changes, 19 in the 14:00 hour, 17 and 18 of them on a routine line
(excited after a 40-second turn, back to happy at the next turn start),
and excited was the mood for about 400 of the day's 570 minutes. It reacted
240 times, but weakly: a curious face at a third of turn starts, proud
at any turn of a few minutes, and happy or excited at most short ones,
while a 14-minute turn ending with its tests failing got a grumpy
"again", held once.

## What changed

- **The guide:** the reaction is the moment, the mood the backdrop (a
  happy Boop makes a grumpy face at a failure and stays happy). Moods
  change only for MOOD's reason to leave, never for one routine turn,
  and go back to happy once HISTORY no longer shows the change, or
  after an hour with nothing. 299 → 275 tokens.
- **The mood files:** each says what it stays through (routine turns,
  even a few minutes long; a first failure; a stopped turn; a first poke
  streak) and leaves only for something lasting: determined at two
  failures in a row, grumpy at three or when poked again right after,
  proud when what failed twice or more finally works, and, when a turn
  of 10 minutes or more ends, excited if nothing failed, proud if it
  fought through failures, sad if it failed. Every mood but happy goes
  back to happy once HISTORY no longer shows it coming.
- **The boop personality:** reacts to anything that stands out, with a
  strong face that fits whatever the mood (determined or grumpy at a
  failure, proud at a fix, sad when a big turn fails, excited at a big
  win), held longer for bigger moments; a small face for routine
  finishes (a long turn happy, or excited when its checks passed; a
  short one only when they did); nothing for a turn starting. 15
  Examples, up from 6. 205 → 582 of its 600 tokens.
- **Two `mood` options in code** (`MoodAction.moods`), because the text
  alone didn't hold over two iterations: `excited` no longer means
  "several wins in a row" (a turn of a few minutes kept making Boop
  excited even with happy's file saying it stays happy through those),
  and `grumpy` means "poked again right after the last time", each with a
  `not_for`. The first worked: excited for a 20-minute clean finish was
  at 0.39 to 0.61 with the text alone and is at 0.92, and no turn of a
  few minutes made Boop excited again (two or three a run before). The
  second didn't: the text took a first poke streak's grumpy from 0.93 to
  0.83 and the option to 0.8, so it still makes Boop grumpy, an open item
  in [PLAN.md](../../../PLAN.md) §3.
- **Settings' line for boop** now says what it does: "Reacts to anything
  that stands out, and with a small face to routine work."

## The working day, before and after

Two runs each, same seed, `jev:jev-latest`. "On a routine line, not a
fade" counts mood changes on a turn start or a clean finish under 10
minutes, other than going back to happy (which is the fade the guide
asks for). The full reports, hour by hour with every mood change, are in
[day-reports.md](day-reports.md); every reaction of the first after run
is in [after-1-reactions.tsv](after-1-reactions.tsv).

| Hour | Turns | Mood changes, before | after | On a routine line, not a fade, before | after | Reactions, before | after |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 1, 1 | 0, 0 | 1, 1 | 0, 0 | 28, 29 | 17, 17 |
| 10:00 | 29 | 10, 10 | 5, 5 | 2, 2 | 0, 0 | 29, 29 | 26, 26 |
| 11:00 | 36 | 5, 5 | 2, 2 | 2, 2 | 1, 1 | 38, 36 | 30, 28 |
| 12:00 | 6 | 1, 1 | 0, 0 | 1, 1 | 0, 0 | 12, 10 | 6, 6 |
| 13:00 | 7 | 8, 10 | 2, 2 | 1, 2 | 0, 0 | 12, 11 | 9, 9 |
| 14:00 | 33 | 19, 19 | 4, 4 | 7, 7 | 0, 0 | 53, 52 | 28, 29 |
| 15:00 | 15 | 2, 2 | 1, 1 | 1, 1 | 0, 0 | 13, 19 | 9, 9 |
| 16:00 | 38 | 2, 3 | 0, 0 | 1, 1 | 0, 0 | 50, 50 | 27, 26 |
| 17:00 | 7 | 3, 1 | 1, 1 | 1, 1 | 0, 0 | 5, 6 | 5, 5 |
| 18:00 | 0 | 1, 1 | 1, 1 | 0, 0 | 0, 0 | 0, 0 | 0, 0 |
| all | 193 | 52, 53 | 16, 16 | 17, 18 | 1, 1 | 240, 242 | 157, 155 |

Mood changes went from 52–53 a day to 16, at most 5 in an hour (the
10:00 hour's test fight: determined, grumpy, proud, back to happy, and a
poke streak's grumpy). Changes on a routine line that aren't a fade went
from 17–18 to 1: in both runs a comeback on the build at 11:08 moved
grumpy to proud one line late, on the next turn start. Happy is now the
mood for 364–372 minutes of the day, excited 81, proud 65–73, grumpy 51
(two poke streaks, open item), sad 6 and determined 4; before, excited
held for 400–410.

**Reactions by kind of line** (both runs):

| Kind of line | Before: reacted/all | Before: faces | After: reacted/all | After: faces |
| --- | --- | --- | --- | --- |
| Notable (failure, fix, failed or stopped turn, turn of 10 min or more, poke streak) | 26/26, 26/26 | grumpy 23, proud 16, curious 7, determined 4, excited 2 | 26/26, 26/26 | grumpy 24, proud 16, determined 8, sad 2, excited 2 |
| Clean finish, 1–10 min | 26/26, 26/26 | proud 49, happy 3 | 26/26, 26/26 | excited 24, happy 22, proud 6 |
| Clean finish, under a minute | 127/157, 128/157 | happy 174, excited 63, proud 18 | 105/157, 103/157 | happy 189, excited 19 |
| Turn start | 61/192, 62/192 | curious 123 | 0/192, 0/192 | – |
| Heartbeat | 0/2, 0/2 | – | 0/2, 0/2 | – |

Every notable line still gets a reaction, now with the fitting face:
determined at a first failure, grumpy with "again" held twice at a
repeat, sad held three times when the 14-minute turn failed, proud held
three times at a comeback. Their holds: once 10, twice 8, three times 8
in the first after run, against once 15, twice 2, three times 9 before.
Every clean finish of a minute or more gets one too, excited or happy
rather than proud. The drop in the total, 241 to 156, is the curious face
at turn starts (123 over two runs) and short finishes with nothing to
show (a turn under 15 s with no checks passed).

**Against tonight's real log,** which is what the owner has seen: 156
reactions for 193 finished turns is 0.81 a turn, against 0.71 in the
21:00 hour and 0.42 from 22:00, and every one now has a face. The face
mix over the day: happy 211, excited 45, grumpy 24, proud 22,
determined 8, sad 2 (two runs); happy is two thirds because most of a
day is routine wins, which get a small happy face. The knobs for
tomorrow are single Examples in `personality/boop.md`: the long turn
(`→ happy, "yay", once`) for how busy routine work is, the short turn
(`→ none`) and the turn start (`→ none`) to add more.

## How it went

| Steering | Mood changes (on routine, not fades) | Reactions | Notes |
| --- | --- | --- | --- |
| main, 7f5d10ff | 52, 53 (17, 18) | 240, 242 | Excited all day; curious at turn starts |
| v1: guide, all moods, personality | 12, 12 (0, 0) | 200, 204 | 19 and 13 passes dropped at the start (Jev cold on new text); proud held for 409 min, since nothing faded; 85% of faces happy |
| v2: fades in each mood file, short turns quiet | 24, 29 (5, 8) | 140, 140 | Excited after turns of a few minutes; a stopped turn made Boop sad |
| v3: happy stays through those | 18, 18 (3, 3) | 168, 166 | Still excited after a few minutes' turn |
| v4: the two `mood` options | 16, 16 (1, 1) | 156, 154 | |
| final (v4, mood files rewrapped) | 16, 16 (1, 1) | 157, 155 | The runs above |

`make eval` was run between them as a warm-up; after v1, every run
started with a one-run eval so Jev had seen the text, and no pass was
dropped again.

## The evals

`BOOP_JEV_KEY=… make eval` on the final steering: **12/12 passed in all
3 runs**, median latency 211 ms, slowest 343 ms (deadline 1250 ms). An
earlier full run on v4, before scenarios 11 and 12 existed, passed 10/10
in all 3 runs.

Scenarios this tuning changed on purpose:

- `02-long-turn`: the 20-minute finish's `mood` was happy or proud; now
  excited or proud. A turn of 10 minutes or more ending is now a lasting
  reason to leave happy, excited when nothing failed.
- `10-run-of-wins`: it wanted four quick clean turns to make Boop
  excited; now they keep it happy (routine wins, however many, don't
  move the mood), and a 12-minute clean turn after them makes it excited
  or proud. That was the flip the owner saw.
- New `11-proud-fades`: proud after a fix stays through a routine turn
  2 min later, and is happy again by one 12 min later, once HISTORY no
  longer shows the change (the fade came on the turn start at 17 min in
  all 3 runs).
- New `12-minutes-turn-is-routine`: turns of 3 and 2.5 minutes get a face
  held once or twice, and leave the mood happy.

`09-failure-worked-through` was briefly changed to keep Boop happy at
two failures in a row, but Jev chose determined there at 0.55–0.73 and
the option says so; two in a row counts as a run of failures, so the
scenario went back as it was. No scenario that tests a rule was
loosened.

[harness/EXAMPLE.md](../../../harness/EXAMPLE.md) and
[harness/HARNESS.md](../../../harness/HARNESS.md) §9 were re-recorded
from run 1 of `04-tests-fight-back` in that final `make eval`
([eval-04-debug.jsonl](eval-04-debug.jsonl) has all three runs, which
made the same picks). The fight now reads: determined "oops" once, then
grumpy "again" twice while the mood turns determined, grumpy "again"
twice as it turns grumpy, and proud "finally" three times as it turns
proud.

## Checks

All on this lane's worktree, with fresh state directories under `/tmp`,
never the everyday app's, and `--link usb:` to the fake device, never
Bluetooth or the board:

- `make build`: builds.
- `make -C internal test`: 205 of 205 passed (the steering's budgets and
  its app copy included).
- `make -C internal fw-test`: 111 of 111 passed.
- `make -C internal sim`: 11 scenarios, no expectation failed, no picture
  changed.
- The tools' tests, run directly since `tools-test` can't rebuild the
  venv in a lane worktree: `boopctl_lib` 27 OK, `webcam` 3 OK, `workday`
  7 OK. `facegen.py --check`: 337 frames match Chrome, nothing changed.
- `Boop --snapshots`: renders and passes its contrast check; the
  Settings pane's new line for boop fits on two lines.
- `make eval`: 12/12 in all 3 runs (above). The working day ran 12
  times: twice on main, twice on each of four drafts, and twice on the
  final steering.

Nothing here touched the board or the webcam.

## Proposals, not done

- **A first poke streak shouldn't move the mood.** Two tries in text
  and one option change left it at 0.8 grumpy. The event line could say
  "for the first time", or the poke could leave the `mood` question
  altogether and stay a face only.
- **Warm Jev up at launch.** On new steering its first 13–19 answers
  took about 1.3 s and were dropped. A throwaway pass when the app
  starts would spare the owner's first minutes after an edit.
- **Curious has no role.** Nothing leads to the curious mood, and its
  face never showed in the day. A turn after a long break, or mixed
  results across threads, could be its reason; the personality has 18
  tokens of room left, so it needs a trim first.
- **A mood that a failure keeps fresh doesn't fade.** Grumpy after the
  10:47 poke streak lasted until a comeback at 11:08, since a build
  failure at 11:05 kept it relevant to Jev. If that reads wrong on the
  device, grumpy's file could say a poke streak's grumpiness fades on
  its own.

## Merged onto main

Rebased onto main at 9315c9b8, whose review lane had already added
scenarios `11-comeback-still-showing` and `12-comeback-that-didnt-happen`
(`EvalTests` names them), so this lane's two became
`13-proud-fades` and `14-minutes-turn-is-routine`; the names above are
as they were run. The pass lines in
[harness/EXAMPLE.md](../../../harness/EXAMPLE.md) gained main's `seen`
field.

Checks on the rebased branch, in its worktree:

- `make build`: builds.
- `make -C internal test`: 242 of 242 passed.
- The tools' tests, run directly: `boopctl_lib` 52 OK, `workday` 9 OK,
  `webcam` 3 OK.
- `workday.py run --brain scripted` (fresh `/tmp` state, fake device):
  193 turns, 403 passes, 0 dropped, all 403 reactions settled `done`
  under main's moment schedule.
- `BOOP_JEV_KEY=… make eval`: **14/14 passed in all 3 runs**, median
  217 ms, slowest 417 ms. Run 1 of `04-tests-fight-back` made
  EXAMPLE.md's picks, with the same states and `seen` equal to `for`.

