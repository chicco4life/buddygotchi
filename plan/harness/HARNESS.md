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
Jev doesn't write text: it reads a state and answers multiple-choice
questions with probabilities, all in one request of about 0.2–0.3 s. The
**harness** is the small, generic code around it. It knows three
contracts and nothing else:

| Contract | Between | Shape |
| --- | --- | --- |
| **Events** (§3) | The core → the harness | What happened: a line of text, whether it wakes the brain, and what Boop already did about it by rule |
| **Actions** (§4) | The harness ↔ each action | The action's questions go out; Jev's answers to them come in; an `(ok, message)` result comes back |
| **The brain** (§7) | The harness ↔ Jev | `answer(state, questions, deadline)`: Jev in the app, a scripted brain in tests |

The harness never reads an event's facts or an action's answers, builds
Minion speech, writes a file or talks to the device
([ARCHITECTURE.md](../ARCHITECTURE.md) §3.4). The brain is never on the
event path: the core has already reacted by rule before the harness sees
an event.

## 2. Architecture

```
 agent hooks, taps
     │
     ▼
 ┌──────────── Core (plain rules) ─────────────┐
 │ hook ─► facts ─► Event ─► rule reaction ────────────────────────────► device
 └──────────────────┬──────────────────────────┘             (state, cheer, wiggle)
                    │ Event { line, reaction, wakesBrain, facts }
                    ▼
 ┌─────────────────────────────── Harness ──────────────────────────────────────┐
 │                                                                              │
 │  Transcript (typed, append-only) ◄─────────────── record ──────────────┐     │
 │    event · pass · action                                               │     │
 │        │                                                               │     │
 │        │ build (§5.3)                                                  │     │
 │        ▼                                                               │     │
 │  State text                                                            │     │
 │    static    guide · PERSONALITY · MOOD    ◄── plan/steering/          │     │
 │              (the guide ends with how to read the rest, generated)     │     │
 │    built     HISTORY · NOW                 ◄── transcript, status line │     │
 │        │                                                               │     │
 │        │              Questions ◄── every action's questions()         │     │
 │        ▼                  │                                            │     │
 │  Brain.answer(state, questions, deadline) ◄────────► Jev               │     │
 │        │                                                               │     │
 │        ▼ each action's own answers                                     │     │
 │  Action.run(answers) ─────────► ActionResult { ok, message } ──────────┘     │
 │        │                                                                     │
 └────────┼─────────────────────────────────────────────────────────────────────┘
          ▼
   whatever the action's body does: the mood file, MomentSchedule ─► device
```

## 3. Events: the input contract

The core hands the harness one shape for everything that happens, whatever
its kind. It writes the line when it builds the event, from facts it has
already worked out, so the harness only places it.

```swift
struct Event {
    let kind: String            // "turn_end", "tool_use", "tap", …
    let receivedAtMs: Int64     // when the app received it
    let line: String            // what happened, as HISTORY and NOW show it
    let reaction: String?       // what Boop already did by rule, as its line:
                                // "Boop cheered on its own." (nil: nothing)
    let wakesBrain: Bool        // opens a pass; false: recorded and shown only
    let facts: [String: JSONValue]
                                // the kind's own fields, for logs and evals;
                                // the harness never reads them
}
```

- **The line is final.** It's written in the words the guide explains
  (§6.1), from the facts shown to Jev only; hidden facts (IDs, raw
  durations) never reach it. The harness adds the time in front and
  nothing else.
- **The reaction** is the rule's, decided at the same moment as the event,
  so it travels with it rather than as an entry of its own.
- **Everything handed over is shown.** The core keeps its own
  bookkeeping (a routine tool use, a session starting) to itself, and it
  only reaches the brain as counts in other lines.
- **`wakesBrain`** is the core's call, gates included (something needs
  you, quiet mode, no key). An event that doesn't wake it, like a tap,
  still gets its line in HISTORY, so the next pass knows it happened.
