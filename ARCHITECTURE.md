# Architecture

## What is Buddygotchi?

Buddygotchi is a macOS menu bar companion for AI coding agents. It gives you an animated ASCII pet that reacts to what your agent is doing — sleeping when idle, working when busy, alerting you when a tool call needs approval, and celebrating when a task completes. It connects to Cursor, Claude Code, and Codex simultaneously via lightweight hooks, and can optionally drive a dedicated hardware display over Bluetooth.

## Who is it for?

Developers who use AI coding agents and want an ambient, glanceable way to monitor agent activity and approve tool calls — without switching windows.

## Key Features

- **Activity visualization** — your pet reflects agent state in real time across 5 animation states: sleep, idle, busy, attention, and celebrate
- **Multi-agent support** — connects to Cursor, Claude Code, and Codex simultaneously, each through their native hook system
- **Tool approval cards** — when an agent needs permission, a card appears showing the tool name, command hint, and source badge
- **Local approval mode** — optionally route tool approvals through the Buddygotchi popover instead of the agent's built-in permission dialog, with approve/deny buttons and keyboard shortcuts
- **Species picker** — choose from 5 hand-crafted ASCII species (cat, axolotl, robot, capybara, dragon), each with unique animations per state
- **Hardware output** — optionally drive an M5StickC Plus 2 over Bluetooth (Nordic UART Service); the device shows pet state and approval prompts and can resolve approvals from its own A/B buttons
- **Setup wizard** — six-step first-run onboarding (welcome → connect agent → test connection → personalize → display output → done). The display step embeds a live BLE scanner / pairing flow when M5Stack is selected, and verifies the link by sending a one-shot celebration to the device.
- **Interactive mode** — when on, the popover auto-shows on attention/long-celebrate transitions, plays system sounds (Glass for attention, Funk for ≥30s celebrates), and auto-dismisses when the pet returns to idle/sleep
- **Bug-report export** — the popover footer's bug button emits a JSON bundle (state snapshot, in-process diagnostic log, agent install status, last 10 minutes of `OSLogStore` entries) to the user's Desktop
- **Fail-open safety** — if the app is down or nobody responds in time, hooks return empty stdout and the agent's native permission dialog takes over; the system never silently blocks or allows

## What it does NOT do

- **No cloud/internet** — everything is localhost only
- **No persistent history** — activity log is in-memory and resets on restart
- **No per-tool rules** — Claude Code/Codex approvals mirror the agent's own permission logic; Cursor has a built-in allowlist for safe read-only tools and a small regex set for safe shell verbs (only when the command contains no shell control characters)
- **No authentication** — the app trusts any local process that can reach its HTTP port

---

## Three-Layer Architecture

The app follows a strict **inputs → core → outputs** pattern. Sources push events in via HTTP; the core engine applies them through a pure reducer; registered outputs receive every state change.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Coding Agents                            │
│  ┌──────────┐    ┌─────────────┐    ┌──────────┐               │
│  │  Cursor   │    │ Claude Code  │    │  Codex   │               │
│  └────┬─────┘    └──────┬──────┘    └────┬─────┘               │
│       │                 │                │                      │
│       │ Signal CLI      │  bash script   │  bash script         │
│       │ (binary)        │ (~/.buddygotchi/buddygotchi-hook.sh)   │
└───────┼─────────────────┼────────────────┼──────────────────────┘
        │                 │                │
        ▼                 ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Buddygotchi (macOS app)                        │
