# Boop: harness events

Updated 2026-09-28. What the core hands the harness: the seven kinds of
event, what makes each one, the facts it carries, its line, the rule's
reaction, and whether it wakes the brain. The shape they share is the
harness's contract ([HARNESS.md](HARNESS.md) §3). Actions only ever see
an event's line, never its facts ([DECISIONS.md](DECISIONS.md)).

## 1. Where events come from

The core (`app/BoopKit/Core/Core.swift`) builds every event, from three
inputs:

- **An agent's hook,** through its adapter ([ADAPTERS.md](../ADAPTERS.md)
  §3): turn start, turn end, tool use and needs you.
- **A tap on the device** ([PROTOCOL.md](../PROTOCOL.md) §4): tap and
  pokes.
- **Its own one-second tick:** heartbeat, and a Codex "needs you" once
  its grace period ends ([ADAPTERS.md](../ADAPTERS.md) §4).

For each, it works out the facts, reacts by rule, decides whether the
event wakes the brain, and writes the line (§8). Everything else is its
own bookkeeping (§7).

## 2. Facts

An event's `facts` are its kind's fields (§4.1). They go to the logs and
the evals; the harness never reads them, and the line is written from
them once. A line holds names, named bands (§5), small counts and rounded
durations, never an ID.

## 3. The thread

The kinds about one thread carry it as the fact `thread`:

| Fact | Example | In the line |
| --- | --- | --- |
| `name` | `fix-nav` | Yes. The workspace, or the project when there's none |
| `agent` | `claude`, `codex` | Yes |
| `turn` | `7` | Yes. Turns started since Boop first saw the thread |
| `project` | `landing` | Yes, unless it's the name ([ADAPTERS.md](../ADAPTERS.md) §3) |
| `workspace` | `fix-nav` | As the name. The worktree folder or git branch, or null on the default branch or outside git |
| `session` | `a1b2c3` | No. The agent's session ID, for matching only |

**The workspace** tells two threads in one project apart. An agent
chooses its branch names, so it's the one field that could carry an
agent's words into the state; it's cleaned to a name before anything
sees it ([ADAPTERS.md](../ADAPTERS.md) §3). An event's `about`
([HARNESS.md](HARNESS.md) §3) is the thread's key, `<agent>/<session>`,
such as `claude_code/s1`.

## 4. The kinds

| Kind | The core makes one when | Reaction | Wakes the brain |
| --- | --- | --- | --- |
| `turn_start` | A turn starts | — | Yes |
| `turn_end` | A turn Boop saw start ends `done`, `failed` or `stopped` (§4.1) | `Boop cheered on its own.` when `done`, or none while something needs you | Yes |
| `tool_use` | A tool call finishes and is notable (§4.1), or any call with the personality's `tool_uses: all` ([BEHAVIORS.md](../BEHAVIORS.md) §6) | — | Yes |
| `pokes` | Taps make a poke streak ([BEHAVIORS.md](../BEHAVIORS.md) §3.3) | `Boop wiggled on its own.` | Yes, unless it comes within a minute of the last streak that could (`Core.Config.pokedEveryMs`) |
| `heartbeat` | While no thread works, each whole hour since the last hook or tap (`Core.Config.heartbeatMs`); none before the first since launch | — | Yes |
| `tap` | Any other tap | `Boop wiggled on its own.`, or none while something needs you | Never |
| `needs_you` | An agent starts needing you ([ADAPTERS.md](../ADAPTERS.md) §4) | — | Never |

"Yes" is always subject to the gates in §6.

### 4.1 What each kind carries

