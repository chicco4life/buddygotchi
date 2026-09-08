# Ideas

Exploratory. One idea per section, worked far enough to know whether it is
real and what it would cost. Nothing here is committed until it moves into
`VISION.md` or a UX document.

---

## Idea 1: A friend who knows what you are working on

### The moment

You have been trying to get one test to pass for forty minutes. The agent
runs it, it fails, the agent edits, runs it again. On the tenth run it goes
green. Today the buddy does the same modest hop it does for every completed
turn. It should lose its mind: the big cheer, the loud chirp, and a line like
"TEN tries. Nice job on the tests."

More moments of the same kind:

- You open a project you have not touched in three weeks. "Oh, the landing
  page! Back at it?"
- You are in the file the agent has edited forty times this month. "That
  file again. It really doesn't want to behave."
- It is 1 a.m. and you are still going. "Late one. We're close, right?"
- The build has been red all afternoon and finally goes green. A bigger
  cheer than a green build after a green build.
- The agent hits a rate limit for the third time today. "It's hungry again.
  Might be a good time to stretch."
- You always ask agents to write tests first. The buddy notices, and one day
  says, "You and your tests. I respect it."

None of these need the buddy to understand code. They need it to remember
what has been happening, spot a pattern, and say one short thing about it in
its own voice. That is what a friend at the next desk does.

### What the buddy would need to know

Three layers, from fast-moving to slow.

1. **Working memory** (this session). What is being attempted right now, how
   many times, with what outcome. Retry counts per goal, elapsed time, the
   current project, errors seen.
2. **Episodic memory** (recent weeks). Structured facts about sessions: this
   project, this many turns, tests fought with, builds broken and fixed,
   late nights, tools used. Enough to notice "again."
3. **A profile** (durable). What a friend would remember: the projects you
   have, the stacks you use, your rituals (tests first, commits often), your
   hours, the things you have said you like or hate, and its opinions about
   each agent. Small, human-readable, and shown to you on request.

The buddy already keeps a seed of the third layer. The current app tracks
per-project stats, per-agent stats, an hour-of-day histogram, and keepsakes.
This idea grows that into something that can carry a conversation.

### Are we "in the flow of tokens"? Yes, already

The question was whether Claude Code, Codex, and Cursor let us see what is
going on, or whether we need another source. Checked against the hook
references in `research/eng/reference/` and against the files on this
machine: all three put the content stream on the wire through hooks we
already install. Boop's hook script receives it today and forwards only a
tool name and a truncated hint.

| Signal | Claude Code | Codex | Cursor |
| --- | --- | --- | --- |
| User prompt text | yes, `UserPromptSubmit` | yes, `UserPromptSubmit` | yes, `beforeSubmitPrompt` (with attachments) |
| Tool call with full arguments | yes, `PreToolUse` `tool_input` | yes, `PreToolUse` `tool_input` | yes, `preToolUse`, `beforeShellExecution` (full command), `beforeMCPExecution` |
| Tool result or output | yes, `PostToolUse` `tool_response`, plus `PostToolUseFailure` with error and duration | yes, `PostToolUse` `tool_response` | yes, `afterShellExecution` (full terminal output, duration), `postToolUse` `tool_output`, `postToolUseFailure` |
| Agent's final message | yes, `Stop` `last_assistant_message` | yes, `Stop` `last_assistant_message` | yes, `afterAgentResponse` text |
| Agent's thinking | no, only in transcript | no, only in log | yes, `afterAgentThought` |
| File edits | via `PostToolUse` on Edit and Write | via `PostToolUse` on `apply_patch` | yes, `afterFileEdit` |
| Turn boundaries | yes | yes, with `turn_id` | yes, `stop` with status |
| Errors and rate limits | yes, `StopFailure` with typed error | partial | partial, `stop` status |
| Working directory and session id | yes | yes | yes |
| Path to the full transcript | yes, `transcript_path` on every payload | yes, `transcript_path` when available | no |

So the answer to "does the agent support this" is yes for all three, without
asking anyone for permission or scraping anything. The tenth-try example
needs exactly two of these rows: the tool call (is this a test command, in
which project) and the tool result (did it pass). Both are in every hook
payload we already receive.

### Where else the information lives

