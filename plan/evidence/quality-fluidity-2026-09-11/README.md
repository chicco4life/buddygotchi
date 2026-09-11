# Quality and fluidity pass — 2026-09-11

## Changes

- Split pure display projection out of the lifecycle reducer. All Mac sessions
  remain visible and scrollable; only the independent device preview is capped.
  Thinking sessions now agree across the face, counts, Mac rows and device rows.
- Preserve eligible companion dialogue when sessions are present. The test-cheer
  action now survives the activity projection while respecting attention/errors.
- Share popover sizing with snapshots and clamp to small screens. Isolate
  snapshot appearance fixtures so onboarding cannot mutate the next overview.
  Firmware sheets now follow dark appearance; failure copy no longer asserts
  an unconfirmed installed version.
- Ease interrupted head tilt and retract raised arms without flipping them down.
  Card departures retract monotonically; system cards cancel completion notices.
  Settled hardware layouts remain unchanged.
- Require a fresh matching device version to confirm firmware installation.
  Both an end acknowledgment and an end-time disconnect wait for confirmation;
  missing confirmation has a 45-second limit, old firmware is a recoverable
  failure, stale checks/cancelled downloads cannot overwrite newer work, and
  dismissing a check error cannot claim firmware is current.
- Replace stale HTTP/device assertions for retired approvals and levels with
  native passthrough, passive-attention, and cumulative-XP checks. Fix the shutdown
  test's consumed-release-marker race. Tooling tests use private reservation
  files instead of blocking the shared device; USB-only hardening tests recognize
  their own data connection correctly.

## Verification

The app passed **382 tests, zero skipped**. Both Mac products and both firmware
variants built. All **105 isolated HTTP checks** passed (Claude 50, Codex 26,
Cursor 24, shared contract 5); all **six workflow tests** passed.

The final candidate's full USB suite passed **99 of 100 cases**, with two BLE
cases deliberately deselected. The remaining case passed its monotonic motion
and position checks, but its fixed sample count ended before the final departure
flag cleared. That assertion now uses a one-second removal deadline; three
repeat runs of that corrected check **all passed** on the identical firmware.
Thus **all 100 unique non-BLE scenarios are verified across the full run and
targeted recheck**; the suite was not rerun wholesale after this test-only
correction. See `hardware-full.xml`, `settle-0.xml` through `settle-2.xml`, and
`verification.json`. System/dialogue/sleep cover,
head/arm interruption, and the strict single-attempt screenshot-integrity gate
passed. No capture-retry warnings occurred in this final full run.

Earlier runs exposed obsolete approval/level assertions, a consumed serial
release marker, reminder tests accidentally expiring the link, a frozen-clock
rewind changing the link glyph, and one truncated USB screenshot. The tests now
exercise current passive-attention behavior, keep heartbeats live when testing
reminders, avoid rewinding before the last heartbeat, and recapture invalid
visual-comparison transfers at most three times with warnings. The dedicated
integrity check still fails on its first invalid transfer. These are test
corrections; already-retired product features were not reintroduced or removed.
Earlier results and restored firmware identities are in `verification.json`.

The initial motion candidate reproduced all **52 goldens twice at zero pixel
error**, with fresh timestamps and identical hashes in
`initial-independent-captures.json`. The final footer candidate also reproduced all 52 twice at zero error; see
`final-independent-captures.json`. No golden references have been replaced.

[Webcam review](webcam/review.md) covers working, greeting, dance and card
arrival/removal. It used every consecutive image rather than real-time playback.
A visible footer-disappearance issue prompted the last fix and a bounded
follow-up clip confirming visible downward text departure and return to rest.
Fine-detail smoothness remains limited by eye bloom/focus.

## Evidence and limits

The contact sheet shows all 52 settled device scenes, including six states,
effort tiers, cheers, attention cards, bubbles, postures, legacy appearance
compatibility, completion notices, thread/history pages and English/Korean scope
fixtures. The overview images show the complete activity grid in both appearances.
The long-session image is a viewport of the scrollable list.

Raw logs, full device backups, and whole-camera footage stay local in
`/tmp/boop-quality-device`, `/tmp/boop-quality-recheck`,
`/tmp/boop-quality-footer`, `/tmp/boop-quality-settle`, and
`/tmp/boop-quality-*.log`. Only selected evidence is copied here. Firmware image
hashes identify the dirty-checkout candidate, because its embedded git label
alone does not identify uncommitted source changes.

