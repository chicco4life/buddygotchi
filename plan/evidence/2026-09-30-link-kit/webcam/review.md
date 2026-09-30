# Webcam review: the turn on the board

2026-09-30 23:30 KST, bench board, firmware `baf548d12a` (kit 1), MacBook
Air camera at 30 fps, screen cropped at `0.38,0.07,0.46,0.55`, volume 0,
clock running. Raw footage stayed local; `turn-handover.png` is one sheet
of consecutive cropped frames (the screen reads upside down to the camera).

**Scenario.** Over USB, as the Mac would send them: a brain `react`
(`previous.finish`, proud, `next`, ttl 5000), 0.1 s later a second
(`previous.work`, curious, `next`), 0.2 s later a rule one-shot
(`starting`, `if_free`). `dbg.state`'s `turn` was read every 0.25 s.

**What the board said** (seconds from the first `do`):

| t | Event |
| --- | --- |
| 0.33 | `ended` 103 `skipped` `busy`: the one-shot, during the first line |
| 0.35 | holder 101 (busy), 102 waiting, 4.8 s of its ttl left |
| 2.29 | `ended` 101 `done`; 102 takes the turn (2.31) |
| 4.28 | 102's line over; 4.83 it rests (bubble + 0.5 s) |
| 5.09 | `ended` 102 `done`; the turn is free |

**What the screen showed.** The "Finish" bubble and the proud face from
1.23 s to 3.40 s of video (the take's 987 ms plus the 1.2 s bubble), no
`starting` animation, then a blink into the curious face with "Work" at
3.43 s, the eyes' blink frames at 3.43–3.53 s, no hard cut. The second
reaction never cut the first's line.

**Verdict:** pass for this scenario. Consecutive frames were reviewed as
sheets, not in real-time playback; this isn't a full hardware pass (see
`board-run.txt` for the scenarios on the board, and the soak).
