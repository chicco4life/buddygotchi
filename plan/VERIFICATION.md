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
| Behavior | Live guide reload, silence, eligibility, cancellation, five-second timeout-to-silence and text bounds |
| Reflection | Evidence/privacy bounds, valid memories, ignored legacy traits, invalid/unavailable model, daily idempotence |
| Approvals | Editor-only for every agent, stale enabled config/hook passthrough, ignored device decisions |
| Wire | UTF-8 caps, compatibility, bounded nudge rung, ignored retired fields |
| Mac UI | Overview and Settings; sessions follow status, compact XP is last and includes tasks/streak; no Activity navigation; pending cards stay on Overview; English/Korean and light/dark |
| Palette | Every `BuddyTheme.*Ink` tone clears 4.5:1 against its own appearance's paper; amber appears only for "needs you", never on a primary action; the twelve-week grid and its legend are unclipped at the resting height |

Latest results and remaining gates are maintained in [Implementation status](PLAN.md),
with dated evidence links. Earlier screenshots may show removed UI such as the
Last finished footer; they are historical evidence, not the current specification.

## Device footer removal

The calm idle/working/done face must draw the same bottom
35-pixel band with or without recent history. A tap in the former footer opens
the ordinary first detail page; Next still reaches history and Back exits.
Run `test_agent_dashboard.py` and `test_work_scope.py` on the reserved USB-only
image, independently repeat affected scope/face captures, and confirm unchanged
history/completion goldens. Install only normal firmware after verification.

## Live hooks and model

Optional dialogue: each display occasion must accept `SILENT`. Unavailable,
timed-out and invalid generations must not insert stock greetings/error text or
record an empty remark in history. Evaluate thin evidence, redundant remarks and
appropriate social moments with the live model; fixture tests prove the silence
path, not the model's judgment of when to use it.

Before trusting hook-dependent results, use the `doctor` skill and its live
confirmation sequence. The owner must launch the Boop app; agents must not.
Registration checks follow HookInstaller's passive lifecycle and elicitation
events. `PermissionRequest` is deliberately absent; its absence is not a repair
warning because approval decisions stay in the editor.
Run the supported harness flows against that identified app instance. Verify
native approvals, old enabled settings, permission-event passthrough and hook
repair without removing third-party hooks. Verify passive attention separately.

On a supported Mac, evaluate real Foundation Models output against the guide in
English for companion text. UI localization remains separate. Check that silence is
common when appropriate, scope covers the desk, claims use supplied evidence,
invalid reflection leaves the stored profile unchanged,
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

## Whole-desk scope

Run `make test` for WorkContextTests and the shared delivery tests. Check whole-desk
coverage, worktree identity, same-name isolation, missing intent, fair input bounds,
idle expiry, lifecycle clearing, no regeneration on unchanged tool activity,
strict output caps, stale replies and wire priority. Enable offscreen snapshots
to inspect `work-scope-{en,ko}-{light,dark}.png`. Build both Mac products and both
shipping/USB-only Waveshare firmware. USB verification must test scope persistence,
omission, atomic overflow rejection, working counts, task-page/completion priority
and UTF-8 layouts; restore the previous normal image after the reserved run. Re-record
and independently reproduce goldens. Live Foundation Models semantics and native
hook coverage remain distinct from fixture and rendering tests.

Before integrating main: 361 app tests, both Mac products, both Waveshare build variants,
18 USB checks and 49/49 independently reproduced goldens passed. The two old
dashboard pixel tests now inspect the documented table band at y=108 instead of
including the enlarged animated buddy at y=70. Scope did not change table layout.
[Evidence](evidence/work-context-2026-09-11/README.md) records the failed live-model
quality gate separately. No native-editor or production BLE pass is implied.
## Glance completion gates

Test short/duplicate/failed completions, coalescing at 5/8 seconds, three-second
cooldown, priority cancellation, title fallback, UTF-8/escaped frame bounds and
full counts beyond preview. Device tests cover repeated frames, reconnect,
notice/table/attention priority, page navigation and sage wash screenshots.
Re-record changed hardware goldens and independently recapture before checking.
Production BLE requires the owner-launched updated app. Webcam remains opt-in.

## Dashboard exit and inset regression

USB-only firmware exposes `tap X Y` to invoke the same bounded coordinate handler
as a panel touch. Verify a normal tap exits immediately with multiple session and
history pages, Next wraps without exiting, and hidden dialogue cannot consume an
exit. Physical primary/secondary taps also exit. Capture thread, long-name and
history pages; inspect 40 px side margins and 24 px top/bottom clearance.
`golden.py record/check --only NAME` updates/checks selected changed scenes;
record and check must still use independently captured images.

The [main integration evidence](evidence/work-context-main-integration-2026-09-11/README.md)
records 369 app tests, 26 USB interaction checks and six independently reproduced
scope goldens for the combined completion/task-page and companion UI.

## Quality pass regressions — 2026-09-11

`make test` covers complete Mac session lists versus bounded device previews,
companion bubble preservation, test-cheer priority, shared popover sizing and
firmware-update confirmation/mismatch/timeout/check races with fixture services.
Snapshot viewports use the same sizing function as the live popover.
HTTP smoke tests assert immediate native permission passthrough and one durable
turn/XP award. Workflow tests use private reservation files, never the real
device lock.

Reserved USB-only runs include `test_motion_quality.py`: interrupt a dance and
a greeting, inspect head/arm settling, check monotonic card departure, and cancel
a completion with a system card. A departing passive footer must yield to
system/dialogue/sleep surfaces. Keep reminder-test heartbeats below the
60-second link-expiry window; do not rewind before the last heartbeat. Visual
comparisons may recapture an invalid USB transfer at most three times, warning
on each retry and checking size/CRC before comparing. The dedicated screenshot
integrity test uses one attempt and fails immediately on corruption. Debug-only pose telemetry supports these tests;
it is absent from shipping status. The hardening fixture recognizes `usbOnly`
so its own recent USB frames do not incorrectly skip the safety tests.
Run the ordinary non-BLE HIL suite and two independent full golden captures.
Webcam review uses bounded clips for working gaze, greeting, dance and card
arrival/dismissal, only under the current user-confirmed camera session.
Fixture updater tests and USB runs do not establish real OTA or production BLE.
Release packaging must target `ESP32-S3`: bootloader at `0x0`, partition table
at `0x8000`, the build toolchain's `boot_app0.bin` at `0xe000`, and application
at `0x10000`. Generate both manifests with the shipping build and explicit
`--boot-app0`; verify that every web-install URL has its matching copied image
and the OTA manifest hash matches the application. The retired ESP32 `0x1000`
bootloader layout is invalid for the supported board. Run
`python3 -m unittest discover -s firmware/esp32/tests -p 'test_release_manifests.py'`.

[Quality-pass results](evidence/quality-fluidity-2026-09-11/README.md): 382 app
tests, 105 HTTP checks, six workflow checks, and 100 distinct non-BLE device
scenarios verified across the full run and targeted recheck; 52 final goldens
reproduced twice at zero error. Camera review is explicitly limited.

The subsequent user-launched GUI run passes fifteen coordinated normal-firmware
Bluetooth assertions, including restoration. The live Codex doctor passes without
warnings. A startup panic remains unexplained after eleven confirmed clean follow-up reboots;
do not turn functional passes into a stability claim. The public update manifest
returns HTTP 404, and real local-model scope samples still omit work or violate
the title contract. Native Claude/Cursor editor interaction and actual OTA remain
open. See the evidence README's follow-up section for the exact limits.
