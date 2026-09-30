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

## Results

| Check | Result |
| --- | --- |
| Prompts against main | [golden-states-on-main.txt](golden-states-on-main.txt): main builds the same 387 states as this branch, byte for byte |
| A working day, scripted, against main | 193 turns both; 427 passes and reactions here, 426 on main; 17 quiet check-ins against 16; no mood bounces either way ([workday-main-vs-branch.md](workday-main-vs-branch.md)) |
| Performance after two days | per event 0.34 ms (main 0.31, B before the fix 1.72), per tick 0.05 ms (main 0.05) ([parity.md](parity.md)) |
| Swift tests | BoopTests 269 (+1 opt-in soak), agent-hooks 77, jharness 36, LinkKit 43, JHarnessLink 7 |
| Firmware tests | Boop's 168, the device library's own 53; `sim` 15 scenarios, all 80 goldens unchanged |
| The board, scenarios | [board-run.txt](board-run.txt): 15 scenarios, 0 expect failures, 0 pictures differ from the simulator |
| The board, pipeline (L4) | [board-e2e/](board-e2e/e2e-scripted.txt): PASS; hook to state on the device p50 80 ms, p95 105 ms; 9 brain reactions, every one ended |
| The board, soak | [board-soak-6min.json](board-soak-6min.json): 38 reactions each ended once, nothing lost or torn, no reset, heap drift 0, least free heap 61,188 bytes (about 2.3 KB less than before: the four queued calls' argument slots; the budget is 50 KB) |
| The board, webcam | [webcam/review.md](webcam/review.md): a reaction waits for the line before it, a one-shot is skipped while a line plays |
| `linkkit-bridge` | [linkkit-bridge.txt](linkkit-bridge.txt): on the board, ping, `hello` and a `do`'s `ended` through it |
| Evals (1 of the owner's 5) | [eval-1.txt](eval-1.txt): 55/60 (1 known gap); the four failures (13, 15, 40, 52) are the ones main's own recent evals fail by turns (2026-09-29 overnight's baseline and evals 2 to 4) |

Not checked: Bluetooth (an agent's shell can't use it: the owner's `make
run`), and the Mac app's popover by eye (`Boop --snapshots` draws it).