USB-only behavior and mocked update transports do not prove production Bluetooth
or a real OTA install. During the original pass the everyday GUI was not launched or replaced; isolated
headless instances were stopped after use. Native editor interactions and the
existing live Foundation Models semantic-quality gate remain unverified.

The implementation and matching specs are left in the worktree for review.
No release was published and no everyday Mac app installation was replaced.

All four hardware reservations restored their full pre-test flash backups.
Final restoration passed identity checks: `ws-amoled164`, shipping/USB-only=false,
`dev+1b4976d44e34` (`1b4976d44e34`). Firmware and persisted device settings were
restored; the tested candidate was not left installed.

## Follow-up with the user-launched worktree GUI

The user launched the worktree `app/.build/debug/Boop` as the sole GUI, PID 79677.
The actual Codex hook passed the doctor's arm/own-tool-call/confirm sequence.
Doctor now checks the lifecycle events installed by HookInstaller instead of
warning about the deliberately retired PermissionRequest registration: 8 OK,
0 failed, 0 warnings. Claude and Cursor native editor interactions remain open;
HTTP source fixtures do not prove native editor behavior.

The reserved normal-firmware run used the GUI as the sole Bluetooth writer.
USB supplied only observations, button input and reset commands; no synthetic
render frames or second BLE client were used. Fifteen assertions passed:
candidate reconnection and RTC sync, multi-source activity, permission-event
passthrough, question arrival/dismissal, dismissal surviving eleven seconds of
host keepalives, a new question after dismissal, host answer clearing the card,
device quiet toggle and host echo, reboot/reconnect, host quiet restoration,
quiet cleanup, and original-firmware reconnection after full-flash restoration.
See [results](integration/bluetooth-results.json). This tests the same shipping
binary hash as the quality pass, with `usbOnly=false`.

**Stability is not signed off:** the initial candidate identity reported a
panic reset and a lifetime panic-count increment from 103 to 104, despite all
behavior assertions passing. The initial serial read-only backup also failed
before any flash writes; a lower-speed retry completed and its full 16 MB backup
was restored after the scenario. Two follow-up reservations captured serial
startup output and compared original/candidate firmware. Neither reproduced
the panic: eleven candidate reboot cycles are confirmed (two, then nine),
plus two stable-uptime observations above 75 seconds, without
increasing the baseline panic count of 103. See [first probe](integration/reboot-probe.json)
and [ten-reboot run](integration/reboot-soak.json). One of the ten stress-run commands was not observed: `candidateReboot8`
retained the previous uptime instead of resetting, so it is excluded from the
confirmed count. Future repetitions must wait for the reset acknowledgment and
verify fresh uptime. Both reservations restored the same saved
original full image and confirmed its identity. The cause of the first panic
is unresolved; clean repeat runs do not establish a fix. No speculative firmware
change was made. The serial logs also contain I2C invalid-state diagnostics on
both original and candidate firmware; those are not attributed to this change.

The configured [firmware endpoint](https://adoptaboop.com/firmware/manifest.json)
returned HTTP 404; [status](integration/manifest-status.txt). No real OTA install
was attempted. The release generator had retained the retired ESP32 chip family
and bootloader address. It now emits the ESP32-S3 layout and copies the explicit
Arduino boot-selection image. Its artifact consistency test is included in the
release workflow and passes; a dry run with the real candidate produced the
two manifests retained under `integration/`. Their `example.invalid` URLs are
deliberate local-test placeholders. No artifacts were published.

The [live model replay](integration/model-replay.txt) returned 360/362-byte task
recaps in about two seconds, failing the title and 120-byte contract. The
[temporary guide trial](integration/guide-trial.md) produced short titles but
omitted the website in the two-project case; [results](integration/model-trial.txt).
A second [guide-order trial](integration/guide-trial-2.md) also omitted the
website and used the forbidden pet-subject wording; [results](integration/model-trial-2.txt).
Neither trial was adopted. Whole-desk semantic coverage remains unresolved.

Full backup, coordinator scripts and serial logs remain local under
`/tmp/boop-gui-integration`. This follow-up opened no webcam session.
