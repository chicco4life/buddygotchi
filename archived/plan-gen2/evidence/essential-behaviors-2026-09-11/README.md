# Essential behaviors — 2026-09-11

## Implemented

- Celebrations: none below one minute; hop at one, cheer at three, dance at five.
  Short completions still record duration and earn XP; completion sounds share
  the one-minute minimum. Folding remains three seconds.
- Editor-only approvals: no interception, decision UI, notification actions,
  device decision holds or acknowledgement presentation. Hook v9 removes Boop
  permission registrations; stale scripts/settings cannot enable interception.
  The compatibility endpoint immediately returns native passthrough.
- Remove five-minute check-ins only. Greeting, error and post-celebration dialogue
  remain, alongside existing time-away greeting animations.
- Personality is Markdown plus evidence-backed profile memory and recent outcomes.
  No numeric trait/bond updates, usual-hour sampling or project/session familiarity
  counters. Old stored values remain inactive. Growth and reminders are unchanged.
- Activity and local share-card export are retained pending owner review.

## Verification

- `make test`: **341 passed, zero skipped** using the repository Swift XCTest shim.
  This includes actual offscreen native-view rendering, HTTP responders, generated
  hook script execution against a stub curl, model fixtures, growth and persistence.
  Retired approval/trait-drift tests were removed or replaced with passive attention,
  native passthrough, ignored legacy fields and new duration-boundary coverage.
- `make build`: Boop and BoopSignal both built.
- `tools/pio_ws.sh run -e ws-amoled164` from firmware/esp32: shipping firmware built.
- `git diff --check`: passed at delivery.
- Inspected [attention](attention.png), [settings](settings.png), and
  [support settings](support-settings.png): no approval switches/buttons or stakes.
  [Activity](activity.png) and [share card](share.png) illustrate retained secondary UI.

Logs: [tests](tests.log), [Mac builds](build.log), [firmware build](firmware-build.log).
Builds required access outside the restricted sandbox for compiler caches and
firmware dependencies. No firmware was flashed, owner app launched, live hooks
trusted, real model evaluated, webcam opened or physical-device gate claimed.
Deploy the matching app/firmware and verify native editor flows, passive requests,
60/120-second nudges, Quiet mode and BLE on actual hardware before release.