| Kind | Fact | Values | In the line |
| --- | --- | --- | --- |
| `turn_start` | `thread` | §3 | Yes |
| | `gap` | Since this thread's last turn ended, a band (§5); null for its first | Yes |
| `turn_end` | `thread` | §3 | Yes |
| | `outcome` | `done`, `failed` or `stopped` | Yes |
| | `error` | The error class of a turn the agent failed ([ADAPTERS.md](../ADAPTERS.md) §2), such as `rate_limit`; else null, as when a failing check failed it | Yes: `failed (rate limit)` |
| | `length`, `length_ms` | The turn's band (§5), and its milliseconds | Both: the band, and the time rounded (`after 18 min`) |
| | `tools`, `tools_failed` | This turn's finished tool calls, and how many failed | Yes |
| | `topics` | Each topic seen this turn, in first-seen order, with its last state: `passing` or `failing` for `tests`, `build` and `deploy`; `edited` for `docs` | Yes: `Tests passing, build failing.` |
| | `comeback` | The last topic whose pass this turn ended a run of failures, or null | Yes |
| `tool_use` | `thread` | §3 | Yes |
| | `tool` | The tool's category (below) | Only in a routine line |
| | `tool_name`, `tool_use_id` | As the agent reports them | No |
| | `topic` | `tests`, `build`, `deploy`, `docs` ([ADAPTERS.md](../ADAPTERS.md) §3), or null | In a notable line |
| | `result` | `ok`, `failed`, or `unknown` when the agent doesn't say | Only `failed` |
| | `error` | A failed call's class: `exit_code`, `timeout`, `denied` or `other`; else null | In brackets, except `exit_code` |
| | `failed_before` | Failures in a row of this topic in this thread just before this call, across turns; a pass sets it back to 0 | Yes |
| | `took`, `took_ms` | The call's band (§5) and milliseconds, when its start was seen | No |
| | `subagent` | The Claude subagent's type (`Explore`), only for a call made inside one | No |
| `pokes` | `count`, `seconds` | Taps in the streak, and the whole seconds they took | Yes |
| | `since_last` | Since the last streak that could wake the brain, a band (§5); null the first time | Yes |
| `heartbeat` | `idle_hours` | Whole hours since the last hook or tap | Yes |
| `tap` | — | | |
| `needs_you` | `thread` | §3 | Yes |

**A turn's outcome** is `failed` when the agent reports an API error, or
when the turn ends while its last test, build or deploy command failed
([BEHAVIORS.md](../BEHAVIORS.md) §3.1); `stopped` when a turn still open is
interrupted ([ADAPTERS.md](../ADAPTERS.md) §3); and `done` otherwise,
the only outcome the rule cheers.

**A turn** starts at your prompt, or at a call while none is open (a
background subagent's after the main agent's `Stop`, or Claude carrying
on after another hook blocked its `Stop`). One a call opens keeps the
thread's `turn` number, and its length and counts start from that call.

**A notable tool use** is a finished `tests`, `build` or `deploy` call
whose result is known: one that failed, or one that passed with
`failed_before` above 0, which also makes its topic the turn's comeback.
Every other finished call only adds to the turn's counts and topics,
unless the personality asks for `all`.

