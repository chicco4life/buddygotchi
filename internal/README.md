# Internal code

Everything in the repo that doesn't ship. What ships is in `app/` (the Mac
app, `boop-hook` and their libraries) and `firmware/` (the board's
firmware, its generated assets and the scripts that build it). This folder
has the tests, evals, dev tools and skills that check them.

| Path | What it is |
| --- | --- |
| `app/Boop/` | `Headless.swift` and `Snapshots.swift`: the sources of `Boop --headless` and `Boop --snapshots`, which are compiled into the shipped `Boop` target |
| `app/BoopDevKit/` | A library for `boopdev` and the tests: the harness evals (`Eval/`, [plan/EVALS.md](../plan/EVALS.md)) and hook replay (`Replay.swift`) |
| `app/BoopDev/` | `boopdev`, the developer CLI ([plan/VERIFICATION.md](../plan/VERIFICATION.md) §2) |
| `app/Tests/` | The Swift unit tests (`BoopTests`) and their fixtures |
| `app/TestSupport/XCTestShim/` | A stand-in XCTest for Command Line Tools, which has none |
| `app/Evals/scenarios/` | The eval scenarios `boopdev eval` runs against Jev |
| `app/tools/` | `test.py` (`make test`) and `gen-test-runner.py`, which writes the tests' `main` for the shim |
| `firmware/sim/` | The simulator's `main` (`boop-sim`), built with the firmware's pure C++ in PlatformIO's `native` env |
| `firmware/test/` | The firmware's unit tests, the simulator scenarios and their golden pictures |
| `tools/` | `boopctl` (the board over USB, the simulator, and the live dashboard, [plan/DASHBOARD.md](../plan/DASHBOARD.md)), `voicegen`, `fontgen` and `facegen` (they write `firmware/assets/*.h`, which is checked in; `facegen` reads the mood designs in `tools/facegen/design/`), and the `webcam/` recorder |
| `skills/` | `doctor` and `webcam-verify`, linked from `.claude/skills/`, `.codex/skills/` and `.cursor/skills/` |

## How it's wired

- **Swift.** `Package.swift` is at the repo root, because SwiftPM takes no
  target outside the package's root and the targets live in both `app/`
  and here. The production targets (`HookWire`, `BoopKit`, `Boop`,
  `BoopHook`) never depend on the internal ones (`BoopDevKit`, `BoopDev`,
  `BoopTests`, `XCTest`). SwiftPM alone only warns about an import of a
  target that isn't a dependency, so `make build` and `make test` build
  with `--explicit-target-dependency-import-check error`, and code in
  `app/` that imports anything from here fails the build. The one
  exception is the `Boop` target: its path is the repo root and its
  sources are `app/Boop/` and `internal/app/Boop/`, so headless mode and
  snapshots are part of the app while their sources live here. Everything
  builds into `.build/` at the root.
- **Firmware.** `firmware/platformio.ini` points its `test_dir` here, and
  the `native` env's `build_src_filter` adds `internal/firmware/sim/`
  (the filter is relative to `firmware/src/`).
- **Tools.** Scripts find the repo root from their own path. `boopctl`
  keeps its Python in `internal/tools/.venv` (`make tools`), and the
  webcam recorder builds into `internal/tools/webcam/.build`, apart from
  SwiftPM's `.build/`.

The make targets that use all this are in
[plan/VERIFICATION.md](../plan/VERIFICATION.md) §2.
