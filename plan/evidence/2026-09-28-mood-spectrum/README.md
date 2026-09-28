# Mood spectrum V4: the integration

Updated 2026-09-29. The design package from `codex/boop-mood-spectrum-v4`
(`72ca30df`: the animation bank and the owner's mood graph) turned into
the shipped Boop overnight, on branch
`claude/mood-spectrum-integration-56192f`: 13 moods on the graph, 22
states, 770 designs with their sounds, on the Mac and the board. The
plan, its phases, the owner's decisions (D1–D11) and the lanes'
contracts are in [PLAN.md](PLAN.md); the decisions that change the specs
are the 2026-09-29 rows of the
[decision log](../../ARCHITECTURE.md).

## How it was built

Four lanes, each in its own worktree, merged here with `--no-ff`:

| Lane | What | Evidence |
| --- | --- | --- |
| states (P4) | The Mac's rules for the 22 states: `state.act`, its priority and 1.5 s hold, waiting, the rules' one-shots, `SubagentStart`, SessionStart's source, plan mode, the `inspect` topic | [states/](states/README.md) |
| art (P1–P3) | The bank as the one source of faces and sounds, facegen for its three SVG dialects, 13 moods × 22 states on the device, per-loop sound mix, `huge_app.csv` | [art/](art/README.md) |
| moods (P6–P7) | The mood graph with options built from the mood on every pass, calm at rest, `react.animation` success, failure or reply, 13 steering files, the evals | [evals/](evals/README.md) |
| device (P5) | The device plays `act`, the one-shots, the finish by outcome, pokes and tap barrages, lines in the voice window, the bubble in the bottom lane, blink steps for flip-books | [device/](device/README.md) |

Then, on this branch: the dashboard, the working day and the day's
summary for the new moods and finishes, the popover's copy, the specs'
sweep, and the board ([board/](board/README.md)).

## What ran, at the last commit

| Check | Result |
| --- | --- |
| `make build`, `make -C internal test` | 313 of 313 |
| `make -C internal fw-test` | 163 of 163 |
| `make -C internal sim` | 14 scenarios, 0 expect failures, 0 changed pictures |
| `make -C internal tools-test` | 63, 12 and 3 tests OK |
| `facegen --check` (in the art and device lanes) | 7,970 frames of 704 scenes match Chrome |
| The bank's `qa/check.mjs` and `validate.mjs` (art lane) | pass |
| Jev evals, committed steering (moods lane) | 53 of 55 scenarios in each of two clean full runs, every `always` one 5 of 5; `20-no-flail` is the known gap. The final steering's last run was cut off by HTTP 402 after scenario 12 |
| On the board over USB (L2, perf, 10-minute soak, L4 twice) | pass ([board/](board/README.md)) |

## Not done, and why

- **Jev.** The key ran out of credit at about 04:40 (HTTP 402), so the
  final steering hasn't had a full run, and the new states' lines (the
  rules' one-shots aren't in the transcript, but `act` changes nothing
  Jev reads) haven't been through the evals with the states lane merged.
  Rerun `make eval` once there's credit.
- **The owner's eye and ear.** The new moods' art and sounds are
  integrated as delivered (D9); nothing here is visual or listening
  approval. Nothing merges to `main` without the owner.
- **Bluetooth** is the owner's (`make run`).

## For the owner

- Look at the new moods and states on the board, and listen: the bank's
  offline review is `internal/boop-design/boop-sound-bank-v4/review/boop-moods.html`.
- The finish's line now starts about 5 s into its scene; a brain
  reaction just after a finish can wait past 5 s and be dropped
  ([board/](board/README.md)).
- The poke's words Jev reads are still `Boop wiggled on its own.` until
  the evals can check new ones (decision log).
- Pokes in the new moods run up to 7.9 s, against the old 0.7 s wiggle.