**Tool categories:** `shell` (`Bash`, `shell`, `exec_command`,
`local_shell`), `edit` (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`,
`apply_patch`), `read` (`Read`), `search` (`Grep`, `Glob`, `LS`), `web`
(`WebFetch`, `WebSearch`), `subagent` (`Task`, `Agent`), `mcp` (any
`mcp__…`) and `other`. A call's time pairs its `PreToolUse` with its
result by `tool_use_id`, or else takes the thread's last call start.

**Codex** reports no tool failures, so its tool uses are `unknown` and
never notable, and its turns never fail ([ADAPTERS.md](../ADAPTERS.md)
§3).

## 5. Named bands

No number reaches Jev that it would have to compare
([HARNESS.md](HARNESS.md) §8). The core names them (`Band` in
`app/BoopKit/Core/Event.swift`):

| Band | For | Values |
| --- | --- | --- |
| `Band.length` | A turn's `length`, a tool call's `took` | `short` under 15 s, `long` up to a minute, `very long` past it |
| `Band.gap` | A turn's `gap`, a poke streak's `since_last` | `right after` under 2 min, `a while` under an hour, `a long break` past it |
| `Band.took` | A turn's time in its line, and the status line | `8 s` under a minute, `18 min` under two hours, then `2 h` |

## 6. Which events wake the brain

Every event is recorded and gets its line in later HISTORY. One wakes the
brain only when its kind says so (§4), and never:

- while something needs you ([BEHAVIORS.md](../BEHAVIORS.md) §3.2);
- while there's no brain: before Jev's key is read, or without one
  ([HARNESS.md](HARNESS.md) §7).

The core checks both when it builds the event (`Core.wakes`), after the
event has answered any request it answers ([ADAPTERS.md](../ADAPTERS.md)
§4): tests that fail right after you approved them, or the turn Claude's
idle notice stops after you pressed Esc on its prompt, wake it. Beyond the
poke streak's minute, there's no cooldown: Jev decides every time whether
Boop mumbles.

## 7. Rule reactions and bookkeeping

A rule reaction is decided with its event, so it travels in the event's
`reaction` as a line. The brain can't slow or change it; it only reads
it.

| Reaction | On | The moment |
| --- | --- | --- |
| `Boop cheered on its own.` | `turn_end` with `done`, unless something needs you: attention wins, so there's no cheer to claim ([BEHAVIORS.md](../BEHAVIORS.md) §1) | The core's `cheer` |
| `Boop wiggled on its own.` | `tap`, `pokes` | The device's own `wiggle`, already played |

**Never an event:** a session starting or ending, a tool call starting,
a routine tool use under `notable`, "needs you" clearing, a turn's end
with no turn open (a second `Stop`, or one after the turn stopped), and
the end of a turn Boop joined partway: it launched, or forgot the
session, after the turn started, so it can't know the turn's length or
tools. That turn's finish still cheers, with no event to carry the
reaction, since the screen showed it working. These reach Jev only as counts and
topics in other lines, and in the status line. Working chatter, the
rules' own mumble ([BEHAVIORS.md](../BEHAVIORS.md) §2), never reaches
Jev at all.

## 8. Lines

The core writes every line when it builds the event, from the facts
marked "in the line" in §4.1 (`EventLine` in
`app/BoopKit/Core/Event.swift`), and `EventTests` checks them.

| Kind | Line |
| --- | --- |
| `turn_start` | `claude started turn 7 on "fix-nav" (landing), right after its last one.` The gap reads `, right after its last one`, `, a while after its last one` or `, after a long break`, and is left out for a thread's first turn |
| `turn_end` | `claude finished turn 7 on "fix-nav" (landing): done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.` `failed`, `failed (rate limit)` or `stopped` in place of `done`; `(N failed)`, the topics and the comeback only when there are any |
| `tool_use`, notable | `claude's tests failed on "fix-nav" (landing).`, `… failed again on "…", 3 in a row.`, `… passed on "…" after 3 failures in a row.` An error other than `exit_code` goes in brackets: `(timed out)`, `(denied)`, `(error)` |
| `tool_use`, routine | By category: `claude ran a command on "…".`, `edited a file`, `read a file`, `searched`, `looked something up on the web`, `started a subagent`, and `used a tool` for `mcp` and `other`; ` It failed.` added when it did |
| `pokes` | `You poked Boop 4 times in 2 s, again a while after the last time.` The last part reads `, again right after the last time`, `, again a while after the last time` or `, again after a long break`, and is left out the first time |
| `heartbeat` | `Nothing has happened for 1 hour.`, `… for 3 hours.` |
| `tap` | `You tapped Boop.` |
| `needs_you` | `claude needs you on "fix-nav" (landing).` |

A thread reads `"fix-nav" (landing)`, or just `"landing"` when its name is
the project.

**The status line** closes HISTORY and is the core's too
(`Core.statusLine`): every thread working now except NOW's, in the order
Boop first saw them, each with how long its turn has run:
`Working now: "fix-nav" (codex, landing), for 3 min.`, or
`Working now: nothing else.`

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
  means it ended with an error. A comeback passed after failing.
- Turns are short (under 15 s), long (under a minute) or very long.
```

## 9. Privacy

No prompt text, commands, tool input or output, file contents or agent
messages reach an event. The only names in one are the project's, the
workspace's, the agent's, and in the facts alone, the tool's and a
subagent's type.
