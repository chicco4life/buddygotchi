# A denied subagent's request clears when it ends (A3, lane core)

2026-09-28, overnight run, lane `core` (branch `ovn2/core`, from main
7f5d10ff). Closes the [PLAN.md](../../../PLAN.md) §3 item "A denied
subagent can keep 'needs you' until the main turn ends".

## What changed

Boop now hooks Claude's `SubagentStop`
([ADAPTERS.md](../../../ADAPTERS.md) §3–5):

- **Installer.** Claude gets 13 hooks, `SubagentStop` the new one, with
  no matcher, so it runs for every subagent type.
- **Hook client.** Nothing new: `boop-hook` already keeps `agent_id` and
  `agent_type` on every hook, and drops `last_assistant_message` and
  `agent_transcript_path` with the rest of the payload.
- **Adapter.** `SubagentStop` becomes a new event, `subagent_end`,
  carrying the subagent's `agent_id`. One without an `agent_id` is
  ignored, since it would pass for the main agent. Codex has none.
- **Core.** `subagent_end` answers that subagent's request and nobody
  else's, since a subagent that has finished can't be waiting on a
  prompt. It isn't activity, so:
  - it never sets a session working;
  - it doesn't move the session's clock, so it can't bring a turn that
    went quiet for an hour (`staleWorkMs`) back to working, or put off
    the safety net;
  - when it answers the last asker, the session works again only if its
    turn is still going, and otherwise goes idle.
  The brain doesn't hear of it: there's no new harness event, so
  [harness/EVENTS.md](../../../harness/EVENTS.md) doesn't change.

Decisions made without the owner:

1. **A new event, not `activity`.** Treating `SubagentStop` as the
   subagent's `activity` would have answered its request with no new
   rule, but it would also make every session working whenever a
   subagent ends, including a background subagent that finishes after
   the main turn's `Stop`. The replay below shows that happening.
2. **"Anyone" stays asking.** A request that came as a `Notification`
   alone doesn't say who asked. A subagent's end answers only its own
   `agent_id`, because hiding a prompt that's still open is the worse
   mistake ([ADAPTERS.md](../../../ADAPTERS.md) §4).
3. **Back to working only mid-turn.** The rule is "works again if its
   turn is still going". Other events that answer a request make the
   session working, but a subagent's end doesn't say the main agent
   is working. In practice a foreground subagent always ends mid-turn,
   and the main agent's `PostToolUse` for the `Agent` call follows at
   once.
4. **An unseen session is created idle,** as for any event from a
   session Boop hasn't seen.

## How an existing install gets the hook

An install from before this change has 12 Claude entries. That isn't
what a fresh install writes, so its health is *outdated*. At launch the
everyday menu-bar app repairs outdated installs, which adds the
`SubagentStop` group (keeping any `SubagentStop` hooks of the person's
own) and asks you to restart open sessions ([ADAPTERS.md](../../../ADAPTERS.md)
§5). `InstallerTests.testAnInstallWithoutSubagentStopIsRepaired` pins
this against the exact 12-hook file in a temporary HOME. Until the owner
next launches the app, `boopdev hooks status` and the `doctor` skill
report Claude's hooks as outdated. This run never read or wrote the real
`~/.claude`.

## Checks that ran

| Check | Result |
| --- | --- |
| `make build` | ok |
| `make -C internal test` | 212 of 212 passed, 7 of them new (below) |
| `make -C internal fw-test` | 111 of 111 passed |
| `make -C internal sim` | 11 scenarios, 0 expect failures, 0 new or changed pictures |
| `internal/tools/.venv/bin/python -m unittest discover -s internal/tools/boopctl_lib/tests` | 27 ok |
| `python3 -m unittest discover -s internal/tools/webcam/tests` | 3 ok |
| `internal/tools/.venv/bin/python internal/tools/facegen/facegen.py --check` | 337 frames of 30 scenes match, no file changed |
| Headless check (below) | as expected |

`make -C internal tools-test` and `faces` weren't run as make targets:
in a lane worktree `internal/tools/.venv` is a symlink that their venv
step can't rebuild. The same commands ran directly, as listed above. No
board, webcam or Jev in this lane.

New or changed tests:

- `AdapterTests.testSubagentStopSaysWhichSubagentEnded`: the event's
  JSON; ignored without an `agent_id`, and for Codex.
