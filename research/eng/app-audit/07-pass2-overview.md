# Pass 2 Overview — Verification of Pass 1 + New Findings

Date: 2026-07-03 (second audit pass, after commits `5c4ed48`…`4cc4a1a`)
Method: full re-read of the app, the new onboarding/theme/hook-health/consumer code, the release pipeline, and — new this pass — the ESP32 firmware line by line, plus local build/test verification.

## Verdict

Pass 1 execution was strong: of the ~45 concrete pass-1 items, roughly **35 landed fully** (passthrough approvals, hook health + auto-repair, non-destructive installer with tests, token auth, onboarding window with the adoption arc, DesktopOutput, actionable notifications, night/amber theme, blob default, packaging/release scaffolding, uninstaller, web flasher, support docs). The remaining risk now concentrates in four places:

1. **Things that look done but don't actually work** — Geist is referenced everywhere but no font file exists anywhere in the repo; Sparkle is wired but no CI step ever downloads the framework; released firmware will always self-report `0.1.0` so OTA "update available" never clears. These are the most dangerous class: green code, dead feature.
2. **Regressions introduced by the fixes** — the server now snapshots `approvalMode` at launch (runtime toggles half-work); the onboarding window has no close button; the launch-time notification-permission call that pass 1 flagged is still there *alongside* the new contextual button.
3. **The firmware**, which pass 1 never audited: ~700 lines of unreachable UI code (plus `main.cpp.bak` committed), user-visible strings from its `claude-desktop-buddy` heritage ("Claude-XXXX" BT name, "No Claude connected", pairing instructions pointing at the wrong app), a fake-data pet-stats page, **no screen dimming at all**, no device sounds, and a BLE line buffer that can drop the busiest heartbeats.
4. **The local test trap** — `swift test` exits 0 having run **zero tests** on Macs without Xcode (verified on this machine). The new XCTest shim makes the target compile but nothing executes, and nothing warns.

## Pass-1 scoreboard

| Area | Landed | Partial / still open |
| --- | --- | --- |
| 01 Onboarding | Welcome window, hatch/adopt/name/first-contact/display/done arc, per-agent "Heard from X.", install-failure surfacing, pairing timeout+retry, adoption card, contextual notification button, lazy Bluetooth, persistence per step | Window not closable (new bug); launch-time `requestPermission()` never removed; "Back/Next/Skip/Heard from" strings bypass copy law |
| 02 Theme | Night/amber/cream tokens, borderless cards, `buddyEase` motion, BlobBuddyView + blob default, warm species palette, tiny-label headers, copy table + test, custom status icon with badge | **Fonts not bundled** (Geist silently falls back everywhere); popover surface is translucent material, not opaque night; blob is missing the light-language animation periods, sleep peek, one-shot celebrate ripple; custom chirps not done (system sounds remain) |
| 03 UI/UX | Flexible popover height, empty state, queue count, error trailer, live thinking timer, path-aware truncation, deny shortcut (broken — see 08 §9), server health row+warning, right-click menu, Advanced disclosure, health-aware agent rows, Forget confirmation, flash link, About overhaul, bug-report error surfacing, sounds toggle | Approval-mode explainer sheet; name editing after onboarding; species state-preview; popover pinning logic still inverted; menu "Check for updates" doesn't check |
| 04 Architecture | DesktopOutput (poll timer gone), passthrough on all cleanup paths + tests, speciesChanged event, session identity fix, stable cwd hash, lazy central, DefaultsKey, HookInstaller DI + tests, timeout 310/300 alignment | Prompt-expiry rule (ghost card ≤10 min remains); ConfigStore (approvalMode still triple-homed → new snapshot regression); process-watcher ancestry still unverified (now also used for Cursor where the walk is likely wrong); DiagnosticLog rawPayload retention/redaction; BLEScanner still spawns a central per scan |
| 05 Hooks | Health model, versioned script, launch auto-repair, atomic writes + backups, corrupt-JSON refusal (tested), managed helper path, token auth end-to-end, Codex TOML parsing, SignalCLI celebrate + pid | `installedAgents` key not in DefaultsKey / not removed by uninstaller; uninstall silently no-ops on unparseable configs; verify runs 2× per agent at launch |
| 06 Consumer | package.sh (sign/notarize/DMG), Info.plist complete, release.yml + firmware-release.yml, Sparkle loader + settings entry, uninstaller flow, single instance, reopen handler, SUPPORT.md, flash page, manifest generator, HIL make targets | **Sparkle framework never fetched in CI**; **FW_VERSION never injected**; `v`-prefix double-applied to version; Pages repo/hosting doesn't exist yet; OTA throughput unchanged; appcast generation manual |

## New findings by priority

**P0 — broken-in-practice or user-hostile:**
1. `approvalMode` launch snapshot in `HookServer` — runtime toggle half-applies (08 §1).
2. Onboarding window cannot be closed (08 §2).
3. Launch-time `requestPermission()` still fires — the pass-1 permission ambush survives (08 §3).
4. Geist fonts don't exist in the repo — the entire type system is a silent fallback (09 §1).
5. Sparkle absent from release artifacts; placeholder EdDSA key would ship (11 §2).
6. Released firmware self-reports 0.1.0 forever → OTA update loop (11 §3).
7. `swift test` false-green on Xcode-less Macs, no warning (11 §1).

**P1 — quality, correctness, brand:**
8. Firmware dead code + heritage branding + no dim/sleep + no chirps + fake stats page (10).
9. BLE heartbeat `_LineBuf<1024>` can drop the largest (busiest) frames (10 §4).
10. Blob light-language animation gaps; popover not opaque night (09 §2–3).
11. Copy-law coverage collapsed: manifest is hand-maintained and ~40 view strings bypass it (09 §5).
12. Broken double `keyboardShortcut` on Deny; menu update-check indirection; pairing UUID persists after abandoned pairing; uninstaller gaps (08).
13. Prompt expiry; Cursor process-watcher ancestry (08 §11–12).

**P2 — polish and roadmap:**
14. OTA proto v2 (windowed acks / bigger chunks) — carried over from pass 1.
15. Custom chirp sounds; approval explainer; name editing; species preview; ESP Web Tools manifest `home_assistant_domain` removal; `.orange` off-palette; em-dash consistency.

## Doc map for this pass

- [08-pass2-app-fixes.md](08-pass2-app-fixes.md) — Mac app bugs & regressions, each with fix.
- [09-pass2-brand-fit-finish.md](09-pass2-brand-fit-finish.md) — the gap between "themed" and "matching the landing page": fonts, surfaces, blob motion, sounds, copy-law enforcement.
- [10-pass2-firmware.md](10-pass2-firmware.md) — the firmware deep dive (new scope this pass).
- [11-pass2-release-and-testing.md](11-pass2-release-and-testing.md) — the release train's dead ends and the local-test trap.

Suggested order: 08 §1–3 and 11 §1–3 first (small, high-stakes), then 09, then 10, then the rest of 08/11.
