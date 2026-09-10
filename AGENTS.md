# Boop Agent Instructions

These instructions apply to the whole repo.

## Repo Layout

- `plan/` is the active direction: `VISION.md`, `UX-DEVICE.md`,
  `ARCHITECTURE.md`, `VERIFICATION.md`, `PLAN.md`, `IDEAS.md`. Read
  `plan/PLAN.md` to find the current phase before starting work.
- `archived/` is the previous generation of the product, moved whole: the
  Swift macOS app (`archived/app/`), the ESP32 firmware
  (`archived/firmware/esp32/`), the landing page, hardware, emails, docs,
  the Makefile, and the earlier research (`archived/research/`). It still
  builds and runs, and `plan/ARCHITECTURE.md` §10 says which parts carry
  forward. Do not extend it except to keep it building; new work lands
  outside `archived/` per the plan.
- `skills/doctor/` is the agent-agnostic harness self-check: `SKILL.md` plus
  the `doctor.sh` it drives, symlinked into `.claude`, `.codex`, and `.cursor`.

## Current Product Shape

- The production data path of the archived app is
  `agent hooks -> HookServer -> BuddyEngine -> pure reducer -> OutputProvider`.
- The target data path is in `plan/ARCHITECTURE.md`:
  `hooks -> Server -> Extractor -> Core -> Outputs`, with `Store` and
  `Voice` beside the core.
- The archived ESP32 firmware consumes the archived app's heartbeat JSON;
  the target wire contract is `RenderState v2` in `plan/ARCHITECTURE.md` §8.

## Build And Test

The archived implementation builds from `archived/`:

```sh
cd archived
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
archived/app/tools/e2e-smoke.sh
archived/app/tools/e2e/claude.sh
archived/app/tools/e2e/codex.sh
archived/app/tools/e2e/cursor.sh
```

ESP32 hardware-in-the-loop checks require a plugged-in M5StickC Plus 2:

```sh
make hil
make hil-ble
```

Verifying firmware on the real device:

```sh
cd archived/firmware/esp32
pio run -e m5stickc-plus -t upload
tools/buddyctl.py ping --json
tools/buddyctl.py set --pet attention --waiting 1 --prompt-id req_1 --prompt-tool Bash --prompt-hint "npm test"
tools/buddyctl.py expect --pet attention --prompt-id req_1 --json
tools/buddyctl.py screenshot --out approve.png --scale 2 --json
tools/buddyctl.py press a --ms 150 --json
```

Use `tools/buddyctl.py ble status`, `ble set`, and `ble prompt --wait-decision`
after the one-time OS pairing step to exercise the production BLE transport.

## Independent USB Device Verification

For device UI and button work, prefer the `ws-amoled164-usb-debug` build
through `firmware/esp32/tools/pio_ws.sh` and `tools/dev/device.py --usb-only`.
This debug-only image disables BLE at compile time, so the Mac app can stay
open. The runner retains the hardware lock and verifies `ping.usbOnly` before
scenarios. Use setup/restoration scripts and return to normal firmware after
tests. Never publish the debug image. See `tools/dev/README.md`.

Bluetooth integration uses normal firmware and one explicitly identified Mac
app instance. USB-only tests do not satisfy that gate. Do not add production
app lifecycle behavior merely to coordinate independent USB debugging.

## Webcam Motion Verification

Webcam verification is **explicit opt-in only**. Use the `webcam-verify` skill
at `skills/webcam-verify/SKILL.md` only when the user requests webcam verification
and confirms the physical setup for that session. Do not activate it for general
verification, animation changes, or merely because a camera/device is connected.
An earlier setup is not standing authorization for future sessions. Once a session
is set up, capture the requested bounded clips without re-asking per clip; stop
when it is complete. Regular tests and screenshots remain independent of webcam
setup. `make webcam-test` uses synthetic video and never opens a camera.

## Self-Diagnosis

