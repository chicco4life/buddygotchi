# Buddygotchi macOS App

A native macOS menu bar app that approves AI agent tool calls. Replaces the Bun daemon + browser UI with a single Swift app.

## Quick Start

```bash
cd app
swift build
swift run Buddygotchi
```

A menu bar icon appears. Click it to open the popover. On first launch, the setup wizard walks you through species selection, agent hook installation, and preferences.

## Testing

### Run tests

```bash
cd app
swift test
```

### Simulate a hook request

With the app running (`swift run Buddygotchi` in another terminal):

```bash
# Health check
curl http://127.0.0.1:8080/healthz
```

#### Pet states via signals

```bash
# Connect agent + start working (sleep → busy)
curl -X POST http://127.0.0.1:8080/hook/signal \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"claude-code","signal":"start_working"}'

# Keep working (stays busy)
curl -X POST http://127.0.0.1:8080/hook/signal \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"claude-code","signal":"keep_working"}'

# Stop working (busy → idle)
curl -X POST http://127.0.0.1:8080/hook/signal \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"claude-code","signal":"stop_working"}'

# Celebrate (idle → celebrate for 2s → idle)
curl -X POST http://127.0.0.1:8080/hook/signal \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"claude-code","signal":"celebrate"}'
```

#### Approval flow

```bash
# Send an approval request (hangs until you approve/deny in the popover)
# Pet goes to "attention" state
curl -X POST http://127.0.0.1:8080/hook/claude-code \
  -H 'Content-Type: application/json' \
  -d '{"tool":"Bash","hint":"rm -rf ./dist","source":"claude-code","timeout_s":30}'
```

#### Test via CLI binaries (same as Claude Code invokes)

```bash
# Simulate UserPromptSubmit signal (sleep → busy)
echo '{"hook_event_name":"UserPromptSubmit"}' \
  | .build/arm64-apple-macosx/debug/BuddygotchiSignal

# Simulate PostToolUse signal (keep_working)
echo '{"hook_event_name":"PostToolUse"}' \
  | .build/arm64-apple-macosx/debug/BuddygotchiSignal

# Simulate Stop signal (→ idle)
echo '{"hook_event_name":"Stop"}' \
  | .build/arm64-apple-macosx/debug/BuddygotchiSignal

# Simulate TaskCompleted signal (→ celebrate)
echo '{"hook_event_name":"TaskCompleted"}' \
  | .build/arm64-apple-macosx/debug/BuddygotchiSignal

# Simulate PreToolUse hook (hangs until approved in popover)
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"hook_event_name":"PreToolUse"}' \
  | .build/arm64-apple-macosx/debug/BuddygotchiHook --format claude-code
```

## Exiting

- **From the app**: Click the menu bar icon, then click "Quit" in the popover footer.
- **From the terminal**: Press Ctrl+C — the app handles SIGINT and cleans up the menu bar icon.

If the menu bar icon gets stuck (e.g. after a crash), hover your cursor over it and it will disappear.

## Reset Onboarding

To go through the setup wizard again:

```bash
defaults delete Buddygotchi setupCompleted
```

If running via `swift run` (no bundle ID), try:

```bash
defaults delete -g setupCompleted
```

To find where it's stored: `defaults find setupCompleted`

## Project Structure

```
app/
├── Package.swift                    # SPM manifest (Hummingbird dependency)
├── Buddygotchi/
│   ├── App/                         # App entry point, AppDelegate, login item
│   ├── Core/                        # BuddyState, events, reducer, engine, protocols
│   ├── Server/                      # Hummingbird HTTP server for hook endpoints
│   ├── Views/                       # SwiftUI popover, setup wizard, approval card
│   ├── Buddies/                     # ASCII sprite data (5 species × 7 states)
│   ├── Notifications/               # macOS notification manager
│   └── Install/                     # Hook installer for Claude Code / Cursor
├── BuddygotchiHook/                 # CLI: stdin → POST → stdout (agent hook)
├── BuddygotchiSignal/               # CLI: stdin → POST signal → exit
└── Tests/                           # Reducer unit tests
```
