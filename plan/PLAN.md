# Implementation plan

Current phase: behavior simplification is implemented; live model, editor and
physical-device verification remain. [Component behaviors](BEHAVIORS.md) is the
current contract, with detailed specs in the [index](README.md).

## Implemented

| Area | Current result |
| --- | --- |
| Core | Six states; explicit errors only; effort from task duration; 3 s celebration folding |
| Help | Fixed nudges at 60/120 s; dismissal snoozes only the current request |
| Approvals | Native editor default; Buddy opt-in enforced at the server; Codex also requires its own opt-in |
| Growth | Completed turn +3 XP, active local day +10; historical XP preserved; ordinary consecutive-day streaks |
| Local model | Live-read Markdown steers dialogue/silence, memory selection and personality evolution |
| Memory | Reduced facts and bounded model reflection; no automatic bond awards or fixed habit detectors |
| Mac/device | Quiet mode, simple menu popover/settings, fixed appearance, local sharing |
| Removed | Gifts, recaps, teach, inferred stuck/hungry, quick commands, agent expression/drawings, named moment creation, leaderboard/sync/signing |

## Verified in this change

- 368 app tests passed, zero skipped; Boop and BoopSignal built.
- Shipping Waveshare firmware built after the device simplification.
- Offscreen Mac views reviewed; Python/shell syntax checks passed.
- [Latest app evidence](evidence/markdown-learning-native-approvals-2026-09-11/README.md)
  and [device/UI simplification evidence](evidence/behavior-simplification-2026-09-11/README.md).

## Remaining gates

1. Evaluate real on-device model responses in English/Korean: relevance, silence,
   supported memories, personality changes and latency. Unit tests use fixtures.
2. With the owner-launched app, verify native approval defaults and explicit Buddy
   opt-in in supported Claude/Codex/Cursor versions, including disable/passthrough.
3. Verify nudge timing, button guards, Quiet mode, reconnect and acknowledgement
   on physical hardware over production BLE. Build success is not a device pass.
4. Finish applicable release checks: clean installation/update, supported Mac and
   board coverage, signing/notarization and packaging. Historical phase results
   do not automatically close these gates for the changed build.

Use [Verification](VERIFICATION.md) for commands and evidence rules. No device
was flashed, GUI launched, or webcam session performed for this change.
The original phase checklists and dated evidence remain in
[plan history](PLAN-HISTORY.md); removed features there are not future requirements.
