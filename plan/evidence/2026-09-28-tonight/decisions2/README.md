# The owner's second set of decisions (2026-09-28)

The owner decided three of the morning report's open items
([README](../README.md), "What needs your decision" 5, 8 and 9). All three
are built, headless; the board wasn't used (the owner had it).

- **8a. HISTORY names Boop's last reaction.** The line before the status
  line reads `Boop's last reaction, just now: an excited face and
  "…tests!".`, with how long ago in HISTORY's own wording. `react`
  supplies it through the runtime's `parts`, so the harness only places
  it; a reaction that didn't happen doesn't count
  ([harness/HARNESS.md](../../../harness/HARNESS.md) §5.3,
  [harness/DECISIONS.md](../../../harness/DECISIONS.md) §5). The guide
  and the reading part are unchanged.
- **9. The bar for a routine finish is 20 s, not 40 s** (`boop.md`). The
  30 s "none" Example went and the 50 s one became 25 s, so boop.md stays
  within its 600 tokens.
- **5c. The next reaction replaces a held face.** Once a brain
  reaction's mumble has played (plus the link's 0.5 s), the next brain
  reaction is sent and replaces the face held for its loops; the device
  already ends the first as `done`, and a new firmware test checks that
  case (`test_a_waited_moment_says_how_it_ended`, moment 22). Rule
  moments and working chatter still wait for the device's `ended`
  ([ARCHITECTURE.md](../../../ARCHITECTURE.md) §3.2). No firmware code
  changed.

## Checks

- `make build`; `make -C internal test`: 263 of 263; `make -C internal
  fw-test`: 114 of 114; `make -C internal sim`: 11 scenarios, 0 expect
  failures, 0 new or changed pictures; `boopctl_lib` 53 OK, `workday` 10
  OK.
- `BOOP_JEV_KEY=… make eval`: 14 of 14 in all 3 runs, median 215 ms,
  slowest 443 ms ([eval.txt](eval.txt)). No scenario changed.
- One scripted working day with Jev (seed 1), against round 2's reruns
  in [tune2-check](../tune2-check/README.md)
  ([day-report.md](day-report.md)):

| | Round 2 (four runs) | Now (one run) |
| --- | --- | --- |
| Reactions per finished turn | 0.47–0.51 | 0.75 (144 of 193) |
| Quick finishes with a face | 55–65 of 157 | 92 of 157 |
| Notable lines reacted | 26/26 | 26/26 |
| Happy of the faces | 33–35% | 44% |
| Longest run of the same reaction | 8 (excited "…tests!") | 4 (a small happy face, no word); excited "…tests!" at most 2 |
| Mood changes | 16–18 | 16 |
| Dropped passes | 0 | 1 (late) |

Still open ([PLAN.md](../../../PLAN.md) §3): a comeback's finish 35–55 s
after its fix still gets the fix's proud "…finally!" again, held three
times, in both comebacks of the day. The run was one day, so the numbers
carry Jev's spread.
