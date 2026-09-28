# "nice" joins the brain's words

2026-09-28, `boopdev eval` against `jev:jev-latest`.

Tried three already-recorded words: the exclamations "nice" (a long turn
done) and "wow" (a very long turn done that fought back), and the topic
"fix" (a turn done after its fix). Only "nice" was kept
([ARCHITECTURE.md](../../ARCHITECTURE.md) decision log).

| Run | Result |
| --- | --- |
| All three words, full eval | 22/25; `24` (wow) 0/3: Jev said "yay" with the fix 8 min back (wow 0.03), though it picked "wow" at 0.47–0.62 in `12`, fix 20 s back; `11` 1/3, a second proud face |
| `11`, 10 runs: main / branch / branch code with main's steering | 10/10 / 7/10 / 10/10: the steering, not the options |
| `11`, 10 runs, one edit reverted at a time | without the "fix" example 9/10 (and 10/10 with proud's words reverted too); the rest 6–9/10 |
| "nice" only, full eval | 19/23; every failure but `20` (known gap) a Jev timeout at 1500 ms; `09`, `16`, `19` pass on rerun; `11` 2/3, proud with "nice" |
| "nice" not for a turn ending just after its fix | `11` 15/15, 2/3 (full eval), 30/30 (main 30/30); `23` 15/15 |

`11` on the final branch: 46 of 48 runs, where main passed 43 of 43.
The failure is always the same: a second proud face, with "nice", while
the first still shows.
