# 09 — Pass 2: Brand Fit & Finish

The theme retrofit landed structurally (tokens, borderless cards, damped motion, blob default). This doc covers the distance still remaining between "themed" and "indistinguishable from the landing page" — including one item that looks done but isn't.

## 1. (P0) Geist does not exist in this repository

Every text style calls `.buddy()` → `Font.custom("Geist"/"Geist SemiBold"/"Geist Mono", …)`, and `AppDelegate.registerBundledFonts()` scans `Resources/Fonts/` — but `app/Buddygotchi/Resources/` contains **only Info.plist**. There are no font files, no `resources:` declaration in `Package.swift`, and `package.sh` copies no fonts into the bundle. Result: every string in the app renders in the SF fallback, in dev *and* in the packaged app, silently. The type system is currently fiction.

**Fix, concretely:**

1. Vendor the fonts: `Geist-Regular.otf`, `Geist-SemiBold.otf`, `GeistMono-Regular.otf` (SIL OFL 1.1 — include `OFL.txt` alongside) into `app/Buddygotchi/Resources/Fonts/`.
2. `Package.swift`: add `resources: [.copy("Resources/Fonts")]` to the Buddygotchi target (keep the Info.plist `exclude`). Note SwiftPM puts these in `Buddygotchi_Buddygotchi.bundle` — `Bundle.main.resourceURL` won't see them under `swift run`. Use `Bundle.module` in the registration helper instead of `Bundle.main`, and have `package.sh` copy the built `.bundle` into `Contents/Resources/` (SwiftPM executables expect the bundle next to the binary — copy it into `Contents/MacOS/` as well, or register from both candidate locations).
3. Verify actual PostScript names post-registration (`CTFontManagerCopyAvailablePostScriptNames`); Geist's are likely `Geist-Regular` / `Geist-SemiBold` / `GeistMono-Regular`, which means the current `.custom("Geist SemiBold", …)` string is wrong even once files exist. Centralize the names as constants next to the registration code.
4. Add a debug assertion (DEBUG builds only) after registration: if `NSFont(name: geistSemiBoldName, size: 12) == nil`, log loudly to diagnostics. That converts the silent-fallback failure mode into a visible one forever.
5. Snapshot fixtures will shift — regenerate and eyeball.

If vendoring is refused, the honest alternative stands (pass-1 02 §2): change `.buddy()` to system font and delete the registration code. Either is fine; the current in-between is the only wrong state.

## 2. The popover surface isn't the night surface

Only `unfinishedSetupView` paints `BuddyTheme.night`. `liveView` and `SettingsView` sit on the default translucent `NSPopover` material (dark-vibrancy gray), so the app's main surface doesn't match the onboarding window or the landing S4 band, and token colors composite over vibrancy unpredictably.

**Fix:** wrap the popover root in `ZStack { BuddyTheme.night.ignoresSafeArea() … }` (one place — `PopoverView.body`), and kill the material behind it by giving the hosting view an opaque layer: set `popover.contentViewController?.view.wantsLayer = true` isn't enough for NSPopover's frame — the reliable approach is an `NSView` subclass overriding `viewDidMoveToWindow` to walk to the popover's `_NSPopoverFrame`… don't. The pragmatic version: the ZStack fill covers everything except the popover's border chrome and arrow; then set `popover.appearance = NSAppearance(named: .darkAqua)` (already effectively true) and accept the arrow tinting. If the arrow mismatch bothers, `NSPopover.hasFullSizeContent` (macOS 14+) plus the fill gets edge-to-edge night. Verify with a snapshot.

## 3. The blob doesn't speak the light language yet

`BlobBuddyView` has a static glow opacity per state with a generic bob/rock. The landing page (and `globals.css`) define specific, recognizable rhythms — this is the brand's core visual vocabulary and the whole point of the S4 section:

| State | Landing spec | Blob today | Fix |
| --- | --- | --- | --- |
| working | warm breathing, **4 s period** (`buddy-breathe`: opacity 0.55→1, scale 1→1.04) | static 0.28 | modulate glow opacity+scale with `sin(t·2π/4)` |
| needs-you | amber pulse, **2.4 s** (`buddy-amber`: 0.5→1) | static 0.38 | 2.4 s sinusoid on the amber glow |
| stuck | heartbeat, **2.6 s, low duty cycle** (bright ~15/30 % keyframes, dim rest) | static 0.38 | piecewise duty-cycle function, not a sine |
| done | **one** green ripple then fade, "not a rave" | 4 twinkles looping forever at 3.2 s | play ripple + twinkles once on entry (track state-entry time via `.onChange`), then settle to a quiet contented glow for the rest of the celebrate window |
| asleep | dark; occasional **one-eye peek** (`buddy-peek`, ~8 s cycle) | both eyes closed, static | one eye opens for ~1.5 s every ~8 s |
| thinking | drifting "…" | "…" mouth exists — good | fade the dots in/out slowly |

