# 02 — Theme & Design System: Make the App Look Like the Landing Page

Goal: the Mac app and the landing page should feel like one object. Today they don't share a single color, font, motion curve, or vocabulary rule. This doc defines the app-side design system derived from `landing/src/styles/globals.css`, `landing/SPEC.md` §4, and `research/product/MARKETING.md` §1.3, and lists every place the current app violates it.

## Current state (what's wrong)

`app/Buddygotchi/Theme/BuddyTheme.swift`:

- Accent is **purple `#9B8AFF`** — appears nowhere in the brand. Used for: busy state, thinking state, "connected" dot, primary buttons, toggles, install buttons, firmware badges, progress bars, wizard progress.
- Attention amber is `#FFBB33` (brand is `#E8A33D`), celebrate green is `#4ADE80` (neon; brand is sage `#7FA96B`), destructive is `#FF6B6B` (hot coral; brand's "stuck" is a *dim red heartbeat*, concern not alarm).
- Cards are `Color.white.opacity(0.07)` fills with 0.5 pt white strokes — the landing explicitly bans borders ("separation by whitespace"; where unavoidable, 15 % charcoal).
- Every view forces `preferredColorScheme(.dark)` over the default `NSPopover` material — the background is whatever the system vibrancy gives, not a designed surface.
- Type is `design: .rounded` everywhere (toy-like; brand is a modern grotesque, Geist, two weights) plus `.monospaced` for data.
- Motion: `PetStageView.onChange(of: petState)` uses `.spring(response: 0.3, dampingFraction: 0.5)` — a bouncy overshoot spring. Brand law: "eased, damped, never bouncy" with `cubic-bezier(0.22, 1, 0.36, 1)`.
- Copy violations (brand law bans `!`, requires sentence case, in-universe words): `"your buddy is ready!"`, `"Connected! Your buddy just cheered."` (SetupWizardView), Title Case buttons ("Get Started", "Install Hooks", "Pair Device", "Update Now", "Reset Setup"), out-of-universe jargon ("Install Hooks", "HTTP Port", "M5Stack Firmware", "Reinstall").

## 1. New `BuddyTheme` tokens

Replace the body of `app/Buddygotchi/Theme/BuddyTheme.swift` with tokens derived from the landing palette. The app surface is the landing's **night** passage (see 00-OVERVIEW cross-cutting decisions).

```swift
enum BuddyTheme {
    // MARK: Surfaces (landing --night family)
    static let night        = Color(hex: "#1B1714")   // popover/window background
    static let nightRaised  = Color(hex: "#27211B")   // card fill (one step up; replaces white-opacity fills)
    static let nightRaised2 = Color(hex: "#312A22")   // hover / elevated card

    // MARK: Text (landing --night-text = cream family)
    static let textPrimary   = Color(hex: "#EFE7D8")  // == --cream-deep; never pure white
    static let textSecondary = Color(hex: "#B9AE9C")  // cream at ~65%; verify ≥4.5:1 on night
    static let textTertiary  = Color(hex: "#877D6D")  // captions only, large-ish sizes

    // MARK: The light language (SPEC §5 S4 — these ARE the pet-state colors)
    static let amber     = Color(hex: "#E8A33D")      // needs-you; the ONLY interactive accent
    static let amberDeep = Color(hex: "#C9862B")      // pressed/hover
    static let green     = Color(hex: "#7FA96B")      // done / celebrate / verify
    static let stuckRed  = Color(hex: "#C96B5E")      // error — dim, warm, "concern not alarm"
    static let workGlow  = Color(hex: "#EFE7D8")      // working = warm-white breathing (glow only)

    // MARK: Shape
    static let cardCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 999     // pills, matching the landing CTA

    // MARK: Metrics
    static let popoverWidth: CGFloat = 320
    // heights become flexible — see 03 §1
}
```

Rules to enforce while retheming (grep-able):

- Delete `accent`, `accentSubtle`, `attentionAmber`, `celebrateGreen`, `destructive`, `connected`, `disconnected`, `cardFill*`, `cardStroke*` and fix every call site. Mapping: `accent → amber` (interactive), `busy/thinking tint → textSecondary or workGlow` (busy is *not* an accent moment — amber must keep meaning "you're needed"), `celebrateGreen → green`, `destructive → stuckRed`, `attentionAmber → amber`, `connected → green` (small dot) or `textSecondary`.
- **No borders**: `BuddyCardModifier` and `BuddyGroupedCardModifier` drop `strokeBorder` overlays entirely; cards are `nightRaised` fills with 12 pt radius and roomier padding (`.padding(14)`), separated by whitespace, not dividers where possible. Where a divider is truly needed (grouped settings rows), use `textPrimary.opacity(0.08)`.
- Set the background explicitly: give the popover root `ZStack { BuddyTheme.night.ignoresSafeArea() … }` and keep `preferredColorScheme(.dark)` so system controls harmonize. For a true opaque popover, set `NSPopover.appearance = NSAppearance(named: .darkAqua)` in `AppDelegate` and put the night color behind everything (the default popover material is translucent; opaque night reads more like the landing's S4 band — do it).
- No pure `#FFF`/`#000` anywhere (grep for `Color.white`, `Color.black` and replace with cream/night tokens at appropriate opacity).

## 2. Typography

- Bundle **Geist Sans** (SIL OFL 1.1 — redistribution in-app is allowed; keep the license file) at weights 400 and 600, plus **Geist Mono** 400 for hints/commands/versions.
  - Add `app/Buddygotchi/Resources/Fonts/Geist-Regular.otf`, `Geist-SemiBold.otf`, `GeistMono-Regular.otf` and register them in `Package.swift` target resources: `resources: [.copy("Resources/Fonts")]`.
  - Register at launch (SwiftPM bundles don't auto-register fonts): in `AppDelegate.applicationDidFinishLaunching`, iterate the font URLs and call `CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)`.
- Add helpers to `BuddyTheme.swift`:

```swift
extension Font {
    static func buddy(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .semibold ? "Geist SemiBold" : "Geist", size: size)   // verify PostScript names after embedding
    }
    static func buddyMono(_ size: CGFloat) -> Font { .custom("Geist Mono", size: size) }
}
```

- Type scale for the popover (mirrors landing ratios at popover scale): title 15/600, body 13/400, caption 11/400, tiny-label 9.5/600 with `.tracking(0.8)` and uppercase (the *only* permitted caps, e.g. `FOUNDING LITTER`-style section labels — use sparingly: "AGENTS", "DISPLAYS" in settings section headers).
- Replace every `design: .rounded` with `.buddy(...)`; every `design: .monospaced` with `.buddyMono(...)`. If font registration fails, `Font.custom` falls back to system automatically — acceptable.
- Fallback decision: if bundling Geist is rejected for any reason, use the system font (SF Pro, *default* design, not rounded) with weights regular/semibold only — that's still far closer to the brand than rounded.

## 3. Motion

Add to `BuddyTheme.swift`:

```swift
extension Animation {
    /// The blob's physics: eased, damped, no overshoot. cubic-bezier(0.22, 1, 0.36, 1).
    static func buddyEase(_ duration: Double = 0.5) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
}
```

- Replace every `.easeInOut(duration:)` and `.spring(...)` in `PopoverView`, `SetupWizardView`, `PetStageView`, `SettingsView` with `.buddyEase(…)`. Durations: 0.3–0.7 s for view/card transitions, 0.15 s for hover states, nothing bouncy. The `PetStageView` state-change "pop" (`petScale 1.06`) becomes a single damped ease up then down (`.buddyEase(0.25)` up, `.buddyEase(0.45)` down) — think a breath, not a boing.
- Port the landing's glow keyframes into the pet stage (`TimelineView`-driven, since SwiftUI keyframes must be code):
  - working: glow opacity oscillates 0.55→1.0 with a 4 s period (sinusoidal is fine — the CSS curve is close enough).
  - needs-you: amber pulse, 2.4 s period.
  - stuck: heartbeat at low duty cycle — bright for ~15 % of a 2.6 s period, dim otherwise (mirror `buddy-heartbeat` keyframes: two quick beats then rest).
  - asleep: static, near-off (0.05 opacity).
  - celebrate: one green ripple then fade — a single non-repeating ease, "not a rave" (PRODUCT.md §9.3).
- All continuous animation freezes under `accessibilityReduceMotion` (the views already read the environment — extend coverage to the glow).

## 4. The Blob: default buddy, drawn not typed

The landing page sells a specific creature (`landing/src/components/BuddyBlob.tsx`: squashed sphere ~wider than tall, face slightly above midline, two blush dots, expressions: content / alert / squint / sleep-with-peek / celebrate). The app greets you with ASCII cats. Fix:

- New file `app/Buddygotchi/Buddies/BlobBuddyView.swift`: a SwiftUI `Canvas`/shape rendition of the blob with the product's real proportions (PRODUCT.md §9.1 — squashed sphere, wider than tall, no limbs):
  - Body: an ellipse ~1.19:1 width:height (74×62 mm proportions) with a slightly flattened bottom; fill = a warm cream radial gradient (`#F7F2E9` core → `#EFE7D8` edge) so it reads as the frosted shell; the state glow renders *behind and through* it (radial gradient in the state color).
  - Face: two eyes (capsules) + optional mouth line, positioned above vertical midline; blush: two soft `amber.opacity(0.25)` circles flanking the face.
  - Expressions map from `PetState`: sleep = closed arcs (and an occasional one-eye peek every ~8 s, mirroring `buddy-peek-*`), idle = open + periodic blink, busy = slightly narrowed "focused", attention = wide + subtle upward look, celebrate = happy squints (inverted arcs) + 3–4 floating twinkle dots, error = dizzy (x x or spiral-lite), thinking = eyes drifting + a "…" that fades in/out.
  - Idle micro-motion: a very slow (6–8 s) ±1.5° rock or 1–2 px bob — damped, ambient.
- `PetStageView` becomes a switcher: `species == "blob"` renders `BlobBuddyView`; other species keep the existing ASCII renderer (recolored to the new palette — species accent colors in `BuddySprites.swift` should be resampled toward the warm palette rather than saturated hues; keep them distinguishable but muted).
- Add `"blob"` to `buddyOrder` as the **first** entry and change `Pet.defaultSpecies` to `"blob"`. The firmware already has `buddies/blob.cpp`, so hardware parity exists.
- Migration: existing users keep their stored `buddySpecies`; only fresh installs default to blob.

## 5. Copy system + brand-law enforcement

- New file `app/Buddygotchi/Theme/BuddyCopy.swift`: a single `enum BuddyCopy` (or struct of static lets) holding **every user-visible string** — wizard steps, settings rows and descriptions, card labels, buttons, notification bodies, firmware sheet copy. Mirror the structure of `landing/src/lib/copy.ts`.
- Rewrite the strings in-register while centralizing. Guidance and concrete replacements:
  - `"your buddy is ready!"` → `"Your buddy is ready."`
  - `"Connected! Your buddy just cheered."` → `"Connected — your buddy just cheered."`
  - `"Install Hooks"` → `"Connect"` (row subtitle explains: *"adds Buddygotchi to Claude Code's hooks — removable anytime"*)
  - `"Reinstall"` → `"Repair"` (it uninstall+installs; see 05)
  - `"M5Stack"` → `"Hardware buddy"` (Settings row detail may say `M5StickC Plus 2` in tertiary text)
  - `"M5Stack Firmware"` → `"Buddy firmware"`
  - `"HTTP Port"` → keep, but move under an "Advanced" disclosure (03 §5)
  - `"Reset Setup"` → `"Run setup again"`
  - `"Waiting for connection..."` → `"listening for your agent…"` (and use a real ellipsis `…` everywhere, not `...`)
  - Buttons: sentence case — `"Get started"`, `"Update now"`, `"Try again"`, `"Pair device"` → `"Pair a buddy"`.
- Add `app/Tests/CopyRulesTests.swift`: reflect over `BuddyCopy` (or keep the strings in a `[String]` manifest the test imports) and assert: no `!`, none of the banned words (revolutionary, supercharge, AI-powered, productivity, game-changer, premium), no `...` (require `…`), and no ALL-CAPS words longer than 4 chars outside an allow-listed tiny-label set. This is the Swift twin of `landing/tests/copy-rules.test.mjs`.
- Sweep for stragglers after centralizing: `rg -n '"[^"]*!"' app/Buddygotchi` should return nothing user-visible.

## 6. Menu bar icon

- Today: per-state SF Symbols (`moon.zzz`, `circle`, `brain`, …) — generic, width-jittery, and semantically noisy.
- Replace with a custom **template** blob glyph (monochrome, 18×18 pt PDF/asset, `image.isTemplate = true`) with small state variants: asleep (closed eyes), neutral, and a badge dot for the states that matter. State communication moves to a 3 px badge dot at the blob's corner: amber = needs you, green = just finished (during celebrate window), dim red = stuck, none = working/idle. Template images can't carry color, so composite: draw the template blob, then draw the dot as a separate colored layer via `NSImage(size:flipped:drawingHandler:)` with `button.image` regenerated on state change (keep the existing `lastIconSymbol`-style dedupe).
- Keep an accessibility description per state ("Buddygotchi — needs you", etc.).
- App icon (`.icns`, needed for 06 packaging): the blob on a night-rounded-rect background with an amber glow — commission/generate once, spec: matches `landing/src/app/icon.svg` proportions.

## 7. Snapshot coverage

- Update `SnapshotHarnessTests` fixtures for: sleep/idle/busy/attention/celebrate/error/thinking popover, approval card, review card, error card, multi-session list, settings, each wizard step, firmware sheet states. These are the regression net for the retheme — land them in the same PR as the theme change and eyeball every PNG in `/tmp/buddy-snapshots`.

## Acceptance criteria

- No occurrence of `#9B8AFF`, `Color.white.opacity`, `design: .rounded`, or `.spring(` in `app/Buddygotchi/` (except deliberate, commented exceptions).
- Popover background is opaque night `#1B1714`; every color on it comes from `BuddyTheme` tokens; amber appears only for needs-you states and primary actions.
- Geist renders in the popover (verify via snapshot harness; check the actual PostScript names with `CTFontManagerCopyAvailablePostScriptNames` if `.custom` shows fallback).
- Default species for fresh installs is `blob`, rendered as vector with working expression set for all 7 `PetState`s.
- `swift test --filter CopyRulesTests` passes and fails if someone adds `"Done!"`.
- All state-glow animations pause under Reduce Motion.
