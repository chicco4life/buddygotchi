# Testing Boop

This is the canonical test matrix for the macOS app, agent hooks, ESP32
firmware, packaged assets, OTA, hardware HIL, and the web flasher.

Run commands from the repo root unless a section says otherwise.

## 1. Unit Tests

**Full unit-test execution requires XCTest from a full Xcode install or CI.**
On CommandLineTools-only hosts, the local shim can compile test sources but it
does not execute the XCTest suite. On this machine, `BoopTests` reaches
the link step and cannot link against the app target; `swift test` does not
produce a valid local test run. Do not count raw `swift test` here as unit-test
execution; depending on shim state it either fails at link or reports no useful
executed XCTest cases.

Full Xcode or CI:

```sh
make build
make test
```

Expected success:

```text
Build complete
Test Suite 'All tests' passed
```

Useful focused runs on a full Xcode machine:

```sh
cd app
swift test --filter ReducerTests
swift test --filter EngineIntegrationTests
swift test --filter AutoApproveTests
swift test --filter ResourceTests
```

Expected success:

```text
Test Suite 'Selected tests' passed
```

CommandLineTools-only compile gate:

```sh
BUDDY_ALLOW_COMPILE_ONLY=1 make test
```

Expected local output includes:

```text
WARNING: XCTest unavailable - tests COMPILED but DID NOT RUN.
WARNING: swift build --build-tests reached the BoopTests link step; treating this CommandLineTools shim limitation as compile-verified.
```

Use product-scoped builds when you only need to prove the shipping binaries
compile on a CommandLineTools-only machine:

```sh
cd app
swift build --product Boop
swift build --product BoopSignal
swift build -c release --product Boop
swift build -c release --product BoopSignal
```

Expected success:

```text
Build of product 'Boop' complete!
Build of product 'BoopSignal' complete!
```

## 2. HTTP E2E

Note on launching the debug app: macOS TCC may kill the bare SwiftPM binary at
startup (Bluetooth usage description requires a bundle identity). If
`app/.build/debug/Boop` dies before `/healthz` answers, wrap it in a
minimal `.app` (the binary plus `app/Boop/Resources/Info.plist` under
`Something.app/Contents/`) and `open` that instead — or use the packaged app
from `make package`.

The HTTP e2e suite requires a live Boop app. It reads the auth token from
`~/.boop/config.json`. The default port is `21321`; override it with
`BUDDY_PORT` if the app is configured to listen elsewhere.

Confirm the app is up:

```sh
curl -sS --noproxy '*' http://127.0.0.1:21321/healthz
```

Expected success:

```json
{"ok":true,"desktop":"disconnected","stateVersion":1}
```

Run the master suite:

```sh
make e2e
```

Equivalent direct command:

```sh
app/tools/e2e-smoke.sh
```

Expected success:

```text
Grand total: ... passed, 0 failed
```

Run per-agent suites when debugging a single adapter:

```sh
app/tools/e2e/claude.sh
app/tools/e2e/codex.sh
app/tools/e2e/cursor.sh
```

Expected success for each:

```text
Summary
  ... passed, 0 failed
```

If the app uses a non-default port:

```sh
BUDDY_PORT=21322 app/tools/e2e-smoke.sh
```

If another Boop process owns the single-instance lock but `/healthz`
does not answer, do not kill unrelated processes. Start a clean app in a real
terminal or clean macOS user session, then rerun the smoke suite.

## 3. Snapshot And Visual Review

### 3a. Local renderer (no XCTest required)

The app renders every UI surface headlessly on any machine, including
CommandLineTools-only hosts:

```sh
cd app
swift build --product Boop
.build/debug/Boop --render-snapshots /tmp/buddy-snapshots
open /tmp/buddy-snapshots
```

This writes PNGs for all popover states (sleep, busy, passive prompt, approval
with queue + error trailer, multi-session, error, review), settings, every
onboarding step, and the species gallery. TimelineView animation is captured at
a single frame. This is the fastest local answer to "does the UI still match
the landing page" — use it before and after any view change.

### 3b. XCTest snapshot harness (full Xcode or CI)

The harness additionally exercises the approval button loop end to end and runs
in CI, which uploads the PNGs as the `ui-snapshots` artifact on every run.
Locally it requires XCTest:

```sh
make test-snapshots
```

Equivalent direct command:

```sh
mkdir -p /tmp/buddy-snapshots
touch /tmp/buddy-snapshots/.enable
cd app
swift test --disable-sandbox --filter SnapshotHarnessTests
```

Expected success:

```text
Test Suite 'SnapshotHarnessTests' passed
```

Expected artifacts:

```sh
ls /tmp/buddy-snapshots/*.png
```

