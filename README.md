# Buddygotchi

**Buddygotchi** is a local service plus web app that turns **Cursor** and **Claude Code** permission prompts into a small **pixel-style buddy** you can answer from a browser tab on your Mac—or from a phone on the same Wi‑Fi.

No Bluetooth and no gadget required for the main flow: a **Python daemon** receives hook events, pushes state over **WebSockets**, and your **PWA-style UI** shows approve/deny with animated ASCII species and overlay effects.

Repository: [github.com/chicco4life/buddygotchi](https://github.com/chicco4life/buddygotchi)

## What it does

1. **Hooks** run when the agent is about to execute something you care about (shell patterns and/or file tools, configured in `.cursor/hooks.json`).
2. **`mobile-mvp/hooks/buddy-approval.py`** sends the tool name and hint to the daemon and waits for a decision.
3. The **daemon** broadcasts a permission card to every **paired** web client.
4. You tap **approve** or **deny**; the hook returns that choice to the host (or **`ask`** if the daemon is down or nothing decides in time—fail-open to the native UI).

## Features

- **Web UI:** pairing, live buddy state, source filter (e.g. Cursor vs Claude Code), species picker with persistence, canvas particles per mood state.
- **Daemon:** HTTP + WebSocket API, strict reducer-driven state (`mobile-mvp/schema/`).
- **Safety default:** if anything breaks, hooks fall back to the editor’s normal permission flow.

## Quick start

Full steps, env vars, and tests: **[`mobile-mvp/README.md`](mobile-mvp/README.md)**.

```bash
cd mobile-mvp/daemon
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# from repo root
PYTHONPATH=mobile-mvp/daemon python -m buddy_daemon
```

Open **http://127.0.0.1:8080/**, enter the pairing code from the terminal, then use Cursor with this folder as the workspace so **`python3 mobile-mvp/hooks/buddy-approval.py`** resolves.

## Project layout

| Path | Purpose |
|------|---------|
| **`mobile-mvp/`** | **Main product:** daemon (`buddy_daemon`), web client (`web/`), Cursor/Claude hook script (`hooks/`), TypeScript schemas (`schema/`), harness and archived BLE experiments (`archive/`). |
| **`src/`**, **`platformio.ini`**, **`characters/`**, **`tools/`** | **Reference firmware** inherited from [Anthropic’s Claude Desktop Buddy](https://github.com/anthropics/claude-desktop-buddy): ESP32 desk pet that talks to Claude desktop over **BLE** (optional; separate from Buddygotchi’s hook path). |
| **`REFERENCE.md`** | Nordic UART / JSONL protocol for that **hardware** integration. |
| **`docs/`** | Screenshots and manual for the original hardware workflow. |

## Relationship to Claude Desktop Buddy

Buddygotchi’s **animations and “desk pet” idea** are inspired by the official buddy sample, but the **default integration here is hooks + localhost**, not the Claude desktop **Hardware Buddy** BLE window. If you flash the firmware in `src/`, you’re using Anthropic’s maker API; see **`REFERENCE.md`** and upstream **[claude-desktop-buddy](https://github.com/anthropics/claude-desktop-buddy)**.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Upstream firmware changes are best discussed against the Anthropic repo; Buddygotchi-specific work lives under **`mobile-mvp/`**.

## License

See [`LICENSE`](LICENSE).
