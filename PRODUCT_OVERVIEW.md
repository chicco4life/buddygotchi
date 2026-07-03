# Buddygotchi Product Overview

This document summarizes Buddygotchi as a product. It is split into two parts:

1. A general overview of the product and the overall solution.
2. A detailed inventory of what exists in the current repository.

The focus is product behavior and user-facing functionality, not internal implementation design.

---

# Part 1: General Product Overview

## One-Line Summary

Buddygotchi is a local macOS menu bar companion for AI coding agents. It gives developers a glanceable animated buddy that reflects what their agents are doing, highlights when human attention is needed, and can optionally approve or deny tool calls from the menu bar or a small Bluetooth hardware display.

## Product Concept

AI coding agents often work in the background across editors, terminals, and agent-specific UIs. They can be busy for minutes, stop with output that needs review, request permission to run a tool, or fail while the developer is focused somewhere else. Buddygotchi turns those invisible agent states into a small ambient companion.

The product sits beside the developer's existing tools rather than replacing them. It listens to official agent hook systems, translates agent activity into a shared state model, and presents that state through:

- A macOS menu bar popover.
- macOS notifications.
- An optional M5StickC Plus 2 hardware buddy over Bluetooth.

The experience is deliberately local-first. Agent events are sent to a localhost server running inside the macOS app. The core approval and monitoring flow does not require a cloud service.

## Problem It Solves

Developers using AI coding agents face several coordination problems:

- Agent work is often hidden behind another app or terminal tab.
- Permission prompts can stall progress until the developer notices them.
- Multiple agents can be running at once, making it difficult to tell which one is active, waiting, failed, or done.
- Completion is easy to miss because many agents briefly show success and then return to an idle state.
- Failures and long silent stalls can look similar to normal idleness unless the user checks the agent directly.
- Hardware companion concepts are appealing, but most agent workflows still need a practical desktop control path.

Buddygotchi addresses those issues with a persistent, low-friction status surface.

## Target Users

Primary users:

- Developers who use Claude Code, Cursor, or Codex for coding tasks.
- Developers who run long agent tasks and want peripheral awareness without constantly switching windows.
- Developers using more than one AI coding agent at the same time.
- Developers who want a playful but functional companion for agent state.

Secondary users:

- Hardware hobbyists who want a physical AI-agent status device.
- Teams exploring ambient developer tools or agent-control surfaces.
- Power users who want to route selected tool approvals through a unified local UI.

## Core Value Proposition

Buddygotchi makes AI agent activity visible and actionable.

Instead of requiring the developer to monitor each agent app, Buddygotchi answers:

- Is any agent connected?
- Is an agent working?
- What is it doing right now?
- Does it need permission?
- Did it finish?
- Did it fail?
- Which agent or session needs attention?
- Can I approve or deny the request without switching context?

## High-Level Product Pillars

### 1. Ambient Agent Awareness

Buddygotchi uses an animated pet to represent agent status:

- Sleeping when no agents are connected.
- Idle when connected but not working.
- Busy when an agent is running work.
- Thinking when an agent has been quiet for a while but is presumed alive.
- Attention when a prompt or permission request is waiting.
- Error when an agent explicitly fails.
- Celebrate when a task completes.

This makes agent status legible from a glance rather than through logs.

### 2. Unified Multi-Agent Monitoring

The product supports Claude Code, Cursor, and Codex simultaneously. It does not force the user to choose one agent. It aggregates all connected sessions into one state while still preserving enough detail to show source, session, current tool, and waiting state.

The menu bar becomes a small command center for several agent workflows.

### 3. Human-in-the-Loop Tool Approval

Buddygotchi supports two approval experiences:

- Passive mode: Buddygotchi shows that a permission prompt exists, but the agent's native UI remains the actual approval surface.
- Local Approval Mode: Buddygotchi becomes the approval surface. The user can approve or deny from the popover, and the optional hardware buddy can approve or deny using physical buttons.

This is the most actionable feature: it turns the companion from a monitor into a control point.

### 4. Productive Playfulness

The pet framing makes agent activity emotionally readable without making the app purely decorative. The buddy is not only a mascot; it encodes real workflow state.

Personalization is part of the product:

- Five desktop ASCII species are available in the app.
- Each species has custom animation frames for core states.
- The hardware firmware includes additional species and GIF character support.
- The UI uses sounds and optional auto-show behavior for important transitions.

