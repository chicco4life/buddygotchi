# 03 — UI/UX Polish Audit

Goal: every surface of the running app feels considered. This doc covers the live popover, notifications, sounds, settings, menu bar behavior, and the firmware sheet. Depends on 02 for tokens/typography; items here are behavioral and can be sequenced independently.

## 1. Popover layout & sizing

- **Fixed heights will clip.** `liveViewHeight` is 240/380 pt switched only on "any card present". A state with a 6-row session list + activity row + a 3-line approval card overflows; conversely a bare idle popover has dead space. Fix: remove the fixed `height:` from `PopoverView.liveView` and let content size drive it (`hostingController.sizingOptions = .preferredContentSize` is already set — it currently can't work because the frame pins the height). Keep `width: BuddyTheme.popoverWidth`, add `.frame(minHeight: 240)` and animate size changes with `.buddyEase(0.3)`. Verify no feedback loops with `TimelineView` (the pet stage has a fixed frame, so fine).
- **Empty/sleep state is unhelpful.** When `pet.state == .sleep` (no sessions), the popover shows a sleeping pet and "disconnected". Add a quiet guidance block below the pet: *"No agents awake. Open Claude Code, Cursor, or Codex and send a message — your buddy will hear it."* plus, if 05's health check reports any agent unconnected/corrupted, a one-line *"Claude Code hooks need repair"* row linking to Settings → Agents.
- **Idle-but-connected state**: show "watching · N session(s)" and the last completion if present (already does via review card) — fine.
- **Prompt queue is invisible.** Only the oldest prompt renders; with 3 agents waiting, the user can't tell. Add a tiny label in the tool card header when `state.sessions.waiting > 1`: `"+2 more waiting"` (data already exists in `SessionCounts.waiting`). After resolving, the next prompt slides in (already happens via aggregation).
- **Approve/Deny ergonomics**: ⏎ approves (exists). Add ⌫ or `D` for deny (`.keyboardShortcut(.delete, modifiers: [])`), and show the shortcut hints subtly on hover. Consider requiring a beat of intention for deny per the product's interaction philosophy (deny is deliberate) — no confirmation dialog, just no shortcut on plain Esc.
- **Session rows**: `SessionListView` shows `currentTool` and `sessionLabel` — with both present the row truncates awkwardly at 320 pt. Drop `currentTool` when `sessionLabel` exists, or stack: primary line = source + state, secondary = tool. Also give rows the project label priority (users think in projects, not tools).
- **Footer**: `Quit` and the ladybug bug-report button are permanently visible in the main surface. Move both into Settings (About section already has Quit; add "Export bug report" there). Footer keeps only the settings gear — the main surface is the pet, not chrome. Quit stays reachable via the status-item context menu (§7).
- **Card hierarchy**: tool card / error card / review card are mutually exclusive (`if/else if`) — a pending approval hides an error entirely. Acceptable priority, but when both exist show a one-line trailer under the tool card: *"also: Codex hit an error"*. Data: `state.firstErrored != nil && state.prompt != nil`.

## 2. Actionable notifications (high value, low cost)

`NotificationManager` posts inert notifications. The product's whole thesis is "act without switching context" — make the notification itself an approval surface:

- Register category `TOOL_CALL` with actions:

```swift
let approve = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [.authenticationRequired])
let deny    = UNNotificationAction(identifier: "DENY", title: "Deny", options: [.destructive])
let category = UNNotificationCategory(identifier: categoryId, actions: [approve, deny], intentIdentifiers: [])
```

  Only attach actions when `prompt.isApproval` (use a second category `TOOL_CALL_APPROVAL`; passive prompts keep the empty one).
- Implement `userNotificationCenter(_:didReceive:withCompletionHandler:)`: parse `tool-<promptId>` from the identifier, hop to the main actor, call `engine.resolveApproval(requestId:decision:)`. Default tap (no action) opens the popover.
- Notification content: title = `"<AgentName> needs you"` (or `"<buddyName> needs you"`), body = `"<tool>: <hint>"` (today title is the raw tool name — `"Bash"` as a notification title is meaningless).
- The notification should also clear when the prompt resolves from *any* surface (exists: `clearNotification`) — keep.
- Requires a real bundle ID (notifications are silently disabled under `swift run` because `Bundle.main.bundleIdentifier` is nil — see 06 §1; note this dependency).

## 3. Sound design

- Current: hardcoded `NSSound(named:)` — `Funk` (celebrate), `Glass` (attention), `Sosumi` (error). System sounds read "someone's Mac beeped", not "my creature chirped", and there is **no way to turn them off**.
- Add a `Sounds` toggle in Settings → General (default on) and honor it in the sound path. Optional refinement: "only when popover is closed".
- Replace system sounds with three short custom chirps following the firmware's sound rules (PRODUCT.md §10.3: distinct motif per event, ≤3 notes, hard volume cap): attention = rising "meep?", celebrate = short trill, error = single low "oof". Ship as small `.caf` files in `Resources/Sounds/`, play via `NSSound(contentsOf:byReference:)`. If sourcing audio assets is blocked, synthesize simple square-wave chirps offline and commit them — chiptune-adjacent is on-brand — or keep system sounds behind the toggle as interim.
- Respect Do Not Disturb / Focus implicitly: notifications already do; direct `NSSound` playback does not. Gate the direct sounds on popover-closed + not-in-attention-notification path to avoid double-audio (notification already carries `.sound`). Simplest correct rule: if a notification was just posted for this transition, skip the NSSound.

## 4. Interactive mode & popover behavior

- Auto-show attention uses `popover.behavior = .applicationDefined` (pinned; user's clicks elsewhere don't dismiss). Pinning a transient-looking popover is surprising. Recommendation: always `.transient`, and rely on notification + menu bar badge for persistence — or keep pinning only for blocking approvals (inverse of today's logic, which pins *non*-approvals). Decide and document; current inversion looks like a bug (approvals are the actionable ones, yet they're the dismissible ones).
- Auto-dismiss timers (3 s celebrate / 15 s attention) are fine; cancel on any user interaction inside the popover (`.onHover`/mouse-entered on the root → `cancelAutoDismiss()` via a callback into `AppDelegate`, else the popover vanishes mid-read).
- Consider making Interactive Mode **default on** for new installs — it's the product's core promise ("only bothers you when it matters"); shipping it off means the default experience is a static menu bar icon. Keep the toggle.

## 5. Settings restructure

Current single scroll of General / Buddy / Agents / Displays / About is fine at this size; polish within it:

- **General**: Launch at Login, Interactive Mode, Sounds (new), Local Approval Mode. Approval mode gets an explainer: first enable shows a small sheet — *what changes (Buddygotchi becomes the approval surface for supported hooks), what stays safe (fail-open, auto-approve rules for Cursor read-only tools), and a "turn on" confirm.* Toggling **off** must not auto-allow pending approvals (04 §3.1 — resolve as `passthrough`).
- **Advanced disclosure** (collapsed `DisclosureGroup` at the bottom of General): HTTP port (read-only value + "why can't I change this?" tooltip, or make it editable with restart-server logic if cheap), server health row (§6), "Open config folder" (`~/.buddygotchi`) button.
- **Agents**: rows gain the health states from 05 (`connected / needs repair / not connected` with reason on hover) and a single context-appropriate button (Connect / Repair / nothing). Add "Disconnect" as a secondary action (uninstall exists but is only exposed via Reinstall today).
- **Buddy**: species carousel (blob-first), name field (01 §3.2), and a "preview states" affordance — clicking the buddy cycles idle → attention → celebrate so users see what the states look like.
- **Displays**: rename per brand (02 §5); firmware row stays; add "Forget this buddy" confirmation before unpair (destructive, currently instant).
- **About**: version **read from the bundle** (`Bundle.main.infoDictionary?["CFBundleShortVersionString"]`) — it's hardcoded `"v0.3.0"` in `SettingsView.swift` today and will drift; "Check for updates" (Sparkle, 06 §2); "Export bug report" (moved from footer); privacy note (one paragraph: local-first, what touches the network); links: help/docs, contact.

## 6. Server health surfacing

The Hummingbird server can fail to bind (port taken) and today the failure is invisible (`try? await group.run()` swallows it) — the app looks alive while every hook 404s.

- Add an `@Observable ServerHealth` (owned by `AppDelegate` or the engine): states `starting / listening(port) / failed(reason)`. Set `failed` when `group.run()` throws or returns unexpectedly early; optionally self-probe `GET /healthz` after startup.
- Surface: red dot + *"can't listen on port 21321 — another app is using it"* in the popover connection bar and Settings → Advanced; onboarding step 4 uses it for troubleshooting (01 §3.4).
- Bind failure recovery: retry with backoff, and consider auto-fallback to a free port (write it to `config.json` so hooks follow — hooks read the port per-invocation, so this Just Works; do bump a `configVersion` and note it in diagnostics).

## 7. Menu bar behavior

- **Right-click menu**: status items conventionally offer a context menu. Implement `button.sendAction(on: [.leftMouseUp, .rightMouseUp])` and in the action check `NSApp.currentEvent?.type == .rightMouseUp` → show `NSMenu`: Open Buddygotchi, Settings…, Check for updates…, Pause watching (optional, see below), Quit. Left click keeps toggling the popover.
- **Pause/quiet hours (optional, nice)**: a "Pause for 1 hour" item that suppresses sounds/notifications/auto-show (state kept in `AppDelegate`; pet still animates). Mirrors the hardware's sleep/quiet-hours concept.
- Icon work is specced in 02 §6 (custom template blob + state dot).

## 8. Firmware sheet polish

`FirmwareUpdateView` is structurally good (reattachable, honest failure copy). Small items:

- The sheet can appear over the 320 pt popover at width 360 — wider than its parent. Present it within the popover width or as a standalone window (`NSPanel`) instead of a popover sheet; a mid-update panel also survives popover dismissal more naturally than the reattach dance.
- "Cancel" during `uploading` immediately kills the task and shows `failed("Update cancelled")` — soften: confirmation ("Stop the update? Your buddy keeps its current firmware.") since a 9-minute upload is expensive to lose (until 06 §5 makes it fast).
- Release notes render as plain `Text` — the manifest declares markdown. Render with `Text(AttributedString(markdown:))` fallback to plain.
- Show `publishedAt` ("released 2 weeks ago") next to the version when present — the field is parsed and then unused.
- Success state: have the desktop buddy do a celebrate blip too. The device just got smarter; mark the moment.

## 9. Assorted small polish

- `PopoverView.exportBugReport` writes to Desktop and reveals in Finder — good; move entry point to Settings (§1), add error surfacing (currently `catch {}` swallows write failures; show *"couldn't write to Desktop"*).
- `Text(species)` renders the raw id (`"cat"`); fine for lowercase brand voice, but capitalize display names via a `displayName` on species (and show `buddyName` when set).
- `ThinkingRow` elapsed time only updates when state versions bump — during a long stall nothing re-renders, so the timer freezes. Drive it with `TimelineView(.periodic(from:by: 1))` around the elapsed label.
- `ToolCardView` hint is `lineLimit(3)` monospaced — long paths truncate tail; use `.truncationMode(.middle)` for path-like hints (activityKind == .read/.write).
- Wizard/Settings species chevrons: add wrap-around haptic-ish blip (tiny scale pulse on the stage) so cycling feels alive.
- Audit `Divider()` usage post-retheme (02 bans strokes; grouped rows use the 8 %-opacity rule).
- Localization: not now, but route all strings through `BuddyCopy` (02 §5) so it's mechanical later.

## Acceptance criteria

- Popover never clips at any state combination in the snapshot harness (add a worst-case fixture: 6 sessions + approval card + queue label).
- An approval can be fully resolved from a notification without the popover ever opening.
- Sounds can be disabled; no sound plays when disabled; no double-sound when a notification fires.
- Killing the port (run `nc -l 21321` first, launch app) produces a visible failed-server state in popover + settings.
- Right-click on the menu bar icon shows the context menu; left-click still toggles.
- Settings About shows the bundle version, not a hardcoded string.
