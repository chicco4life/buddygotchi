# Design: Agent-Driven Hardware-in-the-Loop Testing for the ESP32 Buddy

Status: design proposal (not yet implemented)
Last updated: 2026-07-03

## Goal

Let a Claude/Codex agent autonomously flash, drive, observe, and verify the
**real** M5StickC Plus 2 over its actual transports — no camera, no simulator,
no human in the loop (except a one-time BLE pairing per device). The agent
must be able to answer, programmatically:

- What firmware is running right now?
- What is the device's internal state?
- What is literally on the screen?
- What happens when a button is pressed?
- Does the production BLE path (heartbeat in, permission decision out) work?

## Current state, verified against a live device (2026-07-03)

The existing tools in `tools/` were exercised against a plugged-in device
(`/dev/cu.usbserial-*`). Happy-path results:

- `screenshot.py` works: captured a valid 135×240 PNG of the sleeping buddy.
- `button.py --mock a` works: armed a fake prompt, injected a press, saw
  `{"cmd":"permission","id":"DEBUG","decision":"allow"}` echoed back.
- Full loop works: injecting heartbeat JSON over USB serial switched the
  device to attention state with "APPROVE? Bash / npm test" rendered, and a
  follow-up screenshot captured it.

So the primitives are sound. The problems are structural:

1. **Fragile screenshot framing.** The base64 body is cleaned by stripping
   non-base64 characters — but firmware log lines (e.g. `[ble] passkey
   123456`, and everything `CORE_DEBUG_LEVEL=5` emits from other tasks) are
   composed almost entirely of base64-alphabet characters. Any log line
   interleaved mid-frame silently corrupts the image or hard-fails on length
   mismatch. Works when the device is quiet; flaky whenever BLE is active.
2. **No integrity check.** No CRC/length in the frame trailer, so corruption
   is detected only by luck (length mismatch) and there is no retry.
3. **`btn` bypasses the real button path.** The serial `btn` command calls
   `sendApproval()` directly, skipping `handleApprovalButtons()` — the GPIO
   edge detection (A fires on release, B on press) is never exercised.
4. **No semantic state introspection.** The only observation channel is
   pixels. Agents can read the PNG with vision, but asserting "waiting == 1
   and promptId == req_X" from an 8px font is error-prone. There is no
   `state` dump to use as ground truth.
5. **No version/identity probe.** Tools guess "is the new firmware flashed?"
   from timeouts. There is no `ping` returning firmware version/git SHA.
6. **Port handling is duplicated and unmanaged.** Each script reopens the
   port with copy-pasted termios code, pays a fixed 2 s settle, and nothing
   prevents two tools (or two agent turns) from fighting over the port.
7. **The production transport is untested.** Everything runs over USB serial;
   the Mac app talks BLE NUS. The BLE receive path (`_btLine`, MTU-fragment
   reassembly, permission notify, time sync, status acks) has zero tooling.
8. **Inconsistent dependencies.** Some scripts are pure stdlib, others
   silently require pyserial.

## Design overview

Three layers, each independently useful:

```
Layer 3   pytest HIL suite + agent docs        (tests/hil/, CLAUDE.md section)
Layer 2   buddyctl — one host CLI, JSON out    (tools/buddyctl.py)
Layer 1   firmware debug surface               (serial commands in main.cpp)
                    │ USB serial                │ BLE NUS (bleak)
                    ▼                           ▼
              ┌─────────────────────────────────────┐
              │        real M5StickC Plus 2         │
              └─────────────────────────────────────┘
```

Principle: **observe semantically, verify visually.** The `state` dump is
ground truth for assertions; screenshots verify that rendering matches, read
by agent vision (verified legible today) or by coarse pixel checks in CI.

## Layer 1: Firmware debug surface

All additions live in `handleSerialCommand()` (USB serial only, same channel
as today). Sentinel-framed one-line responses so hosts can parse them out of
log noise. Estimated footprint: tiny (a few hundred bytes each).

### `ping`

```
<<PONG {"fw":"0.1.0","git":"a1b2c3d","up":123456,"heap":84200}>>
```

Git SHA injected at build time via a platformio `extra_scripts` hook
(`-DGIT_SHA=\"...\"`). This kills the "is the new firmware flashed?"
guessing everywhere: `flash → ping → assert sha changed`.

### `state`

One-line JSON dump of everything the firmware knows:

```
<<STATE {"pet":"attention","species":"cat","desktop":"connected",
"connected":true,"total":2,"running":1,"waiting":1,"msg":"approve: Bash",
"promptId":"req_x","promptTool":"Bash","promptHint":"npm test",
"promptApproval":true,"responseSent":false,"persona":"P_ATTENTION",
"screen":"buddy","rot":0,"mode":"live","rtcValid":true,"nLines":3}>>
```

`screen` is which top-level screen the loop is drawing (`buddy` / `passkey` /
`ota`) — essential for interpreting screenshots. `mode` is demo/live/asleep
from `data.h`. This is the primary assertion surface for tests.

