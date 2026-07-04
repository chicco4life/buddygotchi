# Architecture

Buddygotchi is a local-first macOS companion for AI coding agents. The active
product is the Swift app in `app/`: agent hooks send localhost events, the app
reduces them into one `BuddyState`, desktop outputs render that state, and the
ESP32 output mirrors it to firmware over BLE.

The production boundary is:

```text
agent hooks -> HookServer -> BuddyEngine -> pure reducer -> OutputProvider
```

Inputs normalize external payloads. Core owns state transitions. Outputs render
or relay state. Agent-specific parsing, UI, persistence, clocks, BLE, and HTTP
do not belong in the reducer.

## Current Runtime

| Area | Implementation |
| --- | --- |
| macOS app | Swift 6 package, SwiftUI/AppKit menu bar app, macOS 14 minimum |
| HTTP server | Hummingbird on `127.0.0.1:21321` by default |
| Local auth | `X-Buddygotchi-Token` header for hook routes; token lives in `~/.buddygotchi/config.json` |
| State management | `@Observable` `BuddyEngine` plus pure `reduce(_:_:)` |
| Agent hooks | Generated bash hook for Claude Code/Codex; managed Swift `BuddygotchiSignal` helper for Cursor |
| Desktop output | `DesktopOutput` updates status icon, notifications, sounds, and interactive popover behavior from state changes |
| Hardware output | `ESP32Output` sends heartbeat JSON over CoreBluetooth Nordic UART Service |
| Firmware | ESP32/M5StickC Plus 2 renderer and device I/O under `firmware/esp32/` |
| Tests | XCTest in CI, local compile-only fallback when XCTest is unavailable, shell e2e, opt-in snapshots, HIL pytest |

## Repository Map

| Path | Role |
| --- | --- |
| `app/Buddygotchi/App/` | app delegate, menu bar lifecycle, Sparkle, uninstall |
| `app/Buddygotchi/Core/` | reducer, state, events, config, diagnostics, protocols |
| `app/Buddygotchi/Server/` | Hummingbird localhost input adapter |
| `app/Buddygotchi/Install/` | agent hook installer and generated hook script |
| `app/Buddygotchi/Views/` | popover, settings, onboarding, firmware update UI |
| `app/Buddygotchi/Outputs/` | desktop and ESP32 output providers |
| `app/BuddygotchiSignal/` | Cursor hook stdin -> localhost HTTP bridge |
| `app/Tests/`, `app/tools/` | XCTest, snapshots, e2e, packaging, appcast |
| `firmware/esp32/` | active ESP32 firmware, PlatformIO project, HIL tools |
| `docs/`, `research/eng/`, `landing/` | release/support docs, engineering docs, product site |

## End-To-End Flow

```text
Claude Code / Codex / Cursor
        |
        | hook payload on stdin
        v
~/.buddygotchi/buddygotchi-hook.sh
or ~/.buddygotchi/bin/buddygotchi-signal
        |
        | localhost HTTP + X-Buddygotchi-Token
        v
HookServer
  GET  /healthz
  POST /hook/event
  POST /hook/signal
  POST /hook/approve
        |
        v
BuddyEngine
  - owns pending approval continuations
  - owns process watchers
  - owns output registrations
        |
        v
BuddyReducer
  InternalState + BuddyEvent -> InternalState
        |
        v
BuddyState projection
        |
        +--> SwiftUI popover
        +--> DesktopOutput: status icon, notifications, sounds, auto-show/close
        +--> DiagnosticLog export bundle
        +--> ESP32Output: heartbeat JSON over BLE
```

## Local API And Config

`BuddyConfig.default` creates `~/.buddygotchi/config.json` with mode `0600`.
The current keys are:

| Key | Meaning |
| --- | --- |
| `port` | Localhost HTTP port. Default: `21321`. |
| `approvalMode` | Optional boolean. Missing means `false`. |
| `token` | 32 random bytes as 64 hex characters, generated with Security framework randomness when possible. |

`GET /healthz` is unauthenticated and returns `ok`, `stateVersion`, and
`desktop`. Every hook route requires `X-Buddygotchi-Token`; token comparison is
constant-time. Hook bodies are collected up to `1_048_576` bytes.

