# The second race hunt, fixed where it could be (lane hunt2)

2026-09-28, overnight run, round 2, lane `hunt2` (branch `ovn3/hunt2`,
from main b5ff8e9c). Round 2's race hunters filed 22 reports, each
reproduced by at least one of two verifiers. This lane reproduced them
on its own build, fixed the real ones with a test that fails before
each fix, and reran the hunters' scripts on the result.

In short: 17 of the 22 are fixed, one was a doc slip (fixed), and four
are left open because they need a recording or a decision. Most of the
fixes are in the core's idea of a turn. It lost track of a turn at the
edges: after the safety net, after `SessionEnd`, across a Mac asleep, or
for a turn it only joined halfway. The rest are in the brain's side
(the deadline's timer, the dashboard, HISTORY) and in the moment
schedule, which freed the line on two guesses about the device.

## Every report

Numbered in the order the lane was given them. "Pinned by" names the
test that fails without the fix; each was seen failing before its fix
went in (the shim runner stops at the first failure, so each was run
alone).

| # | Report (votes) | Verdict | Outcome | Pinned by |
| --- | --- | --- | --- | --- |
| 1 | After the safety net an interrupt is dropped, and the late result restarts the turn for an hour (2) | Real | Fixed, `9fb74a32`: a stop ends any open turn, even once the safety net made the session idle, so the late result is late | `CoreAgentWorkTests.testAStopAfterTheSafetyNetEndsTheOpenTurn` |
| 2 | A Mac sleep mid-turn counts as turn time: "done after 8 h" (2) | Real | Fixed, `9ff7d6c5`: the runtime tells the core how long the Mac slept (the steady clock less one that stops in sleep), and the core takes it off every open turn and the status line's "for". Timers still count sleep | `CoreAgentWorkTests.testTheMacAsleepIsntTurnTime`, `RuntimeTests.testTheCoreHearsHowLongTheMacSlept` |
| 3 | A turn from a session forgotten after 24 h reads "turn 0 … after 0 s" and cheers (2) | Real | Fixed, `db7ac46f` (decision 1) | `testAFinishWithNoTurnOpenIsNothing`, `testATurnBoopJoinedPartwayEndsWithoutAnEvent` |
| 4 | ARCHITECTURE.md §4 says a new day's snapshot goes under "the day before" (2) | Doc slip; the code is right | Fixed, `794d8fd4`: it goes under the last day with activity, as §4.4's table says | (wording) |
| 5 | After a 1 s link blip the next reaction cuts one still playing (2) | Real | Fixed, `542175b6`: a link drop no longer stops the schedule, so the reaction sent before it holds the line until its `ended` comes over the link again, or the app gives up (decision 3) | `RuntimeTests.testALinkBlipKeepsTheLineForTheReactionPlaying` |
| 6 | A tap the device handled before a reaction arrived frees that reaction's line (2) | Real | Fixed, `542175b6`: a tap leaves a reaction sent with an id holding the line; the device sends `ended` at once for one its tap cut | `RuntimeTests.testATapLeavesTheLineToTheDevicesEnded`, and `testTheDeviceSaysWhenTheLineIsFree`, `testWhatFreesTheLineSendsTheNextAtOnce` changed to match |
| 7 | A relaunched app numbers its first request 1 again, so it doesn't chirp (2) | Real | Fixed, `98b01ef0`: each launch starts its request numbers somewhere random, as moment ids do, and wraps to 1 in 32 bits. `boopdev replay` and the tests still start at 1, so PROTOCOL.md's example stays real | `RuntimeTests.testRequestNumbersDifferEachLaunch` |
| 8 | A command Codex's reviewer approves still shows "needs you" if it runs past the 2 s grace (2) | Real in the fixtures' hook order | Open. ADAPTERS.md §4 no longer says such a request never shows (`794d8fd4`), and PLAN.md §3 has it. Whether Codex sends anything at the reviewer's approval needs a real Codex session | — |
| 9 | Esc after the safety net records no stopped turn (2) | Real, the same cause as 1 | Fixed, `9fb74a32`. `boopdev replay` of the hunter's f1 and f1c now records "stopped after 10 min" and "11 min". A `Stop` in the same place still cheers, as it should: the turn was open, and it finished | as 1 |
| 10 | A late result after `SessionEnd` brings the session back working for an hour (1) | Real | Fixed, `bfc0ce95` (decision 2). Replay f4 stays asleep | `CoreAgentWorkTests.testALateHookAfterSessionEndDoesntBringItBack` |
| 11 | A `Stop` with no turn open cheers and wakes the brain (1) | Real | Fixed, `db7ac46f`: a finish with no open turn is nothing. Replay f6 gives one `turn_end` | `testAFinishWithNoTurnOpenIsNothing` |
| 12 | A Codex `PermissionRequest` landing just after its own `Interrupt` shows amber for 10 minutes (1) | Reproduces (replay f7) | Open, below | — |
| 13 | A mood the dashboard sets while a pass runs is undone by that pass (2) | Real | Fixed, `4f055537` (decision 4) | `HarnessTests.testAnActionTheDashboardChangedDuringAPassSitsItOut` |
| 14 | The 1.25 s deadline fires at 1.25–1.33 s, and a dropped pass's latency is the timer's (2) | Real | Fixed, `93da2670` and `d011d808` (decision 5): the timer fires within 5 ms, a request the deadline passed goes on to its end and the log says when it answered, Jev doesn't retry past the deadline, and `boopctl day` times only passes answered in time. PLAN.md §3 has a new item saying the night's "about 1.3 s" was the timer | `HarnessTests.testTheDeadlineComesOnTime` (four at once all fired at 1290 ms before), `testALateAnswerIsStillTimed`, `testJevsAnswerAndRetry` (extended), `test_day.py` |
| 15 | A pass for an event that waited when "needs you" started still asks the brain (1) | Real, against BEHAVIORS.md §1's "no event wakes the brain" | Fixed, `b6c01666` (decision 6). The part about a pass already running is left open, below | `HarnessTests.testAWaitingPassDoesntStartWhileSomethingNeedsYou`, `RuntimeTests.testNoWaitingPassStartsWhileSomethingNeedsYou` |
| 16 | A face held 2–4 loops blocks every other reaction for 16–36 s (2) | Real, by design today | Open: a behaviour decision, now a PLAN.md §3 item next to the 9 s one | — |
| 17 | With chatter, a face still playing drops out of HISTORY after 40 newer events (1) | Real | Fixed, `5ccdb082`: an event whose started action is in progress stays in HISTORY past the newest 40 | `HarnessTests.testAReactionInProgressStaysInHistory` |
| 18 | A permission `Notification` after `SessionEnd` brings back a ghost that needs you for 10 minutes (2) | Real | Fixed, `bfc0ce95` | `testALateHookAfterSessionEndDoesntBringItBack` |
| 19 | A tool result after `SessionEnd` brings the session back working for an hour (2) | Real | Fixed, `bfc0ce95` | the same |
| 20 | A late `SubagentStop`, `Stop`, interrupt or idle notice after `SessionEnd` leaves an idle ghost for 24 h, and a late `Stop` cheers "turn 0" (1) | Real | Fixed, `bfc0ce95` and `db7ac46f` | the same, and `testAFinishWithNoTurnOpenIsNothing` |
| 21 | A `Stop` another hook blocks cheers at every `Stop`, with counts carried over (2) | Real | In part, `db7ac46f`: the third `Stop` (no turn open) is nothing, and the continuation counts its own tools ("1 tool", not "2"). It still cheers twice and says "turn 1" twice: open, below | `testATurnACallOpensCountsItsOwnTools` |
| 22 | A session first seen mid-turn reports "turn 0" timed from the restart, but its interrupt is dropped (2) | Real | Fixed, `db7ac46f`: done, failed and stopped are alike now; none tells the brain (decision 1) | `testATurnBoopJoinedPartwayEndsWithoutAnEvent` |

## Decisions made without the owner

Each is written into the spec it changes, and the four that replace
something have a row in ARCHITECTURE.md §11's decision log.

1. **A turn Boop didn't see start tells the brain nothing** (EVENTS.md
   §7, BEHAVIORS.md §3.1, ARCHITECTURE.md §8). After a relaunch, or a
   day's forgetting, Boop can't know a running turn's length or tools,
   so its end makes no event, whatever the outcome, as a stop already
   didn't. A finish still cheers, since the screen showed it working.
   The other choice, no cheer either, would make a relaunch mid-turn
   silent. A finish with no turn open at all (a second `Stop`, one
   after an interrupt, one from a session Boop only now sees) is
   nothing: no cheer and no event.
