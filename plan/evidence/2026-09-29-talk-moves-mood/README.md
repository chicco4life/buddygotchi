# Talk moves the mood, and evals on a budget

2026-09-29. The owner's brief: Boop's mood should change faster while the
person talks to it (one apology should do, sad news should make it sad
until it's taken back), and the evals should send Jev fewer requests.

## What changed

- **Steering.** The guide lets words said to Boop move the mood in its
  first minute, as a poke does. Saying sorry moves grumpy to irritated
  or annoyed, irritated to annoyed and annoyed to calm. Sad news the
  person shares moves most moods to sad, and more of it keeps Boop sad;
  taking it back or cheering Boop up leaves sad for calm or happy. The
  mood question's meanings (`MoodAction.moods`) and PERSONALITY ("sad at
  sad news") say the same. [harness/DECISIONS.md](../../harness/DECISIONS.md) §2.3.
- **Scenarios.** `56`–`59` are new: one apology softens a grumpy Boop a
  step, poking again undoes it and a second apology is fair, sad news
  then "just kidding", and a plain question that softens nothing. `36`
  now also accepts an irritated or annoyed face, since its apology can
  soften the mood.
- **The eval's cost.** `always` scenarios run 3 times (was 5), the rest
  once (was 3), `53` runs once, and `boopdev eval` counts the requests
  first and stops over a budget of 100 unless `--no-budget` (`make
  eval`). A full eval went from about 1,340 requests to about 620.
  [EVALS.md](../../EVALS.md) §2.

## What ran

1. `make -C internal test`: 314 passed.
2. With the scripted brain, the state Jev would read at `56`'s apology:
   the new guide line, grumpy's "says sorry" rule, and the mood options
   naming irritated and annoyed "softening at an apology".
3. Targeted, with Jev: `--only apology`, `sad-news`, `plain-question`
   and `talk`: 11 of 11 passed, about 89 requests. Jev's picks were
   sure: sorry → irritated 0.90; sad news → sad 1.00, held 1.00; "just
   kidding" → calm 0.88; the plain question stays grumpy 0.91. The
   closest was `57`'s second apology, irritated 0.50 against annoyed
   0.42, both accepted.
4. `make eval` ([eval.txt](eval.txt)): 58 of 59 passed in every run; the
   one that didn't is `20`, the known gap, failing as before. No pass
   dropped; latency median 228 ms, slowest 1,030 ms against the 1.5 s
   deadline.

The working day (VERIFICATION.md L5 step 3) didn't run: the change is to
what the person says to Boop, which the scripted day has none of.
