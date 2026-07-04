# Buddygotchi Mac App Audit — Overview

> **Status (pass 2, 2026-07-03):** most of this pass was implemented (commits `5c4ed48`…`4cc4a1a`). The follow-up audit — verification scoreboard, regressions in the new code, and the firmware deep dive — starts at [07-pass2-overview.md](07-pass2-overview.md). Treat docs 01–06 as historical context; current work items live in 07–11.

Date: 2026-07-03
Scope: `app/` (Swift macOS app), its integrations, and its alignment with the brand defined by `landing/` and `research/product/`.
Audience: an implementing agent. Each numbered doc in this directory is a self-contained work package with file paths, code sketches, and acceptance criteria.

## The one-paragraph verdict

The app's core architecture (hooks → HookServer → BuddyEngine → pure reducer → OutputProvider) is genuinely good and well tested, and the feature set is nearly complete. What's missing is everything *around* the core: the app looks and speaks nothing like the brand the landing page sells (purple accent, ASCII pets, system sounds, exclamation marks, "M5Stack" jargon vs. the cream/amber/charcoal "adopt a buddy" world); first launch shows literally nothing until the user finds the menu bar icon; hooks can't detect their own corruption and the installer can destroy a user's `settings.json`; pending approvals silently auto-**allow** in several cleanup paths; and there is no packaged `.app`, no app auto-update, no firmware hosting, and no first-flash story. All of it is fixable with the plans below.

## The documents

| Doc | Covers | Depends on |
| --- | --- | --- |
| [01-onboarding.md](01-onboarding.md) | A dedicated welcome window, the adoption/hatching arc, permission choreography, per-agent "heard from" test, hardware pairing flow | 02 (theme tokens) |
| [02-theme-design-system.md](02-theme-design-system.md) | New `BuddyTheme` from landing tokens, typography (Geist), damped motion, vector Blob buddy, light-language color mapping, copy/brand law + enforcement test | — |
| [03-ui-ux-polish.md](03-ui-ux-polish.md) | Popover layout/sizing, empty states, actionable notifications, sounds, settings restructure, menu bar behavior, prompt queue, firmware sheet polish | 02 |
| [04-architecture.md](04-architecture.md) | DesktopOutput refactor (kill the polling tick), config single-source-of-truth, species into state, correctness bugs (session identity, approval auto-allow, hash instability), file splits, test gaps | — |
| [05-hooks-integrations.md](05-hooks-integrations.md) | Hook health model (installed/corrupted/outdated → auto-repair), atomic + non-destructive config writes, stable helper binary path, HTTP auth token, timeout alignment, per-agent verification | 04 |
| [06-consumer-readiness.md](06-consumer-readiness.md) | `.app` packaging + signing + notarization, Sparkle auto-update, firmware release hosting + CI, first-flash (ESP Web Tools), uninstaller, single-instance, OTA speed, support surface | 05 |

## Priority ladder

**P0 — correctness & safety (do first, small diffs):**

1. `HookInstaller` overwrites unparseable agent config files with Buddygotchi-only content — can destroy a user's `~/.claude/settings.json`. (05 §2)
2. Pending approvals resolve to `.allow` when a session is reaped, goes stale, or Local Approval Mode is toggled off — an unattended dangerous command can be auto-approved. Introduce a `passthrough` decision. (04 §3.1)
3. First launch shows nothing: the setup wizard lives inside the popover and never auto-opens. (01 §1)
4. `CBCentralManager` is created eagerly at app start, so the Bluetooth permission dialog is the first thing a new user ever sees. Lazily create it. (01 §4, 04 §3.4)
5. Non-atomic writes (`FileManager.createFile`) for `config.json`, hook script, and all agent configs. (05 §2)

**P1 — the product ask (the bulk of the work):**