### 5. Local-First Safety

Buddygotchi is designed to avoid silently breaking developer workflows:

- Hooks fail open if the app is unavailable.
- Approval hooks time out rather than blocking forever.
- If Local Approval Mode is disabled while approvals are pending, pending approvals are released.
- If a session dies mid-approval, the pending approval is released.
- Core agent activity and approval routing use localhost.

The product trades strict enforcement for developer workflow continuity.

### 6. Optional Hardware Extension

The M5StickC Plus 2 output turns Buddygotchi from a menu bar utility into an ambient physical device. The hardware can show pet state, session counts, prompt context, completion summaries, and approval prompts. It can also send approval decisions back to the macOS app.

This creates a distinct market angle: Buddygotchi is both a software companion and a bridge to a dedicated desk device.

## Market-Research Framing

Buddygotchi sits at the intersection of several product categories:

- AI coding-agent utility.
- Developer productivity companion.
- Ambient status monitor.
- Local approval/control surface.
- Desk gadget / hardware companion.
- Lightweight automation observability tool.

Potential differentiators:

- Multi-agent support rather than a single-agent integration.
- Local-first architecture instead of a cloud dashboard.
- Approval control, not just status visualization.
- Playful pet metaphor tied to real workflow states.
- Optional hardware output with bidirectional controls.
- Lightweight menu bar presence instead of a full dashboard.

Potential comparison sets:

- Agent-native permission dialogs.
- Menu bar productivity monitors.
- Build/CI status lights.
- Developer desk gadgets.
- Local automation dashboards.
- AI coding-agent orchestration tools.

The strongest market story is not "virtual pet for developers" by itself. It is "ambient command center for AI coding agents, expressed as a companion."

## What Buddygotchi Is Not

Buddygotchi currently does not try to be:

- A full agent orchestrator.
- A replacement for Claude Code, Cursor, or Codex.
- A cloud dashboard.
- A long-term analytics product.
- A security policy engine with detailed per-tool rules.
- A remote mobile approval service.
- A persistent audit/history database.

Its current product center is local awareness and local intervention.

---

# Part 2: Current Product Details

## Current Active Product

The active product is the native macOS app in `app/`.

The older TypeScript daemon and web client under `src/` are useful historical context and contain archived/prototype work, but the current primary product is the Swift/SwiftUI menu bar app.

Current active surfaces:

- Native macOS menu bar app.
- SwiftUI popover.
- First-run setup wizard.
- Settings panel.
- Local HTTP hook server.
- Agent hook installer.
- macOS notifications.
- Optional ESP32/M5StickC Plus 2 Bluetooth output.
- ESP32 firmware and support tools.

## Current Platform Scope

| Area | Current state |
| --- | --- |
| Desktop OS | macOS 14+ |
| App runtime | Swift 6, SwiftUI |
| App form factor | Menu bar accessory app |
| Local server | Hummingbird HTTP server on `127.0.0.1` |
| Default port | `21321` |
| Agent integrations | Claude Code, Cursor, Codex |
| Hardware output | M5StickC Plus 2 over Bluetooth LE Nordic UART Service |
| Core cloud dependency | None for activity and approval routing |
| Optional network use | Firmware update manifest and binary download |

## Primary User Flows

### First-Run Setup

The app opens into a six-step setup wizard when setup has not been completed:

1. Welcome: introduces the coding companion.
2. Connect agent: detects configured agent directories and offers hook installation.
3. Test connection: asks the user to send any agent message and watches for a hook event.
4. Personalize: lets the user choose a buddy species.
5. Display output: chooses where the buddy lives, with "This Mac" as default and M5Stack as an optional Bluetooth display.
6. Done: summarizes installed agents and selected display, and offers Launch at Login.

Setup can be reset later from Settings or by deleting the `setupCompleted` defaults key.

### Day-to-Day Monitoring

After setup, Buddygotchi lives in the macOS menu bar. The menu bar icon mirrors the pet state using SF Symbols. Clicking the icon opens a compact popover with:

- Animated buddy.
- Species and state label.
- Connection status.
- Active session count.
- Per-session list when more than one session exists.
- Current activity row during work.
- Thinking row when a session is quiet past the stall threshold.
- Tool request card when attention is needed.
- Error card when an agent fails.
- Review card when a task completes.
- Footer controls for bug report export, settings, and quit.

