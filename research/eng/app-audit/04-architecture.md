# 04 — Architecture: Keep the Core Pure, Fix the Edges

Goal: preserve the (good) `hooks → HookServer → BuddyEngine → reducer → OutputProvider` spine while fixing the places where state leaks around it, cleanup paths make unsafe decisions, and polling substitutes for events. Includes the P0 approval-safety fix.

## What's healthy (leave alone)

- Pure reducer with injected time; `InternalState` vs `BuddyState` projection split; event-first modeling; the aggregation priority ladder.
- Test pyramid: ReducerTests / EngineIntegrationTests / AutoApproveTests / snapshot harness, with small honest doubles (`MockClock`, `EchoRecorder`).
- `OutputProvider` as the output seam; `RenderState` as an explicit wire contract.
- Hummingbird server as a thin input adapter.

## 1. Desktop UI should be an `OutputProvider`, not a 0.5 s poll

`AppDelegate.tick()` polls the engine every 500 ms to diff icon/sounds/notifications/interactive-mode against `previousPetState`. Problems:

- A state that changes twice within one tick (attention → busy → attention) is missed — no sound, no notification.
- The comparison logic duplicates what `stateDidChange(prev:next:)` already provides for free.
- A wake-every-500 ms timer forever is hostile to App Nap / battery for an ambient app.

Fix: new `app/Buddygotchi/Outputs/Desktop/DesktopOutput.swift` implementing `OutputProvider`, registered in `AppDelegate` alongside `ESP32Output`. It receives every `(prev, next)` pair and owns:

- status-item icon updates (`prev.pet.state != next.pet.state`),
- transition sounds (exact edge, not sampled),
- notification post/clear (`prev.prompt?.id != next.prompt?.id`),
- interactive-mode auto-show/dismiss (callbacks into `AppDelegate` for popover control — inject a small `PopoverPresenting` protocol so `DesktopOutput` stays testable with a mock).

Delete `iconTimer`, `tick()`, `previousPetState`, `lastPromptId`, `lastIconSymbol` from `AppDelegate` (it shrinks to lifecycle + window plumbing). Add an `EngineIntegrationTests` case asserting a rapid attention→busy→attention sequence produces two notification posts through a mocked presenter.

Note: the engine's `staleTimer` (2 s) stays — that's a legitimate clock input to the reducer, and it already early-outs when idle.

## 2. Single sources of truth

### 2.1 `approvalMode` lives in three places

