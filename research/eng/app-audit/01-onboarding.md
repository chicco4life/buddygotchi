# 01 — Onboarding: An Adoption, Not a Setup Wizard

Goal: the first five minutes should feel like the landing page promised — you adopted a small creature, it hatched, it met your agents, and it came alive. Today the first five minutes are: nothing happens, then a Bluetooth permission dialog, then (if you find the menu bar icon) a cramped 6-step form in a popover.

Depends on: 02 (theme tokens, BlobBuddyView, BuddyCopy). The P0 items in §1 and §4 can land immediately without the retheme.

## Current state

- `SetupWizardView` renders inside the 320×440 popover when `setupCompleted == false`. Steps: welcome → connect agent → test connection → personalize → display output → done.
- **Nothing opens on first launch.** `AppDelegate.applicationDidFinishLaunching` builds the status item and popover but never shows it. A first-time user double-clicks the app and sees no window, no dock icon (LSUIElement), no hint.
- **Permission ambush:** `NotificationManager.requestPermission()` fires at launch (before the user knows what the app is), and `ESP32Output.start → BLEManager.init → CBCentralManager(delegate:queue:)` triggers the macOS Bluetooth permission dialog at launch even for users with no hardware.
- The connect step's "Install Hooks" buttons fail silently (`install()` returning false does nothing visible).
- The test step watches `engine.state.desktop.status == .connected` and auto-advances 2 s later — it never says *which agent* it heard.
- Species/output selections are only persisted on the final "Done" — quit midway and everything is lost.
- The M5Stack pairing sub-flow has no timeout/retry: pick a device and if pairing stalls you're stuck on a spinner with no cancel.
- Copy violates brand law ("your buddy is ready!", "Connected! Your buddy just cheered.").

## 1. First launch must present itself (P0, do first)

Minimal immediate fix (independent of the redesign):

```swift
// AppDelegate.applicationDidFinishLaunching, after popover setup:
if !UserDefaults.standard.bool(forKey: "setupCompleted") {
    NSApp.activate(ignoringOtherApps: true)
    togglePopover()   // or show the onboarding window from §2 once it exists
}
```

Also handle re-launch of an already-running instance (see 06 §7): `applicationShouldHandleReopen` → show popover.

## 2. Move onboarding into a real welcome window

A 320 pt popover cannot deliver a premium first run. Create a dedicated window:

- New file `app/Buddygotchi/Views/Onboarding/OnboardingWindowController.swift`: an `NSWindow` (`.titled, .fullSizeContentView`, `titlebarAppearsTransparent = true`, `isMovableByWindowBackground = true`, not resizable), ~**760×560**, centered, night background, hosting `OnboardingView`. Owned by `AppDelegate`; shown when `!setupCompleted`, closed via the flow's finish. Keep `NSApp.setActivationPolicy(.accessory)` but `NSApp.activate(ignoringOtherApps: true)` when showing.
- Split the current monolithic `SetupWizardView` into `Views/Onboarding/` step files (`WelcomeStep.swift`, `AdoptStep.swift`, `AgentsStep.swift`, `FirstContactStep.swift`, `DisplayStep.swift`, `DoneStep.swift`) plus an `OnboardingModel` (`@Observable`) holding step index, selections, and per-agent status. Persist every selection the moment it's made (write `buddySpecies` etc. immediately), so quitting mid-flow loses nothing.
- The wizard-in-popover path is deleted; `PopoverView` renders a small "finish meeting your buddy" card (button reopens the window) if `!setupCompleted`.
- Keyboard: ⏎ advances, Esc goes back (never quits), all controls focusable. Progress: keep the segmented capsule bar but restyle with tokens (amber fill on night, `buddyEase` animation).
- Transitions between steps: horizontal slide + fade with `.buddyEase(0.45)` (already close to this; retune the curve).

## 3. The new arc (6 steps, emotionally reordered)

Adopt-first: fall in love, then do the practical part, then the payoff moment.

### Step 1 — Hatch (the welcome)

- A large egg (SwiftUI shapes, mirroring the `/welcome` page's egg-crack animation and the firmware's first-boot hatch: PRODUCT.md §10.2 "this is the unboxing moment") sits center. It rocks slowly; after ~1.5 s (or on click) it cracks and the blob peeks out, then pops free with a damped ease.
- Copy: heading **"Someone's been waiting for you."**, sub *"A little creature that watches your AI agents — and only bothers you when it matters."* (reuse the landing subhead verbatim; one brand voice). Button: **"Meet your buddy"**.
- Reduce Motion: egg pre-cracked, blob visible, no rocking.

### Step 2 — Adopt (species + name)

- The species carousel (blob first/default), rendered large (the window has room — 200 pt stage), with left/right chevrons and click-to-cycle; the buddy plays its `idle` animation and reacts with a tiny celebrate blip when selected.
- **Add an optional name field** ("Name your buddy — optional", placeholder "Mochi"). Store as `buddyName` in UserDefaults. Downstream: popover status pill shows the name when set ("Mochi · busy"); notifications say "Mochi needs you"; the heartbeat can carry it later (additive `RenderState` field, safe per the wire-contract rule). Pets with names get kept.
- Button: **"Adopt"**.

### Step 3 — Connect your agents

