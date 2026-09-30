# LinkKit (piece C), JHarness, and Boop on all three pieces

The overnight run of 2026-09-30, on branch `link-kit` from `c6570f60`
(main-refactor, which holds piece A, plus piece B's branch). The owner's
brief: implement the proposal "Boop open-source split: the device link
(C) and how it all joins"; keep the architecture discussed, fixing bugs
and odd architecture on the way; behave as main does, at main's quality;
separate and document each module cleanly (BrainKit renamed JHarness);
at most five evals.

## Where things end up

| Folder | Module | What it is |
| --- | --- | --- |
| `agent-hooks/` | A: AgentHooks | Hooks to events, sessions and "needs you" (already its own package) |
| `jharness/` | B: JHarness | The multiple-choice harness: log, lines, rules, outputs, prompt, loop |
| `linkkit/` | C: LinkKit | The device protocol: the Swift host side and the glue to JHarness, and in `linkkit/device/` the C++ device library |
| `app/`, `firmware/` | Boop | The app on top of all three |

## Steps

1. **JHarness** (done, 18d9a0a0): BrainKit moved out into `jharness/`,
   renamed, its tests in the package, three bugs fixed.
2. **The device lane:** `linkkit/device/` (the generic C++ library:
   dispatch, `hello`, the turn, the clock, the generic debug messages),
   Boop's firmware on it, the new wire (`hello`, `state`, `do`, `ev`),
   the native tests and the simulator's scenarios, and `boopctl`.
3. **The Mac lane:** the LinkKit Swift package (wire, transports, link),
   the JHarnessLink glue, and Boop's app on it; `MomentSchedule` shrinks
   to the requests in progress, since the device now times the queue.
4. **Parity and performance:** what A and B changed that a person could
   notice, checked against main, and B's per-tick and per-pass costs.
5. **Integration:** the board over USB (flash, the scenarios on the
   board, the pipeline check), the webcam, perf and soak, evals.
6. **Docs:** each module's README and SPEC, how they tie together, the
   specs in `plan/`.
7. **A final review** of the whole change, then the commit.

The contract both lanes built against is [linkkit/SPEC.md](../../../linkkit/SPEC.md)
(the generic protocol) and Boop's vocabulary on it,
[PROTOCOL.md](../../PROTOCOL.md).

## Evidence

- [golden-states-on-main.txt](golden-states-on-main.txt): main builds the
  same 387 prompt states as the A and B branch.
