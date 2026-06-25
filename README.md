# Buddygotchi

A macOS menu bar companion for AI coding agents. Your buddy reacts to what your agent is doing — sleeping when idle, working when busy, alerting you when a tool call needs approval, and celebrating when a task completes.

Connects to **Claude Code**, **Cursor**, and **Codex** simultaneously. Optionally drives an M5Stack hardware display over Bluetooth.

## Getting Started

### Build & Run

```sh
cd app
swift build
swift run Buddygotchi
```

On first launch, the setup wizard walks you through:

1. **Detect agents** — finds which coding agents are installed on your machine
2. **Install hooks** — one click to register Buddygotchi hooks for each agent
3. **Test connection** — send any message in your agent to verify the link
4. **Choose your buddy** — pick from 5 ASCII species (cat, axolotl, robot, capybara, dragon)
5. **Pick an output** — menu bar popover (default) or M5Stack over Bluetooth

After setup, Buddygotchi runs as a menu bar icon. Click it to see your pet, connection status, and any pending tool approval cards.

### Testing

Verify the server is running:

```sh
curl http://localhost:21321/healthz
```

Simulate a tool approval request:

```sh
curl -X POST http://localhost:21321/hook/event \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"test","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}'
```

Send an activity signal:

```sh
curl -X POST http://localhost:21321/hook/signal \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"claude-code","signal":"start_working","session_id":"test"}'
```

### Reset Onboarding

```sh
defaults delete Buddygotchi setupCompleted
```

## Project Layout

| Path | Purpose |
|------|---------|
| `app/` | Native macOS menu bar app (Swift/SwiftUI) |
| `app/Buddygotchi/Core/` | Pure business logic — engine, reducer, state model |
| `app/Buddygotchi/Server/` | HTTP input (Hummingbird) |
| `app/Buddygotchi/Views/` | SwiftUI popover, settings, setup wizard |
| `app/Buddygotchi/Outputs/ESP32/` | BLE hardware output for M5Stack |
| `app/BuddygotchiHook/` | Hook CLI — agent stdin to HTTP POST |
| `app/BuddygotchiSignal/` | Signal CLI — lifecycle events to HTTP POST |
| `src/outputs/esp32/` | ESP32 firmware (C++/PlatformIO) |

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical design.

## Releasing the Mac App

Buddygotchi is distributed outside the Mac App Store as a signed and notarized DMG with Sparkle updates. See [docs/release.md](docs/release.md) for the release process and required GitHub Actions secrets.

## License

See [`src/outputs/esp32/LICENSE`](src/outputs/esp32/LICENSE).
