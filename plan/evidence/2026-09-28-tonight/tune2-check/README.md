# Checking the second tuning pass (tune2-check, 2026-09-28)

An independent check of the tune2 lane's two commits on `ovn3/tune2`
(`46e5e6ef`, `44e45e12`, on `main` at b5ff8e9c), against the owner's
brief: a calm mood, and vivid reactions with strong faces (grumpy, sad,
proud, excited and determined where they fit, not mostly happy), now and
then at a routine finish and almost always at anything notable.
Everything ran on the lane's worktree with fresh state under `/tmp` and
the fake USB device of `workday.py`. Nothing touched the board, the
webcam, Bluetooth or the everyday app.

In short: the lane's numbers hold on two reruns of the working day. One
thing was a little off, and it's fixed in the steering: a sad Boop
turned determined at the next failure in half the runs, a mood change
more than the calm target. Two things aren't fixed. Jev makes a
reaction it has just finished again (a run of "…tests!" in the hour of
quick wins, and a double "…finally!" at a comeback), and there are
fewer reactions overall than after the first pass.

## Is it steering, and within budget

- **Behaviour changes through steering text only:** `boop.md` and four
  mood files (happy, excited, proud, grumpy), and in this check
  `sad.md`. The rest is docs, the Settings pane's one-line description
  of `boop` (a UI string), and `workday.py report` printing the words
  (a dev tool). No code path changed.