│                                                                 │
│  ┌────────────────────────────────────────────────────┐         │
│  │              HTTP Server (Hummingbird)              │         │
│  │  POST /hook/event       POST /hook/signal          │         │
│  │  POST /hook/approve     GET  /healthz              │         │
│  └──────────┬─────────────────────────────────────────┘         │
│             │                                                   │
│             ▼                                                   │
│  ┌──────────────────┐                                           │
│  │   BuddyEngine     │  Pure reducer: events → BuddyState       │
│  │   (Observable)     │  Monotonic version, no side effects       │
│  └────────┬─────────┘                                           │
│           │ stateDidChange                                      │
│           ├────────────────────┬─────────────────────┐          │
│           ▼                    ▼                     ▼          │
│  ┌─────────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │  Menu Bar UI     │  │  Notifications │  │  ESP32 Output    │  │
│  │  (PopoverView)   │  │  (macOS)       │  │  (BLE bridge)    │  │
│  └─────────────────┘  └───────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
app/Buddygotchi/
├── App/                 Lifecycle
│   ├── AppDelegate.swift   Menu bar item, engine startup, output wiring
│   ├── BuddygotchiApp.swift
│   └── LoginItemManager.swift
│
├── Core/                Pure business logic
│   ├── BuddyEngine.swift   Orchestrator: wires inputs/outputs through reducer
│   ├── BuddyReducer.swift  Pure reducer: events → BuddyState
│   ├── BuddyEvent.swift    Event type definitions
│   ├── BuddyState.swift    State model (Pet, Prompt, Sessions, Desktop)
│   ├── Clock.swift          Clock protocol + WallClock (injectable for tests)
│   ├── Config.swift         Reads/writes ~/.buddygotchi/config.json (port + approvalMode)
│   ├── DiagnosticLog.swift  Engine + hook event log; bug-bundle exporter
│   └── Protocols.swift      OutputProvider contract
│
├── Server/              HTTP input (Hummingbird)
│   └── HookServer.swift   Routes /hook/event, /hook/signal, /hook/approve, /healthz → engine events
│
├── Views/               SwiftUI display output
│   ├── PopoverView.swift      Menu bar popover (pet + status + tool card + bug-export button)
│   ├── PetStageView.swift     Animated ASCII pet renderer
│   ├── SetupWizardView.swift  First-run setup wizard (6 steps, embedded BLE pairing on output step)
│   └── SettingsView.swift     Preferences panel (incl. M5Stack pairing)
│
├── Theme/               Design system
│   └── BuddyTheme.swift  Colors, card modifiers, button styles
│
├── Buddies/             Pet data
│   └── BuddySprites.swift ASCII art (5 species × 7 states, animation frames)
│
├── Outputs/ESP32/       BLE hardware output (bidirectional)
│   ├── ESP32Output.swift    OutputProvider: state → heartbeat → M5Stack; receives device-side approvals
│   ├── BLEManager.swift     CoreBluetooth central + scanner (Nordic UART Service); routes inbound permission JSON to engine
│   └── Heartbeat.swift      Pure BuddyState → heartbeat JSON mapper
│
├── Notifications/       macOS notification output
│   └── NotificationManager.swift
│
└── Install/             Agent hook installer (writes ~/.buddygotchi/buddygotchi-hook.sh + per-agent config)
    └── HookInstaller.swift

