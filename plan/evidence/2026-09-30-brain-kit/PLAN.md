# Brain kit (piece B): plan and progress

The owner asked (2026-09-30) for the generic multiple-choice harness,
"B", to be written up as a spec and then built, with Boop moved onto it,
without stopping until done. The spec is [plan/kit/BRAIN-KIT.md](../../kit/BRAIN-KIT.md).

## The bar

- Boop keeps working after every commit: `make build`, `make -C internal
  test` and `make -C internal tools-test` pass.
- Boop's prompts stay byte-identical: no Jev key here, so no steering
  eval can check a wording change. `GoldenStateTests` pins every state
  the 60 eval scenarios build, with a scripted brain, before anything
  moves; every step keeps it green.
- Specs change in the same commit as their code.

## Steps

| # | Step | State |
| --- | --- | --- |
| 0 | Golden states: every scenario's states pinned from today's code | |
| 1 | The spec, `plan/kit/BRAIN-KIT.md`, with the plan index and the CLAUDE.md table | |
| 2 | `BrainKit` target: the generic files moved as they are (contracts, brain, Jev, line file); BoopKit re-exports it | |
| 3 | Open up `Event`: `{seq, at, source, kind, line?, data}`, the log (`Log`, `LogView`) in BrainKit, Boop's typed view of an event, old transcript lines still read; tools read the new lines | |
| 4 | The kit's harness: inputs and transforms, rules and `did`, outputs and `ended`, `Choice`, the prompt builder, the loop, the tick, with its own tests (Beacon's timeline) | |
| 5 | Boop on the kit: the view as transforms, the pipeline as rules, mood as a `Choice`, react's `run(now:)`, the runtime, evals, headless and boopdev rewired; specs | |
| 6 | Beacon, the second tiny example, in `internal/examples/` | |
| 7 | Checks: build, tests, tools tests, headless run with the scripted brain, golden states; the evidence below | |

## Decisions made while building

(Added as they come.)

## Evidence

(Added at the end.)
