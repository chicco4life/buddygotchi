# Boop: device

Updated 2026-09-29. The board Boop runs on, the pins it uses, how the
firmware is built and runs, what it keeps, and how to build and flash it.
The code is the source (`firmware/`); board facts come from the
MicroTech MTR024QV01A-V1 product specification (2025-03-24) and
measurements on our own board.

## 1. The board

MicroTech **MTR024QV01A-V1** (SKU E32R24P), a 2.4" "Cheap Yellow Display":
an ESP32 module, screen, touch, audio amp, RGB LED and LiPo charger on one
board.

| Part | Spec | Notes for Boop |
| --- | --- | --- |
| Module | ESP32-WROOM-32E: ESP32-D0WD-V3 rev v3.1, dual-core Xtensa LX6 at 240 MHz | Pre-certified radio module |
| Memory | 520 KB SRAM, **no PSRAM** | RAM is the tightest limit (§6) |
| Flash | 4 MB QSPI, DIO mode | Two app slots (§5) |
| Radio | Wi-Fi 2.4 GHz; Bluetooth 4.2 BR/EDR and BLE | BLE only; Wi-Fi stays off |
| Screen | 2.4" IPS TFT, 240×320, ST7789, 4-wire SPI, RGB565, about 169 ppi | Used sideways, as 320×240 (§4) |
| Backlight | 4 white LEDs through a MOSFET, 220 cd/m² | PWM-dimmed |
| Touch | Resistive XPT2046 on its own SPI pins | Needs a firm press |
| Audio | 8-bit DAC on GPIO26 → on-board amp → 2-pin speaker header | A speaker is attached (§3) |
| Light | RGB LED, common anode | On the back, so it shows as a glow |
| Buttons | BOOT (IO0) and RESET (EN) | BOOT is a normal button after boot |
| USB | USB-C: power, and a CH340 USB-serial bridge (1a86:7523) with auto-reset | Shows up as `/dev/cu.usbserial-*`; flashing needs no BOOT press (§7) |
| Battery | 1.25 mm LiPo header and a charger for 3.7 V cells; sense on GPIO34 | Unused in v1 |
| Storage | microSD slot | Unused |
| Size | 42.89 × 74.33 × 5.44 mm, four Ø3.2 mm holes 34.89 × 66.33 mm apart | |

The bench unit's Bluetooth MAC ends in `54:fe`, so it advertises as
`Boop-54FE` ([PROTOCOL.md](PROTOCOL.md) §2).

## 2. Pin map

The pins the firmware drives, from `firmware/src/board/pins.h`:

