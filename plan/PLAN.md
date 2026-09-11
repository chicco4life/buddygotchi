# Implementation plan

Current phase: shared Markdown behavior pipeline and whole-desk scope summary
implemented as a development slice. Automated and USB checks pass; real-model
whole-desk coverage is not yet reliable. Companion text is English-only. Native-editor and
production BLE gates remain.
This includes main's glanceable completion notices and tap-to-view task pages.
Combined verification is recorded below; earlier feature evidence is historical.
[Component behaviors](BEHAVIORS.md) is the current contract, with detailed specs
in the [index](README.md).

## Implemented

| Area | Current result |
| --- | --- |
| Core | Six states; 1/3/5-minute celebrations (none below 1 minute); 3 s folding |
| Help | Fixed nudges at 60/120 s; dismissal snoozes only the current request |
| Approvals | Editor only; Buddy interception and controls removed; stale hooks return passthrough |
| Growth | Completed turn +3 XP, active local day +10; historical XP preserved; no levels; daily turn grid and consecutive-day streaks |
| Local model | One Markdown guide and shared display context; whole-desk scope plus existing dialogue; no timed check-ins |
| Memory | Reduced facts, small profile and recent outcomes; no numeric personality/bond or familiarity counters |
| Mac/device | Quiet mode, simple menu popover/settings, fixed appearance |
| Removed | Gifts, recaps, teach, inferred stuck/hungry, quick commands, agent expression/drawings, named moment creation, leaderboard/sync/signing |

## Verified in this change

### Integration with current main

The scope phrase sits above the calm device face, leaving the working and
last-finished footers clear. Task pages and completion notices cover it.
The combined implementation passes 369 app tests with zero skipped; both Mac
products and both firmware variants build. Earlier evidence below describes
the feature branches before integration.

### Shared behavior pipeline and work scope, 2026-09-11

- **361 app tests passed, zero skipped**; both Mac products built.
- Shipping and USB-only Waveshare firmware built. **18/18 USB scope/dashboard
  checks passed**. **49/49 hardware goldens** were re-recorded and reproduced by
  an independent capture at exactly zero error; the existing 43 were unchanged.
- Earlier English/Korean fixture scope snapshots inspected on Mac in both appearances and on
  the actual device. The exact previous normal firmware/settings were restored.
- The live Foundation Models check is **not a quality pass**: it sometimes
  summarizes only one task/project, echoes examples, or uses the wrong language;
  some trials timed out. Byte/cancellation tests do not establish semantic truth.
  Multilingual companion output is now deferred; coverage remains the open gate.
  Do not treat this as ready for ordinary use until that gate is resolved.
- English-only follow-up: 361 app tests pass. The fresh local replay timed out
  at the diagnostic 30-second limit; production retains its five-second timeout.
- The shared context and scope occasion are implemented. Richer check-result
  triggers and durable episode callbacks remain stages 2/3, not completed work.
- [Evidence and remaining gates](evidence/work-context-2026-09-11/README.md).


### UI/UX pass, 2026-09-11

- **349 app tests passed, zero skipped**, including four new `PaletteTests`
  that pin the contrast promise in `UX-APP.md`, keep the surfaces separable,
  and fail the build if amber is ever used to tint a primary action.
- Both Mac products built. Shipping `ws-amoled164` firmware built, flashed, and
  **43/43 device goldens re-recorded and reproduced at 0.000000 error**,
  including five new dashboard cells and two heart cells.
- Offscreen app screenshots reviewed in both appearances for Overview, the
  needs-you state, Settings and all five setup steps.
- Device-side fix: the needs-you and uh-oh field washes were rendering the
  *identical* colour `(36,0,0)`, because `animMix` blends in RGB565 and the
  8-bit canvas truncates to RGB332. Both washes were re-chosen against the real
  quantization path; see `UX-DEVICE.md` §7.