### Passive Approval Awareness

When Local Approval Mode is off, Buddygotchi shows permission prompts as read-only attention cards. The agent's native permission dialog remains responsible for the actual decision.

This mode is useful for awareness without changing the user's existing approval behavior.

### Local Approval Mode

When Local Approval Mode is on, supported permission hooks are routed through Buddygotchi:

1. The agent invokes a hook.
2. The hook posts to `/hook/approve`.
3. The app displays an approval card.
4. The user approves or denies in the popover, or on the hardware device.
5. The server returns an agent-specific approval response.
6. The agent continues or receives the denial.

Approval cards show:

- Agent/source badge.
- Session label when available.
- Tool name.
- Tool hint or command/path/query.
- Activity icon when classifiable.
- Approve and Deny buttons for blocking approvals.

The Approve button supports the Return keyboard shortcut in the popover.

### Completion Review

When a task completes, Buddygotchi briefly enters celebrate state and records a completion summary. The review surface can persist past the celebration window so the user can see what finished after they return.

Completion details can include:

- Agent source.
- Tool name.
- Hint/path/command.
- Duration.
- Activity kind.
- Session label.

The review card can be dismissed manually.

### Error and Thinking States

Buddygotchi distinguishes explicit failure from long quiet work:

- Explicit failure becomes `error`.
- A working session that goes quiet past the work-stall threshold becomes `thinking`.

The product meaning is different:

- Error means the agent failed and the user should inspect it.
- Thinking means the agent is presumed alive but quiet, so the UI stays calm and does not present it as a failure.

### Multi-Agent and Multi-Session Behavior

Buddygotchi can track several sessions at once. The aggregate pet state follows priority rules while the popover can still show session-level details.

Current priority order when at least one session is connected:

1. Attention: at least one prompt or approval is waiting.
2. Error: at least one session explicitly failed.
3. Busy: at least one session is actively working.
4. Thinking: at least one session is quiet past the stall threshold.
5. Celebrate: a recent task completed.
6. Idle: connected, but no active work.

If no sessions are connected, the pet sleeps.

When several sessions are active:

- The oldest waiting prompt is shown first.
- Waiting sessions come first in the session list.
- Errored sessions are shown before working sessions.
- Working sessions are ordered by longest-running work.
- Idle sessions are shown after active sessions.
- The session list is capped at six rows.

## Agent Integrations

### Claude Code

Claude Code integration is installed into `~/.claude/settings.json`.

Buddygotchi writes command hooks that invoke:

```sh
~/.buddygotchi/buddygotchi-hook.sh claude-code
```

Installed hook coverage includes:

- `SessionStart`
- `UserPromptSubmit`
- `Stop`
- `StopFailure`
- `SessionEnd`
- `PostToolUse`
- `Elicitation`
- `ElicitationResult`
- `PermissionRequest`
- `Notification` matchers for permission, idle, and elicitation prompts

Key behaviors:

- `UserPromptSubmit` starts work.
- `PostToolUse` keeps the session busy and records current tool context.
- `Stop` celebrates and records completion.
- `StopFailure` enters error state.
- `PermissionRequest` becomes either a passive prompt or a blocking local approval depending on approval mode.
- `Elicitation` becomes an attention request.
- `SessionEnd` disconnects the session.

### Cursor

Cursor integration is installed into `~/.cursor/hooks.json`.

Cursor uses the `BuddygotchiSignal` Swift binary rather than the shared bash script for most hooks.

Installed hook coverage includes:

- `sessionStart`
- `sessionEnd`
- `beforeSubmitPrompt`
- `stop`
- `beforeShellExecution`
- `beforeMCPExecution`
- `afterShellExecution`
- `afterMCPExecution`

Key behaviors:

- `beforeSubmitPrompt` and `sessionStart` start work.
- Shell and MCP execution hooks keep work active.
- `stop` is treated as completion/celebration server-side.
- `sessionEnd` explicitly deregisters the session.
- In Local Approval Mode, `beforeShellExecution` and `beforeMCPExecution` can route to `/hook/approve`.

Cursor has additional auto-approval behavior in Local Approval Mode:

- Read-only tools such as `Read`, `Glob`, `Grep`, `LSP`, and `WebFetch` auto-approve.
- Safe single shell commands such as `ls`, `cat`, `rg`, `pwd`, and selected read-only `git` commands auto-approve.
- Commands containing shell control characters are not auto-approved and require manual review.

