# The core's record and the screen, after the race hunt (A2, lane core)

2026-09-28, overnight run, lane `core` (branch `ovn2/core`, from main
7f5d10ff). Five race hunters fed adversarial hook orders into
`Boop --headless` with `boop-sim` on its USB link and reported 38
discrepancies. This lane reproduced them on its own build, fixed the
real ones with a test that fails before each fix, and reran the
hunters' own scripts afterwards. The lane's first two commits are the
`SubagentStop` fix (PLAN.md §3 A3), written up in
[core-subagentstop](../core-subagentstop/README.md).

In short: the hunters found that the screen never disagreed with the
`state` the core sent. What went wrong was the core's own model of the
agents, which the screen then showed faithfully, what the core wrote to
HISTORY, and the Mac's reckoning of moments the device had cut. Of the 38 reports, 34 are fixed
(some reports are the same bug seen by two or three hunters), 1 is
fixed in part, and 3 are left open, each with a reason.

## What changed, by cause

Each row lists the hunters' reports it covers, numbered in the order the
lane was given them (1–6 approval-vs-turn-end, 7–10 two-sessions, 11–22
esc-between-tools, 23–31 subagents, 32–38 reactions-vs-attention).

| # | Cause | Reports | Fix | Test that pins it |
| --- | --- | --- | --- | --- |
| 1 | A turn that finished while another session needed you still sent a cheer, which the device drops, and its `turn_end` still said "Boop cheered on its own.", so HISTORY told the brain about a cheer nobody saw | 1, 8, 14 | e07f5938: no cheer and no reaction line while something needs you, as a tap already does. A `Stop` that answers its own session's request still cheers | `CoreNeedsYouTests.testAFinishWhileSomethingNeedsYouDoesntCheer` |
| 2 | The device chirps when `attn`'s agent or project changes, so a different request with the same names (two worktrees of one repo, two subagents in one session) took over in silence, against BEHAVIORS.md §3.2. PROTOCOL.md §3 and BEHAVIORS.md disagreed | 2, 7, 15, 30, 38 | ea1746f9: the core numbers each request as it starts showing (and gives the next asker's prompt a new number when one of several askers in a session is answered); `attn.id` carries it, and the device chirps when it changes. A decision-log row says why | `testTheRequestShownHasItsOwnNumber`, `testASecondAskerAnsweredShowsAnotherRequest`; firmware `test_a_different_request_with_the_same_names_chirps` and `test_attention_shows_needs_you_and_chirps_once` |
| 3 | Two requests in the same millisecond were ordered by when their sessions were first seen, so `attn` flipped to the later one and chirped twice | 3 | ea1746f9: ordered by when they started showing, then by number | `testRequestsInTheSameMillisecondKeepTheirOrder` |
| 4 | Every tool-less `needs_you` within 5 s of a clear was dropped as the cleared request's late `Notification`, so an MCP dialog (`Elicitation`) right after an approval or an Esc never showed | 4, 11 | 08dfd63d, bc075e53: the adapter marks a `Notification` with its type; an `Elicitation` is a request of its own; only a late `Notification` of the type the cleared request sends is a copy | `testAnElicitationRightAfterAClearShows`, `AdapterTests.testANotificationIsMarkedAsANotice` |
| 5 | A permission `Notification` more than 5 s late, after the turn had ended, started a request nobody was making: amber for up to 10 minutes | 6, 22, 31 | 08dfd63d: it's also a late copy when no tool call has started since the clear, since a new request always follows a new call | `testALateNotificationAfterTheTurnEndedIsIgnored` |
| 6 | A Codex request answered after its 2 s grace but before the tick that shows it was promoted and cleared in one `handle()`: a `needs_you` event in HISTORY, no amber on screen | 5, 9 | 89b4d8f6: the event's own session is promoted only after the event, so an answer that beats the tick answers it unseen and unrecorded | `testACodexRequestAnsweredBeforeATickShowsItIsNeverRecorded` |
| 7 | A sibling subagent's calls from another folder moved the waiting session's project, so the strip flipped between names and chirped at every flip | 10 | fd3a155c: a session keeps its project while its request waits | `testAWaitingSessionKeepsItsProject` |
| 8 | The core cleared a request on its copy of the session but judged "wakes the brain" from the table, so approved-then-failing tests, the turn stopped after Esc on a prompt, and Codex's stopped turn never woke the brain | 12 | 9a5e88d7: the session is written back before the event applies | `testAnEventThatAnswersTheRequestWakesTheBrain` |
| 9 | After Esc on a subagent's prompt, Claude's idle notice answered only the main agent and restarted the safety net: amber for about 11 minutes, where BEHAVIORS.md §3.2 says a minute. ADAPTERS.md §4 and BEHAVIORS.md disagreed | 13, 25 | d7e2312c: the idle notice clears a request whoever asked. A decision-log row says why | `testClaudesIdleNoticeAnswersEveryRequest` |
| 10 | A tool result that landed just after an interrupt (Esc with parallel calls or subagents running, or Codex's aborted command after `Interrupt`) made the session work again: Boop chattered until the idle notice, which then recorded a second stopped turn; Codex stayed working for an hour | 17, 18, 26 | 091f949e: the result of a call that started before the turn ended or stopped counts, but doesn't start the turn again | `testALateResultDoesntRestartAStoppedTurn` |
| 11 | A `Notification` landing before its own `PermissionRequest` made the request "anyone"'s, and a sibling's tool call then cleared it | 19 | 08dfd63d: within 5 s, the request's own hook takes a lone `Notification`'s request over | `testANotificationBeforeItsRequestBecomesThatRequest` |
| 12 | An idle notice landing just after a new prompt showed the new turn idle and told the brain it stopped after 0 s | 20 | 98743d20: an idle notice less than 30 s after the turn started is ignored (it comes after a minute at the prompt, so it's from before). Codex's `Interrupt` still counts | `testAStaleIdleNoticeDoesntStopANewTurn` |
| 13 | A result of another call the asking agent made alongside the one that asks (a parallel `Grep`, or the main agent's `Agent` call) cleared the prompt while it was still up | 21, 23 | c837a1da: each asker's tool is remembered, and a result for another tool isn't the answer | `testAParallelCallsResultDoesntAnswerTheRequest` |
| 14 | A subagent's `Elicitation` was "anyone"'s, so a sibling's call hid it, and answering it hid a sibling's prompt | 27 | 08dfd63d: an `Elicitation` names its asker, as a `PermissionRequest` does | `testASubagentsElicitationIsItsOwn` |
| 15 | A turn-level hook sent from inside a subagent (`StopFailure` or `SessionStart` with its `agent_id`) cleared a sibling's request and ended the whole session's turn | 28 (in part) | 98743d20: such a hook is that subagent's alone, like its `SubagentStop` | `testASubagentsTurnLevelHooksAreItsOwn` |
| 16 | The Mac's moment schedule kept timing a cheer the device had cut (tap) or never played (needs you), so a reaction after it was timed on the cheer's short loop: the Mac gave up on it early, or let the next reaction cut its face | 32, 33 | 9375bd0f: a tap's wiggle and a `state` with `attn` end the cheer and any line in the schedule too | `testNeedsYouEndsWhatTheScheduleThoughtWasPlaying`, `testTheScheduleFollowsTapsCheersAndTicks` |
| 17 | A rule's cheer didn't pump the schedule, so a reaction waiting behind a face didn't play over it and was later dropped | 34 | 9375bd0f: every rule moment pumps | `testTheScheduleFollowsTapsCheersAndTicks` |
| 18 | A waiting reaction was judged only when its turn came: in progress for up to 30 s after it could no longer play, or, after a clock jump, ended by the harness's ceiling as "no word it finished" | 35, 36 | 9375bd0f: dropped once it has waited 5 s whatever holds the turn, the pump is asked again then, and every tick asks | `testAWaitingMomentIsDroppedAtFiveSecondsWhateverPlays`, `testTheScheduleFollowsTapsCheersAndTicks` |
| 19 | After the Mac app restarted, its first reaction reused id 1 while the device still waited on the last launch's id 1, and was reported cut though it played out | 37 | efb97b14: the device forgets the old launch's moment, unreported, when its id comes again | firmware `test_a_new_launchs_moment_is_its_own` |

Two more changes came out of the work:

- f697f1ef: the device's `ended` for the moment holding the turn frees
  the turn, since the device ends a face up to a loop sooner than the
  Mac reckons. This was half of a PLAN.md §3 item (the idle look's 9 s
  face), which now says so.
- ca57c1f1: `CoreFuzzTests` plays 20,000 random hooks from three
  sessions into the core, with ticks and clock jumps, and checks after
  each call that every `needs_you` event is for a session shown waiting,
  that nothing cheers or wakes the brain while something needs you, that
  the state sent is the snapshot, and that one request's number never
  changes its agent or project. Reverting the cheer fix, or the Codex
  promotion fix, on their own makes it fail (at call 22 and at call
  5,374).

## Left open

- **16: a new prompt soon after Esc between tools never records the
  interrupted turn as stopped.** The core could close an open turn as
  `stopped` when a new `turn_start` arrives, but if Claude sends
  `UserPromptSubmit` for a message queued mid-turn, that would record a
  stop that didn't happen. It needs a recorded session that queues a
  message first.
- **24: a background subagent working past the main `Stop` keeps the
  session working for up to an hour.** Already written up by the
  `SubagentStop` work as a proposal
  ([core-subagentstop](../core-subagentstop/README.md)); it needs a
  recorded session with a background subagent.
- **28, in part: the main agent's `Stop` over a background subagent's
  prompt clears it.** Whether a background subagent can prompt after
  the main turn is over isn't recorded. Hooks from inside a subagent are
  fixed (row 15).
- **29: whether a turn with parallel check results cheers depends on
  which result lands last.** A design question rather than a race:
  BEHAVIORS.md §3.1's "last test, build or deploy command" has no single
  meaning for parallel subagents. One answer would be to fail a turn
  that leaves any check topic failing, which `topics` already tracks,
  but that also changes sequential turns (tests fail, then a build
  passes), so it's the owner's call.

Decisions made without the owner, each recorded in the spec it changes:

1. **Codex's grace stays tick-based.** A request answered after its 2 s
   grace but before the next 1 s tick is now answered unseen and not
   recorded, rather than flashed amber for a few milliseconds. So the
   grace is 2–3 s by the tick's phase; ADAPTERS.md §4 says so. An exact
   timer at the grace's end would make it 2 s (proposal below).
2. **A `Notification` is a late copy if it's the cleared request's type
   and comes within 5 s, or before any new tool call.** The 5 s window
   stays as a guard for a quick approval followed by a quick next call.
3. **An idle notice under 30 s into a turn is stale.** Claude sends it
   after a minute at its prompt, so a real one can't come sooner. 30 s
   leaves room either way.
4. **A parallel call's result is told apart by tool name.** Claude's
   `PermissionRequest` has no `tool_use_id`. Two parallel calls of the
   same tool still answer each other, as before.
5. **`attn.id` falls back to agent and project** when it's missing, so an
   older Mac and the new firmware, or the new Mac and older firmware,
   still work together (the old firmware simply ignores the id). The
   number also covers a worry two hunters raised from reading the code:
   Bluetooth's outbox replaces a waiting `state`, so a `state` without
   `attn` could be merged away between two requests with the same names,
   and the device would miss the chirp. The new request's number still
   differs.

## How it was checked

All on this branch at cb0115b4, with a temporary HOME and state
directories under `/tmp`. No Bluetooth, board, webcam, Jev, `~/.claude`
or `~/.codex`. The firmware changes (`attn.id`, a reused moment id) ran
in the native tests and the simulator only: the board wasn't flashed.

| Check | Result |
| --- | --- |
| `make build` | OK |
| `make -C internal test` | 233 of 233 passed (212 before this lane's A2 work; 21 new, several changed) |
| `make -C internal fw-test` | 113 of 113 passed (111 before; 2 new, 1 extended) |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 new or changed pictures |
| `internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests` | 27 OK |
| `python3 -m unittest discover -s internal/tools/webcam/tests` | 3 OK |
| `internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check` | 337 frames of 30 scenes match, tree unchanged |
| `CoreFuzzTests` (inside `make -C internal test`) | 20,000 calls, 1,835 requests shown, 770 cheers, no invariant broken |
| Each new test fails before its fix | Seen for every row above: by running the test before writing the fix, or, where another test failed first, by reverting that fix alone and running only the new test (`/tmp/oc/mut.py`) |

### The hunters' own scripts, rerun on this build

The hunters' scratch rigs were copied to `/tmp/oc/hunt/` and pointed at
this worktree's `Boop` and `boop-sim` (firmware built from this branch),
with their state directories renamed so they couldn't collide with
other lanes'. Each runs `Boop --headless --brain scripted --debug` with
its USB link on a stand-in bridge to `boop-sim`, sends real `boop-hook`
payloads, and compares the core's `status`, the `state` lines sent and
the simulator's `dbg.state`. Outputs are in [hunters-rerun.txt](hunters-rerun.txt).

| Rig | What ran | Result |
| --- | --- | --- |
| approval-vs-turn-end | `repro.py all`, `probe_late.py`, `probe_codex_tick.py`, `fuzz.py 7 30` | cheer-claim: the finish under another session's request sends no cheer and claims none, and the next HISTORY doesn't say it cheered. sameproj-chirp: 2 chirps, `attn.id` 1 then 2. samems-flip: 5 of 5 runs keep landing shown with "+1" and one chirp. elicit: needs you shows, with a chirp. codex-tick: a `Stop` at +2010 to +2200 ms records no `needs_you` and sends no `attn`; from +2300 ms each records one and sends one. probe_late: the late `Notification` leaves the session idle. fuzz: 30 of 30 runs with no core/screen mismatch |
| two-sessions | the 5 `repro_*.py`; `fuzz.py` seeds 15, 21, 22, 23 | All 5 PASS. The fuzz saw no unseen `needs_you` in any seed. Its model disagreed in seeds 21 and 22 (4 and 12 checkpoints), each time right after it sent Claude's idle notice 1 to 5 s after an Esc and 13 s into the turn, which real Claude doesn't do (it waits a minute at its prompt) and which the core now takes as stale (row 12) |
| esc-between-tools | 18 scenarios: s03d, s04, s05, s07b, s08, s08c, s09, s09b, s09c, s10c, s12, s13, s14, s21, s23, s24, s25, s31 | Every check passes except s08c's two "still amber" checks, which the hunter wrote to show the old behaviour (amber kept through the idle notice); the amber now clears at the notice, as BEHAVIORS.md §3.2 says |
| subagents | s4, s5, s6a, s7, s7b, s9, s9b, s11, s11c, s11d, s12, s16, s17, c1, c2; sweeps P1n, P3, P4 | Fixed: s4, s5, s11, s11c, s11d, s12, s16, s17; c1 and c2 chirp twice; s6a clears at the idle notice; s9 and s9b record one stopped turn and stay idle; P1n 0 of 30 orders unexpected, P3 0 of 24 (18 before). Still as reported: s7 and s7b (a background subagent, report 24) and P4 (report 29). s6a's amber in the minute between Esc and the idle notice is the documented minute |
| reactions-vs-attention | s1, s2 a, s2 b, s3, s4 same, s5, s6, s7, s8; `fuzz.py 3 6 3` | s1, s2a, s2b: the reaction settles `done` from the device's `ended`, not "the device never said it ended". s3: the second reaction no longer cuts the first's face; it's dropped at 5 s while the first holds the idle face (the PLAN.md §3 9 s item). s5: the waiting reaction plays over the cheer and settles `done`. s8: dropped 5.3 s after its action (35.9 s before). s7: "waited too long", not the harness's ceiling. s6: the new launch's reaction settles `done`. s4: 2 chirps. fuzz: 0 findings in 6 random cases |

The esc-between-tools rig's "invariants" line flags every reaction that
settled as failed, including the expected "cut short: something needed
you" when a request comes in, so it reads BAD in almost every scenario
before and after this work; it isn't a discrepancy.

## Proposals

- **Record a few Claude sessions** with hooks pointed at a recorder
  (fixtures' `VERSIONS.md`): a denied subagent, a background subagent,
  parallel calls with one needing permission, Esc on a subagent's
  prompt, and a message queued mid-turn. Most of the "plausible" rows
  above rest on the hook reference rather than a recording.
- **Find a session's project from its git root, not its folder.**
  `Adapter.place` names the project after the `cwd` itself, so when
  Claude `cd`s into a subfolder of a repo (`landing/web`), the session's
  project becomes `web`. Walking up to the nearest `.git` (cached per
  folder, as now) would keep it `landing`. Found while fixing row 7; not
  changed, since it renames projects. Now a PLAN.md §3 item, with the
  three unrecorded hook orders above.
- **Promote a Codex request on time.** Runtime could ask the core when
  the next grace ends and tick then, making the grace 2 s rather than
  2–3 s.
- **PLAN.md §2 step 6** says the strip "moves to the other, chirping if
  it's another agent or project"; it now chirps for any other request.
  Left for the final stage, which owns PLAN.md outside §3.
