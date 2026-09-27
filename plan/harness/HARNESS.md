# Boop: the harness

Updated 2026-09-27. The generic code between the core and the brain: how
an event becomes questions for Jev, and how Jev's answers become
something Boop does. The events are in [EVENTS.md](EVENTS.md), Boop's
questions and actions in [DECISIONS.md](DECISIONS.md), and
[EXAMPLE.md](EXAMPLE.md) follows one real pass through all of it.

## 1. What this is

Boop has one brain, TypeSafe's **Jev** ([docs](https://docs.typesafe.ai/api)).
Jev doesn't write text. It reads a plain-text state and answers
multiple-choice questions, giving every option a probability, all in one
request of about 0.2–0.3 s. The **harness** is the small, generic code
around it. It knows three contracts and nothing else:

| Contract | Between | Shape |
| --- | --- | --- |
| **Event** (§3) | The core → the harness | What happened, as a line of text; what Boop already did about it by rule; whether it wakes the brain |
| **Action** (§4) | The harness ↔ each action | The action's questions go out, Jev's answers to them come back in, and the action reports `(ok, message)`, or that it started something that ends later |
| **Brain** (§7) | The harness ↔ Jev | `answer(state, questions, deadline) → Answers` |

The harness never reads an event's facts or an action's answers, never
builds Minion speech, writes a file or talks to the device. The brain is
never on the event path: by the time the harness sees an event, the core
has already reacted by rule.

## 2. Data flow

Everything but the brain call runs on `home`, the runtime's one serial
queue.

```
 agent hooks ─► adapters ─► Core ◄── device taps, 1 s ticks
                             │
   rule effects ◄────────────┤ CoreEffect.event(Event)
   (state, cheer,            ▼
    chatter)          Harness.take(event)
        │               ├─ append an `event` entry ──────────► Transcript ─► debug.jsonl
        │               ├─ wakes the brain, and there is one? no ─► stop here
        │               └─ a pass running? yes ─► it waits (a newer one replaces it)
        │                    │ no
        │                    ▼
        │             prepare: the state (§5.3, §6) + every action's questions
        │                    ▼                                        off `home`
        │             Brain.answer(state, questions, 1.25 s) ─────► Jev (§7)
        │                    ▼                                        back on `home`
        │             append a `pass` entry: the answers, or why it was dropped
        │                    ▼ not dropped
        │             each action in order: run(its own answers) → an `action` entry
        │                 mood  ─► `mood` file ─► Core.setMood ─► next `state`
        │                 react ─► Voice line ─► MomentSchedule (waits its turn)
        ▼                    ▼
   Device link ◄─────────────┘
```

What the picture leaves out:

- A waiting event that a newer one replaces keeps its entry, so later
  passes still see it in HISTORY. The app log says
  `harness: turn_start replaced by a newer tool_use`.
- The state and the questions are fixed when a pass starts, so a mood
  that changes meanwhile doesn't change what it sent.
- After every pass, dropped ones included, the runtime hears of it
  (`onRecord`) and writes its app log line (§9). Then the waiting
  event's pass starts.
- An action that started something reports its end later, on `home`,
  and the harness appends it as a `settle` entry. The runtime's 1 s tick
  also ticks the harness, which ends any left open too long (§5.1).

**The harness's states:**

| State | A waking event arrives | The pass finishes |
| --- | --- | --- |
| Idle | Its pass starts | — |
| Running | It waits | Back to idle |
| Running, one waiting | It replaces the waiting one | The waiting one's pass starts |
| No brain | It's recorded, and no pass runs | — |

`use(brain)` swaps the brain from the next pass on; the runtime sets it
once Jev's key is read, or to none (§7).

## 3. Events: the input contract

The core hands over one shape for everything that happens
(`app/BoopKit/Core/Event.swift`):

```swift
struct Event {
    var kind: Kind                 // turn_start, turn_end, tool_use, pokes, heartbeat, tap, needs_you
    var receivedAtMs: Int64        // when the app got it, on its steady clock
    var line: String               // what happened, as HISTORY and NOW show it
    var reaction: String?          // what Boop already did by rule, as its line; nil for nothing
    var wakesBrain: Bool           // opens a pass; false: recorded and shown only
    var about: String?             // the thread it's about, opaque to the harness
    var facts: [String: JSONValue] // the kind's own fields, for logs and evals only
}
```

