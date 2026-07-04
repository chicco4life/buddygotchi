# Architecture

Buddygotchi is a local-first macOS companion for AI coding agents. The active product is a Swift menu bar app that receives agent hook events over localhost HTTP, reduces them into one `BuddyState`, renders that state in SwiftUI, and optionally mirrors it to ESP32 firmware over BLE.

The important architectural boundary is:

```text
agent hooks -> HTTP input adapters -> BuddyEngine -> pure reducer -> output providers
```

Inputs normalize external payloads. Core owns state transitions. Outputs render or relay state. That separation is what keeps agent-specific quirks, UI code, and hardware transport from leaking into the reducer.

## Current Runtime

| Area | Implementation |
| --- | --- |
| macOS app | Swift 6, SwiftUI, AppKit menu bar status item |
| HTTP server | Hummingbird on `127.0.0.1:21321` by default |
| State management | `@Observable` `BuddyEngine` plus pure `reduce(_:_:)` |
| Agent hooks | Generated bash hook for Claude Code/Codex, Swift signal CLI for Cursor |
| Desktop output | SwiftUI popover, AppKit status icon, macOS notifications and sounds |
| Hardware output | CoreBluetooth central talking Nordic UART Service to M5StickC Plus 2 firmware |
| Tests | XCTest unit/integration tests, opt-in SwiftUI snapshot harness, shell e2e smoke scripts |

The legacy Bun/TypeScript daemon and browser prototype have been removed. The ESP32 firmware under `firmware/esp32/` is active.

## Repository Map

```text
app/
  Package.swift
  Buddygotchi/
    App/                  app delegate, menu bar lifecycle, signal handling
    Core/                 reducer, state, events, config, diagnostics, protocols
    Server/               Hummingbird routes for hook input
    Install/              agent hook installer and generated hook script
    Views/                SwiftUI popover, settings, setup wizard, cards
    Buddies/              ASCII sprite definitions
    Theme/                shared SwiftUI styling
    Notifications/        macOS notification output
    Outputs/ESP32/        BLE output, heartbeat mapper, OTA updater
  BuddygotchiSignal/      Cursor hook stdin -> localhost HTTP bridge
  Tests/                  XCTest suites and snapshot harness
  tools/                  e2e HTTP smoke tests

landing/                    Next.js landing page and waitlist API

firmware/esp32/             active ESP32 firmware, PlatformIO project, hardware tools

docs/                       architecture, planning, product, marketing, and references
```

## End-To-End Flow

```text
Claude Code / Cursor / Codex
        |
        | native hook payload on stdin
        v
hook script or BuddygotchiSignal
        |
        | localhost HTTP
        v
HookServer
  POST /hook/event
  POST /hook/signal
  POST /hook/approve
  GET  /healthz
        |
        v
BuddyEngine
  - owns pending approval continuations
  - owns process watchers
  - owns output registrations
  - applies BuddyEvent values
        |
        v
BuddyReducer
  InternalState + BuddyEvent -> InternalState
        |
        v
BuddyState projections
        |
        +--> SwiftUI popover and status icon
        +--> macOS notifications and sounds
        +--> DiagnosticLog export bundle
        +--> ESP32 heartbeat JSON over BLE
```

## Agent Inputs

All agent integrations are intentionally fail-open. If Buddygotchi is not running or localhost cannot be reached quickly, the hook exits successfully and the agent's native permission flow continues.

### Claude Code

`HookInstaller.installClaudeCode()` writes nested command hooks into `~/.claude/settings.json`. The command points to `~/.buddygotchi/buddygotchi-hook.sh claude-code`.

Installed events:

- `SessionStart`
- `UserPromptSubmit`
- `Stop`
- `StopFailure`
- `SessionEnd`
- `PostToolUse`
- `Elicitation`
- `ElicitationResult`
- `PermissionRequest`
- `Notification` matchers: `permission_prompt`, `idle_prompt`, `elicitation_dialog`

The generated bash script reads `~/.buddygotchi/config.json` every time. If `approvalMode` is true and the hook is `PermissionRequest`, it calls `/hook/approve` with a long timeout and prints Buddygotchi's response to stdout. Otherwise it posts to `/hook/event` with a short timeout and returns no stdout.

`SessionStart` includes a `pid` query parameter. `BuddyEngine` walks from hook PID to the agent process and creates a `DispatchSourceProcess` watcher so sessions are reaped when the parent exits.

### Codex

`HookInstaller.installCodex()` writes `~/.codex/hooks.json` and ensures this feature flag exists in `~/.codex/config.toml`:

```toml
[features]
codex_hooks = true
```

Installed events:

- `SessionStart` with matcher `startup|resume`
- `UserPromptSubmit`
- `PermissionRequest`
- `PreToolUse`
- `PostToolUse`
- `Stop`

Codex shares the same generated bash hook script as Claude Code, using `source=codex`.

### Cursor

