# An independent check of the core lane (lane core-check)

2026-09-28, overnight run. The `core` lane (branch `ovn2/core`) made 19
commits on main 7f5d10ff: the `SubagentStop` fix (PLAN.md §3 A3) and
fixes for 34 of the race hunters' 38 reports
([core-subagentstop](../core-subagentstop/README.md),
[core](../core/README.md)). This lane read every change against the
specs, tried to break the new rules on purpose, and fixed what it found,
in four more commits on the same branch.

## In short

The changes hold up. A subagent's end never clears the main agent's
request or a sibling's, never makes an idle session look busy, and
doesn't put off the 10-minute safety net. Every new rule but one had a
test that fails when the rule is broken. The one gap, and three smaller
problems, are fixed:

| Commit | What was wrong | Fix and the test that pins it |
| --- | --- | --- |
| adf8d711 | Letting `SubagentStop` also clear a request that came as a `Notification` alone ("anyone") left every test passing: the only test of it had the ending subagent asking as well | `testASubagentsEndLeavesOtherAskersWaiting` now sends the end of a subagent that never asked, over the main agent's request and over a lone `Notification`'s. `CoreFuzzTests` also checks every subagent end, and every turn-level hook from inside a subagent: it removes only that subagent from the askers, leaves the session's clock and turn start alone, and makes the session work again only while its turn goes on. VERIFICATION.md §5 lists the check |
| 4f8b77e4 | ADAPTERS.md §3 said `PermissionRequest` carries a `tool_use_id`, for both agents, and the new denied-subagent fixture gave it one. Neither agent sends one, which is why the core matches a request to its answer by tool name | The tables and the fixture drop it, and ADAPTERS.md §4 says a parallel call of the same tool still answers a request. The fixture's replay is unchanged |
| 7aad538e | An MCP dialog (`Elicitation`) asks for no tool, so any result from the same agent answered it: a read-only call running alongside the MCP tool, or the main agent's own `Agent` call, cleared the amber while the dialog was still up (2 s of a 13 s dialog in a replay). The lane's parallel-call fix covered permission requests only | No call's result answers an `Elicitation` now; its `ElicitationResult` does, or the agent's next call, or anything turn-level. `testAParallelCallsResultDoesntAnswerTheRequest` gains a case for each answer |
| c3254691 | The guard against a stale idle notice (under 30 s after a turn started) also caught a real one: a background subagent's call after the main agent's `Stop` starts a turn with no prompt, and a notice under 30 s after that call was ignored, leaving the session working for up to an hour | The core remembers your last prompt and measures from it, which is what the guard's reasoning needs. ADAPTERS.md §4 says so; `testAStaleIdleNoticeDoesntStopANewTurn` gains the background case |

## How it was checked

**Breaking each rule on purpose.** `mutations.txt` has every run. Each
mutation changes one line of the core, adapter or installer, rebuilds,
and runs the whole Swift suite (which stops at the first failure).

- 24 mutations of the lane's rules at 0aca9fbe: 23 caught, each by the
  test the lane names for it. The one that survived is the "anyone" gap
  above.
- After adf8d711, with only `CoreFuzzTests` in the runner, five
  mutations of the subagent branch (answering "anyone", clearing every
  asker, always working again, moving the session's clock, treating a
  subagent's `StopFailure` as the session's) each fail the fuzz test on
  its own.
- The three later fixes: undoing each fails its new test.

**Replaying hostile hook orders.** `replay-probes.txt` is
`boopdev replay --states` over the eight sessions `probes1.py` and
`probes2.py` write (one hook a second unless a wait says otherwise). To
rerun them from the repo root after `make build`:
`PYTHONPATH=plan/evidence/2026-09-28-tonight/core-check python3 plan/evidence/2026-09-28-tonight/core-check/probes1.py`
(and `probes2.py`).

| Probe | What happens | Result |
| --- | --- | --- |
| t1 | The main agent asks; a subagent works and ends; the main agent's `Agent` call returns | Amber until the main agent's next call (+30 s), through the subagent's end and the parallel result |
| t2 | A `Notification` alone asks; 8 s later a subagent that never asked ends | Amber until the `Stop` |
| t3 | A subagent ends 30 s after the `Stop`, and another an hour later | Idle throughout; no state sent |
| t5 | The main agent asks; a subagent's `StopFailure` arrives | Amber until the asking call's result |
| t6 | Two subagents ask; the first ends | Still amber with a new `attn.id` (a chirp); the second's result clears it |
| h1 | An approval, then a subagent's request 1 s later | Amber again at once, new id |
| h2 | The same, with its `Notification` before its `PermissionRequest` | The `Notification` is taken as the cleared request's copy, and the hook a second later shows the new one |
| h4 | An MCP dialog with a parallel `Read` | Before 7aad538e cleared at +6 s by the `Read`; after, amber until its `ElicitationResult` at +17 s |

**Checks**, in the lane worktree:

| Check | Result |
| --- | --- |
| `make build` | OK, at c3254691 |
| `make -C internal test` | 233 of 233 passed at c3254691 (test count unchanged: the new cases extend existing tests). `CoreFuzzTests`: 20,000 calls, 1,843 requests shown, 757 cheers (1,835 and 770 before 7aad538e, which lets fewer random results clear a dialog) |
| `make -C internal fw-test` | 113 of 113, at 7aad538e (no firmware change since) |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 new or changed pictures, at 7aad538e |
| `cmp CLAUDE.md AGENTS.md` | Silent |
| `git log HEAD..main` | Empty: main is still 7f5d10ff |

No board, webcam, Bluetooth, Jev, `~/.claude` or `~/.codex` was used.

## Read and left alone

- **The idle notice now clears a subagent's request too** (d7e2312c). It
  could hide a real prompt only if Claude sent `idle_prompt` while a
  subagent's prompt is up. A foreground subagent's prompt keeps the main
  turn going, so it can't; a background subagent's is unrecorded, and is
  already open in PLAN.md §3.
- **Two parallel calls of the same tool still answer each other's
  request.** Neither agent's `PermissionRequest` has a `tool_use_id`, so
  nothing better is possible without a recording. Now said in
  ADAPTERS.md §4.
- **A tap's wiggle can lose its 0.7 s in the moment schedule** when the
  device's `ended` for the reaction the tap cut arrives just after the
  tap (`MomentSchedule.ended` lowers the busy time to now), so working
  chatter may start during the wiggle. Main behaved the same way before
  the lane (it didn't track the wiggle at all), and a mumble over a
  wiggle doesn't cut it.
- **Firmware** (`attn.id` chirp, forgetting a reused moment id): read
  against PROTOCOL.md §3–4; the native tests and simulator pass. The
  board wasn't flashed.

## Proposals

- **Keep a rule animation's end in the schedule** (`animUntil`, for the
  cheer or a wiggle), so the device's `ended` frees the turn without
  shortening a wiggle that's playing.
- **A subagent's call racing an Esc** starts the turn again: the
  late-result rule covers results only, so a `PreToolUse` that lands
  after the interrupt makes the session work, and the idle notice a
  minute later records a second stopped turn. Treating any call from a
  subagent whose turn was just interrupted as late would fix it, but
  that needs a recording of what Claude sends after Esc with subagents
  running (the core lane's recording proposal).
- **PLAN.md §2 step 6** still says the strip chirps "if it's another
  agent or project"; it now chirps for any other request. The core lane
  left this for the final stage, as does this one.
