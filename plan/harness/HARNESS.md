# Boop: the harness

Updated 2026-09-28. The generic code between the view and the brain: how
a view event becomes questions for Jev, how Jev's answers become
something Boop does, and the transcript it all comes from. The events
and the view are in [EVENTS.md](EVENTS.md), Boop's
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
| **View event** (§3) | The pipeline → the harness | What happened, as a line of text; what Boop has done about it; whether it wakes the brain |
| **Action** (§4) | The harness ↔ each action | The action's questions go out, Jev's answers to them come back in, and the action reports `(ok, message)`, or that it started something that ends later |
| **Brain** (§7) | The harness ↔ Jev | `answer(state, questions, deadline) → Answers` |

The harness never reads a view event's facts or an action's answers,
never builds Minion speech or talks to the device. The brain is never on
the screen's path: by the time the harness sees a view event, the core
has already updated the look and "needs you". Every reaction, a finished
turn's included, is the brain's.

## 2. Data flow

Everything but the brain call runs on `home`, the runtime's one serial
queue. Every input takes the same way, the `Pipeline`
(`app/BoopKit/App/Pipeline.swift`): it's recorded, the core has it, what
the core did by rule is recorded after it, and the view events it made
are gated ([EVENTS.md](EVENTS.md) §6).

```
 agent hooks ─► adapters ─┐
 device pokes ────────────┼─► Transcript.append ─► transcript/<day>.jsonl, debug.jsonl
 heartbeats (the view) ───┘        │
                                   ├─► Core ─► state ─► device link
                                   │     └─► rule actions (wiggle, needs_you) ─► Transcript.append
                                   └─► TranscriptView.take ─► view events, gated
                                                    ▼
                                 Harness.take(view events)
                      ├─ wakes the brain, and there is one? no ─► stop here
                      └─ a pass running? yes ─► it waits (a newer one replaces it)
                           │ no
                           ▼
                    prepare: the state (§5.3, §6) + every action's questions   on `home`
                           ▼                                                   off `home`
                    Brain.answer(state, questions, 1.5 s) ──────► Jev (§7)
                           ▼                                                   back on `home`
                    a `pass` line in debug.jsonl: the answers, or why it was dropped
                           ▼ not dropped
                    each action in order: run(its own answers) ─► an `action` event
                        mood  ─► `mood` file ─► Core.setMood ─► next `state`
                        react ─► Voice line ─► MomentSchedule (waits its turn) ─► device link
```

What the picture leaves out:

- A waiting view event that a newer one replaces stays in the view, so
  later passes still see it in HISTORY. The app log says
  `harness: turn start replaced by a newer tool end`.
