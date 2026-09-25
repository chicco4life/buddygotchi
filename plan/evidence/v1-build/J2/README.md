# J2: Soak and polish — Passed

2026-09-26. Board `b00p-54fe`, firmware 1.0.0 (F5's build, unchanged), over
USB through `boopctl bridge`. Webcam off for this run (owner's decision of
05:36), so no L3 checks ran.

## Done when

| Check | Result |
| --- | --- |
| 30-minute soak with replayed traffic and the Apple brain: no resets, leaks or stuck states | **Pass.** `tools/boopctl e2e --soak 30 --brain apple` |
| All tests green | **Pass.** `make test` 166/166, `make fw-test` 74/74 |
| All goldens reviewed | **Pass.** `tools/boopctl sim`: 10 scenarios, 0 expect failures, 0 new or changed pictures. All 80 goldens looked at again on one sheet ([goldens.png](goldens.png)); each was reviewed when it was accepted (F2, F3) |
| `README.md` describes the new product and commands | **Pass.** Rewritten: what Boop is, using it, the board's gestures, the repo, `make` targets, `boopctl` (including `e2e --soak` and `voice`), `boopdev`, `voicegen` |

## The soak

`boopctl e2e --soak MIN` (new; VERIFICATION.md §2) runs the J1 fixtures (a
Claude session and two Codex sessions, with needs-you, cheers and an oops)
through the real `boop-hook`, the headless app with Apple's model, the bridge
and the board, round after round. It presses BOOT between rounds (the
brain's `tap` trigger), then waits a quiet minute and checks the board is
back on the plain face.

From [soak-apple.json](soak-apple.json):

- 31.2 min, 37 rounds, 962 hooks, 0 checkpoint misses.
- Hook to state on the board: p50 80 ms, p95 98 ms (n 427).
- Board: uptime rose across all 113 samples (no reset); heap minimum 72,484
  bytes from start to end (drift 0); `audio.out.errors` 0.
- App: stayed up; RSS 51 MB at the start, 26 MB at the end (max 52 MB), so no
  growth.
- End: `screen` face, `base` idle, no `attn`, no moment. Nothing stuck.
- Brain: 333 answers (128 `face` and 168 silent on events, 37 `face` on
  taps); 5 lines spoken, all on events. The speech limit counts on the app's
  clock, which the fixtures move about 9 minutes forward per round, so 5
  lines in 31 real minutes is within it.

Files: [soak-apple.txt](soak-apple.txt) (every step),
[soak-app-apple.log](soak-app-apple.log) (the app's trace),
[soak-brain-apple.jsonl.gz](soak-brain-apple.jsonl.gz) (the brain's
prompts and answers), and the two needs-you screenshots from the last round.

## What went wrong on the way

The first two soak attempts died on the USB debug channel, not in Boop:

1. At about 1 minute, twice: `timed out waiting for the board through the
   bridge`. A `dbg.ping`/`dbg.state` reply never arrived.
2. At 22 minutes: a `dbg.shot` whose header said 77,312 bytes (103,084
   base64 characters) arrived with 103,061. About 23 characters were lost
   from the board to the Mac.

Both runs showed no reset, no heap drift and no stuck state up to the point
they stopped. My best guess is the CH340 at 460800 baud on macOS, which
sometimes drops a run of bytes while the Mac is busy with Apple's model. The
soak now retries a debug request once and records it under `link_glitches`.
A second loss in a row still fails. The passing run had no glitches.

## Known issue

Over USB, a line lost from the board to the Mac is lost for good. That
includes an input like a tap, because the link has no sequence numbers or
checksums. The app resends `state` only when something changes. Bluetooth
is the everyday transport and isn't affected by the CH340. For J3's report:
consider framing board-to-Mac lines with a sequence number, or dropping to
230400 baud.
