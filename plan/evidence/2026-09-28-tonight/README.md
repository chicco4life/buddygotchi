# Morning report: the night of 2026-09-28

Good morning. Overnight, seven lanes of work went onto local `main`, one
after another, and everything was checked again together. Then a second
round ran two more: another race hunt (hunt2) and another tuning pass
(tune2), each with its own check. Everything was checked together once
more at the end. Nothing is pushed.

The short version: Boop should feel calmer and more expressive today.
Its mood now changes only for something that lasts (16 times over a scripted
working day, down from 52). The second tuning made the faces vivid: happy
went from two thirds of the faces to a third, and "yay" from 83% of the
worded reactions to 38%, so failures, fixes and big wins each get their
own face and word. The cost is fewer reactions to quick routine turns.
Behind that, a lot of small races between hooks were fixed, 34 in the
first hunt and 17 in the second, so the screen and what Boop remembers
agree, even across a Mac asleep, a relaunch or a session that ended.
The board runs `main`'s firmware (round 2 changed none) and passed the
pipeline check in round 1. The Jev evals passed 14 of 14 in 2 of 3
full runs this morning; the third lost one pass to Jev's deadline.

Your checks from last evening (1, 2, 3, 4, 5 and 9, nothing noted as off)
are recorded in [PLAN.md](../../PLAN.md) §2. Tonight's work changed what
checks 6, 7, 8, 9, 10 and 12 expect, and their text now says so.

## Start here

In one terminal (Bluetooth, so it's yours to run):

```sh
make debug
```

On its first launch since last night, the app adds Claude's new
`SubagentStop` hook and asks you to restart open Claude sessions. Do that,
then check the hooks from inside one session (check 3 has the full round
trip):

```sh
internal/skills/doctor/doctor.sh
```

In a second terminal, the live dashboard:

```sh
make dash                  # the same as internal/tools/boopctl dash
```

At the end of the day, what Boop did and why, hour by hour. It reads every
launch's log, so restarting the app during the day loses nothing (the last
10 launches are kept):

```sh
make day                   # the newest day in the logs; make day DATE=YYYY-MM-DD for another
```

**To retune the brain.** The knobs are the Examples in
`plan/steering/personality/boop.md`, and each mood's file in
`plan/steering/mood/`. After an edit:

```sh
rsync -a --delete plan/steering/ app/Boop/Resources/steering/   # the app reads only its own copy
BOOP_JEV_KEY=… make eval                                         # every scenario, 3 runs; also warms Jev up on the new text
BOOP_JEV_KEY=… python3 internal/tools/workday/workday.py run --state /tmp/tn-1 --out /tmp/tn-out/1
BOOP_JEV_KEY=… python3 internal/tools/workday/workday.py run --state /tmp/tn-2 --out /tmp/tn-out/2
python3 internal/tools/workday/workday.py report /tmp/tn-out/1/debug.jsonl /tmp/tn-out/2/debug.jsonl
```

`make eval` builds first, and the working day needs that build, since it
runs the headless app. Each day takes about 5 minutes. Run it twice,
because Jev varies, and compare against tonight's numbers below or the
hour-by-hour reports in [tune2-check/day-reports.md](tune2-check/day-reports.md)
(the steering on `main`). The report now lists the words mumbled too.
Without a key, `workday.py run --brain scripted` checks the plumbing only.

`boop.md` is at exactly its 600-token budget, so a new Example needs a
trim first. The two cheapest knobs are in it: the "40 s" bar decides how
often a quick routine finish gets a face (30 s gave about half, 40 s a
third), and the 2-minute Example's "yay" is where most of the "yay"s come
from.

## What to watch for today

- **The mood should be calm.** Mostly happy. A test fight should take it
  through determined, grumpy and proud and back. A long clean finish
  should make it excited. If it changes on a routine turn, note the time;
  `make day` lists every change and what caused it.
- **Strong faces where they fit.** Determined or grumpy at failures,
  proud at a fix, excited at a clean win, sad when a long turn fails,
  curious with "hmm" at a stopped turn. A quick routine finish gets a
  face only with something to show (40 s of work or checks passing), so
  about a third of them do. The second tuning (round 2,
  [tune2](tune2/README.md), [check](tune2-check/README.md)) took happy
  from 67% to about a third of the faces and "yay" from 83% to 38% of
  the reactions with a word. Watch for the same excited
  "…tests!" over and over on a run of quick passing turns: it's an open
  item.
- **A first poke streak makes Boop grumpy.** It's known, and text alone
  couldn't fix it (below).
- **Dropped passes.** When Jev answers after 1.25 s, `make debug` prints a
  dropped pass, and that reaction never comes. Expect a few in clusters,
  and more in the first minutes after a steering edit. The app's
  `boop.log` now also says when Jev did answer
  (`answered after N ms, too late for …`), which is the number to judge
  decision 2 by.
- **Quieter after sleep and restarts.** A turn no longer counts the time
  the Mac slept, so opening the lid shouldn't bring a "very long turn"
  cheer. A session that ended stays ended, so a late hook can't bring it
  back as working or needing you. After a relaunch, a turn Boop only
  joined halfway still cheers when it's done, but the brain isn't told
  about it.
- **Reactions that didn't happen.** `make day` lists them with the
  reason. "waited too long" right after a face over the idle look is the
  known 9-second item.
- **Chirps.** A different request now chirps even when it's the same agent
  and project, such as two worktrees of one repo (check 6), and also
  the first request after you relaunch the app.