- **Budgets** (bytes ÷ 4, comments and front matter left out): the
  guide 275 of 300, `boop` 600 of 600 (full), `chatter` 297 of 300,
  moods 111–149 of 150 (happy 149, sad 118 after this check's change).
  `make -C internal test` passes the budget test.
- **The app's copy:** `diff -r plan/steering app/Boop/Resources/steering`
  is silent, and so is a diff against the built app's bundle, which is
  what `Boop --headless` reads.
- No committed file or lane diff contains the Jev key (checked with
  `git grep -F` against the key file, without printing it).
- The Settings line fits on two lines in `Boop --snapshots`, and
  contrast passes on 58 pairs.

## The reruns

Seed 1, `jev:jev-latest`, two days run at once, after a full
`make eval` to warm Jev up. "The lane's text" is `44e45e12` as the lane
left it; "with the fix" adds this check's change to `mood/sad.md`. No
pass was dropped in any run. The full reports are in
[day-reports.md](day-reports.md).

| Hour | Turns | Mood changes, lane's text | with the fix | Reactions, lane's text | with the fix | Per finished turn, lane's text | with the fix | Notable reacted |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 09:00 | 22 | 0, 0 | 0, 0 | 15, 14 | 15, 15 | 0.68, 0.64 | 0.68, 0.68 | – |
| 10:00 | 29 | 5, 5 | 5, 5 | 18, 19 | 17, 17 | 0.45, 0.48 | 0.41, 0.41 | 7/7 in all four |
| 11:00 | 36 | 2, 3 | 2, 2 | 18, 22 | 17, 17 | 0.44, 0.56 | 0.42, 0.42 | 4/4 in all four |
| 12:00 | 6 | 0, 0 | 0, 0 | 5, 5 | 5, 5 | 0.83, 0.83 | 0.83, 0.83 | – |
| 13:00 | 6 | 2, 2 | 2, 2 | 8, 7 | 9, 9 | 0.83, 0.67 | 1.00, 1.00 | 4/4 in all four |
| 14:00 | 34 | 4, 5 | 4, 4 | 17, 17 | 16, 16 | 0.29, 0.29 | 0.26, 0.26 | 9/9 in all four |
| 15:00 | 15 | 1, 1 | 1, 1 | 7, 7 | 7, 7 | 0.47, 0.47 | 0.47, 0.47 | – |
| 16:00 | 38 | 0, 0 | 0, 0 | 18, 21 | 21, 17 | 0.47, 0.55 | 0.55, 0.45 | 1/1 in all four |
| 17:00 | 7 | 1, 1 | 1, 1 | 4, 4 | 4, 4 | 0.57, 0.57 | 0.57, 0.57 | 1/1 in all four |
| 18:00 | 0 | 1, 1 | 1, 1 | 0, 0 | 0, 0 | – | – | – |
| **Day** | **193** | **16, 18** | **16, 16** | **110, 116** | **111, 107** | **0.48, 0.51** | **0.49, 0.47** | **26/26 in all four** |

**Faces**, both runs of a side together:

| | happy | excited | proud | grumpy | determined | sad | curious | the five |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| The lane's four runs (441) | 35% | 36% | 14% | 10% | 4% | 1% | 1% | 64% |
| Rerun, the lane's text (226) | 35% (80) | 35% (80) | 14% (32) | 9% (21) | 4% (9) | 1% (2) | 1% (2) | 64% |
| Rerun, with the fix (218) | 33% (73) | 39% (84) | 12% (27) | 10% (22) | 4% (8) | 1% (2) | 1% (2) | 66% |

**Words**, both runs together ("none" is a mumble with no real word):

| | yay | tests | finally | again | oops | nope | ugh | hmm | none | yay of those with a word |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Rerun, the lane's text | 56 | 48 | 13 | 14 | 9 | 6 | 3 | 2 | 75 | 37% |
| Rerun, with the fix | 58 | 46 | 14 | 14 | 8 | 6 | 4 | 2 | 66 | 38% |

**By kind of line**, reacted/all per run (lane's text, lane's text;
with the fix, with the fix):

| Kind of line | Reacted | Faces and words |
| --- | --- | --- |
| Failures (10 a day) | 10/10 in all four | grumpy "again" held twice at a repeat, determined "oops" once at a first |
| Fixes (4) | 4/4 in all four | proud "finally", twice or three times |
| Comeback finishes (4) | 4/4 in all four | proud, three times, "finally" or "yay" |
| The 14-minute turn failing | 1/1 in all four | sad, three times ("again") |
| The 16-minute docs turn | 1/1 in all four | excited "yay", three times |
| Failed turns (rate limit, API error) | 2/2 in all four | grumpy "ugh", determined "oops" |
| The stopped turn | 1/1 in all four | curious "hmm" |
| Poke streaks (3) | 3/3 in all four | grumpy "nope", once |
| Clean finishes of 1–10 min (26) | 26, 25; 26, 26 | excited, happy or proud, mostly "yay" |
| Under a minute, tests passing (32) | 24, 28; 27, 24 | excited, "tests" (21–27 a run) or "yay" (1–3) |
| Under a minute, nothing to show (125) | 34, 37; 32, 31 | happy with no word, a handful excited or proud |
| Turn starts (192) | 0 in all four | – |
| Heartbeats (2) | 0 in all four | – |

## Against the brief

- **Face mix: holds.** Happy is 33–35% of the faces (under ~40%), and
  the five strong ones 64–66% (over ~50%), as the lane said.
- **Word variety: holds, with one pattern.** "yay" is 37–38% of the
  reactions with a word, and nine words turn up where they fit. But a
  run of quick turns with their tests passing gets "…tests!" nearly
  every time: the longest runs of one word were "tests" 5, 7, 8 and 5
  times in a row, the 7 and the 8 in the 16:00 hour (below).
- **Notable lines: almost always.** 26 of 26 in every run, with the
  fitting face.
- **Routine finishes: now and then.** Turns of a few minutes get a face
  every time (25–26 of 26); quick ones 35–41% of the time: a quarter to
  a third of those with nothing to show (31–37 of 125), and three
  quarters or more of those whose tests passed (24–28 of 32).
- **"React more": not on the count.** Reactions per finished turn are
  0.47–0.51, where the first pass had 0.70. Everything lost is a quick
  routine finish, and the brief's "now and then" asks for that, but the
  day has fewer reactions than the first pass left. It's a trade:
  reacting to more quick finishes means more happy faces (below).
- **Mood changes: 16, 18 on the lane's text; 16, 16 with the fix.** The
  lane's extra ones were sad turning determined at the next failure (in
  3 of its 6 runs, counting these), which is fixed below, and in the
  second rerun the first poke streak's grumpy fading at 11:02, so the
  22-minute comeback made Boop proud and it faded again. Each is what a
  mood file says.
- **A mood change on one routine line: 1, 0; 1, 1.** Each is the known
  11:08 case ([PLAN.md](../../../PLAN.md) §3, from the first pass): the
  first poke streak's grumpy turns proud on the turn start 10 s after
  the build comes back. To a viewer it follows the build, not the turn
  start.
- **Nothing absurd.** In all four runs: no sad, grumpy or determined
  face at a clean finish, no happy, excited or proud face (or "yay",
  "finally") at a failure, no "again", "oops", "ugh" or "nope" at a
  win, no reaction at a turn start or a heartbeat, and no routine tool
  use reaches the brain (`tool_uses: notable`). Faces are held once
  87–97 times a run, twice 9 and three times 10–11: the long holds are
  the fixes, comebacks, long turns and repeated failures, plus three or
  four turns of a few minutes a run (a proud "…yay!" while Boop is proud
  after a fix, the passing deploy, and in one run a Codex turn at
  12:08, which is more than a routine turn needs).

## Fixed: a sad Boop stays sad through more failures

