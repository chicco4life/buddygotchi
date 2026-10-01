# Expressive moods (2026-09-28)

The owner wanted to see Boop's personality shift during ordinary use. The
mood now moves for anything with some weight and fades back after a few
minutes, each change comes with a reaction in the new mood's face, and a
poke streak can make Boop grumpy for 2 minutes
([harness/DECISIONS.md](../../harness/DECISIONS.md) §2.1, §2.3, §4).

## Evals

`BOOP_JEV_KEY=… make eval` on the final text: 14 of 15 in all 3 runs
([eval.txt](eval.txt)). `14-minutes-turn-is-routine` fails the same way
on `main` (`9fdbbb50`), 0 of 3 runs: a cheer and "yay" on a 3-minute
turn. It's left open.

Along the way:

- Jev couldn't tell that "7 min ago" meant a mood's 5 minutes were up,
  and kept Boop proud at 0.68–0.75. `mood` now closes HISTORY with
  `Boop has been proud for 7 min.`, and `13-proud-fades` went from 0 to
  3 of 3.
- Jev went excited at the second clean finish instead of the third. The
  core now says `3 clean finishes in a row.` on the finish line, and
  `10-run-of-wins` went from 1 to 3 of 3.
- `11-comeback-still-showing` sat near a coin flip even on `main`'s text
  (proud 0.48 against none 0.43). The guide now says never to repeat a
  reaction in progress even when NOW matches an Example; 3 of 3.

## The working day

`workday.py` over the scripted day (193 turns), two runs each
([day-reports.md](day-reports.md) for the final text):

| Text | Mood changes a day |
| --- | --- |
| `main` (last night's tuning) | 16 |
| First version, any 3 clean finishes in a row | 135, 137 |
| Final, only at exactly 3 | 75, 76 |

The first version flipped between excited and happy every few minutes
through a clean stretch. With the trigger at exactly 3, a change comes
about every 15 minutes of active work, each change and its fade back
counted apart. No fade came because the change had left HISTORY: all 34
early ones (a minute before their time) still showed it.
