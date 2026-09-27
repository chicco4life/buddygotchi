# Boop: the harness

Updated 2026-09-27. The generic machinery between the core and the brain:
how an event becomes a question for Jev, and how Jev's answers become
something Boop does. What the events are is in [EVENTS.md](EVENTS.md);
what Boop decides, and how, is in [DECISIONS.md](DECISIONS.md); and
[EXAMPLE.md](EXAMPLE.md) follows one turn through all of it. This file
names neither events nor decisions.

This spec is ahead of the code: the harness is being reworked to match it
([PLAN.md](../PLAN.md) §3, "Harness rework"). Talk and memory writes are
out of this version and come back later.

## 1. What this is

Boop has one brain, TypeSafe's **Jev** ([docs](https://docs.typesafe.ai/api)).
Jev doesn't write text: it reads a state and answers typed questions with
probabilities, all in one request of about 0.2–0.3 s. The **harness** is
the small, generic code around it. It knows three contracts and nothing
else:

- **Events in.** The core hands it events. An event knows its own line of
  text and whether it wakes the brain ([EVENTS.md](EVENTS.md)).
- **Decisions out.** Each action declares the questions it needs and how
  its arguments are read from the answers ([DECISIONS.md](DECISIONS.md)).
  The harness asks them all in one request and hands each action its
  call.
- **The brain.** `answer(state, questions, deadline)`: Jev in the app, a
  scripted brain in tests.

It never builds Minion speech, writes a file or talks to the device:
that's the actions' job ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.4). The
brain is never on the event path: the core has already reacted by rule
before the harness sees an event.

## 2. Architecture

```
 agent hooks
     │
     ▼
 ┌──────────── Core (plain rules) ────────────┐
 │ hook ─► Event ─► automatic reaction ───────────────────────────────► device
 └──────────────────┬─────────────────────────┘              (state, cheer, wiggle)
                    │ Event, and whether it wakes the brain
                    ▼
 ┌─────────────────────────────── Harness ──────────────────────────────────────┐
 │                                                                              │
 │  Transcript (typed, append-only) ◄──────────────── record ─────────────┐     │
 │    event · aside · boop · pass                                         │     │
 │        │                                                               │     │
 │        │ render                                                        │     │
 │        ▼                                                               │     │
 │  State text                                                            │     │
 │    static    GUIDE · PERSONALITY · MOOD    ◄── plan/steering/          │     │
 │    rendered  HISTORY · NOW                 ◄── transcript, threads     │     │
 │        │                                                               │     │
 │        │              Questions ◄── each action's definition           │     │
 │        ▼                  │                                            │     │
 │  Brain.answer(state, questions, deadline) ◄────────► Jev               │     │
 │        │                                                               │     │
 │        ▼                                                               │     │
 │  Read answers ─► calls ─► Actions ─── what they did ───────────────────┘     │
 │                              │                                               │
 └──────────────────────────────┼───────────────────────────────────────────────┘
                                ▼
                    mood file, MomentSchedule ─► device (mumbles)
```

## 3. A pass, step by step

1. **An event arrives** from the core, with its automatic reaction. Both
   are appended to the transcript, whether or not the event wakes the
   brain.
2. **Wait its turn.** One pass runs at a time. A newer event that wakes
   the brain replaces one that's waiting; the replaced one stays in the
   transcript and shows up in the next state's HISTORY.
3. **Render the state** (§5) from the transcript, the static files and
   the core's live list of threads, and collect every action's questions.
4. **Ask the brain,** within the deadline (§6).
5. **Read the answers** with each action's readings: at most one call per
   action.
6. **Hand each call to its action,** in the order the actions are
   registered. Each checks the call against its own rules and may still
   drop it.
7. **Record.** A `pass` entry with every answer and its probabilities,
   then a `boop` entry for each thing an action actually did. A dropped or
   silent pass leaves only its `pass` entry, which Jev never sees.

The core and the device never wait for a pass.

## 4. The transcript

The transcript is Boop's record of what happened and what it did. It has
two forms: a **typed list** the app keeps, which is the only thing ever
written, and a **text form** for the state, rendered from the list for
each pass and never stored.

### 4.1 Maintaining it

- **One list, append-only,** owned by the harness
  (`app/BoopKit/Harness/Transcript.swift`) and touched only on its queue.
  Nothing in it is ever changed or removed out of order; a later fact is
  a new entry.
