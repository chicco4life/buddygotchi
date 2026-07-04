# 06 — Consumer Readiness: Packaging, Updates, Firmware Delivery, and the Missing Table Stakes

Goal: everything a person expects from a paid consumer Mac product: a signed, notarized `.app` that updates itself; firmware that hosts, updates, and first-flashes; clean install/uninstall; and the operational scaffolding (release automation, support surface). This doc turns `research/product/PLAN.md`'s "Remaining Production Work" list into concrete implementations.

## 1. A real `.app` bundle (everything else depends on this)

Today `swift build` produces bare executables; `Bundle.main.bundleIdentifier` is nil, so **notifications are silently disabled** (`NotificationManager.setup` guard), **`SMAppService` Launch-at-Login can't work**, Sparkle can't work, and permissions (Bluetooth) attribute to the wrong identity.

Build a packaging script — `app/tools/package.sh` (invoked as `make package`) — that assembles the bundle from SwiftPM release output (no Xcode project needed):

```
Buddygotchi.app/
  Contents/
    Info.plist                # full plist, superset of the current -sectcreate one
    MacOS/Buddygotchi         # swift build -c release artifact
    MacOS/BuddygotchiSignal   # helper (copied to ~/.buddygotchi/bin at runtime, 05 §3)
    Resources/AppIcon.icns    # 02 §6
    Resources/Fonts/…  Resources/Sounds/…
    Frameworks/Sparkle.framework   # §2
```

Info.plist keys: `CFBundleIdentifier` = `com.buddygotchi.mac` (pick once, never change — it keys notifications, login item, defaults migration), `CFBundleShortVersionString`/`CFBundleVersion` (injected by the script from a `VERSION` file or git tag), `LSUIElement` = true, `LSMinimumSystemVersion` = 14.0, `NSBluetoothAlwaysUsageDescription` (exists), `CFBundleIconFile`, `NSHumanReadableCopyright`, Sparkle keys (§2).

Signing & notarization (extend the same script, gated on env vars so CI and local dev both work):

1. `codesign --force --options runtime --timestamp --sign "Developer ID Application: …"` — sign `BuddygotchiSignal` and Sparkle's nested bits first, then the app. Hardened runtime entitlements: none needed beyond defaults (no JIT, no unsigned memory); Bluetooth/notifications need no entitlements for Developer ID distribution.
2. `ditto -c -k` zip → `xcrun notarytool submit --wait` → `xcrun stapler staple`.
3. Distribute as a DMG (`create-dmg`, cream/night background image with the drag-to-Applications arrow — the DMG is unboxing; make it on-brand) or a zip; DMG preferred.

Also:

- Keep `swift run` working for development (the `-sectcreate` plist stays; code paths that need the bundle — notifications, SMAppService, Sparkle — already degrade or should degrade with a diagnostic log line instead of silence).
- `SettingsView` version string reads from the bundle (03 §5).
- First-launch quarantine: notarization + stapling makes Gatekeeper show the standard "verified" open dialog — test the full download-from-browser path on a clean VM.

## 2. App auto-update (Sparkle 2)

The product promise is literally "buy it once. When agents change, it learns new tricks in free updates" (landing copy) — the app must update itself.

- Add `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")` and link in the app target.
- Wire `SPUStandardUpdaterController` in `AppDelegate` (works fine for menu-bar apps; no UI needed until an update exists). Settings → About gets "Check for updates" (03 §5); automatic checks on (daily), with the toggle in Settings → General or About.
- Info.plist: `SUFeedURL` = `https://buddygotchi.github.io/releases/appcast.xml` (same static-hosting pattern as the firmware manifest), `SUPublicEDKey` = generated EdDSA public key (`generate_keys` from Sparkle tools; private key in CI secrets), `SUEnableInstallerLauncherService` not needed (non-sandboxed).
- Release flow (§6 automation) generates the appcast entry with `generate_appcast`.
- Brand note: Sparkle's default update UI is stock AppKit — acceptable; do not skin it in v1.
- Privacy note in About: "checks for updates against a static file; no identifiers sent" (Sparkle sends a system-profile only if enabled — keep `SUEnableSystemProfiling` off).