| GPIO | Used for | Notes |
| --- | --- | --- |
| 14, 13, 15, 2 | Screen SPI clock, MOSI, chip select, data/command | SPI2 (HSPI). No MISO, so the panel can't be read back. 2 is a strapping pin, fine as wired |
| EN | Screen reset | Shared with the ESP32's reset, so the firmware resets the ST7789 in software |
| 21 | Backlight | PWM at 12 kHz; high is on |
| 25, 32, 39, 33 | Touch SPI clock, MOSI, MISO, chip select | SPI3 (VSPI), remapped. 39 is input-only |
| 36 | Touch interrupt | Low while pressed; input-only |
| 22, 16, 17 | LED red, green, blue | PWM at 5 kHz, **active low**. 16 is free because there's no PSRAM |
| 26 | Audio | DAC channel 2 (the driver's `CH1`) |
| 4 | Amp enable | **Low enables** the amp |
| 0 | BOOT, the main button (`kMainButton`) | Active low, internal pull-up |
| 3, 1 | UART0 | The USB serial port |

**Two SPI buses.** The screen is on SPI2 and touch on SPI3, which is free
because Boop doesn't use the microSD card that normally has it. The
spec's FAQ says touch and screen share a bus; its pin table, which says
otherwise, is right, and touch must stay on its own bus.

Not used: 34 (battery sense), 5, 18, 19 and 23 (microSD; 18, 19 and 23
are also on the SPI header), 27 (the SPI header's chip select) and 35
(the expansion header). 34, 35, 36 and 39 are input-only with no
internal pull-ups.

## 3. What's attached

| Part | v1 bench | Later |
| --- | --- | --- |
| Main button | None: BOOT is the main button | An external button on IO35, to GND with a 10 kΩ pull-up to 3.3 V. Moving it is one line, `kMainButton` in `pins.h` |
| Speaker | On the speaker header (8 Ω, 1–2 W) | The same |
| Vibration motor | None | A coin motor on GPIO27 through an N-MOSFET, with a flyback diode |
| Battery | None: USB power only. Nothing reads or reports a battery level | A protected 3.7 V LiPo |

The firmware detects none of these, and the speaker can't be switched off
except by volume 0.

## 4. Firmware

| Piece | Choice |
| --- | --- |
| Platform | PlatformIO, pioarduino `platform-espressif32` 55.03.39 (Arduino core 3.x on ESP-IDF 5.x), board `esp32dev` at 240 MHz, DIO flash |
| Display and touch | LovyanGFX 1.2: `Panel_ST7789` on SPI2, `Touch_XPT2046` on SPI3, `Light_PWM` backlight |
| Bluetooth | NimBLE-Arduino 2.x, a Nordic UART peripheral ([PROTOCOL.md](PROTOCOL.md) §2); Classic Bluetooth's memory is released at start |
| JSON | ArduinoJson 7 |
| Audio | ESP-IDF's continuous DAC driver at a fixed 22.05 kHz, fed by a task on core 0 (§6, [VOICE.md](VOICE.md) §8) |

Arduino and LovyanGFX were the fastest way to a working face. The port to
ESP-IDF and LVGL comes after v1; it only has to
replace the code that knows the hardware.

### Modules

| Path (`firmware/`) | Job | Builds for |
| --- | --- | --- |
| `src/main.cpp` | Start-up and the main loop (below) | Board |
| `src/app/device.*` | The device core: parses each line, answers `dbg.*`, turns BOOT and touch into gestures, decides when to draw, and sends `status`, `input` and `ended` | Board and Mac |
| `src/app/behaviour.*` | What Boop does ([BEHAVIORS.md](BEHAVIORS.md)): the last `state`, the moment and line playing and how each the Mac waits on ended, taps in a row, blinks, no app, and the light, backlight and sound cues they imply | Board and Mac |
| `src/app/` (the rest) | The device clock and random numbers (`clock.h`), BOOT's taps and holds (`gesture.*`), touch calibration (`touch_cal.h`), line reassembly and Bluetooth packets (`line_reader.h`, `packets.h`), dropping a quiet link (`link_silence.h`), and the screenshot's CRC and base64 (`codec.*`) | Board and Mac |
| `src/render/` | The 8-bit canvas, palette, anti-aliased shapes, fonts, the animation bank's player (`scene.*`), the face screen with its bottom lane, the bubble or the strip (`screens.*`), the animation and mood names (`anim.*`) and the test pattern | Board and Mac |
| `src/voice/player.*` | Turns a line or cue into samples ([VOICE.md](VOICE.md) §8) | Board and Mac |
| `src/voice/effects.*`, `src/app/effect_track.*` | The sound effects' clips and timelines, the mixer that adds them to the voice, and when each event plays with the face ([VOICE.md](VOICE.md) §10) | Board and Mac |
| `src/board/` | The pins; `board_hal.*`, the board's side of the core's `Hal` (buttons, touch, LED, backlight, NVS, heap, sound); `display.*`, the only code that knows LovyanGFX; `audio.*`, the DAC task | Board |
| `src/link/ble.*` | The Nordic UART peripheral | Board |
| `assets/` | Generated and checked in: `faces.h` (facegen), `fonts.h` (fontgen), `voice.h` (voicegen), `sfx.h` (sfxgen) ([VERIFICATION.md](VERIFICATION.md) §2) | Both |
| `tools/pio.sh`, `tools/version.py` | PlatformIO with its packages inside the checkout; the version and git SHA baked into each build | — |

Everything marked "Board and Mac" is plain C++ with integer maths. The
`native` env builds it on the Mac for the unit tests and for `boop-sim`,
the simulator (`internal/firmware/sim/main.cpp`), which runs the same
device core on stdin and stdout with its clock frozen at 0
([VERIFICATION.md](VERIFICATION.md) §4).

### Start-up and the main loop

`setup()` allocates the 76.8 KB canvas first, while one contiguous block
is still free, then starts USB serial (460800 baud, 2 KB receive buffer),
the board (amp off, BOOT's pull-up, the LED, the stored touch
calibration), the display, the audio task and the device core, and
Bluetooth last. If the canvas or the display fails, it turns the
backlight on and prints `dbg.fatal` every 2 s instead
([PROTOCOL.md](PROTOCOL.md) §5).

```
loop()
 ├─ read lines, up to 8 ms ─ USB serial ─┐
 │                           Bluetooth ──┴─► Device::handleLine ─► Behaviour: state, moment
 │                                                               └► replies; lines to the voice task
 ├─ Device::tick ─► status every 60 s, the debug clock's thaw
 │               ─► Behaviour::advance: moment and line ends, blinks, no app
 │               ─► BOOT and touch ─► press, tap, push-to-talk ─► Behaviour, and `input` to the Mac
 │               ─► sound cues, LED and backlight, through the Hal
 │               ─► draw into the canvas, if the picture changed
 └─ displayPush ─► only the changed bands, to the panel over SPI DMA

Bluetooth task ─► received bytes into a 2 KB ring; connects and MTU as atomics
voice task (core 0) ─► an 8-deep queue of lines, cues, hushes and effects ─► player + effects ─► DAC
```

Only the main loop touches the device core. The Bluetooth task only fills
the ring, and the voice task only plays what it's handed (when the queue
is full, the newest wins). The main loop's pass hands it the face's sound
effects as their frames come near ([VOICE.md](VOICE.md) §10). A `dbg.*` line ends the batch of lines, so a
test's input and clock steps land between frames. The loop sleeps 1 ms
when a pass had nothing to read.

### What the device keeps

All of it lives in RAM, in `Behaviour`, as a function of the device clock:
every change happens at an exact millisecond, so a frozen clock gives the
same frames on the board and in the simulator. After a reset the device
knows nothing until the next `state`. Only the touch calibration survives
(§5).

| State | Set by | Cleared by |
| --- | --- | --- |
| The model: `base`, `act`, `mood`, `attn` (agent, project, more), `busy` and `vol` from the last `state` ([PROTOCOL.md](PROTOCOL.md) §3) | Each `state` | The next `state` |
| The moment: an animation (the finish, a one-shot, a poke, `listening`), its variation, start and length | A `moment`'s `anim`, a tap (`poked` or `tap_spam`), or BOOT held (`listening`) | Its end, a new moment, or a new "needs you". `listening` only by its end, the reply or the empty moment (below) |
| The line: syllables, word, the word's place and the beat, for the mouth and bubble, and when it starts: at once, or at its animation's voice window ([VOICE.md](VOICE.md) §9) | A `moment`'s `say` | Its end, a new moment, or a new "needs you". A `state` with `attn` or volume 0 also stops its sound |
| Taps in a row: how many, and when the last came | Every tap ([BEHAVIORS.md](BEHAVIORS.md) §3.3) | A tap 3 s or more after the last starts a new run |
| The variation of each animation's design shown last | Each animation that plays | `dbg.reset` |
| A blink | The device's own timer ([BEHAVIORS.md](BEHAVIORS.md) §2), not on a flip-book | Its end, or an animation |
| A design switch: the eyes shut (a flip-book shows its blink step) and the backlight eases | Any change to another design | Its end |
| The press dip | BOOT or a touch going down | Its release, or push-to-talk starting |
| The alert: needs you's performance starting over | A new request shown | Nothing; `dbg.state` reports when (`alert`) |
| No app, latched | 30 s without a `state` | The next `state` |
| A test pattern or light held by `dbg.pattern` or `dbg.light` | The debug message | The next `state` |
| The clock, running or frozen | `dbg.clock`, `dbg.reset` | `dbg.clock` `run`, or 60 s with no `dbg.*` |

**Screens.** One of four shows, the first that applies (`dbg.state`'s
`screen`):

| Screen | When | What it shows |
| --- | --- | --- |
| `pattern` | After `dbg.pattern`, until the next `state` | The test pattern (§7), a solid colour, or a calibration cross |
| `no_app` | 30 s without a `state`, until the next | The no-app design and the unplugged icon ([BEHAVIORS.md](BEHAVIORS.md) §3.4) |
| `needs_you` | The last `state` had `attn` | The mood's needs-you design, or listening's while it plays, and who in the strip ([BEHAVIORS.md](BEHAVIORS.md) §3.2) |
| `face` | Otherwise | The mood's design for the look (`base`, with what the agents are doing in working's place), or an animation's while one plays, with whose turn in the strip while the finish plays ([BEHAVIORS.md](BEHAVIORS.md) §5) |

