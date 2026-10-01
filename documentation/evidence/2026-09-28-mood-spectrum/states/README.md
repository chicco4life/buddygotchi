# The 22 states on the Mac (P4, lane states)

2026-09-28, overnight run, lane `states` (branch `ms/states`, from
`a6244be7`). Phase P4 of [the plan](../PLAN.md): the core's rules for the
activity states and the one-shots, the hooks they need, and the specs.
The device side (P5), the brain's finish (`task_complete`, `reply_ready`)
and the art are other lanes'.

## What changed

**Hooks** ([ADAPTERS.md](../../../ADAPTERS.md) §2–5). `boop-hook` keeps
`SessionStart`'s `source` and every hook's `permission_mode` (as `mode`).
A shell command that only looks at files (`rg`, `grep`, `cat`, `sed -n`,
`find`, `ls`, `head`, `tail`, `wc`, `nl`, `sort`, `uniq`, `cut`, with
`cd` or `echo` alongside and no `>` into a file) gets the topic
`inspect`, after any check topic. Claude's `SubagentStart` is installed
(14 hooks; an older install is repaired at launch) and maps to a
`subagent` start with its `agent_id`.

**What the agents are doing** ([BEHAVIORS.md](../../../BEHAVIORS.md) §2,
`app/BoopKit/Core/Activity.swift`). The core keeps each session's running
calls (by `tool_use_id`, else the last call of that tool by the same
agent), the helpers it saw start and Claude's plan mode. The `state`
line gains `act` while `base` is `working` and nothing needs you:

| `act` | Evidence |
| --- | --- |
| testing | a running call with topic `tests` |
| delegating | the main agent's `Task`/`Agent` call, or a helper seen starting that hasn't stopped |
| terminal | `Bash`, `shell`, `exec_command`, `local_shell` |
| searching | `WebSearch`, `WebFetch` |
| analyzing | `Read`, `Grep`, `Glob`, `LS`, or topic `inspect` |
| tool_use | any other call |
| waiting | a call with nothing heard from its session for 20 s, or Codex's request grace |
| planning | plan mode, or `TodoWrite`, `ExitPlanMode`, `update_plan` running |

Priority in that order. A higher one shows at once; a lower one, or none,
only once 1.5 s (`Core.actHoldMs`) have passed since the one showing was
last in force and since it started showing. The working session heard
from last picks, among those doing something. The variant is the
visual's, and is picked again when a new mood has fewer of it.

**The rules' one-shots** ([BEHAVIORS.md](../../../BEHAVIORS.md) §3.1).
The core returns a new effect, `moment`, sent right after the `state`,
with no `id`: `starting` (`ctx` `session` for startup/clear,
`continuation` for resume/compact, `new_task` for a prompt), `stopped`
(an interrupt that ends an open turn), `error` (a failed call of class
`exit_code` or `timeout`, at most every 30 s, decision D7) and
`helper_return` (a helper seen starting ends while its turn goes on, or,
with hooks from before `SubagentStart`, the main agent's `Task`/`Agent`
call returns). Each in Boop's mood, a variation at random, never the
last. None while needs you or `listening` holds the screen; the runtime
drops one while a brain moment's line plays
(`MomentSchedule.rulePlays`), and a brain moment plays over one without
waiting, as over the wiggle.

## Decisions made without the owner