- **Codex's automatic reviewer.** A command it approves that runs past
  2 s shows "needs you" and chirps until it ends (check 8). If you see
  it, note it: it's the first real sign of what Codex sends then.
- **A denied subagent** should drop "needs you" as soon as it ends
  (check 7). That's the first real `SubagentStop` Boop will see.

## What needs your decision

1. **The first poke streak.** Jev makes Boop grumpy at 0.65–0.91 whatever
   the text says (five tries). Either leave pokes out of the mood
   question, so they get a face only, or have the event line say it's the
   first streak ([tune-check](tune-check/README.md)).
2. **Jev's deadline.** Even warmed up, Jev drops a few passes over a
   day; one of them was the day's 16-minute finish, and this morning one
   cost a full eval run a scenario. The first round read these as Jev
   taking 1.28–1.33 s, but hunt2 found that was the deadline's own timer
   firing late. It now fires on time and `boop.log` records when Jev
   really answered, so a day of `make debug` gives the number to decide
   on. Raising the deadline probably costs nothing, since no reflex waits
   on the brain. A throwaway pass at launch would cover the cold start.
3. **Two parallel subagents' test results.** Today the one that lands
   last decides whether the turn failed. The alternative is to fail any
   turn that leaves a check failing, but that changes sequential turns
   too (race report 29, [core](core/README.md)).
4. **Curious has no way in as a mood.** Its face now shows at a stopped
   turn, with "…hmm", but nothing leads to the mood. Give it a reason
   (a turn after a long break, mixed results), or drop it.
5. **A face held for its loops blocks the next reaction.** Over the idle
   look one loop lasts up to 9 s, since the idle designs loop every 9 s,
   and a face Jev holds two to four times holds the line for 16–36 s.
   Another reaction waits at most 5 s, so another thread's failure
   meanwhile gets no face. The options are a shorter idle loop, a cap on
   a face's first loop, or letting the next reaction end a held face
   once its mumble has played ([hunt2](hunt2/README.md), report 16).
6. **When "needs you" starts, a waiting reaction** is sent at once for the
   board to skip, as [harness/DECISIONS.md](../../harness/DECISIONS.md) §5
   says. It could stay queued instead, and play if "needs you" clears
   within 5 s ([review-check](review-check/README.md)).
7. **The cheer's card drops 6 px** each time a cheer of two or more loops
   starts over. The rules' cheer is one loop, so only the dashboard and
   `play cheer --loops` show it. Fix it only if you see it on the panel
   ([firmware](firmware/README.md)).
8. **Jev repeats a reaction once the last one has ended.** A run of
   quick turns with their tests passing gets the same excited "…tests!"
   up to 8 times in a row, and a comeback's finish repeats the fix's
   proud "…finally!" under a minute later. Text didn't stop it. Either
   the state names Boop's last reaction and how long ago it was, or those
   quick passes get no face (then happy climbs to about 42% of faces)
   ([tune2-check](tune2-check/README.md)).
9. **Fewer reactions, stronger ones.** Round 2 reacts to 0.47–0.49 of
   finished turns, from 0.70 after round 1. Every notable moment and
   nearly every turn of a few minutes still gets one; the drop is all
   quick routine turns, which now get a face only with something to
   show. If Boop feels too quiet, lower boop.md's "40 s" bar.
10. **A `Stop` another hook blocks still cheers twice.** Keeping
    `stop_hook_active` through `boop-hook` and ending such a turn with
    no second cheer would make one prompt one turn. It touches the hook,
    the adapter and the core, so the spec first ([hunt2](hunt2/README.md),
    report 21).
11. **A brain pass already running when "needs you" starts** can still
    change the mood when it lands, which redraws the needs-you face. The
    mood could sit out passes while something needs you (report 15's
    other half).
12. **An ended session ignores its hooks for a day** unless it starts
    again. That hides a real request only if an agent asks after its own
    `SessionEnd` with no `SessionStart` first, which no recording shows.
    Accept it, or record a session that exits with a background
    subagent running ([hunt2](hunt2/README.md)).

## Still open, no decision needed

- **Some things need a real session recorded.** These are what a message
  queued mid-turn sends, what a background subagent sends after the
  main `Stop`, a real `SubagentStop`, and a real Codex session with an
  approval, a failing test and its automatic reviewer on. Three race
  reports from round 1 (16, 24, 28) and two from round 2 (8, the
  reviewer, and 12, a Codex request landing just after its own
  `Interrupt`) wait on these.
- **The pipeline check cuts one reaction for no real reason.** Its
  fixture jumps the app's clock 40 s while a reaction plays, so the app
  stops waiting and the next reaction cuts it. Tonight's run showed it
  again. It's a test artefact only.
- **A session's project follows `cd` into subfolders.** It should walk
  up to the repo.
- **The dashboard's recorded test run is old.** It has no started
  actions, loops or `attn.id`, and should be recorded again.
- **The webcam check (L3) was a short one.** At about 05:10 the cheer,
  two held reactions, a tap and four moods' looks all passed on camera
  ([webcam](webcam/review.md)), but sad's tears were too faint to see
  and nothing asleep, without the app, or over Bluetooth was filmed.
  The board was yours from 06:25, so round 2's final check didn't rerun
  the pipeline check; round 2 changed no firmware.
- **Heap headroom is about 14 KB** over the 60 KB target, so anything that
  adds RAM needs measuring.
- **USB drops the odd byte**, which is why the soak retries a reply.