On the three face screens the device draws the design, what it adds of
its own (blinks, the press dip and the talking mouth) and the bottom
lane.

**The bottom lane.** The animation bank's designs keep y 192–240 free
for text (their clip, §6). The status strip sits in it, from y 204, and
while a line plays the bubble takes the whole lane in the strip's place
(`render::kLaneTop`): the squiggles and the one real word in amber, in a
box with stepped corners and a short tail up to the face, as the bank
asks host text to be drawn. No line plays while something needs you, so
the bubble never hides who's asking. The first pack's looks and its
successes for the finish draw into the lane; the bubble blanks it, so
their props there are cut at y 192 while it shows. The word is never cut
while squiggles can make room: they go, one at a time from the side with
more, before it's cut with "..".

### Taps and push-to-talk

BOOT pressed for less than 400 ms (`ButtonGesture::kHoldMs`) is a tap,
sent on release. The device counts taps in a row itself: a tap within
3 s of the last is another in the run, and from its third on the device
plays `tap_spam` instead of `poked` (`Behaviour::kTapRunMs`,
`kTapSpamFrom`, the Mac's `TranscriptView` numbers,
[BEHAVIORS.md](BEHAVIORS.md) §3.3). Every tap counts, those that only
dip the face included. Held 400 ms, it's push-to-talk: at that moment the
device sends `talk_on` and shows `listening` at once, without waiting for
the Mac; on release it sends `talk_off`, and no tap. After 30 s of
talking (`kTalkCapMs`, from `talk_on`) the device sends `talk_off` itself,
and the release after that sends nothing. A touch is a tap however long
it's held. Presses are debounced for 15 ms. The Mac records and
transcribes; the device has no mic ([PROTOCOL.md](PROTOCOL.md) §4).

