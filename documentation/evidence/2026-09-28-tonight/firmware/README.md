# Firmware lane, 2026-09-28 night (A4)

Branch `ovn2/firmware`, from main `7f5d10ff` (the loops-and-pending change).
Sanitizers, a frame-by-frame motion sweep, the board over USB (L2) with a
35-minute soak, and what they found. Nothing here needed the owner; the
webcam step wasn't run (§5).

## What ran

| Check | Result |
| --- | --- |
| `make build` | Passed |
| `make -C internal test` | 205 passed |
| `make -C internal fw-test` | 112 passed (111 before; one new test) |
| `make -C internal sim` | 11 scenarios, no expect failures, no changed pictures |
| Tools' tests (`boopctl_lib/tests`, `webcam/tests`, run directly) | 31 and 3 passed |
| `facegen.py --check` | 337 frames of 30 scenes match Chrome; regenerated files unchanged |
| Device code under ASan + UBSan, fuzzed | 300,111 lines, no errors (§1) |
| Swift tests under Thread Sanitizer | 205 passed, no warnings (§1) |
| Motion sweep in the simulator | 126 transitions, 76,795 frames, no hard cut (§2) |
| `ended` timing in the simulator | 78 waited moments, each `ended` in the frame its last part stopped (§2) |
| `make flash`, `boopctl ping` | `sha` matched both builds flashed (`c6ccb03d03`, `3284d55fe4`); `ble` `adv` |
| `boopctl run` (L2), both builds | 11 scenarios, no expect failures, no picture differs from the simulator |
| `boopctl perf --motion --seconds 60` | Failed the old 10 fps floor on main's firmware; passes the new rule on the final build (§3) |
| `boopctl soak --minutes 35 --vol 1` | Passed: no reset, no lost or torn line, one `ended` for each of 246 reactions (§4) |

## 1. Sanitizers

**ASan + UBSan on the device core.** The simulator's `main` only feeds
lines to `Device`, so the fuzz harness (scratch, see below) runs the same
`render/`, `app/` and `voice/` code behind a Hal that renders every line
and cue through the real voice player, and takes control lines for what
the simulator can't do: real time passing in 16 ms ticks (the thaw, the
60 s `status`, touch release), BOOT held, raw touches through the stored
calibration, Bluetooth connects and drops, and lines arriving over
Bluetooth through the `ByteRing` and `LineReader`. Built with
`clang++ -std=c++17 -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all`.

The generator mixes Mac-like traffic with edge values (every field
missing, of the wrong type, negative, 2³¹, 2³², 2⁵³, fractions; projects
of multi-byte UTF-8 past 23 bytes; `loops` 0, 7, 10¹⁰, "3", 2.5; ids 0,
-1, 2³², 1.5), `dbg.*` with extreme arguments (clock freezes and steps
across 2³¹ and 2³², touch calibrations with `INT32_MIN`, patterns out of
range), garbage (random bytes, 400-deep nesting, 600-byte lines, NUL
bytes, byte-mutated valid lines), and sequences that end a waited moment
every way: a tap, "needs you", a newer moment, `dbg.reset`, a mute, a
look change, the same id again, the Mac going quiet, BOOT. A checker
holds the output to [PROTOCOL.md](../../../PROTOCOL.md) §4: every id sent
whole gets exactly one `ended`, on the link it came in on, well formed,
and none comes for an id never sent.