All but the webcam are open items in [PLAN.md](../../PLAN.md) §3, as
are the decisions above other than 6 and 9.

## The numbers

### The brain over a working day

The scripted day has 193 turns on four threads, with a test fight, a
22-minute turn, lunch, poke streaks, a 14-minute turn that fails, and an
hour of quick wins. It ran twice on each side, with the same seed. Pairs
below are the two runs.

**Round 1, the mood** ([tune](tune/README.md)):

| Hour | Turns | Mood changes, before | after | Reactions, before | after |
| --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 1, 1 | 0, 0 | 28, 29 | 17, 17 |
| 10:00 | 29 | 10, 10 | 5, 5 | 29, 29 | 26, 26 |
| 11:00 | 36 | 5, 5 | 2, 2 | 38, 36 | 30, 28 |
| 12:00 | 6 | 1, 1 | 0, 0 | 12, 10 | 6, 6 |
| 13:00 | 7 | 8, 10 | 2, 2 | 12, 11 | 9, 9 |
| 14:00 | 33 | 19, 19 | 4, 4 | 53, 52 | 28, 29 |
| 15:00 | 15 | 2, 2 | 1, 1 | 13, 19 | 9, 9 |
| 16:00 | 38 | 2, 3 | 0, 0 | 50, 50 | 27, 26 |
| 17:00 | 7 | 3, 1 | 1, 1 | 5, 6 | 5, 5 |
| 18:00 | 0 | 1, 1 | 1, 1 | 0, 0 | 0, 0 |
| **Day** | **193** | **52, 53** | **16, 16** | **240, 242** | **157, 155** |

- **Mood.** Changes on a routine line (other than fading back to happy)
  went from 17–18 a day to 1. Before, Boop was excited for about 400 of
  the day's 570 minutes. After, it's happy for 364–372 of them, excited
  81, proud 65–73, grumpy 51, sad 6 and determined 4.
- **Reactions.** There are fewer on the scripted day (0.81 a finished
  turn, from about 1.25) because the curious face at a third of turn starts is
  gone. Against what you saw on the 27th, though, there are more: 0.42–0.71
  a cheer then, and 97 of those 102 reactions had no face. Every notable
  line (26 of 26) and every clean finish of 1–10 minutes still gets one.
- **The faces**, both runs together:

  | | happy | excited | proud | grumpy | determined | sad | curious |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | Before (482) | 37% | 13% | 17% | 5% | 1% | 0 | 27% |
  | After (312) | 68% | 14% | 7% | 8% | 3% | 1% | 0 |

  Happy dominates because most of a day is routine wins, which get a
  small happy face. The bigger moments now get the fitting face, held
  longer: determined "oops" at a first failure, grumpy "again" twice at a
  repeat, proud "finally" three times at a comeback, sad three times when
  the 14-minute turn failed.
- **The check's reruns** agreed: 14 and 16 mood changes, 150 and 156
  reactions ([tune-check](tune-check/README.md)).

**Round 2, the faces and words.** Round 1 left the faces mostly a happy
"yay". The second pass, text only, asked for a strong face wherever one
fits, and a face on a quick routine turn only with something to show.
Before is `main` after round 1 ([tune2](tune2/README.md)); after is the
steering on `main` now, with its check's fix for sad
([tune2-check](tune2-check/README.md)).

| Hour | Turns | Mood changes, before | after | Reactions, before | after |
| --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 0, 0 | 0, 0 | 17, 17 | 15, 15 |
| 10:00 | 29 | 5, 5 | 5, 5 | 26, 26 | 17, 17 |
| 11:00 | 36 | 2, 2 | 2, 2 | 27, 27 | 17, 17 |
| 12:00 | 6 | 0, 0 | 0, 0 | 6, 6 | 5, 5 |
| 13:00 | 6 | 2, 2 | 2, 2 | 8, 8 | 9, 9 |
| 14:00 | 34 | 4, 4 | 4, 4 | 29, 30 | 16, 16 |
| 15:00 | 15 | 1, 1 | 1, 1 | 9, 9 | 7, 7 |
| 16:00 | 38 | 0, 0 | 0, 0 | 25, 25 | 21, 17 |
| 17:00 | 7 | 1, 1 | 1, 1 | 5, 5 | 4, 4 |
| 18:00 | 0 | 1, 1 | 1, 1 | 0, 0 | 0, 0 |
| **Day** | **193** | **16, 16** | **16, 16** | **152, 153** | **111, 107** |

- **The faces**, both runs together:

  | | happy | excited | proud | grumpy | determined | sad | curious |
  | --- | --- | --- | --- | --- | --- | --- | --- |
  | Before (305) | 67% | 14% | 8% | 8% | 3% | 1% | 0 |
  | After (218) | 33% | 39% | 12% | 10% | 4% | 1% | 1% |

- **The words.** "Yay" went from 83% of the reactions with a word to
  38%. After, over both runs: yay 58, tests 46, finally 14, again 14,
  oops 8, nope 6, ugh 4, hmm 2, and 66 with no word.
- **Where they go.** Every failure, fix, comeback, poke and failed turn
  still gets its face (26 of 26 notable lines). A quick finish with its
  tests passing gets an excited "…tests!"; one with 40 s of work gets a
  small happy face and no word; the rest get nothing, so about a third
  of quick finishes react. The stopped turn is a curious "…hmm". Nothing
  is absurd: no sad or grumpy face at a clean finish, no happy one at a
  failure, and nothing at turn starts or heartbeats.