Review the PNGs for the popover states, onboarding steps, settings, approval
loop, and species gallery. The visual check is the continuing proof that the UI
still matches the product/landing-page direction after rendering changes.

## 4. Packaged-App Smoke

Package on a release-capable Mac or CI runner:

```sh
make package
```

Expected success:

```text
Created build/package/Boop.app
Created build/artifacts/Boop-<version>.zip
```

Historical note (fixed): `make package` previously failed on CommandLineTools-only
machines by linking `BoopTests`; it now builds only the shipped products
and completes unsigned here. The old failure looked like: the release app binary built, then it failed linking `BoopTests` before
assembling the `.app`. Treat that as a packaging-script/build-environment
failure, not a packaged-app smoke pass.

On a clean macOS account or VM, verify:

```sh
open build/package/Boop.app
```

Expected manual results:

- Gatekeeper launch succeeds.
- Onboarding appears for a fresh profile.
- The menu bar item appears and opens the popover.
- Notifications post for approval prompts after permission is granted.
- Launch at Login can be enabled, survives logout/login, and can be disabled.
- Starting a second app instance activates the existing one instead of running
  two HTTP servers.
- Settings shows a single `v` prefix and the expected build number.
- Check for Updates opens Sparkle against the hosted appcast when Sparkle is
  bundled and configured.
- Uninstall removes managed hooks and helper files without breaking native
  agent fail-open behavior.

## 5. Firmware Update OTA

The build, manifest, and local hosting steps do not require hardware. The OTA
install and version confirmation require a paired M5StickC Plus 2.

Build firmware with an explicit version:

```sh
cd firmware/esp32
BUDDY_FW_VERSION=0.3.1 pio run -e m5stickc-plus
```

Expected success:

```text
Boop firmware version: 0.3.1 (...)
[SUCCESS]
```

Generate OTA and ESP Web Tools manifests:

```sh
rm -rf /tmp/boop-fw
mkdir -p /tmp/boop-fw
python3 tools/generate_release_manifests.py \
  --version 0.3.1 \
  --base-url http://127.0.0.1:8000 \
  --build-dir .pio/build/m5stickc-plus \
  --out-dir /tmp/boop-fw
```

Expected success:

```text
Wrote /tmp/boop-fw/manifest.json
Wrote /tmp/boop-fw/esp-web-tools-manifest.json
```

Serve the manifest and binary locally:

```sh
cd /tmp/boop-fw
python3 -m http.server 8000 --bind 127.0.0.1
```

In another terminal:

```sh
curl -sS --noproxy '*' http://127.0.0.1:8000/manifest.json
curl -sS --noproxy '*' -I http://127.0.0.1:8000/boop-fw-0.3.1.bin
```

Expected success:

```text
"version": "0.3.1"
HTTP/1.0 200 OK
```

Start Boop pointed at the local manifest:

```sh
BUDDY_FIRMWARE_MANIFEST_URL=http://127.0.0.1:8000/manifest.json \
  app/.build/debug/Boop
```

If port `21321` is owned by another app instance, use that instance only if it
was started with the same `BUDDY_FIRMWARE_MANIFEST_URL`; otherwise quit it from
the UI or use a clean macOS account.

Hardware-required OTA steps:

1. Pair the M5StickC Plus 2 from Settings if it is not already paired.
2. Open Settings, Firmware Update.
3. Confirm the app shows version `0.3.1` from the local manifest.
4. Start the update and wait for the device to reboot.
5. Confirm the device reports the new version:

```sh
cd firmware/esp32
tools/buddyctl.py ping --json
```

Expected success:

```json
{"ok":true,"port":"auto","pong":{"fw":"0.3.1", "...":"..."}}
```

The OTA pass is complete only when `pong.fw` matches `manifest.version`.

## 6. Asset Deployment

The app package must contain the SwiftPM resource bundle in both locations that
runtime lookup and packaged execution can use.

After a successful `make package`:

```sh
APP=build/package/Boop.app
test -d "$APP/Contents/MacOS/Boop_Boop.bundle"
test -d "$APP/Contents/Resources/Boop_Boop.bundle"
find "$APP/Contents/Resources/Boop_Boop.bundle" -maxdepth 3 -type f | sort
```

Expected files include:

```text
Fonts/Geist-Regular.otf
Fonts/Geist-SemiBold.otf
Fonts/GeistMono-Regular.otf
Sounds/attention.caf
Sounds/celebrate.caf
Sounds/error.caf
```

Verify packaged font registration and `NSFont` resolution:

```sh
APP=build/package/Boop.app
BUNDLE="$APP/Contents/Resources/Boop_Boop.bundle" swift -e '
import AppKit
import CoreText
import Foundation
let bundle = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BUNDLE"]!)
for name in ["Geist-Regular", "Geist-SemiBold", "GeistMono-Regular"] {
  let url = bundle.appendingPathComponent("Fonts/\(name).otf")
  CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
print(NSFont(name: "Geist-SemiBold", size: 12) != nil ? "Geist-SemiBold resolved" : "Geist-SemiBold missing")
'
```

Expected success:

```text
Geist-SemiBold resolved
```

On a packaged app, also visually confirm the UI uses Geist rather than the
system fallback and that attention/celebrate/error chirps play.

## 7. Hardware HIL

These checks require a plugged-in M5StickC Plus 2. USB HIL does not require
BLE pairing; BLE HIL requires the one-time OS pairing step first.

USB HIL:

```sh
make hil
```

Expected success:

```text
tests/hil/test_usb.py ... passed
```

BLE HIL:

```sh
make hil-ble
```

Expected success:

```text
tests/hil/test_ble.py ... passed
```

`make hil` covers USB serial ping, state, heartbeat states, approval paths,
button edges, screenshot integrity, and timeout behavior. `make hil-ble`
covers the production BLE heartbeat/status/prompt transport after pairing.

`tests/hil/test_hardening.py` (part of `make hil`) is the reliability gate:

- heap headroom floors (`heap` ≥ 40KB, `heapBig` ≥ 28KB at idle) — catches
  silent RAM regressions before they OOM the BLE connect path
- reboot soak — commanded reboots must come back clean with no panics;
  crank with `BUDDY_SOAK_CYCLES=200` for a pre-ship soak
- serial fuzz — seeded garbage on the command channel must never panic,
  reboot, or wedge the device; reproduce with `BUDDY_FUZZ_SEED=<seed>`
- watchdog recovery (slow, ~70s) — a deliberately hung `loop()` must
  self-reboot via the task WDT and land in crash telemetry

Crash telemetry lives in `ping`: `reset` (last reset reason), `panics`
(lifetime), `early` (consecutive crashes before stable uptime), `safe`
(safe-mode tier). Recovery serial commands: `clearbonds`, `guardclear`;
debug: `hang`.

Buddyctl cookbook:

```sh
cd firmware/esp32
tools/buddyctl.py ping --json
tools/buddyctl.py set --pet attention --waiting 1 --prompt-id req_1 --prompt-tool Bash --prompt-hint "npm test"
tools/buddyctl.py expect --pet attention --prompt-id req_1 --json
tools/buddyctl.py screenshot --out approve.png --scale 2 --json
tools/buddyctl.py press a --ms 150 --json
tools/buddyctl.py ble status --json
tools/buddyctl.py ble set --pet busy --running 1 --json
tools/buddyctl.py ble prompt --id req_1 --tool Bash --hint "npm test" --wait-decision --json
```

Expected success: each `--json` command returns `"ok": true`; the prompt command
returns a `decision` object after a real button approval or denial.

## 8. Web Flasher

The web flasher can be tested locally before GitHub Pages hosting exists. The
page expects the ESP Web Tools manifest at `/firmware/esp-web-tools-manifest.json`.

Prepare a local site root:

```sh
rm -rf /tmp/boop-webflash
mkdir -p /tmp/boop-webflash/flash /tmp/boop-webflash/firmware
cp docs/flash/index.html /tmp/boop-webflash/flash/index.html
cd firmware/esp32
python3 tools/generate_release_manifests.py \
  --version 0.3.1 \
  --base-url http://127.0.0.1:8001/firmware \
  --build-dir .pio/build/m5stickc-plus \
  --out-dir /tmp/boop-webflash/firmware
```

Serve it:

```sh
cd /tmp/boop-webflash
python3 -m http.server 8001 --bind 127.0.0.1
```

Dry-run checks:

```sh
curl -sS --noproxy '*' http://127.0.0.1:8001/flash/ | rg 'esp-web-install-button|/firmware/esp-web-tools-manifest.json'
curl -sS --noproxy '*' http://127.0.0.1:8001/firmware/esp-web-tools-manifest.json
curl -sS --noproxy '*' -I http://127.0.0.1:8001/firmware/boop-fw-0.3.1.bin
```

Expected success:

```text
<esp-web-install-button manifest="/firmware/esp-web-tools-manifest.json">
"chipFamily": "ESP32"
HTTP/1.0 200 OK
```

Hardware/browser-required install check:

1. Open `http://127.0.0.1:8001/flash/` in Chrome or Edge.
2. Connect the M5StickC Plus 2 over USB.
3. Use the ESP Web Tools install button.
4. Confirm the browser prompts for the serial device without Home Assistant
   prompts.
5. After flashing, verify:

```sh
cd firmware/esp32
tools/buddyctl.py ping --json
```

Expected success: `pong.fw` matches the manifest version used for the flash.