### Codex

Codex integration is installed into `~/.codex/hooks.json`, and the installer also ensures:

```toml
[features]
codex_hooks = true
```

Installed hook coverage includes:

- `SessionStart` with startup/resume matcher.
- `UserPromptSubmit`
- `PermissionRequest`
- `PreToolUse`
- `PostToolUse`
- `Stop`

Key behaviors:

- `UserPromptSubmit` starts work.
- `PreToolUse` and `PostToolUse` keep the pet busy and capture tool context.
- `Stop` celebrates and records completion.
- `PermissionRequest` becomes passive or blocking depending on approval mode.

## Hook Runtime Behavior

The shared bash hook script for Claude Code and Codex reads `~/.buddygotchi/config.json` on every invocation. This matters because toggling Local Approval Mode does not require reinstalling hooks.

The script behavior is:

- If `approvalMode` is true and the event is `PermissionRequest`, POST to `/hook/approve` and wait.
- Otherwise POST to `/hook/event` and exit quickly.
- If the app is down or the request times out, exit successfully with no stdout so the agent falls back to native behavior.

Cursor's signal binary also reads the config file and routes approval-mode events to `/hook/approve`.

## Local HTTP API

The macOS app exposes local-only routes:

| Route | Purpose |
| --- | --- |
| `GET /healthz` | Health probe with state version and desktop status |
| `POST /hook/event` | Non-blocking agent hook event path |
| `POST /hook/signal` | Non-blocking lifecycle/activity signal path |
| `POST /hook/approve` | Blocking approval path |

All routes bind to `127.0.0.1` on the configured port.

## Pet States and Product Meaning

| State | Product meaning | Typical trigger |
| --- | --- | --- |
| `sleep` | Nothing connected | No active sessions |
| `idle` | Agent connected but waiting | Session exists with no active work |
| `busy` | Agent is working | User prompt, pre/post tool use, keep-working signal |
| `thinking` | Agent has been quiet for a while but may still be alive | Work-stall timeout |
| `attention` | User needs to look or decide | Prompt, elicitation, permission request |
| `error` | Agent failed | Claude Code `StopFailure` or explicit error signal |
| `celebrate` | Task completed | Stop/completion signal |

The desktop ASCII species currently define animation frames for `sleep`, `idle`, `busy`, `attention`, and `celebrate`. When `error` or `thinking` is shown in the desktop pet stage, the renderer falls back to the species idle frame while the rest of the UI still reflects the real state through labels, colors, cards, sounds, and hardware mappings.

## Activity Classification

Buddygotchi classifies tool activity into product-level categories:

| Activity kind | Examples |
| --- | --- |
| `read` | `Read`, `Glob`, `Grep`, `LSP` |
| `write` | `Edit`, `Write`, `MultiEdit`, `NotebookEdit` |
| `web` | `WebFetch`, `WebSearch` |
| `verify` | Test commands such as `swift test`, `npm test`, `pytest`, `go test`, `cargo test` |
| `shell` | Other shell commands |
| `work` | Unknown or generic tools |

These categories drive icons in the popover and are also sent to the hardware heartbeat.

## Menu Bar Popover Details

The live popover is the main product surface. It includes:

- Animated ASCII buddy stage with species color glow.
- State pill with species name and current state.
- Connection bar with connected/disconnected status and active session count.
- Multi-session list when more than one session exists.
- Current activity row during busy work.
- Thinking row with elapsed time for quiet long-running work.
- Tool card for prompt/approval state.
- Error card for failed sessions.
- Review card for completed tasks.
- Bug report export button.
- Settings button.
- Quit button.

The popover supports reduced-motion accessibility by disabling some transitions and animations.

## Notifications and Sounds

Buddygotchi can request macOS notification permission. When a new prompt arrives and the popover is closed, it posts a notification with the tool title and hint. The notification is cleared when the prompt resolves.

Sounds are used for state transitions:

- Attention: `Glass`
- Long celebrate, when task duration is at least 30 seconds: `Funk`
- Error: `Sosumi`

Interactive Mode controls automatic popover behavior:

- Auto-show on attention.
- Auto-show briefly on long celebrations.
- Auto-dismiss when returning to idle or sleep.

## Settings Details

The Settings view contains:

General:

- Launch at Login.
- Interactive Mode.
- Local Approval Mode.
- HTTP port display.

Buddy:

- Species picker with previous/next controls.
- Current species preview.

Agents:

- Claude Code install/reinstall.
- Cursor install/reinstall.
- Codex install/reinstall.

Displays:

- This Mac status.
- M5Stack pairing status.
- BLE scan and connect flow.
- Unpair control.
- Firmware update row when hardware is connected.

About:

- App version.
- Reset Setup.
- Quit Buddygotchi.

## Personalization

The desktop app currently exposes five buddy species:

- Cat
- Axolotl
- Robot
- Capybara
- Dragon

Each has hand-authored ASCII frames and a species color. The setup wizard and settings panel both let the user choose the species.

## Hardware Companion Details

Buddygotchi can drive an M5StickC Plus 2 over Bluetooth LE using the Nordic UART Service.

Hardware features currently supported by the app/firmware combination include:

- Pairing and reconnecting to a saved device.
- On-device passkey display during BLE pairing.
- Desktop-to-device heartbeat on every state change.
- 10-second keepalive heartbeat.
- Time sync from Mac to device.
- Pet state display.
- Species display.
- Connected/disconnected status.
- Total, running, and waiting session counts.
- Message line for current activity or completion summary.
- Prompt ID, tool, hint, source, and approval flag.
- Activity log entries.
- Multi-session summary fields sent by desktop.
- Completion metadata sent by desktop.
- Error/activity metadata sent by desktop.
- A-button approval and B-button denial for active approval prompts.
- Device-to-desktop approval messages over BLE.
- Unpair command from desktop to device.
- Firmware status query.
- Firmware update over BLE OTA.

The firmware itself also contains:

- Hardware clock and rotation support.
- Info pages.
- Battery and device status pages.
- Settings menu.
- 18 built-in ASCII species.
- GIF character support from LittleFS.
- USB/serial debug tooling.
- Demo/live/asleep modes.

## Hardware Approval Flow

When Local Approval Mode is active and an approval prompt is pending:

1. The Mac sends the prompt over the heartbeat.
2. The hardware displays the tool and hint.
3. Button A sends an allow decision.
4. Button B sends a deny decision.
5. The Mac receives `{"cmd":"permission","id":"...","decision":"allow|deny"}`.
6. The app resolves the same pending approval that the popover would have resolved.
7. The blocked agent hook receives the decision.

The hardware is therefore bidirectional, not merely a passive display.

## Firmware Update Flow

When an M5Stack is connected, the app can query firmware status and check for updates.

Update flow:

1. App fetches a firmware manifest.
2. App downloads the binary.
3. App verifies the binary SHA-256 hash.
4. App sends `ota_begin`.
5. App streams base64 chunks over BLE, waiting for acknowledgements.
6. App sends `ota_end`.
7. Device verifies and commits the update.
8. Device reboots.
9. App shows success, failure, progress, or retry states.

The update UI can be hidden while the update continues. If the popover is reopened mid-update, the sheet can reattach to the in-flight updater state.

## Configuration and Local State

Buddygotchi uses a small set of local files and defaults:

| Location | Purpose |
| --- | --- |
| `~/.buddygotchi/config.json` | Port and Local Approval Mode |
| `~/.buddygotchi/buddygotchi-hook.sh` | Shared bash hook script for Claude Code and Codex |
| `~/.claude/settings.json` | Claude Code hook registration |
| `~/.cursor/hooks.json` | Cursor hook registration |
| `~/.codex/hooks.json` | Codex hook registration |
| `~/.codex/config.toml` | Codex hook feature flag |
| macOS UserDefaults | Setup state, species, output target, interactive mode, approval mode, hardware UUID |

Important defaults:

- Port: `21321`
- Stale session timeout: 10 minutes
- Celebrate duration: 4 seconds
- Work-stall thinking threshold: 5 minutes
- Default species: `cat`
- Local Approval Mode: off by default

## Privacy and Safety Characteristics

Current privacy/safety posture:

- Agent activity and approval traffic stay on localhost.
- The HTTP server binds to `127.0.0.1`.
- Hooks are fail-open if Buddygotchi is unavailable.
- The app does not persist a long-term activity history.
- Diagnostic logs are in-process with a fixed capacity.
- Bug report export is user-initiated.
- No authentication is implemented for localhost callers.
- Optional firmware update checks/downloads use the network.