- **The mood stays calm**: 16 changes a day, as before. The lane's text
  first let a sad Boop turn determined at the next failure, in half the
  runs; the check's line in `sad.md` holds it sad at 0.96.
- **The cost.** 0.47–0.49 reactions a finished turn, from 0.70, all of
  it quick routine turns (decision 9). And the same excited "…tests!"
  can come up to 8 times in a row (decision 8).

### Evals

`BOOP_JEV_KEY=… make eval` on round 1's `main`: **14/14 scenarios in all
3 runs**, median 228 ms, slowest 568 ms ([final/eval.txt](final/eval.txt)).
Both round-2 lanes and the tune2 check passed 14/14 in all 3 runs, each
on its own text.

On the final `main`, three full runs this morning: 14/14 twice (medians
212 and 220 ms, slowest 336 ms), and once 13/14, because one pass of
`02-long-turn` came after the 1.25 s deadline and was dropped
([final/eval-round2.txt](final/eval-round2.txt)). Every answer Jev did
give was right. It's decision 2 again, now in an eval.

Scenarios whose expectations changed tonight:

- `02-long-turn`: a 20-minute finish now makes the mood excited or proud,
  where it was happy or proud.
- `10-run-of-wins`: four quick wins now keep Boop happy. A 12-minute clean
  turn after them makes it excited or proud.
- New `11-comeback-still-showing` and `12-comeback-that-didnt-happen`
  ([review](review/README.md)). Jev failed 11 in 3 of 3 runs at first: it
  repeated a proud "finally" that was still on screen. `react`'s `none`
  option now covers a reaction Boop is still making.
- New `13-proud-fades` and `14-minutes-turn-is-routine`
  ([tune](tune/README.md)). The second tuning broke 13 at first (proud
  stopped fading); `proud.md` now ties staying proud to HISTORY still
  showing the change, and it passes again. No scenario changed in
  round 2.

No scenario that tests a rule was loosened.

### Firmware

- **Heap.** The least free heap is 73,704 B over a 35-minute soak (24 B
  of drift), and 73,764 B after tonight's flash and pipeline check,
  against a 60 KB target. Static RAM is 45,804 B, and flash is 1,102,695 B
  (56.1%).
- **Soak.** 35 minutes over USB, with 598 states and 621 moments, 246 of
  them reactions with ids. Each got exactly one `ended`. No reset, no
  lost or torn line, and no audio error.
- **Sanitizers.** The device code ran under ASan and UBSan, fuzzed with
  500,183 lines in all (300,111 in the lane, 200,072 in its check), with
  no errors. Every waited moment got one `ended`. The Swift suite under
  TSan passed with no warnings.
- **Motion.** 126 transitions and 76,795 frames in the simulator had no
  hard cut. With the blink removed, the same sweep found 238, so the
  detector works.
- **Speed.** `perf --motion` gives 6 fps at least and 15.5 on average. The
  slowest frame took 14.2 ms of the 40 ms allowed. The old 10 fps floor
  dated from the drawn face. The mood designs step only a few times a
  second, so the rule is now a frame in every second of motion, none over
  40 ms. The median draw is 1.0 ms and the median push 8.8 ms.

([firmware](firmware/README.md), [its check](firmware-check/README.md))

### The final check, on `main`

Round 1's check ran on `e13cc124`; round 2's on `9146e378`, after both
round-2 lanes merged. Where a row has two results, round 2's is second.
Round 2 changed no firmware, designs or simulator code.

| Check | Result |
| --- | --- |
| `make build` | Builds, both rounds |
| `make -C internal test` | 242 of 242; then 258 of 258 (16 new from hunt2) |
| `make -C internal fw-test` | 114 of 114, both rounds |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 changed pictures, both rounds |
| boopctl, webcam and workday tests | 53, 3 and 9 OK; then 53, 3 and 10 OK |
| `facegen.py --check` | 337 frames of 30 scenes match Chrome (round 1 only) |
| `make flash`, `boopctl ping` | Firmware `e13cc1245e`, heap 74,076 B free, 73,960 B at the least. Still `main`'s firmware; not reflashed in round 2 |
| `make -C internal e2e` | Round 1: PASS, 17 of 17 checkpoints, 5 of 5 expected events, hook to board p50 39 ms and p95 64 ms. All 9 brain moments got their `ended`: 7 done, 2 cut, one by the Codex cheer and one by the clock-jump artefact ([final/e2e.txt](final/e2e.txt)). Round 2: skipped, because you had the board from 06:25 |
| `make eval` with Jev | 14/14 in all 3 runs; then 14/14, 14/14 and 13/14 over three full runs (one late pass, above) |
| Scripted working day | 193 turns, 403 passes, 0 dropped, all 403 reactions `done`, both rounds; 2 min 21 s in round 2 ([final/workday-scripted.md](final/workday-scripted.md)) |
| `cmp CLAUDE.md AGENTS.md`, `diff -r plan/steering app/Boop/Resources/steering` | Both silent, both rounds |

## Bugs found and fixed

Each one has a test that fails without its fix, unless it says otherwise.

**Loops and pending, reviewed** ([review](review/README.md),
[review-check](review-check/README.md)). A three-way review found 15
problems, which came down to eight. The builders had reported 6 more.