Today: `~/.buddygotchi/config.json` (read by hook script + SignalCLI), `UserDefaults("approvalMode")` (written at launch from config, toggled by Settings, read by `HookServer`'s Notification handler), and `BuddyConfig.approvalMode` (frozen at process start). Drift is possible and `HookServer` reaching into `UserDefaults` couples the input adapter to the UI layer.

Fix: an `@Observable ConfigStore` (main-actor) that owns `config.json`:

```swift
@MainActor @Observable final class ConfigStore {
    private(set) var port: Int
    private(set) var approvalMode: Bool
    func setApprovalMode(_ on: Bool)   // writes file atomically (05 §2), updates property
    // optional: DispatchSource file watcher so external edits reflect live
}
```

- `SettingsView` binds to it; `HookServer` receives it (or just the values it needs) at build time instead of touching `UserDefaults`; the launch-time mirror write in `AppDelegate` goes away; `@AppStorage("approvalMode")` in Settings is replaced by the store.
- `BuddyConfig` stays as the immutable startup snapshot for engine timings; runtime-mutable knobs move to `ConfigStore`.

### 2.2 Species belongs in state

`BuddyState.pet.species` is permanently `"cat"`; the UI reads `@AppStorage("buddySpecies")` directly and `Heartbeat.renderState` patches over it by reading `UserDefaults` inside the output mapper — a core-purity leak and a lie in the state (`EchoRecorder`-based tests see the wrong species).

Fix: add `case speciesChanged(at: Double, species: String)` to `BuddyEvent`; reducer sets `buddy.pet.species`. Engine gets `func setSpecies(_:)`. `AppDelegate` applies the persisted value at startup; the Settings/onboarding pickers call the engine *and* persist to defaults. Delete the `UserDefaults` read in `Heartbeat.swift`. Same pattern later for `buddyName` if it goes on the wire.

## 3. Correctness & safety fixes

### 3.1 (P0) Pending approvals must never silently auto-allow

Three paths currently resolve a blocked approval with `.allow` without a human decision:

1. `BuddyEngine.apply` — when a session is removed (process watcher fired, explicit `SessionEnd`, or **stale reap after 10 min**), its pending approval continuation resumes `.allow`.
2. `SettingsView` — toggling Local Approval Mode off calls `resolveAllPendingApprovals(decision: .allow)`.
3. By extension any future cleanup that reuses these.

"Allow" is not fail-open — it *executes the tool call*. Fail-open means "Buddygotchi has no opinion; let the agent's native flow decide." The hook protocols support exactly that:

- Claude Code / Codex `PermissionRequest` hook: exiting with **no stdout** (or an output without a decision) falls back to the agent's own permission prompt.
- Cursor `beforeShellExecution` / `beforeMCPExecution`: the permission field supports `"ask"` (fall back to Cursor's own dialog) — verify against current Cursor docs (`research/external_sites/cursor_hooks.md`) and use it; if unavailable, `deny` with an explanatory `agent_message` is the safe fallback.

Implementation:

```swift
enum ApprovalDecision: String, Sendable {
    case allow, deny
    case passthrough   // "no opinion" — agent-native flow takes over
}
```

- `HookServer.approvalResponse`: for `passthrough` → Cursor: `{"permission":"ask"}`; Claude/Codex: return an **empty 200 body**. The hook script already prints stdout only when non-empty (`[ -n "$RESPONSE" ]`), so an empty body yields no stdout → native fallback. Verify end-to-end with `app/tools/e2e/claude.sh`.
- Replace both cleanup paths with `.passthrough`. The reducer's `handleApprovalResolved` treats `passthrough` like `deny` for session state (→ `.idle`, prompt cleared) — the agent will re-drive state.
- UI never offers passthrough; it's cleanup-only.
- Tests: engine test — session with pending approval reaped by stale tick → continuation resolves `.passthrough`; server-level test of the empty-body encoding.

### 3.2 Session reverse-lookup can mis-identify sessions

`aggregate()` maps a `Session` value back to its id with `sessions.first(where: { $0.value == sess })?.key`. Two sessions with identical field values (e.g. two idle Cursor sessions created in the same millisecond with no cwd) resolve to the *same* id → duplicate `SessionSnapshot.id`s (breaks `ForEach` identity) and a mistargeted `dismissError`. Fix mechanically: iterate `state.sessions` as `(id, session)` pairs from the start instead of value-matching — build `waitingOrdered` etc. from `[(String, Session)]` and carry ids through. Also removes the accidental O(n²).

### 3.3 `hashCwd` is unstable across launches

`String.hashValue` is seeded per-process; the fallback session id `"\(source)_\(hashCwd(cwd))"` changes across app restarts, so an agent surviving an app restart re-registers as a new session. Use a stable digest: `SHA256.hash(data:)` prefix (import `Crypto`/`CryptoKit`), first 8 hex chars.

### 3.4 Lazy `CBCentralManager` (shared with 01 §4)

`BLEManager.init` constructs the central → Bluetooth permission dialog at first launch for everyone. Make the central lazily created on first scan/connect; `ESP32Output.start` already only connects when a saved UUID exists.

### 3.5 Process-watcher ancestry is a guess

`resolveAncestor` walks exactly two parents (hook → shell → app). If an agent changes its spawn depth, the watcher binds to the wrong process — worst case a long-lived ancestor (session never reaped) or a short-lived one (session killed mid-work). Harden: after walking, read the ancestor's name (`proc_name`/`proc_pidpath`) and only install the watcher if it looks like an agent process (`claude`, `node`, `cursor`, `codex`, `bun`…); otherwise walk one more level or skip (stale reaping still covers cleanup). Log the resolved name to diagnostics for field debugging.

### 3.6 Timeout ladder is inconsistent

Hook-side curl `--max-time 300` vs Claude/Codex hook config `timeout: 600` vs stale reap 600 s. Effective ceiling is 300 s, after which the hook exits (native fallback) but the app still shows a pending card until the 10-min reap — a ghost prompt for up to 5 minutes that, if answered, goes nowhere. Fix: pick one number (300 s), set hook config timeouts to ~310, and add a reducer rule: approval prompts expire at 300 s (`staleTick` clears prompts older than `approvalTimeoutMs`, resolving `.passthrough`). Config knob in `BuddyConfig`.

### 3.7 Assorted

- `BLEScanner.start()` builds a fresh `BLEManager` (and central) per scan; reuse one scanner-owned manager, or expose scanning from the existing `ESP32Output` manager to keep a single central. (Multiple centrals work but multiply permission/state edge cases.)
- `HookServer` builds responses via `JSONSerialization` dictionaries — move to small `Encodable` structs for compile-time safety of the agent wire formats (they're contracts; today a typo like `"behaviour"` would compile).
- `DiagnosticLog` stores `rawPayload` of every hook (may include prompts/commands/paths). Bug-report export is user-initiated, but the bundle should say so: include a `"note": "may contain file paths and commands from your sessions"` field, and cap rawPayload retention (e.g. keep raw only for the last 20 entries).
- `formatDuration` lives in `BuddyReducer.swift` but is used by views — move to a shared `Formatting.swift`.
- `PopoverView.swift` (643 lines) holds five card views — split into `Views/Cards/{ToolCard,ReviewCard,ErrorCard,ThinkingRow,SessionList}.swift`. Pure file moves.
- `Package.swift` embeds Info.plist via `-sectcreate` — fine for `swift run`, superseded by real bundling (06 §1); keep both paths working.

## 4. Test gaps to close

- **HookInstaller has zero tests** and is the highest-blast-radius file-writing code in the app. Refactor for testability: give `HookInstaller` an injected root directory (`init(homeDirectory: URL = FileManager…)`) replacing the file-private `homeDir` global, then add `HookInstallerTests` with a temp dir covering: fresh install per agent, idempotent re-install, uninstall restores original content, **corrupted-JSON refusal** (05 §2), legacy-hook migration, and Codex TOML flag insertion in all three shapes (no file / `[features]` exists / flag exists).
- Server-level tests: run `buildHookServer` against an in-process engine (Hummingbird supports test clients) for `/hook/event` happy paths per agent payload shape, `/hook/approve` auto-approve short-circuit, and the `passthrough` empty-body encoding (§3.1).
- Engine tests for: stale-reap `passthrough` resolution, `speciesChanged`, prompt-expiry rule (§3.6).
- CI (`.github/workflows/ci.yml`) already builds + tests on macOS-15; add `swift build -c release` (catches release-only concurrency diagnostics) and, once 06 lands, the packaging script in dry-run.

## Acceptance criteria

- `AppDelegate` contains no repeating UI timer; sounds/notifications/icon verified via `DesktopOutput` unit tests with a mock presenter.
- Disabling approval mode with a pending `rm -rf` prompt results in the agent's native permission dialog appearing (manual e2e with Claude Code), not execution.
- `rg 'UserDefaults' app/Buddygotchi/Outputs app/Buddygotchi/Server app/Buddygotchi/Core` returns nothing (defaults confined to UI + ConfigStore + explicitly-allowed persistence like the firmware cache).
- Two identical concurrent sessions render as two rows with distinct ids.
- All new/changed reducer behavior has ReducerTests; `swift test` green.
