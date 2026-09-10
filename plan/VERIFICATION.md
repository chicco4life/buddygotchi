# Verification

Verify the current [behavior contract](BEHAVIORS.md). Keep automated, offscreen,
live-editor and physical-device evidence distinct.

## Automated checks

From the repository root:

```sh
make test
make build
```

The root test entry point runs the repository's Swift test harness. SwiftPM
cache/module failures before source compilation should be retried outside the
restricted sandbox before diagnosing source issues.

Shipping firmware build (no flash):

```sh
cd firmware/esp32
tools/pio_ws.sh run -e ws-amoled164
```

| Area | Required coverage |
| --- | --- |
| Core | State priority, session lifecycle, duration boundaries, folding, stale requests |
| Growth | Two award sources, duplicate completion, local-day streaks, frozen legacy XP and restart |
| Behavior | Live guide reload, silence, eligibility, cancellation, five-second fallback and text bounds |
| Reflection | Evidence/privacy bounds, valid traits/memories, invalid/unavailable model, daily idempotence |
| Approvals | Native default for every agent, global/Codex opt-ins, stale hook passthrough and request-ID guards |
| Wire | UTF-8 caps, compatibility, bounded nudge rung, ignored retired fields |
| Mac UI | Overview, Settings and Activity; pending cards stay on Overview; English/Korean and light/dark |

Latest result: **368 tests passed, zero skipped**, both Mac products built.
[App evidence](evidence/markdown-learning-native-approvals-2026-09-11/README.md).
The shipping firmware build, syntax checks and offscreen screenshots are in
[simplification evidence](evidence/behavior-simplification-2026-09-11/README.md).
No live model, editor interception or physical-device pass is implied.

## Live hooks and model

Before trusting hook-dependent results, use the `doctor` skill and its live
confirmation sequence. The owner must launch the Boop app; agents must not.
Run the supported harness flows against that identified app instance. Verify
native approvals with interception off, explicit opt-in, timeout/disconnect,
competing decisions and disabling interception while a request is held.

On a supported Mac, evaluate real Foundation Models output against the guide in
both languages. Check that silence is common when appropriate, callbacks use
supplied evidence, invalid reflection leaves stored traits/profile unchanged,
and guide edits affect the next decision without restarting.

## Device and transport

Follow [device tooling](../tools/dev/README.md). Independent USB UI/button tests
use the USB-only debug build and verify `ping.usbOnly`; restore normal firmware
afterward. Never publish a debug image. Production BLE checks require normal
firmware and one explicitly identified Mac app. USB-only tests do not close BLE.

Exercise arrival, 60/120-second nudge rungs, repeated frames, snooze/new request,
Quiet mode, 600 ms arming, careful hold, denial, acknowledgement/no-link,
reconnect, byte-capped multilingual text, stats, dimming and OTA recovery.
Record board/build, commands, assertions and screenshots with each result.

Webcam verification requires explicit permission and physical setup for that
session; it is not part of ordinary build or screenshot checks.

## Release status and history

Outstanding live/model/hardware and packaging gates are listed in [Plan](PLAN.md).
Earlier phase procedures and evidence are preserved in
[verification history](VERIFICATION-HISTORY.md). Historical checks for removed
features are not required to restore them; use current contracts for new tests.