- The state and the questions are fixed when a pass starts, so a mood
  that changes meanwhile doesn't change what it sent. An action the
  dashboard makes act meanwhile (a mood it sets, or a forced pass's
  result that's `ok`) sits that pass's answers out, since they're about
  the state from before the change: Jev's "stay happy" from a state that
  showed happy would undo the dashboard's grumpy. The app log says
  `harness: mood sat out the pass: the dashboard changed it while the pass ran`.
- After every pass, dropped ones included, the runtime hears of it
  (`onRecord`) and writes its app log line (§9). Then the waiting view
  event's pass starts, unless it may no longer wake the brain
  (`Harness.whyNotStart`, the pipeline's `whyNotWake`): while something
  needs you only a poke may, and a poke may not while Boop is answering
  its run ([EVENTS.md](EVENTS.md) §6). It's logged as a pass dropped
  with that reason (`something needs you`, `Boop is answering these
  pokes`), and the brain isn't asked.
- An action that started something reports its end later, on `home`,
  and the harness records it as the action's `end`. The runtime's 1 s
  tick also ticks the harness, which ends any left open too long (§5.1),
  and asks the view for a heartbeat.

**The harness's states:**

| State | A waking view event arrives | The pass finishes |
| --- | --- | --- |
| Idle | Its pass starts | — |
| Running | It waits | Back to idle |
| Running, one waiting | It replaces the waiting one | The waiting one's pass starts, or, if it may no longer wake the brain, is dropped |
| No brain | Nothing: no view event wakes it | — |

`use(brain)` swaps the brain from the next pass on; the runtime sets it
once Jev's key is read, or to none (§7).

## 3. View events: the input contract

The harness takes one shape, whatever happened
(`app/BoopKit/Core/TranscriptView.swift`, [EVENTS.md](EVENTS.md) §3–4):

```swift
struct ViewEvent {
    var id: Int                    // its number in the view
    var type: Event.Kind           // turn, tool, poke, heartbeat: the raw event's type…
    var phase: Event.Phase?        // …and phase: start, wait, end
    var from: [Int]                // the raw events it came from; the last made it
    var ts: Int64                  // when, in unix milliseconds
    var line: String               // what happened, as HISTORY and NOW show it
    var notes: [String]            // lines under it: your prompt, the agent's last message
    var wakesBrain: Bool           // opens a pass; false: kept and shown only
    var about: String?             // the thread it's about, opaque to the harness
    var facts: [String: JSONValue] // for logs and evals only
    var did: [Did]                 // what Boop did about it, in order
}
```

- **The line and notes are final.** The view writes them; the harness only
  adds the time in front.
- **What Boop did** is the view's too: the actions the transcript holds
  `for` the view event's raw event, rule actions first, each done or in
  progress ([EVENTS.md](EVENTS.md) §7).
- **`wakesBrain` is decided before the harness sees it,** gates included
  ([EVENTS.md](EVENTS.md) §6). A view event that doesn't wake the brain
  still gets its line in HISTORY, so the next pass knows it happened.
- **`about`** names the thread as the view keys it, for tests, and
  **`facts`** go to `debug.jsonl` and the evals. The harness reads
  neither.

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

- Its questions go in the same request as every other action's, on
  every pass. Keys are
  unique across all actions; the harness won't start otherwise.
- It gets the answers to its own questions and no others. From Jev
  that's all of them, since an answer missing one is dropped whole (§7).
- Actions run one at a time, in registration order, on `home`. A body
  with slow work hands it off and returns at once. One that takes over
  **300 ms** (`Harness.actionSlowMs`) is logged, since it holds up
  everything behind it.
- A result becomes an `action` event in the transcript
  ([EVENTS.md](EVENTS.md) §2), `for` the raw event its view event came
  from, `by` `brain`; `nil` records nothing.
- A successful result's message becomes its line in HISTORY, indented
  under the view event it answered. A failed one is logged but never shown to
  Jev, because Boop didn't do anything.
- **A started result** (`.started(message, pending)`) is for something
  that plays out after `run` returns, such as a moment on the device. The
  action, or whatever it hands the `Pending` to (`react` hands it on with
  its moment, [DECISIONS.md](DECISIONS.md) §5), finishes it when it knows
  how things went: `done`, or `failed` with why it never happened. Until
  then HISTORY shows its line as in progress (§5.3). Its end is recorded
  as the action's `end` event. An end that comes before the harness has
  recorded the result is kept and recorded right after it. A result that's done, failed or `nil` has no end to wait for.

**An action owns** its questions and their wording, how it reads its
answers (which choice means "do nothing", any probability floor), its own
rules, its dependencies (passed in when it's made), its effect and its
message. Adding one is writing those and registering it in `Runtime`;
nothing else changes.

## 5. The transcript

Boop's record of what happened and what it did
(`app/BoopKit/Harness/Transcript.swift`): every raw event
([EVENTS.md](EVENTS.md) §1–2), in order. The view is folded from it, and
the state from the view, for each pass; neither is ever kept.

### 5.1 Keeping it

| Recorded | By |
| --- | --- |
| An agent's hook, as its adapter maps it | The runtime, as it arrives, before the core has it |
| A poke | The runtime, before the core has it |
| A heartbeat | The runtime, when the view says one is due (on the 1 s tick) |
| A rule's action (`wiggle`, `needs_you`) | The core, as an effect of the event that caused it, recorded right after that event |
| An action's result, and a started one's end | The harness, right after the action runs, and when the end reaches it or it's left open too long (below) |
| The dashboard's forced actions | The harness, `by` `dashboard`, for no event |

- **Append-only.** Each event gets the next `seq`, which counts on across
  days and launches, and is never changed.
- **On disk,** one file a day: `<state-dir>/transcript/<date>.jsonl`
  (`Transcript.folderName`), each event its line, written as it's
  appended. A launch deletes files older than **14 days**
  (`Transcript.keptDays`), reads the last **2** days' back
  (`Transcript.replayDays`) and folds them into the view, so turn
  numbers and failure runs carry on. A line that doesn't parse, such as
  one a crash cut short, is skipped, and `seq` goes on from the newest
  file's last event. The newest **1,000** events are also kept in memory
  (`Transcript.limit`).
- **A started action that was still in progress** when the last launch
  quit can't end now, since its handle went with that launch, so the
  launch records its end as failed, `Boop restarted`.
- **Debug mode** also writes each event to `debug.jsonl` (§9).
- **Privacy.** Your prompt and the agent's last message are the only
  words in it ([EVENTS.md](EVENTS.md) §9).
- **Started actions stay open** until their end is recorded. The harness
  keeps the open ones by their `action` event's `seq`, and records only
  the first end of each. One still open **60 s**
  (`Harness.pendingMaxMs`) after its result is ended as failed with
  `no word it finished`, on the runtime's 1 s tick (`Harness.tick`), and
  the app log says `harness: <name> was still in progress after <N> ms;
  ended it`. So HISTORY never says in progress for good, whatever the
  action forgot.

### 5.2 Passes

A pass isn't something that happened to Boop, so it's no event: only
`debug.jsonl` keeps it (§9). Its line has `for` (the `seq` of the raw
event its view event came from, or null for a forced one), `now` (the
view event's `id`, `type`, `phase` and `line`), `answers` (each
question's `choice`, and `p`, every option's probability to three
places), `dropped` (why no action ran, or null) and `latency_ms`.

### 5.3 The text form

`StateText` builds the state's HISTORY and NOW for each pass. It's a
pure function of the view's events, the closing line (step 5) and the
clock, and the view is a pure function of the transcript, so a logged
pass can be rebuilt exactly by folding `debug.jsonl`'s events up to its
`seen` (§9) into a fresh view. An action's end recorded while Jev
answered lands in the log before the pass, but the state was built when
the pass started, without it, and `seen` leaves it out. StateText places
lines, notes and actions' messages and never writes them, apart from
marking a started action's progress (step 3).

1. **NOW** is the view event the pass is for.
2. **HISTORY's view events** are those before NOW, from the last **10
   minutes** (`StateText.historyMs`) or since the oldest turn still
   working began, whichever reaches further back, then at most the
   newest **40** (`StateText.historyLimit`), and any older one whose
   started action is still in progress (step 3), so a pass sees what
   Boop is still doing however many view events came since. The harness
   ends a started action within a minute (§5.1), so few ever stay.
3. **Under each** go its notes, then what Boop did: its `did` lines in
   order, rule actions and the brain's. A started one's message ends in
   ` (in progress)` until its end; after that it's plain if it was done,
   and left out if it didn't happen, so HISTORY shows only what Boop did
   or is doing. A forced action counts as done about the latest view
   event before it.
4. **Each view event** is written oldest first as `<when>: <line>`, with
   `<when>` relative to now: `just now` under a minute, then `N min
   ago`, then `N h ago`. Its notes and what Boop did follow, indented two
   spaces, one line each.
5. **HISTORY closes** with the line the runtime hands it, if any:
   `mood`'s saying how long Boop has been in a mood other than happy,
   once it has changed since launch ([DECISIONS.md](DECISIONS.md) §4),
   which the moods' fades are read against:

   ```
   Boop has been grumpy for under a minute.
   ```
6. **NOW** is a heading with the time and weekday, NOW's line and notes,
   then what the rules did about it or `Boop did nothing on its own.`

## 6. The state

One plain-text document in five parts, always in this order, built
fresh for every pass since Jev keeps no session:

| Part | Kind | Source |
| --- | --- | --- |
| The guide (no heading) | Static, then generated | [steering/guide.md](../steering/guide.md), then how to read HISTORY and NOW (§6.1) |
| `PERSONALITY` | Static, the one chosen in Settings | `plan/steering/personality/<name>.md` ([boop](../steering/personality/boop.md), [chatter](../steering/personality/chatter.md)) |
| `MOOD` | Static, the current mood's | `plan/steering/mood/<mood>.md` ([happy](../steering/mood/happy.md), …), read from the mood store at each pass |
| `HISTORY (oldest first; indented lines add to the line above)` | Built | The view and the closing line (§5.3) |
| `NOW (14:23, Tuesday)` | Built | The view event this pass is for (§5.3) |

The guide and its generated part are joined by single line breaks; the
other parts follow, each after a blank line. The runtime supplies
everything but the view's events through one closure (`parts`): the
steering text, the line that closes HISTORY (§5.3), the view's oldest
working turn, and the time (`Runtime.stateParts`). The harness never reads them.

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
- HISTORY is oldest first. Each line says how long ago it happened.
  Lines indented under it add to it: an agent's last message, then
  what Boop did. A line of what Boop did ending in (in progress)
  hasn't finished yet.
- NOW is what to react to. Its last line is what Boop already did on
  its own, by reflex.
[EVENTS.md §8.1]
```

### 6.2 Sizes

Each static part has a budget in tokens (`Steering.Budget`), counted as
bytes ÷ 4, which overestimates English: the guide 300 (now 296), a
personality 600 (`boop` 569, `chatter` 319) and a mood 175 (136–169), raised from 150 when the moods took four reasons from the notes ([DECISIONS.md](DECISIONS.md) §2.3): Jev reads only the current mood's file, so it costs at most 25 tokens a request.
A part over its budget is logged at launch (`steering: over budget: …`),
and a test keeps every file within it. The generated reading part is
about 200 tokens and HISTORY's 40 view events about 1,200, and each
prompt or last message quoted under one adds up to about 80 more (300
characters). With the questions a request is about 3,400 tokens with
nothing quoted, and could reach about 6,500 in the worst case, every one
of the 40 quoting 300 characters. The evals' states came to 1,000–1,550,
and a busy working day's ([EVALS.md](../EVALS.md) §5) to 1,250–2,100,
before prompts and last messages were quoted.

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
| Deadline for the whole pass | **1.5 s**, about five times Jev's usual time, with room for one retry and for a slower first answer on steering Jev hasn't seen. There's no warm-up pass. Its timer fires within 5 ms of it: the system's default leeway would let it fire up to 7% late | `Harness.deadlineMs`, `Harness.deadlineLeewayMs` |
| One retry, after | **300 ms**, on a 429, any 5xx, or a connection that failed (not one that timed out), unless the deadline would pass first | `JevBrain.retryAfterMs` |
| The HTTP request's own timeout | 2 s (the deadline's whole seconds + 1); the deadline cuts it off first | `JevBrain.answer` |

**A dropped pass** runs no action, so Boop does only its rule
reactions. The `pass` line's `dropped` says why:

| `dropped` | When |
| --- | --- |
| `late: no answer within 1500 ms` | The deadline passed. The pass's `latency_ms` is then the deadline's, not the brain's, so the request goes on to its end (the HTTP timeout at most), off the pass, and the app log says when it came: `harness: jev:jev-latest answered after 1702 ms, too late for the turn start pass`, with `: ` and why if it failed. Its answer is thrown away |
| `jev: HTTP <status>` | Not 200, after the retry. Only the status is kept, since an error body may repeat the request |
| `jev: no answers` | The body had no `answers` object |
| `jev: no usable answer for <key>` | A question left out, or answered with an option it doesn't have |
| `something needs you`, `Boop is answering these pokes` | The view event waited behind a running pass, and by the time its turn came something needed you, or, for a poke, the pass's reaction answered its run ([EVENTS.md](EVENTS.md) §6). The brain wasn't asked, so the line has no state and a `latency_ms` of 0 |
| `cancelled`, or an error's own text | The pass's task was cancelled, or the request failed some other way |

**When Jev keeps failing, the popover says so.** The harness counts the
passes that asked Jev and dropped in a row (`Harness.trouble`, a
`BrainTrouble`), and the Overview pane shows a "Jev isn't answering"
notice with the reason. An HTTP 401 or 403 (the key) or 402 (out of
credit) shows it at once, since only the person can fix those; anything
else shows it after **3** in a row (`BrainTrouble.showAfter`), so one
slow answer doesn't. The next pass that runs clears it, and so does a new
key. A pass that never asked Jev (`something needs you`) doesn't count.

When the body came back but couldn't be used, the app log gets its size,
never its text: `harness: jev:jev-latest answered what couldn't be used
(N bytes)`.

**The key** comes from `BOOP_JEV_KEY`, else, in the menu-bar app only,
the Keychain, which Boop reads through `/usr/bin/security`
([ARCHITECTURE.md](../ARCHITECTURE.md) §11). `Boop --headless` and
`boopdev` read only the variable, so a run from an agent shell never
uses the owner's key. The runtime reads it off `home` and the main
thread, since a Keychain prompt would stall both. Until it's read, and
without one, there's no brain: no view event wakes it
([EVENTS.md](EVENTS.md) §6), and nothing reacts to what agents do. A key saved in Settings takes effect
from the next event.

**The brains:**

| Brain | `id` | Used by |
| --- | --- | --- |
| `JevBrain` | `jev:jev-latest` | The app with a key, and the evals |
| `ScriptedBrain` | `scripted` | Tests: a script sees the state and questions and returns answers. `Boop --headless --brain scripted` uses `pipelineCheck`, which answers every pass `mood: happy`, `react.mood: excited`, `react.loops: once`, `word.feeling: yay`, `word.about: none`, and `react.animation: cheer` when NOW is a turn finished done (else `none`) |

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
waiting event, a dropped pass, when the brain answered a pass it was
late for (§7), an action that sat a pass out (§2), a slow action, an
unusable answer's size, forced answers it left out, and a started action
it ended for staying open too long (§5.1).

**Debug mode** is `Boop --debug`, in the menu-bar app (`make debug`) or
headless. It prints to the terminal that started the app: each hook with
what the adapter made of it, every line sent to the device, and each
view event, pass and action, readably. From a headless run with the
scripted brain and no device (`--link none`), as `boopdev watch` prints
its `debug.jsonl`:

```
▸ 1 turn start: claude started turn 1 on "jetpack".
    You asked: "PRIVATE_PROMPT_7001 fix the flaky test"
  pass scripted 0 ms: mood happy 1.00 · react.animation none 1.00 · react.loops once 1.00 · react.mood excited 1.00 · word.about none 1.00 · word.feeling yay 1.00
    │ <the whole state for the first pass, then only its HISTORY and NOW>
  … react: Boop made an excited face, held once, and mumbled "…yay!"
  ✗ react (5) didn't happen: no device connected
  … needs_you (rule): Boop showed that claude needs you.
▸ 2 tool wait (no pass): claude needs you on "jetpack".
  · needs_you (rule) ended
```

A view event that doesn't wake the brain is marked `(no pass)`, and a
failed action `✗`. A started action is marked `…`, and its end prints as
a line of its own when it comes, naming the action and its `seq`:
`  ✓ react (15) done`, or `  ✗ react (15) didn't happen: <why>`. A
rule's action is marked `(rule)`. Of the raw events only actions print:
the view events say the rest. (The eval's queue ends a reaction at once,
`done` unless its step says otherwise, [EVALS.md](../EVALS.md) §1.) The
state goes to the terminal only, never `boop.log`.

**`debug.jsonl`,** in the state directory, is emptied in place at every
launch. Before emptying it, the app keeps a copy of the last launch's
lines as `debug.1.jsonl`, moving older copies up to `debug.10.jsonl`
(`DebugLog.keptLaunches`) and letting the oldest go, so relaunching
mid-day doesn't lose the morning. An empty file isn't kept.
`boopdev watch [FILE]` prints it as the terminal does, following it as it
grows. Each line has one kind and `received_at_ms`, the app's clock,
which headless `advance` moves:

| Line | When | Holds |
| --- | --- | --- |
| `event` | Every event the transcript records ([EVENTS.md](EVENTS.md) §2) | The event, as its transcript line |
| `view` | Every view event, as the pipeline gates it | `id`, `type`, `phase`, `from`, `line`, `notes`, `wakes_brain` and `facts` |
| `pass` | Every pass (§5.2), dropped ones included | A Jev pass also has `state` (the whole state sent), `questions` (the keys asked, in order), `brain` (its `id`) and `seen` (the transcript's last `seq` when its state was built, so a rebuild folds the events up to it, §5.3). A forced pass has `questions` (the keys it answered) and `by`, and no `state` or `brain` |
| `questions` | Once, as the file's first line, before the socket or the link can add one | Every action's questions in order: `action`, `key`, `text`, and each option's `name`, `what` and `not_for` |
| `sent` | Every line sent to the device, whatever the link, none included | The line, verbatim ([PROTOCOL.md](../PROTOCOL.md) §3) |
| `status` | When the personality, the brain, the sessions or the connection changes | `personality`, `brain` (an `id`, or `none`), `sessions` (`agent`, `project`, `status`) and `connected`; the mood is in `sent`'s `state` |

The last three are for the dashboard (`internal/tools/boopctl dash`);
the terminal and `boopdev watch` skip them.

**Dev lines.** Headless, or in debug mode, the hook socket also takes
`{"dev":…}` lines; plain `make run` ignores them. Nothing replies: what a
line did shows in `debug.jsonl`. Any other `dev` value is ignored.

| Line | Does |
| --- | --- |
| `{"dev":"advance","ms":N}` | Headless only: moves the app's clock forward N ms, then ticks |
| `{"dev":"answer","answers":{"react.mood":"grumpy","word.feeling":"again"}}` | A **forced pass**: each choice at probability 1, handed to the actions exactly as Jev's answers would be. It runs at once on `home`, needs no brain or key, and leaves a running or waiting pass alone. A choice that isn't one of its question's options is left out. The actions keep their own rules. Logged as a `pass` line, and its actions recorded `by` `dashboard`, for no event; no `brain` line in `boop.log` |
| `{"dev":"mood","mood":"grumpy"}` | Sets the mood at once through the mood action, device included ([DECISIONS.md](DECISIONS.md) §4). Recorded as an `action` named `mood`, for no event, `by` `dashboard`, refusals included |
| `{"dev":"report"}` | Saves a bug report, as the button does (below) |

A forced pass that cheers, its action and the action's end, from a
headless run with no device (`--link none`), so the reaction never
played ([DECISIONS.md](DECISIONS.md) §5):

```jsonl
{"pass":{"answers":{"react.animation":{"choice":"cheer","p":{"cheer":1}},"react.loops":{"choice":"twice","p":{"twice":1}},"react.mood":{"choice":"proud","p":{"proud":1}},"word.feeling":{"choice":"finally","p":{"finally":1}}},"by":"dashboard","dropped":null,"for":null,"latency_ms":0,"questions":["react.mood","react.animation","react.loops","word.feeling"]},"received_at_ms":1790575002520}
{"event":{"seq":1,"ts":1790575002522,"source":"boop","type":"action","phase":"start","specific_type":"react","data":{"by":"dashboard","for":null,"latency_ms":0,"message":"Boop played a cheer in a proud face, held twice, and mumbled \"…finally!\"","ok":true}},"received_at_ms":1790575002522}
{"event":{"seq":2,"ts":1790575002523,"source":"boop","type":"action","phase":"end","specific_type":"react","data":{"by":"dashboard","for":1,"outcome":"failed","why":"no device connected"}},"received_at_ms":1790575002523}
```

**A bug report.** The ladybug button in the popover's footer (⌘B)
saves everything needed to work out afterwards what Boop saw and did
this launch, debug mode or not, then shows it in Finder and copies its
path, to hand to an agent. For that, the app always keeps this launch's
`debug.jsonl` lines in memory (`DebugLog.Recent`), states and all, up
to 8 MB, the oldest let go first; they go nowhere until the button is
pressed. The report is a new folder,
`bug-reports/<yyyy-MM-dd-HHmmss>/` in the state directory (the
transcript's own files are beside it, in `transcript/`, §5.1):

| File | Holds |
| --- | --- |
| `debug.jsonl` | Those lines, in the format above, so `boopdev watch` prints it |
| `boop.log` | The log's last megabyte: replaced view events, late answers, actions that sat a pass out |
| `settings.json`, `mood` | Copies, when they exist |
| `about.json` | The app's and firmware's versions, the link, whether it's connected, debug mode, the personality, mood, brain and sessions, and when it was taken (`taken_at_ms` on the app's clock, `taken_at_wall_ms`) |

**A day's summary.** `boopctl day` (`make day` for the everyday app,
[VERIFICATION.md](../VERIFICATION.md) §2) reads `debug.jsonl` and the
kept launches', oldest first, and sums up one local day by the hour from
the lines alone:

| It counts | From |
| --- | --- |
| Cheers, and working chatter in older logs | A `sent` moment with `anim` `cheer`: the brain's since 2026-09-28 (older logs also have ones the dashboard played, which only their `sent` line records); and a `say` without a `mood`, the rules' chatter before then |
| The brain's reactions, and their faces | A `react` action for a Jev pass, started or refused, in the face its pass's `react.mood` answer chose (`react` in older logs). Those `by` the dashboard were forced, and are counted apart |
| Alerts, and each time something needed you | A `sent` state whose `attn` is new, or has a different `id`, agent or project ([PROTOCOL.md](../PROTOCOL.md) §3; a missing `id` reads as 0). Needing you lasts from the `state` that brings `attn` to the first without it, or to the end of its launch |
| Mood changes, and what made each | A `sent` state's `mood`, and the `mood` action right after it: its view event, or `by` the dashboard. A launch's first `state` in a mood other than the last launch's changed between launches |
| Brain passes, dropped ones, and ones that chose `none` | `pass` lines with a `brain`; forced ones are counted apart. The median and slowest times are of the passes answered in time, since a dropped pass's `latency_ms` is the deadline's (§7). A view event that woke the brain with no `pass` for it was replaced by a newer one while a pass ran |
| Reactions that didn't happen, and why | A `react` action with `ok: false` (its message is the reason), or an action's `end` that isn't `done` (its `why`); the forced ones apart |
| Pokes | `poke` view events |
| Time running, and with the device connected | Each launch's first and last lines, and `status` lines' `connected` |

## 10. Where it lives

| Part | File | Job |
| --- | --- | --- |
| Harness | `app/BoopKit/Harness/Harness.swift` | One pass running and one waiting; asks, hands out answers, records actions; started actions until they end, and their ceiling (`tick`); forced passes; `respond(to:)`, one view event straight through for the evals |
| Contracts | `app/BoopKit/Harness/Contracts.swift`, `app/BoopKit/Core/Event.swift` | `Action`, `Question`, `Option`, `Answer`, `ActionResult`, `Pending`, `JSONValue`; `Event` |
| Transcript | `app/BoopKit/Harness/Transcript.swift` | The events, their files, and reading them back |
| Pipeline | `app/BoopKit/App/Pipeline.swift` | Records each input, hands it to the core and the view, and gates the view events |
| The view | `app/BoopKit/Core/TranscriptView.swift` | View events, their lines, the keep rule, heartbeats ([EVENTS.md](EVENTS.md)) |
| State text | `app/BoopKit/Harness/StateText.swift` | HISTORY, NOW and the reading part, put together; pure |
| Steering | `app/BoopKit/Harness/Steering.swift` | Loads the static parts, read-only, and checks their budgets |
| Brain | `app/BoopKit/Harness/Brain.swift`, `app/BoopKit/Brains/JevBrain.swift` | The `Brain` protocol and `ScriptedBrain`; Jev and its key |
| Debug log | `app/BoopKit/Harness/DebugLog.swift` | The `debug.jsonl` lines, and printing them readably, an action's end by its name |
| Wiring | `app/BoopKit/App/Runtime.swift` | Registers the actions, supplies `parts`, reads the key, takes dev lines, reads the transcript back, ticks the pipeline and the harness every second |
| Rule actions | `app/BoopKit/Core/Core.swift` | The wiggle and "needs you" ([EVENTS.md](EVENTS.md) §2) |
| Actions | `app/BoopKit/Actions/` | [DECISIONS.md](DECISIONS.md) |