`HookInstaller.installCursor()` writes `~/.cursor/hooks.json` with commands that run `BuddygotchiSignal --agent cursor`.

Installed events:

- `sessionStart`
- `sessionEnd`
- `beforeSubmitPrompt`
- `stop`
- `beforeShellExecution`
- `beforeMCPExecution`
- `afterShellExecution`
- `afterMCPExecution`

The signal CLI maps Cursor lifecycle events to `/hook/signal`. When local approval mode is on, `beforeShellExecution` and `beforeMCPExecution` are routed to `/hook/approve` and block for a decision. Cursor always receives `{"permission":"allow"}` for non-blocking signal hooks so its own flow can continue.

Cursor does not provide a dedicated "permission prompt opened" event. In passive mode, before/after tool hooks only keep Buddygotchi busy. In approval mode, `/hook/approve` first runs the auto-approval allowlist.

## HTTP Routes

| Route | Purpose |
| --- | --- |
| `GET /healthz` | Returns `ok`, state version, and desktop status |
| `POST /hook/event?source=...&pid=...` | Non-blocking hook events from Claude Code/Codex |
| `POST /hook/signal` | Lightweight lifecycle/activity signals from Cursor |
| `POST /hook/approve?source=...` | Blocking approval request path for Cursor, Claude Code, and Codex |

`HookServer` is an input adapter. It decodes payloads, derives session IDs, extracts tool hints, records diagnostics, and calls `BuddyEngine`. It should not own durable state.

## Core State Model

The reducer is pure. It receives all time as event `at` values and does not perform I/O, read clocks, touch user defaults, or call outputs.

`InternalState` contains:

- `buddy: BuddyState`
- `sessions: [String: Session]`
- stale session timeout
- celebrate duration
- work-stall timeout

`BuddyState` is the output projection used by UI and hardware:

- `version`, `updatedAt`
- `desktop` connection status and last heartbeat timestamp
- aggregate `sessions` counts
- `msg` current hardware-friendly line
- `entries` recent activity log, newest first, capped at 10
- `prompt` selected approval/passive request
- `pet` state and species
- `celebrateUntil` and `lastTaskDurationMs`
- `lastCompleted` review-card projection
- `firstErrored` error-card projection
- `firstThinking` thinking-card projection
- `activeSessions` compact per-session rows, capped at 6
- `currentActivityKind`

Session state is richer than the aggregate buddy state. A session tracks source, current state, prompt, working timestamps, last/current tool, hints, activity kind, and current working directory.

## Pet State Priority

Aggregation applies one visible pet state across all sessions:

1. disconnected -> `sleep`
2. any waiting prompt -> `attention`
3. any explicit failed session -> `error`
4. any actively working session -> `busy`
5. any silent-but-not-stale working session -> `thinking`
6. active celebrate window -> `celebrate`
7. otherwise connected -> `idle`

Live prompts intentionally outrank errors because the user can act on them immediately. Explicit errors outrank ordinary work. Thinking is not an error; it means a working session has been silent past `workStallTimeoutMs` but has not hit the stale-session reap threshold.

## Activity And Review Surfaces

`ActivityKind.swift` classifies tool + hint pairs into:

- `verify`
- `read`
- `write`
- `shell`
- `web`
- `work`

The classifier is stack-agnostic and pure. It powers popover icons, prompt metadata, completion review metadata, and the optional `activity` heartbeat field.

When work completes, `.celebrate` records a `CompletedTask` from the session's last tool/hint/source. The UI shows it as a review card after the celebrate animation, and the ESP32 `msg` line carries a compact `Done: <tool>` summary until new work or a new prompt clears it.

## Approval Model

`BuddyEngine.submitApproval(...)` applies an `approvalArrived` event and suspends with a `CheckedContinuation`. The continuation is stored by request ID in `pendingApprovals`.

Approvals can resolve from:

- SwiftUI popover approve/deny buttons
- ESP32 hardware buttons over BLE
- fail-open cleanup when a session disappears

`resolveApproval(requestId:decision:)` applies `approvalResolved`, resumes the continuation, and returns an agent-specific response:

- Cursor: `{"permission":"allow"}` or `{"permission":"deny", ...}`
- Claude Code/Codex: `hookSpecificOutput` with `PermissionRequest` decision behavior

Cursor has a conservative auto-approve path for read-only tools and simple read-only shell commands. Any shell control character such as `;`, `&`, `|`, backticks, `$`, parentheses, redirection, or newlines disables auto-approval.

## Outputs

Outputs conform to `OutputProvider`:

```swift
protocol OutputProvider {
    var id: String { get }
    func stateDidChange(prev: BuddyState, next: BuddyState)
}
```

### Menu Bar UI

`AppDelegate` owns the `BuddyEngine`, Hummingbird service group, status item, popover, ESP32 output, timers, and signal handlers.

The popover renders:

- animated ASCII buddy
- connection and session counts
- current activity row
- approval/passive prompt card
- thinking card
- error card with dismiss
- review card with dismiss
- per-session rows when more than one session is active
- settings and bug-report controls