- **The M5StickC Plus 2 is retired** (owner, 2026-09-11: "the old device I no
  longer use"). Removed: both `m5stickc-plus` build envs, `partitions.csv`,
  `firmware/hal/hal_m5stick.cpp`, the `M5StickCPlus2`/M5GFX dependency, the
  `BOARD_WS_AMOLED_164` board conditionals (one board needs no board switch),
  and the portrait layout branches — `HAL_LANDSCAPE`, `HAL_UI_SCALE` and
  `HAL_HUD_H` existed only for its 135x240 screen and are gone. The Waveshare
  ESP32-S3-Touch-AMOLED-1.64 is now the only supported board; `default_envs` is
  `ws-amoled164`. The previous generation stays readable under `archived/`.
  This supersedes the partition-table fix made earlier the same day, which is
  moot now that the board is gone.
- **Not verified:** webcam verification of animation smoothness is outstanding.
  Camera access was granted and one greet-wave clip was recorded, but the
  footage could not judge motion (room-metered exposure crushed the screen,
  device small and oblique with a reflection, panel at the dimmed 90/255). To
  be retried with Buddy larger, face-on and awake. See the evidence README.
- **Not verified:** BLE integration with the Mac app, and any live-model or
  native-editor flow.
- [UI pass evidence](evidence/ui-pass-2026-09-11/README.md).

- Cumulative XP and daily turn grid: 342 tests passed, zero skipped; both Mac
  products and shipping firmware built. [Evidence](evidence/cumulative-xp-2026-09-11/README.md).

- Share removal: 340 tests passed, zero skipped; both Mac products built.
  [Evidence](evidence/no-share-2026-09-11/README.md).

- Compact overview update: 341 tests passed, zero skipped; both Mac products built.
  [Layout evidence](evidence/compact-overview-2026-09-11/README.md).

- **341 app tests passed, zero skipped**, including offscreen native UI checks.
- Boop and BoopSignal built; shipping Waveshare firmware built without flashing.
- [Essentials evidence](evidence/essential-behaviors-2026-09-11/README.md).
- Overview now puts sessions after status and compact XP last; Activity is removed.
  Share-card export and the overflow menu are removed; Quit is a plain footer button. Growth, time-away greetings,
  60/120-second reminders and event-based dialogue remain.

## Previous verification (before this change)

- 368 app tests passed, zero skipped; Boop and BoopSignal built.
- Shipping Waveshare firmware built after the device simplification.
- Offscreen Mac views reviewed; Python/shell syntax checks passed.
- [Latest app evidence](evidence/markdown-learning-native-approvals-2026-09-11/README.md)
  and [device/UI simplification evidence](evidence/behavior-simplification-2026-09-11/README.md).

## Remaining gates

1. Evaluate real on-device companion responses in English: relevance, silence,
   supported memories and latency. Unit tests use fixtures.
2. With the owner-launched app, verify native approvals, stale-hook passthrough
   and hook repair in supported Claude/Codex/Cursor versions.
3. Verify nudge timing, passive dismissal, Quiet mode and reconnect
   on physical hardware over production BLE. Build success is not a device pass.
4. Finish applicable release checks: clean installation/update, supported Mac and
   board coverage, signing/notarization and packaging. Historical phase results
   do not automatically close these gates for the changed build.

Use [Verification](VERIFICATION.md) for commands and evidence rules. No device
was flashed, GUI launched, or webcam session performed for this change.
The original phase checklists and dated evidence remain in
[plan history](PLAN-HISTORY.md); removed features there are not future requirements.

## Agent dashboard update

Implemented full-session per-harness counts, additive wire field, persistent mixed-state board, animated corner buddy, all-idle green footer and retained idle affection. 344 app tests and 11 USB hardware tests passed; shipping Waveshare and USB-only builds passed. Screenshots were inspected. [Dashboard evidence](evidence/agent-dashboard-2026-09-11/README.md). Production BLE with the owner-launched updated app remains outstanding. (The M5 flash-size limit noted here is moot: that board was retired on 2026-09-11.)

Dashboard invitation refinement: larger buddy above IDLE, two downward nods and a rosy smile, with unchanged static counts and proportional labels. 12 USB hardware tests passed, both Waveshare variants built, and the captured loop was checked against static board pixels. Device verification recorded in dashboard evidence.

Main integration preserves cumulative XP and daily activity: 345 app tests passed with zero skips, and the integrated shipping Waveshare firmware built successfully.

## Glanceable completion implementation — 2026-09-11

Replaced the mixed count dashboard with a working face, coalesced completion
notices, sage wash and tap-through thread/history pages. 357 app tests passed,
zero skipped; both Mac products and both firmware variants built. 12 USB device
checks passed and 44/44 independently recaptured goldens matched at zero error.
Codex titles use bounded local index metadata; unavailable titles use project
plus stable ID. [Evidence](evidence/glance-completions-2026-09-11/README.md).
The owner must launch the rebuilt Mac app before the production BLE gate closes.

## Dashboard navigation and spacing — 2026-09-11

Normal dashboard taps now exit directly; a separate Next control pages details.
The table gets 40 px side margins and 24 px top/bottom margins. Both firmware
variants built; 19 USB checks passed, and three changed/new dashboard goldens
matched independent captures at zero error. Shared panel handling, multiple/history
pages, hidden dialogue and invalid coordinates were checked. The previous normal
firmware is restored because another hardware task is active; the verified
candidate is not left installed. [Evidence](evidence/dashboard-navigation-spacing-2026-09-11/README.md).

The [main integration evidence](evidence/work-context-main-integration-2026-09-11/README.md)
records 369 app tests, 26 USB interaction checks and six independently reproduced
scope goldens for the combined completion/task-page and companion UI.