app/BuddygotchiHook/    Legacy CLI (still in Package.swift; not wired by the installer — see BUGS.md N3)
app/BuddygotchiSignal/  Signal CLI used by Cursor's hooks.json
app/Tests/              ReducerTests, EngineIntegrationTests, AutoApproveTests, SnapshotHarnessTests (opt-in)
app/tools/              e2e-smoke.sh + e2e/{claude,codex,cursor}.sh (HTTP-level smoke runner)
```

## Sources

Each coding agent connects through its native hook system. Two delivery shapes are in use:

- **Claude Code** and **Codex** invoke a generated bash script (`~/.buddygotchi/buddygotchi-hook.sh`, written by `HookInstaller`) that reads the hook payload from stdin, reads the daemon port and `approvalMode` flag from `~/.buddygotchi/config.json`, and `curl`s either `/hook/event` (non-blocking) or `/hook/approve` (blocking, when approval mode is on and the event is `PermissionRequest`). The script's response is echoed to stdout for the agent to consume. Reading config on every invocation means toggling approval mode never requires a reinstall.
- **Cursor** invokes the `BuddygotchiSignal` Swift binary, which translates the hook payload into either an `/hook/signal` POST (lifecycle / activity events) or an `/hook/approve` POST (when `approvalMode` is on and the event is `beforeShellExecution`/`beforeMCPExecution`). The binary always prints `{"permission":"allow"}` for non-approval Cursor hooks so Cursor's permission flow continues normally.

| Agent | Hook Config | Hook Delivery | Events Installed |
|-------|------------|---------------|------------------|
| **Claude Code** | `~/.claude/settings.json` | bash script → `/hook/event` + `/hook/approve` | SessionStart, UserPromptSubmit, Stop, StopFailure, SessionEnd, PostToolUse, Elicitation, ElicitationResult, PermissionRequest (blocking), Notification (matchers: `permission_prompt`, `idle_prompt`, `elicitation_dialog`) |
| **Cursor** | `~/.cursor/hooks.json` | `BuddygotchiSignal` binary → `/hook/signal` (or `/hook/approve` when approval mode is on) | sessionStart, sessionEnd, beforeSubmitPrompt, stop, beforeShellExecution, beforeMCPExecution, afterShellExecution, afterMCPExecution |
| **Codex** | `~/.codex/hooks.json` + `[features] codex_hooks = true` in `~/.codex/config.toml` | bash script → `/hook/event` + `/hook/approve` | SessionStart (matcher `startup\|resume`), UserPromptSubmit, PermissionRequest (blocking), PreToolUse, PostToolUse, Stop |

The bash script is shared by Claude Code and Codex (the hook arguments differ only by `source`); the `BuddygotchiHook` Swift binary still ships in `Package.swift` but is unused (see BUGS.md N3). The `signalMap["claude-code"]` entries in `BuddygotchiSignal/SignalCLI.swift` are vestigial — Claude Code's hooks no longer route through the signal binary.

### How Each Agent Integrates

**Claude Code** has the richest hook surface. The HTTP server's `handleAgentEvent` maps inbound events to engine calls:

| Hook Event | Engine Action |
|-----------|---------------|
| `SessionStart` | register session (PID is captured from a `pid=` query param so a `DispatchSourceProcess` can reap stale sessions on parent-process exit) |
| `UserPromptSubmit` | `activitySignal(.startWorking)` |
| `PostToolUse` | clear pending request for session, `activitySignal(.keepWorking)` |
| `Stop` | `activitySignal(.celebrate)` (≥30s tasks also play sound + auto-show popover when interactive mode is on) |
| `StopFailure` | `activitySignal(.stopWorking)` |
| `Elicitation` | `submitRequest` (read-only prompt) |
| `ElicitationResult` | clear request, `activitySignal(.startWorking)` |
| `SessionEnd` | `engine.sessionEnded` |
| `PermissionRequest` | when approval mode is on, blocks via `/hook/approve` until the user decides; when off, the bash script falls through to `/hook/event` and the engine surfaces a read-only `submitRequest` |
| `Notification:permission_prompt` | `submitRequest` (skipped in approval mode — the script routes to `/hook/approve` instead) |
| `Notification:elicitation_dialog` | `submitRequest` |
| `Notification:idle_prompt` | `activitySignal(.stopWorking)` |

Claude Code supports both `command` and `http` hook handler types. Buddygotchi installs `command` handlers that exec the bash script. Non-blocking hooks return immediately (1s connect timeout, fail-open); `PermissionRequest` in approval mode runs with a 600s timeout to give the user time to decide.

**Cursor** hooks cover agent lifecycle and tool execution. The signal binary translates them through this map (`SignalCLI.signalMap["cursor"]`):

| Hook Event | Engine Action |
|-----------|---------------|
| `beforeSubmitPrompt` / `sessionStart` | `activitySignal(.startWorking)` |
| `afterShellExecution` / `afterMCPExecution` / `beforeShellExecution` / `beforeMCPExecution` | `activitySignal(.keepWorking)` (when approval mode is OFF) |
| `beforeShellExecution` / `beforeMCPExecution` | route to `/hook/approve` and block (when approval mode is ON) |
| `stop` | `activitySignal(.stopWorking)` |
| `sessionEnd` | special-cased `"session_end"` signal → `engine.sessionEnded` (no process watcher available, so the explicit deregister is the only timely path; otherwise the 10-min stale tick reaps it) |

Cursor does not fire a dedicated "permission dialog opened" event. In passive mode the pet shows `busy` while Cursor's own permission UI is up. In approval mode the `/hook/approve` path runs an auto-approve allowlist first (read-only tools `Read`/`Glob`/`Grep`/`LSP`/`WebFetch`, plus a regex set of safe shell verbs); commands containing shell control characters (`; & | \` $ ( ) < > \n \r`) skip the allowlist and require manual approval.

**Codex** registers six events in this build; ARCHITECTURE.md previously described it as
"experimental, 5 events" without `PermissionRequest` or `PreToolUse` — that is no longer
accurate.

| Hook Event | Engine Action |
|-----------|---------------|
| `SessionStart` (matcher `startup\|resume`) | register session |
| `UserPromptSubmit` | `activitySignal(.startWorking)` |
| `PreToolUse` | `activitySignal(.keepWorking)` (so the pet shows busy while a Codex tool runs) |
| `PostToolUse` | clear pending request, `activitySignal(.keepWorking)` |
| `Stop` | `activitySignal(.celebrate)` |
| `PermissionRequest` | blocking when approval mode is on; otherwise read-only `submitRequest` |