`listening` also plays when the Mac sends a moment with
`"anim":"listening"` (its own mic), in the mood's listening design, a
variation picked at random and never the last, unless the moment names
one it has. It holds until the reply:

- **The reply ends it.** Any moment with a `say` ends `listening`, then
  plays as it would have, its animation, face and `ended` included. So
  does the empty moment, `{"t":"moment"}`, which does nothing else: it
  never ends another animation or a mumble ([PROTOCOL.md](PROTOCOL.md)
  §3).
- **Or its time runs out.** It lasts at most 30 s of listening
  (`Behaviour::kListenMs`) and then 8 s for the reply (`kReplyWaitMs`):
  38 s from the Mac's moment. `talk_off`, the release or the cap, cuts
  the wait to 8 s from then, with the same design going on, no blend.
  With no reply, the face blends back with nothing else.
- **Nothing else replaces it.** Another animation from the Mac, a
  one-shot or a face without a `say` is skipped (answered `ended`
  `skipped` if the Mac waits on it), and a tap only dips the face. It's
  the one moment that plays while something needs you, and a new
  request doesn't cut it
  ([BEHAVIORS.md](BEHAVIORS.md) §1). Push-to-talk cuts whatever was
  playing, as a tap does (`ended` `why` `tap`), and stops the line.
- **Silent.** The bank's mix leaves listening silent
  ([VOICE.md](VOICE.md) §10), so nothing competes with your voice.

BOOT held while the Mac's `listening` plays keeps the same face and
tops its time up again. Input a tool injects with `dbg.press` behaves the
same, and its `talk_on` and `talk_off` go back only over USB
([PROTOCOL.md](PROTOCOL.md) §4).

### Panel settings

The spec doesn't give these. They were confirmed on the real panel with
the test pattern and the webcam, and live in `firmware/src/board/display.h`:

| Setting | Value |
| --- | --- |
| SPI write clock | 40 MHz; faster hasn't been tried |
| Colour inversion | On |
| Colour order | RGB |
| Panel memory | 240×320, offsets 0, 0 |
| Rotation | `kRotation` 1: landscape, 320×240, USB-C on the right. The panel controller turns the picture, so it costs no CPU. A board that shows the pattern upside down needs 3; 4–7 mirror it |

