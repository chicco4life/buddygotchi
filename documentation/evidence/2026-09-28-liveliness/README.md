# A livelier Boop: evals and steering (2026-09-28)

The owner's brief: an animated Boop that doesn't stay on one mood or
animation for long, whose moods move step by step without flailing,
that doesn't do the same thing too often, and that never idles long
(the plain working look for 5 minutes, say). Some things always hold,
like poking it again and again makes it angry. Only the steering
changes; the app's code doesn't, and anything the steering can't reach
is proposed instead.

## What changed

**The evals** ([EVALS.md](../../EVALS.md)):

- Every scenario has a `case`: the situation and what Boop should do,
  in plain words, so the steps can be rewritten when the harness
  changes. `boopdev eval --list` prints them.
- `always` scenarios are Boop's character (10 of them, 5 runs each by
  default; `--always` runs only these). New: `16-poking-keeps-boop-angry`
  and `17-never-the-wrong-face`.
- Whole-run `checks` (quiet stretches of work, identical reactions in a
  row, mood changes and bounces, how many and how varied the reactions),
  with loose limits. New: `18-long-grind`, `19-same-win-again`,
  `20-no-flail` and `21-busy-session`.
- A `gap` marks a scenario the steering can't pass yet, with why and the
  fix; it's reported `GAP` and doesn't fail the eval (`19`, `20`).
- `--timeline` prints every pass of every run.
- The runner now answers a heartbeat at the tick it comes, not at the
  step's end. Before, a 15-minute `wait` answered all its heartbeats at
  once, at 15:00.
- `workday.py report` gives the day's liveliness, and `workday.py check`
  holds a run to loose limits.

**The steering:**

- `guide.md`: moods shift step by step, and not while HISTORY ends "for
  under a minute" unless a turn failed, a very long turn ended or Boop
  was poked.
- `boop.md`: lively. A long finish gets a small happy face, and each
  working heartbeat a small face with no word (happy in a long turn,
  determined in a very long one). A short finish still gets nothing
  (see below).
- `happy.md`: a very long turn still working makes Boop determined.
- `determined.md`: stays through long work, and doesn't fade while the
  very long turn goes on; a very long turn done makes it excited.
- `proud.md`: rides out a failed check with a determined face.
- `grumpy.md`: goes back to happy after 2 minutes, but never at a poke
  streak.
- `13-proud-fades` moves its pass to 1m30s, over a minute after the
  first failure.

## The evals

All with `jev:jev-latest`.

- **Before** ([eval-base.txt](eval-base.txt), `main`'s steering, on the
  runner before the heartbeat fix and the gaps): 16 of 21. The five new
  scenarios failed:
  - Poking: Boop went happy at the third streak, 2m20s in, while still
    being poked.
  - A 20-minute grind: 15 minutes with no reaction.
  - Five quick wins: no reaction at all.
  - Tests flipping every 20 s: the mood flipped six times.
- **After** ([eval-final.txt](eval-final.txt)): 17 of 21, and every
  `always` scenario in all 5 runs.
  - `11-comeback-still-showing` failed 1 run of 3 with a second proud
    face at the finish. It's a coin flip on `main` too (its commit
    message says so), and it passed 5 of 5 in a run of its own.
  - `18-long-grind` failed on quiet stretches of 7 to 9 minutes. Jev
    answered `none` to heartbeats after a determined face; see the last
    change below.
  - `19` and `20` fail as known gaps.

## The working day

Seed 1. Before is `main`'s steering, twice. "After, faces" is a draft
that also gave a short finish a small face, twice. The final steering's
two runs hit HTTP 402 from Jev at 15:11 (the key ran out), so only the
day up to 15:11 counts. Full checks are in
[workday-checks.txt](workday-checks.txt).

| | Before | After, faces | Final (to 15:11) |
| --- | --- | --- | --- |
| Reactions a day | 57, 55 | 214, 213 | – |
| Short finishes with a face | 0/157 | 157/157 | 0 |
| Longest work with no reaction | 9.1, 16.0 min | 3.8, 3.5 min | 16.0, 16.0 min |
| Same as the reaction before | 48% | 78%, 77% | 51%, 46% |
| Longest run of the same | 8 | 42, 36 | 8, 8 |
| Mood changes | 31, 31 | 34, 33 | 27, 27 (to 15:11; before: 27) |
| Longest work happy all through | 16.1 min | 9.1, 9.2 min | 9.1, 9.2 min |
| Mood bounces | 1 | 1 | 1 |

What that comes to:

- **Faces at short finishes end the idles, but they're one face.**
  Every short finish got the same happy face with no word, 42 in a row
  at most. That's the boredom the brief warns of, so the final steering
  goes back to nothing for a short finish.
- **The long idle left is a heartbeat that never comes.** From 11:08 to
  11:24, `api`'s 22-minute turn runs while `fix-nav` does quick turns.
  Each quick turn wakes the brain, and that restarts the working
  heartbeat's wait ([EVENTS.md](../../harness/EVENTS.md) §4), so no
  heartbeat comes, and Boop is quiet for 16 minutes. The steering can't
  reach it (proposal 3 below).
- **The mood drifts more and stays away from happy longer.** Determined
  goes from 20 to 26 minutes a day, and the longest happy stretch of
  work from 16 to 9 minutes.
- **The same bounce is in every run, before and after.** At 14:23 a
  short finish turns a new grumpy back to happy within the minute,
  then a poke streak turns it grumpy again. That's the `20-no-flail`
  gap.

## What the steering can't do

