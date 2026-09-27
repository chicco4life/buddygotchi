# Boop: harness and brain

Updated 2026-09-27. How something an agent does becomes a question for
the brain, and how its answer becomes something Boop does.

This spec is ahead of the code: the harness is being reworked to match it
([PLAN.md](PLAN.md) §3, "Harness rework"). Talk and memory writes are out
of this version and come back later.

## 1. What this is

Boop has one brain, TypeSafe's **Jev** ([docs](https://docs.typesafe.ai/api)).
Jev doesn't write text: it reads a state and answers typed questions with
probabilities, all in one request of about 0.2–0.3 s. The **harness** is
the small, generic code around it:

```
 core ──► event ──► transcript ──► Jev's state (text) + questions ──► Jev ──► answers ──► actions ──► device
                        ▲                                                                   │
                        └──────────────── what Boop did is appended ◄──────────────────────┘
```

1. The core turns hook events into **events** (§2) and has already
   reacted to them with plain rules (a cheer, a wiggle), so the brain only
   adds to what Boop does, and never slows the rules down.
2. The **transcript** (§4) keeps every event, and everything Boop did, as
   typed entries.
3. For each event that wakes the brain, the harness renders the
   transcript as one plain-text **state** (§5) and asks Jev a fixed set of
   **questions** (§6).
4. The answers become at most two calls: `mood`, which swaps Boop's
   current mood, and `react`, which makes the mumble. Each action checks
   its own rules. What they did is appended to the transcript, so the
   next state includes it.

The harness doesn't know what an action does. It never builds Minion
speech or talks to the device: that's the actions' job
([ARCHITECTURE.md](ARCHITECTURE.md) §3.4).

## 2. Events

The core builds five kinds of event: **turn start**, **turn end**, **tool
use**, **pokes** and **heartbeat**. They share one envelope; only `detail` differs.

### 2.1 The envelope

| Field | Shown to Jev | Meaning |
| --- | --- | --- |
| `thread` | ✓ | Which agent thread it's about (§2.2). `null` for pokes |
| `detail` | ✓ | The kind's own fields (§2.3) |
| `automatic_reaction` | ✓ | What Boop already did by rule, before the brain was asked: `cheer`, `wiggle` or `none`. So the brain doesn't do it twice |
| `woke_brain` | — | Whether it opened a pass (§2.5) |
| `received_at_ms` | — | When the app received it, in ms since the epoch. Clock times, relative times and bands (§2.4) are worked out from it |

Fields not shown to Jev are for matching, timing and logs. Jev only ever
sees names, named bands and small counts: never IDs or raw durations.

### 2.2 The thread

| Field | Shown to Jev | Example | Meaning |
| --- | --- | --- | --- |
| `name` | ✓ | `agent-work-visibility` | The workspace, or the project when there's none |
| `agent` | ✓ | `claude`, `codex` | Which agent |
| `subagent` | ✓ | `Explore` | A Claude subagent's type, for events from inside one |
| `turn` | ✓ | `7` | Which turn of the thread this is, counted since Boop first saw it |
| `project` | ✓ (with the name) | `buddygotchi` | The project ([ADAPTERS.md](ADAPTERS.md) §3) |
| `workspace` | — | `agent-work-visibility` | The worktree folder, or else the git branch; none on the default branch or outside git |
| `session` | — | `a1b2c3` | The agent's session ID, for matching only |

**The workspace name** tells two threads in the same project apart. It
comes from the worktree folder, or else the branch in `.git/HEAD`, read
with the project name and cached the same way. It's cleaned before
anything sees it: a leading `word/` (`claude/`) and a trailing hash
(`-7a22ea`) are dropped, it's lowercased, only `a-z`, `0-9` and `-` are
kept, and it's cut to 40 characters. An agent chooses its branch names, so
this is the one field in Jev's state an agent could put words into; the
cleaning keeps it a name.

### 2.3 The kinds

