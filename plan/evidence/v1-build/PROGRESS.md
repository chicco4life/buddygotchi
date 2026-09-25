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
