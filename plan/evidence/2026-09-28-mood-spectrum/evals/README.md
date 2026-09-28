# Mood spectrum: the moods lane's evals (2026-09-28)

The moods half of the integration plan ([PLAN.md](../PLAN.md) P6 and
P7): Boop's 13 moods on the owner's graph, with the `mood` question
built on every pass from the saved mood, and `react.animation` judging
each finish as a success, a failure or a reply. Everything here ran
against `jev:jev-latest` with the owner's key, supplied for the night
through `BOOP_JEV_KEY` and kept out of every file.

```sh
BOOP_JEV_KEY=… .build/debug/boopdev eval --timeline     # 5 runs for always, 3 for the rest
BOOP_JEV_KEY=… .build/debug/boopdev eval --only 16-poking --runs 3 --timeline
```

The files keep each run's verdicts and failing steps; the timelines are
left out.

## How the steering got there

| Run | Steering | Result | What it showed, and what changed next |
| --- | --- | --- | --- |
| [first](eval-first.txt) | The first draft, 1 run each | 44 of 55 | Jev played a finish (`failure`, `success`) on check lines such as `claude's tests failed`, not only on turn ends; fades took the dramatic jump to calm (grumpy or irritated straight to calm at a turn start); poke counts in the option meanings pulled a grumpy Boop back down to annoyed; a question to the agent ("what does the retry helper do?") made calm curious. So: the `react.animation` options now key on NOW's own words ("NOW's line says a turn finished"), a jump's "not for" names checks and fades, the counts left the meanings for the mood files, and curious is for a poke or something said to Boop |
| second | Those fixes, 1 run each | 49 of 55 | No more finishes on check lines. annoyed didn't move on to determined at the second failed check, and faded to calm in the middle of failures; the agent giving up made calm annoyed, not sad |
| [middle](eval-middle.txt) | annoyed's file turned around ("it stays annoyed only until the next failure"), a failure holds it, the fade "at whatever NOW is"; full runs | 50 of 55 in every run | 09 (2/5), 11 (2/3), 16 (0/5), 27 (0/3), and the known gap 20 (2/3). A grumpy Boop after a barrage of pokes never faded at the next turn start |
| (targeted) | The fade targets say they're where a mood cools down (annoyed: "grumpy or irritated cooling down"), the hold says it's for when MOOD gives no reason to leave "nor are its minutes up", sad and annoyed split on the agent giving up | 09 5/5, 27 3/3, 47 5/5, 16 0/5 | Seven wordings of grumpy's fade (and of the hold) never moved the turn start (Jev gave annoyed 0.24–0.44); the next turn's finish did, 3 of 3 ([16's two ways](eval-16-cooldown.txt)). 16 checks the cool-down there now: "by the end of the agent's next turn", still a few minutes after the last poke |
| [final 1](eval-final-1.txt) | Committed steering, full runs | 53 of 55 in every run | Every `always` scenario passed in all 5 runs. 33 missed its "claude" once (a "hmm" after a curious face at the start), and the known gap 20 failed |
| [slow Jev](eval-slow-jev.txt) | The same, full runs | 36 of 55 | Not the steering: Jev was slow for a while, and 111 passes were dropped at the 1.5 s deadline. Every failing step in it is `dropped: late`; none got a wrong answer. Left in to show how drops read |
| (probes) | The same | – | Jev stayed slow for the next half hour: small probes every 3 minutes dropped 1 or 2 of 6 passes, and by 22:25 its median answer was at the 1.5 s deadline. No second clean full run was possible before this report |

## The full runs, by scenario

Runs passed of runs made: the middle run (the steering before the last
round of fixes), the final one (the committed steering), and the slow
one (the same steering, with every failure a pass Jev answered too
late). The final run's two misses are 33, a word ("hmm" for "claude"
once), and the known gap 20.

| Scenario | Kind | Middle | Final | Slow Jev |
| --- | --- | --- | --- | --- |
| `01-short-turn` | tuning | 3/3 | 3/3 | 3/3 |
| `02-long-turn` | always | 5/5 | 5/5 | 5/5 |
| `03-turn-failed` | always | 5/5 | 5/5 | 5/5 |
| `04-tests-fight-back` | always | 5/5 | 5/5 | 5/5 |
| `05-pokes-glad-miffed-grumpy` | always | 5/5 | 5/5 | 5/5 |
| `06-heartbeat-lets-grumpy-go` | always | 5/5 | 5/5 | 5/5 |
| `07-chatter-reacts-to-everything` | tuning | 3/3 | 3/3 | 3/3 |
| `08-long-turn-fails` | always | 5/5 | 5/5 | 5/5 |
| `09-failure-worked-through` | always | 2/5 | 5/5 | 2/5 |
| `10-run-of-wins` | tuning | 3/3 | 3/3 | 3/3 |
| `11-comeback-still-showing` | tuning | 2/3 | 3/3 | 3/3 |
| `12-comeback-that-didnt-happen` | tuning | 3/3 | 3/3 | 2/3 |
| `13-proud-fades` | always | 5/5 | 5/5 | 4/5 |
| `14-minutes-turn-is-routine` | tuning | 3/3 | 3/3 | 3/3 |
| `15-quiet-work` | tuning | 3/3 | 3/3 | 2/3 |
| `16-poking-keeps-boop-angry` | always | 0/5 | 5/5 | 5/5 |
| `17-never-the-wrong-face` | always | 5/5 | 5/5 | 4/5 |
| `18-long-grind` | tuning | 3/3 | 3/3 | 3/3 |
| `19-same-win-again` | tuning | 3/3 | 3/3 | 1/3 |
| `20-no-flail` | gap | 2/3 | 0/3 | 2/3 |
| `21-busy-session` | tuning | 3/3 | 3/3 | 3/3 |
| `22-other-thread-keeps-busy` | tuning | 3/3 | 3/3 | 3/3 |
| `23-poke-barrage-one-face` | always | 5/5 | 5/5 | 5/5 |
| `24-frustrated-ask` | tuning | 3/3 | 3/3 | 3/3 |
| `25-thanks` | tuning | 3/3 | 3/3 | 3/3 |
| `26-hard-work-done` | tuning | 3/3 | 3/3 | 3/3 |
| `27-agent-gives-up` | tuning | 0/3 | 3/3 | 3/3 |
| `28-plain-words-leave-mood` | always | 5/5 | 5/5 | 3/5 |
| `29-long-turn-is-nice` | tuning | 3/3 | 3/3 | 3/3 |
| `30-bug-fixed-says-bug` | tuning | 3/3 | 3/3 | 3/3 |
| `31-pushed-says-merge` | tuning | 3/3 | 3/3 | 3/3 |
| `32-review-says-review` | tuning | 3/3 | 3/3 | 3/3 |
| `33-plain-finish-says-agent` | tuning | 3/3 | 2/3 | 3/3 |
| `34-long-bug-fix-nice` | tuning | 3/3 | 3/3 | 3/3 |
| `35-talk-gets-an-answer` | always | 5/5 | 5/5 | 5/5 |
| `36-talk-when-grumpy` | always | 5/5 | 5/5 | 5/5 |
| `37-talk-when-idle` | always | 5/5 | 5/5 | 5/5 |
| `38-talk-twice-over-a-face` | always | 5/5 | 5/5 | 4/5 |
| `39-talk-after-a-failure` | always | 5/5 | 5/5 | 5/5 |
| `40-talk-garbled-words` | always | 5/5 | 5/5 | 2/5 |
| `41-done-and-working-is-success` | always | 5/5 | 5/5 | 4/5 |
| `42-couldnt-finish-is-failure` | always | 5/5 | 5/5 | 5/5 |
| `43-failed-turn-sounds-upbeat` | always | 5/5 | 5/5 | 5/5 |
| `44-question-back-is-reply` | tuning | 3/3 | 3/3 | 3/3 |
| `45-answer-is-reply` | tuning | 3/3 | 3/3 | 3/3 |
| `46-finish-in-a-bad-mood` | tuning | 3/3 | 3/3 | 2/3 |
| `47-recovery-walk` | always | 5/5 | 5/5 | 4/5 |
| `48-small-and-big-failure-from-calm` | tuning | 3/3 | 3/3 | 3/3 |
| `49-poke-ladder-on-the-graph` | always | 5/5 | 5/5 | 4/5 |
| `50-thanks-while-hurt` | tuning | 3/3 | 3/3 | 1/3 |
| `51-long-grind-of-passing-work` | tuning | 3/3 | 3/3 | 1/3 |
| `52-routine-work-holds-calm` | tuning | 3/3 | 3/3 | 2/3 |
| `53-busy-day-on-the-graph` | always | 5/5 | 5/5 | 5/5 |
| `54-talk-while-irritated` | tuning | 3/3 | 3/3 | 2/3 |
| `55-quiet-fades-from-excited` | tuning | 3/3 | 3/3 | 2/3 |

## What the steering says now

- **The guide:** the mood moves a step at a time, only to a mood on
  offer; after the minutes MOOD gives, or an hour of nothing, it fades
  one step, to the mood MOOD names, at whatever NOW is. A finish is
  judged: success, failure or only a reply.
- **Each mood file** says who Boop is in it, its faces and words, when
  it stays, when it leaves and for which neighbour (only neighbours: a
  test checks), and its fade: 2 min for grumpy and curious, 3 for
  annoyed and irritated, 5 for excited, proud, engaged, determined and
  whiny, 10 for happy, wounded and sad, one step toward calm
  (excited and proud to happy, determined to engaged, irritated and
  grumpy to annoyed, the rest to calm).
- **The ladders:** a failed check puts a calm Boop out (annoyed) and the
  next makes it determined; a pass after failing makes it proud; a
  failed turn is annoyed from calm and grumpy from annoyed; pokes climb
  curious or happy, annoyed, irritated, grumpy; a very long turn done
  is excited, failed sad; the agent giving up is sad; thanks lift
  (excited from calm, happy from whiny or wounded, calm from grumpy);
  rude words wound.
- **The personalities:** boop's Examples give each finish its outcome
  (`→ excited, success, "yay", three times`), a reply for an answer
  (curious), engaged at a long turn's check-in, annoyed at a failed
  check, a curious face at a poke and a grumpy "nope" at four; wounded
  at rude words. chatter's finishes are successes and failures too.

## What Jev taught us this time

- Jev keys on NOW's literal words. The finish question only stopped
  playing finishes on check lines once its options said "NOW's line
  says a turn finished".
- A fade needs somewhere to land that means cooling down: the old happy
  was the resting mood and a turn start fit it; annoyed didn't, until
  its meaning said it's where grumpy cools down. Even then Jev won't
  move a mood at a turn start after a barrage of pokes, and will at the
  next finish.
- A dramatic move offered alongside the ordinary ones gets taken when
  its meaning fits and nothing forbids it (grumpy straight to calm as a
  fade), so the jump's "not for" names what isn't big enough.
- Tests flipping every 20 s still flip the mood (`20-no-flail`, a known
  gap): determined and proud trade places at each result. Steering
  alone hasn't held it; a minimum hold would, and the owner chose
  steering-only pacing (D5).

## The scripted pipeline

[headless-scripted.txt](headless-scripted.txt): `Boop --headless
--brain scripted --link none --debug`, a short Claude session through
`boopdev replay`, then a forced pass and a mood set from the dashboard.
The scripted brain keeps the mood (calm), makes its excited face, and
plays the turn's finish as a success: `{"t":"moment","anim":"task_complete",…,
"who":{"agent":"claude","thread":"jetpack"},"outcome":"success"}`.
`debug.jsonl`'s `questions` line comes again once the dashboard moved
the mood to grumpy, with grumpy's options: staying, irritated, annoyed,
whiny, determined, then the jumps calm, wounded, sad and proud.