- **The status line.** The core also gives the harness one line of live
  state for the end of HISTORY, the threads working now, through
  `status() -> String`. The harness calls it when it builds a state and
  never keeps it.

What each kind carries, its line and when it wakes the brain are in
[EVENTS.md](EVENTS.md).

## 4. Actions: the output contract

An action is something Boop can do. It declares the questions it needs;
the harness asks them, hands it Jev's answers, and records what it
reports. The body can call anything.

```swift
protocol Action {
    var name: String { get }                       // "react"
    /// Asked on every pass. Built fresh, so they can depend on live state
    /// (the mood question knows the current mood).
    func questions() -> [Question]
    /// Jev's answers to this action's own questions. Returns nil when they
    /// mean "do nothing".
    func run(_ answers: Answers) async -> ActionResult?
}

struct Question {
    let key: String                                // "react"; unique across all actions
    let text: String                               // "How should Boop react to NOW, if at all?"
    let about: String                              // "the NOW section"
    let judgeBy: String                            // "the PERSONALITY and MOOD sections, …"
    let options: [Option]
}

struct Option {
    let name: String                               // "annoyed"
    let what: String                               // its meaning: Jev's criterion
    let notFor: String?                            // what it isn't, when two are easily confused
}

struct Answer {
    let choice: String                             // Jev's pick
    let probabilities: [String: Double]            // every option's
}

typealias Answers = [String: Answer]               // by question key

struct ActionResult {
    let ok: Bool                                   // success or failure
    let message: String                            // ok: its line in HISTORY ("Boop mumbled, annoyed: "…again!"")
                                                   // not ok: why ("quiet mode")
}
```

**What the harness guarantees an action:**

- Its questions are asked in the same request as every other action's.
- It gets the answers to its own questions only, and all of them.
- Actions run one at a time, in the order they're registered, each with a
  **300 ms** timeout. A body that throws or runs late counts as
  `ok: false` with the reason. A body with slow work (a mumble that plays
  for seconds) hands it off and returns.
- A result is recorded as an `action` entry (§5); `nil` records nothing.
- A successful result's message becomes its line in HISTORY, indented
  under the event it answered. A failed one is logged but never shown to
  Jev, since Boop didn't do anything.

