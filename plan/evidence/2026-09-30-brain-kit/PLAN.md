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
| 0 | Golden states: every scenario's states pinned from today's code | Done, 2cad8ddd |
| 1 | The spec, `plan/kit/BRAIN-KIT.md`, with the plan index and the CLAUDE.md table | Done, 58c89b30 |
| 2 | `BrainKit` target: the generic files moved as they are (contracts, brain, Jev, line file); BoopKit re-exports it | Done, 8c7dcdf6 |
| 3 | Open up `Event`: `{seq, at, source, kind, line?, data}`, the log (`Log`, `LogView`) in BrainKit, Boop's typed view of an event, old transcript lines still read; tools read the new lines | Done, 0575fa37 |
| 4 | The kit's harness: inputs and transforms, rules and `did`, outputs and `ended`, `Choice`, the prompt builder, the loop, the tick, with its own tests | Done with 5, f38a766c |
| 5 | Boop on the kit: the view as transforms, the pipeline as rules, mood as a `Choice`, react's `run(now:)`, the runtime, evals, headless and boopdev rewired; specs | Done, f38a766c |
| 6 | Beacon, the second tiny example, in `internal/examples/`, with `beacon` and `kit-emit` | Done |
| 7 | Checks: build, tests, tools tests, headless run with the scripted brain, golden states; the evidence below | |

## Decisions made while building

- **Messages are whole sentences.** The kit shows a `did`'s message as
  written, and adds nothing but ` (in progress)`. The brief had HISTORY
  write `<Name> did …` from phrases; that would have reworded Boop's
  lines, which only an interleaved A/B eval with Jev could check.
- **Holds are registered apart** (`h.hold(kind) { … }`), not a `when:`
  argument: with both closures on `input`, Swift's trailing closure
  matched the hold, silently.
- **Held events get a `pass` with `held`**, not a dropped one, so the
  day's summary and the popover's "Jev isn't answering" count only real
  calls.
- **A 0 gives way to any newer event that wakes the brain, answered or
  not.** Counting only the unanswered ones brought the passed-over ones
  back once the newer one was answered (found by `BrainKitTests`).
- **`h.batch`** lets Boop run the core in the same step as the event:
  the core needs the tap's finish, which isn't in the event.
- **The agents' lines use a fold of the log** (`TranscriptView.Fold`)
  that catches up to whatever event it's asked about: a cache of a
  function of the log, since re-folding a session for every event would
  be quadratic.
- **The working heartbeat keeps its own random timer**, reset from the
  log, so its waits, and every eval state, stayed the same.
- **Tap-cut reactions are held by the moment schedule**, which has the
  handle, until the pokes stop.
- **The mood lives in the transcript.** No `mood` file; after 24 hours
  with no change Boop starts calm.
- **The read-back window is the kit's 24 hours**, where it was the last
  two days' files.

## Evidence

(Added at the end.)
