# Boop: events and the view

Updated 2026-09-30. What Boop records and what the brain hears. Every
raw event goes into the transcript in one shape; the view folds them
into view events, each with a line of text, and HISTORY and NOW are built
from those ([HARNESS.md](HARNESS.md) §5). Actions only ever see a view
event's line, never its facts ([DECISIONS.md](DECISIONS.md)).

## 1. What goes in the transcript

**An event is something that happened to Boop that the view could need,
or something Boop did that a person could notice. Everything else is a
log line (`debug.jsonl`).**

- **In:** agent hooks that map to a type (§2), pokes, what you say to
  Boop on push-to-talk, you stepping away from the Mac and coming back
  (§2.1), heartbeats, "needs you" starting and ending, and actions: the
  brain's and the dashboard's (`react`, `mood`) and the rules' (`wiggle`,
  `open_thread`).
- **Out:** hooks Boop ignores, passes (`debug.jsonl` only), state
  snapshots and every other line sent to the device (the rules'
  one-shots included: like the look, they show what the agents did, and
  the view has the events behind them), `status`, the
  device's `ended` (it arrives only as an action's end), the mic going
  on and off, hearing nothing or failing (the app log), and changes of
  settings, brain or connection (the app log).

For a new case, ask: would deleting it change any prompt, or what we can
say Boop did? If not, it's a log line.

## 2. Raw events

Every event is the brain kit's ([kit/BRAIN-KIT.md](../kit/BRAIN-KIT.md)
§2.1): `seq`, `at`, `source`, `kind` and `data`. For Boop, `kind` is the
event's type and phase together (`tool_start`, `poke`), and the rest of
what used to be at the top (the source's own name for it, the session,
subagent and working directory) is in `data` (Boop's reading of an event,
`type`, `phase`, `specificType`, `session`, is in
`app/BoopKit/Core/Event.swift`). A Claude `PreToolUse` that runs tests
(`AdapterTests.testEventJSONShape`):

```json
{"seq":102,"at":1790000000123,"source":"claude","kind":"tool_start","data":{"cwd":"/Users/me/src/landing","session":"a1b2","specific_type":"PreToolUse","tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}}
```

| Field | Meaning |
| --- | --- |
| `seq` | Its place in the transcript. It counts on across days and launches |
| `at` | When it happened, in unix milliseconds (the app's steady clock, which starts at the wall clock's time: [ARCHITECTURE.md](../ARCHITECTURE.md) §3.2) |
| `source` | `claude`, `codex`, `device`, `clock`, `boop`, `mic` or `mac`, and `self` for the kit's own events (below) |
| `kind` | One of the nine types below, and for a type with a lifetime its phase after an underscore, `start`, `wait` or `end`: `turn_end`, `tool_wait`, `presence_start`. A type that just happens is its name alone: `poke` |
| `data.specific_type` | The source's own name for it: the hook (`UserPromptSubmit`, `Interrupt`), the device's message (`input`), the clock's reason (`idle`, `working`), the button that turned the mic on (`device` or `app`) or why you're away or back (§2.1) |
| `data.session`, `data.subagent`, `data.cwd` | An agent's session, the Claude subagent's `agent_id`, and the working directory; "needs you" names its session too. Left out when there's none |
| `data` | Those, and the type's own fields, below. Every agent event can also carry `name`, the thread's name as its agent's app shows it, when the hook found one ([ADAPTERS.md](../ADAPTERS.md) §2): for the strip, the popover and a cheer; and `app` and `app_session`, the app the agent runs in and that app's ID for the session, when the hook's environment said: where a tap opens the thread ([BEHAVIORS.md](../BEHAVIORS.md) §3.2). The view leaves them out. The core carries each on, so an event is recorded without the ones its session already has (and `mode` while plan mode hasn't changed): the first event of a session each day, so each day's file has them for a launch's read-back ([HARNESS.md](HARNESS.md) §5), or of one the core doesn't hold, after a launch, the session's end or a day's silence, has them all (`Core.unrepeated`) |