- **Who appends, and when:**

| When | Appended | By |
| --- | --- | --- |
| The core emits an event | `event`, then a `boop` entry `by: automatic` if the rules reacted | The runtime, before the event is submitted, so a pass always finds its own event already there |
| The core handles something alone | `aside`, then its automatic `boop` entry | The runtime |
| A pass finishes | `pass`, then a `boop` entry `by: brain` for each action that did something | The harness, after the actions have run |

- **Order** is arrival order: each entry gets the next sequence number.
  Entries from a pass can land after events that arrived while it ran;
  `for` ties each `boop` and `pass` entry to the entry it answered, so the
  text form puts it in the right place anyway.
- **Keeping it.** In memory only. Past a thousand entries the oldest are
  let go; nothing is summarised. Every entry is also written to
  `debug.jsonl` as it's appended (§8), so a session can be read back.
- **Privacy.** No prompt text, commands, tool input or output, file
  contents or agent messages go in ([EVENTS.md](EVENTS.md) §9 lists the
  only names that do).

### 4.2 The typed form

| Entry | Holds | Written by |
| --- | --- | --- |
| `event` | An event as the core built it ([EVENTS.md](EVENTS.md)) | The runtime |
| `aside` | Something only the rules handle: a tap, "needs you" ([EVENTS.md](EVENTS.md) §7) | The runtime |
| `boop` | Something Boop did: `by` (`automatic` or `brain`), the action and its arguments. `for` is the entry it answered | The runtime for automatic reactions, the harness for the brain's actions |
| `pass` | What the brain was asked and answered: every answer with its probabilities, the calls made, why the pass was dropped if it was, and the latency. `for` is the event it was for | The harness |

Each entry is a sequence number, `received_at_ms` and a body:

```swift
struct Entry { let seq: Int; let receivedAtMs: Int64; let body: Body }

enum Body {
    case event(Event)      // EVENTS.md
    case aside(Aside)      // EVENTS.md
    case boop(BoopAction)  // forSeq, by, action, arguments
    case pass(Pass)        // forSeq, answers, calls, dropped, latencyMs
}
```

As `debug.jsonl` holds them (fields abridged with `…`):

```jsonl
{"seq":1,"received_at_ms":1790000000000,"event":{"thread":{"name":"agent-work-visibility","agent":"claude","turn":7,…},"detail":{"turn_start":{"resumed":false,"gap":"right after"}},"automatic_reaction":"none","woke_brain":true}}
{"seq":2,"received_at_ms":1790000000210,"pass":{"for":1,"answers":{…},"calls":[],"dropped":null,"latency_ms":210}}
{"seq":3,"received_at_ms":1790000060000,"event":{"thread":{…},"detail":{"tool_use":{"tool":"edit","topic":null,"result":"ok",…}},"automatic_reaction":"none","woke_brain":false}}
{"seq":4,"received_at_ms":1790000540000,"event":{"thread":{…},"detail":{"tool_use":{"tool":"shell","topic":"tests","result":"failed","failed_before":1,…}},"automatic_reaction":"none","woke_brain":true}}
{"seq":5,"received_at_ms":1790000540230,"pass":{"for":4,"answers":{…},"calls":[{"react":{"feeling":"annoyed","word":"tests"}}],"dropped":null,"latency_ms":230}}
{"seq":6,"received_at_ms":1790000540231,"boop":{"for":4,"by":"brain","action":"react","feeling":"annoyed","word":"tests"}}
{"seq":7,"received_at_ms":1790000840000,"aside":{"tap":{}}}
{"seq":8,"received_at_ms":1790000840001,"boop":{"for":7,"by":"automatic","action":"wiggle"}}
{"seq":9,"received_at_ms":1790001080000,"event":{"thread":{…},"detail":{"turn_end":{"outcome":"done","length":"very long","comeback":"tests",…}},"automatic_reaction":"cheer","woke_brain":true}}
{"seq":10,"received_at_ms":1790001080001,"boop":{"for":9,"by":"automatic","action":"cheer"}}
```

### 4.3 The text form

For each pass, `StateText` builds the state's HISTORY and NOW sections
(§5) from the list. It's a pure function of the transcript, the core's
live threads and the clock: the same inputs always give the same text,
so a logged pass can be built again exactly. The text is never kept,
except inside that pass's `debug.jsonl` line.

**How it's built, step by step:**

