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
| `make -C internal sim` | 14 scenarios, no expect failures; `bubble` has 3 new or changed goldens: `bubble-gone` (the look's next variation, since "Bada bing bada boom" is now 1,845 ms), and the new `two-takes` and `small-text` |
| `make -C internal tools-test` | Passed |
| `make -C internal fw` | 2,320,171 bytes, 73.8% of app0 (2,725,851 before: the voice left flash) |
| The changed eval scenarios, once each against `jev:jev-latest` ([eval.txt](eval.txt)) | 15 of 15: 03, 04, 05, 09, 11, 12, 15, 16, 27, 29, 35, 54, 60, 61, 62. Before the last steering changes 12 of 15: 15 (upset at quiet work, fixed by putting back the very-long-work Example and telling `upset` it's not for work going on), 54 (a tickled "Yep" to "how's it going?", now allowed) and 03 (sad, which passed 3 of 3 on a rerun) |
| Scenario 04 alone, for [harness/EXAMPLE.md](../../harness/EXAMPLE.md) | Passed; its log is [eval-04-debug.jsonl](eval-04-debug.jsonl) |

## Still to do on the board (Phase 4)

1. Copy the pack onto the card in a reader on the Mac:
   `python3 internal/tools/voicegen/voicegen.py --card /Volumes/<card>`.
2. Put the card back, flash (`make flash`), and check `ping`: `card`
   `ok`, `voice` `1aace295d219`, and the free heap (the target is 50 KB
   or more; 72 KB before).
3. Touch is now bit-banged: a tap and `boopctl state`'s raw touch need a
   person's finger.
4. `internal/tools/boopctl takes --only <a few>`, then the soak (L2) and
   the pipeline check (L4), and a failed turn, being told off, a poke and
   a failing check on the board, heard.
