# The owner's follow-up: pokes, the deadline and curious

2026-09-28, branch `ovn4/followup`. Three decisions the owner made after
the night's work, recorded in the [decision log](../../../ARCHITECTURE.md)
and in [PLAN.md](../../../PLAN.md) §1.

## What changed

1. **A poke streak never changes Boop's mood.** The core names the `mood`
   action in the poke streak event's new `sitsOut` field
   (`Core.pokesSitOut`), and the harness leaves that action's question out
   of the pass and doesn't run it. The harness only reads the names, never
   the kind. Jev still picks the face, the hold and the word, at most once
   a minute as before. The `grumpy` option and happy's mood file no longer
   mention pokes ([harness/EVENTS.md](../../../harness/EVENTS.md) §6,
   [harness/HARNESS.md](../../../harness/HARNESS.md) §3). This closes the
   "first poke streak still makes Boop grumpy" item.
2. **The deadline is 1.5 s** (`Harness.deadlineMs = 1500`), with no
   warm-up pass. The HTTP request's own timeout stays 2 s (the deadline's
   whole seconds + 1) ([harness/HARNESS.md](../../../harness/HARNESS.md) §7).
3. **Curious is no longer a mood Jev can pick.** It's gone from the
   `mood` and `react` options, `mood/curious.md` is deleted (with the
   app's copy), chatter's two curious examples are happy, and a saved
   `mood` file saying curious reads as happy. The device keeps its curious
   designs and still draws them if a state names it
   ([PROTOCOL.md](../../../PROTOCOL.md) §3). Working chatter still mumbles
   in Voice's curious feeling. This closes "Curious has no way in".

## Checks

| Check | Result |
| --- | --- |
| `make build` | Passes |
| `make -C internal test` | 260 passed, including `testAPokeStreakNeverChangesTheMood`, `testTheActionsAnEventLeavesOutSitItsPassOut` and `testALateAnswerIsDropped` (1500 ms) |
| `make -C internal fw-test` | 114 passed (a test comment changed) |
| boopctl tools' tests | 53 passed |
| workday tests | 9 passed |
| `cmp CLAUDE.md AGENTS.md`, `diff -r plan/steering app/Boop/Resources/steering` | Silent |

## The evals

`make eval` ran twice. Before rebasing onto `main` (the first tuning's
steering): 13/14 in all 3 runs, `11-comeback-still-showing` 2/3 (once
Jev made the comeback again at the finish, `react proud, word finally`,
where the scenario wants excited, happy or none; it doesn't touch pokes
or curious); no pass dropped, median 214 ms, slowest 341 ms.

After rebasing onto `main` `9146e378` (the second tuning, tune2, whose
stopped-turn Example was `curious, "hmm"`, now `happy, "hmm"`):
**14/14 in all 3 runs**, no pass dropped, median 206 ms, slowest 266 ms
against the 1.5 s deadline. `05-poke-streak` passed 3/3 both times with
its new `mood happy`.

Scenarios changed: `05-poke-streak` expects `mood` happy; `01`, `03`,
`04`, `06` and `07` no longer list curious among the faces they accept.

## Left open

- The stopped turn's face: tune2 gave boop's stopped turn a curious
  "…hmm"; with curious gone it's a happy "…hmm", a guess the owner may
  want to change.
- [harness/EXAMPLE.md](../../../harness/EXAMPLE.md) and the dashboard
  tests' fixture were recorded with curious ([PLAN.md](../../../PLAN.md) §3).
