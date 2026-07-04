# Buddygotchi Agent Instructions

These instructions apply to the whole repo.

## Current Product Shape

- The active app is the Swift macOS project in `app/`.
- The production data path is `agent hooks -> HookServer -> BuddyEngine -> pure reducer -> OutputProvider`.
- The ESP32 firmware in `firmware/esp32/` is active and consumes the Swift app's heartbeat JSON.

## Build And Test

From the repo root:

```sh
make build
make test
make run
```

Direct SwiftPM equivalents:

```sh
cd app
swift build
swift test
swift run Buddygotchi
```

`swift test` requires a developer directory with XCTest available, normally a full Xcode install.

Useful targeted checks:

```sh
cd app
swift test --filter ReducerTests
swift test --filter EngineIntegrationTests
swift test --filter AutoApproveTests
mkdir -p /tmp/buddy-snapshots && touch /tmp/buddy-snapshots/.enable
swift test --disable-sandbox --filter SnapshotHarnessTests
```

HTTP smoke tests require the app running in a real terminal:

```sh
app/tools/e2e-smoke.sh
app/tools/e2e/claude.sh
app/tools/e2e/codex.sh
app/tools/e2e/cursor.sh
```

## Architecture Rules

- Keep `app/Buddygotchi/Core/` pure. The reducer must not perform I/O, read clocks, read user defaults, call UI, or touch BLE.
- Model new behavior as `BuddyEvent` values and reducer transitions first.
- Add agent-specific parsing in `HookServer` or hook installer code, not in output code.
- Add displays by implementing `OutputProvider` and deriving everything from `BuddyState`.
- Preserve fail-open hook behavior. If Buddygotchi is down, agent hooks should exit successfully and let the agent's native flow continue.
- Approval continuations belong in `BuddyEngine`, not in `BuddyState`.
- Treat `RenderState` in `Outputs/ESP32/Heartbeat.swift` as the desktop-to-firmware wire contract.
- Keep Cursor auto-approval conservative. Shell commands with control characters must require manual review.

## Files To Know

| File | Role |
| --- | --- |
| `app/Buddygotchi/Core/BuddyState.swift` | Public state projection and session models |
| `app/Buddygotchi/Core/BuddyReducer.swift` | State transition authority |
| `app/Buddygotchi/Core/BuddyEngine.swift` | Main orchestrator, outputs, approval continuations |
| `app/Buddygotchi/Server/HookServer.swift` | HTTP input adapter and approval responses |
| `app/Buddygotchi/Install/HookInstaller.swift` | Agent hook registration and generated bash script |
| `app/Buddygotchi/Outputs/ESP32/Heartbeat.swift` | Hardware heartbeat mapper |
| `app/Buddygotchi/Outputs/ESP32/BLEManager.swift` | BLE transport, inbound approvals, OTA acks |
| `app/Buddygotchi/Views/PopoverView.swift` | Main user-visible UI |

## Documentation Expectations

- Keep `README.md` focused on overview and build/run/test instructions.
- Keep `docs/ARCHITECTURE.md` focused on how pieces fit together, including test/mocking strategy.
- Keep this file mirrored in `CLAUDE.md`.
- Use `docs/PLAN.md`, `docs/BUGS.md`, and `docs/TODOs.md` for current status only; do not let old completed task dumps become the source of truth.