Implementation stays in the existing `TimelineView` — these are all pure functions of `t` and state-entry timestamp. Two efficiency notes while in there: drop the tick rate by state (sleep/idle don't need 10 Hz — 2 Hz reads identically; the popover is the only visible instance but the onboarding window also hosts one), and gate all of it on `reduceMotion` (already plumbed).

## 4. Sounds are still system sounds

`DesktopOutput` defaults remain `Funk`/`Glass`/`Sosumi`. The toggle landed; the character didn't. Pass-1 03 §3 stands verbatim: three short chirps (attention "meep?", celebrate trill, error "oof") as `.caf` files in `Resources/Sounds/`, played via `NSSound(contentsOf:)`, following the firmware sound rules (≤3 notes, volume cap). This also unblocks the firmware side reusing the same motifs (10 §3). Bundle plumbing is shared with §1 — do them together.

## 5. Copy law is enforced on a shrinking fraction of the copy

`BuddyCopy.manifest` is a **hand-maintained array**; anything not added to it escapes `CopyRulesTests`. Today that's most of the app: ~33 inline `Text("…")` strings in `SettingsView` alone ("Launch at Login", "Route tool approvals through…", "Remove and quit", the removal alert body), `EmptyAgentsView`'s guidance line, `ErrorTrailerView`'s "Also: … hit an error", onboarding's `"Back"/"Next"/"Skip"` and the interpolated `"Heard from \(name)."`, notification titles in `NotificationManager`, `hookHealthLabel` strings. The enforcement mechanism exists but the moat is dry.

**Fix in two moves:**

1. **Make the manifest impossible to forget.** Replace the array with reflection: restructure `BuddyCopy` as nested structs of `let` String properties on a singleton instance, then walk it with `Mirror` (recursing into children) to collect every `String` — the test covers new strings automatically. (Static-let enums can't be mirrored; the instance-property shape is the price and it's fine.)
2. **Finish the migration.** Move the remaining user-visible strings into `BuddyCopy` (settings, popover empties/trailers, notification title format, health labels, onboarding chrome buttons). Interpolations become functions (`BuddyCopy.heardFrom(_ agent: String) -> String`) whose *template* lives in a tested constant.

Then add one cheap ratchet: a test that greps the Views directory sources (readable at test time via `#filePath`-relative path) for `Text("` with a letter following and fails on new occurrences above a recorded baseline — crude, but it stops regression while the migration completes. Delete it when the count reaches zero.

## 6. Settings polish still owed (pass-1 03 §5 leftovers)

- **Approval-mode explainer**: the toggle still flips silently. First enable → small sheet: what changes, the Cursor auto-approve rules, fail-open promise, confirm button. One `@AppStorage("approvalModeExplained")` gate.
- **Name your buddy, later**: `buddyName` is settable only during onboarding. Add the name field to the Buddy section (same styling as onboarding's). The status pill already prefers the name — this is a 20-line change with outsized affection ROI.
- **Species preview**: clicking the buddy in Settings/onboarding should cycle a state preview (idle → attention → celebrate) so people see what they're choosing. The stage view already renders any state; drive it from a local `@State` + timer on click.
- "Run setup again" is tinted `stuckRed` — it's not destructive; use plain secondary. Keep red for Quit/Remove.

## 7. Micro-notes

- `BuddySpecies` blob entry reuses `catStates` for its ASCII frames — harmless (PetStageView branches to `BlobBuddyView` first) but `renderFrame` on species "blob" would draw a cat; make the mapping explicit or assert unreachable.
- Menu-bar hint (`showMenuHint`) auto-clears after 4 s *of popover visibility* — good; but it's set on every onboarding finish including "Run setup again" reruns. Fine; just noting intent.
- `statusIcon` badge colors are hard-coded sRGB triplets duplicating `BuddyTheme` values — derive them from the shared hexes so a palette tweak can't fork.
- The onboarding hatch egg never wobbles before cracking (spec said "rocks slowly"); one `rotationEffect(sin(t)·2°)` on the egg while `!didHatch` completes the beat.

## Acceptance criteria

- `NSFont(name:)` resolves all three Geist faces in a packaged build *and* under `swift run`; a snapshot diff shows the type actually changed.
- Recording the popover for 10 s in each state shows: 4 s breathing (busy), 2.4 s amber pulse (attention), duty-cycle heartbeat (error), a single celebrate ripple, a sleep peek within 10 s.
- `CopyRulesTests` fails when any *new* `let` is added to `BuddyCopy` containing `"!"` — without touching a manifest.
- Popover background samples as `#1B1714` in a screenshot.
- Attention plays a chirp that no macOS system sound shipped.