Settings keeps approval mode live in two places: `UserDefaults` key
`approvalMode` drives the server's provider closure, and
`BuddyConfig.setApprovalMode(_:)` writes `approvalMode` back to
`config.json`. The server does not need a restart when approval mode changes.

Default runtime timing comes from `Config.swift`:

| Constant | Value | Use |
| --- | ---: | --- |
| `staleTimeoutMs` | `600_000` | stale session reap after 600 seconds |
| `approvalTimeoutMs` | `300_000` | prompt/approval expiry after 300 seconds |
| `workStallTimeoutMs` | `300_000` | quiet working session becomes `thinking` after 300 seconds |
| `celebrateDurationMs` | `4_000` | celebrate window |
| engine stale timer | `2.0` seconds | periodic `staleTick` |

## Agent Inputs

All integrations are fail-open. If the app is down, the token is missing, or
the localhost call fails, the hook exits successfully and lets the agent's
native flow continue.

### Claude Code

`HookInstaller` writes nested command hooks to `~/.claude/settings.json`.
Plain hooks use timeout `5`; `PermissionRequest` uses timeout `310` so the
generated script can wait up to `300` seconds for `/hook/approve`.

Installed plain events are `SessionStart`, `UserPromptSubmit`, `Stop`,
`StopFailure`, `SessionEnd`, `PostToolUse`, `Elicitation`, and
`ElicitationResult`. Notification matchers are `permission_prompt`,
`idle_prompt`, and `elicitation_dialog`.

The generated script reads `port`, `token`, and `approvalMode` from
`config.json` on every invocation. With approval mode on, Claude
`PermissionRequest` events go to `/hook/approve?source=claude-code&pid=$$`;
other events go to `/hook/event?source=claude-code&pid=$$`.

### Codex

`HookInstaller` writes `~/.codex/hooks.json` and ensures
`codex_hooks = true` under `[features]` in `~/.codex/config.toml`. Installed
events are `SessionStart` with matcher `startup|resume`, `UserPromptSubmit`,
`PermissionRequest`, `PreToolUse`, `PostToolUse`, and `Stop`.

Codex uses the same bash hook as Claude, with `source=codex`.

### Cursor

`HookInstaller` writes `~/.cursor/hooks.json` and runs the managed helper at
`~/.buddygotchi/bin/buddygotchi-signal --agent cursor`. Installed events are
`sessionStart`, `sessionEnd`, `beforeSubmitPrompt`, `stop`,
`beforeShellExecution`, `beforeMCPExecution`, `afterShellExecution`, and
`afterMCPExecution`.

`BuddygotchiSignal` maps Cursor payloads to `/hook/signal` or `/hook/approve`.
The server still maps Cursor's legacy `stop_working` signal to `celebrate` so
old installed helpers keep producing completion cards.

Cursor auto-approval is intentionally conservative. `Read`, `Glob`, `Grep`,
`LSP`, and `WebFetch` can auto-allow. Shell hints can auto-allow only for the
small read-only command/pattern list, and any `;`, `&`, `|`, backtick, `$`,
parentheses, redirection, or newline requires manual review.

## Hook Health

Hook installation is versioned by `HookInstaller.hookSchemaVersion == 3`.
States are `notInstalled`, `installed`, `outdated(installed:current:)`, and
`corrupted(reason:)`.

Launch auto-repair runs in `AppDelegate.verifyManagedHooksAfterLaunch()`. It
checks every previously installed or currently detected agent. Outdated hooks
and repairable corruptions are reinstalled; non-repairable corruptions are
logged to diagnostics. Non-repairable reasons are invalid Claude
`settings.json`, invalid `hooks.json`, and unreadable hook script.

Every config write backs up the old agent file under
`~/.buddygotchi/backups`, keeping the latest 3 backups per agent/path prefix.
Cursor's helper is copied from the packaged `BuddygotchiSignal` executable into
`~/.buddygotchi/bin/buddygotchi-signal` and verified executable.

## HTTP Routes

| Route | Source | Purpose |
| --- | --- | --- |
| `GET /healthz` | any local caller | unauthenticated liveness: `ok`, `stateVersion`, `desktop` |
| `POST /hook/event?source=...&pid=...` | Claude/Codex bash hook | non-blocking lifecycle and tool events |
| `POST /hook/signal` | Cursor helper | lightweight Cursor lifecycle/activity signals |
| `POST /hook/approve?source=...` | all agents | blocking approval request path |

