# Boop: harness events

Updated 2026-09-27. What the core hands the harness: the kinds of event,
the facts each carries, which wake the brain, and the lines they're
written as. The shape every event shares is the harness's contract
([HARNESS.md](HARNESS.md) §3); what Boop decides about them is in
[DECISIONS.md](DECISIONS.md), which never reads an event's facts, only
its line.

## 1. What an event is

The core turns hook events ([ADAPTERS.md](../ADAPTERS.md)), taps and its
own clock into seven kinds of event: **turn start**, **turn end**, **tool
use**, **pokes**, **heartbeat**, **tap** and **needs you**. For each it
works out the facts, reacts by rule, decides whether the event wakes the
brain, and writes its line (§8). The result is
one `Event` ([HARNESS.md](HARNESS.md) §3); the harness only records it
and places its line.

## 2. Facts

An event's `facts` are its kind's fields (§4), plus the thread (§3) for
the kinds about one. They're for the core's line-writing, the logs and
the evals; the harness never reads them. Each fact is either **shown**,
meaning a line may say it, or **hidden**, used only for matching, timing
and logs. A line only ever says names, named bands (§5) and small counts:
never IDs or raw durations.

## 3. The thread

| Fact | Shown | Example | Meaning |
| --- | --- | --- | --- |
| `name` | ✓ | `agent-work-visibility` | The workspace, or the project when there's none |
| `agent` | ✓ | `claude`, `codex` | Which agent |
| `subagent` | ✓ | `Explore` | A Claude subagent's type, for events from inside one |
| `turn` | ✓ | `7` | Which turn of the thread this is, counted since Boop first saw it |
| `project` | ✓ (with the name) | `buddygotchi` | The project ([ADAPTERS.md](../ADAPTERS.md) §3) |
| `workspace` | — | `agent-work-visibility` | The worktree folder, or else the git branch; none on the default branch or outside git |
| `session` | — | `a1b2c3` | The agent's session ID, for matching only |

**The workspace name** tells two threads in the same project apart. It
comes from the worktree folder, or else the branch in `.git/HEAD`, read
with the project name and cached the same way. It's cleaned before
anything sees it: a leading `word/` (`claude/`) and a trailing hash
(`-7a22ea`) are dropped, it's lowercased, only `a-z`, `0-9` and `-` are
kept, and it's cut to 40 characters. An agent chooses its branch names, so
this is the one field in the state an agent could put words into; the
cleaning keeps it a name.

## 4. The kinds

| Kind | Facts, shown | Facts, hidden | Wakes the brain |
| --- | --- | --- | --- |
| **Turn start** (`turn_start`) | The thread; `resumed` (the session was resumed), `gap` since this thread's last turn | — | Always |
| **Turn end** (`turn_end`) | The thread; `outcome`: `done`, `failed` or `stopped`; `error` class when failed; `length`; `tools` and `tools_failed` (counts for the turn); `topics`: each topic's last state this turn; `comeback`: a topic that passed after failing this turn, if one did | `length_ms` | Always |
| **Tool use** (`tool_use`) | The thread; `tool` category; `topic`; `result`: `ok`, `failed` or `unknown`; `error` class when failed; `took`; `failed_before`: failures in a row of this topic in this thread just before this one | `tool_name`, `tool_use_id`, `took_ms` | Always. Only a tool use with a topic that failed, or passed after at least one failure, becomes an event; the core keeps the rest to itself and only counts them |
| **Pokes** (`pokes`) | `count`, `seconds` (the window they came in), `since_last` streak | — | As [BEHAVIORS.md](../BEHAVIORS.md) §3.3 allows a poke streak |
| **Heartbeat** (`heartbeat`) | `idle_hours`: whole hours since the last event | — | Always |
| **Tap** (`tap`) | — | — | Never: the rules handle it alone |
| **Needs you** (`needs_you`) | The thread | — | Never: the rules handle it alone |

- **Outcome.** `failed` is as [BEHAVIORS.md](../BEHAVIORS.md) §3.1
  defines it: an API error, or the turn's last test, build or deploy
  command failed. `stopped` is a turn you interrupted (Esc, or Claude
  reporting itself idle, [ADAPTERS.md](../ADAPTERS.md) §3).