Sources beyond hooks, in order of usefulness. None replace hooks; some fill
gaps.

1. **Transcripts on disk.** Claude Code writes one JSONL per session under
   `~/.claude/projects/<project>/`, with every tool use, tool result, and
   per-message token usage. Codex writes rollout logs under
   `~/.codex/sessions/<date>/` with user messages, agent messages, tool calls
   and outputs, task start and complete markers, and running token counts.
   Both are readable after the fact, which makes them the right source for
   the nightly reflection pass: "what happened today" without having to keep
   anything live. Cursor keeps its conversations in a local SQLite store
   inside its application support directory; not present on this machine,
   and the least stable of the three.
2. **Git.** Commits, branches, and diffs are the most honest signal of what
   someone is actually working on and finishing. Boop already has the
   working directory from every hook. Watching the repo there gives project
   identity, commit rhythm, "you shipped," and "you reverted." No agent
   involvement needed, and it works for hand-written code too.
3. **Ask the agent to tell us.** The buddy already exposes a small tool
   interface to agents (introduce, express, report effort, draw). Add one
   more: a way for the agent to report what it is trying to do and how it
   went, in one structured line. Pair it with an instruction in the
   installed hook context so the agent does it at natural points. This is
   the highest-quality signal because the agent knows what "the test" is,
   and the least reliable because agents forget. Use it as a bonus on top of
   inference, never as the floor.
4. **The agent's own last message.** The `Stop` payload carries the agent's
   closing text on all three agents. A local model can turn "I fixed the
   failing test in AuthTests by correcting the mock" into a one-line fact
   without the buddy ever reading the code.
5. **Telemetry export.** Claude Code can export OpenTelemetry metrics and
   events (tool results with success and duration, prompt submissions, API
   token counts) to a local collector. It duplicates what hooks give us with
   more setup, so it is a fallback if hooks ever go away, not a first choice.
6. **File system watchers** on test result files, build outputs, and lock
   files. Cheap, framework-specific, brittle. Only for gaps.

### The privacy line, and how to hold it

`VISION.md` says file contents, code, and prompt text are never read. This
idea needs the stream. Both can be true if the rule becomes **see, extract,
forget**: raw payloads are parsed on the Mac the moment they arrive, turned
into structured facts, and discarded. Nothing raw is persisted, nothing raw
is shown, and nothing raw goes to the local model.

A structured fact for the tenth-try moment looks like:

```
{ project: "buddygotchi", action: "test", runner: "swift test",
  attempt: 10, outcome: "pass", elapsed_min: 41, agent: "claude-code" }
```

That is enough for the buddy to say something specific and nothing more.

Proposed levels, user-selectable, with the middle as default:

| Level | What the buddy keeps | What it can say |
| --- | --- | --- |
| Events only | Turn boundaries, tool classes, outcomes | "Nice, that one took a while." |
| Facts (default) | Structured facts as above, project names, runners, file extensions, retry counts, error classes | "Ten tries. Nice job on the tests." |
| Summaries (opt-in) | One-line summaries of each turn from the agent's closing message, produced by the local model and kept for 30 days | "The auth mock again? You fixed that last Tuesday too." |

At every level the profile is a page in the app titled something like "what
your buddy knows about you," fully readable and deletable line by line. The
test for whether a fact belongs there: would a friend remember it, and would
you be fine hearing them say it out loud.

Things that never enter memory at any level: file contents, code, secrets,
the text of prompts beyond tone and topic, anything about people other than
the owner.

If this idea moves forward, principle 6 in `VISION.md` should be amended
from "never read" to "see, extract, forget," with the levels above.

### How the pieces fit

```
hooks (all three agents)
   │  raw payload, in memory only
   ▼
extractor            classify tool call and result; normalize commands;
   │                 detect runner, pass/fail, error class; project id
   ▼
working memory       per-session goal signatures and attempt counters
   │                 (lives in the reducer, drives effort and cheer size)
   ▼
occasion detector    rules first: hard-won pass, long red streak ends,
   │                 back after absence, same file again, late night,
   │                 nth rate limit today, ritual observed
   ▼
episodic log         structured facts, 30 days, local SQLite
   │
   ▼  nightly, plugged in and idle
reflection           local model reads the day's facts and the agent's
   │                 closing messages, writes 3 to 5 profile lines,
   │                 adjusts personality traits by small amounts
   ▼
profile              small, readable, deletable
   │
   ▼
voice                occasion + 3 profile facts + personality → one line
```

