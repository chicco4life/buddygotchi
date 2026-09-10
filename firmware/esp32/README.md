# Boop ESP32 firmware

RenderState v2 firmware for the Waveshare ESP32-S3-Touch-AMOLED-1.64
(`ws-amoled164`, 456×280 landscape canvas). The Mac supplies six creature
states; firmware renders composable face parts, cards, bubbles,
one gift orb, and an agent frame. The frozen previous generation remains in
`archived/`; this firmware does not load character packs or a character menu.

From this directory, use the wrapper for worktree-local pioarduino tools:

```sh
tools/pio_ws.sh run -e ws-amoled164
python3 -m py_compile tests/hil/test_usb.py
# Independent USB UI verification (Mac GUI may remain open):
tools/pio_ws.sh run -e ws-amoled164-usb-debug
```

PlatformIO is `/opt/homebrew/bin/pio`; the wrapper defaults to
the ignored `.platformio-core/` directory inside this firmware worktree. Keep the pinned platform version in
`platformio.ini`. No library additions or asset filesystem upload are needed.
The M5 HAL and environments remain, but this phase verifies only ws-amoled164.
The bring-up environment remains `ws-amoled164-spike`.

Reserve flashing and tests through `tools/dev/device.py` from the repo root.
Use `--usb-only` with setup/restoration scripts for the USB debug build; the
runner verifies `ping.usbOnly=true` before tests. See
[the verification workflow](../../tools/dev/README.md#shared-esp32).
Return to normal firmware after testing; never release the USB debug image.
Bluetooth integration requires normal firmware and one identified Mac app
instance. USB-only screenshots and button tests do not verify Bluetooth.

The approval footer puts the tool/gloss on the left and persistent
`Press: yes` / `Hold: no` instructions on the right (careful prompts:
`Hold 2s: yes` / `Side: no`). Hold progress uses a transient underline.
Session dots and the persistent hold ring are not rendered.

Primary is IO1/BOOT; secondary is IO2; IO5 is a secondary alias. Tap primary to
approve, collect, dismiss a bubble or boop. Hold primary to deny ordinary
cards, approve careful cards at 2 s, or pet. Double tap sends quick when linked
and opens the two travel stats cards when unlinked in travel. Secondary tap
denies/dismisses/pages; hold toggles sound-only Quiet mode at 1 s and shuts the screen off at
3 s after “night night”. Motion and touch never approve. Touch is affection.

The parser, button guards, timer scheduler, drawing and persistence are in
`firmware/data.h`, `main.cpp`, `face.h`, `agent.h`, `presence.h`, and `clock.h`.
`anim.h` supplies the springs and deterministic drawing helpers. HAL, BLE,
OTA and crash guard retain the existing board/transport implementation.
The sprite lives in PSRAM at RGB332; screenshots preserve the existing
RGB565LE + CRC32 format. Cards and bubbles use LGFX's bundled Korean font.
Seven sound motifs are scheduled and counted even though this board has no
speaker (`halTone` is a no-op).

See [PROTOCOL.md](PROTOCOL.md) for frames and diagnostics, and
[UX-DEVICE.md](../../plan/UX-DEVICE.md) for the rendering reference.
For deterministic captures, send a frame, `clock <ms>`, then `screenshot`;
`clock clear` resumes animation. Frozen time also advances model deadlines
for HIL, but physical holds and the watchdog always use real elapsed time.

Hardware-only verification still required: card/face legibility and motion
on glass, Korean glyph coverage, actual IMU posture thresholds, overnight
brightness/battery behavior, BLE round trips, screenshot goldens, and heap
floors (≥40 KB free, ≥28 KB largest block). Static RAM usage is not a runtime
heap measurement. Sound volume cannot be evaluated on this speakerless board.

### Phase 6 device experience

The shared face now renders first wake and its grey-to-color signal, four
greet sizes, level shimmer/cosmetic reveal, streak flames, retirement,
accessories/silhouettes, richer perch poses and a one-second pick-up reaction.
The Bluetooth mark pulses while unpaired or link-lost and lights solid for
800 ms on first frame/reconnection. Rituals use the virtual presentation
clock. See `PROTOCOL.md` for reset/retire commands and telemetry.

Offline build with the existing cached dependencies:

```sh
tools/pio_ws.sh run -e ws-amoled164
python3 -m py_compile tests/hil/test_usb.py tools/shots.py tools/shot_cells.py
```

With a flashed board and the host writer stopped, capture all cells with
`python3 tools/shots.py`, or one with `python3 tools/shots.py --only greet-3`.
Capture recipes reset cached cosmetics/growth, so running one cell produces
the same setup as running the whole sheet. They modify the device snapshot.
The new 18 cells and their exact settle offsets are listed in `PROTOCOL.md`.
Existing goldens require review and recapture because the shared face changed.
Run USB HIL with `/tmp/hilvenv/bin/python -m pytest tests/hil/test_usb.py`;
retire testing clears creature data and reboots. The independent source clock
guard is `tests/hil/test_animation_clock.py` and needs no hardware.

No Phase 6 hardware results are claimed yet: flash, HIL, golden recording,
visual review, idle heap floors (40 KB free / 28 KB largest block), frame
latency and overnight battery behavior still need a connected board.
