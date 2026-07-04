# 08 — Pass 2: Mac App Bugs & Regressions

Each item: what's wrong, why it matters, how to fix. File references are to current `main` (`4cc4a1a`).

## 1. (P0) `approvalMode` is frozen at launch in the hook server

`buildHookServer` captures `config: BuddyConfig` once; `handleAgentEvent(..., approvalMode: config.approvalMode, ...)` uses that snapshot for the `Notification/permission_prompt` skip. The hook script and SignalCLI read `config.json` **live** per invocation, so after a runtime toggle the two halves disagree:

- Toggle **on** after launch: script routes `PermissionRequest` to `/hook/approve` (blocking card) *and* the server still creates a passive card from the `permission_prompt` notification (snapshot says off) → two prompts for one request with different IDs; the passive one lingers until `PostToolUse`/resolution churn clears it.
- Toggle **off** after launch: snapshot says on → passive `permission_prompt` cards are suppressed until app restart → the user loses passive awareness entirely.

**Fix:** stop passing a value; pass a provider. `buildHookServer(engine:config:isApprovalModeEnabled: @Sendable () -> Bool)` where the closure reads `UserDefaults.standard.bool(forKey: DefaultsKey.approvalMode)` (Settings already keeps that current via `@AppStorage` + `BuddyConfig.setApprovalMode`). Longer term this is the pass-1 `ConfigStore` item (04 §2.1) — `approvalMode` still lives in three places and this regression is exactly the drift it predicted. Add a server-level test: build router with a mutable flag, flip it between two `permission_prompt` posts, assert prompt-creation behavior follows.

## 2. (P0) The onboarding window is a trap

`OnboardingWindowController` uses `styleMask: [.titled, .fullSizeContentView]` — no `.closable`, no miniaturize. Esc only steps backward and does nothing at step 0. The app is `LSUIElement` (no Dock icon) and a brand-new user hasn't found the menu bar icon yet, so there is **no way to dismiss the window short of force-quitting**. Premium onboarding never traps.

**Fix:** add `.closable` to the style mask; treat window close as "finish later" (state is already persisted per-step, and `PopoverView.unfinishedSetupView` already exists as the resume path). Optionally show the menu-hint arrow copy when closing early so the user knows where the app lives. Keep `isReleasedWhenClosed = false` (already set).

## 3. (P0) Remove the launch-time notification permission request

`AppDelegate.applicationDidFinishLaunching` still calls `NotificationManager.shared.requestPermission()` (line ~65). Pass 1's contextual flow was built — onboarding's done step has the "Enable notifications" button, and `postToolNotification` lazily requests on `.notDetermined` — but the launch call preempts both: on a packaged first launch the system dialog appears over the hatch screen, and the onboarding button becomes a no-op rubber stamp.

**Fix:** delete the call. Nothing else needs to change; both contextual paths already exist. Acceptance: fresh install, packaged app → no system dialogs until the user clicks "Enable notifications" (or the first prompt-notification moment, whichever comes first).

## 4. Uninstaller gaps

`ConsumerUninstaller.removeInstalledState()`:

- Doesn't remove the `"installedAgents"` key (it's a private constant in `HookInstaller`, absent from `DefaultsKey`). After remove + reinstall, launch verification resurrects ghosts. Move `installedAgents` into `DefaultsKey` and clear it here.
- `HookInstaller.uninstall` silently no-ops when an agent config is unparseable (`try?` guards) — the flow then reports success while hooks remain. Make uninstall collect per-agent outcomes and have the removal alert list anything it couldn't clean ("Cursor hooks.json couldn't be read — remove the Buddygotchi lines by hand"), linking the SUPPORT.md manual section.
- Sparkle writes `SU*` defaults once it runs (last-check date etc.) — clear the app domain wholesale instead of key-by-key: `UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? …)` when a bundle id exists, falling back to the current list under `swift run`.

## 5. Abandoned pairing leaves a saved device

`OnboardingView.chooseDevice` writes `esp32PeripheralUUIDKey` **before** pairing succeeds. If pairing times out and the user picks "Back to list" or switches output to "This Mac", the UUID stays saved → `ESP32Output.connectToSavedDevice()` on every future launch reconnect-loops against a device the user never finished pairing (and Settings shows a paired "Hardware buddy" row they never confirmed).

**Fix:** hold the candidate UUID in model state only; persist it in the `connectionState == .connected` handler (where `sendTestCelebrate` fires). On "Back to list" / output change / step exit without connection, `UserDefaults.removeObject(forKey:)` + `esp32Output.unpair()` if a connect attempt is in flight. Same pattern applies to `SettingsView`'s scan list (it also saves before connecting).

## 6. `checkForUpdatesFromMenu` doesn't check for updates

The status-item menu's "Check for updates…" calls `openSettingsFromMenu()`. It should call `SparkleUpdateManager.shared.checkForUpdates()` directly (falling back to the settings "unavailable" alert path when `!isAvailable`). Menu items that say X should do X.

## 7. Corrupt `config.json` self-heal is silent and inconsistent