1. **Pick NOW.** The `event` entry the pass is for.
2. **Pick HISTORY's entries.** The `event` entries that woke the brain,
   and the `aside` entries, older than NOW: those from the last 10
   minutes or since the oldest turn still working began, whichever reaches
   further back, then at most the newest 40. Left out: `pass` entries,
   events that didn't wake the brain, and NOW itself.
3. **Attach what Boop did.** Each `boop` entry goes with the entry its
   `for` names, automatic ones first, then the brain's, in sequence
   order. One whose entry wasn't picked is left out with it.
4. **Order** the picked entries oldest first, by sequence number.
5. **Write each line.** An entry becomes `<time>: <its line>`: the time
   is relative to now (`just now` under a minute, then `N min ago`, then
   `N h ago`), and the line is its kind's template, filled from the
   fields shown to Jev ([EVENTS.md](EVENTS.md) §8 for events, asides and
   automatic reactions). Each attached `boop` entry becomes its template
   ([EVENTS.md](EVENTS.md) §8 for automatic ones,
   [DECISIONS.md](DECISIONS.md) §6 for the brain's), indented two
   spaces under its entry's line. Hidden fields never reach a template.
6. **Close HISTORY** with the threads line: every thread working now,
   from the core's live state, except the one NOW is about.
7. **Write NOW:** a heading with the clock and weekday, NOW's line, then
   its automatic reaction's line (`Boop did nothing on its own.` when
   there was none).

Every template is in `app/BoopKit/Harness/StateText.swift`, each with a
test, and no other code writes state text.

**The entries of §4.2, built for the pass on entry 9 at 14:23:**

| Entry | Picked? | Becomes |
| --- | --- | --- |
| 1 `event` turn start | Yes | `18 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.` |
| 2 `pass` | No: passes never show | — |
| 3 `event` edit | No: didn't wake the brain | — |
| 4 `event` tests failed | Yes | `9 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.` |
| 5 `pass` | No | — |
| 6 `boop` brain, for 4 | Attached to 4 | `  Boop mumbled, annoyed: "…tests!"` |
| 7 `aside` tap | Yes | `4 min ago: You tapped Boop.` |
| 8 `boop` automatic, for 7 | Attached to 7 | `  Boop wiggled on its own.` |
| 9 `event` turn end | NOW | `claude finished turn 7 on …` under the NOW heading |
| 10 `boop` automatic, for 9 | Attached to NOW | `Boop already cheered on its own.` |

Put together:

```
HISTORY (oldest first; indented lines are what Boop did)
18 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
9 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, annoyed: "…tests!"
4 min ago: You tapped Boop.
  Boop wiggled on its own.
Working now: nothing else.

NOW (14:23, Tuesday)
claude finished turn 7 on "agent-work-visibility": done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.
Boop already cheered on its own.
```

## 5. The state

The brain gets one plain-text document with six named sections, always
in this order. READING is **generated** by the code that writes the
lines, so it always matches them. The next three are **static**: files
that ship with the app and change only in a release, so each can be
swapped whole. The last two are **rendered** from the transcript for
every pass (§4.3). Jev keeps no session and no cache, so relative times
cost nothing to rebuild.

| Section | Kind | Source |
| --- | --- | --- |
| **READING** | Generated | How to read HISTORY and NOW (this section, below), then the words the lines use ([EVENTS.md](EVENTS.md) §8) |
| **GUIDE** | Static | `plan/steering/guide.md` |
| **PERSONALITY** | Static, chosen in Settings | `plan/steering/personality/<name>.md` |
| **MOOD** | Static, swapped when the mood changes | `plan/steering/mood/<current>.md` |
| **HISTORY** | Rendered | The transcript and the core's live threads |
| **NOW** | Rendered | The entry this pass is for |

**READING** explains the format, so no static file has to. Its first
part is the harness's, since it's about the layout §4.3 builds; its
second is the events', since it's about their words, and lives in
[EVENTS.md](EVENTS.md) §8.1. [EXAMPLE.md](EXAMPLE.md) §4 shows it whole.

```
READING
HISTORY and NOW describe what's happening around Boop, one line each.
- HISTORY is what already happened, oldest first. Each line starts with
  how long ago it was. Lines indented under it are what Boop did about it.
- The last line of HISTORY lists the other threads still working.
- NOW is the one thing to react to, headed with the time. Its second line
  is what Boop already did on its own.
- "On its own" means one of Boop's fixed reflexes, not a choice.
Words the lines use:
[EVENTS.md §8.1]
```

