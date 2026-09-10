# Implementation plan

Current phase: agent availability dashboard implemented and USB hardware verified;
essential behavior simplification is implemented and automated checks pass;
live model, editor and
physical-device verification remain. [Component behaviors](BEHAVIORS.md) is the
current contract, with detailed specs in the [index](README.md).

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

Implemented full-session per-harness counts, additive wire field, persistent mixed-state board, animated corner buddy, all-idle green footer and retained idle affection. 344 app tests and 11 USB hardware tests passed; shipping Waveshare and USB-only builds passed. Screenshots were inspected. [Dashboard evidence](evidence/agent-dashboard-2026-09-11/README.md). M5 flash-size limits and production BLE with the owner-launched updated app remain outstanding.

Dashboard invitation refinement: larger buddy above IDLE, two downward nods and a rosy smile, with unchanged static counts and proportional labels. 12 USB hardware tests passed, both Waveshare variants built, and the captured loop was checked against static board pixels. Device verification recorded in dashboard evidence.

Main integration preserves cumulative XP and daily activity: 345 app tests passed with zero skips, and the integrated shipping Waveshare firmware built successfully.
