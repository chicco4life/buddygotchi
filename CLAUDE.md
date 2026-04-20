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
