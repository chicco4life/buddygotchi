# Seven moods for Jev (A11, part 1), 2026-09-27

Jev's `mood` question offers the seven moods of the mood SVGs (happy,
excited, proud, curious, determined, grumpy, sad) instead of cheerful and
grumpy, each with a steering file in `plan/steering/mood/`, and the
10-minute hold between mood changes is gone
([harness/DECISIONS.md](../../harness/DECISIONS.md) §2.3, §4).

## What ran

- **`make test`:** passes, among them `HarnessTests.testMood` (the seven
  moods, a change straight after another, `cheerful` reading as happy),
  the bundled steering matching `plan/steering/` file for file, every
  steering file within its budget, and the eval runner with a scripted
  brain.
- **`make eval` against `jev:jev-latest`,** with the owner's key in
  `BOOP_JEV_KEY`: 10/10 scenarios in all 3 runs, median 209 ms, slowest
  388 ms ([eval-passes.txt](eval-passes.txt)).

## What the evals changed

The first run passed 7 of 10. The failures showed wording that Jev read
differently from what was meant, so the steering was tightened until all
ten passed:

| Seen | Cause | Change |
| --- | --- | --- |
| Every turn start turned Boop curious (about 0.7) | Happy left for curious "when something new starts", and every turn is new | Curious is "unsure how things are going: mixed results, or something unusual", not for a routine turn start or a failure |
| Four clean 3-minute turns made Boop proud, not excited | The core calls any turn past a minute "a very long turn" ([harness/EVENTS.md](../../harness/EVENTS.md) §5), and happy left for proud "after a long finish" | Proud is for a hard-won finish, not a routine one however long; scenario 10 uses turns that pass their tests |
| A 25-minute turn that failed turned Boop determined or curious, not sad | Determined didn't say the agent had to be retrying, and the curious turn start sent it on from there | Determined is not for a turn that has ended |
| A 2-minute rate-limit failure turned Boop sad (0.78) | "A turn that ran for many minutes" matched 2 minutes | Sad is for a turn of 10 minutes or more |
| Two failures in a row split happy 0.40, determined 0.37, grumpy 0.21 | Happy's ways out had no count for determined | Happy's ladder: one failure gets a shrug, two in a row is determined, three or more is grumpy |

## Part 2: the mood reaches the device

Every `state` now carries `mood` ([PROTOCOL.md](../../PROTOCOL.md) §3).
The mood action tells the runtime once it has saved a new mood, and the
core sends a fresh `state` at once. The device keeps the mood (a missing
or unknown one is happy) and reports it in `dbg.state`, but draws
nothing new yet. `boopctl play --mood MOOD` sets it by hand.

- **`make test`:** 187 pass. New: `CoreTests.testANewMoodGoesOutInTheNextState`;
  `HarnessTests.testMood` checks each saved change is passed on;
  `RuntimeTests.testAPassMumblesAndChangesTheMood` waits for a `state`
  with `"mood":"grumpy"` on the link after Jev's pass.
- **`make fw-test`:** 115 pass. New: `test_every_mood_has_a_name`
  (the seven names round-trip; `cheerful`, `annoyed` and unknown names
  read as happy) and `test_state_carries_the_mood` (a state without a
  mood, or with an unknown one, is happy again). `test_state_has_no_parked_fields`
  now expects gen-2's `mood` object to read as happy.
- **`make fw`:** the board firmware builds; RAM 13.9%, flash 55.1%.
- **`make sim`:** 10 scenarios, 0 expect failures, 0 new or changed
  pictures, since nothing draws the mood yet.
- **`make tools-test`:** passes, with `PlayTests.test_play_sets_the_mood`.
- **`Boop --snapshots`:** 42 PNGs, as before.

Not run: the board over USB (L4), since the face doesn't change yet.
