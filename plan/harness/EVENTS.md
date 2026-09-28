# Boop: events and the view

Updated 2026-09-28. What Boop records and what the brain hears. Every
raw event goes into the transcript in one shape; the view folds them
into view events, each with a line of text, and HISTORY and NOW are built
from those ([HARNESS.md](HARNESS.md) §5). Actions only ever see a view
event's line, never its facts ([DECISIONS.md](DECISIONS.md)).

## 1. What goes in the transcript

**An event is something that happened to Boop that the view could need,
or something Boop did that a person could notice. Everything else is a
log line (`debug.jsonl`).**

- **In:** agent hooks that map to a type (§2), pokes, heartbeats, and
  actions: the brain's and the dashboard's (`react`, `mood`) and the
  rules' (`wiggle`, and `needs_you` starting and ending).
- **Out:** hooks Boop ignores, passes (`debug.jsonl` only), state
  snapshots and every other line sent to the device, `status`, the
  device's `ended` (it arrives only as an action's end), and changes of
  settings, brain or connection (the app log).

For a new case, ask: would deleting it change any prompt, or what we can
say Boop did? If not, it's a log line.

## 2. Raw events

Every raw event has the same metadata at the top level, and `data` for
what only its type has (`Event` in `app/BoopKit/Core/Event.swift`). A
Claude `PreToolUse` that runs tests (`AdapterTests.testEventJSONShape`):

```json
{"seq":102,"ts":1790000000123,"source":"claude","type":"tool","phase":"start","specific_type":"PreToolUse","session":"a1b2","cwd":"/Users/me/src/landing","data":{"tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}}
```

| Field | Meaning |
| --- | --- |
| `seq` | Its place in the transcript. It counts on across days and launches |
| `ts` | When it happened, in unix milliseconds (the app's steady clock, which starts at the wall clock's time: [ARCHITECTURE.md](../ARCHITECTURE.md) §3.2) |
| `source` | `claude`, `codex`, `device`, `clock` or `boop` |
| `type` | One of the seven generic types below |
| `phase` | `start`, `wait` or `end` for a type with a lifetime; left out for one that just happens |
| `specific_type` | The source's own name for it: the hook (`UserPromptSubmit`, `Interrupt`), the device's message (`input`), the clock's reason (`idle`, `working`) or the action's name (`react`, `wiggle`) |
| `session`, `subagent`, `cwd` | An agent's session, the Claude subagent's `agent_id`, and the working directory; an action about a session names it too. Left out when there's none |
| `data` | The type's own fields, below |

