# 12 — Pass 3: Does It Actually Work? (Verification, Testing, and the Transport Decision)

Date: 2026-07-03, after the pass-2 delegation merged (`770789a`).
Focus per request: polish, cleanup, and testing of the actual code — proving functionality rather than reading it.

## 1. What was verified live this pass

| Check | Result |
| --- | --- |
| `swift build` (app product, signal CLI, test-target compile) | ✅ pass |
| `make test` on an Xcode-less Mac | ✅ fails loudly with the compile-only warning, exactly as designed |
| App boots headless, `/healthz` responds | ✅ `{"ok":true,...}` |
| Full HTTP e2e suite against the live app | ⚠️ **40/43** — the 3 failures are the *tests* asserting the old auto-allow-on-session-death behavior; the app correctly returns the passthrough empty body. The P0 approval fix is proven end-to-end; the assertions are stale (§3.2) |
| `make package` | ❌ **broken on Xcode-less machines** — `swift build -c release` pulls the test target into the build graph and dies at the known link step (§3.1) |
| Product-scoped release builds (`--product Buddygotchi` / `BuddygotchiSignal`) | ✅ pass — this is the packaging fix |
| Geist registration + PostScript resolution | ✅ independently re-verified |
| Firmware compile (`pio run`) | ✅ (verified during pass-2 delegation, incl. version injection) |

**Not verifiable on this machine** (and therefore what the testing docs must cover): unit-test *execution* (CI-only), snapshot rendering, BLE/hardware behavior (needs the device), OTA end-to-end (needs a hosted or locally-served manifest + device), Sparkle updates (needs framework + signed build), notifications/Launch-at-Login (need a packaged bundle).

## 2. The transport decision: keep BLE (recommendation)

Question: keep BLE pairing, or require a USB-C connection to the Mac for simplicity?

**Recommendation: keep BLE as the product transport.** Reasoning:

- **The complexity is already paid and tested.** Reconnect backoff, LESC+MITM bonding, passkey UI, pairing timeout/retry, unpair — all built, reviewed, and covered. Switching now discards working, hardened code for a new unproven path.
- **The firmware already speaks both.** `data.h` feeds the same JSON protocol from USB serial and BLE; the HIL suite drives the device over USB today. So USB is not "instead of" — it exists as the debug/recovery/factory transport for free. The only missing piece for a USB *product* path is a serial transport in the Mac app (~200 lines + device discovery), which can be added later if field data demands it.
- **Product story:** the landing page and product docs promise "lives on your desk … talks to your Mac over Bluetooth." USB-to-computer tethers the buddy to a laptop port (MacBooks have 2–4), kills placement freedom and the wobble (a data cable to the laptop is exactly the cable-fights-the-wobble problem PRODUCT.md §9.4 designs around), and breaks the common setup of powering the buddy from a wall charger.
- **Risk containment instead of removal:** BLE connection issues degrade to "the buddy sleeps" — hooks and the Mac app keep working. The failure mode is cosmetic, not functional.

Decision to record in ARCHITECTURE.md: BLE = product transport; USB serial = debug/factory/recovery transport (buddyctl, HIL, web flasher); a Mac-app serial fallback is explicitly deferred until reliability data justifies it.

## 3. Findings (delegation targets)

### 3.1 `make package` fails on CLT-only machines (P0 for "does deploying work")

`package.sh` runs `swift build -c release`, which builds the whole graph including `BuddygotchiTests` → dies at the unlinkable test-executable step. Fix: build only what ships — `swift build -c release --product Buddygotchi` and `--product BuddygotchiSignal` (verified both succeed). Keep the rest of the script unchanged; also point the resource-bundle copy at the product build output.

### 3.2 e2e suites assert the retired auto-allow semantics

`app/tools/e2e/{claude,codex,cursor}.sh` each have one test "resolved by session death = fail-open allow" expecting `"behavior":"allow"` (Claude/Codex) or `"permission":"allow"` (Cursor). Correct expectations now: **empty response body** for Claude/Codex, `{"permission":"ask"}` for Cursor; rename the labels to "…= passthrough". Also worth adding while in there: a prompt-expiry e2e (park an approval, wait — infeasible at 300 s; instead assert the pending card exists then resolve; note expiry is reducer-tested) — skip if awkward, the 3 assertion fixes are the deliverable.

### 3.3 ARCHITECTURE.md is two passes stale

`research/eng/ARCHITECTURE.md` (395 lines) predates both delegation rounds: no token auth, no `passthrough` decision, no prompt expiry, no hook health/schema-version/auto-repair, no `DesktopOutput`, no onboarding window, no Sparkle/packaging/release pipeline, no pure-renderer firmware or PROTOCOL.md, no testing-truthfulness story, and it still describes `config.json` as "port and approvalMode" (now also token). Needs a full rewrite against current `main`, including the §2 transport decision and a "what runs where" test matrix pointer.

