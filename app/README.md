# Boop macOS App

This is the active Boop runtime: a Swift macOS menu bar app that receives AI agent hook events over localhost, reduces them into one state model, renders the menu bar popover, and optionally mirrors state to the Waveshare AMOLED 1.64 ESP32 over BLE.

For the target architecture and implementation status, see `../plan/ARCHITECTURE.md` and `../plan/PLAN.md`.

## Quick Start

```sh
swift build
make -C .. test
swift run Boop
tools/package.sh
```

The app listens on `127.0.0.1:21321` by default:

```sh
curl http://127.0.0.1:21321/healthz
```

## Tests

`make -C .. test` runs the test target selected by `Package.swift`: real XCTest
with full Xcode, or the generated executable runner with CommandLineTools.
It regenerates the shim runner before executing it and propagates failures.
The targeted `swift test` commands below require full Xcode.

```sh
swift test
swift test --filter ReducerTests
swift test --filter EngineIntegrationTests
swift test --filter AutoApproveTests
```

Snapshot harness:

```sh
mkdir -p /tmp/buddy-snapshots
touch /tmp/buddy-snapshots/.enable
swift test --disable-sandbox --filter SnapshotHarnessTests
```

HTTP smoke tests require the app running in a real terminal:

```sh
../app/tools/e2e-smoke.sh
```

## Layout

| Path | Purpose |
| --- | --- |
| `Boop/App/` | App delegate, menu bar lifecycle, login item helper |
| `Boop/Core/` | Pure state model, reducer, events, engine, config, diagnostics |
| `Boop/Server/` | Hummingbird hook routes |
| `Boop/Install/` | Agent hook installers and generated bash script |
| `Boop/Views/` | SwiftUI popover, settings, setup wizard |
| `Boop/Outputs/ESP32/` | BLE heartbeat output and firmware updater |
| `BoopSignal/` | Cursor hook bridge binary |
| `Tests/` | XCTest unit, integration, auto-approval, and snapshot harness tests |
| `tools/` | Shell e2e smoke scripts |

## Reset Onboarding

```sh
defaults delete Boop setupCompleted
```