2. **An ended session is remembered for a day** (ADAPTERS.md §4). Its
   hooks are ignored until a `session_start` or a prompt from the main
   agent brings it back, since a resume sends `SessionStart`. The mark
   lasts `forgetMs`, as long as a silent session is kept.
3. **The line waits for the device, not for guesses** (ARCHITECTURE.md
   §3.2, §8). HISTORY still says a reaction playing when the link
   dropped didn't happen, but the line stays held for it. So a reaction
   queued while the link is down waits for that line, and settles
   "waited too long" or, when its turn comes, "no device connected",
   instead of failing at once.
4. **What the dashboard changed sits out the running pass** (HARNESS.md
   §2, DECISIONS.md §4). The harness can't read answers, so it doesn't
   compare Jev's mood with the one the state showed; it skips the pass's
   answers for any action the dashboard made act while the pass ran. A
   different mood from Jev in that pass is dropped too: the dashboard's
   is newer. The log says `harness: mood sat out the pass: …`.
5. **A late Jev request is finished, not cancelled** (HARNESS.md §7), so
   `boop.log` gets `harness: jev:jev-latest answered after N ms, too late
   for the <kind> pass`. It stops at the request's own 2 s timeout, and
   `JevBrain` no longer retries when the retry would land past the
   deadline, so no request goes out that nobody waits for.
