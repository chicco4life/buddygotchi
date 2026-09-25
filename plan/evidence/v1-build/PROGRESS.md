# v1 build progress

One entry per iteration, newest last. Each ends with the exact next step.

## 2026-09-26 00:55 — M0: Setup — Passed

- **Changed:** tag `gen2-final`, branch `v1-overnight`; gen-2 code deleted;
  new `app/` SwiftPM layout (BoopKit, Boop, boop-hook, boopdev, shim tests);
  new `firmware/` PlatformIO project (`cyd24`, `native`) with
  `firmware/tools/pio.sh`; `tools/boopctl` (ports, ping, state, send); new
  Makefile. Details in [M0/README.md](M0/README.md).
- **Checks:** make build, test, fw, fw-test, sim, tools and
  `boopctl ports` all passed.
- **Decisions:**
  - Reusable gen-2 files were deleted rather than parked; fetch them with
    `git show gen2-final:app/Boop/...` when the milestone needs them.
  - `app/Tests/GeneratedTestRunner.swift` is now git-ignored (regenerated
    by `make test`).
  - `.claude/skills/release` still describes the gen-2 packaging scripts,
    which are gone. Left alone; it's not part of v1's milestones.
  - `TODO.md` still lists gen-2 owner items; left for the owner.
- **Next step:** F1 board bring-up. Start with `firmware/src/board/`
  (LovyanGFX config for ST7789 on SPI2 and XPT2046 on SPI3, PWM backlight),
  the canvas push, the USB `dbg.*` channel at 921600, then the test pattern
  in `render/` so `native` can draw it too. Add `boopctl shot`, `diff`,
  `pattern`, `press`, `touch`, `clock` and `sim`, and `boopctl cam` for L3.

## 2026-09-26 00:58 — F1: Board bring-up — Passed

- **Changed:** LovyanGFX display and touch driver with a changed-rows DMA
  push; a pure C++ device core (`app/device.*`) with the whole debug channel,
  the clock and BOOT gestures, shared with `boop-sim` (stdin/stdout);
  the test pattern, 5×7 font and a placeholder face; the board HAL (LED,
  amp, battery, touch raw). boopctl gained `flash shot diff pattern press
  touch clock sim run cam`. Details in [F1/README.md](F1/README.md).
- **Checks:** fw-test 21/21; sim expects pass and 2 goldens reviewed; on the
  board: ping SHA matches, 160 KB free; `run` gives screenshots identical to
  the simulator's and every expect passes; webcam framing and pattern
  passed; LED red and blue seen on the webcam.
- **Decisions:**
  - USB serial runs at **460800**. The CH340 on macOS's driver can't do
    921600, for flashing or messages. Specs updated.
  - boopctl no longer touches DTR/RTS on open, which had rebooted the board.
  - NimBLE is out of `lib_deps` until F4 (it reserves 39 KB at boot).
  - Added `dbg.light` and `dbg.pattern` `fill` (VERIFICATION.md §3).
- **Board left on:** the test pattern, running F1 firmware `174d429931`.
- **Next step:** F2 renderer and simulator. Start with the "Warm Terminal"
  palette in `render/palette.h` and the face renderer in `render/`
  (eyes, lids, pupils, squash, mouth; eased blends ≤ 150 ms), replacing
  `drawPlaceholderFace`. Then add the screens (UX.md §2–3), a second font
  size, scenarios for every screen and state, `boopctl cam clip`, and
  `boopctl perf`, to check ≥ 25 fps during blends. If blends are too slow,
  try the SPI clock at 60–80 MHz (`board/display.h`).
