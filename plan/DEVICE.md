# Boop: device

Updated 2026-09-27. The board Boop runs on: its parts and pins, the
firmware stack, memory and speed, and how to build and flash it. Sources:
the MicroTech MTR024QV01A-V1 product specification (2025-03-24) and
measurements on our own board.

## 1. The board

MicroTech **MTR024QV01A-V1** (SKU E32R24P), a 2.4" "Cheap Yellow Display":
an ESP32 module, screen, touch, audio amp, RGB LED and LiPo charger on one
board.

| Part | Spec | Notes for Boop |
| --- | --- | --- |
| Module | ESP32-WROOM-32E | Pre-certified radio module |
| Chip | ESP32-D0WD-V3, revision v3.1 | Dual-core Xtensa LX6 at 240 MHz, 40 MHz crystal |
| Memory | 520 KB SRAM, **no PSRAM** | RAM is the tightest limit (§6) |
| Flash | 4 MB QSPI, DIO mode | Two app slots (§5) |
| Radio | Wi-Fi 2.4 GHz; Bluetooth 4.2 BR/EDR and BLE | Boop uses BLE only; Wi-Fi stays off |
| Screen | 2.4" IPS TFT, 240×320, ST7789, 4-wire SPI, RGB565 | 36.2 × 49 mm active area, about 169 ppi. Boop uses it sideways, as 320×240 (§4) |
| Backlight | 4 white LEDs through a MOSFET, 220 cd/m² | GPIO21: high is on, PWM dims it |
| Touch | Resistive XPT2046, SPI on its own pins | Needs a firm press |
| Audio | 8-bit DAC on GPIO26 → on-board amp (enable GPIO4, **active low**) → 2-pin speaker header | A speaker is attached (§3) |
| Light | RGB LED, common anode (**active low**) | On the back of the board, so it shows as a glow |
| Buttons | BOOT (IO0) and RESET (EN) | BOOT works as a normal button after boot |
| USB | USB-C: power, and programming through a CH340 USB-serial bridge (1a86:7523) with auto-reset | Shows up as `/dev/cu.usbserial-*`; flashing needs no BOOT press. At most 460800 baud on macOS (§7) |
| Battery | 1.25 mm 2-pin LiPo header, with a charger for 3.7 V cells | Charges from 4.2–6.5 V (5 V typical) at up to 500 mA (367 mA measured), to 4.2 V |
| Battery sense | ADC on GPIO34 | The divider ratio isn't in the spec; assumed 2:1 |
| Storage | microSD slot, SPI | Unused |
| Size | 42.89 × 74.33 × 5.44 mm | Four Ø3.2 mm mounting holes, 34.89 × 66.33 mm apart |

Our unit's Wi-Fi MAC is `8c:94:df:4e:54:fc`. Its Bluetooth MAC ends in
`54:fe`, so it advertises as `Boop-54FE` ([PROTOCOL.md](PROTOCOL.md) §2).

## 2. Pin map

From the spec's pin table (§4.2). "Free" means Boop can use it.

| GPIO | Used for | Direction | Notes |
| --- | --- | --- | --- |
| 15 | Screen chip select | Out | Active low |
| 2 | Screen data/command | Out | High is data. Also a boot strapping pin, which is fine as wired |
| 14, 13 | Screen SPI clock and data (MOSI) | Out | The screen has no MISO line, so its memory can't be read back |
| EN | Screen reset | — | Shared with the ESP32's reset; the firmware uses the ST7789's software reset |
| 21 | Backlight | Out (PWM) | High is on |
| 25, 32, 39, 33 | Touch SPI clock, MOSI, MISO and chip select | Out, out, in, out | Chip select is active low; 39 is input-only; 25 also rules out DAC channel 1 |
| 36 | Touch interrupt | In | Low while pressed. Input-only pin |
| 22, 16, 17 | LED red, green and blue | Out (PWM) | Active low. 16 is free to use because there's no PSRAM |
| 26 | Audio DAC (DAC channel 2) | Out | |
| 4 | Audio amp enable | Out | **Low enables** the amp |
| 34 | Battery voltage | In (ADC) | Input-only pin |
| 0 | BOOT button | In | Active low. Held through a reset, it enters download mode |
| 3 / 1 | UART0 RX / TX | — | The USB-serial UART; also on the 4-pin UART header |
| 5, 18, 19, 23 | microSD (CS, SCK, MISO, MOSI) | — | 18, 19 and 23 are shared with the SPI header. Unused |
| 27 | SPI header chip select | Free | Planned for a vibration motor |
| 35 | Expansion header (with GND and 3.3 V) | In | Input-only, no internal pull-up. Planned for the main button |

