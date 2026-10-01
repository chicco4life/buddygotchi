# Internal code

Everything in the repo that doesn't ship. What ships is in `app/` (the Mac
app and its library, BoopKit), `firmware/` (the board's firmware, its
generated assets and the scripts that build it), and three packages of
their own, each with its own tests beside its code
([documentation/MODULES.md](../documentation/MODULES.md)): `agent-hooks/` (the hook client
and its library), `jharness/` (the brain's harness, `jharness-emit` and
its example, Beacon) and `linkkit/` (the device link: its Swift host and
the C++ device library the firmware builds). This folder has Boop's
tests, evals, dev tools and skills.

| Path | What it is |
| --- | --- |
| `app/Boop/` | `Headless.swift` and `Snapshots.swift`: the sources of `Boop --headless` and `Boop --snapshots`, which are compiled into the shipped `Boop` target |
| `app/BoopDevKit/` | A library for `boopdev` and the tests: the harness evals (`Eval/`, [documentation/EVALS.md](../documentation/EVALS.md)) and hook replay (`Replay.swift`) |
| `app/BoopDev/` | `boopdev`, the developer CLI ([documentation/VERIFICATION.md](../documentation/VERIFICATION.md) §2) |
| `app/Tests/` | Boop's Swift unit tests (`BoopTests`) and their fixtures. The packages' tests are in each package, under `swift test` (`agent-hooks/Tests/`, `jharness/Tests/`, `linkkit/Tests/`); the hook fixtures are agent-hooks' (`agent-hooks/Tests/AgentHooksTests/Fixtures/`), and only the pipeline check's are here (`Fixtures/hooks/e2e/`) |
| `app/TestSupport/XCTestShim/` | A stand-in XCTest for Command Line Tools, which has none |
| `app/Evals/scenarios/` | The eval scenarios `boopdev eval` runs against Jev |
| `app/tools/` | `gen-test-runner.py`, which writes the tests' `main` for the shim (`make build` runs it) |
| `firmware/sim/` | The simulator's `main` (`boop-sim`), built with the firmware's pure C++ and LinkKit's device library in PlatformIO's `native` env |
| `firmware/test/` | The firmware's unit tests, the simulator scenarios and their golden pictures. LinkKit's device library tests in its own project (`linkkit/device/test/`) |
| `firmware/pack_file.h` | The voice pack read from `.build/voice/voice.bin`, for the simulator and the tests, which have no SD card |
| `tools/` | `boopctl` (the board over USB, the simulator, the live dashboard, a day's summary from the debug logs, and `boopctl workday`, a scripted working day through the headless app and its brain, [documentation/EVALS.md](../documentation/EVALS.md) §5), `voicegen`, `sfxgen`, `fontgen` and `facegen` (they write `firmware/assets/*.h`, which is checked in; `facegen` runs the animation bank's generator, `boop-design/boop-sound-bank-v4/`, for the designs, `sfxgen` imports its sounds, and `voicegen` converts the recorded voice bank, `boop-design/assets/boop-voice-v1/`, into the voice pack for the board's SD card, `.build/voice/voice.bin`, which isn't checked in, and the Mac's `Takes.swift`), and the `webcam/` recorder |
| `skills/` | `doctor` and `webcam-verify`, linked from `.claude/skills/`, `.codex/skills/` and `.cursor/skills/` |
| `boop-design/` | The animation bank, the source of the device's designs and sounds (facegen and sfxgen build from it), with its offline preview, the approved mood-graph design/handover, and the recorded voice bank ([guide](boop-design/README.md)) |

## How it's wired

- **Swift.** `Package.swift` is at the repo root, because SwiftPM takes no
  target outside the package's root and the targets live in both `app/`
  and here. The production targets (`BoopKit`, `Boop`, and the products
  they take from the three local packages the root one depends on,
  `agent-hooks`, `jharness` and `linkkit`) never depend on the internal
  ones (`BoopDevKit`, `BoopDev`, `BoopTests`, `XCTest`). SwiftPM alone only warns about an import of a
  target that isn't a dependency, so `make build`, `make app` and
  `make -C internal test` build with
  `--explicit-target-dependency-import-check error`, and code in
  `app/` that imports anything from here fails the build. The one
  exception is the `Boop` target: its path is the repo root and its
  sources are `app/Boop/` and `internal/app/Boop/`, so headless mode and
  snapshots are part of the app while their sources live here. Everything
  builds into `.build/` at the root. Each package's own tests run under
  `swift test` in its folder, into its own `.build/tests`, which
  `make -C internal test` runs after Boop's.
- **Firmware.** `firmware/platformio.ini` points its `test_dir` here, and
  the `native` env's `build_src_filter` adds `internal/firmware/sim/`
  (the filter is relative to `firmware/src/`). Both envs link LinkKit's
  device library, `linkkit/device/`, through `lib_deps`
  (`symlink://../linkkit/device`), so the tests and the simulator run the
  same kit as the board. The library's own tests are in its folder, with
  a PlatformIO project of their own (`linkkit/device/platformio.ini`),
  which `make -C internal fw-test` runs after Boop's.
- **Tools.** Scripts find the repo root from their own path. `boopctl`
  keeps its Python in `internal/tools/.venv` (`make -C internal tools`), and the
  webcam recorder builds into `internal/tools/webcam/.build`, apart from
  SwiftPM's `.build/`.

`internal/Makefile` has the development targets; run them from the repo
root as `make -C internal <target>`. They are listed in
[documentation/VERIFICATION.md](../documentation/VERIFICATION.md) §2.