The lack of localhost authentication is acceptable for a local developer utility prototype, but it is a product consideration if expanding to stricter security or enterprise use cases.

## Diagnostics and Bug Reports

The popover footer includes a bug report export button. It creates a JSON bundle on the user's Desktop containing:

- Export timestamp.
- App version.
- macOS version.
- Process uptime.
- Current Buddygotchi state snapshot.
- Selected settings.
- Agent detection/install status.
- Recent in-process diagnostic entries.
- Recent OSLog entries for the Buddygotchi subsystem.

This is designed for actionable support without requiring the user to manually gather logs.

## Testing and Verification Assets

Current test coverage includes:

- 59 reducer tests.
- 43 engine integration tests.
- 5 auto-approve tests.
- 6 disabled-by-default snapshot harness tests.

The standard in-process suites cover:

- Session lifecycle.
- State priority.
- Prompt and approval behavior.
- Completion review.
- Current activity and entries.
- Error and thinking states.
- Multi-session ordering.
- Activity classification.
- Heartbeat fields.
- Auto-approval safety.

Additional verification tools include:

- End-to-end HTTP smoke scripts under `app/tools/e2e/`.
- Snapshot harness for SwiftUI views.
- ESP32 screenshot and button tools under `src/outputs/esp32/tools/`.
- Firmware serial debug commands.

## Current Non-Active or Legacy Areas

Several repo areas are useful context but are not the primary active product path:

- `src/` contains an older TypeScript daemon and web UI approach.
- `src/outputs/web/` contains a browser UI from the earlier architecture.
- `src/outputs/mobile/` is a placeholder.
- `app/BuddygotchiHook/` still builds as a Swift target but is legacy/unused by the installer.
- Some documentation files have historical drift from the current Swift implementation.

For current product research, treat `app/` plus `src/outputs/esp32/` as the active product.

## Current Product Limitations

Known product limitations and caveats:

- macOS only.
- The active user experience is local, not remote/mobile.
- No persistent history or analytics beyond the current in-memory state and exported diagnostics.
- No per-tool rule editor.
- Cursor approval support relies on generic before-execution hooks rather than a dedicated permission prompt event.
- Cursor hook binary paths need a stable packaged install story.
- Launch at Login depends on a proper app bundle and is limited during `swift run` development.
- Localhost HTTP routes are unauthenticated.
- Firmware OTA requires devices to already have compatible dual-OTA partitioning.
- Desktop pet species picker exposes five species, while firmware has more internal species support.
- The active product does not use the older browser/PWA approval interface.

## Current Feature Matrix

| Feature | Current status |
| --- | --- |
| macOS menu bar companion | Implemented |
| Animated ASCII buddy | Implemented |
| Species selection | Implemented with five desktop species |
| First-run setup wizard | Implemented |
| Claude Code support | Implemented |
| Cursor support | Implemented |
| Codex support | Implemented |
| Passive permission awareness | Implemented |
| Local Approval Mode | Implemented |
| Popover approve/deny | Implemented |
| Hardware approve/deny | Implemented |
| Multi-agent aggregation | Implemented |
| Per-session popover list | Implemented |
| Completion review card | Implemented |
| Error card | Implemented |
| Thinking/stall state | Implemented |
| Current activity display | Implemented |
| macOS notifications | Implemented |
| Interactive auto-show mode | Implemented |
| Bug report export | Implemented |
| Launch at Login UI | Implemented, packaging-dependent |
| M5Stack BLE pairing | Implemented |
| M5Stack heartbeat display | Implemented |
| M5Stack firmware update UI | Implemented |
| Persistent activity history | Not implemented |
| Remote/mobile approval | Not implemented in active app |
| Cloud dashboard | Not implemented |
| Per-tool approval policy editor | Not implemented |

## Product Takeaway

Buddygotchi is currently a functional local companion and control surface for AI coding agents. Its core product loop is:

1. Detect agent activity through hooks.
2. Convert that activity into a clear companion state.
3. Notify or surface the exact moments that need attention.
4. Let the user approve or deny tool calls from a unified local UI.
5. Preserve lightweight context about what is running, what finished, and what failed.
6. Optionally mirror and control the same loop from a physical desk device.

For market research, the product should be evaluated less as a novelty virtual pet and more as a local, ambient, multi-agent status and approval layer for developers adopting AI coding agents.