- **The line is final.** The core writes it; the harness only adds the
  time in front.
- **The reaction travels with its event,** since the rule decided it at
  the same moment, and is never an entry of its own.
- **`wakesBrain` is the core's call,** gates included
  ([EVENTS.md](EVENTS.md) §6). An event that doesn't wake the brain still
  gets its line in HISTORY, so the next pass knows it happened.
- **`about`** goes back to the core, unread, when the state is built:
  the status line at the end of HISTORY lists every thread working now
  except NOW's.
- **`facts`** go to `debug.jsonl` and the evals. The harness never reads
  them.

## 4. Actions: the output contract

An action is something Boop can do when the brain wakes
(`app/BoopKit/Harness/Contracts.swift`):

```swift
protocol Action: AnyObject {
    var name: String { get }                     // "react"
    func questions() -> [Question]               // asked on every pass, built fresh each time
    func run(_ answers: Answers) -> ActionResult? // its own answers; nil means "did nothing"
}

struct Question { key, text, about, judgeBy: String; options: [Option] }
struct Option   { name, what: String; notFor: String? }   // `what` is Jev's criterion
struct Answer   { choice: String; probabilities: [String: Double] }
typealias Answers = [String: Answer]                        // by question key
struct ActionResult { ok: Bool; message: String; pending: Pending? } // ok: its line in HISTORY; not ok: why

// .done(message), .failed(why), or .started(message, pending): begun, and ends later
final class Pending {
    enum End { case done, failed(String) }  // failed: why it never happened
    func finish(_ end: End)                  // on `home`; only the first call counts
}
```

**What the harness guarantees an action:**

- Its questions go in the same request as every other action's. Keys are
  unique across all actions; the harness won't start otherwise.
- It gets the answers to its own questions and no others. From Jev
  that's all of them, since an answer missing one is dropped whole (§7).
- Actions run one at a time, in registration order, on `home`. A body
  with slow work hands it off and returns at once. One that takes over
  **300 ms** (`Harness.actionSlowMs`) is logged, since it holds up
  everything behind it.
- A result becomes an `action` entry; `nil` records nothing.
- A successful result's message becomes its line in HISTORY, indented
  under the event it answered. A failed one is logged but never shown to
  Jev, because Boop didn't do anything.
- **A started result** (`.started(message, pending)`) is for something
  that plays out after `run` returns, such as a moment on the device. The
  action keeps the `Pending` and finishes it when it knows how things
  went: `done`, or `failed` with why it never happened. Until then HISTORY
  shows its line as in progress (§5.3). An end that comes before the
  harness has recorded the result is kept and recorded right after it.
  A result that's done, failed or `nil` has no end to wait for.

