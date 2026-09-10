# UX: Help

Current contract, 2026-09-11. The nudge ladder is the only help behavior.

| Rung | Time since request arrival | Behavior |
| --- | --- | --- |
| 0 | Immediately | Amber field, face turns, one “meep?” |
| 1 | 60 seconds | Soft repeat, small lean |
| 2 | 120 seconds | Stronger sound and field pulse |

All stakes use the same timings, supplied by `NudgeTiming`. Each request owns
its ladder; a delayed tick advances to the correct rung. There is no repeating
rung-2 timer. Dismissal resets the rung and silences this request until it
clears. New requests start fresh, including the same tool in the same session.
No dismissal counters, shortening intervals, per-tool snoozes or rate floors.

Quiet mode mutes sounds while retaining visual escalation. Snoozing does not
approve, deny or resolve a request. The 290-second prompt expiry remains, so
both nudges occur before it. Approval arming, acknowledgement and fail-open
behavior are specified in [the component guide](BEHAVIORS.md#7-approvals-hooks-and-reminders).
