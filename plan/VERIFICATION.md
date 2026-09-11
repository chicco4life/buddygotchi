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
| Reflection | Evidence/privacy bounds, valid memories, ignored legacy traits, invalid/unavailable model, daily idempotence |
| Approvals | Editor-only for every agent, stale enabled config/hook passthrough, ignored device decisions |
| Wire | UTF-8 caps, compatibility, bounded nudge rung, ignored retired fields |
| Mac UI | Overview and Settings; sessions follow status, compact XP is last and includes tasks/streak; no Activity navigation; pending cards stay on Overview; English/Korean and light/dark |
| Palette | Every `BuddyTheme.*Ink` tone clears 4.5:1 against its own appearance's paper; amber appears only for "needs you", never on a primary action; the twelve-week grid and its legend are unclipped at the resting height |

Current glanceable-completion result: **357 app tests passed, zero skipped**;
both Mac products and both firmware variants built; **12 USB hardware checks
passed**, **44/44 goldens** matched independently recaptured images at zero error.
English/Korean text, grouped completion, thread table and last-finished footer
were visually reviewed. Updated-app production BLE remains a separate gate.
[Glanceable completion evidence](evidence/glance-completions-2026-09-11/README.md).

Previous UI-pass result: **349 tests passed, zero skipped**, both Mac products built,
shipping Waveshare firmware built and flashed, 43/43 device goldens re-recorded
and reproduced at zero error against an independently recaptured set. The
M5StickC Plus 2 was retired, leaving `ws-amoled164` as the only board and the
only firmware build. Offscreen UI checked in both appearances.
Previous result: **341 tests passed**; see the
[essential behavior evidence](evidence/essential-behaviors-2026-09-11/README.md).

Previous result (before the essentials change): **368 tests passed, zero skipped**, both Mac products built.
[App evidence](evidence/markdown-learning-native-approvals-2026-09-11/README.md).
The shipping firmware build, syntax checks and offscreen screenshots are in
[simplification evidence](evidence/behavior-simplification-2026-09-11/README.md).
No live model, native-editor or physical-device pass is implied.

## Live hooks and model

Before trusting hook-dependent results, use the `doctor` skill and its live
confirmation sequence. The owner must launch the Boop app; agents must not.
Run the supported harness flows against that identified app instance. Verify
native approvals, old enabled settings, permission-event passthrough and hook
repair without removing third-party hooks. Verify passive attention separately.

On a supported Mac, evaluate real Foundation Models output against the guide in
both languages. Check that silence is common when appropriate, callbacks use
supplied evidence, invalid reflection leaves stored profile unchanged,
and guide edits affect the next decision without restarting.

## Device and transport

Follow [device tooling](../tools/dev/README.md). Independent USB UI/button tests
use the USB-only debug build and verify `ping.usbOnly`; restore normal firmware
afterward. Never publish a debug image. Production BLE checks require normal
firmware and one explicitly identified Mac app. USB-only tests do not close BLE.

Exercise arrival, 60/120-second nudge rungs, repeated frames, snooze/new request,
Quiet mode, passive dismissal, absence of decision controls/feedback,
reconnect, byte-capped multilingual text, stats, dimming and OTA recovery.
Record board/build, commands, assertions and screenshots with each result.

The device contact sheet is `firmware/esp32/tools/shots.py`, whose scenes live
in `tools/shot_cells.py` and are shared with `tools/golden.py`. Any change to
the palette, the face, the arms, the card footer or the dashboard invalidates
`firmware/esp32/tests/golden/ws-amoled164/` and the goldens must be re-recorded
on hardware in the same commit.

**Record and verify like this, or the check is meaningless.** `golden.py record`
copies whatever sits in `/tmp/boop-shots`, so a `check` run immediately after a
`record` compares those same images against goldens made from them and always
passes. Additionally `shots.py` aborts whenever `state.connected` is true, and
`dataConnected()` stays true for 60 s after any frame — including the frames
`shots.py` itself just sent — so a second run inside that window exits early and
leaves a mixed-vintage directory behind. Never redirect its output to
`/dev/null`. The sequence that actually verifies:

```sh
rm -rf /tmp/boop-shots && python3 tools/shots.py   # watch for errors
python3 tools/golden.py record
# wait for state.connected to go false (up to 60s), then capture again
rm -rf /tmp/boop-shots && python3 tools/shots.py
python3 tools/golden.py check                      # independent round-trip
``` Cells cover the four phases of the dashboard
invitation, the single-agent board, and the heart at its peak and on the way out.

Webcam verification requires explicit permission and physical setup for that
session; it is not part of ordinary build or screenshot checks.

## Release status and history

Outstanding live/model/hardware and packaging gates are listed in [Plan](PLAN.md).
Earlier phase procedures and evidence are preserved in
[verification history](VERIFICATION-HISTORY.md). Historical checks for removed
features are not required to restore them; use current contracts for new tests.

Growth without levels: verify persisted XP is unchanged, completed-turn units
aggregate by civil day, active-only days preserve streaks, and twelve-week grids
render in English/Korean and both appearances. Device stats show cumulative XP
and ignore level transitions. Build firmware; physical verification is separate.

## Previous agent dashboard verification (superseded)

Run `make test` (uses the XCTest shim on CLT-only Macs); with full Xcode, targeted `swift test --filter AgentDashboardTests` and `HeartbeatTruncationTests` from app also work. Verify full-session counts beyond six, turn start/end, session end/stale cleanup, attention priority and wire bounds. Build the shipping Waveshare firmware. In an independent USB-only reservation run `test_agent_dashboard.py`: mixed counts persist beyond ten seconds, all-working/all-idle exit, legacy omission clears, invalid rows reject atomically, and attention wins. Capture settled and transitional dashboard screenshots and verify readable counts, sage non-zero idle, cream working counts, dimmed zeros, the hairline under the column heads, a table centred in the band below the buddy at one and at three agents, and an unobscured animated corner face whose gesturing hand lands above the column heads rather than on them. Restore normal firmware. Production BLE integration remains a separate gate.

For the dashboard invitation, capture entry-relative 650, 1250, 1950 and 3000 ms. Run the full-loop regression across re-applied frames as well as the original two-frame check. Verify the two downward nods and rosy smile stay above the fixed text, and repeated-frame board pixels remain identical.

## Glance completion gates

Test short/duplicate/failed completions, coalescing at 5/8 seconds, three-second
cooldown, priority cancellation, title fallback, UTF-8/escaped frame bounds and
full counts beyond preview. Device tests cover repeated frames, reconnect,
notice/table/attention priority, page navigation and sage wash screenshots.
Re-record changed hardware goldens and independently recapture before checking.
Production BLE requires the owner-launched updated app. Webcam remains opt-in.