- `AdapterTests.testClaudeMapping`: `SubagentStart` takes
  `SubagentStop`'s place as an unmapped hook.
- `HookWireTests.testSubagentStopKeepsOnlyWhichSubagentEnded`: the
  subagent's id and type are kept, its last message and transcript path
  never. A payload cut off at 256 KB by a long last message still says
  which subagent.
- `CoreNeedsYouTests.testASubagentsEndAnswersOnlyItsOwnRequest`,
  `testASubagentsEndLeavesOtherAskersWaiting` and
  `testASubagentsEndNeverMakesASessionWork`.
- `InstallerTests.testAnInstallWithoutSubagentStopIsRepaired`, and
  `SubagentStop` added to `testInstallsEveryClaudeHookAndKeepsOthers`.
- `ReplayTests.testADeniedSubagentsEndAnswersItsRequest`, over the new
  fixture `claude-code/synthetic/subagent-denied.jsonl`.

**Mutation checks.** Each variant was built and run, then reverted:

- *Always working when a subagent's end clears a request:* the suite
  stops at `testASubagentsEndNeverMakesASessionWork` ("no turn was
  going").
- *`SubagentStop` mapped to `activity`:* the suite stops at
  `testSubagentStopSaysWhichSubagentEnded`. The replay shows the idle
  session going back to working at +41 s (below).

## The fixture, replayed

`boopdev replay internal/app/Tests/Fixtures/hooks/claude-code/synthetic/subagent-denied.jsonl --agent claude --states`.
It has two parallel subagents. At +5 s `a1` asks for a Bash command.
`a2` reads a file and ends while `a1` waits. You deny `a1`, which ends
20 s later with only `SubagentStop`. The main agent then edits a file and
stops. Five seconds after the `Stop`, a third subagent `a3` ends.

With this change:

```
+0.0s state {"t":"state","v":1,"base":"idle","mood":"happy","busy":0,"idle":1,"wait":0,"vol":6}
+1.0s state {"t":"state","v":1,"base":"working","mood":"happy","busy":1,"idle":0,"wait":0,"vol":6}
+5.0s state {"t":"state","v":1,"base":"idle","mood":"happy","attn":{"agent":"claude","project":"landing","more":0},"busy":0,"idle":0,"wait":1,"vol":6}
+31.0s state {"t":"state","v":1,"base":"working","mood":"happy","busy":1,"idle":0,"wait":0,"vol":6}
+35.0s state {"t":"state","v":1,"base":"idle","mood":"happy","busy":0,"idle":1,"wait":0,"vol":6}
```

Before the change, `SubagentStop` was ignored, so "needs you" stayed up
through the main agent's work, until its `Stop` (at +33 s here, since
replay moves its clock only for hooks it handles):

```
+5.0s state {…"attn":{"agent":"claude","project":"landing","more":0},"busy":0,"idle":0,"wait":1,…}
+33.0s state {"t":"state","v":1,"base":"idle","mood":"happy","busy":0,"idle":1,"wait":0,"vol":6}
```

With `SubagentStop` mapped to `activity`, the request clears at the same
point, but `a3`'s late end makes the idle session working again:

```
+35.0s state {"t":"state","v":1,"base":"idle","mood":"happy","busy":0,"idle":1,"wait":0,"vol":6}
+41.0s state {"t":"state","v":1,"base":"working","mood":"happy","busy":1,"idle":0,"wait":0,"vol":6}
```

## Headless check

The same session went through the real `boop-hook` to a headless app.
The fixture's waits became clock jumps, and a second session that is
idle then gets a subagent's end
([headless-input.jsonl](headless-input.jsonl)):

```sh
HOME=/tmp/oc1h .build/debug/Boop --headless --brain scripted --state-dir /tmp/oc1 --debug
.build/debug/boopdev replay headless-input.jsonl --socket /tmp/oc1/boop.sock --agent claude
```

From [headless-debug.log](headless-debug.log) (the brain's prompt
text left out):

