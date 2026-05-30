# Buddygotchi

## Architecture

Follow the strict **inputs → core → outputs** separation defined in ARCHITECTURE.md.

- **Core** (`Core/`) is pure business logic: the engine, reducer, state model, and events. It has no UI imports and no I/O.
- **Inputs** (`Server/`, CLI tools) translate external events into `BuddyEvent` values and feed them to the engine. They never touch UI.
- **Outputs** (`Views/`, `Outputs/`, `Notifications/`) are thin wrappers that react to `stateDidChange`. Keep presentation logic minimal — derive everything from `BuddyState`, don't store parallel state.

When adding a new source (agent integration), add an input adapter. When adding a new display (hardware, widget, etc.), implement `OutputProvider`. Neither should require changes to `Core/`.

## Build & Run

```sh
cd app
swift build
swift run Buddygotchi
```

Test the hook server:

```sh
curl http://localhost:21321/healthz
```

Reset onboarding:

```sh
defaults delete Buddygotchi setupCompleted
```

Capture the ESP32 display (for visually verifying firmware changes):

```sh
python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy.png
```

Reads the panel via `M5.Display.readRect`, so direct-to-LCD draws (landscape clock) are captured too — not just sprite content.

Press a device button (for verifying button input, e.g. approval flow):

```sh
python3 src/outputs/esp32/tools/button.py --mock a   # arm a fake prompt, press A (approve)
python3 src/outputs/esp32/tools/button.py b          # press B (deny) against whatever's live
```

Injects a synthetic press through the firmware's real approval path. `--mock` arms a fake prompt so it works offline (no daemon). Self-verifies via the permission JSON echoed on serial; pair with a screenshot to confirm `APPROVE?` renders. Both `screenshot`/`btn`/`mockprompt` are non-JSON debug commands handled by `handleSerialCommand` in `main.cpp`.

## Key Files

| File | Role |
|------|------|
| `Core/BuddyEngine.swift` | Central orchestrator — all state flows through here |
| `Core/BuddyReducer.swift` | Pure reducer — the only place state transitions are defined |
| `Core/BuddyState.swift` | Single source of truth for all outputs |
| `Server/HookServer.swift` | HTTP input — translates hook payloads to engine events |
| `Theme/BuddyTheme.swift` | Design tokens, card modifiers, button styles |
| `Views/PopoverView.swift` | Main UI — live view, tool card, debug pane |
| `Buddies/BuddySprites.swift` | ASCII art data (5 species × 7 states) |