`BuddyConfig.readOrCreateConfig` on an unparseable file falls through and **rewrites defaults** — custom port silently lost, token regenerated (hooks follow the file so nothing breaks, but the user's choice evaporates without a trace). Meanwhile `HookInstaller.verifyCommon` reports `corrupted("config.json is not valid JSON")` as *non-repairable* — but by the time verify runs, `BuddyConfig.default` has already replaced the file, so the state is unreachable in practice. Tidy both: log the self-heal to `DiagnosticLog` ("config.json was unreadable — recreated with defaults"), and drop the config.json branch from `verifyCommon`'s non-repairable set (or make `HookHealth.corrupted` carry a structured `repairable: Bool` instead of string-matching `reason.contains("not valid JSON")` — the current string matching is exactly the fragility pass 1 warned about, now load-bearing).

## 8. Launch verification does double work

`verifyManagedHooksAfterLaunch` calls `HookInstaller.shared.verify(agent:)` inside the `agents` filter and then again in the loop body — six full file-system verifications for three agents. Verify once into a dictionary, then act. Cosmetic, but it's on the launch path.

## 9. The Deny keyboard shortcut is broken

`ToolCardView`'s Deny button chains `.keyboardShortcut(.delete, modifiers: []).keyboardShortcut("d", modifiers: [])` — SwiftUI keeps only one (the outermost modifier wins); the hover hint advertises `⌫` which may be the dropped one. Pick a single shortcut (recommend ⌫ to match the hint) and delete the second modifier; if both are truly wanted, attach the second to a hidden zero-size button with the same action.

## 10. Popover pinning is still inverted (carried from pass 1, now explicit)

`DesktopOutput.updateInteractiveMode` → `presenter.showPopover(isApproval: next.prompt?.isApproval == true, …)` → `AppDelegate.showPopover` sets `.transient` for approvals and `.applicationDefined` (pinned, click-through-proof) for everything else. Net effect: the *actionable* surface (approval) dismisses if you click anywhere, while a celebrate auto-show pins itself for 3 s and eats a click. Decide once: recommend always `.transient` (notification + badge already provide persistence) — that also lets `showPopover(isApproval:dismissAfter:)` collapse to one parameter. If pinning survives anywhere, it should be for approvals, not against them.

## 11. Prompt expiry is still missing (pass-1 04 §3.6, half-done)

The timeout ladder was aligned (curl 300 s, hook timeout 310 s) but the reducer rule wasn't added: after the hook's curl gives up at 300 s, the card stays visible until the 10-minute stale reap — up to 5 minutes of a ghost approval whose Approve button resolves a continuation nobody is listening to (the HTTP response goes to a closed socket; the agent already fell back to its native dialog, so the user can *think* they approved while the agent still waits natively — a real confusion vector). Add `approvalTimeoutMs` (300_000) to `InternalState`; in `handleStaleTick`, clear prompts where `now - prompt.arrivedAt > approvalTimeoutMs` (engine side: resolve the continuation `.passthrough` — reuse the removed-session path by having the engine diff cleared prompts, or give the engine its own sweep over `pendingApprovals` keyed by arrival time). Reducer test + engine test.

## 12. Cursor process watchers probably bind to the wrong process

Pass 1's SignalCLI change now sends `pid` on `/hook/signal`, and `sessionStarted(hookPid:)` runs `resolveAncestor` = parent-of-parent. That walk was calibrated for the bash script (`script ← shell ← agent`). Cursor spawns `buddygotchi-signal` **directly** (no intermediate shell — `hooks.json` commands may exec without `sh -c` depending on Cursor's runner), in which case parent = Cursor and grandparent = launchd session leader or Cursor's own parent — watching the wrong thing either reaps sessions instantly or never. Before trusting it: log `proc_name` of the resolved ancestor to diagnostics (pass-1 04 §3.5's name check, still unimplemented), and only install the watcher when the name looks like an agent (`Cursor`, `claude`, `node`, `codex`, `bun`). Until then, consider not passing `hookPid` from `/hook/signal` (Cursor has explicit `sessionEnd` + stale reap as its cleanup story, which was the previous, safe behavior).

## 13. Small but real

- `ServerHealth.status = .listening` is set *before* `group.run()` attempts to bind — a taken port shows "Listening" for a beat before flipping to failed. Set `.listening` after a successful self-probe of `/healthz` (or at minimum move the assignment after `run()` has been given ~200 ms without throwing).
- `AppDelegate.showOnboardingWindow` falls back to `ESP32Output()` when `esp32Output` is nil — that path can't happen (it's set earlier in launch); replace with a precondition or reorder so the real instance is always passed. A second `ESP32Output` would register a second keepalive timer against nothing.
- `hookHealthColor` returns SwiftUI `.orange` — off-palette; use `BuddyTheme.amber` (or `stuckRed` for corrupted). `hookHealthLabel` uses `" - "`; brand punctuation is an em dash.
- `AgentKind.configDir` (file-global `defaultHomeDir`) duplicates `HookInstaller.configDir(for:)`; the property is now unused or nearly so — delete it so no future caller bypasses the injected home.
- `DiagnosticLog` rawPayload retention/redaction (pass-1 04 §3.7) remains open: cap raw payloads to the newest ~20 entries and add the "may contain file paths and commands" note to the export bundle.
- `isAuthorized` compares tokens with `==` — fine for the threat model, but a constant-time compare is one line if you're touching the file.
- `BLEScanner` still constructs a fresh `BLEManager`/central per scan (pass-1 04 §3.7). With the lazy-central change the cost is small; still worth consolidating to one scanner-owned manager when convenient.

## Acceptance criteria

- Runtime approval-mode toggle: with the app running, enable approval mode, trigger a Claude Code permission prompt → exactly one (blocking) card; disable it, trigger again → exactly one passive card. No restart.
- Fresh packaged install: no system permission dialog before the onboarding notifications step; the onboarding window has a close button; closing it and clicking the menu bar icon shows the resume card.
- Abandon a pairing (let it time out, go back) → relaunch app → no reconnect attempts, Settings shows "Not paired".
- "Remove Buddygotchi" on a machine with a corrupt `~/.cursor/hooks.json` reports what it couldn't remove instead of claiming success.
- An approval left unanswered for 6 minutes has disappeared from the popover on its own (and diagnostics show a passthrough resolution).
- ⌫ triggers Deny while an approval card is focused.