## 3. Firmware hosting + release pipeline

`FirmwareReleaseService` already fetches `https://buddygotchi.github.io/firmware/manifest.json` — nothing exists there yet (PLAN.md item 4).

- Create the `buddygotchi.github.io` pages repo (or a `gh-pages` branch of this repo serving `/firmware` and `/releases`).
- Manifest contract (already parsed): `{"version", "url", "sha256", "notes", "published_at"}`. Add (tolerated by the parser, useful later): `"minAppVersion"`, `"board": "m5stickc-plus2"`.
- CI workflow `firmware-release.yml`: on tag `fw-v*` → PlatformIO build (`platformio run` in `firmware/esp32`), compute sha256, upload `.bin` to the pages repo/GitHub Release, regenerate `manifest.json`, publish. Keep old binaries forever (rollback path: manually repoint the manifest).
- Staged rollout is overkill at 100 units; instead add a `BUDDY_FIRMWARE_MANIFEST_URL` override doc note for beta devices (already supported via env/Info.plist).
- QA gate from PLAN.md stands: a real-device OTA run is part of the firmware release checklist.

## 4. First-flash story ("firmware flash" ask)

BLE OTA requires a device already running compatible firmware. Three audiences need a from-zero flash: (a) production line (us), (b) hobbyists with a bare M5StickC Plus 2, (c) recovery from a bricked/foreign state.

Recommendation: **ESP Web Tools** page, not in-app flashing.

