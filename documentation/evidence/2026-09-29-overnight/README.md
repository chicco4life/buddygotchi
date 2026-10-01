# Overnight: test, simplify, speed up (2026-09-29 to 30)

The owner asked for a night of testing the Mac app and the board: find
bugs users would hit, simplify the architecture and cut code, make Boop
faster and smaller, without regressing any feature or eval. Budget: five
full `make eval` runs (four used); the board, flashing and the webcam
allowed; the microSD card left alone (nothing wrote to it).

The everyday app (`make debug`) was connected to the board over
Bluetooth, which replaces every USB test frame (VERIFICATION L2), so it
was stopped with SIGINT at 21:15 before the board checks. Restart it
with `make debug`.

## How it ran

1. Baseline: every check, the board's numbers, eval run 1.
2. Audit: ten read-only auditors (core, harness, runtime, hooks, the Mac
   UI, voice, firmware logic, firmware drawing, a headless pipeline
   tester, tooling), 102 findings, each put to one or two skeptics told
   to refute it: 49 confirmed, 45 partly, 8 refuted.
3. Three waves of worktree lanes implemented them, one commit per
   finding with a failing test first where it was a bug, and an
   independent reviewer read every lane; the reviewers' findings became
   the next wave. A separate sweep looked only for code to delete (22
   proposals, each checked). Lanes never touched the board.
4. The firmware and every board, webcam and eval check were done by the
   orchestrator alone, since one process can own the serial port.

## Checks at the end (`b3172d2b` and its firmware `3b85e610`)

| Check | Baseline (`a0d75321`) | End |
| --- | --- | --- |
| `make -C internal test` | 323 passed | 348 passed |
| ThreadSanitizer on the Swift tests | clean | clean (at `81789275`) |
| `make -C internal fw-test` | 163 passed | 164 passed |
| `make -C internal sim` | 14 scenarios | 14 scenarios, 12 goldens accepted once (below) |
| `make -C internal tools-test` | ok | 93 + 3 ok |
| `Boop --snapshots` | 48 panes | 74 panes, contrast checks pass |
| `boopctl run` (L2) | 14 scenarios match | 14 scenarios match |
| `boopctl perf --motion` | `ok: false` (heap 50.9 KB < 60 KB) | `ok: true`, heap 64.8 KB |
| `boopctl takes --only previous` | — | 20/20 takes played from the card, 0% timing error |
| `boopctl e2e` (L4) | fails one check (a fixture artifact, below) | passes |
| Soak | — | 30 min (NimBLE), 45 min (new push) and 30 min (the final firmware): no reset, heap drift 4 B, 0 B and 0 B, every reaction ended once |
| `make eval` | 54/57: 13 (2/3), 40 (1/3) flaky, 20 the known gap | run 2 54/57; run 3 54/57, the same three as baseline; run 4 53/57 (flakes, checked below) |

## Numbers

| Measure | Baseline | End |
| --- | --- | --- |
| Firmware flash | 2,341,507 B (74.4%) | 1,789,927 B (56.9%) |
| Firmware static RAM | 51,772 B | 48,084 B |
| Board free heap, idle | 51.3 KB | 65.2 KB |
| Board free heap, least in motion | 50.9 KB | 64.8 KB |
| Slowest frame drawn and pushed (`perf --motion`) | 32.7 ms | 10.9 ms |
| `Boop` release binary | 4,690,760 B | 4,356,472 B |
| `boop-hook` release binary | 231,544 B | 230,968 B |
| `boop-hook` launch to exit, 115 hooks | mean 10.5 ms (main, measured tonight) | mean 9.4 ms |
| Headless app after 1,380 hooks | RSS +7.3 MB (main) | RSS +2.8 MB (the hook server's autorelease leak fixed) |
| Swift test suite | ~28-40 s wall | ~18-26 s wall (lane's A/B) |
| `Boop --snapshots` | 15 s | 5 s |
| Menu-bar app idle (`--link none`) | too noisy to compare: 34-95 MB run to run on either build; CPU the same, ~0.25 s a minute | |

## Goldens accepted

- 12 pictures across `base`, `behaviour`, `blend`, `bubble`, `expression`,
  `life` and `needs_you`: only row 204 changes, where the strip's divider
  no longer paints over a design's own pixels (the older moods' working
  props, the yellow finish). Looked at before and after; the divider still
  shows over bare glass.

## Evals

- Run 1 (baseline, `a0d75321`): [baseline-eval.txt](baseline-eval.txt).
- Run 2 (`c4a8e90b`, after wave 1): [eval2.txt](eval2.txt). 15 and 24
  failed. 24 then passed 5/5 at HEAD against 3/5 on main. 15 traced to a
  garbled-talk Example added to `boop`'s PERSONALITY for 40: an A/B in
  the same window gave 6/9 without it and 0/9 with it, and a rule-wording
  variant did the same, so the steering change was reverted (`5bc03b81`)
  and the steering is main's.
- Run 3 (`eebdcea3`, after the simplify lanes): [eval3.txt](eval3.txt),
  the same failures as baseline.
- Run 4 (`c1eaabc3`, the final code): [eval4.txt](eval4.txt), 53/57: 15,
  50 and 52 failed, 13 and 40 passed. Nothing the evals run changed since
  run 3. Then, 5 runs each: 50 4/5 here against 5/5 on main, and in an
  interleaved A/B 9/9 on both; 52 4/5 here against 3/5 on main; 15 was
  1/6 on main earlier in the night. Flakes, not regressions: every
  scenario that failed in runs 2-4 fails on main at a similar rate.

## The pipeline check (L4)

`boopctl e2e` flagged a brain line cut short by the next brain moment,
on main's code and firmware too. Its cause was the codex fixture: it
jumped the headless app's clock 45 s while the line still played on the
board, so the app took the line for over and sent the finish, which cut
it. Real clocks don't jump mid-line; the fixture now waits 2.5 s first,
and the check passes on the board (p95 hook-to-screen 95 ms).

## Webcam

[webcam/review.md](webcam/review.md): the pattern and the moving face at
80 MHz, the busy strip and the needs-you sign; clean.