`HookServer` decodes payloads, derives session IDs, extracts tool/hint/cwd
labels, records diagnostics, and calls `BuddyEngine`. It does not own durable
state.

## Core State Model

The reducer is pure. It receives time as `BuddyEvent.at` values and does not
read clocks, user defaults, network, UI, or BLE.

`InternalState` contains `BuddyState`, sessions, `staleMs`,
`celebrateDurationMs`, `workStallTimeoutMs`, and `approvalTimeoutMs`.
`BuddyState` is the output projection:

- `version`, `updatedAt`
- `desktop` status and last heartbeat timestamp
- aggregate `sessions`
- hardware line `msg`
- newest-first `entries`, capped at 10
- selected `prompt`
- `pet` state/species
- celebrate and last-completed review fields
- first errored/thinking projections
- `activeSessions`, capped at 6 to match firmware capacity
- `currentActivityKind`

Session state is richer than the projection: source, state, prompt, cwd,
timestamps, last/current tool and hint, and activity kind.

## Pet State Priority

Aggregation chooses one visible pet state:

1. no sessions -> `sleep`
2. any waiting prompt -> `attention`
3. any explicit failed session -> `error`
4. any working session -> `busy`
5. any quiet working session past `workStallTimeoutMs` -> `thinking`
6. active celebrate window -> `celebrate`
7. otherwise connected -> `idle`

Live prompts outrank errors because the user can act on them. Errors outrank
ordinary work. `thinking` is not an error; it is a quiet but not-yet-stale
working session.

## Approval Model

`BuddyEngine.submitApproval(...)` applies `approvalArrived` and stores a
`CheckedContinuation` in `pendingApprovals`. A resolution applies
`approvalResolved`, resumes the continuation, and `HookServer.approvalResponse`
formats the agent-specific body.

Decision bodies:

| Decision | Cursor response | Claude/Codex response |
| --- | --- | --- |
| `.allow` | `{"permission":"allow"}` | `hookSpecificOutput.decision.behavior == "allow"` |
| `.deny` | `{"permission":"deny", ...}` | `hookSpecificOutput.decision.behavior == "deny"` with message |
| `.passthrough` | `{"permission":"ask"}` | empty `200 OK` body |

`.passthrough` means "release Buddygotchi's local approval surface and hand the
flow back to the agent." Cleanup paths that use it are:

- explicit session removal (`SessionEnd`, Cursor `session_end`, process watcher)
- stale session reap after `600_000` ms
- prompt expiry after `300_000` ms
- turning local approval mode off in Settings, which calls
  `resolveAllPendingApprovals(decision: .passthrough)`

Approvals can be answered from the SwiftUI popover, actionable notifications,
or ESP32 button messages over BLE.

## Outputs

Outputs conform to:

```swift
protocol OutputProvider {
    var id: String { get }
    func stateDidChange(prev: BuddyState, next: BuddyState)
}
```

`BuddyEngine.apply(_:)` is the only fan-out point. It computes removed sessions
and disappeared prompt IDs, resumes disappeared pending approvals as
`.passthrough`, then calls every output.

### DesktopOutput

`DesktopOutput` is an `OutputProvider`, registered by `AppDelegate` after the
popover is built. It has no polling timer. On state changes it:

- updates the menu bar icon when `pet.state` changes
- posts a notification for a new prompt if the popover is not open
- clears the previous prompt notification when the prompt changes
- plays bundled `celebrate`, `attention`, or `error` `.caf` sounds when enabled
- auto-shows in interactive mode for attention (`15.0` seconds) and long
  completions (`3.0` seconds when task duration is at least `30_000` ms)
- closes the popover when returning to `idle` or `sleep` in interactive mode

Notifications use categories `TOOL_CALL` and `TOOL_CALL_APPROVAL`. Approval
notifications expose `APPROVE` and `DENY` actions, which call
`engine.resolveApproval`.

### SwiftUI App Lifecycle

`AppDelegate` enforces single-instance behavior by activating an existing app
with the same bundle identifier. It starts Sparkle, registers bundled fonts,
creates the status item and popover, registers `ESP32Output` and
`DesktopOutput`, starts the Hummingbird `ServiceGroup`, and runs launch hook
verification.

