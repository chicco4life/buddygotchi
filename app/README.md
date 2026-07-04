# Boop macOS App

This is the active Boop runtime: a Swift macOS menu bar app that receives AI agent hook events over localhost, reduces them into one state model, renders the menu bar popover, and optionally mirrors state to an M5StickC Plus 2 over BLE.

For full architecture, see `../docs/ARCHITECTURE.md`.

## Quick Start

```sh
swift build
swift test
swift run Boop
tools/package.sh
```

The app listens on `127.0.0.1:21321` by default:

```sh
curl http://127.0.0.1:21321/healthz
```

## Tests

`swift test` requires a developer directory with XCTest available, normally a full Xcode install.

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
