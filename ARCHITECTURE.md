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
- **Hardware output** — optionally drive an M5Stack display over Bluetooth, showing pet state and approval prompts on a dedicated device
- **Setup wizard** — first-run onboarding detects installed agents, installs hooks automatically, and lets you pick your buddy and output target
- **Fail-open safety** — if the app is down or nobody responds in time, hooks return "ask" and the agent's native permission dialog takes over; the system never silently blocks or allows

## What it does NOT do

- **No cloud/internet** — everything is localhost only
- **No persistent history** — activity log is in-memory and resets on restart
- **No per-tool rules** — Claude Code/Codex approvals mirror the agent's own permission logic; Cursor has built-in regex auto-approve for safe read-only commands
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
│       │  Hook CLI       │  Hook CLI +    │  Hook CLI            │
│       │  (stdin→HTTP)   │  Signal CLI    │  (stdin→HTTP)        │
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
│   ├── Config.swift         Configuration
│   └── Protocols.swift      OutputProvider contract
│
├── Server/              HTTP input (Hummingbird)
│   └── HookServer.swift   Routes hook/signal requests → engine events
│
├── Views/               SwiftUI display output
│   ├── PopoverView.swift      Menu bar popover (pet + status + tool card)
│   ├── PetStageView.swift     Animated ASCII pet renderer
│   ├── SetupWizardView.swift  First-run setup wizard
│   └── SettingsView.swift     Preferences panel
│
├── Theme/               Design system
│   └── BuddyTheme.swift  Colors, card modifiers, button styles
│
├── Buddies/             Pet data
│   └── BuddySprites.swift ASCII art (5 species × 7 states, animation frames)
│
├── Outputs/ESP32/       BLE hardware output
│   ├── ESP32Output.swift    OutputProvider: state → BLE → M5Stack
│   ├── BLEManager.swift     CoreBluetooth central (Nordic UART Service)
│   └── Heartbeat.swift      Pure BuddyState → heartbeat JSON mapper
│
├── Notifications/       macOS notification output
│   └── NotificationManager.swift
│
└── Install/             Agent hook installer
    └── HookInstaller.swift

app/BuddygotchiHook/    Hook CLI (agent stdin → HTTP POST)
app/BuddygotchiSignal/  Signal CLI (lifecycle events → HTTP POST)
```

## Sources

Each coding agent connects through its native hook system. The agent spawns a CLI binary that reads the hook payload from stdin, POSTs it to the Buddygotchi HTTP server, and writes the response to stdout.

| Agent | Hook Config | CLI Binary | Events |
|-------|------------|------------|--------|
| **Claude Code** | `~/.claude/settings.local.json` | BuddygotchiHook + BuddygotchiSignal | PreToolUse (blocking), UserPromptSubmit/Stop/PostToolUse/TaskCompleted (signals) |
| **Cursor** | `.cursor/hooks.json` | BuddygotchiSignal | beforeShellExecution, preToolUse (blocking) |
| **Codex** | `~/.codex/hooks.json` | BuddygotchiSignal | PreToolUse (blocking) |

### How Each Agent Integrates

**Claude Code** has the richest hook surface. Key events used:

| Hook Event | Buddy Signal |
|-----------|-------------|
| `UserPromptSubmit` | start working |
| `PostToolUse` / `SubagentStart` | keep working |
| `Stop` / `StopFailure` | stop working |
| `TaskCompleted` | celebrate |
| `PermissionRequest` | needs attention (blocking — waits for approval) |
| `Notification:permission_prompt` | needs attention |
| `SessionStart` / `SessionEnd` | register / deregister session |

Claude Code supports both `command` and `http` hook handler types. Buddygotchi uses `command` handlers (the CLI binaries) that POST to the local HTTP server. Non-blocking hooks return immediately; `PermissionRequest` blocks until the user approves or denies via the popover.

**Cursor** hooks cover agent lifecycle and tool execution:

| Hook Event | Buddy Signal |
|-----------|-------------|
| `beforeSubmitPrompt` | start working |
| `afterShellExecution` / `afterMCPExecution` | keep working |
| `stop` | stop working |
| `beforeShellExecution` / `beforeMCPExecution` | needs attention (returns `allow`/`deny`/`ask`) |
| `sessionStart` / `sessionEnd` | register / deregister session |

Cursor does not have a dedicated "permission dialog opened" event — the approval state is inferred from `beforeShellExecution`/`beforeMCPExecution` hooks, which can return a permission decision.

**Codex** hooks are more limited (experimental, 5 events):

| Hook Event | Buddy Signal |
|-----------|-------------|
| `UserPromptSubmit` | start working |
| `Stop` | stop working |
| `SessionStart` | register session |

Codex does not currently fire hooks on permission prompts. The `needs_user_confirmation` state is not available via Codex hooks alone.

### Known Integration Gaps

- Cursor infers approval state from `before*` hooks rather than a dedicated permission event; auto-approve regex handles the noise
- All hooks are fail-open: if the app is down, the agent's native UI takes over

## Outputs

All outputs conform to the `OutputProvider` protocol and receive `stateDidChange(prev:next:)` on every state transition. They are registered with `engine.register(output:)` at startup.

| Output | Description |
|--------|-------------|
| **Menu Bar UI** | SwiftUI popover with animated ASCII pet, connection status, tool approval card |
| **Notifications** | macOS notifications for tool-call alerts when the popover is closed |
| **ESP32 (BLE)** | Bridges heartbeat JSON to M5Stack over Nordic UART Service |

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

1. Agent fires PermissionRequest/Notification hook → spawns Hook CLI
2. Hook CLI reads stdin JSON, POSTs to `http://localhost:21321/hook/event`
3. HookServer creates `requestArrived` event
4. Engine applies event through reducer → BuddyState updates (pet → attention)
5. All registered outputs receive `stateDidChange`
6. PopoverView shows tool card (read-only); ESP32Output sends heartbeat over BLE
7. Hook exits immediately — agent shows its own permission dialog

