# Boop

This repository is mid-redesign. `plan/` holds the direction for the next
generation (vision, device UX, architecture, verification, implementation
plan). `archived/` holds the complete previous generation, which still
builds and runs: the Swift macOS menu bar app, the ESP32 firmware, the
landing page, hardware files, and earlier research. Start with
[plan/VISION.md](plan/VISION.md) and [plan/PLAN.md](plan/PLAN.md).

The v2 Waveshare firmware builds from the active tree:

```sh
cd firmware/esp32
tools/pio_ws.sh run -e ws-amoled164
python3 -m py_compile tests/hil/test_usb.py
```

See [firmware/esp32/README.md](firmware/esp32/README.md) for device controls and HIL.

For physical animation verification using the laptop camera, run `make webcam
ARGS='list'` from the repository root and follow the
[webcam workflow](tools/webcam/README.md). `make webcam-test` checks the tooling
without opening a camera.

The rest of this file describes the archived implementation. Every command
below runs from `archived/` unless it says otherwise.

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

From `archived/`:

```sh
cd archived
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
archived/app/tools/e2e-smoke.sh
archived/app/tools/e2e/claude.sh
archived/app/tools/e2e/codex.sh
archived/app/tools/e2e/cursor.sh
```

## Project Layout

| Path | Purpose |
| --- | --- |
| `archived/app/` | Active macOS Swift app, hook CLIs, tests, and e2e scripts |
| `archived/landing/` | Next.js landing page and waitlist API |
| `archived/firmware/esp32/` | ESP32 firmware, PlatformIO config, character tools, and device docs |
| `plan/` | The active direction: vision, device UX, architecture, verification, implementation plan, ideas |
| `archived/research/` | Earlier product, marketing, hardware, and engineering docs, plus captured agent hook references |
| `archived/docs/` | Public release/support pages and web flasher assets |
| `README.md` | Overview and build/run/test instructions |
| `AGENTS.md`, `CLAUDE.md` | Repo instructions for coding agents |

## ESP32 Firmware

```sh
cd archived/firmware/esp32
pio run
pio run -t upload
pio run -t uploadfs
```

Hardware helper scripts:

```sh
python3 archived/firmware/esp32/tools/screenshot.py --out /tmp/buddy.png
python3 archived/firmware/esp32/tools/button.py --mock a
python3 archived/firmware/esp32/tools/button.py b
```

## More Detail

See [plan/ARCHITECTURE.md](plan/ARCHITECTURE.md) for the target architecture and [archived/research/eng/ARCHITECTURE-APP.md](archived/research/eng/ARCHITECTURE-APP.md) for the source-derived description of the current code. See [AGENTS.md](AGENTS.md) for repo-specific instructions for coding agents.

Support steps (doctor, forgetting, reset and retire, hook regressions) live in [docs/SUPPORT.md](docs/SUPPORT.md); the previous generation's release notes are in [archived/docs/RELEASE.md](archived/docs/RELEASE.md). To remove Boop, use Settings, About, Remove Boop, or follow the manual uninstall notes in the support doc.

## License

The ESP32 firmware license is in [archived/firmware/esp32/LICENSE](archived/firmware/esp32/LICENSE).

For concurrent feature work, see [parallel development](tools/dev/README.md):
per-worktree headless instances and a shared ESP32 reservation workflow.