| Kind | `detail`, shown to Jev | `detail`, hidden | Wakes the brain |
| --- | --- | --- | --- |
| **Turn start** (`turn_start`) | `resumed` (the session was resumed), `gap` since this thread's last turn | — | Always |
| **Turn end** (`turn_end`) | `outcome`: `done`, `failed` or `stopped`; `error` class when failed; `length`; `tools` and `tools_failed` (counts for the turn); `topics`: each topic's last state this turn; `comeback`: a topic that passed after failing this turn, if one did | `length_ms` | Always |
| **Tool use** (`tool_use`) | `tool` category; `topic`; `result`: `ok`, `failed` or `unknown`; `error` class when failed; `took`; `failed_before`: failures in a row of this topic in this thread just before this one | `tool_name`, `tool_use_id`, `took_ms` | Only with a topic, and when it failed, or passed after at least one failure |
| **Pokes** (`pokes`) | `count`, `seconds` (the window they came in), `since_last` streak | — | As [BEHAVIORS.md](BEHAVIORS.md) §3.3 allows a poke streak |
| **Heartbeat** (`heartbeat`) | `idle_hours`: whole hours since the last event | — | Always |

- **Heartbeat.** While no thread is working, the core sends one when an
  hour has passed with no event, and every hour after that until one
  arrives. It gives the brain a chance to let a mood go (§6.1) when
  nothing else would wake it. Its `thread` is `null`.

- **Outcome.** `failed` is as [BEHAVIORS.md](BEHAVIORS.md) §3.1 defines
  it: an API error, or the turn's last test, build or deploy command
  failed. `stopped` is a turn you interrupted (Esc, or Claude reporting
  itself idle, [ADAPTERS.md](ADAPTERS.md) §3).
