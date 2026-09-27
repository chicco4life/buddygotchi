# Review of loops and pending: what was real, and what changed

2026-09-28, overnight lane "review", on `ovn2/review` from `main` at
`7f5d10ff` (A14, [PLAN.md](../../../PLAN.md)). A review of the loops and
pending change had 15 findings confirmed by at least two of three
verifiers, 3 that weren't, and 6 issues the builders had reported. Many
confirmed findings were the same defect found from different sides, so
they come down to eight problems. All eight are fixed, each pinned by a
test that fails on the old code, with its spec changed in the same
commit.

## The commits

| Commit | What it does |
| --- | --- |
| `7e3b612e` | A brain reaction on the device keeps the next one waiting until the device's `ended` for it, or until the app gives up on it. The schedule hears taps and "needs you". Anything that frees the line sends the next reaction at once. A wait is counted to when the turn came, and the timer runs on time. A reaction that has waited too long is dropped at once. While a cheer may be playing, a face is timed by the longer design. With no device, nothing holds the line |
| `3286beba` | Each launch's moment ids start at a random number |
| `5dd10701` | Firmware: if something ends a reaction's face early after its mumble has played, the reaction still counts as `done` |
| `57580dfb` | The pipeline check's Claude deploy now fails before the rate limit, as its expectation says |
| `f370d359` | A pass line records `seen`, the last entry its state saw, so its state can be rebuilt exactly |
| `bb2db6ec` | The protocol's example lines are real again, now with random ids |
| `cb58f122`, `f8b057a8` | Two new evals cover a reaction still in progress and one that didn't happen. `react`'s `none` now covers a reaction Boop is still making |

## Every finding, and what came of it

### Confirmed findings

| # | Finding (file) | Verdict | What I did |
| --- | --- | --- | --- |
| 1, 5 | A rule's cheer frees the line, but nothing runs the pump, so a reaction waiting behind a long face is dropped (`Runtime.swift:509`) | Real. Reproduced by a new test on the old code | `playRule`, a device tap, an `ended`, a `state` and a disconnect now run the pump. The pump's timer can be moved earlier. `testWhatFreesTheLineSendsTheNextAtOnce` fails on `7f5d10ff` at the `ended` step, and again at the cheer step when the first is taken out (`7e3b612e`) |
| 4, 9 | The schedule ignores the device's `ended` and taps, so the next reaction waits for a face that is already over and is dropped after 5 s (`Runtime.swift:161`, `MomentSchedule.swift:75`) | Real. It was also builders' issue 1 | `MomentSchedule.hold` and `ended(id:now:)`: a reaction on the device holds the line until its `ended`, and at most until the app gives up on it (its length plus `endGraceMs`). `testTheDeviceSaysWhenTheLineIsFree` pins this (ARCHITECTURE.md §3.2) |
| 3, 7, 8, 11 | A tap, or "needs you", ends the cheer on the device, but the app still times the next face by the cheer's shorter loop. So the app gives up before the face has ended, and chatter or the next reaction can cut it (`Runtime.swift:155, 401`, `MomentSchedule.swift:43`) | Real | Two fixes that back each other up. First, the schedule now mirrors what the device does by itself: `tapped(now:)` acts as a wiggle, a new "needs you" stops everything, and while something needs you the rules' moments change nothing. Second, while a cheer may still be playing (until it should end, plus `linkSlackMs`, 0.5 s), a face is timed by the longer of the cheer's design and the look's. This also covers a line that reaches the device just after the cheer ended there. Pinned by `testTheScheduleTimesAMomentByTheDesignShowing` and `testWhatFreesTheLineSendsTheNextAtOnce` |
| 2, 6, 10, 14 | Ids restart at 1 each launch, and the device merges a repeated id into an earlier launch's moment, so the new reaction reports the wrong end (`behaviour.cpp:164`, `Runtime.swift:144`) | Real. It was also builders' issue 3 | Each launch starts at a random id in 0..<2^31−1 and counts up, going back to 1 after `Int32.max`. The device reads ids as 32-bit unsigned. `testMomentIdsDifferEachLaunch` pins this, and PROTOCOL.md §3 says it. I left the device's merge alone (proposal 1) |
| 12 | A reaction cut after its mumble has played is recorded as "didn't happen", so Jev may say it again (`Runtime.swift:171`) | Real | Fixed on the device. Only a stopped animation or line counts as `cut`. Ending the face held after the line leaves the reaction `done`. The firmware test now expects `done` after a tap, "needs you", the cheer or a newer line once the mumble is over, and `cut` for a tap during the bubble. It fails on the old firmware with `Expected '17 done' Was '17 cut by tap'`. PROTOCOL.md §4, DECISIONS.md §5 and a decision-log row were updated (`5dd10701`) |
| 13 | The new steering rule about `(in progress)` and `(didn't happen: …)` had no eval (`Eval.swift:199`) | Real, and it hid a behaviour bug | A scenario step can now say how its reaction ends (`reaction`: `done`, `in progress` or `failed: <why>`), with two new scenarios. Against Jev, `11-comeback-still-showing` passed in 0 of 3 runs: Jev said a second proud "…finally!", held three times, while the first was still showing (react proud 0.85, none 0.13). The reason was `react`'s `none` option, which said it wasn't for anything PERSONALITY's Examples react to. `none` now covers a reaction Boop is still making. After that, `make eval` passed 12 of 12 scenarios in all 3 runs (`cb58f122`) |
| 15 | A too-old reaction stays "(in progress)" until the line frees, up to about 36 s (`MomentSchedule.swift:75`) | Real | `due` drops a waiting reaction as soon as it has waited more than 5 s, even while the line is busy. The pump is asked back at that moment. Pinned by `testAWaitIsCountedToItsTurn` |
| 16 | PROTOCOL.md §3 and ReactAction's comment say a reaction waits only for a line, not for a face still showing (`PROTOCOL.md:180`) | Real, docs only | Both now say "line or reaction's face", and PROTOCOL.md links to ARCHITECTURE.md §3.2 for the whole rule |