| What was wrong | How it was found | Pinned by |
| --- | --- | --- |
| Nothing re-ran the moment pump when a cheer, tap, `ended` or "needs you" freed the line, so a waiting reaction sat and was dropped | Review, then reproduced on the old code | `RuntimeTests.testWhatFreesTheLineSendsTheNextAtOnce` |
| The Mac ignored the board's `ended` and taps. It waited on its own estimate (up to 9 s a loop) and dropped the next reaction, or cut a face still showing | Review and the builders | `testTheDeviceSaysWhenTheLineIsFree` |
| After a tap or "needs you" ended the cheer, the Mac timed the next face by the cheer's shorter loop and gave up early | Review | `testTheScheduleTimesAMomentByTheDesignShowing` |
| Moment ids restarted at 1 each launch, so the board mixed a new reaction up with the last launch's | Review and the builders | `testMomentIdsDifferEachLaunch`, firmware `test_a_new_launchs_moment_is_its_own` |
| A face ended early after its mumble had played counted as `cut`, so Jev might say it again | Review | firmware `test_a_waited_moment_says_how_it_ended` |
| No eval covered a reaction still showing. Once one did, Jev repeated "finally" while it was still on screen | Review, then the new eval (0 of 3) | Scenarios 11 and 12, `EvalTests.testAStepSaysHowItsReactionEnds` |
| A reaction that had waited too long stayed "(in progress)" for up to 36 s | Review | `testAWaitIsCountedToItsTurn` |
| The pump's timer fired 0.3 s late and dropped a reaction at 4.84 s | The builders' pipeline run | `testAWaitIsCountedToItsTurn` |
| With no board, a failed reaction still held the line | Reading the code | End of `testWhatFreesTheLineSendsTheNextAtOnce` |
| The pipeline check's Claude fixture sent a hook order Claude never sends, so an expectation always failed | The builders | `make -C internal e2e` itself |
| A settle during a Jev answer made rebuilding a pass's state from `debug.jsonl` inexact | The builders | `HarnessTests.testALoggedStateIsRebuiltFromTheLogWithItsSettles` |
| No test covered the pump call when "needs you" starts | Deleting lines one at a time | The runtime test above, extended |
| After the Mac slept, the pump kept a timer the clock had passed, making a reaction up to 5 s late | Reading the code | `testATimerTheClockHasPassedIsReplaced` |

**The core under racing hooks** ([core](core/README.md),
[SubagentStop](core-subagentstop/README.md), [core-check](core-check/README.md)).
Five race-hunter agents fed awkward hook orders into the headless app with
the simulated board, and filed 38 reports. The screen always matched what
the core sent. What went wrong was the core's picture of the agents, and
what it told the brain.