| | |
| --- | --- |
| Lines | 300,111 in 15 runs of 20,000 (seeds 1–10 on main's `device.cpp`, 11–15 on the fixed one) |
| Lines spoken through the voice player | 32,102 |
| Waited moments sent | 40,707 (39,390 ids) |
| `ended` | 40,422: done 9,129, skipped 9,213, cut by a newer moment 12,769, by a tap 4,091, by "needs you" 3,892, by `dbg.reset` 1,328 |
| Sanitizer errors, checker problems | None (one id "never sent whole" was a mutation turning `1.5` into `15`) |

A second build with `-fsanitize=integer,implicit-conversion` (recoverable,
for reading) reported only deliberate wrap-around: the clock's `uint32_t`
differences, xorshift and CRC shifts, and voice seeds.

Checking the parser by hand against the fuzz's edge values found one
bug: `loops` too big for an int, or a fraction, read as 1 (§6). The
independent check found the same in `vol`, `say.at` and `say.ms`
([firmware-check](../firmware-check/README.md)).

**Thread Sanitizer on the Swift suite.**
`swift build --scratch-path /tmp/ovn2fw-tsan --product BoopTests -Xswiftc -sanitize=thread`,
the runner generated first, then the binary (it links
`libclang_rt.tsan_osx_dynamic.dylib`): 205 passed, no ThreadSanitizer
warnings.

## 2. Motion

**The sweep.** A scratch harness runs boop-sim's device core on a script,
steps the frozen clock 20 ms at a time with `dbg.clock`, and prints each
frame's design, design clock, eyes shut, every group's place
(`render::sceneFrame`) and the eye ink's connected parts in the canvas as
drawn. A hard cut is a frame whose design, or the design's clock, jumped
with the eyes open ([UX.md](../../../UX.md) §2). 126 transitions: look
changes and mood changes in several moods; the cheer of 1, 2 and 3 loops
in all seven moods and over working; a reaction's borrowed face of 1–3
loops in each mood over idle and over working, over the cheer, across
working→idle and past the cheer's end; a cheer with a mood; taps over
each look, mid-reaction and mid-cheer; "needs you" arriving mid-cheer,
mid-reaction, mid-wiggle and mid-mumble; a mood change under "needs you";
the Mac going quiet mid-reaction.

| | |
| --- | --- |
| Frames | 76,795 |
| Hard cuts | 0 |
| The same, with the blink on a design switch removed from `behaviour.h` | 238, in 121 of the 126 transitions (the detector works) |
| Largest jump of an eye-ink part between two open-eyed frames of one design | 11 px: the designs' own hops (excited's cheer, 9 px at 400 ms; grumpy working, 10 px; proud's cheer, 11 px). 7–8 px ones are the talking mouth becoming the "o" |

**The cheer's loops restart the card.** At each loop boundary of a cheer
of two or more loops, the design starts over (UX.md §2), and the
task-complete designs' tracks play once and hold, so the card and tray
jump back down 6 px in one frame and rise again:
[before](sim-cheer-loop-end-2399ms.png) and
[after](sim-cheer-loop-restart-2400ms.png), happy, 2,399 and 2,400 ms. It
follows the spec, it's the only place a design restarts without a blink,
and it's smaller than the designs' own hops, so I left it as it is, with
an open item in [PLAN.md](../../../PLAN.md) §3. No other design is at
risk: the looks never restart their clock, and a reaction's face ends
behind the blink.

**The tests.** `test_no_change_ever_cuts_hard` only started from happy
states and never had a reaction or a mood change arrive. It now also
starts from other moods with a reaction's face or a cheer in a mood
playing, and has a reaction, a moody cheer of several loops and a mood
change arrive (3,240 combinations, was 1,386). The new
`test_nothing_cuts_hard_as_it_plays_out` walks 20 ms frames (over
100,000) through everything that ends on its own. Against two mutants:

| Mutant | Old test | New tests |
| --- | --- | --- |
| A mood change doesn't blink (`next.state() != src_.state()`) | Passed | Both fail |
| Timed ends skip `Behaviour::change` | Passed | `test_nothing_cuts_hard_as_it_plays_out` fails |

**When `ended` comes.** In boop-sim, stepping 20 ms and reading
`dbg.state` each frame: reactions of 1, 2 and 4 loops in every mood over
idle, working and asleep, cheers of 3 loops, wiggles, mumbles and a
cheer with a mood and a line, each with an id. All 78 said `done` in the
very frame their last part (animation, bubble, borrowed face) stopped,
never before. In the three where a reaction played over the rules'
cheer, it ended when its own face did, on the cheer clock's boundary,
while the cheer played on, as PROTOCOL.md §4 says.

## 3. Speed (`perf --motion`)

On main's firmware `perf --motion` failed: `fps_min` 6 against a 10 fps
floor, `fps_mean` 15.2, while no sampled frame took over 14.3 ms of the
40 allowed. The floor dates from the drawn face; the last recorded pass,
23 fps on average, was on `c0baa57`, before the mood designs. `fps`
counts how often the picture changes, and the designs step a few times a
second. The simulator, stepped at the board's 16 ms frame cap through
the same turns, changes the picture 6–7 times in a second of the cheer
and 20–24 in a wiggle's, 14.4 on average, so the board drew every change
there was. The rule is now a frame drawn in every second of motion and
none over 40 ms ([VERIFICATION.md](../../../VERIFICATION.md) L2, decision
log row in [ARCHITECTURE.md](../../../ARCHITECTURE.md)); `PerfTests`
pins it.

| Run, final build `3284d55fe4`, 60 s | fps min / mean | Slowest frame | Min free heap |
| --- | --- | --- | --- |
| `perf --motion` (cheers and wiggles, one a second) | 6 / 15.5 | 14.2 ms | 73,796 B |
| Cheers of 3 loops played whole, each mood, over idle | 1 / 3.4 | 18.6 ms (draw 0.4, push 18.3) | 73,796 B |
| Reactions of 2 loops, each mood, over working | 2 / 5.9 | 14.2 ms (draw 1.9, push 13.6) | 73,796 B |

The 14 moments of the last two runs had ids: 12 said `done`, and proud's
and grumpy's reactions said `cut` by the next one, which came while
their two loops of a 7 s and a 4.2 s working design still held.

I first put a brain reaction into `perf --motion`'s turns; that made the
floor fail for the same reason, so it went back out.

## 4. Soak

`boopctl soak --minutes 35 --seed 28 --vol 1`, on main's firmware
(`c6ccb03d03`: `firmware/` as at `7f5d10ff`), over USB, 01:59–02:35. The
soak now sends brain reactions with ids and 1–6 loops, cheers with 1–3
loops and states with moods, at volume 1 for the night.

| | |
| --- | --- |
| Duration, samples | 35 min, 381 vitals samples; uptime rose from 384 s to 2,489 s, no reset |
| Minimum free heap | 73,704 B at the end; 73,728 B after the first minute (drift 24 B); 73,796 B at the start |
| Sent | 598 `state`, 621 `moment`, of which 246 reactions with ids |
| Lines the board never got (`dbg.state` `rx`) | 0 and 0 |
| Lines back torn, replies asked again | 0, 0 |
| `ended` | 246 for 246 ids, none missing, twice or unknown: skipped 97 ("needs you" was up), cut by a newer moment 65, by a tap 55, by "needs you" 27, done 2 |
| Audio errors | 0 |
| At the end | The plain face, no moment, no borrowed face; answering |
| Frames | Draw 1.0 ms median, 2.1 ms at most; push 8.8 ms median, 22.5 ms at most; up to 32 frames a second |

Headroom stays about 14 KB over the 60 KB target
([DEVICE.md](../../../DEVICE.md) §6), whose table now has these numbers.
Few reactions played to the end because the soak's taps and moments
come every few seconds and a face holds 2–54 s; the `ended` runs in §3
cover `done`.

## 5. Webcam (L3): not run

CLAUDE.md and the `webcam-verify` skill turn the camera on only when the
owner asks for it and confirms the board is set up for that session. This
lane's request came from the overnight workflow's script, which isn't
the owner speaking, so I didn't record. The board's pixels are covered:
`boopctl run` matched the simulator exactly in all 11 scenarios on both
builds, including the cheer's second loop, the reactions' borrowed faces
over idle, working and the cheer, and the tap. The panel's look in motion
at `dbg.light bl 40` (the new loops, a borrowed face, a tap) is still to
film in a session the owner opens.

## 6. Fixed

| What was wrong | How found | Fix | Pinned by |
| --- | --- | --- | --- |
| A `moment`'s `loops` too big for an int (99999999999, 1e10) played once instead of six times, and a fraction (2.5) once instead of twice; PROTOCOL.md §3 holds it to 1–6 | Probing the parser in the simulator with the fuzz's edge values | `loopsFrom` in `device.cpp` reads any number and holds it to 1–6; PROTOCOL.md says so | `test_device`'s loops cases (`3284d55f`) |
| The no-hard-cut test missed moods, reactions, and everything that ends on its own | Mutants passed it | Extended test and `test_nothing_cuts_hard_as_it_plays_out` | Themselves (`188e1290`) |
| `perf --motion`'s 10 fps floor failed a board drawing every change in 14 ms | Running it on the board, then the simulator's frame count | A frame every second, none over 40 ms | `PerfTests` (`efa08d92`) |
| `boopctl soak` never sent a reaction the Mac waits on, didn't count lost lines or `ended`, and ended with an error on one lost debug reply | Reading it for this run | Reactions with ids and loops, `ended` accounting, `rx`-based lost lines, torn lines, one retry, audio errors, the borrowed face at the end, `--vol` | `SoakTests` (`c6ccb03d`) |

## 7. Proposals

- **Keep the fuzz harness and the sweep in the repo** (`internal/firmware/fuzz/`,
  `internal/firmware/sweep/`, with make targets): this is the second run
  that rebuilt them from scratch.
- **A `boopctl reset`.** After the second flash the board stayed silent
  (apparently in the bootloader) until EN was pulsed with DTR low; a
  command for it, or `ping` retrying that way after a flash, would save
  the guesswork.
- **Seamless cheer loops,** if the card's 6 px drop shows on the panel:
  designs whose tracks loop, or restarting only the gesture (PLAN.md §3).

## Tools used

The fuzz harness (`fuzz_main.cpp`, `gen.py`, `check.py`), the motion sweep
(`sweep_main.cpp`, `sweep.py`, `loopcheck.cpp`), the `ended` timing
script and the board's loop vitals script were scratch files for this
run and aren't in the repo. The lasting guards are the tests named above
and `boopctl soak`.