- Rows for Claude Code / Cursor / Codex, each showing detection state (`HookInstaller.detectInstalledAgents()`), with a single **"Connect"** button per row → `install(agent:)`.
- Handle failure visibly: if `install` returns false, the row shows *"couldn't write the hook — check permissions"* in `stuckRed` with a "Try again" affordance, and the diagnostic log records the reason (05 adds real error reasons to the installer; surface `HookInstallError.description` here).
- Auto-connect-detected option: if exactly one agent is detected, preselect and connect it on entry (still visible + reversible). Zero-decision path for the common case.
- Next is disabled until ≥1 connected (unchanged), but add a quiet **"skip for now"** text button — never trap the user.
- Detection copy is honest: "Not detected" rows still allow connecting (the config dir is created), with tertiary text *"haven't seen this agent on your Mac yet"*.

### Step 4 — First contact (the payoff)

This is the "moment of life" and deserves theatrics:

- The buddy sits asleep. Copy: **"Wake it up."** / *"Open ⌘Claude Code (or Cursor, or Codex) and send any message."* Optionally a "copy a test prompt" button that puts `say hi to my buddygotchi` on the clipboard.
- Watch `engine.state.activeSessions` (not just `desktop.status`): on the first session appearing, read its `source`, map through `AgentKind.displayName`, and show **"Heard from Claude Code."** with the buddy waking → celebrate ripple (this is the "Heard from Codex (desktop)!" moment from PRODUCT.md §12.1, minus the exclamation mark). Auto-advance after 2.5 s (keep).
- If nothing arrives in 60 s, surface gentle troubleshooting inline: bullet list — *agent restarted since connecting? server running (green dot below)? port busy?* — plus the `/healthz` self-check result (03 §6 adds a `ServerHealth` observable; show its status dot here).
- "Skip" remains.

### Step 5 — Where your buddy lives

- Same options as today ("This Mac" default; hardware buddy optional) restyled; drop the confusing third "Buddygotchi Device — Coming Soon" row and instead put a small footnote under the hardware option: *"works with an M5StickC Plus 2 today; the Buddygotchi hardware buddy hatches later this year."*
- Hardware pairing sub-flow fixes:
  - Scanning list (unchanged mechanics) with device rows.
  - After selecting: show the passkey instruction *and* a 30 s timeout → *"couldn't pair — hold the buddy closer and try again"* with Retry / Back to list buttons (today it spins forever).
  - On success: buddy celebrates on the device (`sendTestCelebrate()`, existing) and on screen simultaneously — copy *"Connected — your buddy just cheered."*
  - This is the **only** step that may construct a `BLEManager` (see §4).

### Step 6 — Done (the adoption card)

- Render a small "adoption card": buddy portrait, name, species, connected agents as chips, display choice — laid out like a card from the landing's adoption box (S6). It's a screenshot-able moment.
- Launch at Login toggle, **default ON** (pre-toggled but visible and clearly flip-off-able; a companion that dies on reboot isn't a companion). Note: only functional from a packaged app (06) — under `swift run`, show the toggle disabled with tertiary text.
- Notification permission is requested **here**, with context, via an explicit row: *"Let your buddy tap you on the shoulder — one notification when an agent needs you."* [Enable notifications]. Calling `requestPermission()` only on that click. (Remove the launch-time call — §4.)
- Finish button: **"Start watching"** → sets `setupCompleted`, closes window, opens the popover once pointing at the menu bar icon with a one-time arrow/hint ("your buddy lives here now").

## 4. Permission choreography (P0)

- **Remove** `NotificationManager.shared.requestPermission()` from `applicationDidFinishLaunching`. Request it (a) in onboarding step 6 via the explicit row, or (b) lazily at the moment the first notification would be posted, whichever comes first. If denied, `postToolNotification` no-ops and Settings shows a row with a "open System Settings" deep link (`x-apple.systempreferences:com.apple.preference.notifications`).
- **Defer Bluetooth:** `BLEManager` must not construct `CBCentralManager` in `init`. Make the central lazy — create it on first call of `startScan()`/`connect(peripheralIdentifier:)`. `ESP32Output.start` only calls `connectToSavedDevice()` when a saved UUID exists, so users who never paired never see the Bluetooth dialog. Implementation: `private var central: CBCentralManager?` + `private func ensureCentral() -> CBCentralManager` on `bleQueue`; guard every use. (Also listed in 04 §3.4.)
- Result: launch is permission-silent; each dialog appears attached to a user intention.

## 5. Copy for the whole flow lives in `BuddyCopy`

All step strings from §3 go into `BuddyCopy.onboarding.*` and are covered by `CopyRulesTests` (02 §5). Register: lowercase-hearted, dry, in-universe; zero exclamation marks.

## Acceptance criteria

- Fresh profile (`defaults delete` the app domain, clean `~/.buddygotchi`): launching the app immediately shows the welcome window, frontmost; no permission dialogs appear until their designated step.
- Killing the app at any step and relaunching resumes with prior selections intact.
- Connecting only Codex and sending a message shows "Heard from Codex." specifically.
- A failed hook install is visible and retryable; the failure reason lands in the diagnostic log.
- BLE pairing has a visible timeout/retry path; Bluetooth permission never appears for users who choose "This Mac".
- The snapshot harness gains fixtures for each onboarding step.
- `setupCompleted == true` users never see the window; "Run setup again" in Settings reopens it (and re-runs verification, 05).
