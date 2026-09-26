# Boop: device

Updated 2026-09-26. Everything needed to get Boop's board running: the
hardware, the pins, what's attached, the firmware stack, and how to build,
flash and bring it up. Sources: the MicroTech MTR024QV01A-V1 product
specification (2025-03-24) and measurements from our own board.

## 1. The board

MicroTech **MTR024QV01A-V1** (SKU E32R24P), a 2.4" "Cheap Yellow Display":
an ESP32 module, screen, touch, audio amp, RGB LED and LiPo charger on one
board.

| Part | Spec | Notes for Boop |
| --- | --- | --- |
| Module | ESP32-WROOM-32E | Pre-certified radio module |
| Chip | ESP32-D0WD-V3, revision v3.1 (measured) | Classic ESP32: dual-core Xtensa LX6, 240 MHz, 40 MHz crystal |
| Memory | 520 KB SRAM, 448 KB ROM, 16 KB RTC SRAM, **no PSRAM** | RAM is the tightest limit on this board (§6) |
| Flash | 4 MB QSPI (measured: manufacturer 0xC4, device 0x6016), DIO mode | Two app slots plus a little data (§5) |
| Radio | Wi-Fi 2.4 GHz b/g/n; Bluetooth 4.2 BR/EDR + BLE | Boop uses BLE only; Wi-Fi stays off |
| Screen | 2.4" IPS TFT, 240×320, ST7789, 4-wire SPI, RGB565 (RGB666 max) | Active area 36.2 × 49 mm; 0.15 mm pixels (~169 ppi); viewable from all angles. Boop uses it sideways, as 320×240 (§4) |
| Backlight | 4 white LEDs through a MOSFET, 220 cd/m² typical | GPIO21: high is on, PWM dims it |
| Touch | Resistive, XPT2046, SPI on its own pins | Needs a firm press; viewing window 38.36 × 50.70 mm |
| Audio | 8-bit DAC on GPIO26 → on-board amp (enable GPIO4, **active low**) → 2-pin speaker header | Nothing attached yet (§3) |
| Light | RGB LED, common anode (**active low**): R GPIO22, G GPIO16, B GPIO17 | On the back of the board, so it shows as a glow |
| Buttons | BOOT (IO0) and RESET (EN) | BOOT is usable as a normal button after boot |
| USB | USB-C, power and programming through an on-board CH340 USB-serial bridge (1a86:7523) with auto-reset | Shows up as `/dev/cu.usbserial-*`; no need to hold BOOT to flash. 460800 baud at most with macOS's driver (§7) |
| Battery | 1.25 mm 2-pin LiPo header; charger for 3.7 V cells | Charge input 4.2–6.5 V (5 V typical), 500 mA max (367 mA measured), 4.2 V full, up to 62 °C while charging |
| Battery sense | ADC on GPIO34 | Divider ratio isn't in the spec; assume 2:1 until measured |
| Storage | microSD slot, SPI | Not used by Boop |
| Size | 42.89 × 74.33 × 5.44 mm module | Four Ø3.2 mm mounting holes, 34.89 × 66.33 mm apart |

Our unit's MAC address is `8c:94:df:4e:54:fc`.

## 2. Pin map

From the spec's pin table (§4.2). "Free" means Boop can use it.

| GPIO | Used for | Direction | Notes |
| --- | --- | --- | --- |
| 15 | Screen chip select | Out | Active low |
| 2 | Screen data/command | Out | High is data. Also a boot strapping pin, which is fine as wired |
| 14 | Screen SPI clock | Out | |
| 13 | Screen SPI data (MOSI) | Out | The screen has no MISO line, so its memory can't be read back |
| EN | Screen reset | — | Shared with the ESP32 reset. There's no separate screen reset pin; use the ST7789's software reset |
| 21 | Backlight | Out (PWM) | High is on |
| 25 | Touch SPI clock | Out | This also rules out DAC channel 1 |
| 32 | Touch SPI data out (MOSI) | Out | |
| 39 | Touch SPI data in (MISO) | In | Input-only pin |
| 33 | Touch chip select | Out | Active low |
| 36 | Touch interrupt | In | Low while pressed. Input-only pin |
| 22 | LED red | Out (PWM) | Active low |
| 16 | LED green | Out (PWM) | Active low. Free to use because there's no PSRAM |
| 17 | LED blue | Out (PWM) | Active low |
| 26 | Audio DAC (DAC channel 2) | Out | |
| 4 | Audio amp enable | Out | **Low enables** the amp, high disables it |
| 34 | Battery voltage | In (ADC) | Input-only pin |
| 0 | BOOT button | In | Active low. Holding it through a reset enters download mode |
| 3 / 1 | UART0 RX / TX | — | The same UART as USB-serial; also on the 4-pin UART header |
| 5, 18, 19, 23 | microSD (CS, SCK, MISO, MOSI) | — | 18/19/23 are shared with the SPI header. Unused |
| 27 | SPI header chip select | Free | Planned for the vibration motor |
| 35 | Expansion header (with GND and 3.3 V) | In | Input-only, no internal pull-up. Planned for the main button |

