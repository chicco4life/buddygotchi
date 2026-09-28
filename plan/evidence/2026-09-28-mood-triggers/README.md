# Moods from the words in the notes

2026-09-28. Boop's mood barely moved in ordinary work: its reasons to
leave happy were failed checks, fixes, very long turns, failed turns and
pokes, so a day of short turns left it happy but for pokes. Four
reasons now come from the notes Jev already read: the person's prompt
on a turn start and the agent's last message on a finish
([DECISIONS.md](../../harness/DECISIONS.md) §2.3). No new events or code
paths; the words are Jev's to judge.

`make eval` with Jev ([eval.txt](eval.txt), before the scenarios were
renumbered `24`–`28` on rebasing past main's own `23`s): 25/27 in every
run. The new `23`–`27` pass; `10` lost one run to a late answer (1,505 ms against the
1,500 ms deadline), and `20-no-flail` is the known gap.

What it took, from runs along the way:

- `25-hard-work-done` (now `26`) stayed happy (0/3) while happy said it "stays
  through routine turns under 5 minutes": a 4-minute "done, tests pass"
  read as routine. "Plain finishes", and proud as "a long turn's last
  message says hard work is done and working": 3/3.
- `26-agent-gives-up` (now `27`) went grumpy (0/3): the `mood` and `react.mood`
  options (in code) said sad was only for a very long turn failing, and
  grumpy for any failed turn. With "or the agent gave up, stuck" on sad
  and "not for an agent giving up" on grumpy, in both questions and
  PERSONALITY: 3/3.
- `16-poking-keeps-boop-angry` failed to calm down in 1 of 10 runs
  after a rewrap split "grumpy for 2 min" over two lines, away from
  HISTORY's closing `Boop has been grumpy for 2 min.`. Back on one line:
  10/10.
- The mood files' budget went from 150 to 175 tokens to fit the four
  reasons ([HARNESS.md](../../harness/HARNESS.md) §6.2).
