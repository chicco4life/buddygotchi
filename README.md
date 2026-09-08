# Boop

Boop is a native macOS menu bar companion for AI coding agents. It watches Claude Code, Cursor, and Codex through local hook integrations, turns their activity into buddy state, surfaces approval prompts, and can mirror the same state to a Boop hardware buddy over Bluetooth.

The current product lives in three top-level areas: the Swift macOS app in `app/`, the landing page in `landing/`, and the active ESP32 firmware in `firmware/esp32/`. Planning and reference material lives in `research/`; public release/support pages live in `docs/`.

## What It Does

- Shows sleep, idle, busy, attention, celebrate, error, and thinking states in the macOS menu bar popover.
- Tracks multiple concurrent agent sessions and shows a compact per-session breakdown.
- Displays current tool activity, recent activity entries, completion review cards, and error/thinking cards.
- Supports local approval mode for blocking tool calls, with approve/deny from the popover or the paired hardware buddy.
- Installs hooks for Claude Code, Cursor, and Codex, while failing open to the agent's native behavior when Boop is not running.
- Streams heartbeat JSON to ESP32 firmware over Nordic UART BLE and supports firmware update checks/uploads from the app.

## Requirements

- macOS 14 or newer
- Xcode with Swift 6 and XCTest for tests. Command Line Tools may be enough for `swift build`, but `swift test` needs XCTest available.
- Optional: PlatformIO for ESP32 firmware work
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
swift run Boop
```

When the app is running, the local health endpoint is:

```sh
curl http://127.0.0.1:21321/healthz
```

The first-run wizard walks through agent detection, hook installation, connection testing, buddy selection, and optional hardware buddy pairing. To reset onboarding:

```sh
defaults delete Boop setupCompleted
```

## Useful Developer Commands

```sh
make lint              # requires swift-format
make package           # build an unsigned .app bundle and zip
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
| `landing/` | Next.js landing page and waitlist API |
| `firmware/esp32/` | ESP32 firmware, PlatformIO config, character tools, and device docs |
| `research/plan/` | The active direction: vision, device UX, architecture, verification, implementation plan, ideas |
| `research/archived/` | Earlier product, marketing, hardware, and engineering docs, plus captured agent hook references |
| `docs/` | Public release/support pages and web flasher assets |
| `README.md` | Overview and build/run/test instructions |
| `AGENTS.md`, `CLAUDE.md` | Repo instructions for coding agents |

## ESP32 Firmware

```sh
cd firmware/esp32
pio run
pio run -t upload
pio run -t uploadfs
```

Hardware helper scripts:

```sh
python3 firmware/esp32/tools/screenshot.py --out /tmp/buddy.png
python3 firmware/esp32/tools/button.py --mock a
python3 firmware/esp32/tools/button.py b
```

## More Detail

See [research/plan/ARCHITECTURE.md](research/plan/ARCHITECTURE.md) for the target architecture and [research/archived/eng/ARCHITECTURE-APP.md](research/archived/eng/ARCHITECTURE-APP.md) for the source-derived description of the current code. See [AGENTS.md](AGENTS.md) for repo-specific instructions for coding agents.

Release and support details live in [docs/RELEASE.md](docs/RELEASE.md) and [docs/SUPPORT.md](docs/SUPPORT.md). To remove Boop, use Settings, About, Remove Boop, or follow the manual uninstall notes in the support doc.

## License

The ESP32 firmware license is in [firmware/esp32/LICENSE](firmware/esp32/LICENSE).
