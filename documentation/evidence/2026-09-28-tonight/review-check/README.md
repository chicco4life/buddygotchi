# A second check of the review lane's fixes

2026-09-28, overnight lane "review-check", on `ovn2/review` after the
review lane's nine commits ([its evidence](../review/README.md)), from
`main` at `7f5d10ff`, which hadn't moved. The question for each fix: is
the defect really gone, does its test really pin it, and did it break
anything else (moments, timeouts, loops, reactions dropped or cut
wrongly, "needs you" winning), with the specs in step.

## The verdicts

| Fix | Verdict |
| --- | --- |
| The line is held until the device's `ended` (`MomentSchedule.hold`, `ended`) | Holds. `send` holds before the line goes out, so no `ended` can come first. An `ended` for another id changes nothing, and one that comes after the app gave up is ignored. The hold's deadline is the handle's, so the pump's timer and the tick's `overdue` let go together |
| Whatever frees the line runs the pump (a rule moment, a tap, an `ended`, a `state`, a disconnect) | Holds. Removing each call in turn fails `testWhatFreesTheLineSendsTheNextAtOnce`, except the one in `show` ("needs you"), which no test covered. Now pinned (below) |
| The schedule mirrors the device: a tap wiggles, "needs you" stops everything, no rule moment while it shows | Matches the firmware: `Behaviour::tap` and `onMoment` do nothing while `held` (`attn` and not "no app"), and a fresh `attn` stops the moment and the line. The core puts the `state` first in its effects, so the Mac and the device see "needs you" before any moment of the same batch |
| A face is timed by the longer of the look's and the cheer's design while a cheer may play | An upper bound, as it must be: the device times the face by the cheer's design only if a cheer plays when the line arrives, and the look's otherwise |
| Waits counted to the turn, `lateMs`, dropping at once while busy | Holds. The harness's ceiling test now adds `lateMs`, and the tick's `overdue` runs before the harness's own check in the same tick |
| Random ids per launch | Holds. The first id is 1 to 2^31−1, and the device reads `id` as an unsigned 32-bit int (`device.cpp`) |
| Firmware: a face ended after its mumble is `done` | Holds. Only a stopped animation or line records a cut. `dbg.reset` still reports every moment it forgets as `cut (reset)`, as PROTOCOL.md §4 says |
| The e2e fixture, `seen`, the eval `reaction` field, `react`'s `none` | Hold. `seen` is the transcript's last `seq` when the state is built, which stays right when a pass is prepared after later entries |
| Specs | In step with the code, apart from the pump row below. `cmp CLAUDE.md AGENTS.md` and `diff -r plan/steering app/Boop/Resources/steering` are silent |

## Mutations

Each line deleted from `app/BoopKit/App/Runtime.swift` on its own, then
`swift build` and `.build/debug/BoopTests`:

| Line deleted | Result |
| --- | --- |
| `pump()` after the device's `ended` | Fails: "the device says the first is over: the second goes at once" |
| `pump()` in `playRule` | Fails: "a rule's cheer stops the second, and the third plays over the cheer" |
| `schedule.tapped` on a tap | Fails: "the tap's wiggle stops the third on the device" |
| `pump()` after an input | Fails at the same step |
| `schedule.stop` on a disconnect | Fails: "nothing played the first, so the second didn't wait for it" |
| `schedule.stop` in the pump with no device | Fails at the same step |
| `pump()` in `show` | **All 210 passed** |

## What I changed

| Commit | What |
| --- | --- |
| `0e6be0d3` | `testWhatFreesTheLineSendsTheNextAtOnce` queues a reaction behind the tap's and shows a "needs you" state: the one waiting must go at once, for the device to skip. It fails with the `pump()` in `show` removed |
| `a1fb4dad` | The pump kept any timer set for no later than the next turn. Its timer counts the Mac's uptime, which stops during sleep, and the moments' clock doesn't, so after a sleep (or `{"dev":"advance"}`) a waiting reaction could depend on a timer the clock had passed and get its turn up to about 5 s late when no `ended` freed the line. The pump now replaces such a timer. `testATimerTheClockHasPassedIsReplaced` fails with the old guard. ARCHITECTURE.md §3.8's timer table says so, and that a disconnect runs the pump |

## What ran

All on the final commit.

| Check | Result |
| --- | --- |
| `make build` | Builds |
| `make -C internal test` | 211 of 211 pass (210 before, 1 new; the "needs you" check extends an existing test) |
| `make -C internal fw-test` | 111 of 111 pass |
| `make -C internal sim` | 11 scenarios, 0 failed expectations, 0 changed pictures |
| boopctl_lib and webcam unit tests, run directly | 27 and 3 pass |
| `cmp CLAUDE.md AGENTS.md`, `diff -r plan/steering app/Boop/Resources/steering` | Both silent |

Not run: the board (`make -C internal e2e`), `make eval` and
`facegen.py --check`. My two commits touch none of the firmware, the
steering, the questions or the faces, and the pump change only affects
when its timer is set. The review lane ran all three on its fixes.

## Still open

The review lane's list stands (its proposals 1 to 4). One more thing,
by design rather than a defect: when "needs you" starts, a reaction
waiting its turn goes out at once and the device skips it, so HISTORY
says it didn't happen because something needed you
([harness/DECISIONS.md](../../../harness/DECISIONS.md) §5).