### Findings that weren't confirmed

| Finding | Verdict | What I did |
| --- | --- | --- |
| With no device, a failed reaction still holds the schedule for its whole face, so the next one ends "waited too long" instead of "no device connected" | Confirmed by reading the code: `due` set `lineUntil` before the pump knew there was no device | Fixed in `7e3b612e`. With no device the line stays free. The end of `testWhatFreesTheLineSendsTheNextAtOnce` pins it: two reactions in a row both end "no device connected" |
| Waiting moments are matched by id only, so ids from another link or an earlier launch merge | Same root as findings 2, 6, 10 and 14 | Random ids per launch fix it for the app. The device side is proposal 1 |
| `react.loops`' "twice" says it isn't for routine work, but chatter's Examples hold routine lines twice | Not confirmed. `07-chatter-reacts-to-everything` passes in all 3 runs | Nothing |

### The builders' known issues

| # | Issue | What I did |
| --- | --- | --- |
| 1 | The line stays held for the Mac's own estimate even after the device says the face ended | Fixed, as findings 4 and 9 |
| 2 | Back-to-back reactions: the next could reach the device just before the last one ended and cut it | Fixed. The next reaction goes out only after the last one's `ended`, or its deadline. On the board, each queued reaction went out within 1 ms of the last one's `ended` (below) |
| 3 | Ids restart every launch | Fixed, as findings 2, 6, 10 and 14 |
| 4 | The pump's timer fired 0.3 s late and dropped a reaction whose turn had come at 4.84 s | Fixed twice over. `asyncAfter` allows a tenth of the wait as slack, so a 3 s wait could fire 0.3 s late. The pump now uses a timer source with 5 ms of slack. Also, a wait is counted to when the turn came: a pump up to 1 s late (`MomentSchedule.lateMs`) still counts to the turn, and a later one counts to now. That way a Mac that slept doesn't send an hour-old reaction. The test uses the exact 4.84 s turn and a pump at 5.16 s |
| 5 | `make -C internal e2e` failed "claude's deploy failed on" | Fixed in the fixture, not the expectation. Claude always sends a tool call's result before the next API request, and a rate limit is what fails that request. So `PreToolUse` then `StopFailure` with no result isn't a real sequence. The deploy now fails after its 40 s, as `PostToolUseFailure` with an exit code and a `PRIVATE_` marker in its error text, and then the turn hits the rate limit. The core records the failed deploy, then "failed (rate limit) … 1 tool (1 failed). Deploy failing." `ReplayTests` still passes |
| 6 | A settle recorded while Jev answers makes an exact rebuild inexact | Fixed. It was cheap: a Jev pass's line carries `seen`, and a rebuild takes the entries up to it. The rebuild test now has a settle arrive while the brain answers. The rebuild is exact with `seen` and not without it (HARNESS.md §5.3, §9) |

## What ran

All on the final code (`f8b057a8`), except where the table says otherwise.

| Check | Result |
| --- | --- |
| `make build` | Builds |
| `make -C internal test` | 210 of 210 pass (205 before; 5 new tests) |
| `make -C internal fw-test` | 111 of 111 pass |
| `make -C internal sim` | 11 scenarios, no failed expectations, no picture changed |
| Tools tests, run directly because `make … tools-test` can't rebuild the venv in a lane worktree | boopctl_lib 27 pass, webcam 3 pass |
| `cmp CLAUDE.md AGENTS.md`, `diff -r plan/steering app/Boop/Resources/steering` | Both silent |
| `make flash` | Firmware `f370d359d7` on `/dev/cu.usbserial-110`. `dbg.ping` then reported 74,076 bytes of heap free, 73,960 at the least, and 73,732 after both pipeline runs |
| `make -C internal e2e` (twice, on `f370d359` and on `f8b057a8`) | PASS both times. All 17 checkpoints pass, and all 5 expected events appear, including "claude's deploy failed on". p95 from hook to board is 65 and 66 ms. All 9 brain moments got their `ended`: 7 `done` and 2 `cut (moment)`. None were dropped |
| On the board by hand (below) | Every way a reaction can end, with the new rules |
| `make eval`, with Jev | 12 of 12 scenarios pass in all 3 runs. Median 244 ms, slowest 584 ms. Before the `none` change: `11` passed 0 of 3, `12` passed 3 of 3 |
| `facegen.py --check` | Not run. No face or facegen file changed |