**Two SPI buses.** The screen is on SPI2 (HSPI) at 14/13/15, and touch
on SPI3 (VSPI), remapped to 25/32/39/33, which is safe because Boop
doesn't use the microSD card that normally has VSPI. The spec's FAQ says
touch and screen share a bus; its pin table, which says otherwise, is
right.

## 3. What's attached

| Part | v1 bench | Later |
| --- | --- | --- |
| Main button | **None.** BOOT (IO0) acts as the main button | An external button on IO35: button to GND, 10 kΩ pull-up to 3.3 V |
| Secondary button | **None.** v1 has no job for one ([UX.md](UX.md) §4) | BOOT, once the main button is external |
| Speaker | On the 2-pin speaker header | The same; the header takes an 8 Ω, 1–2 W speaker |
| Vibration motor | **None.** Nothing buzzes in v1 ([FUTURE.md](FUTURE.md)) | A coin motor on GPIO27 through an N-MOSFET, with a flyback diode |
| Battery | **None.** USB power only, so battery sense reads nothing useful | A protected 3.7 V LiPo on the battery header |

The firmware detects none of these. The main button (`kMainButton`) and
whether there's a battery (`kHasBattery`) are build settings in
`firmware/src/board/pins.h`, so moving the button from BOOT to IO35 is one
line. The speaker and motor can't be switched on or off in v1.

## 4. Firmware stack

v1 runs on **PlatformIO, the Arduino core, LovyanGFX, NimBLE-Arduino and
ArduinoJson**: the fastest way to a working face. LovyanGFX drives both the
ST7789 and the XPT2046, on separate buses, from one config block. The route
to production is a port to ESP-IDF + LVGL once v1 is verified end to end
([PLAN.md](PLAN.md) §4).

| Piece | Choice |
| --- | --- |
| Platform | pioarduino `platform-espressif32` 55.03.39 (Arduino core 3.x on ESP-IDF 5.x) |
| Board | `esp32dev`, 240 MHz, 4 MB flash, DIO |
| Display and touch | LovyanGFX 1.2: `Panel_ST7789` on SPI2 and `Touch_XPT2046` on SPI3, with a `Light_PWM` backlight on GPIO21 at 12 kHz |
| Bluetooth | NimBLE-Arduino 2.x, peripheral only, Nordic UART Service ([PROTOCOL.md](PROTOCOL.md)) |
| JSON | ArduinoJson 7 |
| Audio | ESP-IDF's continuous DAC driver on GPIO26, at a fixed 22.05 kHz; pitch changes in software ([VOICE.md](VOICE.md) §8). A task on core 0 streams it without a break, silence when there's nothing to say, and turns the amp on only while a line or cue plays |

**Drawing stays independent of LovyanGFX.** Boop draws into its own 8-bit
canvas, and LovyanGFX only pushes that canvas to the screen
(`firmware/src/board/display.cpp` is the only code that knows the
library). The same drawing code builds on the Mac as the simulator
([VERIFICATION.md](VERIFICATION.md)), and the ESP-IDF + LVGL port only has
to replace the part that pushes pixels.

**Panel settings.** The spec doesn't state these. They were confirmed on
the real panel with the test pattern and the webcam, and live in
`firmware/src/board/display.h`:

| Setting | Value |
| --- | --- |
| SPI write clock | 40 MHz; faster hasn't been tried |
| Colour inversion | On |
| Colour order | RGB |
| Panel memory | 240×320, offsets 0, 0 |
| Rotation | `kRotation` 1: landscape, 320×240, USB-C on the right. The panel controller turns the picture, so it costs no CPU. A board that shows the pattern upside down needs 3, half a turn further; USB-C stays on the right either way. 4–7 mirror the picture |