- **Tool categories.** `shell` (Claude's `Bash`, Codex's `shell` and
  `exec_command`), `edit` (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`,
  `apply_patch`), `read` (`Read`), `search` (`Grep`, `Glob`), `web`
  (`WebFetch`, `WebSearch`), `subagent` (`Task`, `Agent`), `mcp` (any
  `mcp__…`) and `other`.
- **Topics** are the tags from [ADAPTERS.md](ADAPTERS.md) §3: `tests`,
  `build`, `deploy`, `docs`. A topic's state is `passing` or `failing`
  after its last run, and `edited` for docs.
- **Error classes.** A turn's are [ADAPTERS.md](ADAPTERS.md) §2's
  (`rate_limit`, `api_error`, …). A tool's are `exit_code` (a command
  exited with an error), `timeout`, `denied` and `other`.
- **Codex** has no failure hook, so its tool uses are `unknown` and never
  wake the brain, and its turns are never `failed`
  ([ADAPTERS.md](ADAPTERS.md) §3).
- **`failed_before`** counts per thread and topic. A pass sets it back to
  0; a new turn doesn't.

### 2.4 Named bands

No number reaches Jev that it would have to compare
(§7). The core names them:

| Band | Values |
| --- | --- |
| `length` (a turn), `took` (a tool) | `short` under 15 s, `long` up to a minute, `very long` past it (`Input.Length`) |
| `gap` (turn start), `since_last` (pokes) | `right after` under 2 min, `a while` under an hour, `a long break` past it; none the first time |

### 2.5 Which events wake the brain

Every event goes into the transcript. One opens a **pass** only when its
kind says so (§2.3), and never:

- while something needs you, or in quiet mode ([BEHAVIORS.md](BEHAVIORS.md)
  §3.2, §4);
- without Jev's key (§6.4).

Otherwise whether Boop mumbles is Jev's call every time: there are no
cooldowns on the brain.

**Asides.** A single tap and "needs you" are the rules' alone, so the
brain can't make them slower or different. They go into the transcript
so the next state shows them, but never open a pass. Sessions starting
and ending, and routine tool uses, are the core's own bookkeeping: they
show up only as counts and in the threads section (§5).

## 3. A pass, step by step

1. **An event arrives** from the core, with its automatic reaction. Both
   are appended to the transcript.
2. **Wait its turn.** One pass runs at a time. A newer event replaces one
   that's waiting; the replaced one stays in the transcript and shows up
   in the next state's HISTORY.
3. **Render the state** (§5) from the transcript and the current mood,
   and build the questions (§6) from the `mood` and `react` actions'
   definitions.
4. **Ask Jev,** within the deadline (§6.4).
5. **Read the answers** (§6.2): at most one `mood` call, and at most one
   `react` call with a feeling and at most one word.
6. **Hand them to their actions,** `mood` first. Each checks the call
   against its own rules and may still drop it: `mood` more often than
   its limit (§6.2), `react` in quiet mode or while something needs you.
7. **Record.** A `pass` entry with every answer and its probabilities,
   then a `boop` entry for each thing an action actually did. A dropped or
   silent pass leaves only its `pass` entry, which Jev never sees.

## 4. The transcript

One append-only list of typed entries, owned by the harness
(`app/BoopKit/Harness/Transcript.swift`). It's the record: Jev's state is
rendered from it (§5), and `debug.jsonl` logs it (§8).

| Entry | Holds | In Jev's state |
| --- | --- | --- |
| `event` | An event as the core built it (§2) | As a line, when it woke the brain |
| `aside` | A tap, or an agent needing you | As a line |
| `boop` | What Boop did: `by` (`automatic` or `brain`), the `action` (`cheer`, `wiggle`, `mumble`, `mood`), a mumble's feeling and word, a mood change's `from` and `to`, and a moment's `moment_id`. `for` is the entry it answered | Under its entry's line, with its moment's status (§5) |
| `pass` | What Jev was asked and answered: every answer with its probabilities, the call made, why it was dropped if it was, and the latency | Never |

In Swift, each entry is a sequence number, `received_at_ms` and a body:

```swift
enum Body {
    case event(Event)      // thread, detail, automaticReaction, wokeBrain
    case aside(Aside)      // .tap, .needsYou(Thread)
    case boop(BoopAction)  // forSeq, by, action, feeling, word
    case pass(Pass)        // forSeq, answers, call, dropped, latencyMs
}
```

As `debug.jsonl` logs them, one thread whose tests fail three times and
then pass (entries 9 to 16 are left out):

```jsonl
{"seq":1,"received_at_ms":1790000000000,"event":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"turn_start":{"resumed":false,"gap":"right after"}},"automatic_reaction":"none","woke_brain":true}}
{"seq":2,"received_at_ms":1790000000210,"pass":{"for":1,"answers":{"react":{"choice":"none","p":{"none":0.82,"curious":0.09,"happy":0.05,"excited":0.02,"proud":0.01,"annoyed":0.01}},"mood":{"choice":"cheerful","p_choice":0.93},"word.about":{"choice":"none","p_choice":0.71},"word.feeling":{"choice":"none","p_choice":0.55}},"call":null,"dropped":null,"latency_ms":210}}
{"seq":3,"received_at_ms":1790000060000,"event":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"tool_use":{"tool":"edit","tool_name":"Edit","tool_use_id":"toolu_01Aa1","topic":null,"result":"ok","error":null,"took":"short","took_ms":120,"failed_before":0}},"automatic_reaction":"none","woke_brain":false}}
{"seq":6,"received_at_ms":1790000540000,"event":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"tool_use":{"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01Cc3","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":49300,"failed_before":1}},"automatic_reaction":"none","woke_brain":true}}
{"seq":7,"received_at_ms":1790000540230,"pass":{"for":6,"answers":{"react":{"choice":"annoyed","p":{"annoyed":0.58,"none":0.27,"curious":0.09,"happy":0.03,"excited":0.02,"proud":0.01}},"mood":{"choice":"cheerful","p_choice":0.72},"word.about":{"choice":"tests","p_choice":0.66},"word.feeling":{"choice":"again","p_choice":0.29}},"call":{"react":{"feeling":"annoyed","word":"tests"}},"dropped":null,"latency_ms":230}}
{"seq":8,"received_at_ms":1790000540231,"boop":{"for":6,"by":"brain","action":"mumble","feeling":"annoyed","word":"tests"}}
{"seq":17,"received_at_ms":1790001080000,"event":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"turn_end":{"outcome":"done","error":null,"length":"very long","length_ms":1079877,"tools":41,"tools_failed":6,"topics":{"tests":"passing","build":"passing"},"comeback":"tests"}},"automatic_reaction":"cheer","woke_brain":true}}
{"seq":18,"received_at_ms":1790001080001,"boop":{"for":17,"by":"automatic","action":"cheer"}}
```

**The current mood** isn't in the transcript: it's one word in the state
directory's `mood` file, which only the `mood` action writes, so it
survives a restart. A new state directory starts `cheerful`. The
transcript records each change.

**Keeping it.** The transcript lives in memory only. Past a thousand
entries the oldest are let go; nothing is summarised.

**Privacy.** No prompt text, commands, tool input or output, file
contents or agent messages go in. The only names are the project's and
the workspace's (§2.2).

## 5. Jev's state

Jev gets one plain-text document with five named sections. The first
three are **static**: files that ship with the app and change only in a
release, so a personality or a mood can be swapped whole. The last two
are **rendered** fresh for every pass from the transcript and the core's
live list of threads. Jev keeps no session and no cache, so relative times
cost nothing to rebuild.

| Section | Kind | Source | Holds |
| --- | --- | --- | --- |
| **GUIDE** | Static | `plan/steering/guide.md` | What Boop is, what it can and can't do, how to read the other sections, and how to choose |
| **PERSONALITY** | Static, chosen in Settings | `plan/steering/personality/<name>.md` (`boop`, the only one for now) | Who this buddy is: character, how often it speaks up, and its Examples |
| **MOOD** | Static, swapped when the mood changes | `plan/steering/mood/<current>.md` | The current mood: how it leans the feelings and words, how often Boop mumbles, and when it would leave this mood |
| **HISTORY** | Rendered | The transcript (§4) | What has happened and what Boop did, oldest first, then the threads working now |
| **NOW** | Rendered | The event this pass is for | The one thing to react to |

The questions (§6) carry the rest: each option's meaning and each
question's own instructions. A fact lives in one place: what a feeling
means is in the `react` question, not in GUIDE or PERSONALITY, and the
Examples are PERSONALITY's, since a different buddy reacts differently.
The runtime reads the static files read-only; `plan/steering/` is their
single source, and the app bundles a copy.

**Personalities replace modes.** Chatty, normal and calm are gone. How
much Boop speaks up is its personality's to say, so a quieter or chattier
Boop is another file in `plan/steering/personality/`, picked by
`personality` in `settings.json` and applied from the next pass.

At 14:23, for the pass on entry 17 above:

```
GUIDE
You decide how Boop reacts to what's happening. Boop is a small creature
on a person's desk that watches their AI coding agents (Claude Code and
Codex) work. Each agent conversation is a thread, named after its
workspace. Boop never approves or blocks anything.
Boop already reacts on its own: it cheers when a turn finishes, wiggles
when tapped, and alerts when an agent needs the person. You only decide
whether it adds a mumble: its own gibberish, in a feeling, with at most
one real word. You also decide whether its mood changes.
How to read this:
- PERSONALITY and MOOD are who Boop is right now. Judge by them.
- HISTORY is what already happened, oldest first. Indented lines are what
  Boop did.