### Touch calibration

`internal/tools/boopctl calibrate` has a person tap four crosses near the
corners, then one in the middle to check. It fits an affine map from raw
readings to screen pixels, x = (ax·raw x + bx·raw y + cx) / 65536 and y
alike, and sends it with `dbg.touchcal`. Until there is one, the raw range
of about 200–3900 on both axes is stretched over the panel and turned with
`kRotation` (`firmware/src/app/touch_cal.h`). v1 barely needs it, since a
touch anywhere is a tap: only the touch position in
`dbg.state` and the calibration crosses depend on it.

## 5. Flash and storage

The Arduino core's `huge_app.csv`, with one 3 MB app slot. The faces of
13 moods don't fit the 1.875 MB slot `min_spiffs.csv` had, and nothing
updates over the air, so its second slot went to the firmware:

| Partition | Size | Use |
| --- | --- | --- |
| nvs | 20 KB | The touch calibration (below) |
| otadata | 8 KB | Which app slot boots: there's only app0 |
| app0 | 3 MB | The firmware, with its fonts, faces, voice and sound effects |
| spiffs | 896 KB | Unused |
| coredump | 64 KB | Reserved for crash dumps |

NVS sits at 0x9000, 20 KB, as it did in `min_spiffs.csv`, so reflashing
with the new layout keeps the touch calibration. Flashing writes
`boot_app0.bin` into otadata too, so the board boots app0.

**NVS** holds one key: namespace `boop`, key `touchcal2`, the six
calibration numbers with the screen width, height and rotation they were
fitted on. A map fitted on any other screen or rotation is ignored, so
calibrate again after changing `kRotation`. It survives reflashing.
Nothing else is stored: the device ID comes from the Bluetooth MAC, and no
`state` is kept.

Fonts, faces, voice clips and sound effects are compiled in as arrays:
the voice is 235 KB ([VOICE.md](VOICE.md) §8), the sound effects 208 KB
with their timelines (§10 there), the faces 1.19 MB (§6) and the fonts
about 27 KB. The whole firmware is 2.50 MB, about 79% of app0.

## 6. Memory, drawing and speed

| Use | Size | Notes |
| --- | --- | --- |
| Screen canvas, 8-bit indexed | 76.8 KB | 320 × 240 × 1 byte, allocated first |
| Push buffers | 2 × 7.68 KB | Each turns a band of 12 canvas rows into RGB565 for SPI DMA, plus the 256-colour palette in the panel's byte order (512 B) |
| NimBLE host and controller | ~75 KB, measured | |
| Audio | ~11 KB, measured | Four 1 KB DMA buffers, a 3 KB task stack and the driver |
| JSON and serial buffers | ~6 KB | 2 KB of received bytes each for USB and Bluetooth; a line is at most 512 bytes |
| **Free heap** | **≥ 60 KB** | The target; measured below |

**The DAC must never run dry.** If its DMA reaches the end of what it was
given, ESP-IDF's DAC writes stop getting buffers back and time out for
good (seen on this board). So the voice task always writes a full
512-sample buffer, silence when there's nothing to say, runs above
Bluetooth's host task, and turns the amp on only while something plays
(and for about a second after, so a design's clicks don't toggle it). A
write that still times out restarts the DAC and counts in `dbg.state`'s
`audio.out.errors`.

**Drawing.** The renderer uses integer maths only, so the board and the
simulator agree to the pixel. Every colour comes from one 256-entry
palette (`render/palette.h`). Text, the bubble and the strip are
anti-aliased: each pixel row samples 4 sub-scanlines of 1/16 px, and the
coverage picks one of 8 steps from black up to the ink.

**The face** is the animation bank's designs
(`internal/boop-design/boop-sound-bank-v4/`, [its guide](../internal/boop-design/README.md)),
drawn as Chrome draws their SVGs: rectangles on whole pixels with
step-wise timings, from `assets/faces.h`, which
`internal/tools/facegen/facegen.py` generates. facegen runs the bank's
own generator (`internal/tools/facegen/bank.mjs`, with node) into its
ignored `build/`, so the bank is the designs' one source, and lists them
in `internal/tools/facegen/design/manifest.json`. There are 13 moods ×
22 states, the order of `render::Mood` and `render::SceneState`
([PROTOCOL.md](PROTOCOL.md) §3), and each mood and state has variations
of its own, 770 designs in all, 704 scenes once the shared ones are
counted once:

| Moods | Variations |
| --- | --- |
| The older seven (happy to sad) | The first pack's: three of idle, needs you, asleep, no app and listening, and five of working. Of the newer states: five of task_complete (the first pack's three successes, a newer one, and a failed one), three of starting (one a context), two of delegating and of helper_return, and one of each other |
| The new six (calm to wounded) | Three of each state, five of working, nine of starting (three a context) and six of task_complete (three a result) |

A variation can be for a host fact: task_complete's `outcome` (success
or failure) and starting's context (new_task, session or continuation).
`render::fitting` gives the variations that fit a fact, or all of them
when none does, as the Mac's `FaceLoops.variants` does, and
`render::variantOutcome` and `variantCtx` say what one is for. Asleep
and no app look the same in every older mood, and in every new one.

The bank writes its SVGs in three dialects, and facegen reads the
animation of each, never its reduced-motion copy: the first pack's
(V2), the older moods' newer states (V3), and the new moods' flip-books
(V4). A flip-book draws a whole picture in each step, and only one step
shows at a time: each step has its own face, with its mouth in it, which
the bank's generator tags, and the device moves the face that shows for
a press and opens its mouth to talk (`render/scene.cpp`). A flip-book
blinks in a step of its own, on the design's clock, so the device's
blink (BEHAVIORS.md §2) leaves it be; to hide a change of design, the
device shows that step in place of the one showing, as it shuts the
first pack's eyes. facegen gives each step its role (`step`, and
`blink_step` for the one whose face the bank tags as its blink). The
talking mouth is a small "o", 14 × 12 px, in the colour of the mouth
that shows, centred on it a pixel low: where the first pack's always
sat, and on the new moods' lips. facegen checks that each design
shows at most one face and one mouth at a time. It bakes what the device
can't do on its own into rectangles and steps:

- **Scaled, turned or fractional shapes** are filled where a pixel's
  centre is inside, as Chrome does; a centre on an edge goes to the shape
  left of it or above it.