**Touch calibration.** `internal/tools/boopctl calibrate` has a person tap
four crosses near the corners and one in the middle to check, fits an
affine map from raw readings to screen pixels, and sends it with
`dbg.touchcal`. The board keeps it in NVS (`boop`/`touchcal2`), which
survives reflashing, with the screen size and rotation it was fitted on; a
map for any other is ignored, so calibrate again after changing
`kRotation`. Until then the raw range, about 200–3900 on both axes, is
stretched over the panel and turned with `kRotation`
(`firmware/src/app/touch_cal.h`). v1 doesn't need it, since a touch
anywhere is a tap ([UX.md](UX.md) §4); only the touch position in
`dbg.state` and the calibration crosses depend on it.

## 5. Flash layout

The Arduino core's standard `min_spiffs.csv`, with two app slots so updates
over Bluetooth can come later without a new layout:

| Partition | Size | Use |
| --- | --- | --- |
| nvs | 20 KB | The touch calibration only. The device ID comes from the MAC, and no `state` is kept |
| otadata | 8 KB | Which app slot boots |
| app0 | 1.875 MB | The firmware, fonts and voice assets included |
| app1 | 1.875 MB | A second slot for future updates |
| spiffs | 128 KB | Unused |
| coredump | 64 KB | Reserved for crash dumps |

Fonts and syllable samples are compiled into the firmware as arrays; the
voice assets are 226 KB ([VOICE.md](VOICE.md) §8). The whole firmware is
about 1.08 MB, a little over half of app0.

## 6. Memory, drawing and speed

| Use | Size | Notes |
| --- | --- | --- |
| Screen canvas, 8-bit indexed | 76.8 KB | 320 × 240 × 1 byte. Allocated first, before Bluetooth, while one contiguous block is still free |
| Push buffers | 2 × 7.68 KB | Each converts a band of 12 canvas rows to RGB565 for SPI DMA. Plus the 256-colour palette in the panel's byte order (512 B) |
| NimBLE host and controller | ~75 KB, measured | Classic Bluetooth's memory is released at start-up |
| Audio | ~11 KB, measured | Four 1 KB DMA buffers, a 3 KB task stack and the DAC driver |
| JSON and serial buffers | ~6 KB | 2 KB of received bytes each for USB and Bluetooth; a message line is at most 512 bytes |
| **Free heap** | **≥ 60 KB** | The target; the measured figure is below |

**The DAC must never run dry.** If its DMA reaches the end of what it was
given, ESP-IDF's synchronous DAC writes stop getting buffers back and time
out for good (seen on this board). So the voice task always writes a full
512-sample buffer, silence when idle, and a write that still times out
restarts the DAC and counts in `dbg.state`'s `audio.out.errors`.

**Drawing.** The renderer (`firmware/src/render/`) uses integer maths only,
so the board and the simulator agree to the pixel. Every colour comes from
one 256-entry palette (`render/palette.h`). Text, the bubble and the strip
are anti-aliased: each pixel is sampled at 4 × 16 sub-pixels and takes a
step from an 8-step ramp, black up to its ink colour. The face is the
mood designs ([UX.md](UX.md) §2), drawn exactly in full-strength inks:
shapes on whole pixels and step-wise timings (`render/scene.h`), about
21 KB in `firmware/assets/faces.h`, generated from the designs' SVGs by
`internal/tools/facegen/facegen.py` (`make -C internal faces`). The two fonts are
Geist Mono (SIL Open Font License) at 13 and 22 px, stored as 4-bit
coverage in `firmware/assets/fonts.h` (about 27 KB of flash) and
generated by `internal/tools/fontgen/fontgen.py`.