1. **Waiting replaces the call's own look.** The plan ranks waiting below
   the tool states, yet its evidence is a tool running: taken literally
   it could never show. So a call reads as waiting once its session has
   been quiet 20 s, and during Codex's grace; a helper at work never
   does (it isn't the machine). A test run longer than about 20 s shows
   testing, then waiting.
2. **The hold counts from the last evidence.** "1.5 s after it starts"
   alone let a burst of 50 ms reads flicker between analyzing and working
   every couple of seconds. The session's activity holds 1.5 s after its
   last call ends, and the one shown holds 1.5 s after it started
   showing, so switching between sessions can't flicker either. The 1 s
   tick ends a hold, so a lower one can come up to a second later.
3. **Rule one-shots never wait, and never cut a brain line.** Waiting
   behind a 4–9 s one-shot would drop most reactions to a prompt (a
   brain moment waits 5 s at most). This keeps 2026-09-27's "a brain
   reaction waits only for a line". A rule one-shot that finds a brain
   line playing is dropped, not queued.
4. **One-shots are out of the transcript.** Like the look, they show
   what the agents did; the view already has the events behind them, and
   recording them would change what Jev reads in NOW (EVENTS.md §1).
5. **Calls end with more than their result.** A turn starting or ending
   ends its calls and helpers; a subagent's end ends its calls; a request
   answered by anything but its call's result drops the asker's latest
   call of that tool (you denied it, which Claude doesn't report).
   Without these, a lost result or a denied command would show as a
   terminal for the rest of the turn.
6. **Codex's `SessionStart` matcher stays `startup|resume|clear`.**
   Adding `compact` would mark every Codex install outdated for a source
   no recorded payload shows. A Codex session never starts as compacted.

## Checks that ran

| Check | Result |
| --- | --- |
| `make build` | ok |
| `make -C internal test` | 307 of 307 passed (278 before; 29 new, several changed) |
| Commit 1 alone (hooks), built and tested in a scratch worktree | 283 of 283 passed |
| `boopdev replay` of every synthetic fixture, `--states` | as pinned in `ReplayTests` (below) |
| Headless app, fixtures through the real `boop-hook` | every `act` and one-shot in the device lines (below) |
| `workday.py run --brain scripted` (seed 1) | ran: 429 passes, none dropped (below) |
| Mutation checks (below) | each of 12 caught by at least one test |

Not run: the board (`make -C internal e2e`, L4), the firmware tests, and
Jev (`make eval`, no `BOOP_JEV_KEY`). The firmware lane implements the
device side later.

New tests: `CoreActivityTests` (each tool's activity, the working look
only, the priority, the 1.5 s hold on a burst and on a higher one,
waiting after 20 s quiet, planning only from plan mode or a planning
call, delegating while a helper works, a helper's and a turn's calls
ending with them, a denied call, the most recent session, the variant
for a mood with fewer), `CoreOneShotTests` (starting by source and for a
prompt, stopped only for an open turn, error at most every 30 s and
never for denied or late, helper_return once per helper, none while
needs you or listening, the mood's variations), `CoreFuzzTests` (new
invariants for `act` and one-shots, with `SubagentStart`, sources and
plan mode in the traffic), `ReplayTests` (two new fixtures,
`claude-code/synthetic/states.jsonl` and `codex/synthetic/states.jsonl`,
and every other fixture's lines with `act` and one-shots),
`RuntimeTests` (the schedule's `rulePlays`, and a one-shot right after
its `state`), `AdapterTests`, `HookWireTests`, `InstallerTests`,
`DeviceLinkTests` (a line with `act` fits 512 bytes), `ViewTests`.

## The Claude fixture, replayed

`boopdev replay internal/app/Tests/Fixtures/hooks/claude-code/synthetic/states.jsonl --states`
(the `t`, `v`, `mood` and `vol` fields left out):

```
+0.0s state {"base":"idle","busy":0,"variant":1}
+0.0s moment {"t":"moment","anim":"starting","variant":2,"ctx":"session"}
+1.0s state {"base":"working","act":"planning","busy":1,"variant":1}
+1.0s moment {"t":"moment","anim":"starting","variant":1,"ctx":"new_task"}
+2.0s state {"base":"working","act":"analyzing","busy":1,"variant":1}
+4.0s state {"base":"working","act":"searching","busy":1,"variant":1}
+7.0s state {"base":"working","act":"planning","busy":1,"variant":1}
+9.0s state {"base":"working","busy":1,"variant":4}
+11.0s state {"base":"working","act":"analyzing","busy":1,"variant":1}
+14.0s state {"base":"working","busy":1,"variant":1}
+15.0s state {"base":"working","act":"tool_use","busy":1,"variant":1}
+17.0s state {"base":"working","act":"testing","busy":1,"variant":1}
+18.0s moment {"t":"moment","anim":"error","variant":1}
+20.0s state {"base":"working","act":"delegating","busy":1,"variant":1}
+23.0s moment {"t":"moment","anim":"helper_return","variant":1}
+26.0s state {"base":"working","act":"terminal","busy":1,"variant":1}
+46.0s state {"base":"working","act":"waiting","busy":1,"variant":1}
+51.0s state {"base":"idle","busy":0,"variant":3}
+51.0s moment {"t":"moment","anim":"stopped","variant":1}
+52.0s moment {"t":"moment","anim":"starting","variant":3,"ctx":"continuation"}
+53.0s state {"base":"working","busy":1,"variant":4}
+53.0s moment {"t":"moment","anim":"starting","variant":1,"ctx":"new_task"}
+54.0s state {"base":"idle","busy":0,"variant":1}
```

The session starts, plans (plan mode), reads, searches the web, exits
plan mode, runs `rg` (analyzing), edits, runs failing tests (error),
sends an Explore helper that greps (delegating outranks its analyzing)
and comes back, starts a build that goes quiet for 25 s (waiting), is
interrupted, resumes and gets a new task. The Codex fixture shows
analyzing for `nl … | sed -n`, testing, tool_use for `apply_patch`,
terminal, waiting and stopped, and none of searching, delegating,
helper_return or error, which its hooks don't report.

## Headless, through the real hook client

```sh
.build/debug/Boop --headless --state-dir /tmp/bstp4 --brain scripted --name Pip --debug
.build/debug/boopdev replay internal/app/Tests/Fixtures/hooks/claude-code/synthetic/states.jsonl --socket /tmp/bstp4/boop.sock --agent claude
.build/debug/boopdev replay internal/app/Tests/Fixtures/hooks/codex/synthetic/states.jsonl --socket /tmp/bstp4/boop.sock --agent codex
```

`debug.jsonl`'s `sent` lines: 43 to the device (the last a keepalive), with `act` planning 2,
analyzing 3, searching 1, tool_use 2, testing 2, delegating 1, terminal
2 and waiting 2 times, and the one-shots starting 6 (all three
contexts), error 1, helper_return 1 and stopped 2. The scripted brain's
mumbles went out after the one-shots, over them, as the schedule says:

```
{"t":"state","v":1,"base":"working","act":"testing","mood":"happy","busy":1,"vol":6,"variant":1}
{"t":"moment","anim":"error","variant":1}
{"t":"moment","say":{"syl":"di pa ya-mi-di ya ma","word":"yay","at":7,"tune":"bounce","ms":115},"mood":"excited","loops":1}
{"t":"state","v":1,"base":"working","act":"delegating","mood":"happy","busy":1,"vol":6,"variant":1}
{"t":"moment","anim":"helper_return","variant":2}
```

## A scripted working day

`python3 internal/tools/workday/workday.py run --state /tmp/wdp4 --brain scripted --out /tmp/wdp4-out`
runs without Jev: 193 turns, 429 passes, none dropped, 429 brain
moments played. Its script predates these states (no helpers, web
searches, plan mode or long quiet calls), so of the activities it shows
analyzing 408 times, tool_use 276, terminal 232 and testing 64 (980 of
its 2,581 `state` lines), and of the one-shots starting 196 (192 new
tasks, 4 sessions), error 10 and stopped 1. No one-shot was dropped for
a brain line: its fake device ends each brain moment at once. The
report's "still waiting for … settles" warnings are the tool waiting on
a `needs_you` action, which ends only when its request does, not on
anything here; it gives up after 30 s and goes on.

## Mutation checks

Each change was built and the tests run past failures in a scratch
worktree, then reverted:

| Change | Caught by |
| --- | --- |
| The hold 1.0 s instead of 1.5 s | `testABurstOfQuickCallsIsOneStretch`, `testAHigherActivityShowsAtOnceAndHolds`, three `ReplayTests` |
| testing below delegating | `testTheHighestActivityShows`, `testAHelpersCallsEndWithIt` |
| The error window allows 30 s exactly | `testAFailedCommandPlaysErrorAtMostEveryThirtySeconds` |
| One-shots while something needs you | `testNoOneShotWhileSomethingHoldsTheScreen`, `CoreFuzzTests`, a `ReplayTests` |
| A denied call kept | `testADeniedCallShowsNothingMore` |
| The oldest session picks | `testTheSessionHeardFromLastPicksTheActivity` |
| No waiting after 20 s quiet | `testALongQuietCallShowsWaiting` |
| stopped with no turn open | `testAnInterruptPlaysStopped` |
| A rule one-shot over a brain line | `testARuleOneShotPlaysAtOnceAndNeverCutsABrainLine` |
| The variant kept for a mood with fewer | `testANewMoodWithFewerVariationsPicksAgain` |
| No `inspect` topic | `testShellReadsAreInspect`, `testTopicComesFromWhatTheCommandRuns` |
| `act` sent with `attn` | `CoreFuzzTests` |

The scratch run's test list predated the two `states.jsonl` replay
tests, which pin the waiting and one-shot lines too.

## For the firmware lane (P5)

What [PROTOCOL.md](../../../PROTOCOL.md) §3 now asks of the device:

- `state.act`: while `base` is `working` and there's no `attn`, draw that
  state's design, in the mood, in working's place, with `variant` as
  its first variation; missing or unknown means working. The act
  changes as often as every 1.5 s, each change a new `variant`.
- `moment` with `anim` `starting`, `stopped`, `error` or
  `helper_return`, no `id`: play that state's design once through, in
  Boop's mood, then back to the look. `variant` picks the variation
  (clamp one out of range); for `starting` without a usable `variant`,
  pick among those for `ctx`. It replaces the moment playing, a tap
  replaces it, and a face-only brain moment that comes during it plays
  over it (its `mood` drawn on the one-shot's design) without cutting
  it. Skip it while `attn` or `listening` holds the screen, and never
  let it end `listening`: today's firmware ends `listening` on any
  moment with no known `anim` and no syllables.
- The Mac times a one-shot as one loop of `FaceLoops.ms(mood, anim,
  variant)` and expects no `ended`.

## Decision-log rows (for the orchestrator)

Not added to ARCHITECTURE.md; proposed:

| Date | Decision | Why | Spec |
| --- | --- | --- | --- |
| 2026-09-28 | The `state` line carries `act`, what the agents are doing while working (testing, delegating, terminal, searching, analyzing, tool_use, waiting, planning), from running calls, helpers and plan mode, in that priority, held at least 1.5 s; the working session heard from last picks | The mood spectrum's sustained states; the hooks already say which tool runs, and a floor keeps quick tools from flickering | BEHAVIORS.md §2, PROTOCOL.md §3 |
| 2026-09-28 | Waiting is a call gone quiet 20 s, or Codex's grace; it replaces the call's own look, though it ranks below the tool states | Ranked below them with a running tool as its evidence, it could never show | BEHAVIORS.md §2 |
| 2026-09-28 | The rules play one-shots as moments with no `id`: starting, stopped, error (exit code or timeout, at most every 30 s), helper_return. This replaces "the rules add no moment" (only the device's wiggle) | The spectrum's one-shots are facts of the hooks, not the brain's to choose | BEHAVIORS.md §3.1, PROTOCOL.md §3 |
| 2026-09-28 | A rule's one-shot plays at once like the wiggle: a brain moment plays over it without waiting, and it's dropped while a brain line plays. The one-shots stay out of the transcript | Waiting behind one would drop most reactions to a prompt; cutting a brain line would break its `ended` | ARCHITECTURE.md §3.2, harness/EVENTS.md §1 |
| 2026-09-28 | Claude's `SubagentStart` is hooked (14 hooks), and a shell command that only reads gets the topic `inspect` | Delegating and helper_return need helpers' starts; Codex's reads come through its shell | ADAPTERS.md §3, §5 |
| 2026-09-28 | A request answered by anything but its call's result drops that call from the look | Claude sends no hook for a denial, so the call would show until the turn ends | BEHAVIORS.md §2, ADAPTERS.md §4 |