- **A colour that fades** (the golds of the first pack's successes)
  becomes a step each time its RGB565 value changes, so it looks the same
  on the panel.
- **A translucent group** is flattened as Chrome composites it, into
  pieces of one colour and opacity. The device blends each over the pixel
  beneath through a table (`kBlendOver`) of every blend the designs make.
- **What the designs repeat is stored once**: each group's rectangles,
  and each track, its key times and its values. The flip-books repeat
  themselves a lot, so the faces take 1.19 MB (§5).

The designs' 89 colours sit in the palette after the ramps
(`faces::kSceneBase`). Every design is clipped above y 192, leaving the
bottom lane to the strip and the bubble (§4), but the first pack's
looks, successes for the finish and listening, which draw to the bottom
of the screen.
`faces.h` also has each design's loop (`loopMs`), which a moment's
`loops` count ([PROTOCOL.md](PROTOCOL.md) §3), how many variations each
mood and state has and what each is for; facegen writes the same numbers
for the Mac, in `app/BoopKit/Core/FaceLoops.swift`, with each design's
voice window ([VOICE.md](VOICE.md) §10), which `sfx.h` has for the
device. The older moods' designs must come
out of the bank byte for byte as they were captured (the bank's
`qa/v3-fingerprints.json`), and facegen stops if one doesn't. The
two fonts are Geist Mono (SIL Open Font License) at 13 and 22 px, stored
as 4-bit coverage in `assets/fonts.h` and generated by
`internal/tools/fontgen/fontgen.py`.

**Redrawing.** A full-screen push is 153.6 KB over SPI, about 31 ms at
40 MHz, so the firmware pushes only the 12-row bands whose rows changed.
It draws a frame only when the picture can have changed: after a message
or an input, when a part of the face's design moves or shows differently
(`render::SceneFrame`, which is also what it draws, so the face is laid out
once a frame), or when the bubble comes or goes. The designs step
a few times a second, so most passes find nothing to draw. It draws at
most once every 16 ms of real time, so two parts stepping a few ms apart
show together, except that a frozen clock checks every step (so scenario
frames stay exact) and a press draws at once for its first 60 ms. A screenshot always draws afresh.

**Measured:**

| Measure | Value | Source |
| --- | --- | --- |
| Firmware size | 2.50 MB (2,498,811 bytes), 79% of app0 | The board build that plays the 22 states (acts, one-shots, the finish, pokes), 2026-09-29 |
| Minimum free heap, through a 10-minute soak with brain reactions | 71.5 KB (71,472 bytes), no drift from its first sample | The bench board, firmware `067c7d80`, [2026-09-29](evidence/2026-09-28-mood-spectrum/board/README.md) |
| Frames a second through `perf --motion`'s finishes and pokes | 6.1 on average, 3 at the least: the wiggle now plays the stepped poke designs, not a continuous sway, so fewer frames change | The bench board, firmware `067c7d80`, 60 s, the same |
| Drawing and pushing one changed frame (`draw_us`, `push_us`), through the soak | 1.5 ms and 11.7 ms typically; 3.0 ms and 27.0 ms at the most | The same |
| Minimum free heap in motion | 71.5 KB | `perf --motion`, the same |

`fps` in `dbg.ping` counts frames drawn, so it says how often the picture
changed; `draw_us` and `push_us` say how fast the board draws.
`internal/tools/boopctl perf --motion` checks both
([VERIFICATION.md](VERIFICATION.md) L2).

## 7. Build and flash

```sh
make -C internal fw          # build the firmware for the board (env cyd24)
make flash                   # build and upload over USB; BOOP_PORT picks the port
make -C internal fw-test     # the firmware's unit tests on the Mac (env native)
make -C internal sim         # every scenario in the simulator, against the goldens
internal/tools/boopctl ping  # firmware version and SHA, uptime, heap, fps, link
```

The make targets run PlatformIO through `firmware/tools/pio.sh`, which
keeps its packages in `firmware/.platformio-core`, inside the checkout.
Each build bakes in the version from `VERSION` and the git SHA
(`firmware/tools/version.py`); `-DBOOP_DEBUG_LABEL=1` in
`firmware/platformio.ini` adds the debug label.

The firmware talks over USB serial at **460800 baud**, and flashing uses
the same rate. The board's CH340 on macOS's own driver can't do 921600:
esptool stops with "The chip stopped responding" and messages arrive
garbled. The ROM boot log before the firmware starts is at 115200 and can
be ignored.

Opening the port must not change DTR or RTS. macOS asserts both on open,
and deasserting one before the other pulses EN through the auto-reset
circuit, which reboots the board. `boopctl` leaves them alone.

**Bringing up a board**, in order ([VERIFICATION.md](VERIFICATION.md) has
the checks):

1. **Backlight:** GPIO21 high. A dark screen after flashing almost always
   means this pin was never driven high.
2. **Test pattern** (`internal/tools/boopctl play pattern`): six colour
   blocks, labelled corners, a big UP arrow and a black bar down the USB-C
   edge. Upright, the arrow is at the top and the bar on the USB-C side;
   the colours confirm inversion and colour order (§4).
3. **Screenshot:** `internal/tools/boopctl shot` matches the simulator
   pixel for pixel.
4. **The rest:** `internal/tools/boopctl state` reports BOOT, raw touch,
   the LED and the amp, and `internal/tools/boopctl ping` shows Bluetooth
   advertising. Presses, calibration, the speaker
   (`internal/tools/boopctl mumble`) and the LED's glow need a person.

## 8. Known quirks

- **Blank screen but backlight on:** usually wrong panel settings or pins,
  says the spec's FAQ. Check inversion, colour order and the SPI pins
  first.
- **Touch does nothing:** wrong pins, no calibration, or bus contention.
  Touch must stay on its own bus (§2).
- **Backlight flickers:** PWM too slow, or unstable USB power. Keep it at
  5 kHz or more.
- **Advertising stops after a disconnect:** NimBLE-Arduino 2.x doesn't
  restart it unless asked, so the firmware turns on advertise-on-disconnect
  and checks once a second ([PROTOCOL.md](PROTOCOL.md) §2).
- **Download mode:** holding BOOT while pressing RESET enters the
  bootloader. Normal flashing doesn't need it, thanks to auto-reset.
- **A button on IO35 needs an external pull-up,** like every input-only
  pin (§2).
