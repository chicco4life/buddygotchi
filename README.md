# Buddygotchi

Buddygotchi is a native macOS menu bar companion for AI coding agents. It watches Claude Code, Cursor, and Codex through local hook integrations, turns their activity into an animated buddy state, surfaces approval prompts, and can mirror the same state to an M5StickC Plus 2 over Bluetooth.

The current production path is the Swift app in `app/`. The older Bun/TypeScript daemon under `src/src/` is retained as reference code; the active ESP32 firmware still lives under `src/outputs/esp32/`.

## What It Does

- Shows sleep, idle, busy, attention, celebrate, error, and thinking states in the macOS menu bar popover.
- Tracks multiple concurrent agent sessions and shows a compact per-session breakdown.
- Displays current tool activity, recent activity entries, completion review cards, and error/thinking cards.
- Supports local approval mode for blocking tool calls, with approve/deny from the popover or the paired M5Stack.
- Installs hooks for Claude Code, Cursor, and Codex, while failing open to the agent's native behavior when Buddygotchi is not running.
- Streams heartbeat JSON to ESP32 firmware over Nordic UART BLE and supports firmware update checks/uploads from the app.

## Requirements

- macOS 14 or newer
- Xcode with Swift 6 and XCTest for tests. Command Line Tools may be enough for `swift build`, but `swift test` needs XCTest available.
- Optional: PlatformIO for ESP32 firmware work
- Optional: Bun for the legacy TypeScript daemon/tests
- Optional: `swift-format` for local lint checks

## Build, Run, And Test

From the repo root:

```sh
make build
make test
make run
```

Equivalent SwiftPM commands:

```sh
cd app
swift build
swift test
swift run Buddygotchi
```

When the app is running, the local health endpoint is:

```sh
curl http://127.0.0.1:21321/healthz
```

The first-run wizard walks through agent detection, hook installation, connection testing, buddy selection, and optional M5Stack pairing. To reset onboarding:

```sh
defaults delete Buddygotchi setupCompleted
```

## Useful Developer Commands

```sh
make lint              # requires swift-format
make test-snapshots    # opt-in SwiftUI PNG snapshot harness
make e2e               # HTTP smoke suite; requires the app already running
make clean             # remove SwiftPM build output
```

The e2e smoke runner can also be invoked directly:

```sh
app/tools/e2e-smoke.sh
app/tools/e2e/claude.sh
app/tools/e2e/codex.sh
app/tools/e2e/cursor.sh
```

## Project Layout

| Path | Purpose |
| --- | --- |
| `app/` | Active macOS Swift app, hook CLIs, tests, and e2e scripts |
| `app/Buddygotchi/Core/` | Pure reducer, state model, events, engine, config, diagnostics |
| `app/Buddygotchi/Server/` | Hummingbird HTTP input for hook events, signals, approvals, and health |
| `app/Buddygotchi/Views/` | SwiftUI popover, settings, setup wizard, activity cards |
| `app/Buddygotchi/Outputs/ESP32/` | BLE output, heartbeat mapper, OTA update client |
| `app/BuddygotchiSignal/` | Cursor hook CLI that bridges stdin payloads to HTTP |
| `src/outputs/esp32/` | ESP32 firmware, PlatformIO config, character tools, device docs |
| `src/src/` | Legacy Bun/TypeScript daemon and browser UI prototype |
| `external_sites/` | Captured external hook docs used as implementation references |

## ESP32 Firmware

```sh
cd src/outputs/esp32
pio run
pio run -t upload
pio run -t uploadfs
```

Hardware helper scripts:

```sh
python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy.png
python3 src/outputs/esp32/tools/button.py --mock a
python3 src/outputs/esp32/tools/button.py b
```

## More Detail

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the app is pieced together, including hook routing, state aggregation, outputs, mocks, and test strategy. See [AGENTS.md](AGENTS.md) for repo-specific instructions for coding agents.

## License

The ESP32 firmware license is in [src/outputs/esp32/LICENSE](src/outputs/esp32/LICENSE).