**What was off.** After the 14-minute turn fails at 14:50, Boop is sad.
At 14:54 the next turn's tests fail again ("4 in a row"), and `sad.md`
said it "leaves this mood for determined when it fails again while the
agent retries". Jev made that a coin flip: determined 0.45 and 0.53
against sad 0.49 and 0.39 in the two reruns, taken in one of them and in
two of the lane's four runs. Then the tests pass at 14:57 and it's
proud. So Boop went sad, determined, proud in three minutes: one mood
change a day more than the calm the brief asks for, and a sad Boop
brightening into determined while the same tests still fail.

**The change** ([sad.md](../../../steering/mood/sad.md)): "Stays sad
through routine turns and more failures. Leaves this mood for proud
when what failed finally works. Goes back to happy once HISTORY no
longer shows Boop's mood changing to sad." Its faces still lean sad, or
determined at a failure. [DECISIONS.md](../../../harness/DECISIONS.md)
§2.3's table and the decision log in
[ARCHITECTURE.md](../../../ARCHITECTURE.md) §11 say so.

**How it did.** In a probe scenario with the same story
([probe-sad-next-failure.json](probe-sad-next-failure.json), `boopdev
eval --scenarios DIR --steering DIR`, 3 runs), sad at the fourth
failure went from 0.47–0.54 to 0.94. A second wording ("the failures
right after") did the same; a first try that kept a way out to
determined at "yet another" failure made it worse (0.35–0.45). In the
day, sad held at 0.96–0.97 at 14:54 in both reruns, went straight to
proud at the fix, and the day had 16 mood changes in both. The faces,
words and reactions are the same as on the lane's text, within the
runs' spread. `make eval` passes 14 of 14 in all 3 runs
([eval.txt](eval.txt)).

## Not fixed

**Jev makes a reaction again once it has ended.** The guide says
"don't repeat what Boop just did", but once a reaction has played out,
Jev makes the same one when the next line calls for it:

- **"…tests!" at nearly every quick test pass.** 21–27 a day, two
  thirds or more of those lines, and in the 16:00 hour of quick wins
  9–12 of the hour's 17–21 reactions, up to 8 in a row. Before this pass it was "yay" everywhere,
  so it's better, but a run of the same excited "…tests!" is the next
  thing the owner may notice.
- **A comeback's "…finally!" twice.** The tests pass at 14:56–14:57
  (proud "…finally!", three times) and the turn finishes 30–40 s later
  as "a comeback on tests" (proud "…finally!", three times, again), in
  all four reruns, and the 13:56 build fix does the same a minute
  before its turn finishes. The first pass had it too. `11-comeback-still-showing`
  covers only a reaction still in progress.

I tried the text for the first. An Example giving a quick test pass an
excited face with "no word" got "yay" instead (0.53–0.60 over none),
and the topic question still named "tests" at 0.82–0.85, since NOW is
about tests: a reaction to a line about tests will carry "tests" or
"yay". The only text lever is fewer of those reactions, and giving the
test passes under 40 s no face would take happy to 41–43% of the faces
and reactions to about 0.40 a finished turn (counted on the reruns of
the lane's text).
So it's left, as an open item in [PLAN.md](../../../PLAN.md) §3. What
would settle it is outside the steering: the guide's "just did"
naming the last reaction, or the state saying how long ago it was.

**Fewer reactions than the first pass** (above). The knob is `boop.md`'s
"40 s" bar, as the lane says; it's full at 600 tokens.

## For the merge

The lane's notes still apply: [PLAN.md](../../../PLAN.md) §2 check 12's
"Routine turns get a small face", §3's "Curious has no way in" (its face
now shows at the stopped turn), §1's tuning row, and the morning
report's "faces on most finishes" and "yay 80%" bullets. The morning
report's 16 mood changes a day is right again with this fix.

## Checks

On the lane's worktree with this check's change, except where it says:

- `make build`: builds.
- `make -C internal test`: 242 of 242, the steering's budgets and the
  app's copy included.
- `make -C internal fw-test`: 114 of 114.
- `make -C internal sim`: 11 scenarios, 0 expect failures, 0 new or
  changed pictures.
- The tools' tests, run directly: `boopctl_lib` 53 OK, `webcam` 3 OK,
  `workday` 10 OK.
- `Boop --snapshots`: contrast passes on 58 pairs; the Settings line is
  two lines.
- `BOOP_JEV_KEY=… make eval`: 14 of 14 in all 3 runs on the lane's text
  (median 206 ms, slowest 330 ms) and with the fix (median 212 ms,
  slowest 596 ms).
- The working day with Jev: twice on the lane's text and twice with the
  fix, 403 passes each and none dropped.
- `diff -r plan/steering app/Boop/Resources/steering` and
  `cmp CLAUDE.md AGENTS.md`: both silent.
