# The animation pack's sound effects on the device, 2026-09-28

What ran for [VOICE.md](../../VOICE.md) §10, on the Mac, before the commit:

| Check | Result |
| --- | --- |
| `node internal/tools/sfxgen/sfxgen.mjs` | 47 clips, 146 KB, 590 events in 140 timelines; a second run writes the same `sfx.h` |
| The pack's timelines against the designs' loops (`FaceLoops.swift`) | Every sounding timeline's length matches its design's loop; the only four that differ are silent (idle variation 1) |
| `make -C internal fw-test` | 128 of 128, with the new `test_effects` (10) and three sound tests in `test_device` |
| `test_effects` and `test_device` under ASan and UBSan (clang, `-fno-sanitize-recover=all`) | 10 of 10 and 40 of 40, no findings |
| `make -C internal sim` | 11 scenarios, no expect failures, no changed pictures |
| The tools' tests (the three `unittest discover` lines of `tools-test`) | 58 (one skipped), OK, OK |
| `firmware/tools/pio.sh run -e cyd24` | Builds; 1,512,959 bytes of 1,966,080 (77.0%), RAM 14.5% |

Before the sounds, each clip's peak was 5–57 of 127 steps (cushion 5,
trophyA 57), so the quiet ones would have been lost in the 8-bit output:
hence full-scale clips and the square-rooted gains (event gains 45–255,
median 90).

Not run: the board over USB (L2) and the sound by ear on the bench
board's speaker (L6). The owner's `make debug` app had the board over
Bluetooth. Listening previews of six designs, the pack's browser sound
next to the device's mixer output (without the speaker), were rendered
off the repo into `~/Downloads/boop-sfx-previews/`.

## The chirp removed

The owner dropped the chirp once needs you had the pack's sound: its
performance is the alert, and a different request shown starts it over
behind a blink. After that change: `make -C internal fw-test` 128 of 128;
`test_effects`, `test_device`, `test_behaviour` and `test_voice` under
ASan and UBSan 10, 40, 27 and 11, no findings; `make -C internal sim` 11
scenarios with one picture changed and accepted (`needs_you/long-project`,
the performance starting over for the new request); boopctl's tests OK;
`make build` complete; the board build 1,511,839 bytes (76.9%).
