# ESP32 Hardware Buddy

C++ firmware, character assets, and tooling for the ESP32 hardware buddy display. This is the original [Claude Desktop Buddy](https://github.com/anthropics/claude-desktop-buddy) codebase, kept under `firmware/esp32/`.

Two boards build from the same source via the HAL in `firmware/hal/`:

| Board | Env | Notes |
|-------|-----|-------|
| M5StickC Plus 2 | `m5stickc-plus` (default) | Original dev board / regression rig. ST7789 135x240, buttons A/B. |
| Waveshare ESP32-S3-Touch-AMOLED-1.64 | `ws-amoled164` | Production "Boop Pebble" board. CO5300 280x456 QSPI AMOLED, FT3168 touch, external BOOP/REJECT/MENU buttons on IO1/IO2/IO5 (BOOT doubles as BOOP). `ws-amoled164-spike` is the bring-up smoke test. Port plan: `archived/research/eng/waveshare-amoled-port.md`. |

## Contents

| Directory | Purpose |
|-----------|---------|
| `firmware/` | ESP32 Arduino firmware (main loop, BLE bridge, character renderer, ASCII sprites) |
| `characters/` | GIF-based character packs for the display (e.g. `bufo/`) |
| `tools/` | Python scripts: `prep_character.py` (downscale GIFs), `flash_character.py` (USB flash to LittleFS) |
| `docs/` | Hardware manual, device photos, UI screenshots |
| `platformio.ini` | PlatformIO build config |
| `REFERENCE.md` | BLE Nordic UART protocol spec |
| `CONTRIBUTING.md` | Upstream contribution guidelines (fork-first) |

## Modes

1. **Direct mode** — Pairs with Claude Code over BLE using the NUS UART protocol. No daemon needed.
2. **Boop mode** — Receives heartbeat JSON from the macOS app over BLE.

## Building

Requires [PlatformIO](https://platformio.org/):

```bash
cd firmware/esp32
pio run                            # compile default (M5) firmware
pio run -t upload                  # flash to device
pio run -t uploadfs                # flash character assets (LittleFS)

# Waveshare AMOLED board — always via the wrapper (isolates the pioarduino
# platform's packages from the M5 envs' espressif32 packages):
tools/pio_ws.sh run -e ws-amoled164
tools/pio_ws.sh run -e ws-amoled164 -t upload
tools/pio_ws.sh run -e ws-amoled164-spike -t upload   # bring-up smoke test
```

## Preparing characters

```bash
python3 tools/prep_character.py characters/bufo/
python3 tools/flash_character.py bufo
```

See `REFERENCE.md` for the BLE wire protocol.