**What an action owns:** its questions and their wording, how it reads its
answers (which choice means "do nothing", any probability floor), its own
rules, its dependencies (passed in when it's made), its effect and its
message. Boop's actions are in [DECISIONS.md](DECISIONS.md).

**Adding an action** is writing those, and registering it. Everything
else comes from the harness: its questions join the request, its answers
are recorded in the `pass` entry, its result in an `action` entry, and its
message shows up in HISTORY for the next pass. No other code changes.

## 5. The transcript

The transcript is Boop's record of what happened and what it did. It has
two forms: a **typed list** the app keeps, which is the only thing ever
written, and a **text form** for the state, built from the list for each
pass and never stored.

### 5.1 Maintaining it

- **One list, append-only,** owned by the harness
  (`app/BoopKit/Harness/Transcript.swift`) and touched only on its queue.
  Nothing in it is ever changed or removed out of order; a later fact is
  a new entry.
- **Who appends, and when:**

| When | Appended | By |
| --- | --- | --- |
| The core emits an event | `event` | The runtime, before submitting it, so a pass always finds its own event already there |
| A pass has its answers | `pass` | The harness |
| An action returns a result | `action` | The harness, right after the action runs |

- **Order** is arrival order: each entry gets the next sequence number.
  Entries from a pass can land after events that arrived while it ran;
  `for` ties each `pass` and `action` entry to its event, so the text form
  puts it in the right place anyway.
- **Keeping it.** In memory only. Past a thousand entries the oldest are
  let go; nothing is summarised. Every entry is also written to
  `debug.jsonl` as it's appended (§9), so a session can be read back.
- **Privacy.** No prompt text, commands, tool input or output, file
  contents or agent messages go in ([EVENTS.md](EVENTS.md) §9 lists the
  only names that do).

### 5.2 The typed form

| Entry | Holds |
| --- | --- |
| `event` | An `Event` (§3), whole |
| `pass` | `for` (its event), every question's answer with its probabilities, why the pass was dropped if it was, and the latency |
| `action` | `for` (its event), the action's `name`, its `ok` and `message`, and the latency |

```swift
struct Entry { let seq: Int; let receivedAtMs: Int64; let body: Body }

enum Body {
    case event(Event)
    case pass(Pass)            // forSeq, answers, dropped, latencyMs
    case action(ActionRecord)  // forSeq, name, result, latencyMs
}
```

As `debug.jsonl` holds them (facts abridged with `…`):

```jsonl
{"seq":1,"received_at_ms":1790000000000,"event":{"kind":"turn_start","line":"claude started turn 7 on \"agent-work-visibility\" (buddygotchi), right after its last one.","reaction":null,"wakes_brain":true,"facts":{"thread":{"name":"agent-work-visibility","agent":"claude","turn":7,…},"resumed":false,"gap":"right after"}}}
{"seq":2,"received_at_ms":1790000000210,"pass":{"for":1,"answers":{…},"dropped":null,"latency_ms":210}}
{"seq":3,"received_at_ms":1790000540000,"event":{"kind":"tool_use","line":"claude's tests failed again on \"agent-work-visibility\", 2 in a row.","reaction":null,"wakes_brain":true,"facts":{"tool":"shell","topic":"tests","result":"failed","failed_before":1,…}}}
{"seq":4,"received_at_ms":1790000540230,"pass":{"for":3,"answers":{…},"dropped":null,"latency_ms":230}}
{"seq":5,"received_at_ms":1790000540231,"action":{"for":3,"name":"react","ok":true,"message":"Boop mumbled, annoyed: \"…tests!\"","latency_ms":1}}
{"seq":6,"received_at_ms":1790000840000,"event":{"kind":"tap","line":"You tapped Boop.","reaction":"Boop wiggled on its own.","wakes_brain":false,"facts":{}}}
{"seq":7,"received_at_ms":1790001080000,"event":{"kind":"turn_end","line":"claude finished turn 7 on \"agent-work-visibility\": done after 18 min, a very long turn, 41 tools (6 failed). Tests passing, build passing. A comeback on tests.","reaction":"Boop cheered on its own.","wakes_brain":true,"facts":{"outcome":"done","length":"very long","comeback":"tests",…}}}
```

### 5.3 The text form

For each pass, `StateText` builds the state's HISTORY and NOW sections
(§6) from the list. It's a pure function of the transcript, the status
line and the clock: the same inputs always give the same text, so a
logged pass can be built again exactly. The text is never kept, except
inside that pass's `debug.jsonl` line. It never writes an event's line or
an action's message; it only places them.

**How it's built, step by step:**

1. **Pick NOW:** the event the pass is for.
2. **Pick HISTORY's events:** those older than NOW, from
   the last 10 minutes or since the oldest turn still working began,
   whichever reaches further back, then at most the newest 40.
3. **Attach what Boop did** to each picked event: its `reaction`, then the
   messages of its successful `action` entries, in sequence order.
4. **Order** the picked events oldest first.
5. **Write each one** as `<time>: <line>`, the time relative to now
   (`just now` under a minute, then `N min ago`, then `N h ago`), with
   what Boop did indented two spaces under it, one line each.
6. **Close HISTORY** with the status line.
7. **Write NOW:** a heading with the clock and weekday, NOW's line, then
   its reaction, or `Boop did nothing on its own.`

**The entries of §5.2, built for the pass on entry 7 at 14:23:**

| Entry | Picked? | Becomes |
| --- | --- | --- |
| 1 `event` turn start | Yes | `18 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.` |
| 2 `pass` | No: passes never show | — |
| 3 `event` tests failed | Yes | `9 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.` |
| 4 `pass` | No | — |
| 5 `action` react, for 3 | Attached to 3 | `  Boop mumbled, annoyed: "…tests!"` |
| 6 `event` tap | Yes, with its reaction | `4 min ago: You tapped Boop.` and `  Boop wiggled on its own.` |
| 7 `event` turn end | NOW, with its reaction | its line under the NOW heading, then `Boop cheered on its own.` |

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
Boop cheered on its own.
```

## 6. The state

The brain gets one plain-text document in five parts, always in this
order. It opens with the guide, which has no heading and starts "You
are…"; the rest are headed, so the questions can point at them by name.
Jev keeps no session and no cache, so all of it is built fresh for every
pass, and relative times cost nothing.

| Part | Kind | Source |
| --- | --- | --- |
| The guide (no heading) | Static, then generated | `plan/steering/guide.md`, then how to read HISTORY and NOW (§6.1) |
| **PERSONALITY** | Static, chosen in Settings | `plan/steering/personality/<name>.md` |
| **MOOD** | Static, chosen per pass | `plan/steering/mood/<current>.md` |
| **HISTORY** | Built | The transcript and the status line (§5.3) |
| **NOW** | Built | The event this pass is for (§5.3) |

The static files ship with the app and change only in a release, so each
can be swapped whole. What each says is in [DECISIONS.md](DECISIONS.md)
§2. The runtime reads them read-only; `plan/steering/` is their single
source, and the app bundles a copy. A static part's file can be chosen
for each pass by a provider the app registers: MOOD's is the mood store,
so the pass after a change reads the new mood's file. The questions carry
the rest: each option's meaning and each question's own wording.

### 6.1 How to read HISTORY and NOW

The guide ends with a short explanation of the format, so no static file has
to describe it. It's generated by the code that builds the format, so the
two can't drift. Its first part is the harness's, since it's about the
layout §5.3 builds; its second is the events', since it's about their
words, and lives in [EVENTS.md](EVENTS.md) §8.1. [EXAMPLE.md](EXAMPLE.md)
§4 shows the guide whole.

```
How to read HISTORY and NOW:
- HISTORY is oldest first. Each line says how long ago it happened, and
  lines indented under it are what Boop did. The last line lists the
  threads still working.
- NOW is what to react to. Its second line is what Boop already did on
  its own, by reflex.
[EVENTS.md §8.1]
```

### 6.2 Putting it together

The guide comes first, as it is. Each section after it is its heading on
a line of its own, then its text, with a blank line between sections. Static files are used as they are, without
comments. The shape, abridged (a full one is in [EXAMPLE.md](EXAMPLE.md)):

```
<guide.md, starting "You are the mind of Boop…">
How to read HISTORY and NOW:
…
PERSONALITY
…
MOOD
…
HISTORY (oldest first; indented lines are what Boop did)
9 min ago: <an event's line>
  <what Boop did about it>
…
<the status line>

NOW (14:23, Tuesday)
<the event's line>
<its reaction>
```

**Sizes.** The guide is kept within 300 tokens and its generated part is about
150,
PERSONALITY within 600 and MOOD within 150, and 40 history lines come to
about 1,200. With the questions a request is about 3,000 tokens, well
inside Jev's 32K. A part over its budget is logged (`Prompt.Budget`).

## 7. Asking Jev

**The request** is the state as one string and every action's questions
in one call to `https://api.typesafe.ai/v1/systemone`. Jev reads the state
once and answers every question on its own against it, so none can depend
on another's answer, and an extra question costs only its own few tokens
([TypeSafe](https://docs.typesafe.ai/cookbooks/parallel_questions.md)).
Output is free.

Each `Question` (§4) becomes one of TypeSafe's choice questions:

| `Question` | Request |
| --- | --- |
| `key` | The question's name in `questions` |
| `text`, `about`, `judgeBy` | `instructions`: `question`, `about`, `judge_by` |
| Each `Option` | A `criteria` entry: its `what` alone, or `{"what", "not_for"}` when it has a `notFor` |

```json
{
  "model": "jev-latest",
  "state": "You are the mind of Boop, …\n\nNOW (14:23, Tuesday)\n…",
  "questions": {
    "<key>": {
      "type": "choice",
      "criteria": {"<option>": "<what>", "<option>": {"what": "…", "not_for": "…"}},
      "instructions": {"question": "<text>", "about": "<about>", "judge_by": "<judgeBy>"}
    }
  }
}
```

**The answer** gives each question's choice and every option's
probability, which become an `Answer` each; each action gets its own.

- **Deadline:** 1.25 s for the whole pass: four times Jev's usual time,
  with room for one retry. A later answer is dropped.
- **Retries:** a 429, a 5xx or a dropped connection is tried once more
  after 0.3 s. Only a failed request's HTTP status is logged, since an
  error body may repeat the request.
- **When Jev fails** or is late, the pass is dropped and no action runs:
  Boop does only its rule reactions, and the `pass` entry says why.
- **The key** comes from `BOOP_JEV_KEY`, else, in the menu-bar app only,
  the Keychain. `Boop --headless` and `boopdev` read only the variable,
  so a run from an agent shell never uses the owner's key. The Keychain is
  read off the app's event queue and the main thread the first time it's
  needed, since a Keychain prompt would stall both. Without a key no
  event wakes the brain and Boop does only its rule reactions, which is
  fine for everyday use; saving one in Settings brings Jev in at once.
  The evals need the key and fail without it ([EVALS.md](../EVALS.md)).

## 8. Designing for Jev

Jev is literal and small: good at judging a short, clearly labelled state
against clear options, bad at arithmetic and at reading between the
lines. The evidence behind these rules is in
[ARCHITECTURE.md](../ARCHITECTURE.md) §11. Events and actions both follow
them.

- **Named sections, pointed at by name.** Every question says which
  section it's about and which to judge by.
- **The format is explained once, by the code that builds it,** at the
  end of the guide.
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

## 9. Logging

**Debug mode** is `Boop --debug`, in the menu-bar app (`make debug`) or
headless. It prints to the terminal that started the app, as it happens:
each hook with the event the core made of it, every line sent to the
device, and each pass.

Every transcript entry is also one JSON line in the state directory's
`debug.jsonl` (§5), which starts afresh at every launch. A `pass` line
there also holds the state text and the questions it sent, so any pass
can be replayed against Jev. `boopdev watch [FILE]` prints it readably
(the everyday app's by default), following it as it grows.

**The app log** (`boop.log`) gets one line per pass, debug mode or not:
the event kind, the latency and which actions returned a result, never
their messages, as in `brain turn_end 240 ms → react`.

## 10. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Harness | `app/BoopKit/Harness/Harness.swift` | One pass running and one waiting; asks, hands out answers, records |
| Contracts | `app/BoopKit/Harness/Contracts.swift` | `Event`, `Action`, `Question`, `Option`, `Answer`, `ActionResult` |
| Transcript | `app/BoopKit/Harness/Transcript.swift` | The typed entries (§5.2) |
| State text | `app/BoopKit/Harness/StateText.swift` | Builds HISTORY, NOW and the guide's reading part, and puts the state together; pure |
| Steering | `app/BoopKit/Harness/Steering.swift` | Loads the static sections from the bundle, read-only, and checks their budgets |
| Brain | `app/BoopKit/Harness/Brain.swift`, `app/BoopKit/Brains/JevBrain.swift` | `answer(state, questions, deadline)`: Jev, or `ScriptedBrain` in tests |
| Events | `app/BoopKit/Core/Event.swift` | [EVENTS.md](EVENTS.md): building events and writing their lines |
| Actions | `app/BoopKit/Actions/` | [DECISIONS.md](DECISIONS.md) |
