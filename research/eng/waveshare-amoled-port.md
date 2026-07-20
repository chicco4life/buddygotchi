# Port Plan: M5StickC Plus 2 → Waveshare ESP32-S3 Touch AMOLED 1.64

> **Status (2026-07-19): Phase A implemented and compiling.** All three envs
> build: `m5stickc-plus` (regression), `ws-amoled164` (product firmware),
> `ws-amoled164-spike` (bring-up smoke test). Done: HAL extraction
> (`firmware/hal/`), 16MB dual-OTA partition table, CO5300/QSPI display path
> via Arduino_GFX on the pioarduino platform (Arduino core 3.3 — its BLE
> library is NimBLE-backed; `ble_bridge.cpp` has small backend conditionals),
> 140x228 logical canvas with 2x present, three-button semantics + boop
> reaction, `press a|b|m`, sprite-based screenshot with streaming base64,
> FT3168 touch-as-boop, battery ADC. Build the WS envs via
> `tools/pio_ws.sh run -e ws-amoled164 [-t upload]` — the wrapper isolates
> the pioarduino package tree from the M5 envs' espressif32 one. Not yet
> done (needs hardware): every Phase B item; also un-run: `make hil` on the
> M5 to on-device-regression-test the refactor.
>
> **UX pass 1 (2026-07-19, same day, both envs compiling):** on-device
> menu (`firmware/menu.h`: root carousel → character/sound/stats; grammar
> MENU=next / BOOP=pick / REJECT=back with hints drawn at the edge nearest
> each physical button; 10s auto-close; armed prompt closes it; timeout and
> prompt-takeover both *revert* an unconfirmed character preview — only an
> explicit pick adopts + persists), approval card redesign (pulsing
> "boop = yes" band at the top edge, "no >" chip at bottom-right, source +
> tool + two-line hint, hot at 10s, "link lost" line when the bridge drops
> mid-prompt), 600ms prompt-arming delay (a press only approves if it
> *started* after the prompt was armed; an early press is swallowed, not
> turned into a boop; `mockprompt` backdates so HIL is unaffected,
> `mockprompt fresh` keeps real arrival for the arming test; `btn a|b`
> bypasses), wake-press guard now also covers REJECT (a tap that wakes the
> screen never denies an unseen prompt), post-decision feedback ("yes!" /
> neutral "okay" until the desktop clears the prompt) + approve/deny
> chirps, menu-adopted species persisted to NVS (`s_spec`, restored at
> boot) and reported upstream as `{"cmd":"species","name":…}` — the Mac
> mirrors it into its `buddySpecies` preference + engine so reconnect
> heartbeats no longer stomp the on-device choice (adopting while
> disconnected still loses to the desktop on reconnect), idle auto-dim after 5min
> (never while a prompt is pending), and a 1px 4-phase pixel drift in the
> WS present path as the first AMOLED burn-in guard. New HIL coverage in
> `tests/hil/test_usb.py` (menu navigate/preview-revert,
> prompt-takes-over-menu, fresh-prompt arming window); `state` now reports
> `menu` and `armed`.
>
> **Hardware bring-up (2026-07-19, board on desk):** flashed over native
> USB CDC with no BOOT dance (`tools/pio_ws.sh run -e ws-amoled164 -t
> upload`, enumerates `/dev/cu.usbmodem*`; buddyctl's raw-termios open
> does not reset the board). Verified on the device: `ping` (board
> `ws-amoled164`, ~151KB free heap), `state`, sprite screenshot at
> 140x228, approval card + arming window + "yes!" feedback via `press a`,
> menu open/navigate/close, character preview/revert, adopt → `<<MENU
> species=duck kept=1>>` → upstream `{"cmd":"species"}` frame → NVS
> persist across reboot. **Full USB HIL suite: 27 passed** (incl.
> hardening/WDT hang-recovery on this board). Fixed during bring-up: the
> FT3168 poll's repeated-start read hit sporadic i2c-ng
> ESP_ERR_INVALID_STATE error spam — now a full-stop write-then-read at
> 300kHz with error backoff + bus re-init; and the new menu HIL tests
> raced the 120ms synthetic release (back-to-back `press` of the same
> button merges into one hold) — tests now join the `<<PRESS x up>>`
> marker per press. Still open from Phase B: eyeball the glass (sprite
> screenshots can't prove the panel), physical-button approve, OS BLE
> pairing + `make hil-ble`, Mac-app e2e, OTA-over-BLE, character
> transfer.

Target board for the production "Boop Pebble" device. Goal for night one: full e2e
(agent hook → Mac app → BLE → device render → physical approve/reject) working on
the new board, no UX polish.

## 1. Board profile (researched 2026-07-19)

Sources: Waveshare wiki + schematic PDF + official demo zip, arduino-esp32 variant
`waveshare_esp32_s3_touch_amoled_164`, community PlatformIO repos (jaapp,
LaZorraTech, trane77).

| Subsystem | Detail |
| --- | --- |
| MCU | ESP32-S3R8 (chip-down, no module): dual LX7 @240MHz, **8MB octal PSRAM** in-package |
| Flash | W25Q128 **16MB quad** SPI, QIO @80MHz → memory_type **`qio_opi`** |
| Display | 1.64" AMOLED **280×456 portrait**, driver **CO5300** (SH8601-compatible command set), **QSPI**: CS=9, CLK=10, D0–D3=11/12/13/14, RST=21. TE **not routed**. No backlight pin — brightness via DCS **0x51** over QSPI |
| Display quirks | Column offset **+20px** in controller RAM; draw windows must be **2-px aligned**; **no hardware rotation** (sw only, reported broken in Arduino_GFX); panel boots at brightness 0 — send 0x51 nonzero *after* 0x29 display-on |
| Touch | FT3168, I2C addr 0x38 on SDA=47/SCL=48; INT/RST **not routed** → poll only |
| IMU | QMI8658C on same I2C bus, addr 0x6A, INT1=46 |
| Buttons | **RST (EN, not a GPIO) + BOOT (GPIO0)** only. No other user buttons on board |
| Headers | P1: IO **1,2,3,5,6,7,8,15,16,17,18** free. P2: RXD44/TXD43/IO19/IO20/SDA47/SCL48/IO45/3V3/VBAT/GND/5V. Avoid strapping pins 3/45/46 for buttons |
| Power | No PMIC/AXP. ETA6098 charger (~2A charge current — high for small cells; check). Battery sense = GPIO4 ADC via ÷3 divider (200K/100K). No charge-status GPIO. 1.25mm 2-pin battery conn, **polarity unconfirmed — meter it** |
| RTC / speaker / LED | **None of the three** (no RTC chip, no buzzer, no user-controllable LED) |
| USB | Native S3 USB-CDC/JTAG only (no UART bridge). Needs `-DARDUINO_USB_CDC_ON_BOOT=1`. Recovery: hold BOOT, tap RST. VID:PID 303A:8249, enumerates `/dev/cu.usbmodem*` |
| PlatformIO | No official board def yet. Community-proven: `board = esp32-s3-devkitc-1` + `qio_opi` + 16MB + flags (below) |
| Physical | PCB 28.6×43.5mm, 4× M2 holes at 22.86×38.50mm spacing, display active area 22.3×36.1mm |

Proven Arduino display stack: **Arduino_GFX (moononournation)**
`Arduino_ESP32QSPI(9,10,11,12,13,14)` + `Arduino_CO5300(bus, RST=21, rot=0, 280, 456,
col_offset1=20, 0, 180, 24)`. Waveshare's own demos use `esp_lcd_sh8601` + LVGL 8.4
(we don't need LVGL).

## 2. Current-code audit — what's coupled to the M5StickC

There is **no HAL today**; all 20 firmware translation units include
`M5StickCPlus2.h`. The full M5 API surface actually used:

- `StickCP2.Display`: setRotation, sleep/wakeup, setBrightness, readRect (screenshot), width/height/getRotation
- `M5Canvas spr` — single full-screen **8bpp 135×240 sprite** (`main.cpp:551`); 8bpp was chosen to save heap for Bluedroid (no longer a constraint on S3 with PSRAM)
- Buttons: **raw digitalRead of GPIO 37/39** (`main.cpp:206`, `handleButtons` `:224-264`), not M5.Btn API. A=approve/boop + long-press sleep, B=deny. Synthetic `press a|b` serial injection for HIL keys off the same pins
- `StickCP2.Power`: getBatteryVoltage/Current, isCharging (status cmd in `xfer.h`, OTA battery gate in `ota.h`), setLed
- `StickCP2.Speaker`: chirps/beeps
- `StickCP2.Rtc`: set from `{"time":[epoch,tz]}` in `data.h`

**Portable as-is (no changes needed):** `ble_bridge.*` (Bluedroid NUS, same on S3),
`guard.h` (WDT/crash-loop/OTA-rollback, pure esp-idf), `stats.h` (Preferences),
the whole JSON wire protocol (`data.h` parse, `xfer.h`, `ota.h` envelopes), Swift
`RenderState`, and the Mac app's BLE discovery (scans by NUS service UUID, not name).

**Hardcoded geometry:** `main.cpp:33` (W/H/CX/CY_BASE), `buddy.cpp:12-17`
(BUDDY_* constants), `character.cpp` (PEEK_TOP=70, 140px GIF band), HUD layout
`main.cpp:640-702`, screenshot `row[256]` / `w>256` cap (`main.cpp:395,403`),
`tools/prep_character.py` TARGET_W=96, HIL heap floors (`test_hardening.py:39`).

## 3. Design decisions

### D1. Introduce a thin board HAL, keep both boards building
New `firmware/esp32/firmware/hal/` with `hal.h` + `board_m5stick.cpp` +
`board_ws_amoled164.cpp`, selected by `-DBOARD_WS_AMOLED_164` in a new
`[env:ws-amoled164]`. Surface (only what's actually used):

```
halInit(); halUpdate();
Display: halDisplaySleep/Wake, halSetBrightness(0-255), halPresent(canvas)
Canvas:  BuddyCanvas type (LGFX_Sprite on both boards), logical W/H constants
Buttons: halBtn(BTN_BOOP|BTN_REJECT|BTN_MENU) → bool (active), + synthetic inject hook
Power:   halBatteryVoltage(), halIsCharging() (best-effort), halSetLed() (no-op on WS)
Sound:   halTone() (no-op on WS)
Clock:   halSetTime(epoch,tz) → settimeofday on WS (no RTC chip; time lost on reboot — fine)
```

The 18 `buddies/*.cpp` files only need `extern BuddyCanvas spr` + the geometry
header — swap their `#include <M5StickCPlus2.h>` for `#include "hal/hal.h"` (mechanical,
scriptable). M5 env keeps `M5Canvas`; WS env uses plain LovyanGFX `LGFX_Sprite`
(identical API, no display bound).

### D2. Night-one rendering: logical canvas + integer 2× upscale
280×456 is almost exactly 2× of 135×240. Change the logical canvas to
**140×228** (touches only a handful of constants: CX=70, CY_BASE=114, HUD block
start y 170→158, BUDDY_CANVAS_W=140/X_CENTER=70) and present it **pixel-doubled
2× → exactly 280×456 full screen**. Every species animation, HUD, OTA screen, and
passkey screen works unchanged and looks chunky-cute at 2×. Native-res redesign is
a later UX pass.

Present path on WS: sprite 16bpp in PSRAM (140×228×2 = 64KB) → 2×2 expand into a
280×456 RGB565 PSRAM framebuffer (255KB) → one full-frame flush (even-aligned, so
the 2-px rule is free; full-frame flush also sidesteps the missing TE / tearing).
At 80MHz QSPI a full frame is ~4ms; our cadence is 5fps. Use Waveshare's exact
init sequence (sleep-out → 0xC4 0x80 → 0x53 0x20 → 0x63 0xFF → 0x29 → 0x51 brightness).
Never call setRotation on this panel.

### D3. Buttons: three externals on header GPIOs, staged fallbacks
Product mapping (Pebble):

| Button | Role | GPIO | Notes |
| --- | --- | --- | --- |
| Top "boop" | approve when prompt armed; else boop/tickle the pet (+ existing long-press = screen sleep) | **IO1** | momentary → GND, INPUT_PULLUP |
| Bottom-right | reject | **IO2** | same |
| Bottom-left | menu: cycle species / buddy state (persist via stats.h settings) | **IO5** | avoid strapping pins 3/45/46 |

Fallbacks so e2e works before any soldering:
1. **BOOT (GPIO0)** doubles as BOOP.
2. **FT3168 touch tap** (polled I2C) anywhere on screen = BOOP.
3. Serial/BLE `press a|b|m` synthetic injection (generalize from raw pins 37/39 to logical buttons — also what HIL uses).

Approve/deny wire format (`{"cmd":"permission","id":…,"decision":…}`) unchanged.
"Boop" is device-local for now (animation + stats bump); surfacing it to the app is later.

### D4. Build config
New env (decide at implementation: stay on `espressif32@6.13.0` if Arduino_GFX's
CO5300 class works on core 2.x, else give this env the **pioarduino** platform fork
(core 3.x) like the community repos — envs can differ in platform; Bluedroid BLE
API is unchanged on core 3):

```ini
[env:ws-amoled164]
board = esp32-s3-devkitc-1
board_build.mcu = esp32s3
board_build.f_cpu = 240000000L
board_build.f_flash = 80000000L
board_build.flash_mode = qio
board_build.arduino.memory_type = qio_opi
board_upload.flash_size = 16MB
board_build.filesystem = littlefs
board_build.partitions = partitions_16mb.csv
build_flags = -DBOARD_WS_AMOLED_164 -DBOARD_HAS_PSRAM -DARDUINO_USB_CDC_ON_BOOT=1
lib_deps = moononournation/GFX Library for Arduino, bitbank2/AnimatedGIF, bblanchon/ArduinoJson
```

`partitions_16mb.csv`: nvs + otadata + **2× 6MB OTA app slots** + ~3MB LittleFS
(keeps dual-OTA + rollback scheme; 4× the old budget, room for real GIF characters).
Do NOT copy Waveshare's sdkconfig (it wrongly says 8MB flash, single 6M factory app).

### D5. Screenshot: dump the logical sprite, not panel RAM
CO5300 readRect is unsupported/untested and 456 > the `row[256]` cap anyway. Change
`dumpScreenshot()` to read from `spr` (140×228, under the cap, board-agnostic,
same `<<SCR_BEGIN>>` framing + CRC). HIL screenshot tests keep working on both boards.

### D6. Power/OTA gate without an AXP
`halBatteryVoltage()` = ADC1_CH3 (GPIO4) ×3, few-sample average. No charge-status
GPIO: `halIsCharging()` = heuristic (vbat ≥ ~4.25V ⇒ on USB) and the OTA battery
gate passes when voltage reads as USB-powered/unknown. Keep the ≥30% rule otherwise.

## 4. Work plan

### Phase A — before the device arrives (all buildable/testable now)
1. `partitions_16mb.csv` + `[env:ws-amoled164]` in platformio.ini; keep `m5stickc-plus` env green.
2. HAL extraction: `hal/hal.h`, `board_m5stick.cpp` (pure move of current behavior), mechanical include swap in the 20 files. **Regression-flash the M5Stick and run `make hil`** — this proves the refactor before any new hardware.
3. `board_ws_amoled164.cpp`: Arduino_GFX QSPI+CO5300 init, brightness via 0x51, present() with 2× expand, buttons (IO1/IO2/IO5 + BOOT + touch-tap), battery ADC, no-op speaker/LED, settimeofday clock.
4. Logical-canvas retarget 135×240 → 140×228 (constants above) + third-button semantics in `handleButtons` + `press a|b|m`.
5. Screenshot-from-sprite change (D5).
6. Standalone panel spike sketch in `firmware/esp32/tools/` (fill colors, 1-px border to verify the 20-px offset, brightness ramp, touch echo, battery ADC print) — first thing flashed tonight.
7. Update `buddyctl.py` (`press m`, port glob already covers usbmodem; add `--no-dtr` if open-reset proves flaky on native CDC) and HIL baselines (heap floors re-measured on S3; screenshot dims 140×228).

### Phase B — bring-up ladder tonight (in order, each gate before the next)
1. `pio device list` → esptool chip-id → flash **spike sketch**: panel lights, colors correct (offset right: border visible on all 4 edges), brightness ramps, touch coordinates sane, vbat plausible.
2. Flash full firmware → `buddyctl.py ping --json` over USB CDC (PONG heap numbers will re-baseline).
3. `set --pet attention --waiting 1 --prompt-id req_1 …` → `expect` → `screenshot` → visual check.
4. `press a` synthetic approve → `{"cmd":"permission"…}` emitted. Then BOOT-button physical approve.
5. Guard checks: `hang` cmd → WDT recovery; reboot soak.
6. BLE: OS pair (passkey screen at 2× scale), `ble status`, `ble prompt --wait-decision`, Mac app connect.
7. **E2E:** Mac app running, real Claude hook fires → device shows attention → top button approves → agent proceeds.
8. `make hil` + `make hil-ble` with new baselines.
9. OTA over wire against the 16MB table + verify rollback path.
10. `tools/test_xfer.py` character transfer (LittleFS now 3MB — note GIF render is still unwired; transfer/storage only).

### Phase C — soon after (not tonight)
- Solder the 3 pebble buttons to IO1/IO2/IO5.
- OTA release channel: add a `board` field to PONG/`status` so the Mac app's FirmwareReleaseService serves per-board binaries (two firmwares exist now).
- ~~Menu-button UX~~ done in UX pass 1 (see status block).
- Touch as real "petting", QMI8658 IMU (shake/face-down → nap stat), native-res 280×456 layout, GIF character render wiring, deep-sleep power management (no PMIC → "off" = deep sleep, BOOT/GPIO0 is an RTC wake source).

## 5. Risks / watch-outs
- **Display bring-up is the only real unknown.** Mitigations: Waveshare's exact init sequence, full-frame even-aligned flushes, brightness after display-on, no setRotation. If Arduino_GFX misbehaves, fall back to Waveshare's `esp_lcd_sh8601` BSP files (Arduino-compatible, in their demo zip).
- Native USB CDC: port dies with the app on a crash (unlike a UART bridge); recovery is BOOT+RST. Serial-open may toggle DTR and reset the board — verify buddyctl/pytest behavior early, set dtr/rts False on open if needed.
- Battery: connector polarity unconfirmed (meter before plugging any cell) and ETA6098 is strapped for ~2A charge — pick a cell that tolerates it or plan the resistor swap. USB power only is fine for tonight.
- Heap floors and any timing baselines in `test_hardening.py` are M5-specific; re-baseline rather than chasing "failures".
- Keep the M5 env compiling + HIL-green so the old device remains the regression rig.