| `type` | `source` | `phase` | `data` |
| --- | --- | --- | --- |
| `session` | agent | start / end | start: `source` (`startup`, `resume`, `clear` or `compact`), when the hook says |
| `turn` | agent | start / end | start: `prompt`, what you asked. end: `outcome` (`done`, `failed` or `stopped`); `error` for a failed one (its class, [ADAPTERS.md](../ADAPTERS.md) §2); `message`, the agent's last message, on `Stop`; `notice` and `tool` for how a stopped one stopped |
| `tool` | agent | start / wait / end | `tool`, `tool_use_id`. start: `topic` ([ADAPTERS.md](../ADAPTERS.md) §3). wait: `for` (`permission` or `input`), `notice` for a `Notification`. end: `failed` and `error` (its class), Claude only |
| `subagent` | claude | start / end | — (the subagent is the event's `subagent`) |
| `poke` | device | — | — |
| `talk` | mic | — | `words`: what the Mac's mic heard, as macOS transcribed it, up to 2,000 characters (`HookLine.maxMessage`). Only when it heard something |
| `presence` | mac | start / end | start (you stepped away): `since`, when you last touched the Mac, in unix milliseconds. end (you're back): — (§2.1) |
| `heartbeat` | clock | — | — (the view says what it's about, §4) |
| `needs_you` | boop | start / end | "Needs you" showing for a session and clearing, which the core records (below) |

What you said after the popover's Talk button (a headless run with
`{"dev":"said",…}`, [VERIFICATION.md](../VERIFICATION.md) §2):

```json
{"seq":1,"at":1790580772176,"source":"mic","kind":"talk","data":{"specific_type":"app","words":"hey Boop, are the tests passing?"}}
```

Any Claude event from inside a subagent also carries the subagent's
`agent_type` in `data`, and any Claude event whose hook reports it
carries its permission mode as `mode` (`plan` shows as planning,
[BEHAVIORS.md](../BEHAVIORS.md) §2). Only the core reads `source` and
`mode`; the view leaves them out. Which hook becomes which type and
phase is [ADAPTERS.md](../ADAPTERS.md) §3.

You locking the screen, it counting as an away 10 minutes later, and
you coming back an hour after you locked it (the shape
`PresenceTests` pins):

```jsonl
{"seq":40,"at":1790000600000,"source":"mac","kind":"presence_start","data":{"since":1790000000000,"specific_type":"locked"}}
{"seq":41,"at":1790003600000,"source":"mac","kind":"presence_end","data":{"specific_type":"unlocked"}}
```

**What Boop did** is the brain kit's own events, `self`'s
([kit/BRAIN-KIT.md](../kit/BRAIN-KIT.md) §2.2): a `did` for each action,
the brain's, the dashboard's (`react`, `mood`) and the rules' (`wiggle`,
`open_thread`), with `for` (the `seq` of the event it's about, or null),
`action` (its name), `by` (`brain`, `dashboard` or `rule`), `ok`,
`message`, and the action's own facts: `react`'s has `takes` (the ids of
the takes it queued, in the order said, `[]` when it says nothing), so a
tool can say what it said. One that starts something that takes time (a
reaction playing on the device) is `open`, and its `ended` comes later,
with `for` naming the `did`, `outcome` (`done` or `failed`) and `why`
(HarnessTests):

```jsonl
{"seq":2,"at":1790000000000,"source":"self","kind":"did","data":{"action":"a","by":"brain","for":1,"latency_ms":0,"message":"Boop did it.","ok":true,"open":true}}
{"seq":3,"at":1790000000000,"source":"self","kind":"ended","data":{"action":"a","by":"brain","for":2,"outcome":"done"}}
```

The rules record three of their own (`Core`), each after the event that
caused it: two actions, and "needs you" as events of its own type:

| Action | When | `data` |
| --- | --- | --- |
| `wiggle` | A poke, unless something needs you or `listening` shows: the device played its poke by itself (the mood's `poked` design, `tap_spam` from the third in a row, [BEHAVIORS.md](../BEHAVIORS.md) §3.3). The action keeps its older name and message, which Jev reads, until the evals can check new wording | `for` the poke, `message` `Boop wiggled on its own.` |
| `open_thread` | A poke while something needs you and `listening` doesn't show: the Mac opens the thread the sign names ([BEHAVIORS.md](../BEHAVIORS.md) §3.2). Or a poke on the brain's finish that names whose turn it was: the Mac opens that thread (§3.3) | `for` the poke, `agent`, `message` `Boop opened the thread that needs you on the Mac.`, or for a finish `Boop opened the thread that finished on the Mac.` |
| `needs_you_start` | "Needs you" starts showing for a session, after Codex's grace ([ADAPTERS.md](../ADAPTERS.md) §4) | `for` the request's `tool` wait, `agent`, `session`, `by` `rule`, `message` |
| `needs_you_end` | It clears | `agent`, `session`, `by` `rule`, `outcome`: `done` when answered, else `failed` with `why` (`nothing for 10 minutes`, `the session ended`, `forgotten`) |

A transcript line written before the brain kit (2026-09-30), with `ts`,
`type`, `phase` and `specific_type` at the top and actions as a type of
their own, is still read, as the event it would be now (`Event.legacy`),
so the launch after the change picks up where the last one left.

### 2.1 Here and away

Whether you're at the Mac is decided in one place, the presence
detector (`PresenceDetector` in
`app/BoopKit/Presence/PresenceDetector.swift`), which makes the
`presence` events. Nothing after it decides again: the view pairs a
start with its end and the brain hears them (§4), and nothing else
reads them.

It hears the Mac's raw signals (`app/Boop/PresenceSignals.swift`), none
of which asks for a permission: the screen locking and unlocking
(switching to another user counts as a lock), the Mac or its displays
sleeping and waking, and, on the runtime's 1 s tick, how long it's been
since the last key press or mouse move: a number, never the keys.

| | When (`PresenceDetector.Config`) | `specific_type` |
| --- | --- | --- |
| Away (`start`) | The screen stays locked 10 minutes (`lockAwayMs`) | `locked` |
| | The Mac or its displays stay asleep 10 minutes (`lockAwayMs`) | `asleep` |
| | No key or mouse for 30 minutes (`idleAwayMs`) | `idle` |
| Back (`end`) | While away: a key or mouse within the last 5 s (`backInputMs`), the screen unlocked and awake | `unlocked` or `woke` if that came since the away, else `input` |

**Only a break worth a hello.** Every back wakes the brain, and Boop
cheers at it, so the detector records only a break long enough to be
greeted: a minute away to fetch a coffee gets nothing, ten minutes gets
a hello. A lock or sleep almost always means you left, so it counts
after 10 minutes. Idle alone can be a video or a long read, so it waits
longer; displays that sleep on their own usually come sooner, and a
playing video keeps them awake. A lock or sleep shorter than 10
minutes, or idle shorter than 30, records nothing, and nothing shows
it happened.

**`since`** is the tick's time minus the idle time, so an away noticed
after 30 minutes of idle starts when you left, not when it was noticed.

**One at a time.** While you're away, more signals record nothing until
you're back. At launch the detector starts from the view: away if the
transcript's last `presence` is a start (`TranscriptView.away`), so a
launch never records a second away, and your first touch records the
back. `Boop --headless` reads none of the Mac's signals; dev lines stand
in for them ([HARNESS.md](HARNESS.md) §9).

**Being away changes nothing.** Nothing acts on an away: the core never
sees one, and it never wakes the brain. Only coming back does, since a
wrong away (a long video) must not make Boop go quiet (decision log in
[ARCHITECTURE.md](../ARCHITECTURE.md) §11).

## 3. The view

The view (`TranscriptView` in `app/BoopKit/Core/TranscriptView.swift`)
folds raw events, one at a time and in order, into view events. A view
event is a raw type and phase with what the view worked out about it: its
facts (§4.1), its line (§8), whether it wakes the brain (§6), how its
pass waits behind a running one (its priority: a finished turn keeps its
pass, and what you said goes ahead of it, [HARNESS.md](HARNESS.md) §2),
and what Boop did about it (§7). It points back to the raw events it came from
(`from`, the last is the one that made it).

The same events always make the same view, so a launch replays the
transcript's last 24 hours to pick up where it left off
([HARNESS.md](HARNESS.md) §5): turn numbers and failure runs carry on.
The one thing it decides from the clock is when a heartbeat is due (§4).

**What it keeps** goes by type and phase (`TranscriptView.keeps`): all
of them, or only the notable ones. The rest are read for what they tell
the view and dropped.

| Type and phase | Kept by default |
| --- | --- |
| `turn` start, `turn` end | All |
| `tool` wait | All |
| `tool` end | Notable ones (§4.1); all with the personality's `tool_uses: all` ([BEHAVIORS.md](../BEHAVIORS.md) §6) |
| `tool` start | None |
| `poke`, `talk`, `heartbeat` | All |
| `presence` start, `presence` end | All |
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
thread's key, `<agent>/<session>`, such as `claude/s1`.

## 4. View events

| View event | Made when | Derived | Wakes the brain |
| --- | --- | --- | --- |
| `turn` start | A turn starts | The thread and its turn number; your prompt | Yes |
| `turn` end | A turn the view saw start ends | Its outcome, length band, tool calls and last message | Yes |
| `tool` wait | "Needs you" starts showing (the core's `needs_you` action), after Codex's 2 s grace | The thread | Never |
| `tool` end | A tool call finishes and is notable, or any with `tool_uses: all` | Its result, whether it passed after failing, its time's band and its category | Yes |
| `poke` | Every poke | How many pokes in a row: each within 3 s of the one before (`TranscriptView.inARowMs`) | Yes, but not while something needs you (the tap opens the thread) or while Boop is answering its run (§6) |
| `talk` | You said something to Boop on push-to-talk ([BEHAVIORS.md](../BEHAVIORS.md) §3.3) | Your words | Always, even while something needs you (§6) |
| `presence` start | The detector says you stepped away (§2.1) | Why, and since when | Never |
| `presence` end | You're back from an away the view saw start | How long you were away, from its `since`, as a band (§5) | Yes |
| `heartbeat` | While no thread works, each whole hour since the last agent event, poke, what you said or your coming back (`TranscriptView.heartbeatMs`). While any thread works, once the personality's `working_heartbeat` wait has passed since Boop last started a reaction (the view sees `react`'s `action` start, §7), however many view events woke the brain in it ([BEHAVIORS.md](../BEHAVIORS.md) §2) | The idle hours, or the thread working longest | Yes |

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
| | `topic` | `tests`, `build`, `deploy`, `docs`, `inspect` (a command that only looks, [ADAPTERS.md](../ADAPTERS.md) §3), or null | In a notable line |
| | `result` | `ok`, `failed`, or `unknown` when the agent doesn't say | Only `failed` |
| | `error` | A failed call's class: `exit_code`, `timeout`, `denied` or `other`; else null | No |
| | `failed_before` | Failures in a row of this topic in this thread just before this call, across turns; a pass sets it back to 0 | Only whether it's above 0, in a pass: `after failing` |
| | `took`, `took_ms` | The call's band (§5) and milliseconds, when its start was seen | No |
| | `subagent` | The Claude subagent's type (`Explore`), only for a call made inside one | No |
| `tool` wait | `thread` | §3.1 | Yes |
| `poke` | `in_a_row`, `seconds` | Pokes in a row, this one included, and the whole seconds they took | The count, past one |
| `talk` | `words`, `by` | What you said, whole; the button, `device` or `app` | The words, cut to 300 characters |
| `presence` start | `why`, `since` | `locked`, `asleep` or `idle` (§2.1); when you last touched the Mac | No |
| `presence` end | `away`, `away_ms` | The break's band (§5), and its milliseconds, from the start's `since` | The band only |
| `heartbeat` | `idle_hours`, or `thread`, `working_ms` and `topic` | Whole hours since the last agent event, poke, what you said or your coming back; or the thread working longest, how long its turn has run, and its latest topic | The hours; or the thread and its turn's band (§5), not the topic |

**A turn's outcome** is `failed` when the agent reports an API error, or
when the turn ends while its own last test, build or deploy command failed
([BEHAVIORS.md](../BEHAVIORS.md) §3.1); `stopped` when a turn still open is
interrupted ([ADAPTERS.md](../ADAPTERS.md) §3); and `done` otherwise.

**A turn** starts at your prompt, or at the main agent's call while none
is open (Claude carrying on after another hook blocked its `Stop`). One
a call opens keeps the thread's `turn` number, and its length, counts
and last check start from that call. A subagent's call opens none: a background helper
that works on after the main agent's `Stop` is no turn, so it has no
working heartbeat and no finish, though its notable tool ends count.
A turn's end with no turn open (a second `Stop`, or one after the turn
stopped) makes no view event, and neither does the end of a turn the view
never saw start. With the transcript read back at launch, that's only a
turn older than the 24 hours it reads.

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
| `Band.away` | A `presence` end's `away` | `short` under 15 minutes, `long` under 2 hours, `very long` from 2 hours |

## 6. Which view events wake the brain

Every kept view event gets its line in later HISTORY. One wakes the brain
only when its kind says so (§4), and never:

- while there's no brain: before Jev's key is read, or without one
  ([HARNESS.md](HARNESS.md) §7);
- while something needs you ([BEHAVIORS.md](../BEHAVIORS.md) §3.2), what
  you say aside: talking to Boop is the only thing that may reach it
  then (`TranscriptView.wakesWhileNeeded`). A poke doesn't: then a tap
  opens the waiting thread (`open_thread`), and it's still counted in
  its run;
- for a poke that opened a finished turn's thread (`open_thread`,
  [BEHAVIORS.md](../BEHAVIORS.md) §3.3): it means "take me there", and
  it's still counted in its run;
- for a poke, while Boop is answering its run: the brain's reaction to
  the run's third poke in a row or a later one
  (`TranscriptView.answersRunFrom`) is in progress, a tap-cut one
  included (§7), and the mood hasn't changed since it started
  (`TranscriptView.pokesAnswered`). Reactions to the run's first two
  pokes don't count, so each poke can take Boop a step further: glad,
  then miffed, then grumpy.

The pipeline checks these once the core has had the event
(`Pipeline.whyNotWake`), so an event that answers a request wakes it: tests
that fail right after you approved them, or the turn Claude's idle
notice stops after you pressed Esc on its prompt. The harness checks
again when a view event that waited behind a running pass would start
its own ([HARNESS.md](HARNESS.md) §2): a poke that came during the pass
whose reaction now answers its run is dropped. There's no cooldown: Jev decides
every time whether Boop reacts, and a view event that wakes it starts
the working heartbeat's wait again.

**Pokes can make Boop grumpy.** A poke's pass asks every question, the
mood's included, as any pass does. The mood files say two pokes in a
row are a reason for determined (miffed) and three or more for grumpy,
and grumpy blows over after 2 minutes
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
rules did (the `wiggle` or `open_thread`), or `Boop did nothing on its own.`
([HARNESS.md](HARNESS.md) §5.3).

## 8. Lines

The view writes every line when it makes the view event, from the facts
marked "in the line" in §4.1 (`EventLine` in
`app/BoopKit/Core/TranscriptView.swift`), and `ViewTests` checks them, `PresenceTests` the presence lines.

| View event | Line |
| --- | --- |
| `turn` start | `claude started turn 7 on "fix-nav" (landing).` |
| `turn` end | `claude finished turn 7 on "fix-nav" (landing): done, a very long turn, 12 tool calls.` `failed` or `stopped` in place of `done`, the length band (§5), and `1 tool call` or `no tool calls` |
| `tool` end, notable | `claude's tests failed on "fix-nav" (landing).`, the same for a repeat, and `claude's tests passed on "fix-nav" (landing) after failing.` |
| `tool` end, routine | By category: `claude ran a command on "…".`, `edited a file`, `read a file`, `searched`, `looked something up on the web`, `started a subagent`, and `used a tool` for `mcp` and `other`; ` It failed.` added when it did |
| `tool` wait | `claude needs you on "fix-nav" (landing).` |
| `poke` | `You poked Boop.`, or `You poked Boop 4 times in a row.` |
| `talk` | `You said to Boop: "are the tests passing yet?"`, on one line and cut to 300 characters like a note (`EventLine.said`) |
| `presence` start | `You stepped away from the Mac.` |
| `presence` end | `You came back to the Mac after a long break.`, the break's band (§5) |
| `heartbeat` | `Nothing has happened for 1 hour.`, `… for 3 hours.` While working: `claude is still working on "fix-nav" (landing), a long turn.`, the band of its turn so far |

A thread reads `"fix-nav" (landing)`, or just `"landing"` when its name is
the project.

**Notes** go under a line, before what Boop did: a turn start's
`You asked: "…"` and a turn end's `Its last message: "…"`, each on one
line and cut to 300 characters (`EventLine.messageMax`).

**Few modifiers.** A line carries only an outcome (`done`, `failed`,
`stopped`, and ` It failed.` on a routine tool line), a length band, a
turn's tool calls, `after failing` on a pass, a poke's count and a
break's band: no
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
- "You said to Boop" quotes the person talking to Boop. It can't talk
  back: it answers with a face, and maybe a word or a sound.
- "You" stepping away from the Mac and coming back is the person. Breaks
  are short (under 15 minutes), long (under 2 hours) or very long (2
  hours or more).
```

## 9. Privacy

Three pieces of anyone's words reach the transcript and the brain: your
prompt (`UserPromptSubmit`), the agent's last message (`Stop`) and what
you say to Boop on push-to-talk (`talk`), each up to 2,000 characters in
the transcript and 300 in the state. Push-to-talk's audio never leaves
the Mac and is never kept: macOS recognizes it on the Mac
(`requiresOnDeviceRecognition`) and only the words go on. No commands,
tool input or output, file contents, error text or transcripts do. The
other names in an event are the project's, the workspace's, the agent's,
and in its data alone, the tool's and a subagent's type. Of what you do
on the Mac, only whether you're away and when you left and came back
are recorded (§2.1): not which app, window or keys.
