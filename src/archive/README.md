# Archived work

These modules were part of the original plan to have Claude desktop
talk to the daemon over the **BLE Nordic UART Service** (same wire as
the ESP32 hardware buddy), and to simulate that pipe via a local TCP
socket during development.

## Why this is archived

We pivoted to **PreToolUse hooks** (Cursor + Claude Code) for the MVP.
Hooks are solicited by the agent at the moment a permission decision
is needed; the hook script forwards to the daemon over HTTP and
receives the decision back synchronously. No BLE, no Claude-desktop
upstream at all. See `../PLAN.md` for details.

The BLE path remains viable when paired with **external peripheral
hardware** (a Raspberry Pi, ESP32, or a second Android device running
as the BLE peripheral) because macOS has a "same-host blind spot" that
prevents Claude desktop from discovering a BLE peripheral running in
the same process on the same Mac. If/when we revisit hardware-buddy
functionality, these files are the starting point.

## Contents

### `harness/ble_probe.py`

Standalone `bless`-based BLE peripheral that advertises the Nordic
UART Service UUID, captures `permission_request` heartbeats from a
connecting Claude desktop, and sends back `{cmd:"permission", ...}`
decisions via keyboard input. Worked at the BLE layer (external
phones could discover it and see the correct advertisement) but was
never discovered by Claude desktop on the same host due to macOS
CoreBluetooth limitations.

Requires a patch to `bless/backends/corebluetooth/peripheral_manager_delegate.py`
to initialize `_powered_on_event` before `CBPeripheralManager.alloc()`
to avoid a startup race condition.

### `harness/ble_scanner.py`

Diagnostic `bleak` central that scans for BLE advertisements. Used to
confirm whether the probe was advertising visibly (it was, to external
scanners).

### `harness/fake_desktop.py`

CLI harness that replayed JSONL scenario files to the daemon's
long-gone `FakeTcpUpstream` to simulate Claude desktop end-to-end
without BLE.

### `fixtures-scenarios/`

JSONL conversation scripts for `fake_desktop.py`:
attention prompts, approval races, disconnect mid-prompt, idle
patterns. Useful if we ever reintroduce a scripted-upstream fixture.

### `schema/ble-upstream.ts`

The TypeScript schema defining the exact BLE NUS wire protocol
(heartbeat + permission_request / permission, folder_push, ack). The
daemon's `protocol.py` still implements the heartbeat + permission
portion of this schema — because `HookUpstream` emits synthetic
heartbeats into the same reducer. If we need the schema for a new BLE
integration, resurrect this file.