- **Tool categories.** `shell` (Claude's `Bash`, Codex's `shell` and
  `exec_command`), `edit` (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`,
  `apply_patch`), `read` (`Read`), `search` (`Grep`, `Glob`), `web`
  (`WebFetch`, `WebSearch`), `subagent` (`Task`, `Agent`), `mcp` (any
  `mcp__…`) and `other`. The duration comes from pairing the tool's
  `PreToolUse` and result by `tool_use_id`.
- **Topics** are the tags from [ADAPTERS.md](../ADAPTERS.md) §3: `tests`,
  `build`, `deploy`, `docs`. A topic's state is `passing` or `failing`
  after its last run, and `edited` for docs.
- **Error classes.** A turn's are [ADAPTERS.md](../ADAPTERS.md) §2's
  (`rate_limit`, `api_error`, …). A tool's are `exit_code` (a command
  exited with an error), `timeout`, `denied` and `other`.
- **`failed_before`** counts per thread and topic. A pass sets it back to
  0; a new turn doesn't.
- **Heartbeat.** While no thread is working, the core sends one when an
  hour has passed with no event, and every hour after that until one
  arrives, so the brain gets a chance to act when nothing else would wake
  it.
- **Codex** has no failure hook, so its tool uses are `unknown` and never
  wake the brain, and its turns are never `failed`
  ([ADAPTERS.md](../ADAPTERS.md) §3).

A tool use as the core hands it over:

```json
{"kind":"tool_use","received_at_ms":1790000540000,"line":"claude's tests failed again on \"agent-work-visibility\", 2 in a row.","reaction":null,"wakes_brain":true,"facts":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01Cc3","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":49300,"failed_before":1}}
```

## 5. Named bands

No number reaches Jev that it would have to compare
([HARNESS.md](HARNESS.md) §8). The core names them:

| Band | Values |
| --- | --- |
| `length` (a turn), `took` (a tool) | `short` under 15 s, `long` up to a minute, `very long` past it |
| `gap` (turn start), `since_last` (pokes) | `right after` under 2 min, `a while` under an hour, `a long break` past it; none the first time |

## 6. Which events wake the brain

Every event goes into the transcript and gets its line in HISTORY. One
wakes the brain only when its kind says so (§4), and never:

- while something needs you, or in quiet mode
  ([BEHAVIORS.md](../BEHAVIORS.md) §3.2, §4);
- without Jev's key ([HARNESS.md](HARNESS.md) §7).

There are no cooldowns on the brain beyond these.

## 7. Rule reactions

The rules' moments are a `cheer` for a finished turn and a `wiggle` for
a tap or a poke streak ([BEHAVIORS.md](../BEHAVIORS.md) §3). The core
decides one at the same moment as its event, so it goes in the event's
`reaction`, as its line. The brain can't make these slower or different;
it only learns of them.

Sessions starting and ending, and routine tool uses, are the core's own
bookkeeping: they never become events, and appear only as counts in other
lines and in the status line.

## 8. Lines

The core writes every event's line, and its reaction's, when it builds
the event (`app/BoopKit/Core/Event.swift`), from the shown facts only.
One template per kind, each with a test:

| Kind | Line |
| --- | --- |
| Turn start | `claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.` The project is left out when it's the name; `, resumed` is added for a resumed session |
| Turn end | `claude finished turn 7 on "…": done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.` `failed (rate limit)` or `stopped` in place of `done` |
| Tool use | `claude's tests failed on "…".`, `… failed again on "…", 3 in a row.`, `… passed on "…" after 3 failures in a row.` An error other than `exit_code` is added in brackets (`(timed out)`). |
| Pokes | `You poked Boop 5 times in 3 s, again a while after the last time.` |
| Heartbeat | `Nothing has happened for 1 hour.`, `… for 3 hours.` |
| Tap | `You tapped Boop.` |
| Needs you | `claude needs you on "…".` |
| Reaction | `Boop cheered on its own.`, `Boop wiggled on its own.` |

**The status line,** the end of HISTORY, is the core's too:
`Working now: "fix-nav" (codex, landing), for 3 min.`, or `Working now:
nothing else.` The thread NOW is about is left out.

In HISTORY, as the harness places them:

```
18 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
11 min ago: claude's tests failed on "agent-work-visibility".
6 min ago: claude's tests failed again on "agent-work-visibility", 3 in a row.
4 min ago: You tapped Boop.
  Boop wiggled on its own.
3 min ago: codex started turn 1 on "fix-nav" (landing).
2 min ago: claude's tests passed on "agent-work-visibility" after 3 failures in a row.
Working now: "fix-nav" (codex, landing), for 3 min.
```

### 8.1 Words

The lines use a few words Jev couldn't know. They're explained in the
second part of the state's READING section ([HARNESS.md](HARNESS.md) §6.1),
which is kept here, next to the lines, so a change to one changes the
other in the same place:

```
Words the lines use:
- claude and codex are the person's coding agents. "claude's tests"
  means tests that claude ran.
- A thread is one conversation with an agent. It's written as its name
  in quotes, then its project in brackets: "fix-nav" (landing) is the
  thread fix-nav in the project landing. The name is the workspace the
  agent works in, so two threads in one project have different names.
  The project is left out when it's the same as the name.
- A turn is one request to a thread, from the person's prompt to the
  agent's answer, numbered within its thread. It ends done, failed, or
  stopped (the person interrupted it).
- Tests, build, deploy and docs are what an agent's command or edit was
  about. Failed means the command ended with an error.
- "N in a row" counts failures of the same thing in that thread. A
  comeback is something that passed after failing.
- A short turn is under 15 s, a long one up to a minute, a very long one
  more.
```

## 9. Privacy

No prompt text, commands, tool input or output, file contents or agent
messages reach an event. The only names are the project's and the
workspace's (§3), and the agent's and subagent's type.
