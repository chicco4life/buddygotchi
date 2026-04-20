# Buddygotchi — Source

Local daemon + web UI that lets you approve or deny Cursor / Claude Code
tool calls from a browser tab on your Mac (or a phone on the same Wi-Fi),
via a `PreToolUse` hook. No BLE, no hardware.

## What it does

1. A `PreToolUse` hook in Cursor (and/or Claude Code) fires on tool calls
   matching a pattern.
2. The hook runs `buddygotchi hook --format <agent>`, which POSTs
   the tool + context to the local daemon and blocks on the response.
3. The daemon pushes a permission card to every paired web client over
   WebSocket.
4. You tap **approve** or **deny** in the browser.
5. The daemon answers the blocked HTTP request; the hook writes the
   decision back to the agent; the tool call proceeds (or not).

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
      │ spawn hook script
      ▼
buddygotchi hook --format [cursor|claude-code]
      │ HTTP POST /hook/<agent>
      ▼
daemon (input adapter: src/inputs/)
      │   normalizes payload → engine event
      ▼
reducer (pure, schema/state.ts)
      │   version bump
      ▼
WebSocket broadcast to all paired clients
      │
      ▼
outputs/web/client/  (browser on Mac / phone)
      │   user taps approve/deny
      ▼
WebSocket "decide" message
      │
      ▼
engine resolves pending HTTP request
      │
      ▼
hook script writes agent-specific JSON to stdout
```

Boundaries (frozen contracts in `schema/`):

- **state.ts** — `BuddyState`, the single shape rendered by the UI.
- **ws-protocol.ts** — daemon ⇄ web client messages.
- **errors.ts** — closed set of error codes.

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

See **[`GETTING_STARTED.md`](../GETTING_STARTED.md)** in the repo root for full setup
instructions, including how to connect Cursor, Claude Code, and Codex.

```bash
# install dependencies
bun install

# start the daemon (prints pairing code + URLs)
bun run dev

# open the web UI
open http://localhost:8080/
```

## Running tests

```bash
bun test
```

## Layout

```
src/
  schema/             TS source of truth for wire contracts (state, ws, errors)
  src/
    cli/              CLI entry: daemon, hook, install, version
    core/             Engine, reducer, state, config
    inputs/           Input adapters (Cursor, Claude Code, Codex)
    outputs/          Output providers (Web + WebSocket + pairing)
  outputs/
    web/client/       Static web client (HTML/CSS/JS)
    esp32/            ESP32 hardware buddy (firmware, tools, characters, docs)
    mobile/           Placeholder for native app output
  archive/            BLE probe + experiments (see archive/README.md)
  tests/              Bun test suites
```

## Ports

| Port | Role                                                              |
| ---- | ----------------------------------------------------------------- |
| 8080 | HTTP `/`, `/healthz`, WebSocket `/ws`, `/hook/cursor`, `/hook/claude-code` |