6. **A waiting pass is dropped under "needs you"** (HARNESS.md §2 and
   §7, EVENTS.md §6), recorded as a pass dropped with
   `something needs you`, 0 ms and no state, and the brain isn't asked.
   `boopctl day` counts it with the dropped passes.
7. **Sleep under a second is ignored** (`Runtime.noteSleep`), since the
   two clocks can differ by read jitter. Headless mode's
   `{"dev":"advance","ms":N,"asleep":true}` moves the clock as a sleep,
   so the hunters' 8 h jump can play a lid closed overnight
   (HARNESS.md §9, VERIFICATION.md §2).
8. **A turn a call opens counts its own tools and topics** (EVENTS.md
   §4.1), from that call, keeping the thread's turn number.

## Left open

- **8, Codex's reviewer.** Needs a recorded Codex session with the
  reviewer on. If Codex sends nothing at the approval, the choices are a
  longer grace (every real prompt shows later), or living with amber
  during reviewed long commands, as for Claude's approved ones.
- **12, a Codex request just after its own `Interrupt`.** The core could
  treat a Codex request that comes with no turn open, for a call started
  before the stop, as late, as it does results. But a request has no
  `tool_use_id`, and hiding a real request is worse than 10 minutes of
  amber, which a new prompt or Esc clears. It needs Esc within a few
  milliseconds of the request, so it's left.
- **15's other half: a pass already running when "needs you" starts
  still changes the mood when it lands.** In the hunter's s07 the
  turn's pass landed 0.55 s into the amber and changed the mood
  happy → determined, which redraws the needs-you face. Having the mood
  action sit out while something needs you would stop it; it's a
  behaviour choice.
- **16, long faces block the next reaction.** PLAN.md §3. The hunter's
  proposal (the next brain reaction ends a held face once its mumble has
  played, which the device already counts as done) fits the rule that a
  reaction never cuts another's line; it changes BEHAVIORS.md §3's "no
  reaction's face is playing".
- **21, a blocked `Stop`.** PLAN.md §3. Keeping `stop_hook_active`
  through `boop-hook` and ending such a turn with no second cheer, its
  length from the prompt, would make one prompt one turn. It touches
  HookWire, the adapter and the core, and the spec first.
