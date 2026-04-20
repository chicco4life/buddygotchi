# Mobile Buddy — 0→1 Dev Plan

Living document. Single source of truth for phasing, contracts, and
decisions. Updated as phases complete.

## ⚠️  Pivot (2026-04): hooks replace BLE upstream

Original plan (Phases 0–2) had the Mac impersonate the ESP32 buddy over
BLE so Claude desktop would talk to us as if we were the hardware. We
hit a **macOS same-host blind spot**: a `CBCentralManager` in Claude
desktop cannot reliably discover a `CBPeripheralManager` running in the
same process or even the same Mac (external phones saw it fine).

The replacement is simpler and strictly better for the target use case
(gating agent tool calls): we use **Cursor + Claude Code `PreToolUse`
hooks**. A hook script POSTs to the daemon's new `/hook/request`
endpoint; the daemon renders the prompt on any paired client; the
client's decision flows back as the HTTP response. All of the schemas
(state, ws-protocol, errors), the reducer, the WS server, pairing, and
the web UI stay identical. Only the "upstream" module swapped from BLE
to `HookUpstream`.

BLE work is archived under `archive/`; resurrectable if we ever add
external peripheral hardware (Pi / ESP32 / old Android).

## Goal

Approve/deny Cursor + Claude Code agent tool calls from a browser tab
(same Mac or phone on the same Wi-Fi). The Mac hosts a tiny local
HTTP+WebSocket server; the agent's hook script is the upstream.

```
 Cursor / Claude Code
        │ PreToolUse JSON stdin
        ▼
 buddy-approval.py
        │ POST /hook/request (blocks)
        ▼
 buddy-daemon (HookUpstream)
        │
 reducer ↔ WebSocket /ws ↔ web UI on Mac or phone
```

## Decisions (locked)