Codex hooks require `[features] codex_hooks = true` in `~/.codex/config.toml`; the
installer adds the line idempotently.

### Known Integration Gaps

- Cursor still infers approval state from `before*` hooks rather than a dedicated permission event; the auto-approve allowlist handles read-only noise
- All hooks are fail-open: if the app is down, curl times out and the script exits with empty stdout — the agent's native UI takes over

## Outputs

All outputs conform to the `OutputProvider` protocol and receive `stateDidChange(prev:next:)` on every state transition. They are registered with `engine.register(output:)` at startup. Two of them — the menu bar and ESP32 — are bidirectional: each can resolve a pending approval back into the engine.

| Output | Direction | Description |
|--------|-----------|-------------|
| **Menu Bar UI** | bi | SwiftUI popover with animated ASCII pet, connection status, tool approval card. Approve/Deny buttons call `engine.resolveApproval`. The status bar icon mirrors `pet.state.sfSymbol`. `AppDelegate` plays system sounds (`Glass` for attention, `Funk` for celebrates ≥30s) and, when **Interactive Mode** is on, auto-shows the popover on `attention`/long-celebrate transitions and auto-dismisses when the pet returns to idle/sleep. |
| **Notifications** | out | `NotificationManager` posts a `UNUserNotification` for each new prompt when the popover is closed; the notification clears when the prompt resolves. |
| **ESP32 (BLE)** | bi | `ESP32Output` ships a heartbeat JSON to the M5Stack on every state change and as a 10s keepalive. The firmware ships approve/deny back the other way (see "ESP32 wire format" below). |
| **DiagnosticLog** (export only) | out | Not a registered output — the engine writes a structured event log via `engine.diagnosticLog.log(...)` for both engine state changes and inbound hook payloads. The popover footer's bug button (`PopoverView.exportBugReport`) bundles the log + state snapshot + agent install status + 10 minutes of `OSLogStore` entries into a JSON file dropped on the Desktop. |

### ESP32 wire format

Outbound (desktop → device, line-delimited JSON over Nordic UART RX):

- **Heartbeat** — every state change + 10s keepalive — is `Heartbeat.RenderState`:
  `{ pet, species, desktop, total, running, waiting, msg, celebrate, promptId?, promptTool?, promptApproval? }`. Strings are pre-truncated (msg ≤ 23, promptTool ≤ 20).
- **Time sync** — sent once on connect: `{"time":[epoch_sec, tz_offset_sec]}`.
- **Unpair** — sent when the user clicks Unpair in Settings: `{"cmd":"unpair"}`. The firmware clears its bond and forgets the desktop.

Inbound (device → desktop, same NUS channel, TX characteristic):

- **Permission decision** — when the user presses **A** (approve) or **B** (deny) on the device with a prompt active, the firmware writes `{"cmd":"permission","id":"<requestId>","decision":"allow"|"deny"}`. `BLEManager.handleIncomingLine` parses it and calls `engine.resolveApproval`, which resumes the same `CheckedContinuation` the popover would have. The hook script receives the response and the agent proceeds — same path as a popover button press.

The firmware bundles considerably more UI than the desktop drives — clock face with rotation detection, settings menu, six info pages, an 18-species ASCII renderer, GIF character support from LittleFS, sleep/wake/battery, BLE pairing with on-screen passkey. Of the firmware's wire schema, two fields are currently allocated but never sent by the desktop (`promptHint`/`promptSource`/`promptLabel` for the approval card; `entries[]` for the rolling transcript) — see BUGS.md N1, N2.

## State Model

The reducer is pure — no I/O, no time lookups. All timing arrives via event `at` fields.

```
BuddyState
├── version: Int             Monotonic, +1 per change
├── updatedAt: Double        Epoch ms
├── desktop: DesktopLink     Connection status + last heartbeat
├── sessions: SessionCounts  Total / running / waiting counts
├── prompt: Prompt?          Current tool approval request
│   ├── isApproval: Bool     If true, popover shows Approve/Deny buttons and blocks the hook
│   └── ...                  id, tool, hint, arrivedAt, sessionLabel, source
├── pet: Pet
│   ├── state: PetState      sleep | idle | busy | attention | celebrate
│   └── species: String      "cat", "axolotl", "robot", "capybara", "dragon"
├── celebrateUntil: Double?  Epoch ms — reverts to idle when expired
├── lastTaskDurationMs: Double?  Ms between start_working and celebrate
├── msg: String              Latest formatted message
├── entries: [String]        Activity log (last 10)
└── lastSignal: String?      Last activity signal kind
```