6. Full retheme to the landing design system: night/cream/amber palette, Geist, damped motion, vector blob buddy, brand-law copy pass with an enforcement test. (02)
7. New onboarding: welcome window, adoption arc, per-agent connection test, contextual permissions. (01)
8. Hook health verification + silent auto-repair on launch; stable helper path in `~/.buddygotchi/bin`. (05 §1, §3)
9. Packaging, signing, notarization, Sparkle. Without a real bundle, notifications and Launch-at-Login don't work at all. (06 §1–2)
10. Actionable notifications (Approve/Deny buttons), sound settings, popover empty states, prompt queue indicator. (03)
11. Localhost API auth token — any local process or web page can currently POST fake events/approval requests. (05 §5)

**P2 — polish & scale:**

12. DesktopOutput refactor to remove the 0.5 s polling timer. (04 §1)
13. Species into reducer state; remove the `UserDefaults` read from `Heartbeat.swift`. (04 §2.2)
14. OTA throughput (windowed acks, larger MTU chunks) — 1 MB in ~1 min instead of ~9. (06 §5)
15. ESP Web Tools first-flash page; uninstaller; single-instance guard; version from bundle. (06)
16. Misc correctness: session reverse-lookup identity bug, `hashCwd` instability, timeout mismatches. (04 §3)

## Cross-cutting decisions the docs assume

These are recommendations; if the implementing agent disagrees it should say so, but not silently diverge:

- **The popover is themed "night," not cream.** The landing's one dark passage (S4, the light-language strip: `--night #1B1714`) is exactly what the app *is* — glow states on a dark surface, living next to code editors. Cream text, amber as the *only* interactive accent. The purple `#9B8AFF` is retired entirely.
- **The default desktop buddy becomes the Blob** — a vector SwiftUI rendition of `landing/src/components/BuddyBlob.tsx` (squashed sphere, blush cheeks, expression set). The five ASCII species remain as selectable skins. The landing page sells a blob; the app should greet you with one.
- **Brand law applies to app copy.** No exclamation marks, sentence case, in-universe vocabulary (adopt/buddy/hatch, not install/device/setup where avoidable), one wry line per surface max. Enforced by a unit test over a centralized `BuddyCopy` table, mirroring `landing/tests/copy-rules.test.mjs`.
- **"M5Stack" disappears from user-facing copy.** The device is "your buddy" / "hardware buddy"; the concrete board name may appear in parentheses in Settings only.
- **Fail-open stays sacred.** Every change to hooks/approvals must preserve: if Buddygotchi is down or undecided, the agent's native flow continues. The new `passthrough` decision (04 §3.1) exists precisely to make "undecided" expressible.
- **Local-first stays sacred.** No analytics, no crash-reporting SaaS. The only network calls remain: firmware manifest/binary, Sparkle appcast/download. Both get called out in a privacy note.

## What is already good (don't churn it)

- The pure reducer + `BuddyEvent` model and its 100+ tests. All behavior changes should continue to land as reducer transitions first.
- The fail-open hook script design (config read per-invocation, short timeouts, `exit 0` always).
- The OTA state machine (`FirmwareUpdater`) with reattachable UI, hash verification, ack back-pressure, and honest failure copy.
- Accessibility labeling throughout the SwiftUI views — preserve it during the retheme.
- The e2e smoke scripts and the snapshot harness — extend them, don't replace them.

## Suggested execution order

1. P0 fixes (04 §3.1, 05 §2, 01 §1 quick version, 01 §4) — small, independent, shippable now.
2. 02 (theme/design system) — everything visual builds on the tokens.
3. 01 (onboarding) + 03 (polish) — the visible product work.
4. 05 (hook health) — independent of visuals, high robustness value.
5. 04 remaining refactors — mechanical once behavior is pinned by tests.
6. 06 (packaging/updates/firmware hosting) — the release train.

After each phase: `make build && make test`, plus the snapshot harness for visual phases and `app/tools/e2e-smoke.sh` for hook phases.