On first launch, when `setupCompleted` is false, the app opens
`OnboardingWindowController`. The controller owns a non-restorable `NSWindow`
backed by `OnboardingView`, reuses the same controller while visible, activates
the app, and clears itself after finish. Onboarding persists step, species,
name, output target, setup completion, and menu hint through `DefaultsKey`.

### Resources And Copy

`Package.swift` copies `Resources/Fonts` and `Resources/Sounds` into the SwiftPM
resource bundle. `BuddyResources` first resolves through `Bundle.module`, then
falls back to packaged locations including `Buddygotchi_Buddygotchi.bundle` next
to the executable and in `Contents/Resources`.

`BuddyResources.registerFonts()` registers Geist fonts with CoreText; sounds are
loaded as `.caf` or `.wav`. `ResourceTests` assert the module bundle contains a
font and sound and that Geist SemiBold resolves.

User-visible app copy lives in `BuddyCopy`. `CopyRulesTests` reflects through
`BuddyCopy.shared` and rejects banned hype words, exclamation marks, ASCII
ellipsis, and unexpected all-caps words. The inline-copy ratchet baseline is
`0` for `Text("...")` literals in views plus notification/app delegate surfaces.

## Hardware And Firmware

`RenderState` in `Outputs/ESP32/Heartbeat.swift` is the desktop-to-firmware wire
contract. The detailed field contract lives in `firmware/esp32/PROTOCOL.md`.
The Mac app caps fields before encoding: `msg` 23 chars, prompt tool 20,
prompt hint 60, entries 6 items of 48 chars, sessions 6 summaries, and an
assertion guards the heartbeat at `1536` bytes plus newline.

The ESP32 firmware is a renderer and device I/O endpoint. It parses heartbeat
JSON into `TamaState`, derives a persona, draws the buddy, handles buttons,
emits permission decisions, serves debug commands, and runs OTA/status/asset
commands. It does not decide agent state.

Firmware-owned display behavior:

| Constant | Value |
| --- | ---: |
| render tick | `200` ms |
| sleep dim threshold | `60_000` ms |
| sleep off threshold | `600_000` ms |
| A-button long press | `1_500` ms |
| brightness dim/medium/full | `40` / `120` / `220` |

State-transition chirps play on attention, celebrate, and dizzy/error unless
settings sound is off or the heartbeat carries `mute: true`. The Mac sends
`mute: true` only when the desktop `soundsEnabled` default is false; omitting
`mute` leaves the firmware's current value unchanged.

BLE uses Nordic UART Service:

| Item | Value |
| --- | --- |
| Service UUID | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX UUID | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX UUID | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |
| Firmware RX ring | `2048` bytes |
| Firmware USB/BLE line buffers | `2048` bytes each |
| Mac BLE RX line buffer guard | `4096` bytes |
| Firmware requested MTU | `517` |
| Firmware notify chunk cap | `180` bytes |
| Mac ESP32 keepalive resend | `10` seconds |

The device requires LE Secure Connections with MITM/bonding and passkey display.
BLE acks drive status and OTA. On connect, the Mac sends a time sync, then
queries `{"cmd":"status"}` with a `3` second ack timeout to learn firmware
version and check the manifest.

## Transport Decision

BLE is the product transport. USB serial is the debug/factory/recovery
transport for `buddyctl`, HIL, screenshots, first flash, and web-flasher flows.
A Mac-app USB serial product fallback is explicitly deferred.

The reason is pragmatic: the BLE pairing/reconnect/security path is already
built and tested, while the firmware already accepts the same JSON protocol over
USB. USB is therefore available for debug and recovery without replacing the
wireless product story. A USB product path would require Mac-side serial device
discovery and transport code, and it would tether the hardware buddy to a Mac
port instead of letting it sit anywhere powered by USB. BLE failures degrade to
"the hardware buddy sleeps"; hooks and the desktop app keep working.

## Packaging And Release

`app/tools/package.sh` assembles `build/package/Buddygotchi.app` from SwiftPM
release output, copies `Buddygotchi` and `BuddygotchiSignal`, copies the
SwiftPM resource bundle into both `Contents/MacOS` and `Contents/Resources`,
patches `Info.plist`, optionally copies Sparkle, signs nested items and the app
when `DEVELOPER_ID_APPLICATION` is set, zips the app, optionally notarizes and
staples, and creates a DMG when `create-dmg` exists.

