# Boop: harness events

Updated 2026-09-27. What the core hands the harness: the events, what
they carry, which wake the brain, and the lines they become in the
state. How the harness uses them is in [HARNESS.md](HARNESS.md); what Boop
decides about them is in [DECISIONS.md](DECISIONS.md), which never reads
an event's fields, only its line.

## 1. What an event is

The core turns hook events ([ADAPTERS.md](../ADAPTERS.md)) into five kinds
of event: **turn start**, **turn end**, **tool use**, **pokes** and
**heartbeat**. It builds each one whole, with its facts already worked
out and named, reacts to it by rule, and decides whether it wakes the
brain. The harness only records it and renders its line.

## 2. The envelope

Every event has the same outer fields; only `detail` differs by kind.

| Field | Shown to Jev | Meaning |
| --- | --- | --- |
| `thread` | ✓ | Which agent thread it's about (§3). `null` for pokes and heartbeats |
| `detail` | ✓ | The kind's own fields (§4) |
| `automatic_reaction` | ✓ | What Boop already did by rule, before the brain was asked: `cheer`, `wiggle` or `none` |
| `woke_brain` | — | Whether it opened a pass (§6) |
| `received_at_ms` | — | When the app received it, in ms since the epoch. Clock times, relative times and bands (§5) are worked out from it |

Fields not shown to Jev are for matching, timing and logs. Jev only ever
sees names, named bands and small counts: never IDs or raw durations.

## 3. The thread

| Field | Shown to Jev | Example | Meaning |
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

| Kind | `detail`, shown to Jev | `detail`, hidden | Wakes the brain |
| --- | --- | --- | --- |
| **Turn start** (`turn_start`) | `resumed` (the session was resumed), `gap` since this thread's last turn | — | Always |
| **Turn end** (`turn_end`) | `outcome`: `done`, `failed` or `stopped`; `error` class when failed; `length`; `tools` and `tools_failed` (counts for the turn); `topics`: each topic's last state this turn; `comeback`: a topic that passed after failing this turn, if one did | `length_ms` | Always |
| **Tool use** (`tool_use`) | `tool` category; `topic`; `result`: `ok`, `failed` or `unknown`; `error` class when failed; `took`; `failed_before`: failures in a row of this topic in this thread just before this one | `tool_name`, `tool_use_id`, `took_ms` | Only with a topic, and when it failed, or passed after at least one failure |
| **Pokes** (`pokes`) | `count`, `seconds` (the window they came in), `since_last` streak | — | As [BEHAVIORS.md](../BEHAVIORS.md) §3.3 allows a poke streak |
| **Heartbeat** (`heartbeat`) | `idle_hours`: whole hours since the last event | — | Always |

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

A tool use as it's recorded:

```json
{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"tool_use":{"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01Cc3","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":49300,"failed_before":1}},"automatic_reaction":"none","woke_brain":true}
```

## 5. Named bands

No number reaches Jev that it would have to compare
([HARNESS.md](HARNESS.md) §7). The core names them:

| Band | Values |
| --- | --- |
| `length` (a turn), `took` (a tool) | `short` under 15 s, `long` up to a minute, `very long` past it |
| `gap` (turn start), `since_last` (pokes) | `right after` under 2 min, `a while` under an hour, `a long break` past it; none the first time |

## 6. Which events wake the brain

Every event goes into the transcript. One wakes the brain only when its
kind says so (§4), and never:

- while something needs you, or in quiet mode
  ([BEHAVIORS.md](../BEHAVIORS.md) §3.2, §4);
- without Jev's key ([HARNESS.md](HARNESS.md) §6).

There are no cooldowns on the brain beyond these.

## 7. Asides and automatic reactions

**Asides.** A single tap and "needs you" are the rules' alone, so the
brain can't make them slower or different. They go into the transcript
as `aside` entries so the state shows them, but never wake the brain.

**Automatic reactions** are the rules' moments: a `cheer` for a finished
turn, a `wiggle` for a tap or a poke streak ([BEHAVIORS.md](../BEHAVIORS.md)
§3). Each is recorded as a `boop` entry `by: automatic` under the event
or aside it answered.

Sessions starting and ending, and routine tool uses, are the core's own
bookkeeping: they show up only as counts and in the threads line.

## 8. Lines

Each event, aside and automatic reaction has one template
(`app/BoopKit/Harness/StateText.swift`):

| Entry | Line |
| --- | --- |
| Turn start | `claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.` The project is left out when it's the name; `, resumed` is added for a resumed session |
| Turn end | `claude finished turn 7 on "…": done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.` `failed (rate limit)` or `stopped` in place of `done` |
| Tool use | `claude's tests failed on "…".`, `… failed again on "…", 3 in a row.`, `… passed on "…" after 3 failures in a row.` An error other than `exit_code` is added in brackets (`(timed out)`) |
| Pokes | `You poked Boop 5 times in 3 s, again a while after the last time.` |
| Heartbeat | `Nothing has happened for 1 hour.`, `… for 3 hours.` |
| Tap | `You tapped Boop.` |
| Needs you | `claude needs you on "…".` |
| Automatic reaction | `Boop cheered on its own.`, `Boop wiggled on its own.` In NOW: `Boop already cheered on its own.`, `Boop did nothing on its own.` |
| Threads working now | `Working now: "fix-nav" (codex, landing), for 3 min.`, `Working now: nothing else.` The thread NOW is about is left out |

In HISTORY, as the harness renders them:

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
second part of the state's READING section ([HARNESS.md](HARNESS.md) §5),
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