- NOW is the one thing to react to. React to NOW, not to older lines.
- A line marked [PENDING] is still happening on Boop right now.
How to choose:
- Staying quiet is always fine. Don't repeat what Boop just did.
- A mumble is about NOW: its feeling and word should fit it.
- Boop's mood and its mumble go together. A mood changes only when NOW
  gives MOOD's reason to leave it, and then the mumble should fit that
  change: a grumpy Boop doesn't gush, and a cheerful one doesn't sulk
  over one failure.
- Don't add a mumble that says the same as one that's [PENDING]; choose
  none instead. A new mumble waits until Boop is free and is dropped if
  it waits more than 5 s, so when several things are [PENDING], none is
  usually best.

PERSONALITY
Boop is curious, loyal and easily delighted, and a little smug. It
watches the agents' work like a sport: thrilled by wins, openly grumpy
about failures, always on the person's side, never mean about them.
It speaks up when something stands out, and stays quiet during routine
work.
Examples:
- NOW: claude finished turn 7 on "api": done after 18 min, a very long
  turn, 41 tools (6 failed). A comeback on tests.
  → proud, "finally"
- NOW: claude's tests failed again on "api", 3 in a row.
  → annoyed, "tests"
- NOW: claude started turn 2 on "api", right after its last one.
  → none