### 3.4 No end-to-end testing documentation (explicit user ask)

There is no single document answering "how do I test X". Needed: `research/eng/TESTING.md` covering, with exact commands and expected output:

1. **Unit tests** — real execution only on machines/CI with XCTest; locally `make test` is compile-only and fails loudly by design (document `BUDDY_ALLOW_COMPILE_ONLY=1`).
2. **HTTP e2e** — start the app (`swift run` or built product), run `app/tools/e2e-smoke.sh`; per-agent suites; the token is read from config automatically.
3. **Snapshot/visual review** — requires XCTest: `make test-snapshots` on an Xcode machine or the new CI artifacts job (§3.6); how to eyeball the PNGs; this is the ongoing "does UI match the landing page" check.
4. **Packaged-app smoke** — `make package`, then on a clean account/VM: Gatekeeper open, onboarding appears, notifications actually post, Launch-at-Login registers, single-instance, uninstall flow.
5. **Firmware update (OTA) end-to-end, without public hosting** — build firmware (`pio run` with `BUDDY_FW_VERSION` set), generate manifests (`generate_release_manifests.py`), serve them locally (`python3 -m http.server` in the output dir), point the app at it via `BUDDY_FIRMWARE_MANIFEST_URL=http://127.0.0.1:8000/manifest.json`, run the update from Settings, then confirm the device reports the new version (`buddyctl.py ping --json`). This is the missing "how do I test firmware update + asset deployment" recipe.
6. **Asset deployment** — after `make package`, verify `Buddygotchi_Buddygotchi.bundle` (fonts + sounds) is inside the app and that the packaged binary resolves Geist (`NSFont` check or just visual).
7. **Hardware HIL** — `make hil` (USB, no pairing needed) and `make hil-ble` (after one-time pairing); what each covers; `buddyctl.py` cookbook (set/expect/screenshot/press/monitor).
8. **Web flasher** — serve `docs/flash/` + firmware artifacts locally to test ESP Web Tools before Pages exists.

Link it from RELEASE.md so the release checklist references one canonical testing doc.

### 3.5 HIL suite doesn't cover the pass-2 firmware features

`tests/hil/` covers ping/state/heartbeat-states/approval/button-edges/screenshot/timeout (+2 BLE). Missing, all cheap over USB:

- **Mute:** heartbeat with `"mute":true` → device state must reflect it. Requires exposing `muted` in `dumpState` (add the field), then `buddyctl set`/`expect`.
- **Long-press A:** `press a 1600` with no armed prompt → no `permission` message emitted, and screen toggles off; `press a 120` afterwards wakes it. Requires exposing `screenOff` (and ideally `brightness`) in `dumpState`.
- **Display power:** drive `pet=sleep`, advance… (no fake clock on-device — either make the dim/off thresholds test-tunable via a debug serial command like `power fast` or assert only the immediate brightness tier per state).
- **Long-press must not approve:** armed prompt + `press a 1600` → no decision sent (guards the suppression logic).
- **OTA reject paths:** `ota_begin` with `size:0` → nack; `ota_chunk` with no session → `no_session` nack. (Full OTA transfer over USB serial is possible but slow; leave as a manual TESTING.md step.)

### 3.6 The snapshot harness runs nowhere

Locally impossible (no XCTest); in CI the `.enable` flag file is never created, so `SnapshotHarnessTests` skip silently. Fix in `ci.yml`: a dedicated step after tests — create `/tmp/buddy-snapshots/.enable`, run `swift test --filter SnapshotHarnessTests`, upload `/tmp/buddy-snapshots/*.png` via `actions/upload-artifact`. Every PR then produces reviewable renders of the popover states, onboarding steps, and the species gallery — the recurring "does the UI match the landing page" answer.

### 3.7 Carried-over human actions (not delegable)

- Create the `buddygotchi.github.io` hosting (help/flash/firmware/releases paths + appcast) — four shipped URLs still 404.
- Verify `SPARKLE_SHA256` pin against the official 2.6.4 artifact at first release.
- One real-device OTA + pairing QA pass per RELEASE.md before selling anything.

## 4. UI/UX vs landing page — status

Code-level parity is now in place: night surface everywhere, amber-only accent, real Geist, blob default with the exact S4 light-language rhythms, brand-law copy enforced by reflection + a zero-baseline ratchet, damped motion curves, chirps replacing system sounds. What cannot be asserted from here is *rendered* fidelity — that's §3.6's job (CI snapshot artifacts) plus a 10-minute manual pass driving states via the e2e helpers while the popover is open (document in TESTING.md §7 cookbook).