What each static file says is in [DECISIONS.md](DECISIONS.md) §2. The
runtime reads them read-only; `plan/steering/` is their single source, and
the app bundles a copy. The questions carry the rest: each option's
meaning and each question's own instructions.

**Rendering.** READING is built with the lines, in
`app/BoopKit/Harness/StateText.swift`. The static sections are their
files as they are, without comments, each under its heading. HISTORY and
NOW are the transcript's text form (§4.3).

The shape, abridged (a full one is in [EXAMPLE.md](EXAMPLE.md)):

```
READING
…
GUIDE
…
PERSONALITY
…
MOOD
…
HISTORY (oldest first; indented lines are what Boop did)
9 min ago: <an event's line>
  <what Boop did about it>
…
Working now: <the other threads>

NOW (14:23, Tuesday)
<the event's line>
<its automatic reaction>
```

**Sizes.** READING is about 300 tokens, GUIDE is kept within 300,
PERSONALITY within 600 and MOOD within 150, and 40 history lines come to
about 1,200. With the questions a request is about 3,000 tokens, well inside Jev's 32K. A part
over its budget is logged (`Prompt.Budget`).

## 6. Asking Jev

**The request** is the state as one string and every action's questions,
keyed by name, in one call to `https://api.typesafe.ai/v1/systemone`. Jev
reads the state once and answers every question on its own against it, so
none can depend on another's answer, and an extra question costs only its
own few tokens ([TypeSafe](https://docs.typesafe.ai/cookbooks/parallel_questions.md)).
Output is free.

```json
{
  "model": "jev-latest",
  "state": "GUIDE\n…\n\nNOW (14:23, Tuesday)\n…",
  "questions": {
    "<name>": {
      "type": "choice",
      "criteria": {"<option>": "<its meaning>", "<option>": {"what": "…", "not_for": "…"}},
      "instructions": {"question": "…", "about": "the NOW section", "judge_by": "the … section"}
    }
  }
}
```

**The answer** gives each question's choice and its probabilities. The
harness reads each with the reading its action declared: as Jev chose, or
the likeliest option only above a floor.

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
  The evals need the key and fail without it ([EVALS.md](../EVALS.md)).

## 7. Designing for Jev

Jev is literal and small: good at judging a short, clearly labelled state
against clear options, bad at arithmetic and at reading between the
lines. The evidence behind these rules is in
[ARCHITECTURE.md](../ARCHITECTURE.md) §11. Events and decisions both
follow them.

- **Named sections, pointed at by name.** Every question says which
  section it's about and which to judge by.
- **The format is explained once, by the code that writes it:** READING,
  so a change to a line changes its explanation in the same place.
- **Examples in the state's own lines.** Examples in the static files are
  written exactly as HISTORY and NOW lines are, so Jev compares like with
  like.
- **No arithmetic:** times are relative, and durations and gaps arrive as
  named bands. Counts stay small.
- **Facts worked out beforehand** go in the line, so Jev never has to
  count lines to find them.
- **One question per decision,** with options that say what they're not.
- **Full lists, not shortlists,** as TypeSafe advises: each option's
  meaning keeps the pick grounded.

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
the event kind, the latency and which actions ran, never their
arguments, as in `brain turn_end 240 ms → react`.

## 9. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Harness | `app/BoopKit/Harness/Harness.swift` | One pass running and one waiting (§3) |
| Transcript | `app/BoopKit/Harness/Transcript.swift` | The typed entries (§4) |
| State text | `app/BoopKit/Harness/StateText.swift` | Builds READING, HISTORY and NOW (§4.3, §5), and puts the six sections together; pure |
| Steering | `app/BoopKit/Harness/Steering.swift` | Loads the static sections from the bundle, read-only, and checks their budgets |
| Questions | `app/BoopKit/Harness/Tool.swift` | An action's definition: its questions and the readings of its arguments |
| Brain | `app/BoopKit/Harness/Brain.swift`, `app/BoopKit/Brains/JevBrain.swift` | `answer(state, questions, deadline)`: Jev, or `ScriptedBrain` in tests |
| Events | `app/BoopKit/Core/Event.swift` | [EVENTS.md](EVENTS.md) |
| Actions | `app/BoopKit/Actions/` | [DECISIONS.md](DECISIONS.md) |
