# Implementation plan

Current phase: glanceable activity and completion notices — implemented, with
357 app tests passing and both Mac products and firmware variants built.
12 USB hardware checks passed; all 44 device goldens matched independent
captures at zero error. Owner-launched updated-app BLE verification remains.
[Component behaviors](BEHAVIORS.md) is the current contract, with detailed specs
in the [index](README.md).

## Implemented

| Area | Current result |
| --- | --- |
| Core | Six states; 1/3/5-minute celebrations (none below 1 minute); 3 s folding |
| Help | Fixed nudges at 60/120 s; dismissal snoozes only the current request |
| Approvals | Editor only; Buddy interception and controls removed; stale hooks return passthrough |
| Growth | Completed turn +3 XP, active local day +10; historical XP preserved; no levels; daily turn grid and consecutive-day streaks |
| Local model | Live-read Markdown defines personality, event-based dialogue and memory; no timed check-ins |
| Memory | Reduced facts, small profile and recent outcomes; no numeric personality/bond or familiarity counters |
| Mac/device | Quiet mode, simple menu popover/settings, fixed appearance |
| Removed | Gifts, recaps, teach, inferred stuck/hungry, quick commands, agent expression/drawings, named moment creation, leaderboard/sync/signing |

## Verified in this change

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

1. Evaluate real on-device model responses in English/Korean: relevance, silence,
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