- NOW: claude finished turn 3 on "api": done after 8 s, a short turn.
  → none
- NOW: You poked Boop 5 times in 3 s.
  → annoyed, "nope"
- NOW: Nothing has happened for 1 hour.
  → none

MOOD
Cheerful. Boop is in good spirits. It enjoys the work and roots for the
agents.
Leans happy and excited, and proud for a hard-won finish. A single
failure gets a shrug: quiet, or curious. Annoyed only when failures
repeat.
Mumbles at wins and at anything that stands out.
Words it likes: yay, nice, finally, hooray.
Leaves this mood (for grumpy) when failures pile up, 3 or more in a row
or a very long turn that fails, or when it's poked again and again.

HISTORY (oldest first; indented lines are what Boop did)
18 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
11 min ago: claude's tests failed on "agent-work-visibility".
9 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, annoyed: "…tests!"
6 min ago: claude's tests failed again on "agent-work-visibility", 3 in a row.
4 min ago: You tapped Boop.
  Boop wiggled on its own.
3 min ago: codex started turn 1 on "fix-nav" (landing).
2 min ago: claude's tests passed on "agent-work-visibility" after 3 failures in a row.
Working now: "fix-nav" (codex, landing), for 3 min.

NOW (14:23, Tuesday)
claude finished turn 7 on "agent-work-visibility": done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.
Boop already cheered on its own.
```

**Rendering rules:**

- **The static sections** are the files as they are, without comments.
  The Examples are written exactly as HISTORY and NOW lines are, so Jev
  compares like with like, and each gives the feeling and word, or
  `none`.
- **Times** are relative: `just now` under a minute, then `N min ago`,
  then `N h ago`.
- **HISTORY** holds the `event` entries that woke the brain, and the
  asides, oldest first: those from the last 10 minutes or since the
  oldest turn still working began, whichever reaches further back, and at
  most the newest 40. A `boop` entry is indented under the line of the
  entry it answered. Its last line lists the other threads working now,
  from the core's live state, with how long each turn has run
  (`Working now: nothing else.` when there are none).
- **NOW** is the event this pass is for, with the clock and weekday, and
  its automatic reaction.
- **`[PENDING]`** ends the line of a `boop` entry whose moment is still
  waiting its turn or playing, as `MomentSchedule` times it
  ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2), looked up by its
  `moment_id` when the state is rendered. A moment a rule cut short reads
  `(cut off)`, and one dropped before it played is left out: it never
  happened. Only moments have a status. The base state (asleep, idle,
  working) and "needs you" are the core's conditions, not things Boop
  did, so they're never HISTORY lines; the threads line and NOW already
  say what they follow from.
- **Hidden:** `pass` entries, events that didn't wake the brain, and every
  field §2 marks hidden never appear.
- **Memory** isn't in the state in this version; it comes back with
  memory writes.
- **One template per line,** in `app/BoopKit/Harness/StateText.swift`,
  each with a test:

| Entry | Line |
| --- | --- |
| Turn start | `claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.` The project is left out when it's the name; `, resumed` is added for a resumed session |
| Turn end | `claude finished turn 7 on "…": done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.` `failed (rate limit)` or `stopped` in place of `done` |
| Tool use | `claude's tests failed on "…".`, `… failed again on "…", 3 in a row.`, `… passed on "…" after 3 failures in a row.` An error other than `exit_code` is added in brackets (`(timed out)`) |
| Pokes | `You poked Boop 5 times in 3 s, again a while after the last time.` |
| Heartbeat | `Nothing has happened for 1 hour.`, `… for 3 hours.` |
| Tap, needs you | `You tapped Boop.`, `claude needs you on "…".` |
| `boop` | `Boop cheered on its own.`, `Boop wiggled on its own.`, `Boop mumbled, proud: "…finally!"`, `Boop mumbled, curious.`, `Boop's mood changed: cheerful → grumpy.`, and `[PENDING]` or `(cut off)` after a moment's. In NOW: `Boop already cheered on its own.`, `Boop is cheering on its own [PENDING]`, `Boop did nothing on its own.` |

