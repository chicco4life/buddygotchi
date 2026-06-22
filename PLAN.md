# Fill the five priority gaps in Buddygotchi

## Status

| Gap | Status | Notes |
|---|---|---|
| A. Done / needs review | ✅ COMPLETED | 12 new tests (7 reducer + 5 integration), all 77 green. Hardware verified via synthetic heartbeats over USB serial: celebrate sprite + status, idle-with-review post-celebrate, attention clears review on new prompt. Cursor stop fixed server-side (no reinstall). |
| B. Working with confidence | ✅ COMPLETED | 9 more tests (6 reducer + 3 integration), 86/86 green. Heartbeat now ships `entries[]` and a non-empty `msg` during busy with the primary working session's tool/hint. **Bonus**: BUGS.md N1 fix landed — `promptHint`/`promptSource`/`promptLabel` now sent over wire AND parsed by firmware (1-line `_parsePrompt` extension), AND rendered on-device. New firmware HUD lines: tool name + hint above APPROVE?, and `Done: <tool>` summary on celebrate/idle. Hardware verified: `/tmp/buddy-B-prompt-with-hint-v2.png` shows hint, `/tmp/buddy-B-done-line.png` shows completion summary. |
| C. Blocked / error | ✅ COMPLETED | 7 more tests (7 reducer), 93/93 green. New `PetState.error` + `SessionState.errored` + `ActivitySignalKind.error`. Claude Code `StopFailure` now routes to error. Recovery: any `keepWorking` flips back to working. Sosumi sound on transition. ErrorCardView in popover with Dismiss. Firmware `derive()` repurposes dead `P_DIZZY` enum case (stars overlay, no per-species sprite work). Hardware verified: `/tmp/buddy-C-error.png` shows dizzy sprite, `/tmp/buddy-C-recovered.png` shows busy after recovery. **Refinement (later)**: silent-stall detection split out of error into its own `PetState.thinking` — see C.1 below. |
| C.1 Thinking (silent ≥ 5min) | ✅ COMPLETED | 5 more tests, 112/112 green. New `PetState.thinking` + `SessionState.thinking` + `BuddyState.firstThinking`. The 5-min `staleTick` heuristic now maps silent working sessions to `.thinking` (calm "thinking hard"), NOT `.errored`. Priority: `attention > error > busy > thinking > celebrate > idle` — explicit failure beats silent thinking; an actively-working peer also beats it. No alert sound (thinking isn't an error). Recovery preserves `workStartedAt` (work paused, not restarted). Calm `ThinkingRow` (brain icon, elapsed time, no Dismiss). Error msg/card now reads `Error:` / `Error · <agent>` instead of `Stalled:`. Firmware `derive()` maps `"thinking"` → `P_HEART` (other dead enum case). Hardware verified: `/tmp/buddy-thinking.png` shows the closed-eye contentment sprite with calm overlay marks — reads as "thinking hard", no alarm. |
| D. Subagent / parallel | ✅ COMPLETED | 4 more tests (4 reducer), 97/97 green. New `BuddyState.activeSessions: [SessionSnapshot]` projection in aggregate (priority order: needsConfirmation → errored → working oldest-first → idle most-recent-first, capped at 6 to match firmware tama.lines[6]). Heartbeat now ships a `sessions: [SessionSummary]?` array when total > 1 (firmware ignores for v1; future PR can render). PopoverView renders a per-session row list (source pill, state badge, current tool, sessionLabel) when `activeSessions.count > 1`. Hardware verified: `/tmp/buddy-D-multi.png` shows 3-session counter + correct attention prompt. |
| E. Tests / verify | ✅ COMPLETED | 10 more tests (8 reducer + 2 integration), 107/107 green. New pure `Core/ActivityKind.swift` classifier (`verify`/`read`/`write`/`shell`/`web`/`work`) with stack-agnostic test-runner regex. `Prompt.activityKind`, `Session.currentActivityKind`, `BuddyState.currentActivityKind`, `CompletedTask.activityKind` all populated by reducer. Popover surfaces (CurrentActivityRow, ToolCardView hint, ReviewCardView headline) prefix tool names with SF Symbols. Heartbeat ships `activity: String?` (firmware ignores for v1). Hardware verified: `/tmp/buddy-E-busy-verify.png` shows busy state with no regression from new field. |

## Summary

All five gaps shipped. **107 tests** (was 65, +42 new). Hardware verified across 7 named PNGs covering celebrate, idle-with-review, attention with hint (BUGS.md N1 lift), error/dizzy, error recovery, multi-session, busy with activity. Wire format extended with 13 new RenderState fields (all ignored by firmware unless explicitly parsed). Firmware: 1 derive() line for error→P_DIZZY mapping, 1 _parsePrompt extension for promptHint/Source/Label, +12 lines in main.cpp HUD for tool+hint above APPROVE? and Done summary on celebrate/idle.

## Context

Buddygotchi today nails one priority flow excellently — **Permission needed** — and ships the cosmetic shell of two more (Done, Idle). Mapping the PRD's 7 priority flows against the actual code (see prior turn) surfaced five gaps where data is partly tracked but not surfaced, or where signals are dropped on the floor:

| Gap | Status today | The shipping question |
|---|---|---|
| A. Done / needs review | Pet celebrates 4s then reverts to idle. No "review me" surface. **Cursor `stop` → idle, no celebrate at all.** | What did the agent just finish, and how does the user catch it if they weren't watching? |
| B. Working with confidence | Pet animates `busy`; popover shows only `N active`. `state.entries[]` is maintained but rendered nowhere. Heartbeat clears `msg` in busy. | What is the agent doing right now? |
| C. Blocked / error | `StopFailure` → idle (indistinguishable from "happy idle"). No stalled-session detection. | The agent broke or stuck — how does the user know to come look? |
| D. Subagent / parallel | `SessionCounts` aggregated; popover renders `"N active"` text. No per-session breakdown. | Three agents are running — show me what each one is doing. |
| E. Tests / verify | Every tool run paints generic busy. Tool name and hint are extracted but never displayed during work. | Is the agent verifying / writing / reading / running shell? |

The intended outcome is: a user away from the desk gets glanceable, accurate, emotionally legible signals about agent state across all three integrated agents (Claude Code, Cursor, Codex), on both the macOS popover and the M5StickC Plus 2 hardware. Two pleasant surprises in the firmware shorten the path: (1) `tama.promptHint` / `tama.entries[]` / `tama.promptSource` / `tama.promptLabel` are **already parsed** by `firmware/data.h::_applyJson` but never sent by the desktop, so Gaps A and B can ship with one-line wire changes and zero firmware code. (2) `P_DIZZY` is a dead enum case with sprite frames already authored across all 18 species, so Gap C's `error` state needs only a one-line `derive()` change, no per-species sprite work.

## Cross-cutting decisions (defaults — flag any to override)

1. **Pet-state priority cascade** becomes: `disconnected → attention → error → busy → celebrate → review → idle → sleep`. Approval-needed outranks error (live interaction beats stalled attention). Review never overrides a live state.
2. **Review card has a manual Dismiss button** plus auto-clear on next prompt or `startWorking`/`keepWorking`. Without the button the card persists indefinitely after a session ends.
3. **`currentTool` semantics during busy**: most-recent-of-either `PreToolUse` (Codex fires this) or `PostToolUse` (Claude Code fires this). Cursor doesn't fire either; it gets `currentTool = nil` and falls back to source-only display.
4. **Stalled-detection threshold**: 5 minutes of `state == .working` with no `keepWorking`/`startWorking`/`PostToolUse`. Surface as `BuddyConfig.workStallTimeoutMs` (default 300_000) so it's tweakable without recompile.
5. **Sound mapping**: `error → Sosumi` (single play on transition into error). Review and celebrate stay on the existing scheme (`Funk` for ≥30s celebrate only). No new sound for review.
6. **All time-derived facts stay in the reducer** as functions of `event.at` against `state.buddy.updatedAt` — never `Date()` or `Clock.now()` inside `reduce()`.
7. **Wire compatibility**: `firmware/data.h::_applyJson` silently ignores unknown JSON keys, so adding any number of `RenderState` fields is non-breaking. Run a one-time MTU sanity check during Gap B (the largest payload) — `_LineBuf<1024>` and BLE MTU should comfortably hold ~600 bytes per heartbeat.

## Sequencing

A → B → E → D → C. Each is independently mergeable; later gaps reuse the data plumbed by earlier ones.
- **A first** because it establishes `tool`/`hint` plumbing through `activitySignal` events that B, D, and E all reuse.
- **B second** for highest user-visible value-per-line. The firmware's `drawHUD` transcript starts working the instant the desktop sends `entries[]`.
- **E third** as pure decoration on top of A+B's data plumbing.
- **D fourth** — independent of C; could move earlier if the user prefers.
- **C last** because it adds a new pet state, a firmware `derive()` line, sound wiring, and stalled-detection — the largest blast radius.

---

## Gap A — "Done / needs review"

### Approach
Add a `lastCompleted: CompletedTask?` field on `BuddyState` that survives past the 4-second celebrate window and clears on the next prompt, on `startWorking`/`keepWorking`, on session-end, or on explicit user dismiss. Render it as a muted-green pinned card below the connection bar in the popover. Fix Cursor's stop signal to actually celebrate.

### User flow this enables

> **Today**: User starts a Cursor refactor across 4 files, walks away to make coffee. The agent finishes 90 seconds later. By the time the user comes back, the pet has reverted from `celebrate` to `idle` with no trace of what happened. They have to alt-tab into Cursor and scroll the chat history to find the diff. (And if it was Cursor specifically: `stop` mapped to `stopWorking` → idle, so there was never even a celebrate flash to catch.)
>
> **After**: User comes back to a green-railed Review card pinned in the popover:
> ```
> ✓ Edit · cursor · 1m 12s · my-app
>                              [Dismiss]
> ```
> The M5StickC's message line shows `Done: Edit (1m 12s)` until the user kicks off the next prompt. User glances, hits Dismiss, and has the answer to "did anything happen while I was away?" without leaving the popover.
>
> **Coverage payoff**: Cursor goes from "no completion signal at all" to first-class parity with Claude Code and Codex on the most emotionally meaningful flow.

### Files to change
- `Core/BuddyState.swift` — `struct CompletedTask { id, tool, hint, source, sessionLabel, durationMs, completedAt }`; add `lastCompleted: CompletedTask?` to `BuddyState`. Add `lastTool: String?` and `lastHint: String?` to `Session` so we know what to record at celebrate time.
- `Core/BuddyEvent.swift` — extend `activitySignal` to carry optional `tool: String?, hint: String?`; new event `case reviewDismissed(at: Double)`.
- `Core/BuddyReducer.swift` — `handleActivitySignal` stashes tool/hint on the session for `keepWorking`/`startWorking`; on `.celebrate`, builds a `CompletedTask` from the session's last tool/hint and writes it to `s.buddy.lastCompleted`. `aggregate()` clears `lastCompleted` when `prompt != nil` or any session is `.working`. New `handleReviewDismissed` clears it.
- `Server/HookServer.swift` — pass `body.effectiveToolName` and `extractHint(from: body)` into `engine.activitySignal(...)` for `PostToolUse` (Claude Code), `PreToolUse` (Codex), and the Cursor `before*`/`after*` shell paths in the signal endpoint. **Fix Cursor stop**: in `router.post("/hook/signal")`, when `body.signal == "stop"` and `body.agent_id == "cursor"`, emit `.celebrate` instead of `.stopWorking`. (Alternative: change `SignalCLI.signalMap["cursor"]["stop"]` from `"stop_working"` to `"celebrate"` — one-line edit, simpler.)
- `Core/BuddyEngine.swift` — new `func dismissReview()` calling `apply(.reviewDismissed(at: clock.now()))`.
- `Outputs/ESP32/Heartbeat.swift` — extend `RenderState` with `lastCompletedTool`, `lastCompletedHint`, `lastCompletedSource`, `lastCompletedDurationMs`. Optional during celebrate window: write `state.lastCompleted` summary into the existing `msg` field so the existing `drawHUD` line shows "Done: Edit (1m 12s)" without any firmware code change.
- `Views/PopoverView.swift` — new `ReviewCardView` (style: green left-rail, smaller than ToolCardView). Renders when `state.prompt == nil && state.lastCompleted != nil`. Includes a "Dismiss" button calling `engine.dismissReview()`.

### Reducer tests (`Tests/ReducerTests.swift`)
- `keepWorkingWithToolAndHint_stashesOnSession`
- `celebrateAfterKeepWorking_populatesLastCompleted_withCorrectTool`
- `lastCompletedPersists_afterCelebrateWindowExpires`
- `lastCompletedClears_whenNewRequestArrives`
- `lastCompletedClears_onStartWorkingFromAnySession`
- `reviewDismissedEvent_clearsLastCompleted`
- `cursorStopMaps_toCelebrateNotStopWorking` (HookServer-level → covered in integration)

### Integration tests (`Tests/EngineIntegrationTests.swift`)
- `cursorStopSignal_putsPetInCelebrate_thenIdleWithReview`
- `claudePostToolUseThenStop_recordsLastCompletedToolName`
- `multipleSessions_reviewReflectsCelebratingSessionTool`

### ESP32 verification
1. Start the daemon: `(cd app && swift run Buddygotchi) &`
2. Capture baseline: `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-A-0.png` (idle)
3. Trigger Cursor lifecycle via e2e: `app/tools/e2e/cursor.sh` — drives sessionStart → beforeShellExecution (with command "swift test") → afterShellExecution → stop.
4. Within ~3 seconds: `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-A-celebrate.png` → expect celebrate sprite + msg line "Done: Bash (4s)".
5. After 5+ seconds: `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-A-idle-with-msg.png` → idle sprite, msg line still showing the completion summary (since the desktop continues to write it into `msg` until the popover dismisses or a new prompt arrives).
6. POST a new `UserPromptSubmit` for the same Cursor session; screenshot → expect msg cleared and pet returning to busy.

---

## Gap B — "Working with confidence"

### Approach
Surface the current activity in the popover during `busy` state, and ship `state.entries[]` over the heartbeat so the firmware's already-built `drawHUD` transcript renders. This requires reverting one aspect of BUGS.md fix #3 (clearing `msg` in busy) — the original reason for that clear (showing a stale post-tool message indefinitely) is replaced by an actively tracked `currentTool` that updates as new events arrive.

### User flow this enables

> **Today**: User triggers Claude Code to migrate a database schema. Pet flips to busy and stays there. Three minutes pass. The popover shows `connected · 1 active` and a generic busy sprite — nothing else. The M5StickC shows the same animation with a blank line under it. The user has no way to tell whether the agent is genuinely working through tools or wedged on a model reply, so they alt-tab into the agent's terminal output to check.
>
> **After (popover)**:
> ```
>     [busy pet]
>     claude-code · busy
>     ● connected · 1 active
>     ✓ Bash · swift test                  ← current tool, verify icon (Gap E)
>     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
>       Read: Package.swift                ← entries[0..2] dimmed
>       Edit: BuddyState.swift
> ```
> **After (M5StickC)**: existing `drawHUD` transcript scroll lights up — newest line bright at top, older lines dim below, scroll counter when the user pages back. Zero firmware code change required; `entries[]` was already parsed by `data.h::_applyJson` and rendered by `drawHUD`, the desktop just wasn't sending it.
>
> **Confidence shift**: user goes from "is this thing alive?" to watching the tool name turn over every few seconds — the same affordance the agent's own terminal would give them, but glanceable from peripheral vision.

### Files to change
- `Core/BuddyState.swift` — already has `entries: [String]`. Add `currentTool: String?` and `currentHint: String?` on `Session` (parallel to Gap A's `lastTool`/`lastHint`, but for in-flight rather than just-finished work).
- `Core/BuddyReducer.swift` — `handleActivitySignal` for `.startWorking`/`.keepWorking` writes both `currentTool`/`currentHint` AND `lastTool`/`lastHint`. On `.stopWorking`/`.celebrate`, clears `currentTool`/`currentHint` (but `lastTool`/`lastHint` are preserved for review). In `aggregate()`'s busy branch, replace `buddy.msg = ""` with `buddy.msg = shortMsg(tool: primaryWorking.currentTool ?? "", hint: primaryWorking.currentHint ?? "", source: primaryWorking.source)`. Primary working session = oldest `workStartedAt` (longest-running).
- `Outputs/ESP32/Heartbeat.swift` — add `entries: [String]?` to `RenderState`, encoded from `state.entries.prefix(6)` (firmware caps at 6 lines). The firmware's `_applyJson` line 124–137 already maps `doc["entries"]` → `tama.lines[6][81]`.
- `Views/PopoverView.swift` — new `currentActivityRow` rendered between `connectionBar` and the optional ToolCardView when `state.pet.state == .busy && state.msg.isEmpty == false`. Format: SF Symbol from `ActivityKind` (Gap E) + monospace tool name + secondary hint truncated to 1 line.

### Firmware change
**None.** `drawHUD` already renders `tama.lines` when `nLines > 0` and falls back to `tama.msg` otherwise. Both surfaces light up the moment the desktop starts sending `entries`.

### Reducer tests
- `busyState_msg_includesCurrentTool_fromPrimarySession`
- `currentTool_clearsOnCelebrate`
- `currentTool_clearsOnStopWorking`
- `multipleWorkingSessions_msgUsesOldestWorkStartedAt`
- `entriesAccumulate_andTruncateAt10`

### Integration tests
- `claudeKeepWorkingWithBashTool_stateMsgContainsTool`
- `heartbeatRoundTrip_includesEntriesArray` — register a fake `OutputProvider` that captures `RenderState` (we'll need to expose this; `EchoRecorder` in tests already captures `BuddyState`; add a small `RenderStateRecorder` that calls `renderState(from:)` and stashes the result).

### ESP32 verification
1. `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-B-baseline.png` — note empty msg area.
2. `app/tools/e2e/claude.sh` to register a session, then a sequence of `PostToolUse` POSTs:
   - `tool_name: "Bash", tool_input.command: "swift test"`
   - `tool_name: "Read", tool_input.file_path: "Foo.swift"`
   - `tool_name: "Edit", tool_input.file_path: "Bar.swift"`
3. After each: `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-B-N.png`
4. Expected: busy sprite throughout. Lines area shows newest entry brightly at top (e.g., `[claude-code] Edit: Bar.swift`), with previous entries dimmed below. The popover's `currentActivityRow` shows the most recent tool with the matching activity icon (Gap E: Bash + `swift test` → check-seal; Read → doc; Edit → pencil).
5. Verify the BUGS.md N1/N2 lift: with a permission prompt arriving mid-busy (`PermissionRequest` for `Bash` with `command: "rm -rf /tmp/x"`), the device's approval card should now show a non-empty hint line (`promptHint` field added to `RenderState`, firmware already reads it).

---

## Gap C — "Blocked / error"

### Approach
New `PetState.error` case. Map Claude Code `StopFailure` → error. Detect stalled working sessions in `staleTick` (5 minutes default of no `keepWorking`/`PostToolUse`/`PreToolUse`). Recover automatically when a working signal arrives. New `error` sound (`Sosumi`). Firmware: one-line `derive()` change repurposing the dead `P_DIZZY` enum case (sprite frames already exist for all 18 species).

### User flows this enables

> **Today — explicit failure**: Codex runs `cargo test`, the test binary crashes, Codex emits `StopFailure`. Pet drops to `idle` (visually identical to "task done, agent waiting for next prompt"). The user only realizes 20 minutes later that the run died. Zero notification, zero device feedback.
>
> **After — explicit failure**: Pet flips to `error`. M5StickC shows the dizzy-stars overlay (firmware's pre-authored `P_DIZZY` sprite, now active via the one-line `derive()` change). `Sosumi` plays once. Red-railed Error card in the popover:
> ```
> ⚠ codex · Bash failed · proto/
>                                  [Dismiss]
> ```
> User notices immediately, fixes the test, kicks off a new prompt — pet recovers to busy.
>
> **Today — silent stall**: User triggers a long Claude Code task and walks away. Mid-run, the agent process gets stuck waiting on a subprocess that never returns (maybe an `npm install` in a network-partitioned container). Pet stays in `busy` for the full 10-minute stale-session timeout before disappearing entirely. User comes back to a sleeping pet and no idea anything went wrong.
>
> **After — silent stall**: After 5 minutes of `state == .working` with no `keepWorking`/`PostToolUse`, the stale tick promotes the session to `errored`. Pet → `error`:
> ```
> ⚠ claude-code · Stalled: Bash (6m) · my-app
>                                       [Dismiss]
> ```
> User intervenes by killing the hung subprocess. Stalled session reclassifies on the next signal.
>
> **Priority correctness (covered by tests)**: if a `PermissionRequest` lands while a *different* session is errored, the pet stays in `attention` (live interaction wins); the error card is queued behind the approval card and surfaces when the prompt clears.

### Files to change
- `Core/BuddyState.swift` — `enum PetState { ..., case error }`; add `error` to `sfSymbol` switch (`"exclamationmark.triangle.fill"`). Add `case errored` to `enum SessionState`. Add `lastWorkSignalAt: Double?` to `Session`.
- `Core/BuddyEvent.swift` — extend `ActivitySignalKind` with `case error = "error"`.
- `Core/BuddyReducer.swift` —
  - `handleActivitySignal` for `.error`: set `s.sessions[sessionId]?.state = .errored`, do NOT clear `currentTool`/`currentHint` (we want to show what failed), do NOT clear `workStartedAt`.
  - Update `keepWorking`/`startWorking` to bump `lastWorkSignalAt`, and to flip an `.errored` session back to `.working` (recovery path).
  - `handleStaleTick`: in addition to existing 10-min session-prune, scan working sessions where `now - lastWorkSignalAt > workStallTimeoutMs` AND `now - workStartedAt > workStallTimeoutMs`; mark `state = .errored`. Pure transformation, no side effects.
  - `aggregate()`: insert error branch between attention and busy. `buddy.msg = "Stalled: \(errored.first?.currentTool ?? "?") (\((now - workStartedAt) / 60000)m)"`.
- `Core/Config.swift` — add `var workStallTimeoutMs: Double` (default `300_000`).
- `Server/HookServer.swift` — `case "StopFailure":` for Claude Code → `.error` (was `.stopWorking`). No new route needed.
- `Outputs/ESP32/Heartbeat.swift` — existing `pet` field carries the new string `"error"`; add `errorReason: String?` and `errorTool: String?` (firmware ignores both for v1; we can render them in a follow-up).
- `Views/PopoverView.swift` — new `ErrorCardView` (red left-rail, similar shape to ReviewCardView). Includes "Dismiss" → `engine.dismissError(sessionId:)`. `stateColor` switch gains `.error → BuddyTheme.destructive`.
- `Notifications/NotificationManager.swift` (or `AppDelegate.checkSounds`) — on transition `previousPetState != .error && current == .error`, play `NSSound(named: "Sosumi")`.
- `Buddies/BuddySprites.swift` — **defer**. Swift renderer falls back to `idle` for unknown state names; `pet.state == .error` will animate the idle frames, gated only on the popover state pill text. Authoring `error` frames per species is a follow-up PR (5 species × ~5 frames each).
- `src/outputs/esp32/firmware/main.cpp::derive()` — add one line: `if (strcmp(s.pet, "error") == 0) return P_DIZZY;`. This activates the existing dizzy-stars overlay sprite that's authored across all 18 species (`P_DIZZY` is currently a dead enum case).

### Reducer tests
- `staleTick_marksSessionErrored_after_5min_noWorkSignal`
- `staleTick_doesNotMarkErrored_if_keepWorkingWithin5min`
- `claudeStopFailure_setsPetToError_notIdle`
- `erroredSession_recoversToWorking_onKeepWorking`
- `erroredSessionWithActivePrompt_petRemainsAttention` — priority test
- `erroredAndCelebratingSessions_petIsError` — priority test
- `dismissError_clearsErrorStateForSession`

### Integration tests
- `stopFailureOverHttp_putsPetInError`
- `silentSessionFor6Minutes_emitsErrorViaStaleTickWithMockClock` — uses `MockClock` and `engine.triggerStaleTick()`
- `errorSoundPlaysOnce_onTransitionIntoError` — assert sound plays once via a fake sound provider injected for tests
- `errorWithConcurrentApproval_petRemainsAttention`

### ESP32 verification
1. `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-C-0.png` (idle baseline).
2. POST a Claude Code `UserPromptSubmit` (busy), then a `StopFailure`.
3. `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-C-stopfail.png` → expect dizzy sprite (species-specific stars overlay over the idle pose) and msg line "Stalled: …" or "[claude-code] error".
4. POST a `UserPromptSubmit` again to the same session.
5. `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-C-recovered.png` → busy sprite, dizzy gone.
6. **Stalled detection** (impractical to wait 5 min): build with `BuddyConfig.workStallTimeoutMs = 30_000` for the test session, or wire a debug `/debug/stale` route that fires `engine.triggerStaleTick()` directly. POST a `UserPromptSubmit`, wait 35s without further hooks, fire the stale tick.
7. `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-C-stalled.png` → dizzy sprite, msg "Stalled: ?"
8. **Sound check**: macOS popover transition `.busy → .error` plays `Sosumi.aiff` once. Confirm no repeat on subsequent state changes within the same error span.
9. **Approval-during-error priority**: with the session errored, send a `PermissionRequest`. `python3 src/outputs/esp32/tools/screenshot.py` → expect approval sprite + APPROVE? overlay (attention overrides error). `python3 src/outputs/esp32/tools/button.py b` to deny; verify the error remains afterward.

---

## Gap D — "Subagent / parallel work"

### Approach
Project sessions as an ordered list in `BuddyState` and render a per-session row list in the popover when `total > 1`. Wire an array to the heartbeat for future firmware use; v1 device-side stays as-is (existing `total/running/waiting` counters in `drawHUD` are sufficient).

### User flow this enables

> **Today**: User has Claude Code refactoring a frontend, Cursor running a backend test suite, and Codex prototyping a new feature, all simultaneously across three repos. Popover shows: `connected · 3 active`. Which one needs attention? Which one's busy? Which one's idle? User clicks through each agent app to find out.
>
> **After (popover)**:
> ```
>     [aggregated busy pet — attention if any session waiting]
>     ● connected · 3 active
>     ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
>     ⚠ cursor      waiting   Bash       my-app/        ← amber, click to scroll to its prompt
>     ◍ claude-code busy      ✏ Edit     buddygotchi/   ← purple pencil from Gap E
>     ○ codex       idle      —          proto/         ← greyed
> ```
> User immediately spots the Cursor approval, clicks that row → popover scrolls to the prompt card, approves with Enter. M5StickC shows the same `total/running/waiting` counters (unchanged in v1) but with interleaved transcript entries from all three sources, so the user can tell which agent just acted from the source prefix in `[cursor] Bash: …` style entries.
>
> **Why it matters**: Buddygotchi's pitch is multi-agent. Today the multi-agent visibility ends at a counter; this turns it into actual situational awareness.

### Files to change
- `Core/BuddyState.swift` — new struct:
  ```
  struct SessionSnapshot: Sendable, Equatable {
      var id: String
      var source: String
      var state: SessionState
      var sessionLabel: String?
      var currentTool: String?
  }
  ```
  Add `activeSessions: [SessionSnapshot]` to `BuddyState`. Cap at 6 (matches firmware `tama.lines[6]`).
- `Core/BuddyReducer.swift` — `aggregate()` builds `activeSessions` from `state.sessions.values` after computing counts. Order: `needsConfirmation` first (oldest `prompt.arrivedAt`), then `errored` (oldest `workStartedAt`), then `working` (oldest `workStartedAt`), then `idle` (most-recent `lastActivityAt`). Truncate to 6.
- `Outputs/ESP32/Heartbeat.swift` — add to `RenderState`:
  ```
  var sessions: [SessionSummary]?
  struct SessionSummary: Encodable {
      var src: String
      var st: String
      var tool: String?
      var lbl: String?
  }
  ```
  Encode from `state.activeSessions`. Firmware ignores the new key; future firmware PR can render a "sessions" page in `displayMode` cycling.
- `Views/PopoverView.swift` — when `state.activeSessions.count > 1`, replace the single `"\(running) active"` text with a compact `SessionListView` inside the existing connection panel. Each row: source pill (color via `buddySpeciesColor` for the source's representative species, or a fixed agent color), state badge (working/errored/needsConfirmation/idle), monospace `currentTool ?? "—"`, optional sessionLabel.

### Firmware change
None for v1.

### Reducer tests
- `activeSessions_ordersAttentionFirst_thenErrored_thenOldestWorking`
- `activeSessions_cappedAt6`
- `activeSessions_includesIdleSessions_butAtTail`
- `activeSessions_emptyWhenNoSessions`

### Integration tests
- `threeConcurrentSessions_renderStateContainsAllThreeInOrder`
- `popoverSnapshot_threeSessions_listShowsAllThree` — adds a new test in `SnapshotHarnessTests`. Set up engine with 3 sessions in different states (Cursor working on Edit, Claude Code waiting on Bash approval, Codex idle); render `PopoverView`; assert PNG capture round-trips and a screenshot is saved to `/tmp/buddy-snapshots/D-multi.png`.

### ESP32 verification
1. `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-D-0.png` (idle, 0 sessions).
2. Run all three e2e flows in parallel against the running daemon:
   ```
   app/tools/e2e/claude.sh &
   app/tools/e2e/cursor.sh &
   app/tools/e2e/codex.sh &
   wait
   ```
3. While they're mid-flight (insert pauses in the e2e scripts as needed), `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-D-3up.png` → expect device counters `total: 3, running: ≥1, waiting: ≥0` and lines area showing entries from all three sources interleaved (newest first).
4. Mac-side: open popover, confirm 3-row session list with correct labels and the cursor row showing its `currentTool`. Take a manual screenshot of the popover to attach to the PR.

---

## Gap E — "Tests / verify / browser check"

### Approach
Pure-function classifier `activityKind(tool: String, hint: String) -> ActivityKind`. Stash the result on Session and Prompt. Render as an SF Symbol icon next to the tool name in the popover (busy current-activity row, attention tool card, review card). No new pet state, no firmware change.

### User flow this enables

> **Today**: User watches the popover during a Claude Code task. The current-activity row (added in Gap B) shows tool names in monospace. `Bash` looks like `Bash` looks like `Bash` — three radically different operations all paint the same way. The user has to read each line carefully to figure out whether the agent is verifying, fetching, writing, or shell-poking.
>
> **After**: Same row, with a 1-character icon prefix per activity kind:
> ```
>   ✓  Bash · swift test               ← verify (green check-seal — high signal)
>   🌐  WebFetch · https://docs/...     ← web (accent purple globe)
>   ✏️  Edit · BuddyState.swift         ← write (accent purple pencil)
>   📄  Read · Package.swift            ← read (muted secondary doc)
>   🖥  Bash · rm -rf node_modules     ← generic shell (muted)
>   …  Glob · **/*.ts                   ← work fallback
> ```
> (Real implementation uses SF Symbols, not emoji — `checkmark.seal`, `globe`, `pencil`, `doc.text`, `terminal`, `ellipsis.circle`.)
>
> Same icon shows on the **attention** tool card during approvals and the **review** card after celebrate, so a denied `WebFetch` and a denied `rm` are immediately distinguishable at peripheral-vision distance.
>
> **Concrete payoff**: at peripheral-vision distance, the user can tell whether the agent is in a high-value verifying phase (don't interrupt) or a low-value background-reading phase (safe to redirect or ignore). The verify icon also provides a visual marker for "tests passing means done" — pairs with the Gap A review card to give a clean "tests just passed" moment.

### Files to change
- `Core/BuddyState.swift` — new `enum ActivityKind: String { case verify, read, write, shell, web, work }`. Add `activityKind: ActivityKind = .work` to `Prompt`. Add `currentActivityKind: ActivityKind?` to `Session`. Add `lastCompletedActivityKind` to `CompletedTask`.
- `Core/ActivityKind.swift` (new file) — pure helper:
  ```
  func activityKind(tool: String, hint: String) -> ActivityKind
  ```
  Heuristic table:
  - `Read | Glob | Grep | LSP` → `.read`
  - `WebFetch | WebSearch` → `.web`
  - `Edit | Write | MultiEdit | NotebookEdit` → `.write`
  - `Bash | Shell` AND hint matches `/^(swift test|npm (test|run test)|pytest|go test|cargo test|xcodebuild test|jest|mocha|rspec|cargo bench)\b/` → `.verify`
  - `Bash | Shell` otherwise → `.shell`
  - default → `.work`
- `Core/BuddyReducer.swift` — `setPrompt` and `handleActivitySignal` (in tool/hint branches) call `activityKind(...)` and stash on Session/Prompt.
- `Outputs/ESP32/Heartbeat.swift` — add `activity: String?` to `RenderState` (carries the busy session's `currentActivityKind`). Firmware ignores for v1.
- `Views/PopoverView.swift` —
  - `currentActivityRow` (Gap B) prefixes the tool name with an SF Symbol from a small mapping:
    - `.verify → "checkmark.seal"` (in `BuddyTheme.celebrateGreen`)
    - `.read → "doc.text"` (secondary)
    - `.write → "pencil"` (in `BuddyTheme.accent`)
    - `.shell → "terminal"` (secondary)
    - `.web → "globe"` (in `BuddyTheme.accent`)
    - `.work → "ellipsis.circle"` (tertiary)
  - `ToolCardView` shows the same icon next to the tool name in the attention card.
  - `ReviewCardView` shows the same icon next to the just-completed tool.

### Firmware change
None.

### Reducer tests
- `activityKind_swiftTestCommand_returnsVerify`
- `activityKind_curlCommand_returnsShell`
- `activityKind_ReadTool_returnsRead`
- `activityKind_EditTool_returnsWrite`
- `activityKind_unknownTool_returnsWork`
- `activityKind_emptyHintWithBash_returnsShell`
- `prompt_activityKindSet_afterRequestArrived`
- `session_currentActivityKindSet_afterKeepWorking`

### Integration tests (`SnapshotHarnessTests` — opt-in)
- `popoverSnapshot_busyWithBashSwiftTest_showsVerifyIcon`
- `popoverSnapshot_attentionWithEditTool_showsPencilIcon`
- `popoverSnapshot_reviewCardForWebFetch_showsGlobeIcon`

### ESP32 verification
Device-side is unchanged for v1 (no icon font on device). Verify via:
1. Run `app/tools/e2e/claude.sh` modified to push a `PostToolUse` with `tool_name: "Bash"` and `command: "swift test"`.
2. Open the macOS popover; confirm the busy row shows `checkmark.seal` next to "Bash".
3. POST a `WebFetch` permission request via `app/tools/e2e/cursor.sh` (use the auto-deny path so the prompt blocks).
4. Confirm the popover Tool Card shows the globe icon next to "WebFetch".
5. `python3 src/outputs/esp32/tools/button.py --mock a` to approve through the firmware path; verify the popover icon was correct before approval was sent. (Device card itself stays icon-less in v1; that's fine.)
6. Capture a final `python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-E-postapprove.png` to confirm the round-trip didn't regress the device path.

---

## End-to-end verification (full plan, after all 5 land)

After all gaps merge, run the comprehensive smoke:

```sh
# Build + unit tests
cd app && swift build && swift test
# Expect: prior 66 + ~25 new = ~91 tests, all green

# Snapshot harness
mkdir -p /tmp/buddy-snapshots && touch /tmp/buddy-snapshots/.enable
swift test --disable-sandbox --filter SnapshotHarnessTests
# Inspect /tmp/buddy-snapshots/*.png for visual regressions

# Live daemon + e2e
swift run Buddygotchi &
app/tools/e2e-smoke.sh
# Expect: each agent's flows pass, including the new error/review paths

# Hardware round-trip — flash firmware first if Gap C derive() change is in this build
# (cd src/outputs/esp32 && pio run -t upload)
python3 src/outputs/esp32/tools/screenshot.py --out /tmp/buddy-final-idle.png
# Run a scripted mixed scenario: busy → permission → approve → celebrate → review → idle
# Capture screenshots at each transition; archive for the PR
```

The hardware verifications should produce 12+ named PNGs covering: idle, busy with current tool, busy with stale entries scroll, attention with non-empty hint (BUGS.md N1 fix), error/dizzy, error recovery, celebrate with summary line, review-state idle with summary line, three-session multi-up, approval-during-error priority.

## Decisions to confirm before implementation

1. **Stalled threshold of 5 minutes** — generous enough for slow tool calls but not so long the device looks dead. Override via `BuddyConfig.workStallTimeoutMs`.
2. **Cursor stop fix location** — change `SignalCLI.signalMap["cursor"]["stop"]` (one line, requires reinstall to take effect) vs change `HookServer` server-side mapping (one line, no reinstall). Recommendation: server-side, so existing installations get the fix on next app launch.
3. **`PetState.error` sprite frames** — defer per-species `error` frames to a follow-up PR (Swift falls back to `idle` cleanly for unknown states), or block this PR on authoring 5 × ~5 frames? Recommendation: defer.
4. **Review card placement** — below `connectionBar` in the popover (above the footer), or above `connectionBar` (more prominent)? Recommendation: below, so live state stays visually primary.
5. **`activeSessions` truncation at 6** — matches firmware capacity but the popover could comfortably show more. Two values, or one cap shared? Recommendation: one cap (6) for simplicity; firmware bounds the wire schema anyway.
6. **Soundless review** — confirm we don't add a sound for the review-card transition. If the user's interactive mode is off, they'll miss the celebrate-window flash entirely without a chime. Recommendation: keep silent (matches existing minimal-sound design).

## Critical files to modify

- `app/Buddygotchi/Core/BuddyState.swift` — A, B, C, D, E (data model)
- `app/Buddygotchi/Core/BuddyEvent.swift` — A (extend activitySignal, reviewDismissed), C (error signal kind)
- `app/Buddygotchi/Core/BuddyReducer.swift` — all 5
- `app/Buddygotchi/Core/BuddyEngine.swift` — A (dismissReview), C (dismissError)
- `app/Buddygotchi/Core/Config.swift` — C (workStallTimeoutMs)
- `app/Buddygotchi/Core/ActivityKind.swift` — E (new file)
- `app/Buddygotchi/Server/HookServer.swift` — A (tool/hint plumbing, Cursor stop fix), C (StopFailure → error)
- `app/Buddygotchi/Outputs/ESP32/Heartbeat.swift` — A, B, C, D, E (RenderState extensions)
- `app/Buddygotchi/Views/PopoverView.swift` — A (ReviewCardView), B (currentActivityRow), C (ErrorCardView), D (SessionListView), E (icons)
- `app/Buddygotchi/Notifications/NotificationManager.swift` (or `AppDelegate.checkSounds`) — C (Sosumi)
- `app/Tests/ReducerTests.swift` — all 5
- `app/Tests/EngineIntegrationTests.swift` — all 5
- `app/Tests/SnapshotHarnessTests.swift` — D, E
- `src/outputs/esp32/firmware/main.cpp` — C only (one-line `derive()` addition)

## Reuse pointers

- `Core/BuddyReducer.swift::shortMsg(tool:hint:source:)` — already produces `[source] tool: hint` strings; reused for busy `msg`, completion summary, and entries.
- `Server/HookServer.swift::extractHint(from:)` — already pulls command/file/path/url from any tool input; reused for tool/hint plumbing.
- `Outputs/ESP32/Heartbeat.swift::renderState(from:)` — single point for all wire-format extensions; firmware silently ignores unknown keys.
- `Tests/EngineIntegrationTests.swift::EchoRecorder` — captures `(prev, next)` transitions; sufficient for sound-on-transition tests if extended with a new `RenderStateRecorder` sibling.
- `Theme/BuddyTheme.swift::accent / destructive / celebrateGreen / attentionAmber` — palette is complete; no new colors needed.
- `firmware/main.cpp::P_DIZZY` enum case + per-species `doDizzy()` sprite functions — already authored; activated by one-line `derive()` change.