**SPI buses.** The screen and touch are on different pins, so they need two
SPI buses:

- the screen goes on SPI2 (HSPI) at 14/13/15;
- touch goes on SPI3 (VSPI), remapped to 25/32/39/33. That's safe because
  Boop doesn't use the microSD card, which normally has VSPI.

The spec's FAQ says touch and screen share a bus, which contradicts its own
pin table. The pin table wins.

## 3. What's attached

| Part | v1 bench (now) | Later |
| --- | --- | --- |
| Main button | **None.** BOOT (IO0) acts as the main button | External button on IO35: button to GND, 10 kΩ pull-up to 3.3 V |
| Secondary button | **None.** Touch covers its jobs ([UX.md](UX.md) §4) | BOOT becomes the secondary button |
| Speaker | **None.** The audio code runs, but nothing is heard | 8 Ω, 1–2 W speaker on the 2-pin speaker header |
| Vibration motor | **None.** The buzz rung becomes three strong amber light pulses ([BEHAVIORS.md](BEHAVIORS.md) §3.2) | Coin motor on GPIO27 through an N-MOSFET, with a flyback diode |
| Battery | **None.** USB power only; battery sense reads nothing useful | Protected 3.7 V LiPo on the battery header |

The firmware detects none of these. The main button is a build setting in
`firmware/src/board/pins.h` (`kMainButton`), so switching it from BOOT to
IO35 is one line, and whether there's a battery is a build setting too. The
speaker and motor can't be switched on or off in v1.

## 4. Firmware stack

**v1: PlatformIO + Arduino core + LovyanGFX + NimBLE-Arduino + ArduinoJson.**

This is the fastest way to a working face. The previous generation's
firmware used the same stack, and LovyanGFX drives both the ST7789 and the
XPT2046, on separate buses, from one config block. The route to production is a later
port to ESP-IDF + LVGL ([PLAN.md](PLAN.md), final milestone), once v1 is
verified end to end.

| Piece | Choice |
| --- | --- |
| Platform | pioarduino `platform-espressif32` (Arduino core 3.x on ESP-IDF 5.x), the same release the old firmware used |
| Board | `esp32dev`, 240 MHz, 4 MB flash, DIO |
| Display and touch | LovyanGFX 1.2.x: `Panel_ST7789` on SPI2 and `Touch_XPT2046` on SPI3, with `Light_PWM` backlight on GPIO21 |
| Bluetooth | NimBLE-Arduino 2.x, peripheral only, Nordic UART Service ([PROTOCOL.md](PROTOCOL.md)) |
| JSON | ArduinoJson 7 |
| Audio | ESP-IDF's continuous DAC driver on GPIO26, at a fixed 22.05 kHz output rate; pitch is changed in software. A task on core 0 streams it without a break (silence when there's nothing to say) and turns the amp on only while a line or cue plays |

**Keep the drawing code independent of LovyanGFX.** Boop draws into its own
8-bit canvas, and LovyanGFX only pushes that canvas to the screen. The same
drawing code builds on the Mac as a simulator ([VERIFICATION.md](VERIFICATION.md)),
and the later ESP-IDF + LVGL port only has to replace the part that pushes
pixels.

**Screen settings confirmed at bring-up.** The spec doesn't state these.
They were confirmed on the real panel with the test pattern and the webcam
on 2026-09-26 (F1), and live in `firmware/src/board/display.h`. The
landscape rotation came after, in F6:

| Setting | Started with | Confirmed |
| --- | --- | --- |
| SPI write clock | 40 MHz (try 60–80 MHz later) | 40 MHz works; faster not tried yet |
| Colour inversion | On (usual for IPS ST7789 panels) | On: white reads bright and black dark |
| Colour order | RGB | RGB: the red block reads red, the blue block blue |
| Rotation | Portrait, with USB-C at the bottom as "up" | LovyanGFX rotation 0: the UP arrow points away from USB-C (F1) |
| Rotation, landscape (F6) | `kRotation` 1 in `firmware/src/board/display.h`: landscape, 320×240, USB-C on the **right**. Worked out from rotation 0: LovyanGFX's rotation 1 turns the picture a quarter turn clockwise on the panel, so the panel's USB-C end becomes the right edge. Fairly sure, but not yet seen on the board. The panel controller turns the picture, so it costs no CPU; the panel is still configured as its physical 240×320 | Not yet. With Boop sideways and USB-C on the right, `tools/boopctl pattern` should show the UP arrow at the top and the black bar down the USB-C side. **If it's upside down**, rotation 1 was the wrong way round: set `kRotation` to 3 (half a turn), `make flash`, and run `boopctl calibrate` again. USB-C always goes on the right: the pattern's bar and the webcam check assume it, so 3 isn't a way to put it on the left. Don't use 4–7, which mirror the picture |
| Offsets | 0, 0 (panel memory 240×320) | 0, 0: all four labelled corners show |
| Touch calibration | Raw range about 200–3900 on both axes | Needs a person: `boopctl calibrate` fits an affine raw → screen map from 4 taps and the board keeps it in NVS (`boop`/`touchcal2`) with the screen size and rotation it was fitted on, surviving reflashes. A map for another size or rotation is ignored; the portrait build's `touchcal` is deleted at start-up. Until a calibration exists, the raw range is stretched over the panel and turned with `kRotation` (`firmware/src/app/touch_cal.h`). Not yet run on this board |

## 5. Flash layout

4 MB with two app slots, so updates over Bluetooth can come later without a
new layout.

| Partition | Size | Use |
| --- | --- | --- |
| nvs | 20 KB | The touch calibration only (Bluetooth bonds later). The device ID comes from the MAC, and no `state` is kept |
| otadata | 8 KB | Which app slot boots |
| app0 | 1.875 MB | Firmware, including fonts and sound assets |
| app1 | 1.875 MB | Second slot for future updates |
| spiffs | 128 KB | Unused for now |

That's the Arduino core's standard `min_spiffs.csv`. Fonts and syllable
samples are compiled into the firmware as arrays. The voice assets are
226 KB ([VOICE.md](VOICE.md) §8). With them the firmware uses 1.09 MB,
56% of app0 (F5, 2026-09-26).

## 6. RAM budget

| Use | Size | Notes |
| --- | --- | --- |
| Screen canvas, 8-bit indexed | 76.8 KB | 320 × 240 × 1 byte, plus a 256-colour RGB565 palette (512 B). Allocate it first, before Bluetooth, while one contiguous block is still free |
| Push buffer | 2 × 7.7 KB | Converts 12 canvas rows (of 320 px) at a time to RGB565 for SPI DMA |
| NimBLE host + controller | ~75 KB measured | Release Classic Bluetooth memory at start-up; Boop only uses BLE |
| Audio | ~11 KB | Four 1 KB DMA buffers for the DAC, a 3 KB task stack and the DAC driver (measured, F5) |
| JSON and serial buffers | ~6 KB | One message line is at most 512 bytes |
| **Target free heap** | **≥ 60 KB** | Checked continuously by `boopctl ping` |

**Measured (F1, 2026-09-26).** 264 KB is free when `setup()` starts. The
canvas takes 82 KB with allocator overhead, and the push buffers and
LovyanGFX take 20 KB, which leaves 160 KB before Bluetooth. Linking
NimBLE-Arduino alone reserves the controller's 39 KB at boot (225 KB free at
start), so it's added only in F4.

**Measured (F4, 2026-09-26).** With NimBLE-Arduino 2.x linked, Classic
Bluetooth's memory released and the Nordic UART peripheral advertising,
84 KB is free after start-up, and the minimum stays at 82.7 KB through
motion and a 20-minute soak. Bluetooth costs about 75 KB in all, more than
the 45–60 KB first guessed, but the 60 KB target still holds with 20 KB to
spare. Frame rates are unchanged (44–60 fps in motion).

**Measured (F5, 2026-09-26).** The voice adds four 1 KB DMA buffers, a
3 KB task stack and the DAC driver: about 11 KB. 73 KB is free after
start-up, and the minimum stays at 72.5 KB through a 5-minute soak with
mumbles. Frame rates are unchanged (44–57 fps in motion).

**The DAC must never run dry.** If the DMA reaches the end of what it was
given, ESP-IDF's synchronous DAC writes stop getting buffers back and
time out for good (seen on this board). So the voice task always writes a
full 512-sample buffer, silence when idle, and a write that still times
out restarts the DAC and counts in `dbg.state` `audio.out.errors`.

