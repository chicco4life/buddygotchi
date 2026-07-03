# Production Readiness Plan

Last updated: 2026-07-03

The prior five-gap implementation plan is complete. Buddygotchi now has review cards, current activity, entries, activity classification, error/thinking states, multi-session summaries, ESP32 prompt metadata, and the associated reducer/integration coverage.

This file now tracks the remaining production-readiness work. Detailed architecture lives in `ARCHITECTURE.md`; day-to-day commands live in `README.md`.

## Done

- Native Swift menu bar app is the active runtime.
- Claude Code, Cursor, and Codex hook installers exist.
- Hooks fail open when the app is unavailable.
- Local approval mode can block and resolve tool calls from the popover or ESP32 buttons.
- Core state is reducer-driven and covered by XCTest.
- ESP32 heartbeat includes prompt details, entries, completion summary, activity kind, and session summaries.
- Thinking and error states are distinct.
- E2E HTTP smoke scripts exist for all three agents.

## Remaining Production Work

1. Package and sign a real `.app` bundle.
2. Verify Launch at Login through the packaged app, not `swift run`.
3. Choose a stable install location for hook helper binaries so Cursor hooks survive rebuilds.
4. Host the firmware manifest and release binaries for OTA updates.
5. Add notarization and release automation.
6. Run the HTTP e2e suite against a packaged build on a clean macOS user profile.
7. Run a hardware QA pass with a real M5StickC Plus 2 after each firmware wire-format change.
8. Decide whether the legacy Bun daemon under `src/src/` should be archived harder or removed.

## Release Checklist

- `make build`
- `make test`
- `make e2e` with the app running outside the sandbox
- Snapshot harness for core popover states
- Manual hook install/uninstall for Claude Code, Cursor, and Codex
- Manual local approval allow/deny for each agent
- Manual fail-open check with app stopped
- Manual ESP32 pair, heartbeat, approve/deny, unpair
- Firmware OTA check against the hosted manifest
