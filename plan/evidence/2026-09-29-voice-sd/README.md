# Evidence: Boop's whole voice on the SD card

2026-09-29. The plan is [PLAN.md](PLAN.md), with the owner's answers in
its §4. This is what was built and what ran; the board check (Phase 4)
waits for the pack to be copied onto the card.

## The card, before any of it

A probe firmware, built outside the repo and flashed over USB, mounted
the bench board's own microSD slot on SPI3 (18, 19, 23, 5). The 64 GB
card came as exFAT, which the board can't read, and was reformatted FAT
with the owner's leave. At 10 MHz: 1 MB written in 4.3 s (238 KB/s) and
read in 1.1 s (896 KB/s); opening one of 300 12 KB files and reading its
first 4 KB took 13 ms on average and 19 ms at worst. Boop's firmware
(`0fd4647b`) was flashed back and answered `ping` with its old version.

## What ran

| Check | Result |
| --- | --- |
| `node internal/boop-design/assets/boop-voice-v1/tools/check.mjs` | Passed, with only the robot-soft texture in the repo |
| `python3 internal/tools/voicegen/voicegen.py` | 2,722 takes, pack version `1aace295d219`, 30,536,987 bytes, 0.46–2.61 s a take, in about 3 s |
| `make build` after regenerating `Takes.swift` | 6 s. The first `Takes.swift`, one array literal, ran each `swift-frontend` to about 63 GB before the owner stopped it; written as one `append` per take in functions of 400, the compiler peaked at about 1.6 GB |
| `make -C internal test` (with `BOOP_JEV_KEY` unset in the shell) | 312 of 312 |
| `make -C internal fw-test` | All 8 suites passed |
| `make -C internal sim` | 14 scenarios, no expect failures; `bubble` has 3 new or changed goldens: `bubble-gone` (the look's next variation, since "Bada bing bada boom" is now 1,845 ms), and the new `two-takes` and `small-text`. After merging main, `pattern` too: main's `ceb48772` turned the screen (USB-C on the left) without updating that golden |
| `make -C internal tools-test` | Passed |
| `make -C internal fw` | 2,320,171 bytes, 73.8% of app0 (2,725,851 before: the voice left flash); 2,356,355 once merged with main's needs-you sign (2,761,867 on main) |
| The changed eval scenarios, once each against `jev:jev-latest` ([eval.txt](eval.txt)) | 15 of 15: 03, 04, 05, 09, 11, 12, 15, 16, 27, 29, 35, 54, 60, 61, 62. Before the last steering changes 12 of 15: 15 (upset at quiet work, fixed by putting back the very-long-work Example and telling `upset` it's not for work going on), 54 (a tickled "Yep" to "how's it going?", now allowed) and 03 (sad, which passed 3 of 3 on a rerun) |
| Scenario 04 alone, for [harness/EXAMPLE.md](../../harness/EXAMPLE.md) | Passed; its log is [eval-04-debug.jsonl](eval-04-debug.jsonl) |

## On the board (Phase 4)

| Check | Result |
| --- | --- |
| The firmware's first mount of the card | `card` `no pack`, but free heap 38.8 KB (72 KB before): Arduino `File`s and four files allowed |
| One POSIX descriptor under a mutex, one file allowed | 51.3 KB free with the pack open (51,184 at the least) |
| `boopctl card`, the pack over USB | 217 KB in about 5 minutes, about 0.7 KB/s: hours for the whole pack. Stopped |
| `voicegen.py --card` through a USB-C card reader | 30,536,987 bytes in seconds, `cmp` identical |
| `ping` with the card back | `card` `ok`, `voice` `1aace295d219` |
| `boopctl takes --only` six takes: Go, Bada bing bada boom, Fuck (irritated), Aww... (wounded), Technical difficulties, Test | All `ok`: the DAC took each take's planned length to the millisecond, amp on; the owner heard them |
| A line of two takes, "Tsk... Test" | Planned, rendered and played 2,425 ms (1,377 + 180 + 868), not cut, no DAC errors |

Still to do: a tap, for the bit-banged touch; the soak (L2) and the
pipeline check (L4), which the owner runs tonight; and a failed turn,
being told off and a poke through the app.