- **PLAN.md §2 check 8** says a request Codex's reviewer handles never
  lights up. With report 8, that holds only for a command that finishes
  within 2 s. Left for the final stage, which owns §2.
- **The morning report's decision 2** (raise Jev's deadline to 1.5 s)
  rests on the timer's 1.28–1.33 s. After this lane, a day's `boop.log`
  shows Jev's real time for each pass it was late for; that's the number
  to decide on.

## How it was checked

All on this branch, with temporary `HOME`s and state directories under
`/tmp`. No Bluetooth, board, webcam or Jev.

| Check | Result |
| --- | --- |
| `make build` | OK |
| `make -C internal test` | 258 of 258 (242 before; 16 new, 3 changed) |
| `make -C internal fw-test` | 114 of 114 |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 new or changed pictures |
| boopctl, webcam, workday tests (run directly) | 53, 3 and 9 OK |
| `cmp CLAUDE.md AGENTS.md`, `diff -r plan/steering app/Boop/Resources/steering` | Both silent |
| `CoreFuzzTests` | 20,000 calls, 1,843 requests shown, 459 cheers (757 before: the fuzz sends many `Stop`s with no turn open, which no longer cheer), no invariant broken |
| Scripted working day (`workday.py run --brain scripted`) | 193 turns, 403 passes, 0 dropped, 403 moments played, as on main ([final](../final/workday-scripted.md)) |

### The hunters' scripts, rerun on this build

Copies of the rigs in `/tmp/h2/`, pointed at this worktree's `Boop` and
the b5ff8e9c `boop-sim`, with their state directories renamed. For the
brain-passes rig, its "sleepy" brain was rebuilt against this branch's
`BoopKit` (`/tmp/h2/pkg`). The quiet-and-clock rig's 8 h jumps now send
`"asleep":true`. Outputs are in [reruns.txt](reruns.txt).

| Rig | What ran | Result |
| --- | --- | --- |
| quiet-and-clock | q01, q01b–e, q02, q02b–d, q03, q04, q04b–d, q07b | All 31 checks pass. q01 and q01c record "stopped after 11 min", stay idle after the late result, and send 0 chatter mumbles (13 before). q02c records its stop. q03 reads "done after 2 min". No "turn 0" line anywhere; q04 cheers once (the turn Boop joined), q04c not at all |
| codex (replay) | f1, f1c, f2, f4, f6, f7 | f1 and f1c record the stopped turn, f4 stays asleep, f6 has one `turn_end`. f2 (report 8) and f7 (report 12) still show amber, as left open |
| sessions-lifecycle | `repro_ghost.sh` notice, result, substop, stop; `scen_e.py`; `scen_f.py` | Every ghost case stays asleep after the late hook, with no cheer. scen_e makes no turn events for turns Boop joined. scen_f: two `turn_end`s, not three, the second with 1 tool |
| link | l1, l13 30 10, l13 30 60, l14 a | l1: the first reaction plays out (`done` on the device); the second waits for its 14 s face and is dropped at 5 s (report 16), instead of cutting it. l13: the reaction the tap came before plays out `done`; the next waits instead of cutting it; the control still cuts by the tap. l14: 2 chirps, with random `attn.id`s |
| brain-passes | s02, s07, s09, s13, s15 | s02, s09: `mood sat out the pass`, the dashboard's mood stays. s07: the waiting pass isn't asked under the amber (the running one's mood change is the open half of 15). s13: drops at 1258 and 1259 ms (1318 and 1332 before), and `sleepy answered after 3009 ms, too late for the tool_use pass`. s15: passes 93–97 show the proud face `(in progress)`; the rig's own rebuild of HISTORY follows the old rule, so it flags those passes as differing |

## Proposals

- Let `internal/app/tools/test.py` run one test, or a pattern. The
  generated runner stops at the first failure, so seeing each new test
  fail before its fix meant regenerating the runner by hand (a
  breadcrumb is filed).
- Record the Codex session PLAN.md §3 asks for with the automatic
  reviewer on: it settles reports 8 and 12, and the old "No real Codex
  session" item.