| `type` | `source` | `phase` | `data` |
| --- | --- | --- | --- |
| `session` | agent | start / end | — |
| `turn` | agent | start / end | start: `prompt`, what you asked. end: `outcome` (`done`, `failed` or `stopped`); `error` for a failed one (its class, [ADAPTERS.md](../ADAPTERS.md) §2); `message`, the agent's last message, on `Stop`; `notice` and `tool` for how a stopped one stopped |
| `tool` | agent | start / wait / end | `tool`, `tool_use_id`. start: `topic` ([ADAPTERS.md](../ADAPTERS.md) §3). wait: `for` (`permission` or `input`), `notice` for a `Notification`, `name`, the thread's name, when the hook found one (the strip's; the view leaves it out). end: `failed` and `error` (its class), Claude only |
| `subagent` | claude | end | — |
| `poke` | device | — | — |
| `heartbeat` | clock | — | — (the view says what it's about, §4) |
| `action` | boop | start / end, or none | `for` (the `seq` of the event it's about, or null), `by` (`brain`, `dashboard` or `rule`), `ok`, `message`. end: `for` (its start's `seq`), `outcome` (`done` or `failed`), `why` |

Any Claude event from inside a subagent also carries the subagent's
`agent_type` in `data`. Which hook becomes which type and phase is
[ADAPTERS.md](../ADAPTERS.md) §3.

**Actions.** One that finishes at once is a single event with no phase.
One that starts something that takes time (a reaction playing on the
device) is a `start`, and its `end` comes later, with `for` naming the
start (HarnessTests):

```jsonl
{"seq":2,"ts":1790000000000,"source":"boop","type":"action","phase":"start","specific_type":"a","data":{"by":"brain","for":1,"latency_ms":0,"message":"Boop did it.","ok":true}}
{"seq":3,"ts":1790000000000,"source":"boop","type":"action","phase":"end","specific_type":"a","data":{"by":"brain","for":2,"outcome":"done"}}
```

The rules record two actions of their own (`Core`), each after the
event that caused it:

| Action | When | `data` |
| --- | --- | --- |
| `wiggle` | A poke, unless something needs you: the device wiggled by itself | `for` the poke, `message` `Boop wiggled on its own.` |
| `needs_you`, start | "Needs you" starts showing for a session, after Codex's grace ([ADAPTERS.md](../ADAPTERS.md) §4) | `for` the request's `tool` wait, `agent`, `message` |
| `needs_you`, end | It clears | `agent`, `outcome`: `done` when answered, else `failed` with `why` (`nothing for 10 minutes`, `the session ended`, `forgotten`) |

## 3. The view

The view (`TranscriptView` in `app/BoopKit/Core/TranscriptView.swift`)
folds raw events, one at a time and in order, into view events. A view
event is a raw type and phase with what the view worked out about it: its
facts (§4.1), its line (§8), whether it wakes the brain (§6), and what
Boop did about it (§7). It points back to the raw events it came from
(`from`, the last is the one that made it).

The same events always make the same view, so a launch replays the
transcript's last two days to pick up where it left off
([HARNESS.md](HARNESS.md) §5): turn numbers and failure runs carry on.
The one thing it decides from the clock is when a heartbeat is due (§4).

**What it keeps** is data (`Keep`): each type and phase kept, all of them
or only the notable ones. The rest are read for what they tell the view
and dropped.

| Type and phase | Kept by default |
| --- | --- |
| `turn` start, `turn` end | All |
| `tool` wait | All |
| `tool` end | Notable ones (§4.1); all with the personality's `tool_uses: all` ([BEHAVIORS.md](../BEHAVIORS.md) §6) |
| `tool` start | None |
| `poke`, `heartbeat` | All |
| `session`, `subagent` | None: they only tell the view when a session ends or a subagent's hook isn't the session's turn |
| `action` | Not as view events: as the `did` lines of the view event it's `for` (§7). A `needs_you` start is kept as the `tool` wait it shows |

### 3.1 The thread

The view events about one thread carry it as the fact `thread`:

| Fact | Example | In the line |
| --- | --- | --- |
| `name` | `fix-nav` | Yes. The workspace, or the project when there's none |
| `agent` | `claude`, `codex` | Yes |
| `turn` | `7` | Yes. Turns started since the view first saw the thread |
| `project` | `landing` | Yes, unless it's the name ([ADAPTERS.md](../ADAPTERS.md) §3) |
| `workspace` | `fix-nav` | As the name. The worktree folder or git branch, or null on the default branch or outside git |
| `session` | `a1b2c3` | No. The agent's session ID, for matching only |

**The workspace** tells two threads in one project apart. An agent
chooses its branch names, so it's cleaned to a name before anything sees
it ([ADAPTERS.md](../ADAPTERS.md) §3). A view event's `about` is the
thread's key, `<agent>/<session>`, such as `claude_code/s1`.

## 4. View events

| View event | Made when | Derived | Wakes the brain |
| --- | --- | --- | --- |
| `turn` start | A turn starts | The thread and its turn number; your prompt | Yes |
| `turn` end | A turn the view saw start ends | Its outcome, length band, tool calls and last message | Yes |
| `tool` wait | "Needs you" starts showing (the core's `needs_you` action), after Codex's 2 s grace | The thread | Never |
| `tool` end | A tool call finishes and is notable, or any with `tool_uses: all` | Its result, whether it passed after failing, its time's band and its category | Yes |
| `tool` start | A tool call starts (not kept by default) | Its topic and the thread | No |
| `poke` | Every poke | How many pokes in a row: each within 3 s of the one before (`TranscriptView.Config.inARowMs`) | Yes, even while something needs you, but not while Boop is answering its run (§6) |
| `heartbeat` | While no thread works, each whole hour since the last agent event or poke (`TranscriptView.Config.heartbeatMs`). While any thread works, once the personality's `working_heartbeat` wait has passed since Boop last reacted (`TranscriptView.reacted`, which the runtime calls as a reaction starts), however many view events woke the brain in it ([BEHAVIORS.md](../BEHAVIORS.md) §2) | The idle hours, or the thread working longest | Yes |

A thread **works** while its turn is open, nothing waits on you, and it
has had an event within the hour; within 10 minutes if its last event
asked for you (the core's safety net, [ADAPTERS.md](../ADAPTERS.md) §4).

"Yes" is always subject to the gates in §6.

### 4.1 What each carries

| View event | Fact | Values | In the line |
| --- | --- | --- | --- |
| `turn` start | `thread` | §3.1 | Yes |
| | `prompt` | What you asked | As a note (§8) |
| `turn` end | `thread` | §3.1 | Yes |
| | `outcome` | `done`, `failed` or `stopped` | Yes |
| | `error` | The error class of a turn the agent failed, such as `rate_limit`; else null, as when a failing check failed it | No |
| | `length`, `length_ms` | The turn's band (§5), and its milliseconds, the time the Mac slept included | The band only |
| | `tools`, `tools_failed` | This turn's finished tool calls, and how many failed | The count only: plenty of calls fail in a turn that succeeds |
| | `topics` | Each topic seen this turn, in first-seen order, with its last state: `passing` or `failing` for `tests`, `build` and `deploy`; `edited` for `docs` | No |
| | `comeback` | The last topic whose pass this turn ended a run of failures, or null | No |
| | `message` | The agent's last message | As a note (§8) |
| `tool` end | `thread` | §3.1 | Yes |
| | `tool` | The tool's category (below) | Only in a routine line |
| | `tool_name`, `tool_use_id` | As the agent reports them | No |
| | `topic` | `tests`, `build`, `deploy`, `docs`, or null | In a notable line |
| | `result` | `ok`, `failed`, or `unknown` when the agent doesn't say | Only `failed` |
| | `error` | A failed call's class: `exit_code`, `timeout`, `denied` or `other`; else null | No |
| | `failed_before` | Failures in a row of this topic in this thread just before this call, across turns; a pass sets it back to 0 | Only whether it's above 0, in a pass: `after failing` |
| | `took`, `took_ms` | The call's band (§5) and milliseconds, when its start was seen | No |
| | `subagent` | The Claude subagent's type (`Explore`), only for a call made inside one | No |
| `tool` wait | `thread` | §3.1 | Yes |
| `poke` | `in_a_row`, `seconds` | Pokes in a row, this one included, and the whole seconds they took | The count, past one |
| `heartbeat` | `idle_hours`, or `thread`, `working_ms` and `topic` | Whole hours since the last agent event or poke; or the thread working longest, how long its turn has run, and its latest topic | The hours; or the thread and its turn's band (§5), not the topic |

**A turn's outcome** is `failed` when the agent reports an API error, or
when the turn ends while its last test, build or deploy command failed
([BEHAVIORS.md](../BEHAVIORS.md) §3.1); `stopped` when a turn still open is
interrupted ([ADAPTERS.md](../ADAPTERS.md) §3); and `done` otherwise.

**A turn** starts at your prompt, or at a call while none is open (a
background subagent's after the main agent's `Stop`, or Claude carrying
on after another hook blocked its `Stop`). One a call opens keeps the
thread's `turn` number, and its length and counts start from that call.
A turn's end with no turn open (a second `Stop`, or one after the turn
stopped) makes no view event, and neither does the end of a turn the view
never saw start. With the transcript read back at launch, that's only a
turn older than the two days it reads.

**A notable tool end** is a finished `tests`, `build` or `deploy` call
whose result is known: one that failed, or one that passed with
`failed_before` above 0, which also makes its topic the turn's comeback.
Every other finished call only adds to the turn's counts and topics,
unless the personality asks for `all`.

**Tool categories:** `shell` (`Bash`, `shell`, `exec_command`,
`local_shell`), `edit` (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`,
`apply_patch`), `read` (`Read`), `search` (`Grep`, `Glob`, `LS`), `web`
(`WebFetch`, `WebSearch`), `subagent` (`Task`, `Agent`), `mcp` (any
`mcp__…`) and `other`. A call's time pairs its start with its end by
`tool_use_id`, or else takes the thread's last call start.

**Codex** reports no tool failures, so its tool ends are `unknown` and
never notable, and its turns never fail ([ADAPTERS.md](../ADAPTERS.md)
§3).

## 5. Named bands

No number reaches Jev that it would have to compare
([HARNESS.md](HARNESS.md) §8). The view names them (`Band` in
`app/BoopKit/Core/Event.swift`):

| Band | For | Values |
| --- | --- | --- |
| `Band.length` | A turn's `length`, the working heartbeat's turn so far, a tool call's `took` | `short` under a minute, `long` under 5 minutes, `very long` from 5 minutes: the lengths the moods read ([DECISIONS.md](DECISIONS.md) §2.3) |

## 6. Which view events wake the brain

Every kept view event gets its line in later HISTORY. One wakes the brain
only when its kind says so (§4), and never:

- while there's no brain: before Jev's key is read, or without one
  ([HARNESS.md](HARNESS.md) §7);
- while something needs you ([BEHAVIORS.md](../BEHAVIORS.md) §3.2), a
  poke aside: you poking Boop is the one thing that may reach it then
  (`TranscriptView.wakesWhileNeeded`);
- for a poke, while Boop is answering its run: the brain's reaction to
  the run's pokes in a row is in progress, a tap-cut one included (§7),
  and the mood hasn't changed since it started
  (`TranscriptView.pokesAnswered`). A reaction to the run's first,
  single poke doesn't count: the barrage after it is new to the brain.

The pipeline checks these once the core has had the event
(`Pipeline.whyNotWake`), so an event that answers a request wakes it: tests
that fail right after you approved them, or the turn Claude's idle
notice stops after you pressed Esc on its prompt. The harness checks
again when a view event that waited behind a running pass would start
its own ([HARNESS.md](HARNESS.md) §2): a poke that came during the pass
whose reaction now answers its run is dropped. There's no cooldown: Jev decides
every time whether Boop mumbles, and a view event that wakes it starts
the working heartbeat's wait again.

**Pokes can make Boop grumpy.** A poke's pass asks every question, the
mood's included, as any pass does. The mood files say many pokes in a
row are a reason for grumpy, and grumpy blows over after 2 minutes
([DECISIONS.md](DECISIONS.md) §2.3); the personality's Examples say how
Boop reacts to one poke and to a barrage.

## 7. What Boop did

Every action is a raw event (§2), and the view puts it under the view
event it's `for`, as a `did` line; one forced by the dashboard, for none,
goes under the latest. HISTORY shows the lines in order, a started one
marked `(in progress)` until its end. A failed action isn't shown, and
neither is a started one that ended failed, but for a reaction your tap
cut short (`cut short: you tapped Boop`): you saw it start, so its line
stays, and stays `(in progress)` while the pokes go on (each within 3 s
of the last, §6), so the barrage doesn't wake the brain for it again. The next poke
after that, or any other event, makes it plain. NOW's last line is what the
rules did (the `wiggle`), or `Boop did nothing on its own.`
([HARNESS.md](HARNESS.md) §5.3).

## 8. Lines

The view writes every line when it makes the view event, from the facts
marked "in the line" in §4.1 (`EventLine` in
`app/BoopKit/Core/TranscriptView.swift`), and `ViewTests` checks them.

| View event | Line |
| --- | --- |
| `turn` start | `claude started turn 7 on "fix-nav" (landing).` |
| `turn` end | `claude finished turn 7 on "fix-nav" (landing): done, a very long turn, 12 tool calls.` `failed` or `stopped` in place of `done`, the length band (§5), and `1 tool call` or `no tool calls` |
| `tool` end, notable | `claude's tests failed on "fix-nav" (landing).`, the same for a repeat, and `claude's tests passed on "fix-nav" (landing) after failing.` |
| `tool` end, routine | By category: `claude ran a command on "…".`, `edited a file`, `read a file`, `searched`, `looked something up on the web`, `started a subagent`, and `used a tool` for `mcp` and `other`; ` It failed.` added when it did |
| `tool` start | `claude started running tests on "…".`, `a build`, `a deploy`, `editing docs`, or by category: `a command`, `editing a file`, … |
| `tool` wait | `claude needs you on "fix-nav" (landing).` |
| `poke` | `You poked Boop.`, or `You poked Boop 4 times in a row.` |
| `heartbeat` | `Nothing has happened for 1 hour.`, `… for 3 hours.` While working: `claude is still working on "fix-nav" (landing), a long turn.`, the band of its turn so far |

A thread reads `"fix-nav" (landing)`, or just `"landing"` when its name is
the project.

**Notes** go under a line, before what Boop did: a turn start's
`You asked: "…"` and a turn end's `Its last message: "…"`, each on one
line and cut to 300 characters (`EventLine.messageMax`).

**Few modifiers.** A line carries only an outcome (`done`, `failed`,
`stopped`, and ` It failed.` on a routine tool line), a length band, a
turn's tool calls, `after failing` on a pass and a poke's count: no
streaks, times, gaps, error reasons or topic lists, so a line means one
thing and a test can pin what Jev reads. The facts keep the rest for logs
and evals. The only line that closes HISTORY is `mood`'s
([HARNESS.md](HARNESS.md) §5.3).

### 8.1 Words

The lines use a few words Jev couldn't know. The guide explains them
after how to read the layout ([HARNESS.md](HARNESS.md) §6.1), from
`EventLine.words`, kept next to the lines so a change to one changes the
other:

```
- claude and codex are the person's coding agents.
- A thread is one conversation with an agent, named after its workspace:
  "fix-nav" (landing) is the thread fix-nav in the project landing.
- A turn is one request to a thread. It ends done, failed or stopped.
- Tests, build, deploy and docs are what a command was about; failed
  means it ended with an error.
- Turns are short (under a minute), long (under 5 minutes) or very
  long (5 minutes or more).
```

## 9. Privacy

Two pieces of anyone's words reach the transcript and the brain: your
prompt (`UserPromptSubmit`) and the agent's last message (`Stop`), each
up to 2,000 characters on the wire and 300 in the state. No commands,
tool input or output, file contents, error text or transcripts do. The
other names in an event are the project's, the workspace's, the agent's,
and in its data alone, the tool's and a subagent's type.
