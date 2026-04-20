# ESP32 Hardware Buddy

C++ firmware, character assets, and tooling for the ESP32 hardware buddy display (M5StickC Plus). This is the original [Claude Desktop Buddy](https://github.com/anthropics/claude-desktop-buddy) codebase, consolidated here from the repo root.

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
2. **Daemon mode** — Connects to the buddygotchi daemon over WiFi.

## Building

Requires [PlatformIO](https://platformio.org/):

```bash
cd src/outputs/esp32
pio run                    # compile firmware
pio run -t upload          # flash to device
pio run -t uploadfs        # flash character assets (LittleFS)
```

## Preparing characters

```bash
python3 tools/prep_character.py characters/bufo/
python3 tools/flash_character.py bufo
```

See `REFERENCE.md` for the BLE wire protocol.
