# M0: Setup — evidence

Run 2026-09-26 on branch `v1-overnight`, started from tag `gen2-final`
(commit 2370dad).

## What changed

- Tagged `gen2-final` and created `v1-overnight`.
- Deleted the gen-2 code: `firmware/esp32/`, `wire/`, `tools/dev/`,
  `tools/demo/`, every gen-2 source and test in `app/`, `archived/app`,
  `archived/firmware`, and the release and firmware-release workflows.
  Everything is still at `git show gen2-final:<path>`, including the pieces
  PLAN.md §1 says to reuse later (`HookInstaller.swift`, `BLEManager.swift`,
  `VoiceRuntime.swift`, `ViewState.swift`, `InstanceLock.swift`,
  `buddyctl.py`).
- Kept: `app/Tests/Fixtures/hooks/`, the XCTest shim, `app/tools/test.py` and
  `gen-test-runner.py` (now importing `BoopKit`), `tools/webcam/`, `skills/`.
- `app/` is the new SwiftPM layout: library `BoopKit`, executables `Boop`,
  `boop-hook` and `boopdev`, with the shim test runner. No dependencies.
  Platform macOS 26 (tools version 6.2), for Foundation Models later.
- `firmware/` is the new PlatformIO project: env `cyd24` (pioarduino 55.03.39,
  Arduino core 3.3.9, `esp32dev`, 4 MB DIO, `min_spiffs.csv`; LovyanGFX,
  NimBLE-Arduino, ArduinoJson) and env `native` (tests and `boop-sim`).
  `firmware/tools/pio.sh` keeps PlatformIO's packages in
  `firmware/.platformio-core`. `firmware/tools/version.py` bakes the version
  and git SHA into the build.
- `tools/boopctl` (shell wrapper → `tools/boopctl_lib/` in `tools/.venv`)
  with `ports`, `ping`, `state` and `send`. The rest arrives with F1/F2.
- New Makefile with `build run test tools fw flash sim fw-test e2e`. `e2e`
  prints "not built yet" until J1.
- CLAUDE.md, AGENTS.md, README.md and the opt-in CI workflow updated.

## Checks

All ran in one pass; full output in [checks.log](checks.log).

| Check | Result |
| --- | --- |
| `make build` | Passed (Boop, boop-hook, boopdev) |
| `make test` | Passed: 1 test via the shim runner |
| `make fw` | Passed: RAM 7.6%, flash 20.4% of the app slot |
| `make fw-test` | Passed: 2 canvas tests on `native` |
| `make sim` | Passed (builds the `boop-sim` stub) |
| `make tools` | Passed (venv created fresh earlier in the run; this pass was a no-op) |
| `tools/boopctl ports` | Passed: `/dev/cu.usbserial-110` |

The board wasn't flashed in M0; it still runs its factory demo.
