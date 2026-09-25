# F1: Board bring-up — evidence

Run 2026-09-26 on branch `v1-overnight`. Checks ran against firmware
`174d429931`, flashed from that commit. Full output is in
[checks.log](checks.log).

## What was built

- **Drivers** (`firmware/src/board/display.*`): LovyanGFX with the ST7789
  on SPI2 (14/13/15, DC 2, 40 MHz) and the XPT2046 on SPI3 (25/32/39/33,
  IRQ 36). The backlight is `Light_PWM` on GPIO21 at 12 kHz. Only this file
  knows the display library.
- **Canvas push:** the canvas is allocated first in `setup()`. The pusher
  hashes each row, and only 16-row bands that changed are converted to
  RGB565 and sent by DMA through two 7.7 KB buffers.
- **Device core** (`firmware/src/app/device.*`, pure C++): message
  dispatch and the debug channel (`dbg.ping`, `state`, `shot`, `clock`,
  `pattern`, `press`, `touch`, and the new `light`), the clock
  (freeze/step/run, which also reseeds randomness), and BOOT gestures:
  under 400 ms is a tap, otherwise `talk_on`/`talk_off`. These are sent
  to the Mac as `input`. Touch is recorded in `last_input`; F3 turns it
  into gestures.
- **Other hardware** (`board/board_hal.*`): RGB LED on PWM (active low), the
  amp held off (GPIO4 high), the battery ADC (×2 divider, assumed), raw
  touch and IRQ in `dbg.state`.
- **Render** (`render/`): palette header, a 5×7 ASCII font (Adafruit's
  glcdfont, BSD), triangles and text on the canvas, the test pattern, and
  a placeholder face that F2 replaces.
- **Simulator:** `boop-sim` is the same device core on the Mac, talking the
  same line protocol on stdin/stdout. It starts with the clock frozen at 0.
- **boopctl:** `flash`, `shot`, `diff`, `pattern`, `press`, `touch`,
  `clock`, `sim` (with `--accept` for goldens), `run` (the simulator, then
  the board, then a diff of every shot) and `cam frame|pattern`. The
  scenario runner is shared by `sim` and `run`.
- **Scenarios and goldens:** `pattern` and `inputs`, plus goldens
  `pattern/pattern.png` and `inputs/placeholder-face.png`. I looked at both
  goldens: the pattern matches the spec, and the placeholder is two oat
  eyes on black, to be replaced in F2.

## Checks

| Check | Result |
| --- | --- |
| L0 `make fw-test` | Passed: 21 tests (canvas, text, triangle, row hash, pattern, line reassembly, base64, CRC-32, clock, gestures, device dispatch) |
| L1 `boopctl sim` | Passed: both scenarios' expects; both pictures reviewed and accepted as goldens |
| L2 `ping` | Passed: SHA `174d429931` matches HEAD, link not `ble`, **160,208 bytes free** (minimum 159,364), which is ≥ 150 KB before Bluetooth |
| L2 screenshots | Passed: `boopctl run` gave the device's pattern and face screenshots **identical** to the simulator's (0 pixels differ) |
| L2 inputs | Passed: the `inputs` scenario's expects on the device (tap at 150 ms, touch at 60,200, `talk_on` at exactly 400 ms, `talk_off` on release); `boopctl press tap` and `touch 120 160` show up in `dbg.state` |
| L3 framing | Passed: the screen was found (solid white vs backlight off) |
| L3 pattern | Passed: red reads red and blue reads blue (RGB order), white is bright and black is dark (inversion on), and the UP arrow points away from USB-C (rotation 0). [webcam-pattern.png](webcam-pattern.png) |
| LED | Passed by webcam, red and blue only: with the backlight off, `dbg.light` red and blue glow the right colour on the desk; off is dark. [webcam-led-off-red-blue.png](webcam-led-off-red-blue.png). Green and amber weren't filmed |
| Amp | `dbg.state` reports `amp: false` (off) |
| Physical BOOT and touch | Not checked: needs a person (morning checklist) |

Pictures: [sim-pattern.png](sim-pattern.png),
[device-pattern.png](device-pattern.png) (identical bytes as PNG), and
[webcam-pattern.png](webcam-pattern.png).

A screenshot takes 2.36 s at 460800 baud.

## Decisions and deviations (specs updated in the same commit)

- **460800 baud, not 921600.** The board's USB bridge is a CH340
  (1a86:7523) on macOS's own driver. At 921600, esptool dies with "The chip
  stopped responding" and firmware output is garbled. 460800 works for both
  flashing and messages. Updated DEVICE.md §1 and §7, PROTOCOL.md §2,
  VERIFICATION.md §3, PLAN.md, and the ARCHITECTURE.md §11 log.
- **Opening the port no longer resets the board.** M0's boopctl set DTR
  and RTS low one after the other, which pulsed EN. It now leaves them as
  macOS sets them. Noted in DEVICE.md §7.
- **NimBLE is out of `lib_deps` until F4.** Just linking it reserves the
  Bluetooth controller's 39 KB at boot: free heap was 123 KB after the
  canvas with it linked, and 160 KB without. F1 doesn't use Bluetooth, and
  the real budget (≥ 60 KB with Bluetooth on) is checked in F4. Recorded in
  DEVICE.md §6 and the decision log.
- **New debug messages:** `dbg.light` (backlight and LED) and
  `dbg.pattern` with `fill` (a solid screen for webcam framing). `dbg.ping`'s
  `up` is in ms. `dbg.state` carries bring-up readings (clock, BOOT level,
  touch raw and IRQ, battery, amp, backlight). All are in VERIFICATION.md §3.
- **Scenario semantics** written into VERIFICATION.md §4: `input` lines
  don't move the clock, and the simulator's clock starts frozen at 0.
- The battery ADC reads about 4.16 V with no battery (the charger's
  output), as DEVICE.md §3 expects: "nothing useful".

## Left for later

- SPI above 40 MHz isn't tried yet (DEVICE.md §4). F2's ≥ 25 fps check will
  show whether it's needed.
- `boopctl cam clip`, `perf`, `soak`, `expect`, `bridge` and `calibrate`
  arrive with the milestones that use them (F2, F3, J1, morning).
- Touch calibration and physical presses need a person.
