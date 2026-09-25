# J1: End to end over USB

2026-09-26, the iteration after A4. Board flashed with this milestone's
firmware (F4 plus the `rx` counts in `dbg.state`).

## What was built

| Part | Where |
| --- | --- |
| `boopctl e2e` / `make e2e`: bridge, headless app with throwaway state, fixtures through the real `boop-hook`, checkpoints, latency, memory, privacy and ordering checks, optional webcam clip | `tools/boopctl_lib/e2e.py`, `cli.py`, `cam.py` (`clip(play=…)`), `Makefile` |
| Fixtures: a Claude session (prompt, tools with topics, `PermissionRequest` + `Notification`, a 6-minute `Stop`, a `StopFailure`); Codex approvals answered at 0.5 s and after 10 s; a 10 s version of the Claude session for the camera; the expected memory | `app/Tests/Fixtures/hooks/e2e/` |
| `dbg.state` counts `state` and `moment` messages received (`rx`), so latency is measured to the board | `firmware/src/app/device.cpp`, `device.h` |
| Headless: `{"dev":"advance","ms":N}` moves the app's clock (hooks are now timed on it); `--trace` logs every hook and every line to the device, marked `rules` or `brain` | `app/BoopKit/App/Runtime.swift`, `app/Boop/Headless.swift` |
| **Fix:** the brain's moments wait until the rules' moment and the core's follow-ups have played (`DeviceMoment.playMs`, `Core.followUpsPending`) | `Runtime.swift`, `Actions/Action.swift`, `Core/Core.swift` |
| `boopdev replay` skips `expect` lines and treats `advance_ms` as time | `Adapters/Replay.swift` |
| Specs: VERIFICATION §2, §3 (`rx`), L4 rewritten; BEHAVIORS §3; ARCHITECTURE §3.2 and three decision-log rows | `plan/` |

## The bug J1 found

In the first run the cheer for the 6-minute turn and the oops for the failed
one never showed: the rules brain answers in 0 ms, so its `face` replaced
the rule moment 7 ms later (`proud` over `cheer`, `side_eye` over `oops`).
Apple's model, about 1.5 s later, cut the oops short too, and the core's own
`side_eye` follow-up then cut off the brain's face. Now a brain moment is
held until the last rule moment has played (lengths mirror the firmware's
`animDuration`) and no follow-up is pending. `listening` and `thinking` hold
nothing back, because the reply is meant to replace `thinking`.

## Checks

| Check | Result | Evidence |
| --- | --- | --- |
| L0 `make test` | **163/163 pass** (3 new: brain waits for the cheer after a clock jump, moment lengths, replay skips checkpoints) | |
| `make fw`, `make fw-test` | Pass; 61/61 firmware tests; flash 43.2% | |
| L4, rules brain: every checkpoint | **Pass**: working; Claude "needs you" 27 ms after the hook's `state`, rung 1, still there after 3 s; cleared on `PostToolUse`; `cheer` on the 6-minute `Stop`; `oops` on `StopFailure`; Codex quick: no "needs you" for 3.5 s after the request; Codex slow: none until 1.8 s, then "needs you" (codex · landing) by 2.6 s, cleared on `PostToolUse`; both cheer | [e2e-rules.txt](e2e-rules.txt), [e2e-rules.json](e2e-rules.json), [app-rules.log](app-rules.log) |
| L4 latency, hook launch to `state` on the board | **p50 72 ms, p95 91 ms**, max 91 ms (14 of 26 hooks send a `state`; the rest change nothing). `boop-hook` itself takes ~27 ms | same |
| Memory and XP | **Pass**: xp 8 (5 for the day's first activity + 3 finished turns; the failed one earns nothing), level 1; Happened has both Claude lines and both Codex finishes; `settings.json` finished 3, projects jetpack and landing | [memory-long-term.md](memory-long-term.md), [memory-short-term.md](memory-short-term.md), [settings.json](settings.json) |
| Topics reach the brain | **Pass**: `topic: tests`, `topic: deploy`, `error: rate limit` in the triggers | `/tmp/boop-e2e/brain.jsonl` (not kept) |
| Privacy | **Pass**: no `PRIVATE_` marker from the fixtures in any app file or the brain's log | e2e-*.txt |
| Brain's moments after the rule reactions | **Pass** with both brains: rules brain 2 moments, 1.4–1.75 s after the reaction, each after the rule moment ended; Apple 7 moments, 1.5–3.2 s after, none early, none cut off | e2e-*.txt |
| L4, Apple's brain | **Pass**: same checkpoints, p95 92 ms | [e2e-apple.txt](e2e-apple.txt), [app-apple.log](app-apple.log) |
| Screenshots at checkpoints | Claude and Codex "needs you" | [claude-needs-you.png](claude-needs-you.png), [codex-needs-you.png](codex-needs-you.png) |
| Clean stop | App and bridge exit 0; both sockets removed | e2e-*.txt |
| L3 webcam: a full Claude session through the pipeline | **Reviewed, pass.** Framing check passed first. Working (0.1 s) → "needs you", bubble `claude · jetpack`, amber strip (0.8 s) → nod on approval (3.0 s) → size-2 cheer, warm eyes (3.4–4.9 s) → the brain's "~~~ finally" with the proud face, after the cheer (4.9–7.4 s) → asleep, it being 5 am (7.8 s) | [clip-e2e-session.png](clip-e2e-session.png) |

## Notes

- The first launch of a freshly built `boop-hook` took 273 ms (macOS
  checking the new binary) and made the first run's p95 309 ms. `boopctl
  e2e` now runs it once before the fixtures; every later launch is 7–30 ms.
- Latency is an upper bound: it includes the ~15–20 ms `dbg.state` round
  trip the check polls with. A 10 s keepalive landing inside a hook's
  500 ms window would be counted as that hook's `state`; none of the runs'
  numbers look like that (60–92 ms).
- The Happened times read 05:02–05:05 while the run was at 04:56: the
  clock jumps (6.7 min, 40 s, 45 s, 45 s) are real time as far as the app
  knows.
- Apple's choices are still A3's problem, not J1's: it met most events with
  `side_eye` or `curious`, including a turn starting.
- The Codex grace check allows the tick: "needs you" shows 2–3 s after the
  request, because the core checks the grace on its one-second tick.