### `press a|b [ms]` — real-path button injection

Unlike `btn` (which calls `sendApproval()` directly), `press` injects at the
GPIO-read layer so the actual edge-detection logic runs:

- Wrap the raw reads in `handleApprovalButtons()`:
  `bool readBtn(int pin)` returns `digitalRead(pin)` AND-ed/OR-ed with a
  synthetic override (active-low, so a synthetic press forces LOW).
- `press a 150` schedules: LOW now, HIGH at now+150 ms. The loop's edge
  detector then observes the same press→release sequence a finger produces,
  including A-fires-on-release vs B-fires-on-press semantics.
- Emits `<<PRESS a down>>` / `<<PRESS a up>>` breadcrumbs.

Keep `btn` as the fast high-level injection; `press` is the fidelity path.
If future firmware adds navigation/long-press behaviors (per the product
plan: hold-to-sleep, page cycling), they are automatically testable because
injection happens below the semantics.

### Screenshot v2 (fix, not redesign)

Keep the RGB565/base64 row streaming — it works — and fix the reliability:

- Trailer becomes `<<SCR_END LEN=64800 CRC32=deadbeef>>` (CRC over raw
  RGB565 bytes). Host verifies and retries on mismatch.
- Quiesce logs during the dump: `esp_log_level_set("*", ESP_LOG_NONE)` on
  entry, restore on exit. Removes the interleaving corruption class from
  framework logs. (Our own `Serial.printf` calls are already synchronous
  with the dump.)
- Optional `screenshot 2` arg: 2× nearest-neighbor upscale on the *host*
  side, not firmware — small screens read better through agent vision when
  upscaled. Host-side flag only; noted here for the contract.

### `reboot`

Clean `esp_restart()` with an ack, so tests can verify cold-boot behavior
(boot screen, NVS-persisted settings) without USB power-cycling hardware.

### Explicitly not building

- **A "draw journal" / text-extraction command.** Nearly all on-screen text
  derives from `TamaState`, which `state` already exposes. Vision on the
  screenshot covers layout. Revisit only if firmware grows text the state
  doesn't capture.
- **A BLE-side debug command channel.** Debug stays on USB; BLE stays
  production-shaped. The BLE test client (below) speaks only the real
  protocol, which is the point.

## Layer 2: `buddyctl` — one host CLI

Replaces `screenshot.py`, `button.py`, `test_serial.py` with a single entry
point: `tools/buddyctl.py`. Depends on `pyserial` + `bleak` (declared via
PEP 723 inline metadata so `uv run buddyctl.py` just works; agents don't
manage venvs).

Conventions for every subcommand:

- `--json` flag → machine-readable stdout, one JSON object.
- Exit code 0 = verified success, 1 = device said no, 2 = transport failure.
- Port auto-detect (same globs as today), `--port` override.
- **Lockfile** (`flock` on `/tmp/buddyctl-<port>.lock`) so concurrent
  invocations queue instead of corrupting each other's reads.
- Open the port without touching DTR/RTS (some adapters reset the ESP32 on
  DTR toggling — `platformio.ini` already sets `monitor_dtr = 0` for this
  reason). Settle time drops from a fixed 2 s to "drain until quiet or
  200 ms", since `ping` gives us a positive liveness check.

### USB subcommands

| Command | Does | Verifies |
|---|---|---|
| `buddyctl ping` | ping | firmware version/SHA/uptime |
| `buddyctl state` | state dump | ground-truth assertions |
| `buddyctl screenshot [--out f.png] [--scale 2] [--retry 3]` | capture + CRC check | what's rendered |
| `buddyctl press a\|b [--ms 150]` | GPIO-layer press | real button path |
| `buddyctl btn a\|b [--mock]` | legacy direct injection | approval wire format |
| `buddyctl inject '<json>'` | raw heartbeat line | state parsing |
| `buddyctl set --pet attention --waiting 1 --prompt-tool Bash ...` | convenience flags → heartbeat JSON | common scenarios without hand-writing JSON |
| `buddyctl expect --pet attention --waiting 1 [--timeout 5]` | poll `state` until predicates match | async state transitions |
| `buddyctl monitor [--secs N \| --until regex]` | stream serial log | boot sequences, async events |
| `buddyctl flash [--env m5stickc-plus]` | `pio run -t upload`, reopen, `ping`, assert SHA changed | flash actually landed |
| `buddyctl reboot` | reboot + wait for boot banner | cold-boot behavior |

`expect` is the agent's bread and butter: it converts "wait and see" into a
deterministic, exit-code-checkable step.

### BLE subcommands (the production transport)

Built on `bleak` (CoreBluetooth-backed on macOS), speaking the real NUS
protocol from `REFERENCE.md` — the same bytes the Mac app sends:

| Command | Does |
|---|---|
| `buddyctl ble scan` | list advertising buddies |
| `buddyctl ble pair` | connect, trigger bonding; scrapes the passkey off USB serial (`[ble] passkey NNNNNN`) and prints it for the human/agent to type into the macOS dialog — **one-time per device**, bond persists |
| `buddyctl ble send '<json>'` / `ble set --pet ... ` | heartbeat over BLE |
| `buddyctl ble listen [--until regex] [--secs N]` | collect device→host notifies |
| `buddyctl ble prompt --id req_x --tool Bash --hint 'npm test' --wait-decision` | send a real approval prompt, block until a `{"cmd":"permission",...}` decision arrives |
| `buddyctl ble status` | `{"cmd":"status"}` round-trip, assert ack schema |
| `buddyctl ble timesync` | time sync + verify via `state` (`rtcValid`) |

This finally covers `_btLine` reassembly, MTU fragmentation, the notify path
for decisions, and the command/ack protocol. Note the firmware requires LE
Secure Connections bonding (`ESP_LE_AUTH_REQ_SC_MITM_BOND`) — that's why
pairing is a one-time manual step; do **not** add a firmware backdoor to
disable security for tests.

### The hero test (full production approval loop, no fingers)

```
buddyctl ble prompt --id req_1 --tool Bash --hint "npm test" &   # BLE in
buddyctl expect --pet attention --prompt-id req_1                # state truth
buddyctl screenshot --out approve.png                            # visual truth
buddyctl press a --ms 150                                        # real button path
# `ble prompt --wait-decision` unblocks with decision=allow, id=req_1 → exit 0
```

Every hop of production except the finger and the Mac app is the real thing:
real radio, real parse, real render, real GPIO edge logic, real wire format
back.

## Layer 3: pytest HIL suite + agent ergonomics

### `tests/hil/` (pytest)

- Session-scoped fixture owns the serial port once (one open, one settle,
  one `ping` gate) — individual tests don't churn the port.
- Skips cleanly (`pytest.skip`) when no device is attached, so the suite is
  safe to wire into `make test` paths without hardware.
- Core cases:
  - `test_ping_reports_build` — SHA matches local `git rev-parse`.
  - `test_default_state_is_sleep` — no data → disconnected/sleep.
  - `test_heartbeat_states` — inject each pet state, assert `state` echoes
    it and `persona` derivation matches `derive()`'s table.
  - `test_approval_usb` — mockprompt → press a → decision JSON, and
    press-with-no-prompt → noop.
  - `test_button_edges` — A decides on release, B on press (only provable
    via `press`, not `btn`).
  - `test_screenshot_integrity` — CRC valid; prompt region contains non-
    background pixels when a prompt is armed vs not (coarse pixel checks,
    not golden images — golden PNGs are brittle across palettes/species).
  - `test_connection_timeout` — inject, wait >30 s, state returns to sleep
    (marked `slow`).
  - `@pytest.mark.ble` set: paired-device required — heartbeat over BLE,
    hero approval loop, status ack schema, time sync.
- Entry point: `make hil` / `make hil-ble` from the repo root.

### Agent ergonomics

- Add a short "Verifying firmware on the real device" section to `CLAUDE.md`
  (mirrored per repo policy): flash → `ping` → `set`/`ble set` →
  `expect` → `screenshot` → read the PNG. With that, any agent session knows
  the workflow without re-deriving it.
- All `buddyctl` output is designed to be quoted directly into a test report:
  one line, one JSON object, stable keys.

## Phasing

1. **Foundation (small, do first):** `ping`/`state`/`press` in firmware;
   `buddyctl` skeleton with lockfile, `ping/state/press/inject/set/expect/
   screenshot(v1)/btn`. Retire the old scripts.
2. **Reliability:** screenshot CRC + log quiescing + retry; `flash`,
   `reboot`, `monitor`; pytest USB suite; `make hil`.
3. **Production transport:** `ble` subcommands via bleak; one-time pairing
   flow; `@ble` pytest set; hero approval test.
4. **Full stack (optional):** drive the Mac app end-to-end — reuse
   `app/tools/e2e/` to POST `/hook/approve`, let the real `BLEManager` send
   the heartbeat, verify on-device, press, confirm the hook unblocks. This
   automates the "Manual ESP32 pair, heartbeat, approve/deny" line of the
   release checklist.

## Risks and constraints

- **Single port owner.** `pio monitor`, a stray `screen`, or the flasher can
  hold the port; `buddyctl` should name the holder (`lsof`) in its error.
- **DTR/RTS resets.** Current adapter/driver combo doesn't reset on open
  (verified live), but other cables/adapters may. If flakiness appears, the
  escape hatch is a `buddyctl serve` daemon that holds the port once and
  multiplexes over a unix socket — deliberately deferred, not built.
- **BLE bonding is stateful.** Tests must tolerate a pre-bonded device;
  `{"cmd":"unpair"}` + macOS Bluetooth forget resets the world.
- **Production-run leverage.** `state` + `press` + `screenshot` are exactly
  the self-test primitives the 100-unit production checklist needs
  (research/archived/product/PRODUCT.md §7.4–7.5); design them as the same commands,
  not parallel ones.
