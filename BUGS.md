# Bug Register

Last updated: 2026-07-03

No confirmed open correctness bugs are tracked in this file right now.

The old bug-hunt list has been retired because its actionable findings were either fixed or moved into production-readiness tasks:

- ESP32 approval prompt metadata is now present in the heartbeat (`promptHint`, `promptSource`, `promptLabel` equivalent fields).
- ESP32 activity entries are now sent as `entries[]`.
- Codex hook docs now reflect `PermissionRequest`, `PreToolUse`, and `codex_hooks = true`.
- Claude Code docs now describe `Stop` as the completion signal.
- ESP32 approve/deny over BLE is documented in `ARCHITECTURE.md`.
- The unused `BuddygotchiHook` target has been removed.

Use this file only for confirmed defects with reproduction steps. Use `TODOs.md` for production-readiness tasks and `PLAN.md` for release sequencing.

## Template

```md
## B1. Short bug title

- Severity:
- Affected files:
- Reproduction:
- Expected:
- Actual:
- Notes:
```