**An action owns** its questions and their wording, how it reads its
answers (which choice means "do nothing", any probability floor), its own
rules, its dependencies (passed in when it's made), its effect and its
message. Adding one is writing those and registering it in `Runtime`;
nothing else changes.

## 5. The transcript

Boop's record of what happened and what it did
(`app/BoopKit/Harness/Transcript.swift`). The typed list is the only
thing ever written. The text form is built from it for each pass and
never kept.

### 5.1 Keeping it

| When | Appended | By |
| --- | --- | --- |
| The core emits an event | `event` | The harness, in `take`, before any pass for it |
| A pass has its answers, or is dropped | `pass` | The harness |
| An action returns a result | `action` | The harness, right after the action runs |
| A started action's `Pending` ends, or it's left open too long (below) | `settle` | The harness, when the end reaches it, or on the tick |
| The dashboard forces answers or a mood (§9) | `pass` and `action`, or `action` alone, for no event, and a started action's `settle` later | The harness |

- **Append-only.** Each entry gets the next sequence number, in arrival
  order, and is never changed. A pass's entries can land after events
  that arrived while it ran; their `for` ties them to their event.
- **In memory only.** Past **1,000** entries (`Transcript.limit`) the
  oldest are let go; nothing is summarised. Debug mode also writes each
  entry to `debug.jsonl` as it's appended (§9).
- **Privacy.** No prompt text, commands, tool input or output, file
  contents or agent messages go in ([EVENTS.md](EVENTS.md) §9).
- **Started actions stay open** until their end is recorded. The harness
  keeps the open ones by their `action` entry's `seq`, and records only
  the first end of each. One still open **60 s**
  (`Harness.pendingMaxMs`) after its result is ended as `failed` with
  `no word it finished`, on the runtime's 1 s tick (`Harness.tick`), and
  the app log says `harness: <name> was still in progress after <N> ms;
  ended it`. So HISTORY never says in progress for good, whatever the
  action forgot.

### 5.2 The entries

Each entry has `seq` and `receivedAtMs` (an event's own time; for a
pass, action or settle, when it was recorded), and one body:

| Body | Fields (JSON names) |
| --- | --- |
| `event` | The `Event` whole (§3): `kind`, `line`, `reaction`, `wakes_brain`, `facts` |
| `pass` | `for` (its event's `seq`), `answers` (each question's `choice`, and `p`, every option's probability to three places), `dropped` (why no action ran, or null), `latency_ms` |
| `action` | `for`, `name`, `ok`, `message`, `latency_ms`, and `pending: true` when it started something (left out otherwise) |
| `settle` | `for` (its `action` entry's `seq`), `end` (`done` or `failed`), and `why` when failed |

A forced entry is for no event: `for` is null, and `debug.jsonl` adds
`"by":"dashboard"`. A forced action's `settle` gets the same mark. That
mark is for the log only and never reaches the state. Real entries are in
[EXAMPLE.md](EXAMPLE.md) §3; a started action and its settles, from
`HarnessTests`:

```jsonl
{"action":{"for":1,"latency_ms":0,"message":"Boop did it.","name":"a","ok":true,"pending":true},"received_at_ms":1790000000000,"seq":3}
{"received_at_ms":1790000000000,"seq":4,"settle":{"end":"done","for":3}}
{"received_at_ms":1790000000000,"seq":8,"settle":{"end":"failed","for":7,"why":"waited too long"}}
```

### 5.3 The text form

`StateText` builds the state's HISTORY and NOW for each pass. It's a
pure function of the entries, the status line and the clock, so a logged
pass can be rebuilt exactly from `debug.jsonl`, settles included. It
places event lines and action messages and never writes them, apart from
marking a started action's progress (step 3).

1. **NOW** is the event the pass is for.
2. **HISTORY's events** are those before NOW, from the last **10
   minutes** (`StateText.historyMs`) or since the oldest turn still
   working began, whichever reaches further back, then at most the
   newest **40** (`StateText.historyLimit`). Passes never show.
3. **What Boop did** goes under each: the event's `reaction`, then the
   messages of its successful `action` entries, in order. A forced
   action counts as done about the latest event before it. A started
   one's message ends in ` (in progress)` until its `settle`; after
   that it's plain if it was done, or ends in
   ` (didn't happen: <why>)`.
4. **Each event** is written oldest first as `<when>: <line>`, with
   `<when>` relative to now: `just now` under a minute, then `N min
   ago`, then `N h ago`. What Boop did follows, indented two spaces, one
   line each.
5. **HISTORY closes** with the core's status line
   ([EVENTS.md](EVENTS.md) §8).
6. **NOW** is a heading with the time and weekday, NOW's line, then its
   reaction or `Boop did nothing on its own.`

## 6. The state

One plain-text document in five parts, always in this order, built
fresh for every pass since Jev keeps no session:

| Part | Kind | Source |
| --- | --- | --- |
| The guide (no heading) | Static, then generated | [steering/guide.md](../steering/guide.md), then how to read HISTORY and NOW (§6.1) |
| `PERSONALITY` | Static, the one chosen in Settings | `plan/steering/personality/<name>.md` ([boop](../steering/personality/boop.md), [chatter](../steering/personality/chatter.md)) |
| `MOOD` | Static, the current mood's | `plan/steering/mood/<mood>.md` ([happy](../steering/mood/happy.md), …), read from the mood store at each pass |
| `HISTORY (oldest first; indented lines are what Boop did)` | Built | The transcript and the status line (§5.3) |
| `NOW (14:23, Tuesday)` | Built | The event this pass is for (§5.3) |

The guide and its generated part are joined by single line breaks; the
other parts follow, each after a blank line. The runtime supplies
everything but the transcript through one closure (`parts`): the steering
text, the core's status line and oldest working turn, and the time
(`Runtime.stateParts`).

**The steering files** are read once at launch from the app's bundled
copy of `plan/steering/` (`Steering`), and never written. HTML comments
are left out. A personality's front matter goes to the core's rules
([BEHAVIORS.md](../BEHAVIORS.md) §6) and never reaches Jev. A missing
file stops the app from starting, and an unknown mood reads as happy's
file. What the files say is [DECISIONS.md](DECISIONS.md) §2.

### 6.1 How to read HISTORY and NOW

The guide ends with an explanation of the format, generated by the code
that builds it, so the two can't drift. The layout part is the
harness's (`StateText.reading`); the words part is the events'
([EVENTS.md](EVENTS.md) §8.1):

```
How to read HISTORY and NOW:
- HISTORY is oldest first. Each line says how long ago it happened, and
  lines indented under it are what Boop did. The last line lists the
  threads still working.
- A line of what Boop did may end in brackets: (in progress) means it
  hasn't finished yet, and (didn't happen: …) means it never did, and
  why.
- NOW is what to react to. Its second line is what Boop already did on
  its own, by reflex.
[EVENTS.md §8.1]
```

### 6.2 Sizes

Each static part has a budget in tokens (`Steering.Budget`), counted as
bytes ÷ 4, which overestimates English: the guide 300 (now about 270), a
personality 600 (`boop` about 200, `chatter` 280) and a mood 150 (80–145).
A part over its budget is logged at launch (`steering: over budget: …`),
and a test keeps every file within it. The generated reading part is
about 225 tokens and HISTORY's 40 events about 1,200, so with the
questions a request is at most about 3,000 tokens. The evals' states come
to 800–1,000.

## 7. Asking Jev

**The request** is one `POST` to `https://api.typesafe.ai/v1/systemone`
with the state as one string and every action's questions, model
`jev-latest` (`JevBrain`). Jev reads the state once and answers each
question on its own against it, so no answer depends on another's
([TypeSafe](https://docs.typesafe.ai/cookbooks/parallel_questions.md)).
Each `Question` becomes a choice question named by its `key`, with its
`text`, `about` and `judgeBy` as `instructions`, and each option's `what`
as its criterion (with `not_for` when it has a `notFor`).
[EXAMPLE.md](EXAMPLE.md) §5 shows one, built from a real pass.

**The answer** has each question's `choice` and `probabilities`. Every
question must be answered with one of its own options, or the whole
answer is unusable.

| Number | Value | Where |
| --- | --- | --- |
| Deadline for the whole pass | **1.25 s**, about four times Jev's usual time, with room for one retry | `Harness.deadlineMs` |
| One retry, after | **300 ms**, on a 429, any 5xx, or a connection that failed (not one that timed out) | `JevBrain.retryAfterMs` |
| The HTTP request's own timeout | 2 s (the deadline's whole seconds + 1); the deadline cuts it off first | `JevBrain.answer` |

**A dropped pass** runs no action, so Boop does only its rule
reactions. The `pass` entry's `dropped` says why:

| `dropped` | When |
| --- | --- |
| `late: no answer within 1250 ms` | The deadline passed. A brain that ignores cancelling finishes on its own, and its answer is thrown away |
| `jev: HTTP <status>` | Not 200, after the retry. Only the status is kept, since an error body may repeat the request |
| `jev: no answers` | The body had no `answers` object |
| `jev: no usable answer for <key>` | A question left out, or answered with an option it doesn't have |
| `cancelled`, or an error's own text | The pass's task was cancelled, or the request failed some other way |

When the body came back but couldn't be used, the app log gets its size,
never its text: `harness: jev:jev-latest answered what couldn't be used
(N bytes)`.

**The key** comes from `BOOP_JEV_KEY`, else, in the menu-bar app only,
the Keychain, which Boop reads through `/usr/bin/security`
([ARCHITECTURE.md](../ARCHITECTURE.md) §11). `Boop --headless` and
`boopdev` read only the variable, so a run from an agent shell never
uses the owner's key. The runtime reads it off `home` and the main
thread, since a Keychain prompt would stall both. Until it's read, and
without one, there's no brain: the core marks no event as waking it, and
Boop does only its rule reactions. A key saved in Settings takes effect
from the next event.

**The brains:**

| Brain | `id` | Used by |
| --- | --- | --- |
| `JevBrain` | `jev:jev-latest` | The app with a key, and the evals |
| `ScriptedBrain` | `scripted` | Tests: a script sees the state and questions and returns answers. `Boop --headless --brain scripted` uses `pipelineCheck`, which answers every pass `mood: happy`, `react: excited`, `word.feeling: yay`, `word.about: none` |

## 8. Designing for Jev

Jev is literal and small: good at judging a short, clearly labelled
state against clear options, bad at arithmetic and at reading between
the lines. Events, questions and steering files all follow these rules
(the evidence is in [ARCHITECTURE.md](../ARCHITECTURE.md) §11):

- **Named sections,** and every question says which it's about and
  which to judge by.
- **The format explained once,** at the end of the guide, by the code
  that builds it.
- **Examples in the state's own lines,** so Jev compares like with like.
- **No arithmetic:** relative times, named bands for durations and gaps
  ([EVENTS.md](EVENTS.md) §5), small counts, and facts worked out
  beforehand rather than left for Jev to count.
- **One question per decision,** with the full list of options, each
  saying what it's not when two are easily confused.

## 9. Logging and debug mode

**The app log** (`boop.log`) gets one line per pass, debug mode or not,
dropped passes included: `brain <kind> <ms> ms → <result>`, where
`<result>` is the actions that returned something (`mood, react`, with
` (failed)` after a failed one), `nothing`, or `dropped: <why>`. It never
holds an action's message or the state. The harness also logs a replaced
waiting event, a dropped pass, a slow action, an unusable answer's size,
forced answers it left out, and a started action it ended for staying
open too long (§5.1).

**Debug mode** is `Boop --debug`, in the menu-bar app (`make debug`) or
headless. It prints to the terminal that started the app: each hook with
what the adapter made of it, each of the core's effects, every line sent
to the device, and each transcript entry, readably. From the example run
([EXAMPLE.md](EXAMPLE.md)), recorded while `react` still offered
`annoyed`, today's `grumpy`:

```
▸ 9 tool_use: claude's tests failed again on "fix-nav" (landing), 3 in a row.
  pass jev:jev-latest 187 ms: mood grumpy 0.99 · react annoyed 0.99 · word.about tests 1.00 · word.feeling again 0.88
    │ <the whole state for the first pass, then only its HISTORY and NOW>
  ✓ mood: Boop's mood changed: determined → grumpy.
  ✓ react: Boop mumbled, annoyed: "…again!"
```

An event that doesn't wake the brain is marked `(no pass)`, and a failed
action `✗`. A started action is marked `…`, and its `settle` prints as a
line of its own when it comes, naming the action and its `seq`:
`  ✓ react (16) done`, or `  ✗ react (16) didn't happen: <why>`. The
state goes to the terminal only, never `boop.log`.

**`debug.jsonl`,** in the state directory, is emptied in place at every
launch and gets one JSON line per transcript entry (§5.2), keys sorted.
`boopdev watch [FILE]` prints it as the terminal does, following it as it
grows. A Jev pass's line carries three more fields, so any pass can be
replayed: `state` (the whole state sent), `questions` (the keys asked, in
order) and `brain` (its `id`). A forced pass's line has `questions` (the
keys it answered) and `by`, and no `state` or `brain`.

**The dashboard's lines.** Debug mode also writes three kinds of line
that aren't entries, so they have no `seq`, for
[DASHBOARD.md](../DASHBOARD.md). The terminal and `boopdev watch` skip
them. Every line's `received_at_ms` is the app's clock, which headless
`advance` moves.

| Line | When | Holds |
| --- | --- | --- |
| `questions` | Once, as the file's first line, before the socket or the link can add one | Every action's questions in order: `action`, `key`, `text`, and each option's `name`, `what` and `not_for` |
| `sent` | Every line sent to the device, whatever the link, none included | The line, verbatim ([PROTOCOL.md](../PROTOCOL.md) §3) |
| `status` | When the personality, the brain, the sessions or the connection changes | `personality`, `brain` (an `id`, or `none`), `sessions` (`agent`, `project`, `status`) and `connected`; the mood is in `sent`'s `state` |

**Dev lines.** Headless, or in debug mode, the hook socket also takes
`{"dev":…}` lines; plain `make run` ignores them. Nothing replies: what a
line did shows in `debug.jsonl`. Any other `dev` value is ignored.

| Line | Does |
| --- | --- |
| `{"dev":"advance","ms":N}` | Headless only: moves the app's clock forward N ms, then ticks |
| `{"dev":"answer","answers":{"react":"grumpy","word.feeling":"again"}}` | A **forced pass**: each choice at probability 1, handed to the actions exactly as Jev's answers would be. It runs at once on `home`, needs no brain or key, and leaves a running or waiting pass alone. A choice that isn't one of its question's options is left out. The actions keep their own rules. Recorded as a `pass` and its `action` entries, for no event, by the dashboard; no `brain` line in `boop.log` |
| `{"dev":"mood","mood":"grumpy"}` | Sets the mood at once through the mood action, device included ([DECISIONS.md](DECISIONS.md) §4). Recorded as an `action` named `mood`, for no event, by the dashboard, refusals included |
| `{"dev":"moment","anim":"cheer"}` | Plays `cheer` or `wiggle` as a rule's moment; any other is ignored. Only its `sent` line records it |

A forced pass and its action, from a headless run:

```jsonl
{"pass":{"answers":{"react":{"choice":"grumpy","p":{"grumpy":1}},"word.feeling":{"choice":"again","p":{"again":1}}},"by":"dashboard","dropped":null,"for":null,"latency_ms":0,"questions":["react","word.feeling"]},"received_at_ms":1790512903608,"seq":1}
{"action":{"by":"dashboard","for":null,"latency_ms":0,"message":"Boop made a grumpy face and mumbled \"…again!\"","name":"react","ok":true},"received_at_ms":1790512903609,"seq":2}
```

## 10. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Harness | `app/BoopKit/Harness/Harness.swift` | One pass running and one waiting; asks, hands out answers, records; started actions until they settle, and their ceiling (`tick`); forced passes; `respond(to:)`, one event straight through for the evals |
| Contracts | `app/BoopKit/Harness/Contracts.swift`, `app/BoopKit/Core/Event.swift` | `Action`, `Question`, `Option`, `Answer`, `ActionResult`, `Pending`, `JSONValue`; `Event` |
| Transcript | `app/BoopKit/Harness/Transcript.swift` | The entries and their JSON lines |
| State text | `app/BoopKit/Harness/StateText.swift` | HISTORY, NOW and the reading part, put together; pure |
| Steering | `app/BoopKit/Harness/Steering.swift` | Loads the static parts, read-only, and checks their budgets |
| Brain | `app/BoopKit/Harness/Brain.swift`, `app/BoopKit/Brains/JevBrain.swift` | The `Brain` protocol and `ScriptedBrain`; Jev and its key |
| Debug log | `app/BoopKit/Harness/DebugLog.swift` | The dashboard's lines, and printing entries readably, settles by their action's name |
| Wiring | `app/BoopKit/App/Runtime.swift` | Registers the actions, supplies `parts`, reads the key, takes dev lines, ticks the harness every second |
| Events | `app/BoopKit/Core/Core.swift`, `app/BoopKit/Core/Event.swift` | [EVENTS.md](EVENTS.md) |
| Actions | `app/BoopKit/Actions/` | [DECISIONS.md](DECISIONS.md) |
