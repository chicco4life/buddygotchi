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

## 2026-09-26 01:35 — F2: Renderer and simulator — Passed

- **Changed:** "Warm Terminal" palette with anti-aliasing ramps; an
  integer-only span/band rasterizer; Geist Mono fonts at 13 and 22 px
  (`tools/fontgen`); the pose-based face with eased, interruptible 150 ms
  blends; every animation in BEHAVIORS §7; all screens and the status
  strip; the device core now parses `state`/`moment` and picks the screen;
  `dbg.reset`; `boopctl perf` and `cam clip`. Details in
  [F2/README.md](F2/README.md).
- **Checks:** fw-test 42/42; 8 scenarios and 58 goldens, all reviewed; on the
  board, every expect passed and all 58 screenshots were identical to the
  simulator's; perf with motion gave a minimum of 44 fps and 157 KB heap;
  webcam framing passed, and the idle, needs-you and cheer clips were
  reviewed.
- **Decisions:** integer-only drawing (so the pixels match), Geist Mono
  (OFL), `dbg.reset` before every scenario, and webcam clips as live presets.
  All four are logged in ARCHITECTURE §11. 40 MHz SPI is enough.
- **Board left on:** F2 firmware `c47e775e53`. It shows the face, and goes
  to no app after 30 s without a Mac.
- **Next step:** F3 device behaviour. Start with a behaviour state machine
  in `firmware/src/app/` (pure C++, e.g. `behaviour.*`) that takes over from
  `Device::advance/resync/sourceAt`. Add idle life (blinks every 2–6 s,
  glances, from `rng_`), the nudge ladder's effects (amber LED, chirp
  flags, 3 light pulses at rung 3; visual only in focus), the gestures in
  UX.md §4 (tap face → wiggle + `input tap`; touch-and-hold the face → mood
  face; hold the strip → `focus`; feedback within 20 ms), the 10 s threads
  timeout, dimming (asleep, night, no app), hunger rumble, and mouth sync
  to `say`. Decide which moments may play over needs you (BEHAVIORS §1:
  attention wins). Then add goldens for every BEHAVIORS §3 row, and
  `boopctl soak`.

## 2026-09-26 02:19 — F3: Device behaviour — Passed

- **Changed:** a pure C++ behaviour state machine (`firmware/src/app/behaviour.*`).
  It covers base states, idle life, the needs-you ladder with its light and
  sound cues, moments shaped by mood, mouth sync, gestures with feedback on
  the press itself, the threads and stats timeout, dimming, and hunger. The
  device core now only parses, recognises gestures and draws. `dbg.state`
  gained `hushed`, `life`, `night`, `hungry` and `sfx`. New:
  `boopctl soak`, webcam presets `ladder`, `cheers` and `tap`, and scenarios
  `behaviour` and `life`. Details in [F3/README.md](F3/README.md).
- **Checks:** fw-test 55/55; the simulator ran 10 scenarios, and 22 new and
  8 changed goldens were reviewed; on the board, every expect passed and all
  80 screenshots were identical to the simulator's; perf gave a minimum of
  45 fps and 157 KB of heap; the 20-minute soak had no reset and 0 heap
  drift; webcam framing passed, and the ladder, cheers and tap clips were
  reviewed.
- **Decisions:** attention wins (only nod, listening, thinking, shrug and zip
  play over needs you); the device plays the nod on clearing, the fallback
  shrug, and the mood face, and sends a new `input` `feel`; `sfx` cues show
  in `dbg.state` before F5. All are in the ARCHITECTURE §11 log.
- **Board left on:** F3 firmware `a05f38af45`, showing the face.
- **Next step:** F4, Bluetooth on the device. Add NimBLE back to `lib_deps`
  (DEVICE.md §6) and a Nordic UART peripheral named `Boop-XXXX` (the last 4
  hex digits of the MAC) in `firmware/src/link/`. Feed RX through
  `app::LineReader` into `Device::handleLine(..., Link::kBle)`, with a
  `Device::setOut(Link::kBle, …)` writer that chunks to the MTU. Send
  `status` on connect and every 60 s (PROTOCOL §4), and release Classic BT
  memory. Keep the canvas allocated before BLE starts. Checks: L0
  reassembly tests (test_link already has some), `ping` shows advertising
  with heap_min ≥ 60 KB, and perf and soak re-run with BLE on. Don't use
  `bleak` or the Mac's Bluetooth; the real connection is checked in the
  morning.