### The pipeline check's two cuts

Both are expected. At 03:06:33.800 the fixture jumps the app's clock
40 s mid-turn. The app then stops waiting for the reaction still on the
board, and the next reaction cuts it. Only a jumped clock causes this
(proposal 2). At 03:06:44.279 the Codex turn-start reaction waited
4,857 ms for the rate-limit reaction's face over idle. It went out 1 ms
after that face's `ended`. The old code dropped it at this point in the
same run (4.84 s wait, timer 0.3 s late). Here the Codex cheer then cut
it 0.66 s into its mumble.

### On the board by hand

`boopctl bridge` on `/tmp/brv/usb.sock`, then
`Boop --headless --state-dir /tmp/brv/state --link usb:/tmp/brv/usb.sock --socket /tmp/brv/boop.sock --brain scripted --name Pip --debug`.
Reactions were forced with `{"dev":"answer",…}`, taps with `dbg.press`
through the bridge, and needs you with `boop-hook`. From the app's log:

```
02:57:00.132 link brain → {"t":"moment","say":{"syl":"da-to-lon","word":"finally","at":3,"tune":"lift","ms":135},"mood":"proud","loops":2,"id":1710758195}
02:57:14.107 device: moment 1710758195 ended done                       asleep, held twice: the 2nd boundary
02:57:19.689 … react: Boop made an excited face, held once, …            (waits for the turn-start reaction)
02:57:20.195 … react: Boop made a curious face, held once, …             (waits too)
02:57:20.548 device: moment 1710758196 ended done
02:57:20.549 link brain → {… "mood":"excited" … "id":1710758197}          1 ms after the ended
02:57:22.577 device: moment 1710758197 ended done
02:57:22.577 link brain → {… "mood":"curious" … "id":1710758198}          the same ms
02:57:28.817 device: input tap                                           during the mumble
02:57:28.819 device: moment 1710758199 ended cut (tap)
02:57:37.339 device: input tap                                           4.6 s in: mumble over, face held
02:57:37.341 device: moment 1710758200 ended done
02:57:42.062 link brain → {… "mood":"sad" … "id":1710758202}              the cheer freed the line: sent at once
02:57:42.069 device: moment 1710758201 ended cut (moment)
02:57:48.069 device: moment 1710758202 ended done
02:57:51.814 link brain → {… "mood":"determined" … "id":1710758204}       needs you freed the line
02:57:51.826 device: moment 1710758203 ended cut (needs_you)
02:57:51.829 device: moment 1710758204 ended skipped
02:57:58.367   ✗ react (36) didn't happen: the device disconnected       the bridge killed
```

A second short run, with a client of the bridge recording the board's
raw lines, gave the `ended` examples in PROTOCOL.md §4:
`{"t":"ended","id":558386700,"how":"done"}`,
`{"t":"ended","id":558386701,"how":"cut","why":"tap"}`,
`{"t":"ended","id":558386703,"how":"skipped"}`.

## Proposals

1. **The device could handle a repeated id itself.** `Behaviour::wait`
   merges a new moment into a waiting one with the same id. With random
   ids per launch this is now about a one in 2^31 chance. As a fallback,
   the device could report the old moment as cut at once and add the
   new one fresh. That's a few lines in `wait()` plus a test, but it
   changes the firmware again, so I left it.
2. **The Claude fixture's 40 s clock jump still cuts one reaction.**
   `advance_ms` jumps the app's clock while a reaction plays, so the app
   gives up on it and the next reaction cuts it. The jump could happen
   while nothing plays, for example after a `wait_ms`, or
   `{"dev":"advance"}` could skip moment deadlines. It's only a test
   artefact, so I left it.
3. **A face over idle still holds up to 9 s.** Now that the line is
   freed by `ended`, a reaction waits only as long as the face really
   lasts. But one arriving in the first 4 s of a one-loop idle face is
   still dropped. The open item in PLAN.md §3 stays, trimmed to that.
4. **`boopctl sim` writes to a fixed `/tmp/boop-sim`**, which every
   worktree running it at the same time shares. Left as a breadcrumb.

## PLAN.md §3

Closed and removed: the pump's late timer, the e2e deploy expectation,
and the settle that spoiled an exact rebuild. The idle item lost its
part about the schedule keeping its own estimate.