The status icon follows `PetState.sfSymbol`. Sounds are transition-based: attention uses `Glass`, long celebrates use `Funk`, and error uses `Sosumi`. Interactive mode can auto-show the popover for attention and long celebrate transitions.

### Notifications

`NotificationManager` posts a macOS notification for a new prompt when the popover is closed and clears it once the prompt resolves.

### Diagnostic Log

`DiagnosticLog` is not a registered output, but the engine and server write structured diagnostic entries. Bug report export includes:

- state snapshot
- recent diagnostic entries
- agent install status
- recent OSLog entries when available

### ESP32 BLE Output

`ESP32Output` maps every `BuddyState` change to `RenderState` heartbeat JSON and writes it over Nordic UART RX. It also sends a 10 second keepalive of the last state.

Key outbound fields:

- `pet`, `species`, `desktop`
- `total`, `running`, `waiting`
- `msg`
- `promptId`, `promptTool`, `promptHint`, `promptSource`, `promptApproval`
- `lastCompletedTool`, `lastCompletedHint`, `lastCompletedSource`, `lastCompletedDurationMs`
- `errorTool`, `errorSource`
- `activity`
- `entries`
- `sessions`

Inbound BLE lines handled by `BLEManager`:

- `{"cmd":"permission","id":"...","decision":"allow|deny"}` resolves an approval
- `{"ack":"...","ok":true|false}` resolves OTA/status back-pressure waiters

On connect, the app sends time sync, sends the latest heartbeat, asks for firmware status, and checks for updates.

## Firmware OTA

`FirmwareUpdater` is owned by `ESP32Output` and survives popover presentation. The flow is:

1. Fetch firmware manifest through `FirmwareReleaseService`.
2. Download the binary and verify SHA-256.
3. Send `ota_begin`.
4. Stream chunks with one ack per chunk.
5. Send `ota_end`.
6. Treat disconnect/reboot as part of a successful update path when appropriate.

The manifest URL can come from `BUDDY_FIRMWARE_MANIFEST_URL` in the environment or Info.plist. Otherwise it falls back to the default GitHub Pages URL.

## Config And Local Files

Buddygotchi writes user-local state under `~/.buddygotchi/`:

- `config.json`: `port` and `approvalMode`
- `buddygotchi-hook.sh`: generated bash hook for Claude Code/Codex

Agent hook config files live in the agent's own config directory:

- `~/.claude/settings.json`
- `~/.cursor/hooks.json`
- `~/.codex/hooks.json`
- `~/.codex/config.toml`

The app also uses `UserDefaults` for UI preferences such as setup completion, selected species, interactive mode, paired ESP32 UUID, and firmware manifest cache.

## Testing Architecture

The main test pyramid is in `app/Tests/`.

| Suite | Scope |
| --- | --- |
| `ReducerTests` | Pure reducer behavior, state priority, review/error/thinking transitions, entries, activity classification |
| `EngineIntegrationTests` | Public `BuddyEngine` API, output notification, `MockClock`, `EchoRecorder`, approval continuations, heartbeat render projection |
| `AutoApproveTests` | Cursor auto-approve allowlist and shell-control rejection |
| `SnapshotHarnessTests` | Opt-in real SwiftUI rendering to PNG files in `/tmp/buddy-snapshots` |

The test doubles are intentionally small:

- `MockClock` supplies deterministic time to the engine.
- `EchoRecorder` implements `OutputProvider` and captures state transitions.
- Tests call public engine methods where possible and only use reducer internals for pure state-machine assertions.

Run normal tests:

```sh
cd app
swift test
```

Run one suite:

```sh
swift test --filter ReducerTests
swift test --filter EngineIntegrationTests
```

Run the snapshot harness:

```sh
mkdir -p /tmp/buddy-snapshots
touch /tmp/buddy-snapshots/.enable
swift test --disable-sandbox --filter SnapshotHarnessTests
```

HTTP e2e tests live in `app/tools/e2e-smoke.sh` and `app/tools/e2e/*.sh`. They require a real running app because sandboxed test shells may not be able to reach localhost.

```sh
cd app
swift run Buddygotchi
```

Then, from another terminal:

```sh
app/tools/e2e-smoke.sh
```

## Design Rules

- Keep core pure. Do not add I/O, clocks, randomness, user defaults, or UI imports to the reducer.
- Add new agent behavior in an input adapter or hook installer, then emit `BuddyEvent`.
- Add new displays by implementing `OutputProvider`.
- Keep approval fail-open unless the user explicitly chooses local approval and Buddygotchi returns a decision.
- Treat `RenderState` as the desktop-to-firmware contract. Adding fields is safe only when old firmware can ignore them.
- Preserve process/session cleanup paths. Cursor relies on explicit `session_end`; Claude Code/Codex additionally use process watchers.
- Prefer tests that pin state transitions before changing UI or transport code.
