# Mobile Buddy MVP

Local daemon + web UI that lets you approve or deny Cursor / Claude Code
tool calls from a browser tab on your Mac (or a phone on the same Wi-Fi),
via a `PreToolUse` hook. No BLE, no hardware.

## What it does

1. A `PreToolUse` hook in Cursor (and/or Claude Code) fires on tool calls
   matching a pattern.
2. The hook shell-runs `mobile-mvp/hooks/buddy-approval.py`, which POSTs
   the tool + command to the local daemon at `http://127.0.0.1:8080/hook/request`
   and blocks on the response.
3. The daemon pushes a permission card to every paired web client over
   WebSocket.
4. You tap **approve** or **deny** in the browser.
5. The daemon answers the blocked HTTP request; the hook writes the
   decision back to Cursor / Claude Code; the tool call proceeds (or not).

Fail-open: if the daemon is down or nobody responds in time, the hook
returns `ask` and the agent's native permission UI handles it.

## Why this architecture

The original plan was to impersonate the ESP32 Claude Buddy over BLE.
After Phase 2.a (see `archive/`) we hit a macOS "same-host blind spot"
where a `CBCentralManager` in Claude desktop cannot see a
`CBPeripheralManager` advertising from the same Mac. External phones
saw it fine, but Claude desktop did not.

Hooks are an official first-class extension point on both Cursor and
Claude Code, don't depend on OS Bluetooth quirks, and cover the actual
use case (gating agent tool calls) directly. The daemon, protocol,
state model, pairing, and web UI all stayed the same — only the
"upstream" module swapped out.

The BLE path is still viable if we ever want physical hardware buddies;
all that code lives under `archive/` now.

## Architecture

```
Cursor / Claude Code
      │ PreToolUse event
      ▼
.cursor/hooks.json   OR   ~/.claude/settings.json
      │ spawn script
      ▼
mobile-mvp/hooks/buddy-approval.py
      │ HTTP POST /hook/request
      ▼
buddy-daemon (HookUpstream)
      │   synthesizes a heartbeat carrying the prompt
      ▼
reducer (pure, schema/state.ts)
      │   version bump
      ▼
WebSocket broadcast to all paired clients
      │
      ▼
mobile-mvp/web/  (browser on Mac / phone)
      │   user taps approve/deny
      ▼
WebSocket "decide" message
      │
      ▼
bridge.handle_decide → HookUpstream resolves pending HTTP
      │
      ▼
hook script writes agent-specific JSON to stdout
```

Boundaries (frozen contracts in `schema/`):

- **state.ts** — `BuddyState`, the single shape rendered by the UI.
- **ws-protocol.ts** — daemon ⇄ web client messages.
- **errors.ts** — closed set of error codes.

There is no separate upstream schema for hooks: `buddy-approval.py`
normalizes Cursor / Claude-Code payloads into
`{tool, hint, timeout_s}` before POSTing.

## Invariants the daemon enforces

1. `BuddyState.version` is monotonic, increases by exactly 1 per change.
2. Exactly one of `snapshot` or `patch` is in flight per version on each WS.
3. A `decide` for a stale `promptId` is rejected (`E_PROMPT_ID_MISMATCH`);
   never returned to the hook caller.
4. Multi-client race on the same prompt: first decision wins; losers get
   `E_ALREADY_DECIDED`.
5. Hook timeout fail-open: if no client decides within `timeout_s`, the
   HTTP response is `{decision: "ask"}` so the host's native UI kicks in.
6. The daemon never fabricates a decision; it only relays client input.

## Pairing

Daemon prints a 6-character pairing code to stdout on boot. The web UI
prompts for it the first time you open it. After one successful pair per
`clientId`, the daemon stores a bearer token; the browser sends that
token on subsequent connects. Codes expire after 24 hours by default
(configurable via `BUDDY_PAIRING_TTL_S`).

## Quick start

```bash
# one-time setup
cd mobile-mvp/daemon
pip install -e ".[dev]"
cd ../..

# run the daemon (prints a pairing code + URLs)
PYTHONPATH=mobile-mvp/daemon python -m buddy_daemon

# in a browser on the same machine
open http://127.0.0.1:8080/

# (or from your phone on the same Wi-Fi)
# open http://<mac-lan-ip>:8080/
```

Then trigger a hook from a Cursor chat (with `.cursor/hooks.json`
registered) by running any shell command containing the matcher string
(default `HOOK_TEST`). You'll see an approval card pop up in the
browser; tap it; the command runs.

### Broadening the matcher

Once the flow works, widen `.cursor/hooks.json` to match whatever you
want gated (e.g. `curl|wget|git push|rm ` via JS regex). Keep `failClosed`
= `false` so daemon crashes don't brick Cursor.

### Claude Code

`~/.claude/settings.json` registers the same script with
`--format claude-code`. It applies to any `claude` CLI session.

## Running tests

```bash
cd mobile-mvp/daemon
pytest -q
```

## Layout

```
mobile-mvp/
  schema/             TS source of truth for wire contracts (state, ws, errors)
  daemon/             Python 3.11+ package
    buddy_daemon/
      hook_upstream.py   HTTP /hook/request → WS broadcast → decision
      bridge.py          reducer ↔ upstream ↔ WS
      state.py           pure reducer
      protocol.py        JSON line parser (heartbeat / permission)
      ws_server.py       aiohttp app: /ws, /hook/request, static web
      ...
  hooks/
    buddy-approval.py    universal PreToolUse hook (--format cursor|claude-code)
  web/
    index.html  app.css  app.js
  harness/
    fake_client.py       headless WS client (supports --auto approve/deny)
  archive/               BLE probe + fake TCP upstream (see archive/README.md)
```

## Ports

| Port | Role                                                |
| ---- | --------------------------------------------------- |
| 8080 | HTTP `/`, `/healthz`, WebSocket `/ws`, `/hook/request` |

## Pushing to your own GitHub remote

Your `origin` may still point at [anthropics/claude-desktop-buddy](https://github.com/anthropics/claude-desktop-buddy).
Create a new empty repo under your account, then from the **repository root**:

```bash
git remote rename origin upstream   # optional: keep upstream for pulls
git remote add origin https://github.com/<you>/<your-repo>.git
git push -u origin main
```

Project hooks use `python3 mobile-mvp/hooks/buddy-approval.py` relative to the
repo root; open this folder as the Cursor workspace so that path resolves.