**Drawing.** The renderer (`firmware/src/render/`) uses integer maths
only, so the board and the simulator agree to the pixel. Edges are
anti-aliased by sampling 4 × 16 sub-pixels per pixel and picking from
8-step palette ramps (black up to each ink colour, and eye colour down to
the dark inside an open mouth); the palette is "Warm Terminal" in
`render/palette.h`. The two fonts are Geist Mono (SIL Open Font License) at
13 and 22 px, stored as
4-bit coverage in `firmware/assets/fonts.h` (about 27 KB of flash) and
generated by `tools/fontgen/fontgen.py`.

**Measured (F2, 2026-09-26).** Drawing a face frame takes 5–11 ms and
pushing the changed rows 3–16 ms at 40 MHz, so the board runs at 44–60 fps
during motion (`boopctl perf --motion`); 40 MHz is enough. Free heap stays
at 158 KB before Bluetooth.

A full-screen push is 153.6 KB over SPI: about 31 ms at 40 MHz, so roughly
25–30 frames per second. Most frames only change the eyes and mouth, so the
firmware pushes only the rows that changed. Aim for 30 fps during motion and
10–15 fps at rest. The F2 figures are portrait. In landscape each row is
320 px instead of 240. A band is still 3,840 px (12 rows of 320 rather
than 16 of 240), but the same change now spans more bands, so each changed
row pushes a third more pixels, while the solid eyes draw faster than the
old ones with pupils.

**Measured (F6, 2026-09-26).** Landscape, with the solid eyes and
Bluetooth advertising: `boopctl perf --motion` gives a minimum of 49–50 fps
(mean 70) over 30 s and 60 s, better than F2's 44. 73.9 KB is free after
start-up, and the minimum stays at 72.7 KB through motion, as in F5.

## 7. Build, flash, bring up

Commands (created in the first milestone of [PLAN.md](PLAN.md)):

```sh
make fw          # build firmware/ for the board
make flash       # build and upload over USB (auto-reset, no BOOT press needed)
make sim         # build the Mac simulator of the whole device core
tools/boopctl ping         # firmware version, free heap, fps, uptime
```

The firmware talks over USB serial at **460800 baud**, and flashing uses
the same rate. The board's CH340 bridge on macOS's own driver can't do
921600: esptool stops with "The chip stopped responding" and messages
arrive garbled. The ROM boot log before it starts is at 115200 and can be
ignored.

Opening the port must not change DTR or RTS. macOS asserts both on open,
and deasserting one before the other pulses EN through the auto-reset
circuit, which reboots the board. `boopctl` leaves them alone.

**Bring-up checklist**, in order. Each step has a check in
[VERIFICATION.md](VERIFICATION.md):

1. **Backlight:** GPIO21 high. The spec's FAQ says a dark screen after
   flashing almost always means this pin was never driven high.
2. **Test pattern:** colour bars, labelled corners, an "UP" arrow and a black
   USB-C bar down the right edge. On the webcam, confirm the colours
   (inversion, RGB/BGR order) and the rotation (seen upright, the arrow is
   at the top and the bar is on the side with the USB-C port), then record
   the confirmed values in §4.
3. **Canvas and screenshot:** a USB screenshot must match the simulator's
   render of the same pattern pixel for pixel.
4. **BOOT button:** taps and holds are reported over USB.
5. **Touch:** raw readings and the interrupt respond to a press. Real presses
   and calibration need a person (morning checklist).
6. **LED:** red, green, blue and amber. It's on the back, so check the
   colour of the glow on the webcam or by eye.
7. **Audio:** the amp enables and the DAC runs (reported over USB). It's
   silent until a speaker is attached.
8. **Bluetooth:** advertises as `Boop-XXXX` (the last 4 hex digits of the
   MAC). Connecting needs the Mac app, which the owner launches.

## 8. Known quirks

- **Blank screen but backlight on:** usually wrong panel settings or pins,
  according to the spec's FAQ. Check inversion, colour order and the SPI
  pins before anything else.
- **Touch does nothing:** wrong pins, no calibration, or bus contention.
  Touch must stay on its own bus (§2).
- **Backlight flickers:** PWM at too low a frequency, or unstable USB power.
  Use at least 5 kHz PWM.
- **Download mode:** holding BOOT while pressing RESET enters the
  bootloader. Normal flashing doesn't need it, because of auto-reset.
- **GPIO 34, 35, 36 and 39 are input-only** with no internal pull-ups. Any
  button on IO35 needs an external pull-up.