**Sizes.** GUIDE is kept within 400 tokens, PERSONALITY within 600 and
MOOD within 150, and 40 history lines come to about 1,200. With the
questions a request is about 3,000 tokens, well inside Jev's 32K. A part
over its budget is logged (`Prompt.Budget`).

## 6. The questions

### 6.1 What's asked

Every pass asks the same four questions, in one request. Jev answers
each on its own against the state, so none can depend on another's
answer, and adding one barely changes the time taken
([TypeSafe](https://docs.typesafe.ai/cookbooks/parallel_questions.md)).
Each names what it's about and what to judge it by, as TypeSafe advises.

| Question | Type | Options | About, judged by |
| --- | --- | --- | --- |
| `mood` | choice | The moods below | NOW and HISTORY, by MOOD's reason to leave and each mood's meaning |
| `react` | choice | `none` and the five feelings below | NOW, by PERSONALITY and MOOD, Examples first |
| `word.about` | choice | `none` and the topic words below | NOW, by PERSONALITY's Examples |
| `word.feeling` | choice | `none` and the exclamations below | NOW, by PERSONALITY and MOOD, Examples first |

**`mood` and `react` are separate questions,** both judged against the
current mood, so on a pass that changes the mood the mumble is still
judged by the old one. GUIDE asks for the two to fit together; the evals
check how often they don't.

**The moods,** two for now. Each is a file in `plan/steering/mood/`
that becomes MOOD when it's current, and each has a short meaning, which
is its criterion in the `mood` question:

| Mood | Meaning (its criterion) | Its file, in short |
| --- | --- | --- |
| `cheerful` | Good spirits: things are going fine, or a struggle just ended well | Leans happy and excited, shrugs off one failure; leaves when failures pile up or it's poked again and again |
| `grumpy` | Fed up: failures have piled up, or it's been poked too much | Leans annoyed, a win gets a grudging happy or proud and never excited, quieter; leaves when something that kept failing works, a long turn finishes cleanly, or a heartbeat says nothing has happened for an hour |

**`react` asks whether and how at once.** A separate yes/no and feeling
could disagree (a "no" with a confident "proud"); one choice can't. Its
options, with the meanings Jev is given:

| Option | Meaning |
| --- | --- |
| `none` | Stay quiet: nothing in NOW is worth a mumble. Not for anything PERSONALITY's Examples mumble for |
| `happy` | Pleased and friendly: a turn went fine, a small win |
| `excited` | Thrilled: something big just went right |
| `proud` | Something long or hard just finished, or finally worked |
| `curious` | Interested or unsure: something new started, or it's not clear how it's going |
| `annoyed` | Irritated: a turn failed, tests keep failing, or it's being poked too much |

Each feeling mumbles in the Voice feeling of the same name
([VOICE.md](VOICE.md) §4).

**The words** are two questions over two short lists, so the two picks
are never near-synonyms: what NOW is about, and an exclamation about it.
They start with eleven of Voice's 40 ([VOICE.md](VOICE.md) §6), the ones
something in the state can ground, and grow as the evals show a need.
The device keeps all 40; the brain offers only these. Each meaning is the
word's criterion, with a `not_for` where two are easily confused:

| Question | Word | Meaning |
| --- | --- | --- |
| `word.about` | `none` | No topic word fits NOW |
| | `tests` | NOW is about tests. Not for a build or a deploy |
| | `build` | NOW is about a build. Not for tests |
| | `deploy` | NOW is about a deploy |
| | `docs` | NOW is about docs |
| `word.feeling` | `none` | No exclamation fits NOW |
| | `finally` | Something worked after failing. Not for a first try |
| | `yay` | A win |
| | `oops` | Something just failed, once. Not for a failure that keeps repeating |
| | `again` | The same thing failed again. Not for a first failure |
| | `ugh` | Frustration: things keep going badly |
| | `nope` | Poked too much, or refusing |
| | `hmm` | Unsure, or something new |

### 6.2 Reading the answers

`mood` and `react` are read as Jev chose; their probabilities are only
recorded, for the evals.

- **The mood changes** when Jev's choice isn't the current mood. So it
  doesn't flicker, the `mood` action changes it **at most once every 10
  minutes** and drops a call that comes sooner.
- **React** with Jev's choice: a feeling makes a mumble, and `none` keeps
  Boop quiet. `none`'s meaning says it isn't for anything PERSONALITY's
  Examples mumble for, so a moment worth a mumble doesn't lose to it just
  because Jev can't settle on one feeling; the evals watch for that.
- **The word,** when Boop reacts, is the likeliest option of
  `word.feeling` if it isn't `none` and its probability is **at least
  0.35**, else the same for `word.about`, else no word. A flat spread
  means Jev is guessing, and no word is better than a guessed one. A line
  has one real word ([VOICE.md](VOICE.md) §6), so the other pick is only
  recorded.
- The word's threshold is tuned by the evals ([EVALS.md](EVALS.md)) and
  pinned in a test.

### 6.3 The request

The state is the text of §5; each option's meaning is its criterion.
Abridged:

```json
{
  "model": "jev-latest",
  "state": "GUIDE\n…\n\nNOW (14:23, Tuesday)\nclaude finished turn 7 on \"agent-work-visibility\": …\nBoop already cheered on its own.",
  "questions": {
    "mood": {
      "type": "choice",
      "criteria": {
        "cheerful": "Good spirits: things are going fine, or a struggle just ended well.",
        "grumpy": "Fed up: failures have piled up, or it's been poked too much."
      },
      "instructions": {"question": "After NOW, what is Boop's mood?", "about": "the NOW and HISTORY sections", "judge_by": "the MOOD section, its reason to leave"}
    },
    "react": {
      "type": "choice",
      "criteria": {
        "none": {"what": "Stay quiet: nothing in NOW is worth a mumble.", "not_for": "Anything PERSONALITY's Examples mumble for."},
        "happy": "Pleased and friendly: a turn went fine, a small win.",
        "excited": "Thrilled: something big just went right.",
        "proud": "Something long or hard just finished, or finally worked.",
        "curious": "Interested or unsure: something new started, or it's not clear how it's going.",
        "annoyed": "Irritated: a turn failed, tests keep failing, or it's being poked too much."
      },
      "instructions": {"question": "How should Boop react to NOW, if at all?", "about": "the NOW section", "judge_by": "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"}
    },
    "word.about": {
      "type": "choice",
      "criteria": {
        "none": "No topic word fits NOW.",
        "tests": {"what": "NOW is about tests.", "not_for": "A build or a deploy."},
        "build": {"what": "NOW is about a build.", "not_for": "Tests."},
        "deploy": "NOW is about a deploy.",
        "docs": "NOW is about docs."
      },
      "instructions": {"question": "If Boop mumbles, which topic word is NOW about?", "about": "the NOW section", "judge_by": "the PERSONALITY section's Examples"}
    },
    "word.feeling": {
      "type": "choice",
      "criteria": {
        "none": "No exclamation fits NOW.",
        "finally": {"what": "Something worked after failing.", "not_for": "A first try."},
        "yay": "A win.",
        "oops": {"what": "Something just failed, once.", "not_for": "A failure that keeps repeating."},
        "again": {"what": "The same thing failed again.", "not_for": "A first failure."},
        "ugh": "Frustration: things keep going badly.",
        "nope": "Poked too much, or refusing.",
        "hmm": "Unsure, or something new."
      },
      "instructions": {"question": "If Boop mumbles, which exclamation fits NOW?", "about": "the NOW section", "judge_by": "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"}
    }
  }
}
```

For that state, answers like `mood: cheerful`, `react: proud`, `word.about: tests 0.61` and `word.feeling: finally 0.58` make no mood change and `react(proud,
"finally")`: a proud mumble with "finally" in it.

### 6.4 Deadline, failures and the key

- **Deadline:** 1.25 s for the whole pass: four times Jev's usual time,
  with room for one retry. A later answer is dropped.
- **Retries:** a 429, a 5xx or a dropped connection is tried once more
  after 0.3 s. Only a failed request's HTTP status is logged, since an
  error body may repeat the request.
- **When Jev fails** or is late, the pass is dropped: Boop does only its
  automatic reactions, and the `pass` entry says why.
- **The key** comes from `BOOP_JEV_KEY`, else, in the menu-bar app only,
  the Keychain. `Boop --headless` and `boopdev` read only the variable,
  so a run from an agent shell never uses the owner's key. The Keychain is
  read off the app's event queue and the main thread the first time it's
  needed, since a Keychain prompt would stall both. Without a key no
  event wakes the brain and Boop does only its automatic reactions, which
  is fine for everyday use; saving one in Settings brings Jev in at once.
  The evals need the key and fail without it ([EVALS.md](EVALS.md)).

## 7. Designing for Jev

Jev is literal and small: good at judging a short, clearly labelled state
against clear options, bad at arithmetic and at reading between the
lines. The evidence behind these rules is in
[ARCHITECTURE.md](ARCHITECTURE.md) §11.

- **Named sections, pointed at by name.** Every question says which
  section it's about and which to judge by.
- **Examples in the state's own lines.** PERSONALITY's Examples are
  written exactly as HISTORY and NOW lines are, so Jev compares like with
  like.
- **No arithmetic:** times are relative ("9 min ago"), and durations and
  gaps arrive as named bands. Counts stay small.
- **Facts worked out beforehand:** "3 in a row" and "a comeback on tests"
  are in the line, so Jev never has to count lines to find them.
- **One question per decision:** whether and how to react is one choice,
  read as Jev chose it; only the word has a floor, since a flat spread
  means no word.
- **Full lists, with options that say what they're not:** "annoyed" is a
  failure or too much poking, "proud" is something hard finishing.

The spirit is [pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/)'s
"if I don't need it, it won't be built".

## 8. Logging

**Debug mode** is `Boop --debug`, in the menu-bar app (`make debug`) or
headless. It prints to the terminal that started the app, as it happens:
each hook with the event the adapter made of it, the core's decisions,
every line sent to the device, and each pass.

Every transcript entry is also one JSON line in the state directory's
`debug.jsonl` (§4), which starts afresh at every launch. A `pass` line
there also holds the state text and the questions it sent, so any pass
can be replayed against Jev. `boopdev watch [FILE]` prints it readably
(the everyday app's by default), following it as it grows.

**The app log** (`boop.log`) gets one line per pass, debug mode or not:
the event kind, the latency and whether Boop mumbled, never the feeling
or word, as in `brain turn_end 240 ms → react`.

## 9. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Event | `app/BoopKit/Core/Event.swift` | The typed event (§2). The core builds it, with its bands and whether it wakes the brain |
| Transcript | `app/BoopKit/Harness/Transcript.swift` | The typed entries (§4) |
| State text | `app/BoopKit/Harness/StateText.swift` | Renders the five sections (§5); pure |
| Steering | `app/BoopKit/Harness/Steering.swift` | Loads GUIDE, the personality and the moods from the bundle, read-only, and checks their budgets |
| Questions | `app/BoopKit/Harness/Tool.swift` | Each action's definition declares its questions and how its arguments are read from the answers (§6.2), so the harness stays generic |
| Brain | `app/BoopKit/Harness/Brain.swift`, `app/BoopKit/Brains/JevBrain.swift` | `answer(state, questions, deadline)`: Jev, or `ScriptedBrain` in tests |
| Harness | `app/BoopKit/Harness/Harness.swift` | One pass running and one waiting (§3) |
| Actions | `app/BoopKit/Actions/` | `mood` (through the mood store, the only writer of the `mood` file) and `react` |
| Moments | `app/BoopKit/App/MomentSchedule.swift` | Times every moment and answers its status by `moment_id` |

