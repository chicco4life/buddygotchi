# Overnight pass: firmware reliability and performance

2026-09-27. The firmware lane of the overnight pass: decisions and timers
in `firmware/src/app/`, the links, the voice player and the build. No
board, USB or webcam checks were run here; those come after the merge.

## What ran

| Check | Result |
| --- | --- |
| `make fw-test` | 105 test cases pass (99 before; each new one failed before its fix) |
| `tools/boopctl sim` | 10 scenarios, 0 expect failures; the only changed pictures are the two below, looked at and re-accepted |
| `make fw` | Builds after every commit (not flashed) |

## Pictures

`strip-no-app-before-after.png`: the layout scenario's no-app shot before
(left: a stale amber "1 needs you", the working count and the quiet icon)
and after (right: only the unplugged icon).

`reconnect-before-after-idle.png`: the base scenario's `reconnect` shot,
100 ms after the Mac's state comes back. Left, before: the "blink" held
the eyes shut, the same as asleep. Middle, after: the eyes most of the
way open and the unplugged icon gone. Right: the idle face it blends to.

## Measurements

**Redraws.** With the clock running and the face always moving (asleep),
a loop that ticks every millisecond drew 1,000 frames a second before and
62 after (`test_motion_redraws_at_most_every_16ms`). On the board, the
e2e hardening run measured 129-156 fps of redraws, most of them repeats.

**Press.** The first frame that differs from the unpressed face after a
BOOT press, with a loop pass every millisecond: +20 ms on the idle face
and +15 ms on the working face, the same as a frozen clock drawing every
step (`test_the_redraw_cap_doesnt_delay_a_press`). Before the press was
exempt from the cap, the idle face's came at +32 ms.

**Firmware rebuilds** (`make fw`, counting `Compiling` lines):

| Change | Before | After |
| --- | --- | --- |
| Nothing | 0 | 0 |
| One edit on a clean tree ("-dirty" appears) | 279 objects, 14.4 s | 2 (the file and board_hal.cpp), 8.8 s |
| A commit ("-dirty" goes, the SHA changes) | 279 | 1 (board_hal.cpp) |