| What was wrong | Pinned by (in `CoreNeedsYouTests` unless named) |
| --- | --- |
| A denied subagent's "needs you" stayed up until the main agent's `Stop`, or 10 minutes (PLAN's A3 item) | `testASubagentsEndAnswersOnlyItsOwnRequest` and two more, `InstallerTests.testAnInstallWithoutSubagentStopIsRepaired`, `ReplayTests.testADeniedSubagentsEndAnswersItsRequest` |
| A turn finishing while something else needed you still "cheered", and told the brain so | `testAFinishWhileSomethingNeedsYouDoesntCheer` |
| A different request with the same agent and project took over in silence | `testTheRequestShownHasItsOwnNumber`, `testASecondAskerAnsweredShowsAnotherRequest`, firmware `test_a_different_request_with_the_same_names_chirps` |
| Two requests in the same millisecond swapped places and chirped twice | `testRequestsInTheSameMillisecondKeepTheirOrder` |
| An MCP dialog right after an approval or Esc never showed | `testAnElicitationRightAfterAClearShows` |
| A permission notice arriving late, after the turn, lit amber for up to 10 minutes | `testALateNotificationAfterTheTurnEndedIsIgnored` |
| A Codex request answered before it showed was still recorded as needing you | `testACodexRequestAnsweredBeforeATickShowsItIsNeverRecorded` |
| A sibling subagent's folder renamed the project on the strip, chirping at each flip | `testAWaitingSessionKeepsItsProject` |
| Answering a request didn't wake the brain (approved-then-failing tests, for one) | `testAnEventThatAnswersTheRequestWakesTheBrain` |
| After Esc on a subagent's prompt, amber stayed about 11 minutes | `testClaudesIdleNoticeAnswersEveryRequest` |
| A result landing just after Esc restarted the turn. Codex stayed "working" for an hour | `testALateResultDoesntRestartAStoppedTurn` |
| A notice before its own request made it anyone's, and a sibling's call cleared it | `testANotificationBeforeItsRequestBecomesThatRequest` |
| A stale idle notice just after a new prompt ended the new turn | `testAStaleIdleNoticeDoesntStopANewTurn` |
| A parallel call's result cleared a prompt, or an MCP dialog, still on screen | `testAParallelCallsResultDoesntAnswerTheRequest` |
| A subagent's MCP dialog, or its turn-level hooks, acted for the whole session | `testASubagentsElicitationIsItsOwn`, `testASubagentsTurnLevelHooksAreItsOwn` |
| The Mac's moment schedule kept timing a cheer the board had cut, and judged a waiting reaction only when its turn came | `testNeedsYouEndsWhatTheScheduleThoughtWasPlaying`, `testTheScheduleFollowsTapsCheersAndTicks`, `testAWaitingMomentIsDroppedAtFiveSecondsWhateverPlays` |
| The stale-notice guard also swallowed a real notice after a background subagent's call | `testAStaleIdleNoticeDoesntStopANewTurn` (extended) |
| A subagent ending could clear a request that came as a notice alone, and no test noticed | `testASubagentsEndLeavesOtherAskersWaiting`, `CoreFuzzTests` |
| The specs and the new fixture gave `PermissionRequest` a `tool_use_id` that neither agent sends | The fixture and ADAPTERS.md §3 (no test) |

Each fix was seen failing before it went in. `CoreFuzzTests` now sends
20,000 random hooks and checks that the brain's record and the screen stay
in step.

**Firmware** ([firmware](firmware/README.md), [check](firmware-check/README.md)):

| What was wrong | How it was found | Pinned by |
| --- | --- | --- |
| `loops` too big for an int, or a fraction, played once | Probing the parser with the fuzz's edge values | `test_device`'s loops cases |
| `vol`, a word's place and a syllable's ms had the same problem | The independent check | `test_say_and_volume_are_held_in_range` |
| The no-hard-cut test missed moods, reactions and anything ending on its own | Mutants passed it | `test_nothing_cuts_hard_as_it_plays_out`, the extended `test_no_change_ever_cuts_hard` |
| `perf --motion`'s 10 fps floor failed a board that drew every change in 14 ms | Running it on the board | `PerfTests` |
| `boopctl soak` never sent a reaction, or counted `ended` and lost lines | Reading it | `SoakTests` |

**Tools and logs** ([daylog](daylog/README.md), [daylog-check](daylog-check/README.md),
[tidy](tidy/README.md), [tune-check](tune-check/README.md)):

| What was wrong | How it was found | Pinned by |
| --- | --- | --- |
| Relaunching in debug mode emptied `debug.jsonl`, losing the morning | The lane's brief | `RuntimeTests.testDebugModeKeepsTheLastTenLaunches` |
| `boopctl day` counted the dashboard's forced reactions as the brain's | Counting a day by hand | `test_day.py` (the fixture's counts, `SmallDayTests`) |
| Dropping `idle` from `state` would have hidden a second idle session from the popover | Reading what the count did | `testASessionListChangeTheSnapshotDoesntShow`, `testASecondIdleSessionReachesTheStatusNotTheDevice` |
| `workday.py` moved the clock before a reaction's `ended`, so 7–12 reactions a run looked unplayed | Tracing one moment in `boop.log` | `SettleTests` |

**Round 2: the second race hunt** ([hunt2](hunt2/README.md), its
check in the lane's notes). Five hunters filed 22 more reports, each
reproduced by a second agent. 17 were real bugs, now fixed; one was a slip in a spec;
four are open (report 8, 12, 16, and the rest of 21). Most were the core
losing track of a turn at its edges. The check reverted each fix in turn
and saw its test fail.

| What was wrong | Pinned by |
| --- | --- |
| After the 10-minute safety net, Esc or an interrupt was dropped, and the stopped call's late result restarted the turn: "working" and chatter for up to an hour (reports 1, 9) | `CoreAgentWorkTests.testAStopAfterTheSafetyNetEndsTheOpenTurn` |
| A Mac asleep mid-turn counted as turn time, so a 2-minute turn read "done after 8 h, a very long turn" and Jev reacted to a big finish (2) | `CoreAgentWorkTests.testTheMacAsleepIsntTurnTime`, `RuntimeTests.testTheCoreHearsHowLongTheMacSlept` |
| A `Stop` with no turn open read "turn 0 … after 0 s" and cheered; a turn Boop joined after a relaunch was timed from the relaunch (3, 11, 22, part of 21) | `testAFinishWithNoTurnOpenIsNothing`, `testATurnBoopJoinedPartwayEndsWithoutAnEvent`, `testATurnACallOpensCountsItsOwnTools` |
| A hook arriving after `SessionEnd` brought the session back: needing you (10 minutes of amber, silencing others), working for an hour, or idle at full backlight for a day (10, 18, 19, 20) | `CoreAgentWorkTests.testALateHookAfterSessionEndDoesntBringItBack` |
| A relaunched app numbered its first request 1 again, so it didn't chirp (7) | `RuntimeTests.testRequestNumbersDifferEachLaunch` |
| A 1 s link blip, or a tap the board handled first, freed a reaction's line on the Mac, so the next reaction cut one still playing (5, 6) | `RuntimeTests.testALinkBlipKeepsTheLineForTheReactionPlaying`, `testATapLeavesTheLineToTheDevicesEnded` |
| A mood set from the dashboard during a brain pass was undone by that pass (13) | `HarnessTests.testAnActionTheDashboardChangedDuringAPassSitsItOut` |
| The 1.25 s deadline fired at up to 1.33 s, and a dropped pass logged the timer's time as Jev's (14) | `HarnessTests.testTheDeadlineComesOnTime`, `testALateAnswerIsStillTimed`, `testJevsAnswerAndRetry`, `test_day.py` |
| A pass that waited behind another started, and asked the brain, while something needed you (15) | `HarnessTests.testAWaitingPassDoesntStartWhileSomethingNeedsYou`, `RuntimeTests.testNoWaitingPassStartsWhileSomethingNeedsYou` |
| With chatter, a face still playing fell out of HISTORY after 40 newer events (17) | `HarnessTests.testAReactionInProgressStaysInHistory` |
| ARCHITECTURE.md §4 put a new day's snapshot under "the day before" (4), and ADAPTERS.md §4 said a request Codex's reviewer approves never shows (8) | Wording only |
| The check found two leftovers: ARCHITECTURE.md's moment-pump row and a code comment still described the old line and request numbers | Wording only |

**Round 2: the second tuning** ([tune2](tune2/README.md),
[tune2-check](tune2-check/README.md)). All steering text, checked with
the working day and the evals rather than unit tests:

- Most faces were a happy "yay" (67% and 83%); now they fit the moment
  (above).
- Quick routine finishes got a face every time; now only with something
  to show.
- In one draft a grumpy Boop made a grumpy face at a clean win.
  `grumpy.md` now says a win gets a grudging proud.
- A stopped turn got a wordless grumpy face; it's a curious "…hmm" now.
- The new text stopped proud fading (`13-proud-fades`, 0 of 3); fixed in
  `proud.md`, 3 of 3.
- A sad Boop turned determined at the next failure in half the runs;
  fixed in `sad.md` by the check.
- `workday.py report` couldn't show the words; it does now, pinned by a
  new workday test.
- [harness/EXAMPLE.md](../../harness/EXAMPLE.md) and HARNESS.md §9
  quoted the old personality text; both are re-recorded from a real eval.

**Fixed while merging, and in this final check:**

- The recorded day for `boopctl day` still sent `idle` and `wait`
  (`1b1f56b8`). Its summary is byte-identical without them.
- A runtime test no longer compiled once `state` lost `idle` and `wait`
  (`c40a2f26`).
- The core and review lanes had each fixed the moment schedule their own
  way. The merge kept the review lane's design, plus the core lane's pump
  on every tick, its firmware forgetting a reused id, and its tests. This
  also settles two things the lanes left open: the board handling a
  repeated id, and a tap's wiggle losing time in the schedule.
- `boopctl day` counted chirps by agent and project only, but the board
  now chirps whenever `attn.id` changes (`8560cf59`). Found by reading
  the merged code. Pinned by `test_a_different_request_with_the_same_names_chirps`
  in `test_day.py`, which fails on the old count.
- Round 2's merges had one conflict: both lanes added decision-log rows
  at the end of ARCHITECTURE.md, and the merge kept all of them. The final check found nothing
  broken; its only finding is the late eval pass above.

## What merged

On local `main`, oldest first. The hashes are `main`'s; the lanes'
READMEs quote the hashes from before the rebase.

**A14, loops and pending** (evening of the 27th, before the lanes;
[loops-pending](loops-pending/README.md)):
`4fd15d32`, `d88349dd`, `e5a7ff8e`, `eef3d1dd`, `139b86cd`, `5337a1c2`,
`ea7f8133`, `ddffb54b`, `d9030b5a`, `94004b55`, `32a18547`, `7f5d10ff`.
These are the started actions, `(in progress)`, the board's `ended`, and loops.

**tidy** ([README](tidy/README.md)):

- `91e8b058` The state line no longer carries idle and wait; the dashboard counts them itself
- `ecb7f437` The scenarios and boopctl's own state lines drop idle and wait too
- `a2aafe9f` The firmware's moment tests stop sending a ttl nothing reads
- `243563fb` The tidy lane's evidence
- `8d0245a7` An independent check of the tidy lane

**daylog** ([README](daylog/README.md), [check](daylog-check/README.md)):

- `40b45026` Debug mode keeps the last ten launches' debug.jsonl
- `30bfe8eb` boopctl day sums up a day of debug logs by the hour
- `832c51e2` The daylog evidence
- `24de6a3a` boopctl day counts the brain's reactions from its react actions, and the dashboard's apart
- `e3ce1ecf` The daylog check's evidence
- `1b1f56b8` The recorded day's states drop idle and wait (merge fix)

**core** ([race hunt](core/README.md), [SubagentStop](core-subagentstop/README.md), [check](core-check/README.md)):

- `a10b85e8` A denied subagent's request clears when that subagent ends
- `00ddf7e4` Its evidence
- `9f5c6f26` An event that answers the last request wakes the brain
- `57454c13` A turn that finishes while something needs you doesn't cheer, or say it did
- `e72176e1` A Codex request answered before a tick shows it is never recorded as needing you
- `7dc6e71a` An Elicitation is a request of its own, and a Notification is judged as a copy
- `133f1d4c` Claude's idle notice answers a subagent's request too
- `c7cc092d` A result that lands after its turn stopped doesn't start the turn again
- `d91b5828` A session keeps its project while its request waits
- `aecf00b8` Each request shown has a number, so a different one chirps even in the same project
- `cc598257` The result of a call made alongside the one that asks doesn't answer it
- `1f0041ac` The moment schedule hears what the device cut, and drops a late reaction on time
- `b6d13bcc` After the Mac app restarts, a reused moment id gets its own end on the device
- `a6c62fe9` A stale idle notice doesn't stop a new turn, and a subagent's turn-level hook is its own
- `79b5fc07` A Notification is a late copy only of the kind the cleared request sends
- `76faf5f0` The device's ended frees the turn for the next reaction
- `0770645f` A fuzz test keeps the core's record and the screen in step
- `b50c59c5` The runtime test checks that needs you ends the cheer in the moment schedule
- `e316d8c9` The race hunt's evidence
- `e25fc26b` A subagent's end is pinned to answer only its own request, under random traffic too
- `91530183` PermissionRequest has no tool_use_id, as the specs and the new fixture now say
- `24b83ddf` A parallel call's result doesn't hide an MCP dialog
- `fec87ac4` A stale idle notice is judged from your last prompt, not from any turn's start
- `4d095571` The core check's evidence
- `c40a2f26` The runtime test's needs-you snapshot drops idle and wait (merge fix)

**review** ([README](review/README.md), [check](review-check/README.md)):

- `3c423a5a` A reaction waits for the device's word that the last one ended, and nothing frees the line unheard
- `a6eeef12` A launch's moment ids start somewhere random
- `5e29386f` A reaction's face ended early after its mumble leaves the reaction done
- `bd10d753` The pipeline check's Claude deploy fails before the rate limit
- `2319e632` A pass line says which entries its state saw
- `ccdfd72f` The protocol's moment and ended examples are real lines again
- `99fe4177` The evals check a reaction still in progress and one that didn't happen
- `8a269462` The decision log says why react's none now covers a reaction still showing
- `3b6c9014` The review lane's evidence
- `5f2ef6e6` The runtime test checks that "needs you" sends the reaction waiting at once
- `1dd07044` A pump timer the clock has passed is replaced, not waited for
- `470f574d` The review check's evidence

**firmware** ([README](firmware/README.md), [check](firmware-check/README.md)):

- `951fc27a` The no-hard-cut tests cover a reaction's face, the cheer's loops and what runs out on its own
- `dc29e008` boopctl soak sends brain reactions and holds the board to one `ended` each
- `7e3526fa` perf --motion goes back to cheers and wiggles
- `5dacedf9` A moment's loops too big for an int hold at 6, and a fraction plays its whole loops
- `a09e282d` perf --motion asks for a frame every second, not 10
- `5a8af5d7` The firmware lane's evidence
- `e56e4e0b` vol, a word's place and a syllable's ms hold any number to their range
- `9315c9b8` The firmware lane's check

**tune** ([README](tune/README.md), [check](tune-check/README.md)):

- `cc557a96` A scripted working day shows how Boop's brain adds up over a day
- `86029163` Boop's mood changes only for something lasting, and its reactions show more
- `76d9f0ae` The tune lane's evidence
- `2493d4d6` The working day waits for a pass's reactions before it moves the clock
- `8d4baf45` The tune lane's check
- `e13cc124` The tuned steering holds on main: 14 evals pass (merge follow-up)

**final** (this report):

- `8560cf59` boopctl day counts a new request number as a chirp, as the device now does
- This report, PLAN.md's status, owner checks and open items, and
  [final/](final/)'s outputs

**webcam** ([review](webcam/review.md)):

- `5079f71b` The webcam check: looks, the cheer, reactions held for their loops, and a tap

**hunt2**, round 2 ([README](hunt2/README.md)):

- `0056e0a2` An interrupt after the safety net still stops the open turn
- `e06ad535` A finish with no turn open is nothing, and the brain hears only of turns Boop saw start
- `1b6109b6` A session that ended stays ended until it starts again
- `8cdbf80e` A launch numbers its requests from somewhere random
- `7c1b9e0c` A reaction the device may still be playing keeps the line: across a link blip, and past a tap
- `f6e2f30f` A pass leaves alone what the dashboard changed while it ran
- `4e2f461b` The brain's deadline fires on time, and a late answer's real time is logged
- `927e3175` HISTORY keeps an event whose reaction is still in progress past the newest 40
- `cd8d5492` A turn's length leaves out the time the Mac slept
- `b2da4941` The specs say where a new day's snapshot goes, and what Codex's grace can't see
- `9efb5d1c` A pass that waited doesn't start while something needs you
- `94c3a1d8` boopctl day times only the passes answered in time
- `6616e90e` The decision log says why four of the race fixes replace what the spec said
- `41da3ff1` The second race hunt's evidence, and the open items it leaves
- `801c5a27` A pass that couldn't start keeps its brain's name, so boopctl day counts it as the brain's
- `cc5dc953` The hunt2 evidence names the follow-up commit for report 15
- `fe17a2a4` Two leftovers of the hunt say what the code now does (the check)

**tune2**, round 2 ([README](tune2/README.md), [check](tune2-check/README.md)):

- `29e327b9` The working day's report counts the words the reactions mumbled
- `a30e4cad` Boop's reactions lean strong, and a routine one comes only with something to show
- `27ea3c93` A sad Boop stays sad through more failures, and the second tuning is checked
- `dfff2a82` Jev making a reaction again once it has ended is an open item
- `9146e378` PLAN.md and the morning report say what the second tuning changed (merge follow-up)

**final2**: this report's round-2 update, PLAN.md's rows for round 2,
and [final/eval-round2.txt](final/eval-round2.txt).

## Ideas the lanes left

These aren't open items, just worth a look:

- Keep the firmware's fuzz harness and motion sweep in the repo. Two runs
  have now rebuilt them from scratch.
- Add `boopctl reset`. After a second flash the board once sat in the
  bootloader until EN was pulsed.
- Add `Boop --headless --clock-ms N`, so a simulated day can start at 09:00
  and survive a relaunch. Also `boopctl day --json`.
- Add a `make steering` target to copy `plan/steering/` into the app. For
  now it's the `rsync` above.
- Give `boopctl sim` a per-checkout output folder instead of the shared
  `/tmp/boop-sim`.
- Give `Boop --headless` a `--steering DIR` flag, passed through by
  `workday.py run`, so a steering draft can run a day without copying it
  into the app and rebuilding. And `boopdev watch --once`.
- Have `workday.py report` split quick finishes by whether tests passed,
  and print the longest run of one word. Both tune2 and its check wrote
  their own scripts for it.
- Let `internal/app/tools/test.py` run one test or a pattern; hunt2
  regenerated the runner by hand to see each test fail alone.
