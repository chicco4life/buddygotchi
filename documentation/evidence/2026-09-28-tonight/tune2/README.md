# A second tuning pass, for the reactions (tune2 lane, 2026-09-28)

The owner's brief was for a calm mood and vivid reactions: react more,
with strong faces (grumpy, sad, proud, excited and determined where they
fit, not mostly happy), now and then at a routine finish and almost
always at anything notable. The first pass ([tune](../tune/README.md))
got the mood right, 16 changes over the scripted day, but left the
reactions mostly happy: on `main` at b5ff8e9c, 67% of the day's faces
were happy and "yay" was the word in 83% of the reactions that had one.

This pass changes steering text only, and keeps the mood where it was.
In the same scripted day, happy is now 35% of the faces and the five
strong faces 64%; "yay" is 34% of the words; every notable line still
gets a face; and a quick routine finish gets one about a third of the
time (it was two thirds, nearly all a happy "yay").

## What changed

All in `plan/steering/`, copied to `app/Boop/Resources/steering/`:

- **The personality** ([boop.md](../../../steering/personality/boop.md)).
  A strong face at whatever stands out, whatever the mood: determined at a
  first failure, grumpy at a repeat or a poke, proud at a fix or a
  hard-won finish, excited at a clean win or a run of them, sad when a
  big turn fails, and a curious "hmm" at a stopped turn. A routine finish
  gets a face only when it has something to show: 40 s of work or more,
  or checks passing. The exclamation is kept for what stands out ("yay"
  at a big win); a routine face says its topic ("tests") or no word. Two
  new pick forms in the Examples do that, `→ happy, no word, once` and
  `→ excited, no exclamation, "tests", once`, since "yay" otherwise
  wins any win. The heartbeat's Example became half a sentence to make
  room; the file is at 600 of its 600 tokens.
- **The moods' leanings.** Happy's faces lean excited, with happy for
  small wins, and it mumbles "the topic, or yay at a big win". Excited
  likes "the topic, and yay at a big win"; proud leans proud and excited
  and keeps "yay" for a big win. Grumpy leans grumpy at failures and
  gives a win a grudging proud, never a grumpy face (it made grumpy
  faces at clean finishes while in a grumpy mood, 6 in two runs of one
  draft).
- **Proud's fade.** "Stays proud through routine turns and a first
  failure, but only while HISTORY shows Boop's mood changing to proud;
  then back to happy." The leave rules are as before. With the new
  personality, Jev held proud past its HISTORY in `13-proud-fades` (0 of
  3 runs) until this change.