Before relying on hooks, run `skills/doctor/doctor.sh` from the repo root (skill:
`doctor`). It checks config, the hook script, registration for the current
harness, the running app, auth, and a synthetic round trip, then arms a live
check: run `echo BOOP_DOCTOR_PING` as a tool call and `skills/doctor/doctor.sh
--confirm`. Exit 0 healthy, 1 broken, 2 armed. Do not launch the Boop app
yourself; ask the user to (an agent-launched Boop aborts on Bluetooth).

## Architecture Rules

- Keep `archived/app/Boop/Core/` pure. The reducer must not perform I/O, read clocks, read user defaults, call UI, or touch BLE.
- Model new behavior as `BuddyEvent` values and reducer transitions first.
- Add agent-specific parsing in `HookServer` or hook installer code, not in output code.
- Add displays by implementing `OutputProvider` and deriving everything from `BuddyState`.
- Preserve fail-open hook behavior. If Boop is down, agent hooks should exit successfully and let the agent's native flow continue.
- Approval continuations belong in `BuddyEngine`, not in `BuddyState`.
- Treat `RenderState` in `Outputs/ESP32/Heartbeat.swift` as the desktop-to-firmware wire contract.
- Keep Cursor auto-approval conservative. Shell commands with control characters must require manual review.
- Keep agent expression (MCP) inside the enforced sandbox: suppressed while any prompt is pending, enum-only vocabulary, byte-capped text, engine-side rate limits. Never award pet joy or memory for approval decisions. See `archived/research/eng/personality-and-embodiment.md`.

## Files To Know

| File | Role |
| --- | --- |
| `archived/app/Boop/Core/BuddyState.swift` | Public state projection and session models |
| `archived/app/Boop/Core/BuddyReducer.swift` | State transition authority |
| `archived/app/Boop/Core/BuddyEngine.swift` | Main orchestrator, outputs, approval continuations |
| `archived/app/Boop/Server/HookServer.swift` | HTTP input adapter and approval responses |
| `archived/app/Boop/Install/HookInstaller.swift` | Agent hook registration and generated bash script |
| `archived/app/Boop/Outputs/ESP32/Heartbeat.swift` | Hardware heartbeat mapper |
| `archived/app/Boop/Outputs/ESP32/BLEManager.swift` | BLE transport, inbound approvals, OTA acks |
| `archived/app/Boop/Views/PopoverView.swift` | Main user-visible UI |
| `archived/app/Boop/Core/PetMemory.swift` | Pet personality memory, effort/mood types, agent vocabulary |
| `archived/app/Boop/Server/MCPServer.swift` | Agent-embodiment MCP input adapter (express/say/introduce/report_effort) |

## Specs Stay In Sync

`plan/` is the spec and the code is its implementation; they must not
drift. Any change that alters behavior, a wire contract, a budget, a UX
flow, or a verification step updates the matching document in the same
commit: `plan/UX-*.md` for what the person sees, `plan/WIRE-V2.md` and
`firmware/esp32/PROTOCOL.md` for the wire, `plan/ARCHITECTURE.md` for
structure and budgets, `plan/VERIFICATION.md` for how it is checked, and
`plan/PLAN.md` for phase status. If a change deliberately departs from the
spec, change the spec first and say why in it. Reviewers read the spec
diff next to the code diff.

## Documentation Expectations

- `plan/` is the direction. When code and these docs disagree, the docs
  describe the target and `plan/PLAN.md` says which phase closes the gap.
- `archived/research/` holds the earlier product, marketing, hardware, and
  source-derived engineering docs. Read it for history and for the still
  valid command references in `archived/research/eng/TESTING.md` and
  `RELEASE.md`; do not extend it. Commands in archived docs run from
  `archived/`.
- Keep `README.md` focused on overview and build/run/test instructions.
- Keep this file mirrored in `CLAUDE.md` and `AGENTS.md`.
