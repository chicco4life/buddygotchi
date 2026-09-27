# Firmware lane, checked, 2026-09-28 night

An independent check of the [firmware lane](../firmware/README.md) on its
branch `ovn2/firmware` (six commits from main `7f5d10ff`): each fix read
and tested again, the sanitizer fuzz run again, the mutants run again, and
the numbers in its evidence held against the raw outputs. The board and
the webcam weren't used: the one fix below is in the parser, which the
native tests and the simulator cover, so it needed no board run.

## What ran

| Check | Result |
| --- | --- |
| `make build` | Passed, before and after the fix |
| `make -C internal test` | 205 passed, before and after |
| `make -C internal fw-test` | 112 passed, before and after (the new cases are in an existing test) |
| `make -C internal sim` | 11 scenarios, no expect failures, no changed pictures, before and after |
| `make -C internal fw` (the board build, not flashed) | Built: flash 1,102,535 B (56.1%), 32 B more than the lane's final build; static RAM 45,804 B, the same |
| Tools' tests (`boopctl_lib/tests`, `webcam/tests`, run directly) | 31 and 3 passed |
| `facegen.py --check` | 337 frames of 30 scenes match Chrome; outputs unchanged |
| The lane's fuzz under ASan + UBSan, on its final code | 80,029 lines (4 runs), no errors, one `ended` for every waited moment |
| The same on the fix below, with wider edge values | 120,043 lines (6 runs), no errors, no checker problems |
| The lane's mutant: no blink on a mood change | Both no-hard-cut tests fail on it, as the lane said |
| The lane's TSan build of the Swift tests, run again | 205 passed, no ThreadSanitizer warnings |

## 1. The fixes

**`loops` (`3284d55f`): right, and not the only one.** `loopsFrom`
reads any JSON number and holds it to 1–6; probing the fuzz binary with
cheers of `loops` 2.5, 1e10, 1e999 and -1e999 gave 2, 6, 6 and 1 loops,
and a string `"3"` 1. ArduinoJson 7.4.3 parses an exponent past a
double's range as infinity and never parses NaN (both off by default), so
nothing reaches the `int` cast out of range.

The same reading was left on the other numbers the device clamps
([PROTOCOL.md](../../../PROTOCOL.md) §3), each an `int` with a default
for anything else:

| Sent | Read before | Clamped, as the spec says |
| --- | --- | --- |
| `vol` 99999999999, -1e10, 9.9 | 6, 6, 6 | 10, 0 (muted), 9 |
| `say.ms` -1, 4294967296, 150.7 | 120, 120, 120 | 60, 400, 150 |
| `say.at` 1.5, -1e10 (2 syllables) | 2, 2 | 1, 0 |

The lane's fuzz already sent `ms` -1 and 2³², so its hand check of the
parser should have caught these. The Mac never sends such values. Fixed
in `f589fb93`: `heldTo(value, lo, hi, missing)` in `device.cpp` reads all
four, PROTOCOL.md §3 says the rule once above its tables, and
`test_say_and_volume_are_held_in_range` has the cases, which fail on the
lane's `device.cpp` and pass on the fix. The `id` row now says what the
device already did: a fraction or an id past 2³²−1 gets no `ended`.

**The no-hard-cut tests (`188e1290`): as claimed.** 9 states × 8
playing × 15 events × 3 times is 3,240 combinations (1,386 before). With
`behaviour.h`'s design-switch test changed from `scene()` to `state()`
(no blink on a mood change), `test_no_change_ever_cuts_hard` fails
("from state 0, playing 0, event 7 at +40 ms") and so does
`test_nothing_cuts_hard_as_it_plays_out` ("design 6 at 17997, then 0 at
18017"). The file was restored after.

**`perf --motion`'s rule (`efa08d92`) and the soak (`c6ccb03d`): sound.**
Read through: the soak hears `ended` lines only while it waits for a
reply, but it asks for vitals every 5 s, so none sits unread for long,
and it counts lost lines from `rx` read after its last send. `PerfTests`
and `SoakTests` pass.

## 2. The numbers

Held against the raw outputs the lane left (the soak's `--out` JSON,
perf's JSON and the loop-vitals JSON):

| Claim | Raw output |
| --- | --- |
| Soak: 35 min, 381 samples, uptime 384 s to 2,489 s | 381 samples, `up` 384,136 to 2,489,155 ms |
| Minimum free heap 73,704 B, 24 B drift, 73,796 B at the start | `heap_min_end` 73,704, `heap_min_start` (after a minute) 73,728, first sample 73,796 |
| 598 states, 621 moments, 0 lost, 0 torn, 0 glitches, 0 audio errors | The same |
| 246 reactions, 246 `ended`: skipped 97, cut by a moment 65, a tap 55, needs you 27, done 2 | The same, none missing, twice or unknown |
| Draw 1.0 ms median (2.1 max), push 8.8 ms (22.5 max), up to 32 fps | 995 µs (2,062), 8,772 µs (22,537), 32 |
| `perf --motion` on main's firmware: 6 / 15.2, 14.3 ms, failed | `fps_min` 6, `fps_mean` 15.2, `frame_ms_max` 14.3, `ok` false |
| On the final build: 6 / 15.5, 14.2 ms, 73,796 B, passed | The same, `ok` true |
| Cheers ×3: 1 / 3.4 fps, 18.6 ms; reactions ×2: 2 / 5.9, 14.2 ms; 12 of 14 done | The same; ids 10 and 13 cut by the next moment |

The heap figures are in the lane's evidence, in
[DEVICE.md](../../../DEVICE.md) §6 (73.7 KB through the soak, 73.8 KB in
motion) and in [PLAN.md](../../../PLAN.md)'s headroom item (73.7 KB).
Nothing here measured the board again, so they stand.

The open cheer-loop item holds too: the two simulator frames show the
card and tray 6 px lower at 2,400 ms than at 2,399 ms, and every mood's
task-complete design loops in 2,000 ms or more (`faces.h`), so the rules'
cheer, at least 2 s, is always one loop and never shows the drop.

## 3. The fuzz, again

The lane's harness (a Hal with the real voice player, control lines for
real time, BOOT, touch and Bluetooth, and a checker holding every waited
moment to one `ended` on its own link) was built again from the branch
with `clang++ -std=c++17 -g -O1 -fsanitize=address,undefined
-fno-sanitize-recover=all`.

| | Lane's final code | The fix |
| --- | --- | --- |
| Runs, lines | 4, 80,029 (seeds 101–104) | 6, 120,043 (seeds 201–206) |
| Waited moments, `ended` | 10,804, 10,744 | 16,110, 16,019 |
| Sanitizer errors, checker problems | 0, 0 | 0, 0 |

For the second set the generator also sent `vol`, `say.ms` and `say.at`
past an int's range and as fractions, and infinities: 1,272 `vol`, 1,757
`ms`, 2,454 `at` and 1,255 `loops` values out of an int or fractional,
and 335 lines with `1e999`. Fewer `ended` than waited moments is the
same id sent again while it still plays, which is one moment, reported
once.

## 4. Not run

The board: the fix changes only how four numbers are read, the native
tests cover it, and the board build compiles. The webcam, as in the
lane: it needs the owner's own request.
