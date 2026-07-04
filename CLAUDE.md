# Boop Agent Instructions

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
swift run Boop
```

`swift test` requires a developer directory with XCTest available, normally a full Xcode install.

If `swift build` or `swift test` fails before compiling project sources with
SwiftPM or Clang module-cache errors under `~/.cache/clang` or
`~/Library/org.swift.swiftpm`, rerun the same command outside the restricted
sandbox. In this environment the sandbox can block SwiftPM's user-level cache
writes and surface misleading SDK/compiler mismatch errors. Only investigate
source changes after the command also fails outside the sandbox.

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

ESP32 hardware-in-the-loop checks require a plugged-in M5StickC Plus 2:

```sh
make hil
make hil-ble
```

Verifying firmware on the real device:

```sh
cd firmware/esp32
pio run -e m5stickc-plus -t upload
tools/buddyctl.py ping --json
tools/buddyctl.py set --pet attention --waiting 1 --prompt-id req_1 --prompt-tool Bash --prompt-hint "npm test"
tools/buddyctl.py expect --pet attention --prompt-id req_1 --json
tools/buddyctl.py screenshot --out approve.png --scale 2 --json
tools/buddyctl.py press a --ms 150 --json
```

Use `tools/buddyctl.py ble status`, `ble set`, and `ble prompt --wait-decision`
after the one-time OS pairing step to exercise the production BLE transport.

## Architecture Rules

- Keep `app/Boop/Core/` pure. The reducer must not perform I/O, read clocks, read user defaults, call UI, or touch BLE.
- Model new behavior as `BuddyEvent` values and reducer transitions first.
- Add agent-specific parsing in `HookServer` or hook installer code, not in output code.
- Add displays by implementing `OutputProvider` and deriving everything from `BuddyState`.
- Preserve fail-open hook behavior. If Boop is down, agent hooks should exit successfully and let the agent's native flow continue.
- Approval continuations belong in `BuddyEngine`, not in `BuddyState`.
- Treat `RenderState` in `Outputs/ESP32/Heartbeat.swift` as the desktop-to-firmware wire contract.
- Keep Cursor auto-approval conservative. Shell commands with control characters must require manual review.

## Files To Know

| File | Role |
| --- | --- |
| `app/Boop/Core/BuddyState.swift` | Public state projection and session models |
| `app/Boop/Core/BuddyReducer.swift` | State transition authority |
| `app/Boop/Core/BuddyEngine.swift` | Main orchestrator, outputs, approval continuations |
| `app/Boop/Server/HookServer.swift` | HTTP input adapter and approval responses |
| `app/Boop/Install/HookInstaller.swift` | Agent hook registration and generated bash script |
| `app/Boop/Outputs/ESP32/Heartbeat.swift` | Hardware heartbeat mapper |
| `app/Boop/Outputs/ESP32/BLEManager.swift` | BLE transport, inbound approvals, OTA acks |
| `app/Boop/Views/PopoverView.swift` | Main user-visible UI |

## Documentation Expectations

- Keep `README.md` focused on overview and build/run/test instructions.
- Keep `research/eng/ARCHITECTURE.md` focused on how pieces fit together, including test/mocking strategy.
- Keep this file mirrored in `CLAUDE.md`.
- Use `research/TODOs.md` for open cross-functional items.
- Use `research/eng/TESTING.md` and `research/eng/RELEASE.md` for engineering verification and release gates.
- Keep external agent reference captures under `research/eng/reference/`.