```
01:38:46.643 hook: claude PermissionRequest fixture-claude-deny → needs_you landing · tool Bash, subagent a1
01:38:46.644 link rules → {"t":"state",…,"base":"idle",…,"attn":{"agent":"claude","project":"landing","more":0},"busy":0,"idle":0,"wait":1,"vol":6}
01:38:50.726 hook: claude SubagentStop fixture-claude-deny → subagent_end landing · subagent a2
01:38:51.747 hook: claude PostToolUse fixture-claude-deny → activity landing · tool Agent
01:38:52.751 dev: clock advanced 20000 ms
01:38:52.751 link rules → {"t":"state",…,"base":"idle",…,"attn":{…},"busy":0,"idle":0,"wait":1,"vol":6}
01:38:52.763 hook: claude SubagentStop fixture-claude-deny → subagent_end landing · subagent a1
01:38:52.763 link rules → {"t":"state",…,"base":"working",…,"busy":1,"idle":0,"wait":0,"vol":6}
01:38:53.781 hook: claude PostToolUse fixture-claude-deny → activity landing · tool Agent
01:38:54.804 hook: claude PreToolUse fixture-claude-deny → activity landing · tool Edit
01:38:55.832 hook: claude PostToolUse fixture-claude-deny → activity landing · tool Edit
01:38:56.848 hook: claude Stop fixture-claude-deny → turn_end landing
01:38:56.848 core: moment cheer
01:38:56.849 link rules → {"t":"state",…,"base":"idle",…,"busy":0,"idle":1,"wait":0,"vol":6}
01:38:57.875 hook: claude SubagentStop fixture-claude-deny → subagent_end landing · subagent a3
01:38:58.878 dev: clock advanced 60000 ms
01:38:58.878 link rules → {"t":"state",…,"base":"idle",…,"busy":0,"idle":1,"wait":0,"vol":6}
01:38:58.893 hook: claude SessionStart idle-2 → session_start jetpack
01:38:58.894 link rules → {"t":"state",…,"base":"idle",…,"busy":0,"idle":2,"wait":0,"vol":6}
01:38:59.911 hook: claude SubagentStop idle-2 → subagent_end jetpack · subagent b1
01:39:00.913 dev: clock advanced 120000 ms
01:39:00.913 link rules → {"t":"state",…,"base":"idle",…,"busy":0,"idle":2,"wait":0,"vol":6}
```

- `a2`'s end, and the main agent's `PostToolUse` for `a2`, left `a1`'s
  request up, 20 s on.
- `a1`'s own `SubagentStop` answered it, and the session went straight
  back to working. The main agent worked on until its `Stop` and the
  cheer.
- `a3`'s end after the `Stop`, and `b1`'s end in the idle session
  `idle-2`, changed nothing. No state was sent for either, and the next
  ones (the app resends its state after a clock jump) are still idle
  with `busy` 0.

`boop-hook` took 7–17 ms per hook (250 ms for the first, from cold), and
exited 0 every time ([headless-replay-sent.txt](headless-replay-sent.txt)).

## Not yet seen for real

- **No recorded `SubagentStop`.** The payload's shape comes from Claude's
  hook reference (`archived/research/eng/reference/claude_hooks.md`,
  "SubagentStop input"). No Claude session has been recorded with it. The
  hook client keeps only `agent_id` and `agent_type`, which the recorded
  subagent hooks already carry. The owner's scenario 7 in
  [PLAN.md](../../../PLAN.md) §2 now includes a deny, which checks it
  for real.
- **The owner's install** picks up the new hook the next time the
  everyday app launches, as above. Open sessions need a restart to read
  it.

## Proposals (not done)

- **Record a denied subagent.** Point a scratch Claude session's hooks at
  a recorder (fixtures' `VERSIONS.md` says how), have it start two
  subagents, and deny one. That would replace the synthetic fixture with
  a recorded one, confirm the order (`SubagentStop` before the parent's
  `PostToolUse` for `Agent`), and show whether a denied subagent's
  `PostToolUseFailure` ever arrives.
- **Background subagents after the turn.** A subagent's tool calls make
  its session working even after the main agent's `Stop`, and only
  another `Stop`, an idle notice or the hour of `staleWorkMs` ends that.
  If Claude doesn't wake the main agent when a background subagent
  finishes, the session could look busy for up to an hour. Now that
  `SubagentStop` reaches the core, it could end that work: track
  subagents that act outside a turn, and go idle when the last one ends.
  That's a change to how a turn is counted, so it's left for a recorded
  session to justify.