- **Two lines of docs and UI** say what boop does now: the Settings line
  ("Reacts to anything that stands out, and now and then to routine
  work.", still two lines in `Boop --snapshots`) and
  [BEHAVIORS.md](../../../BEHAVIORS.md) §6.

And one tool change: `workday.py report` prints the day's words, so the
word mix needs no script of its own ([EVALS.md](../../../EVALS.md) §5).

## The working day, before and after

Seed 1, `jev:jev-latest`, no pass dropped in any run. Before is `main`
at b5ff8e9c, twice; after is the final steering, four times (the last
two to be sure of the mood count). Pairs and fours in a cell are the
runs in order. The full reports are in [day-reports.md](day-reports.md),
and every reaction of the first after run in
[after-1-reactions.tsv](after-1-reactions.tsv).

| Hour | Turns | Mood changes, before | after | Reactions, before | after | Per finished turn, before | after | Notable reacted, before | after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 0, 0 | 0, 0, 0, 0 | 17, 17 | 15, 15, 15, 15 | 0.77, 0.77 | 0.68, 0.68, 0.68, 0.68 | –, – | –, –, –, – |
| 10:00 | 29 | 5, 5 | 5, 5, 5, 5 | 26, 26 | 17, 17, 18, 20 | 0.72, 0.72 | 0.41, 0.41, 0.45, 0.52 | 7/7, 7/7 | 7/7, 7/7, 7/7, 7/7 |
| 11:00 | 36 | 2, 2 | 2, 3, 2, 3 | 27, 27 | 17, 19, 17, 20 | 0.69, 0.69 | 0.42, 0.47, 0.42, 0.50 | 4/4, 4/4 | 4/4, 4/4, 4/4, 4/4 |
| 12:00 | 6 | 0, 0 | 0, 0, 0, 0 | 6, 6 | 5, 5, 5, 5 | 1.00, 1.00 | 0.83, 0.83, 0.83, 0.83 | –, – | –, –, –, – |
| 13:00 | 6 | 2, 2 | 2, 2, 2, 2 | 8, 8 | 8, 8, 8, 8 | 0.83, 0.83 | 0.83, 0.83, 0.83, 0.83 | 4/4, 4/4 | 4/4, 4/4, 4/4, 4/4 |
| 14:00 | 34 | 4, 4 | 5, 5, 4, 4 | 29, 30 | 16, 17, 16, 17 | 0.65, 0.68 | 0.26, 0.29, 0.26, 0.29 | 9/9, 9/9 | 9/9, 9/9, 9/9, 9/9 |
| 15:00 | 15 | 1, 1 | 1, 1, 1, 1 | 9, 9 | 7, 7, 7, 7 | 0.60, 0.60 | 0.47, 0.47, 0.47, 0.47 | –, – | –, –, –, – |
| 16:00 | 38 | 0, 0 | 0, 0, 0, 0 | 25, 25 | 14, 22, 18, 21 | 0.66, 0.66 | 0.37, 0.58, 0.47, 0.55 | 1/1, 1/1 | 1/1, 1/1, 1/1, 1/1 |
| 17:00 | 7 | 1, 1 | 1, 1, 1, 1 | 5, 5 | 3, 4, 4, 4 | 0.71, 0.71 | 0.43, 0.57, 0.57, 0.57 | 1/1, 1/1 | 1/1, 1/1, 1/1, 1/1 |
| 18:00 | 0 | 1, 1 | 1, 1, 1, 1 | 0, 0 | 0, 0, 0, 0 | –, – | –, –, –, – | –, – | –, –, –, – |
| **Day** | **193** | **16, 16** | **17, 18, 16, 17** | **152, 153** | **102, 114, 108, 117** | **0.70, 0.70** | **0.44, 0.50, 0.47, 0.52** | **26/26, 26/26** | **26/26, 26/26, 26/26, 26/26** |

"Per finished turn" is reactions to turn ends over turns ended;
"notable" lines are failures, fixes, failed or stopped turns, turns of
10 minutes or more and poke streaks.

**Faces**, all runs of each side together:

| | happy | excited | proud | grumpy | determined | sad | curious | the five |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Before (305) | 67% (204) | 14% (44) | 8% (23) | 8% (24) | 3% (8) | 1% (2) | 0% (0) | 33% |
| After (441) | 35% (154) | 36% (159) | 14% (60) | 10% (43) | 4% (17) | 1% (4) | 1% (4) | 64% |

**Words**, all runs together, "(none)" being a mumble with no real word:

| | yay | tests | finally | again | oops | nope | ugh | hmm | (none) | yay of worded |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Before (305) | 250 | 0 | 18 | 12 | 9 | 6 | 5 | 0 | 5 | 83% |
| After (441) | 102 | 103 | 26 | 25 | 18 | 12 | 8 | 4 | 143 | 34% |

**By kind of line.** "short" is a clean finish under a minute with no
checks, "short+checks" one whose checks passed, "minutes" a clean finish
of 1 to 10 minutes:

| Kind of line | Before: reacted/all | Before: faces | Before: words | After: reacted/all | After: faces | After: words |
| --- | --- | --- | --- | --- | --- | --- |
| notable:fail | 10/10, 10/10 | grumpy 14, determined 6 | again 12, oops 6, ugh 2 | 10/10, 10/10, 10/10, 10/10 | grumpy 27, determined 13 | again 24, oops 14, ugh 2 |
| notable:fix | 4/4, 4/4 | proud 8 | finally 8 | 4/4, 4/4, 4/4, 4/4 | proud 16 | finally 16 |
| notable:comeback finish | 4/4, 4/4 | proud 8 | finally 8 | 4/4, 4/4, 4/4, 4/4 | proud 16 | yay 8, finally 8 |
| notable:big finish | 1/1, 1/1 | excited 1, proud 1 | yay 2 | 1/1, 1/1, 1/1, 1/1 | excited 4 | yay 4 |
| notable:turn failed | 3/3, 3/3 | grumpy 2, sad 2, determined 2 | ugh 3, oops 3 | 3/3, 3/3, 3/3, 3/3 | grumpy 4, sad 4, determined 4 | ugh 6, oops 4, tests 1, again 1 |
| notable:turn stopped | 1/1, 1/1 | grumpy 2 | (none) 2 | 1/1, 1/1, 1/1, 1/1 | curious 4 | hmm 4 |
| notable:poke | 3/3, 3/3 | grumpy 6 | nope 6 | 3/3, 3/3, 3/3, 3/3 | grumpy 12 | nope 12 |
| minutes | 26/26, 26/26 | excited 25, happy 21, proud 6 | yay 50, finally 2 | 25/26, 26/26, 25/26, 26/26 | excited 44, happy 32, proud 26 | yay 79, (none) 20, finally 2, tests 1 |
| short+checks | 32/32, 32/32 | happy 46, excited 18 | yay 64 | 22/32, 29/32, 27/32, 30/32 | excited 108 | tests 101, yay 7 |
| short | 68/125, 69/125 | happy 137 | yay 134, (none) 3 | 29/125, 33/125, 30/125, 35/125 | happy 122, excited 3, proud 2 | (none) 123, yay 4 |
| start | 0/192, 0/192 | – | – | 0/192, 0/192, 0/192, 0/192 | – | – |
| quiet | 0/2, 0/2 | – | – | 0/2, 0/2, 0/2, 0/2 | – | – |

What that comes to:

- **Faces.** The routine wins that were a happy "yay" split three ways:
  a check passing is an excited "tests" (108 of 108), a quick finish
  with 40 s of work a small happy face with no word, and the rest
  nothing. Turns of a few minutes are excited, proud or happy, mostly
  with "yay". Notable lines keep the faces the first pass gave them, and
  a stopped turn is now a curious "hmm" rather than a wordless grumpy
  face.
- **How often.** Reactions went from 152 to 102–117 a day, 0.70 to
  0.44–0.52 a finished turn, all of it from quick routine finishes
  (100 of 157 to 51–65). Notable lines stay at 26 of 26 and finishes of
  a few minutes at 25–26 of 26. The hours of quick work show it most:
  the 14:00 hour, full of fix-nav's quick turns, went from 0.65 to about
  0.28 a turn.
- **Holds** are as they were: notable lines held once, twice and three
  times about 10, 9 and 7 times a run (10, 8 and 8 before). Three turns
  of a few minutes a run are held three times, as before: two while Boop
  is proud after a fix, and the one that passes the deploy.
- **The mood** changed 16–18 times a day (16 before), 0 or 1 of them on
  a routine line other than a fade, the same 11:08 case as before (a
  grumpy Boop from the first poke streak turns proud a line after a
  build comeback; [PLAN.md](../../../PLAN.md) §3 has it). The extra ones
  are each what a mood file says: sad turning determined at 14:54 when
  the next turn fails again (runs 1 and 2), and, in runs 2 and 4, the
  first poke streak's grumpy fading at 11:02, before the build comes
  back, so the 22-minute comeback finish at 11:24 makes Boop proud and
  it fades again (three changes where the others make two, and none on
  a routine line but the fades). Happy is the mood for 390–406 minutes, excited 81,
  proud 37–47, grumpy 44–51, sad 4–7, determined 4–6.
- **Nothing absurd.** No sad or grumpy face at a clean finish in any
  after run, no face at a turn start or a heartbeat, and no routine tool
  use reaches the brain (`tool_uses: notable`).

## How it went

Every draft ran twice, after a one-run `boopdev eval` to warm Jev up.
Quick checks of a single question used `boopdev eval --scenarios DIR
--steering DIR` with a few probe scenarios, which needs no rebuild.

| Draft | What changed | Mood changes | Reactions | Quick finishes | Starts | Happy | The five | yay of words |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| main | | 16, 16 | 152, 153 | 100, 101 | 0, 0 | 68%, 65% | 32%, 35% | 83%, 83% |
| 1 | Personality rewritten: routine faces "only when Boop has made none for a few minutes", "no word" for small wins; a curious "hmm" Example for a turn start after a long break; mood leanings | 17, 17 | 219, 214 | 65, 61 | 102, 101 | 22%, 20% | 31%, 33% | 41%, 41% |
| 2 | Turn-start Example out; "something to show: a minute or more, checks passing, or 5 tools or more" | 17, 17 | 104, 114 | 53, 63 | 0, 0 | 23%, 32% | 77%, 68% | 75%, 75% |
| 3 | Happy's words "the topic, or yay at a big win"; a quick-tests and a stopped-turn Example; grumpy never grumpy at a win | 17, 17 | 122, 118 | 60, 56 | 10, 10 | 25%, 22% | 66%, 69% | 63%, 63% |
| 4 | "no exclamation" in the topic Examples; proud's and excited's words; the stopped turn in the prose | 16, 16 | 115, 116 | 49, 51 | 14, 13 | 18%, 23% | 69%, 65% | 44%, 53% |
| 5 | Proud's fade tied to HISTORY; "half a minute of work" in place of the tool count | 17, 16 | 140, 140 | 76, 75 | 12, 13 | 40%, 36% | 51%, 54% | 38%, 41% |
| 6 | "A turn starting gets nothing"; the tests Example at 2 min | 19, 16 | 131, 126 | 79, 74 | 0, 0 | 55%, 44% | 44%, 56% | 35%, 38% |
| 7 | The tests Example back at 40 s; "excited at a clean win or a run of them" | 17, 16 | 128, 129 | 75, 78 | 0, 0 | 41%, 42% | 58%, 57% | 37%, 39% |
| 8 | The bar at 40 s | 16, 16 | 113, 113 | 61, 61 | 0, 0 | 37%, 37% | 62%, 62% | 37%, 34% |
| 9 | "hmm" named for the stopped turn | 16, 16 | 113, 111 | 61, 59 | 0, 0 | 37%, 37% | 62%, 62% | 39%, 40% |
| final | The stopped turn as an Example again, not in the prose; the heartbeat's Example into the prose | 17, 18, 16, 17 | 102, 114, 108, 117 | 51, 62, 57, 65 | 0 | 39%, 33%, 31%, 36% | 60%, 66%, 68%, 63% | 35%, 36%, 29%, 37% |

"Quick finishes" is reactions to the 157 clean finishes under a minute;
"Starts" to the 192 turn starts. What each draft taught:

- **Jev doesn't count time in HISTORY.** Draft 1 asked for a routine
  face only when Boop had made none for a few minutes. It reacted to 32
  of 46 quick finishes that came under a minute after another face. A
  rule in the line itself (its length, its checks) holds.
- **"Curious" anywhere invites it at turn starts.** The turn-start
  Example made half the day's starts curious, and naming curious for
  the stopped turn, in an Example or the prose, made 10 to 14 starts a
  day curious, nearly all Codex's on the `boop` thread. "A turn
  starting gets nothing" stops it.
- **"yay" wins any win** unless the Example says there's no
  exclamation: `word.feeling` answers first and `word.about` only gets
  the word when it says `none` ([DECISIONS.md](../../../harness/DECISIONS.md)
  §5). With "tests" alone in the Example, "yay" still came 64 times of
  64 at a quick check; with "no exclamation", 7 times of 108.
- **A tool count reads as "nothing to show" at 0.** With "5 tools or
  more", `14-minutes-turn-is-routine`'s 2-minute turn with no tool calls
  (the eval sends none) got no face in 3 of 3 runs. A length bar has no
  such edge, and 40 s put the quick finishes at a third.
- **The stopped turn's curious face can pull the mood.** Named in the
  prose, it left happy at only 0.45–0.60 on that line, and one run of
  draft 9 turned curious for 4 minutes. As an Example it stays at
  0.79–0.86.

## The evals

`BOOP_JEV_KEY=… make eval` on the final steering: **14 of 14 in all 3
runs**, median 206 ms, slowest 353 ms ([eval.txt](eval.txt)). An earlier
full run on draft 9 also passed 14 of 14 three times.

**No scenario changed.** Draft 4 failed `13-proud-fades` (proud didn't
fade) and `14-minutes-turn-is-routine` (a 2-minute turn with no tools got
no face), 0 of 3 each; both were fixed in the steering (proud's fade, and
the length bar in place of the tool count), not in the scenarios. Draft
6 held a poke streak's face twice once, against `05-poke-streak`'s
"once"; later drafts hold it once.

**[harness/EXAMPLE.md](../../../harness/EXAMPLE.md) and
[HARNESS.md](../../../harness/HARNESS.md) §9 are re-recorded** from run 1
of `04-tests-fight-back` in that final run ([its three runs](eval-04-debug.jsonl)).
The personality's first line, which the example's state shows, had
changed, so the old lines weren't real output any more. The picks are
the same as before (determined "oops" once, grumpy "again" twice while
the mood turns determined, grumpy "again" twice as it turns grumpy,
proud "finally" as it turns proud), except that the last face holds
twice (0.53, three times 0.43), where it was three times; run 3 held it
three times. Every state line in the example appears in that run's
states in order, and the probabilities are its own, rounded.
[DECISIONS.md](../../../harness/DECISIONS.md) §2.2–2.3 describe the new
text.

## Checks

On this lane's worktree (branch `ovn3/tune2`, on `main` b5ff8e9c), with
fresh state under `/tmp` and the fake device of `workday.py`; nothing
touched Bluetooth, the board, the webcam or the everyday app:

- `make build`: builds.
- `make -C internal test`: 242 of 242, the steering's budgets and its
  app copy included (`boop.md` is at 600 of 600 tokens).
- `make -C internal fw-test`: 114 of 114.
- `make -C internal sim`: 11 scenarios, 0 expect failures, 0 new or
  changed pictures.
- The tools' tests, run directly: `boopctl_lib` 53 OK, `webcam` 3 OK,
  `workday` 10 OK (one new, for the words).
- `Boop --snapshots`: contrast passes (58 pairs), and the Settings line
  fits on two lines.
- `diff -r plan/steering app/Boop/Resources/steering` and
  `cmp CLAUDE.md AGENTS.md`: both silent.
- `BOOP_JEV_KEY=… make eval`: 14 of 14 in all 3 runs.
- The working day: 26 runs in all (twice on `main`, twice on each of
  nine drafts and twice more on draft 9, four times on the final
  steering), none with a dropped pass, though two days always ran at
  once.

## For the merge

These are outside this lane's part of [PLAN.md](../../../PLAN.md):

- §2, check 12 says routine turns get a small face. Now a quick one gets
  a face only with 40 s of work or its checks passing; a check is an
  excited "…tests!", and the rest mumble with no word.
- §3, "Curious has no way in": its face now shows once a day, at the
  stopped turn, with "hmm". The mood still has no way in.
- §1's tuning row, and the morning report's "Faces on most finishes"
  and "yay" bullets.

## Proposals, not done

- **The knobs for tomorrow** are in `boop.md`: the "40 s" bar sets how
  often a quick routine finish gets a face (30 s gave about half of
  them, 40 s a third), and the 2-minute Example's `"yay"` sets the word
  for turns of a few minutes, now 79 of the 102 "yay"s. If "yay" still
  reads too often there, `no exclamation` in that Example moves them to
  a wordless mumble.
- **`boop.md` is full.** At 600 of 600 tokens, another Example needs a
  trim or a bigger budget. "Bigger moments hold longer" went to make
  room; the guide says the same, but without it a comeback after 3
  failures is held twice about half the time (three times before).
- **A `--steering DIR` flag for the headless app** (and `workday.py
  run`), like `boopdev eval`'s, would save the copy and rebuild before
  each run of the day.
- **Sad turning determined** when the next turn fails again, right after
  a long failing turn, is what sad's file says, but the first pass's
  steering skipped it and this one takes it in half the runs. If it
  reads as one change too many, sad's file could stay through a first
  failure.