| # | Decision                                       | Chosen                             |
| - | ---------------------------------------------- | ---------------------------------- |
| 1 | BLE peripheral library                         | Python + [`bless`](https://github.com/kevincar/bless) |
| 2 | Pairing between phone and daemon               | 6-char code from day one, bearer token after |
| 3 | Phone frontend stack                           | Vanilla TypeScript + HTML + CSS (PWA-lite) |
| 4 | Menu-bar companion app                         | Omitted for MVP                    |
| 5 | `turn` event handling                          | Omitted (drop on parse)            |

## Invariants enforced by the daemon

1. `BuddyState.version` is monotonic, +1 per change.
2. A client `decide` for a stale `promptId` is rejected (`E_PROMPT_ID_MISMATCH`) and never forwarded upstream.
3. Multi-client race on one prompt: first upstream write wins; losers get `E_ALREADY_DECIDED`.
4. Desktop disconnect while a prompt is pending → state keeps the prompt, decisions rejected with `E_DESKTOP_DISCONNECTED`. The daemon never fabricates a decision.
5. Unknown desktop `{cmd:...}` gets `{ack:<cmd>, ok:false, error:"unsupported"}`. `char_begin` is intentionally not acked (we don't accept folder push in MVP).
6. BLE side effects happen in a thin outer bridge, keyed off reducer version bumps — the reducer itself is pure.

## Contracts (schema/)

| Boundary                | File                   | Frozen by           |
| ----------------------- | ---------------------- | ------------------- |
| [A] Claude desktop ↔ daemon | `schema/ble-upstream.ts` | `../REFERENCE.md` (NUS wire) |
| [B] daemon ↔ web client     | `schema/ws-protocol.ts`  | This project        |
| UI rendering            | `schema/state.ts`      | This project — `BuddyState` shape |
| Error codes             | `schema/errors.ts`     | This project — closed literal set |

Python mirrors (dataclasses) live in `daemon/buddy_daemon/state.py`,
`protocol.py`, `errors.py`. Tests assert they stay in sync.

## Phases

### Phase 0 — Contracts [DONE]

- TS schemas above
- JSONL scenario fixtures (`fixtures/scenarios/*.jsonl`) covering idle, attention, approval race, mid-prompt disconnect
- `src/README.md` + `schema/README.md`

**Exit criteria:** schemas compile under `tsc --noEmit`, fixtures replay-able.

### Phase 1 — Daemon + harness on a fake upstream [DONE]

- `buddy_daemon` Python package:
  - `protocol.py` (NUS parse/serialize, `LineBuffer`)
  - `state.py` (`BuddyState`, pure `reduce(state, event) -> state`)
  - `events.py`, `errors.py`, `pairing.py`, `config.py`
  - `upstream.py` — `Upstream` Protocol + `FakeTcpUpstream` (loopback)
  - `ws_server.py` + `bridge.py` — wires parser ↔ reducer ↔ WS
  - `main.py` — entry point, prints pairing code
- `harness/fake_desktop.py`, `harness/fake_client.py`
- `pytest` suite covering parser, reducer, and bridge end-to-end

**Exit criteria (all met):**
- 37 / 37 pytest green
- Smoke test: fake desktop → daemon → fake client "approve" → daemon emits `{"cmd":"permission","id":"req_abc123","decision":"once"}\n` upstream, byte-exact.

### Phase 2 — Real BLE peripheral [IN PROGRESS]

**Critical proof the entire project hinges on:** can this Mac, running
`bless`, advertise the Nordic UART Service such that Claude desktop
(Developer → Open Hardware Buddy…) finds us, connects, and starts
sending heartbeats?

If that fails, nothing above it matters. So Phase 2 is split deliberately:

#### 2.a — Standalone BLE probe (no daemon, no state)

`harness/ble_probe.py` — minimal script that only:
- advertises device name `Claude-Buddy-Mac` + NUS service UUID
- publishes RX (write) + TX (notify) characteristics with NUS UUIDs
- logs every GATT operation (subscribe, write, MTU, disconnect)
- replays `fixtures/scenarios/attention.jsonl` as TX notifications
  once a central subscribes

Goal: verify, with one script and one Mac, that **Claude desktop's
device picker sees us and we can exchange bytes**. No reducer, no
WebSocket, no phones.

#### 2.b — `BleUpstream` class

Only if 2.a works. Wraps `bless` behind the existing `Upstream`
Protocol (`recv_line()`, `send_line()`, `disconnect_event`). Swap in
place of `FakeTcpUpstream` in `main.py`. Phase 1's 37 tests keep
passing because the abstraction boundary didn't move.

#### 2.c — Encryption (conditional)

REFERENCE.md recommends LE Secure Connections + passkey bonding but
explicitly notes Claude desktop connects fine without it. macOS
CoreBluetooth peripheral API (what `bless` uses) does **not** expose
SC passkey entry, so the MVP ships unencrypted and reports
`status.data.sec = false`. If/when we move to native (Swift
CBPeripheralManager + IOBluetooth) or a Linux box running BlueZ, add
SC bonding. Tracked as a security item for Phase 4, not a blocker.

**Exit criteria:**
- Claude desktop (on this Mac, Developer Mode on) lists our device in the pairing window.
- Clicking Connect establishes a GATT connection.
- Our probe receives the desktop's `{"time":[...]}` one-shot and at least one heartbeat snapshot.
- `BleUpstream` drop-in keeps every Phase 1 test green.

### Phase 3 — Vanilla-TS web UI

- `web/` — TypeScript/HTML/CSS, no framework. Vite or tsc watch.
- Renders `BuddyState` from `snapshot`/`patch` messages.
- Pixel-art look ported from the firmware's `TFT_eSprite` assets where possible (the pet GIFs already live in `data/chars/` — load via a tiny asset server).
- First-time pairing screen: input 6-char code → `hello` → stores token in `localStorage`.
- Approve / Deny buttons wired to the `decide` message.
- Service worker + manifest → installable PWA, served by daemon on `:8080/`.

**Exit criteria:** iPhone on same Wi-Fi, "Add to Home Screen", tap notification (or open app), approve a real Claude Code prompt, see approval reflected in the desktop.

### Phase 4 — Hardening

- Reconnect logic: BLE drop → advertise again, WS drops → reconnect with backoff.
- Timeouts surfaced in UI (`E_DESKTOP_DISCONNECTED`, stale heartbeat).
- Error UX and logs.
- LE Secure Connections bonding (may require native component; see 2.c).
- Automatic daemon startup (launchd plist).

### Phase 5 — Deferred

- Native iOS/Android wrapping (Capacitor or WKWebView) if PWA is not enough.
- Remote-away-from-Wi-Fi relay (the original "BLE-to-internet router" idea). Feasible via Cloudflare Tunnel or Tailscale over the daemon's WS, but out of MVP scope.

## File layout

```
src/
  PLAN.md                 this document
  README.md               run/test instructions
  schema/                 TS source of truth
    ble-upstream.ts
    ws-protocol.ts
    state.ts
    errors.ts
  fixtures/
    scenarios/*.jsonl     replayable desktop scripts
  daemon/                 Python 3.11+
    pyproject.toml
    buddy_daemon/         package
    tests/                pytest
  harness/
    fake_desktop.py       Phase 1: TCP replay into FakeTcpUpstream
    fake_client.py        Phase 1: WS client + decide
    ble_probe.py          Phase 2.a: standalone BLE peripheral probe
  web/                    Phase 3
```

## Ports (dev defaults)

| Port | Role                                         |
| ---- | -------------------------------------------- |
| 8080 | Daemon HTTP + WebSocket (`/ws`, `/healthz`)  |
| 8765 | `FakeTcpUpstream` loopback (Phase 1 only; removed when `BleUpstream` ships) |

## Known gotchas encountered

- **Python 3.13 + macOS extended attrs** break editable-install `.pth` files (`Skipping hidden .pth file`). Workaround: `PYTHONPATH=mobile-mvp/daemon` when running the daemon until we switch the install off editable mode.
- **macOS Bluetooth permission:** any terminal emulator running `bless` needs to be granted "Bluetooth" in System Settings → Privacy & Security. First run triggers the prompt; the process will appear to hang otherwise.
- **macOS CoreBluetooth peripheral** does not expose SC passkey entry. See 2.c above.