The occasion detector is the heart of it. It is rules, not a model, so it is
fast, predictable, and testable. The model only writes the sentence.

### Detecting the tenth try

Concrete enough to build.

- A **goal signature** is the normalized command plus the project. Strip
  paths, flags that vary, and timestamps. `swift test --filter ReducerTests`
  and `swift test --filter ReducerTests 2>&1` are the same goal.
- Each tool call whose command matches a known runner (test, build, lint,
  typecheck, a script named test or build) opens or continues a goal.
- The tool result gives the outcome. Exit status where the payload has it;
  otherwise runner-specific patterns on the first and last few hundred bytes
  of output. Outputs can be huge; cap what the extractor reads.
- A goal's attempt counter increments on each failure and resets on a pass.
  A pass after N failures with M minutes elapsed fires **hard-won pass** with
  intensity from N and M. One failure then a pass is normal. Five is a
  cheer. Ten is the dance.
- Effort feeds the existing effort tiers, so the buddy is visibly sweating
  during the streak and the payoff scales with it. This part of the reducer
  already exists.

Same shape for builds, deploys, and lint. Different shape for "same file
again" (count edits per path per week) and "back after absence" (the
per-project last-seen timestamp the app already keeps).

### Likes, dislikes, and rituals

Two sources, treated differently.

- **Said out loud.** Prompt text is reduced to tone and topic on arrival.
  Strong sentiment attached to a topic ("I hate writing regex," "love how
  clean this is") becomes a candidate profile line. Candidates need to
  recur before they are kept. One grumble is a mood; three is a dislike.
- **Shown by behavior.** Always asks for tests first. Never approves network
  commands. Works Sunday mornings. Reaches for Codex for refactors and
  Claude for new features. These come from the episodic log in the nightly
  pass and are phrased as observations, not judgments.

The buddy uses these sparingly. A friend who mentions your habits every hour
is not a friend. Budget: one profile-based remark per session at most, and
never during a stuck or needs-you moment.

### What could go wrong

- **Wrong on the facts.** "Nice job on the tests" when they failed is worse
  than silence. The extractor must prefer "unknown" to a guess, and the
  occasion detector must require a clean pass signal.
- **Creepy instead of warm.** Mitigations: the levels, the readable profile,
  the remark budget, and phrasing that observes rather than analyzes.
- **Too much data through the hook.** Full tool outputs on every call could
  be megabytes. Cap bytes at the hook script, extract on the Mac, keep
  nothing raw.
- **Hooks change.** Payload fields drift across agent releases. The
  extractor degrades to events-only when a field is missing, and the buddy
  says so once.
- **The local model over-reaches.** It only ever sees structured facts and
  optional one-line summaries, never raw text, so the worst case is a flat
  line, not a leak.

### Open questions

- Should "facts" be the default, or should the buddy ask on first run with a
  one-screen explanation? Leaning toward asking once, defaulting to facts.
- How much of the extractor is shared across agents versus per-agent? The
  command and output shapes differ enough that runner detection is shared
  and payload parsing is per-agent.
- Does the profile ever leave the Mac? No. It is not part of the leaderboard
  and not part of the device's travel-mode state.
- Nightly reflection needs the local model to read a day of facts. Is that
  within the small-model budget, or does the reflection pass get a larger
  model than the live voice? Probably the latter, since it runs plugged in
  and idle.

### Smallest thing to build first

1. Widen the installed hook script to forward tool name, full command, exit
   status or error, and the first and last 512 bytes of output, for
   `PostToolUse` and its equivalents on all three agents.
2. Add the extractor and a runner table for the top ten test and build
   commands.
3. Add goal signatures and attempt counters to the reducer, and wire
   hard-won pass into the existing celebrate intensity.
4. Give the voice the occasion and watch whether "ten tries, nice job on the
   tests" lands.

That is one hook change, one parser, one reducer change, and no new storage.
If it feels like a friend, build the episodic log and the profile next.