**Redrawing.** A full-screen push is 153.6 KB over SPI, about 31 ms at
40 MHz, so the firmware pushes only the 12-row bands that changed since
the last frame. It draws a frame only when the picture changes: after a
message or an input, when a part of the face's design moves or shows
differently (`render::SceneFrame`: where each group sits and whether it
shows, so a step that holds its place changes nothing), or when the
bubble comes or goes. The designs step a few times a second, the tap's
sway a little faster, and asleep less than once a second. Two parts can
step a few ms apart, so it draws at most once every 16 ms of real time,
which shows them together. A frozen clock checks on every step, so
scenario frames stay exact, and a press on every loop pass for its first
60 ms, so the cap never delays one ([UX.md](UX.md) §4). A screenshot
always draws afresh.

**Measured:**

| Measure | Value | Source |
| --- | --- | --- |
| Firmware size | 1.10 MB | The board build's flash use, with the mood designs, 2026-09-27 |
| Minimum free heap, through `perf --motion` and a pipeline soak | 74.0 KB | The bench board, [2026-09-26](evidence/2026-09-26-e2e-hardening/README.md) |
| Pictures a second through `perf --motion`'s cheers and wiggles | 23 on average, 18 at the least (the simulator: 15–30, 21 on average) | The bench board, firmware `c0baa57`, 20 s, 2026-09-27 |
| Drawing and pushing one changed frame (`draw_us`, `push_us`) | 1.2 ms and 4.5 ms | The same |
| Minimum free heap in motion | 73.8 KB | The same |

`fps` in `dbg.ping` counts frames drawn, so it says how often the picture
changed; `draw_us` and `push_us` say how fast the board draws.
`internal/tools/boopctl perf --motion` checks both
([VERIFICATION.md](VERIFICATION.md) L2).

## 7. Build and flash

```sh
make -C internal fw                      # build the firmware for the board
make flash                   # build and upload over USB (BOOP_PORT picks the port)
make -C internal sim                     # every scenario in the Mac simulator, against the goldens
internal/tools/boopctl ping  # firmware version and SHA, uptime, heap, fps, link
```

The make targets run PlatformIO through `firmware/tools/pio.sh`, which
keeps its packages inside the checkout.

The firmware talks over USB serial at **460800 baud**, and flashing uses
the same rate. The board's CH340 bridge on macOS's own driver can't do
921600: esptool stops with "The chip stopped responding" and messages
arrive garbled. The ROM boot log before the firmware starts is at 115200
and can be ignored.

Opening the port must not change DTR or RTS. macOS asserts both on open,
and deasserting one before the other pulses EN through the auto-reset
circuit, which reboots the board. `boopctl` leaves them alone.

**Bringing up a board**, in order ([VERIFICATION.md](VERIFICATION.md)
has the checks):

1. **Backlight:** GPIO21 high. A dark screen after flashing almost always
   means this pin was never driven high.
2. **Test pattern** (`internal/tools/boopctl play pattern`): six colour
   blocks, labelled corners, a big UP arrow and a black bar down the USB-C
   edge. Seen upright, the arrow is at the top and the bar on the USB-C
   side; the colours confirm inversion and colour order (§4).
3. **Screenshot:** `internal/tools/boopctl shot` matches the simulator
   pixel for pixel.
4. **The rest:** `internal/tools/boopctl state` reports BOOT, raw touch,
   the LED and the amp, and `internal/tools/boopctl ping` shows Bluetooth
   advertising. Presses, calibration, the speaker
   (`internal/tools/boopctl mumble`) and the LED's glow on the back need a
   person.

## 8. Known quirks

- **Blank screen but backlight on:** usually wrong panel settings or pins,
  according to the spec's FAQ. Check inversion, colour order and the SPI
  pins first.
- **Touch does nothing:** wrong pins, no calibration, or bus contention.
  Touch must stay on its own bus (§2).
- **Backlight flickers:** PWM at too low a frequency, or unstable USB
  power. Use at least 5 kHz.
- **Advertising stops after a disconnect:** NimBLE-Arduino 2.x doesn't
  restart it unless asked, so the firmware turns on advertise-on-disconnect
  and checks once a second ([PROTOCOL.md](PROTOCOL.md) §2).
- **Download mode:** holding BOOT while pressing RESET enters the
  bootloader. Normal flashing doesn't need it, thanks to auto-reset.
- **GPIO 34, 35, 36 and 39 are input-only,** with no internal pull-ups. A
  button on IO35 needs an external pull-up.
