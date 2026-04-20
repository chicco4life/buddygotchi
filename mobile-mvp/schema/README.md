# Schema (source of truth)

TypeScript is the human-readable contract for all wire formats. The
Python daemon hand-ports these shapes in `daemon/buddy_daemon/protocol.py`,
`state.py`, and `ws_server.py`; the web client will `import` them
directly in Phase 3.

If you change a type here, you must also:

1. Update the matching Python class / validator in `daemon/`.
2. Add or amend a fixture in `fixtures/` demonstrating the new shape.
3. Bump `PROTOCOL_VERSION` in `ws-protocol.ts` if the change is not
   backwards-compatible with existing web clients.

Files:

- `ble-upstream.ts` — boundary [A], Claude desktop BLE NUS.
- `ws-protocol.ts`  — boundary [B], daemon ⇄ web client WebSocket.
- `state.ts`        — `BuddyState`, rendered by the web UI.
- `errors.ts`       — closed set of error codes.