### Tool Approval — local approval mode (blocking)

When the "Local Approval Mode" toggle is on in Settings, the app becomes the approval UI:

**Claude Code / Codex** — uses `PermissionRequest` hook (only fires when permission is needed):

1. Agent fires `PermissionRequest` → spawns hook script
2. Hook script reads `~/.buddygotchi/config.json`, sees `approvalMode: true`
3. Hook script POSTs to `/hook/approve` and **blocks** waiting for response
4. HookServer calls `engine.submitApproval()` → stores a `CheckedContinuation`, dispatches `approvalArrived` event
5. BuddyState updates (pet → attention, prompt with `isApproval: true`)
6. PopoverView auto-shows with Approve/Deny buttons
7. User clicks Approve → `engine.resolveApproval()` resumes the continuation
8. `/hook/approve` returns `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`
9. Hook script echoes response to stdout, exits 0 → agent proceeds

**Cursor** — uses `beforeShellExecution` / `beforeMCPExecution` (fires for all operations):

1. Agent fires `beforeShellExecution` → spawns BuddygotchiSignal CLI
2. CLI reads config, sees `approvalMode: true` and event is an approval event
3. CLI POSTs to `/hook/approve` and blocks
4. Server checks auto-approve regex — safe commands (`ls`, `cat`, `git status`, etc.) return `{"permission":"allow"}` immediately
5. Dangerous commands go through the same UI flow as Claude Code
6. Response: `{"permission":"allow|deny"}`

**Toggle mechanics**: `approvalMode` lives in `~/.buddygotchi/config.json`. Hook scripts read it on every invocation — no reinstall needed to toggle. One initial reinstall bumps `PermissionRequest` timeout from 5s → 600s.

**Fail-open safety**: If the app is not running, curl fails, the hook script exits 0 with no stdout, and the agent falls back to its built-in dialog. If the user doesn't respond within 5 minutes, curl times out with the same result. If the toggle is turned off while approvals are pending, all continuations resolve with `allow`.

### Activity Signals (non-blocking)

1. Agent fires lifecycle hook → spawns Signal CLI
2. Signal CLI maps hook event → signal kind (start_working, keep_working, stop_working, celebrate)
3. POSTs to `/hook/signal`, exits immediately
4. Engine applies `activitySignal` event → pet state changes
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

Two layers of tests, each with a clear boundary:

**Reducer tests** (`Tests/ReducerTests.swift`) — test the pure `reduce()` function directly. Events carry explicit timestamps, so timing-sensitive behavior (celebrate expiry, stale timeout) is fully deterministic. No engine, no outputs, no I/O.

**Integration tests** (`Tests/EngineIntegrationTests.swift`) — test the full path through the engine: call the same public methods the HTTP server calls, observe state changes via an `EchoRecorder` output. This verifies the wiring between inputs, reducer, and outputs without touching the network.

The `EchoRecorder` is a minimal `OutputProvider` that records every `(prev, next)` state transition. Tests assert on the recorder's captured transitions — what pet state resulted, whether a prompt appeared, whether session counts changed. Because the recorder sits at the output boundary, tests are decoupled from internal state representation.

A `Clock` protocol (with `WallClock` for production, `MockClock` for tests) lets integration tests control time — advancing the clock and triggering stale ticks to verify celebrate expiry and session cleanup without real-time delays.



| Layer | Technology |
|-------|-----------|
| Runtime | Swift 6.0 (macOS 14+) |
| UI | SwiftUI (menu bar popover) |
| HTTP Server | Hummingbird 2.0 |
| BLE | CoreBluetooth (Nordic UART Service) |
| State | Immutable reducer pattern (@Observable) |
| Firmware | C++/Arduino via PlatformIO (M5StickC Plus) |
