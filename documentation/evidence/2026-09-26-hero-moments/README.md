# Hero moments — 2026-09-26

The owner picked four hero moments ([VISION.md](../../VISION.md) "Hero
moments"): a cheer for a finished turn, frustration at a failed one,
sadness when yelled at, and annoyance at a poke streak. This work makes the
last three real on the two-stage brain (PLAN.md A7) and puts all four in
the harness evals ([EVALS.md](../../EVALS.md) §5):

- A turn whose last test, build or deploy command failed finishes `failed`
  (Claude's `PostToolUseFailure`; Codex can't tell yet).
- The if-else classifier answers a yell (−18 dBFS for 300 ms, *proposed*)
  or being told off with `react(sad, mumble)`, and only words with "quiet"
  with `quiet`. The `quiet` action checks that itself, whichever classifier
  decided, and the core plays `zip` as quiet starts.
- The fourth tap within 3 s is a new input, "poked again and again": the
  rules side-eye you, and the classifier adds `react(annoyed, mumble)`, at
  most once a minute. On the device a tap no longer cuts a side-eye short.

## Checks that ran

| Level | Command | Result |
| --- | --- | --- |
| L0 Swift | `make test` | 210/210 passed, including `EvalTests` |
| Evals | `boopdev eval` | 8/8 passed ([eval.txt](eval.txt)): `04-be-quiet` replaces `04-shut-up`, and `06-tests-left-failing`, `07-told-off` and `08-poke-streak` are new. With the failed-check and poke-streak rules switched off in the core, `06` and `08` fail, so they check them |
| L0 firmware | `make fw-test` | 101/101 passed, including `test_a_tap_doesnt_cut_a_side_eye_short` |
| L1 | `tools/boopctl sim` | 12 scenarios, 0 expect failures, 0 new or changed pictures. The new `poke` scenario has no pictures |
| Board build | `make fw` | Builds: RAM 14.0%, flash 55.7%. Not flashed: the owner's `make run` was connected over Bluetooth |
| L5 | `boopdev brain --classifier rules --writer apple` | PASS ([l5-rules-apple.txt](l5-rules-apple.txt)): 58 inputs, all answered on the menu, 46/46 slots filled, 1 call dropped by an action (a note already there). The four poke streaks got an annoyed *"…nope"*; "shut up for an hour", "stop talking for a bit", "can you keep it down…", "you're so annoying" and both yells got a sad mumble; the two "be quiet" lines got `quiet(30)` |

## Not yet checked

- L2 on the board: `tools/boopctl run poke`, with the Mac app quit.
- The owner's checks: the yelling threshold on a real voice, a real Claude
  turn that ends with failing tests, "be quiet" and "shut up" out loud, and
  poking the board (morning checklist rows 11, 13, 19 and 20 in
  [PLAN.md](../../PLAN.md)).
- Jev deciding: it reads the new steering examples and feeling
  descriptions, but wasn't run (it needs the owner's key).