App version injection comes from `VERSION`, or `BUDDY_VERSION`, with
`BUDDY_BUILD_NUMBER` defaulting to the same value. `BUDDY_BUNDLE_ID` defaults to
`com.buddygotchi.mac`. Sparkle keys in `Info.plist` are
`SUFeedURL=https://buddygotchi.github.io/releases/appcast.xml`,
`SUPublicEDKey`, `SUEnableSystemProfiling=false`, and
`SUEnableInstallerLauncherService=false`.

`SparkleUpdateManager` loads `Sparkle.framework` dynamically from
`Contents/Frameworks` and disables app updates when it is absent. The release
workflow downloads Sparkle `2.6.4`, verifies SHA-256
`50612a06038abc931f16011d7903b8326a362c1074dabccb718404ce8e585f0b`, packages
with tag/run-number version inputs, uploads artifacts to a draft GitHub Release,
and leaves appcast publication as a manual gate using `app/tools/make-appcast.sh`.

Firmware release tags are `fw-v*`. The workflow installs PlatformIO, builds
with `BUDDY_FW_VERSION` stripped of `fw-v`, generates `manifest.json` and
`esp-web-tools-manifest.json`, and creates a draft release. Firmware version
injection is centralized in `tools/inject_version.py`: `BUDDY_FW_VERSION` and
`BUDDY_GIT_SHA` become `FW_VERSION` and `GIT_SHA`, otherwise the version is
`dev+<short sha>`.

## Testing Architecture

The testing truth is split by environment. `research/eng/TESTING.md` is the
canonical test matrix and command cookbook.

| Layer | Where it runs | Command or entry point |
| --- | --- | --- |
| Swift build | local and CI | `make build` / `cd app && swift build` |
| Real XCTest | CI or Macs with XCTest | `cd app && swift test`; CI fails if fewer than 100 tests execute |
| Local no-XCTest fallback | CLT-only Macs | `make test` compiles tests, prints a loud warning, and exits nonzero unless `BUDDY_ALLOW_COMPILE_ONLY=1` |
| Targeted Swift tests | Xcode/XCTest machines | `swift test --filter ReducerTests`, `EngineIntegrationTests`, `AutoApproveTests` |
| HTTP e2e | app running in a real terminal | `app/tools/e2e-smoke.sh`, plus per-agent `claude.sh`, `codex.sh`, `cursor.sh` |
| Snapshots | opt-in XCTest harness | create `/tmp/buddy-snapshots/.enable`, then `make test-snapshots` |
| Packaging smoke | local/CI release path | `make package`, then clean-account Gatekeeper/onboarding/notification/login-item checks |
| HIL over USB | real M5StickC Plus 2 | `make hil` and `firmware/esp32/tools/buddyctl.py` |
| HIL over BLE | paired real device | `make hil-ble` |
| Firmware release/OTA | real device | PlatformIO build, generated manifests, local/static manifest URL, Settings update flow, `buddyctl.py ping --json` |

`make test` cannot be a false green without XCTest. HTTP e2e verifies the
localhost contract but cannot observe full pet aggregation or BLE. Snapshot
tests write PNGs under `/tmp/buddy-snapshots`; visual review is still required.
HIL covers parser, buttons, screenshots, and BLE/USB command paths on hardware.

## Design Rules

- Keep `app/Buddygotchi/Core/` pure.
- Model new behavior as `BuddyEvent` plus reducer transitions before outputs.
- Put agent-specific parsing in `HookServer`, `BuddygotchiSignal`, or hook
  installer code.
- Add displays by implementing `OutputProvider` and deriving from `BuddyState`.
- Preserve fail-open hook behavior.
- Keep approval continuations in `BuddyEngine`, not `BuddyState`.
- Treat `RenderState` and `firmware/esp32/PROTOCOL.md` as the firmware contract.
- Keep Cursor auto-approval conservative; shell control characters require
  manual review.
- Keep docs current but concise: README for overview/build, this file for
  architecture, `research/eng/TESTING.md` for verification commands, and
  status docs only for current work.