- Host `https://buddygotchi.github.io/flash/`: a page embedding [ESP Web Tools](https://esphome.github.io/esp-web-tools/) (`<esp-web-install-button manifest="…">`), which flashes over USB from Chrome/Edge via WebSerial — zero app code, cross-platform, and the manifest can reuse the firmware CI artifacts (ESP Web Tools has its own manifest JSON format listing bootloader/partition/app offsets; generate it in the same CI job — for ESP32 with our `partitions.csv`, parts are bootloader @0x1000, partition table @0x8000, app @0x10000; verify against the PlatformIO build output).
- The Mac app links to it: Settings → Displays, when no device is paired, a tertiary link *"have a bare M5StickC? flash it first"*; and the pairing-scan empty state mentions it after ~20 s of finding nothing.
- In-app USB flashing (bundling esptool or a Swift serial implementation) is explicitly rejected for v1: large surface, drivers, and the web flasher is the ecosystem standard.
- Production line uses the same artifacts with `esptool.py` scripts (already have `firmware/esp32/tools/`); write the one-page flash+test checklist from PRODUCT.md §7.5 when hardware work starts.

## 5. OTA speed (quality-of-life once updates are real)

Current throughput: base64 chunks with a per-chunk ack (`sendAwaitingAck` per ~96-byte payload) ≈ 9 min/MB — users will abandon updates. Improvements, in order of value:

1. **Bigger chunks**: negotiate MTU — `peripheral.maximumWriteValueLength(for: .withoutResponse)` is typically 182–512 bytes post-connection; size chunks to it (firmware `xfer.h` must accept larger lines; its line buffer is the constraint — check `xfer.h`'s buffer size and raise to 1 KB).
2. **Windowed acks**: ack every N chunks (N=8) instead of each; firmware tracks last-seq and acks with the seq number; app pipelines N writes then awaits. Wire change — version the OTA protocol (`ota_begin` gains `"proto":2`; old firmware ignores it and the app falls back to per-chunk when the begin-ack lacks `proto`).
3. **Write-without-response** for chunk frames (keep `withResponse` for begin/end), relying on the windowed ack for integrity — BLE throughput roughly triples.

Target: 1 MB ≤ 90 s. Do this alongside a firmware release since both sides change; the fallback path keeps old devices updatable.

## 6. Release automation

`release.yml` workflow, on tag `v*`:

1. macOS runner: `swift test` → `make package` (build, sign with imported Developer ID cert from secrets, notarize with App Store Connect API key, staple, DMG).
2. `generate_appcast` with the EdDSA key → update appcast.xml in the pages repo.
3. Create GitHub Release with the DMG + auto-generated notes (keep a `CHANGELOG.md`; release notes double as Sparkle notes via appcast `<description>`).
4. Manual gate before publishing the appcast entry (a PR to the pages repo) so a bad build can't auto-ship to users.

Also: add `make package` dry-run (unsigned) to CI on main so packaging never rots.

## 7. Missing consumer table stakes (grab bag)

- **Single instance**: two copies of the app fight over the port and the status bar. In `applicationDidFinishLaunching`: `NSRunningApplication.runningApplications(withBundleIdentifier:)` — if another instance exists, activate it and `NSApp.terminate(nil)`.
- **Reopen behavior**: `applicationShouldHandleReopen` → show popover (or onboarding window if incomplete). Double-clicking the app in Finder when it's already running must visibly respond (today: nothing).
- **Uninstall story**: Settings → About → "Remove Buddygotchi…" flow: confirmation sheet listing exactly what gets removed (hook entries from the three agent configs, `~/.buddygotchi`, login item, notification registrations), then performs it and quits, leaving the user to trash the app. Without this, deleted-app users keep dead hooks in every agent forever (harmless — connection-refused is instant, fail-open holds — but it's litter, and "we clean up after ourselves" is brand-true). Also honor it in docs: a manual-uninstall snippet in the README/help page.
- **Defaults hygiene**: UserDefaults keys are scattered string literals (`"setupCompleted"`, `"buddySpecies"`, `esp32PeripheralUUIDKey`, …) — centralize in a `DefaultsKey` namespace during the retheme touch; prevents typo-forks of state.
- **Help/support surface**: a `docs/` page or site section (help.buddygotchi.com can be GitHub Pages too) covering: what the hooks do, how approval mode works, troubleshooting matrix (nothing connects / port busy / notification permission), uninstall. Link from Settings → About and from onboarding's troubleshooting. Contact = `hello@buddygotchi.com` (verify it works — already tracked in `research/TODOs.md`).
- **Energy audit**: after 04 §1 removes the 0.5 s timer, remaining wakeups are the 2 s stale timer (early-outs when idle), 10 s BLE keepalive (only when paired), and the pet `TimelineView` (only while the popover is visible). Verify with Instruments that the idle app sits near 0% CPU and is App Nap-eligible; consider widening the stale timer to 5 s (reducer timeouts are minutes — nothing needs 2 s resolution).
- **Login items UX**: after packaging, `SMAppService.mainApp.register()` may return `.requiresApproval` — reflect that state in the toggle ("approve in System Settings → Login Items") instead of silently snapping back.
- **Crash/analytics decision (explicit)**: none. Local-first is the brand. Rely on the bug-report bundle; optionally add an opt-in "attach last crash log" that reads `~/Library/Logs/DiagnosticReports/Buddygotchi-*.ips` into the export.
- **macOS version floor**: v14 is right (`@Observable`); document it on the download page.

## Acceptance criteria

- A clean Mac (VM) can: download the DMG from a browser, open it (Gatekeeper verified), drag to Applications, launch → onboarding appears, notifications and Launch-at-Login actually function, Bluetooth prompt only during pairing.
- Sparkle updates a v0.3.0 install to v0.3.1 from the hosted appcast, signed and verified.
- `FirmwareUpdater` completes an OTA against the *hosted* manifest on a real M5StickC Plus 2; a bare M5StickC can be flashed from the web page and then paired.
- Launching the app twice yields one running instance.
- The uninstall flow leaves `~/.claude/settings.json`, `~/.cursor/hooks.json`, `~/.codex/{hooks.json,config.toml}` free of buddygotchi entries and `~/.buddygotchi` gone.
- CI produces an unsigned package on every main push; the tagged release workflow produces the signed, notarized, stapled DMG plus appcast entry behind a manual gate.