### Pet State Priority

1. **attention** — prompt waiting for user approval (highest)
2. **busy** — start_working / keep_working signal
3. **celebrate** — time-limited (4s default), then reverts to idle
4. **idle** — stop_working signal, or default when connected
5. **sleep** — no agents connected (lowest)

## Data Flow

### Tool Approval — passive mode (default)

When local approval mode is off, tool approvals are read-only notifications:

1. Agent fires PermissionRequest/Notification hook → spawns the bash hook script (Claude Code / Codex) or `BuddygotchiSignal` (Cursor)
2. Script POSTs to `http://localhost:21321/hook/event` (or, for Cursor's `before*` hooks, the Signal CLI emits a `keep_working` signal to `/hook/signal`)
3. HookServer creates `requestArrived` (or `activitySignal`) event
4. Engine applies event through reducer → BuddyState updates (pet → attention or busy)
5. All registered outputs receive `stateDidChange`
6. PopoverView shows tool card (read-only); ESP32Output sends heartbeat over BLE
7. Hook exits immediately — agent shows its own permission dialog

### Tool Approval — local approval mode (blocking)

When the "Local Approval Mode" toggle is on in Settings, the app becomes the approval UI:

**Claude Code / Codex** — uses `PermissionRequest` hook (only fires when permission is needed):

1. Agent fires `PermissionRequest` → exec's `~/.buddygotchi/buddygotchi-hook.sh`
2. Script reads `~/.buddygotchi/config.json`, sees `"approvalMode": true`
3. Script `curl`s `/hook/approve?source=<agent>&pid=$$` and **blocks** (300s budget)
4. HookServer calls `engine.submitApproval()` → stores a `CheckedContinuation`, dispatches `approvalArrived` event
5. BuddyState updates (pet → attention, prompt with `isApproval: true`)
6. PopoverView auto-shows with Approve/Deny buttons (only when Interactive Mode is on); the M5Stack also shows the prompt and arms its A/B buttons
7. User clicks Approve in the popover **or** presses A on the device → `engine.resolveApproval()` resumes the continuation
8. `/hook/approve` returns `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
9. Hook script echoes response to stdout, exits 0 → agent proceeds

**Cursor** — uses `beforeShellExecution` / `beforeMCPExecution` (fires for all operations):

1. Agent fires `beforeShellExecution` → spawns `BuddygotchiSignal`
2. CLI reads config, sees `approvalMode: true` and event is in `{beforeShellExecution, beforeMCPExecution}`
3. CLI POSTs to `/hook/approve` and blocks (300s timeout)
4. Server runs the auto-approve allowlist — read-only tools (`Read`, `Glob`, `Grep`, `LSP`, `WebFetch`) auto-allow; safe shell verbs (`ls`, `cat`, `git status`, …) auto-allow only if the command contains no shell control characters; everything else falls through to manual approval
5. Manual approvals run the same UI/device path as Claude Code
6. Response shape: `{"permission":"allow"}` or `{"permission":"deny", "user_message":..., "agent_message":...}`

**Toggle mechanics**: `approvalMode` lives in `~/.buddygotchi/config.json`. Hook scripts read it on every invocation — no reinstall needed to toggle. The installer registers `PermissionRequest` with a 600s timeout (vs. 5s default) so a paused approval doesn't time out before the user gets back to it.

**Fail-open safety**: If the app is not running, curl fails, the hook script exits 0 with no stdout, and the agent falls back to its built-in dialog. If the user doesn't respond within 5 minutes, curl times out with the same result. If the toggle is turned off while approvals are pending, `resolveAllPendingApprovals(.allow)` releases every waiting continuation so no hook hangs.

### Activity Signals (non-blocking)

1. Agent fires lifecycle hook → spawns the bash script (Claude Code / Codex `/hook/event`) or `BuddygotchiSignal` (Cursor `/hook/signal`)
2. The script/binary maps the hook event → signal kind (`start_working`, `keep_working`, `stop_working`, `celebrate`, or the special-cased `session_end` for Cursor)
3. POSTs to `/hook/event` or `/hook/signal`, exits immediately
4. Engine applies the corresponding event → pet state changes
5. Outputs update

## Key Invariants

1. **Monotonic version** — `BuddyState.version` increases by exactly 1 per state change
2. **Pure reducer** — deterministic given the same event sequence; continuations live on the engine, not in the reducer
3. **Fail-open** — if the app is down or nobody decides in time, hooks return empty stdout and agents fall back to their built-in dialog
4. **Signals never block** — the signal endpoint fires-and-forgets
5. **Approvals block exactly once** — each `/hook/approve` request gets one `CheckedContinuation`, resumed by user action, toggle-off, or session cleanup
6. **Stale cleanup** — process monitoring (via `DispatchSource`) reaps sessions instantly when the parent process exits; 10-minute timeout serves as fallback

## Multi-Session Behavior

When multiple agents are connected simultaneously, the engine aggregates across all sessions:

- **Pet state** is the highest-priority state across all sessions (attention > busy > celebrate > idle)
- **Prompt selection** shows the oldest pending request when multiple sessions need attention
- **Session counts** track total, running (working + waiting), and waiting independently
- **Celebrate** fires when any session sends a celebrate signal, but busy/attention from other sessions override it

Edge cases the engine handles:

- **Duplicate session start** — idempotent; updates timestamp without creating a second session
- **End nonexistent session** — no-op; the reducer returns unchanged state, no output notification
- **Clear request without pending** — no-op
- **Session dies mid-approval** — process watcher detects exit, resumes the pending continuation with `allow`, cleans up the session
- **Toggle off during pending approvals** — `resolveAllPendingApprovals(.allow)` resumes every waiting continuation so no hook hangs

## Testing

Four test layers, plus an opt-in snapshot harness and an HTTP-level smoke runner:

**Reducer tests** (`Tests/ReducerTests.swift`, 21 tests) — test the pure `reduce()` function directly. Events carry explicit timestamps, so timing-sensitive behavior (celebrate expiry, stale timeout) is fully deterministic. No engine, no outputs, no I/O. Includes regressions for the species default (`testDefaultSpeciesIsAKnownSpecies`), the displayed-prompt source label (`testMsgUsesDisplayedPromptSourceNotArbitrarySession`), and the post-resolve `msg` clear (`testMsgClearsWhenPromptResolves`).

**Integration tests** (`Tests/EngineIntegrationTests.swift`, 34 tests) — test the full path through the engine: call the same public methods the HTTP server calls, observe state changes via an `EchoRecorder` output. This verifies the wiring between inputs, reducer, and outputs without touching the network.

**Auto-approve tests** (`Tests/AutoApproveTests.swift`, 5 tests) — pin the Cursor-only allowlist behavior, including the hardening that rejects shell control characters before consulting safe-command regexes (so `ls; rm -rf ~` never auto-approves).

**Snapshot harness** (`Tests/SnapshotHarnessTests.swift`, disabled by default) — renders the real SwiftUI views (`PopoverView`, `SettingsView`, `PetStageView`) in driven engine states to PNGs under `/tmp/buddy-snapshots/` via `NSHostingView`, and exercises the approval flow as a closed loop (drive → render the Approve/Deny card → invoke the button's action → re-render). Skipped on CI; enable with `mkdir -p /tmp/buddy-snapshots && touch /tmp/buddy-snapshots/.enable`.

The `EchoRecorder` is a minimal `OutputProvider` that records every `(prev, next)` state transition. Tests assert on the recorder's captured transitions — what pet state resulted, whether a prompt appeared, whether session counts changed. Because the recorder sits at the output boundary, tests are decoupled from internal state representation.

A `Clock` protocol (with `WallClock` for production, `MockClock` for tests) lets integration tests control time — advancing the clock and triggering stale ticks to verify celebrate expiry and session cleanup without real-time delays.

**End-to-end smoke** (`app/tools/e2e-smoke.sh`, plus per-agent suites under `app/tools/e2e/`) — bash scripts that exercise the live HTTP server with each agent's documented hook payloads, including a `parked_approve` helper that verifies the blocking-approval round trip and the fail-open invariant (a session dying mid-approval resolves the hook to `allow`). Run against a running daemon in a real terminal, since the bash sandbox can't reach localhost.



| Layer | Technology |
|-------|-----------|
| Runtime | Swift 6.0 (macOS 14+) |
| UI | SwiftUI (menu bar popover) |
| HTTP Server | Hummingbird 2.0 |
| BLE | CoreBluetooth (Nordic UART Service) |
| State | Immutable reducer pattern (@Observable) |
| Firmware | C++/Arduino via PlatformIO (M5StickC Plus 2) |