Jev acts on what NOW says and on the Examples, but not on conditions
that mean reading back through HISTORY. Three drafts tried "make the
other face after a happy one", "not while under a minute" and "avoid
the face you made last". None changed its answers, and the last made
it answer `none` to heartbeats. It also answers the same line the same
way, whatever the prompt says about variety.

## The last change

The steering in the first commit is the one the final eval ran. The
second commit takes the "avoid the face it made last" sentence out of
`boop.md`, and makes a heartbeat's face "never none", to fix
`18-long-grind`'s quiet stretches. It was checked once the key was
topped up (the follow-up below): 19 of 21, `18` included.

## Proposals (code, for the owner)

1. **Repetition penalty in `react`.** When Jev's top face (and word)
   would repeat the last reaction on a routine line, take its
   second-best if that's at least 0.2. Or HISTORY closes with Boop's
   last reaction again. Closes `19-same-win-again`.
2. **A minimum mood hold.** Reword the mood question's options
   (`MoodAction.moods`: determined is "a check failed", which beats the
   MOOD file). Or the mood action keeps a new mood for a minute unless
   a turn fails, a very long turn ends or Boop is poked. Closes
   `20-no-flail` and the 14:23 bounce.
3. **The working heartbeat counts from Boop's last reaction,** not the
   last event that woke the brain. Quick turns on one thread then can't
   starve another's long turn of check-ins (11:08–11:24 above).
4. **A heartbeat line that says what's new.** For example "claude is
   still working on "api", a very long turn, 12 minutes in", or a count
   of check-ins, so identical heartbeats read differently and Jev can
   vary its face.
5. **An idle heartbeat.** With no agent working, the brain hears
   nothing for an hour. An idle check-in every 10–20 minutes would let
   Boop fidget while you're away from your agents.
6. **Reaction animations.** The candidates in
   [DECISIONS.md](../../harness/DECISIONS.md) §3 (`oops`, `slump`,
   `huff`, `ponder`) would give the same face new ways to show,
   which is variety without new moods.

## Follow-up: telling Jev to look at HISTORY (later the same day)

With a new key, the full eval on the second commit (the heartbeat
tweak) passed 19 of 21, every scenario but the two gaps in every run,
`18-long-grind` included ([eval-heartbeat-tweak.txt](eval-heartbeat-tweak.txt)).

`19-same-win-again`'s quick wins were short finishes, which boop now
answers with nothing, so there was nothing to repeat. Its steps are
now five turns of two minutes each; its case is the same. On them, Boop
made five happy faces in a row in every run.

Two question changes were tried against it, one at a time, and taken
back out:

1. **Naming the guide in `judgeBy`** for `react.mood` and `mood`, with
   a line in the guide: "For a routine line, don't make the face Boop
   made last: pick another that fits." The full eval was unchanged
   (19 of 21), and so were `19` and `20`.
2. **`react.mood`'s `about`** made "the NOW section, and the face Boop
   made last in HISTORY". `19` was unchanged.

Jev does read HISTORY: at each of the five finishes happy got 0.97,
0.87, 0.80, 0.88 and 0.84, with `none` taking the rest. But `none` is
the only other answer it moves to. The Example gives a long finish
"happy, no word", and the other faces' meanings (excited is "something
big just went right") rule them out, so for a routine win no other
face fits. `20-no-flail` didn't move either: the determined option's
"a check failed" matches NOW word for word, whatever it's told to
weigh.

## React often, and a heartbeat that waits from the last reaction

The owner's call: repeats are fine, as long as Boop reacts more often.
So:

- **Every finish done gets a small happy face,** the same one each
  time (`boop.md`).
- **The working heartbeat's wait starts again when Boop reacts,** not at
  any event that woke the brain (`Core.reacted`, [EVENTS.md](../../harness/EVENTS.md)
  §4). Before, another thread's quick turns could keep restarting it.
- **Determined stays through routine finishes.** The heartbeat change
  let a long `docs` turn drift Boop to determined, and a quick `api`
  finish then turned it back to happy a minute later, three times from
  17:11 to 17:20 in one of the first two runs.

The evals:

- `19` is now "quick wins each get a reaction" (4 of 5 at least), no
  longer a gap.
- `21` drops its repeat check and wants 10 reactions or more.
- New `22-other-thread-keeps-busy`: a 15-minute turn while a second
  session (the new step field `session`) does a quick turn every two
  minutes. It wants no more than 6 minutes of work with no reaction.
- `workday.py check` drops its repeat limits (still reported) and wants
  0.8 reactions per turn ended or more.
- `CoreTests` pin the new wait.

Full eval ([eval-react-often.txt](eval-react-often.txt)): 21 of 22, all
but the `20-no-flail` gap, in every run. The working day, seed 1, the
final steering twice against `main`'s twice
([workday-checks-react-often.txt](workday-checks-react-often.txt)):

| | Before | After |
| --- | --- | --- |
| Reactions a day | 57, 55 | 219, 214 |
| Reactions per turn ended | 0.30, 0.28 | 1.13, 1.11 |
| Short finishes with a face | 0/157 | 157/157 |
| Heartbeats that woke the brain | 8, 7 | 13, 8 |
| Longest work with no reaction | 9.1, 16.0 min | 3.7, 3.7 min |
| Work over 6 minutes with no reaction | 2, 1 | 0, 0 |
| Mood changes | 31, 31 | 33, 33 |
| Longest work happy all through | 16.1 min | 9.1 min |
| Mood bounces | 1 (14:23) | 1 (14:23) |
| Same as the reaction before | 48% | 79%, 78% (repeats are fine) |

Every limit holds in both after runs, and neither before run meets
them. The 14:23 bounce is the `20-no-flail` gap: a quick finish turns a
new grumpy back to happy within the minute.
