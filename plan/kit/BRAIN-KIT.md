# The brain kit

Updated 2026-09-30. The generic, open-sourceable harness Boop's brain runs
on: give anything a personality with Markdown plus multiple choice. It's
the second of three pieces Boop is being split into (A, agent hooks to
events; B, this; C, the device link and test rig, later). This spec is
the kit's contract. How Boop sits on top of it is in §13, and Boop's own
harness spec ([harness/HARNESS.md](../harness/HARNESS.md)) says what Boop
adds.

The code is the `BrainKit` target (`app/BrainKit/`, Foundation only, so
it builds on Linux too). The log format (§2), the prompt's layout (§7) and
the question-and-answer shape (§5) are written so a port to another
language is a translation; §12 says what a port must match and what to
test it against.

## 1. What it is

A small box with registration on both sides and a record in the middle.
Things happen and go into the log as events. For each kind of event you
can register a function that turns it into a line of English by looking
back at the log. When a kind you registered to wake the brain arrives, the
kit builds a plain-text prompt (your sections, then HISTORY and NOW), asks
every output's multiple-choice questions in one request, hands each
output its own answers, and writes what the outputs did back into the log.
Rules are your own code that reacts to an event at once and records what
it did. Everything app-specific (a mood graph, a voice, faces, who needs
you) is yours, on top.

```
 inputs (registered)          the kit                                    outputs (registered)

 kind → line, wake  ──► log (every event, on disk)
                         │ a transform turns each into a line (looking back at the log)
                         ▼
                        prompt: your sections + HISTORY + NOW ──► brain ──► answers ──► output.run()
                         ▲                                                                    │
                         └──────────────── what it did, recorded as an event ◄───────────────┘
```

**The one rule the kit keeps: the log is the only state.** Lines,
questions, sections, a `Choice`'s value and which event the brain answers
next are all worked out from the log. The only thing held in memory
besides the log is which call to the brain is running (§9). A function
you register may cache what it works out, as long as the same log always
gives the same answer.

## 2. Events and the log

### 2.1 An event

```swift
public struct Event {
    var seq: Int                  // stamped by the log: counts on across days and launches
    var at: Int64                 // unix milliseconds: stamped by the log unless the emitter set it
    var source: String            // who it's from: "ci", "device", "claude", "self"
    var kind: String              // what it is: "build_failed", "press", "turn_end"
    var line: String?             // a line of its own, for a kind with no transform (§3)
    var data: [String: JSONValue] // everything else
}
```

`source` and `kind` are free strings. There are no fields for waking,
phases, sessions or anything else: an app that needs them puts them in
`data`. `e["branch"]` reads `data`.

On disk and on the wire an event is one JSON line, the keys in this
order, `line` only when there is one, and `data`'s keys sorted:

```json
{"seq":408,"at":1790676542311,"source":"ci","kind":"build_failed","data":{"branch":"main","run":812}}
```

### 2.2 What the kit writes itself

The kit's own events have `source` `self`. Their `for` is the `seq` of
the event they answer.

| `kind` | When | `data` |
| --- | --- | --- |
| `did` | A rule or an output did something (§4, §5) | `for` (or null), `by` (`rule`, `brain`, or who forced it), `action` (the output's or rule's name), `message` (the line HISTORY shows), `ok`, `open` (true while something that takes a while plays, §5.3), `latency_ms` for an output, and the output's own facts, which the kit never reads |
| `ended` | Something that took a while finished, or never will (§5.3) | `for` (the `did`), `action`, `by`, `outcome` (`done` or `failed`) and, when failed, `why` |
| `pass` | Every call to the brain, dropped ones included, and every forced pass (§9) | `for` (or null), `brain` (its `id`) or `by` (who forced it), `answers` (each key's `choice`, and `p`, every option's probability to three places), `dropped` (why no output ran, or null), `ms` |

```json
{"seq":409,"at":1790676542312,"source":"self","kind":"did","data":{"action":"flash","by":"rule","for":408,"message":"Beacon flashed red on its own.","ok":true}}
{"seq":410,"at":1790676542601,"source":"self","kind":"pass","data":{"answers":{"play":{"choice":"wobble","p":{"cheer":0.06,"none":0.2,"wobble":0.74}},"tone":{"choice":"worried","p":{"calm":0.19,"worried":0.81}}},"brain":"jev:jev-latest","dropped":null,"for":408,"ms":286}}
```

### 2.3 The log

`Log` is append-only. Each event gets the next `seq`, and `at` if it had
none. With a folder, each event is written as it's appended to
`<folder>/<yyyy-mm-dd>.jsonl`, one file a day; files older than
**14 days** are deleted at launch and at each new day. A launch reads the
files back into memory and keeps the last **24 hours** there (`keepMs`,
which an app may raise), dropping older events as new ones come. A line
that doesn't parse, such as one a crash cut short, is skipped, and a file
that ends mid-line is ended first so the next line isn't glued to it.
Without a folder (tests) it's in memory only. An app whose older files
hold another shape of line passes a `decode` for them (Boop's does, §13).

### 2.4 Looking back: `LogView`

Every function you register gets a `LogView`, a read-only view of the log.
A transform's view stops just before its event, so replaying the log gives
the same lines; the others see everything so far.

```swift
struct LogView {
    var now: Int64                                                   // the event's `at`, or the clock
    func last(_ kind: String, where: ((Event) -> Bool)? = nil) -> Event?
    func all(_ kind: String, since: Event? = nil, where: ((Event) -> Bool)? = nil) -> [Event]
    func count(_ kind: String, since: Event? = nil, where: ((Event) -> Bool)? = nil) -> Int
    func count(_ kind: String, within ms: Int64) -> Int              // at or after now - ms
    func events(after seq: Int) -> ArraySlice<Event>                 // every kind, oldest first
    func event(_ seq: Int) -> Event?
}
```

`since` means after that event; `since: nil` means everything in view.

## 3. Inputs

### 3.1 Registering a kind

```swift
h.input("build_failed", wake: 1) { e, log in
    let streak = log.count("build_failed", since: log.last("build_passed"))
    return streak == 0 ? "The build on \(e["branch"]!) failed."
                       : "The build on \(e["branch"]!) failed again, \(streak + 1) in a row."
}
h.input("press", wake: 0, when: { e, log in !link.playing }) { e, log in
    let n = log.count("press", within: 3000)
    return n == 0 ? "You pressed the button." : "You pressed the button \(n + 1) times in a row."
}
```

- **The transform** returns `nil` (the event is hidden: no line, and it
  never wakes the brain), a `String`, or `Line(text, notes:, facts:)`.
  Notes go indented under the line. Facts are for your logs and tools:
  the kit hands them to `onLine` and never shows or stores them.
- **Its output is never stored.** The kit works out each event's line
  once, as it's emitted and for every event read back at launch, in
  order, and keeps it in memory with the event.
- **A registered kind with no transform** shows the event's own `line`,
  or else a short rendering of its data: `hold: secs 2`. **A kind you
  never registered** has no line. Its events are still logged and
  readable by every look-back.
- **`wake`** is the kind's priority. Left out, the kind never wakes the
  brain. A higher number goes ahead of lower ones waiting; one at `0`
  gives way to any newer event that wakes the brain (§9).
- **`when`** is an optional check, asked when the event's turn to wake
  the brain comes (§9). It can read your live state as well as the log.

### 3.2 The file form

`h.load(url)` registers kinds from JSON, for the ones a template does:

```json
{
  "build_passed": {"line": "The build on {branch} passed.", "wake": 1},
  "deploy":       {"line": "{who} deployed {service}."}
}
```

`{field}` is the event's `data` field. A field the event doesn't have is
left as it is written. The code API comes first; the file is sugar.

### 3.3 Three ways in

All three end in the same `emit`:

| Way | For |
| --- | --- |
| `h.emit(source:kind:data:line:)`, or `h.emit(event)` | Your own code |
| `EventServer`, a Unix socket that takes one JSON event per line (`{"source":…,"kind":…,"data":…}`), and the `kit-emit` command line | Other processes: a CI script, a cron job. `kit-emit --socket /tmp/beacon.sock ci build_failed branch=main run=812` |
| The device's `ev` lines | Piece C, later: `source` `device`, and `did` for what it already did on its own |

## 4. Rules

A rule is your own code that runs at once on an event, before the brain
hears of it, and never waits for the brain.

```swift
h.on("build_failed") { e in
    link.do("flash", ["color": "red"])
    h.did("Beacon flashed red on its own.", for: e, action: "flash")
}
```

- `h.on("*")` runs for every event, the kit's own included.
- Rules run in the order they were registered, right after the event is
  logged and before the kit looks at waking the brain, so a `when` sees
  what the rule changed.
- `h.did(message, for:, action:, by: "rule")` records what a rule did as
  a `did`. NOW shows the rule's `did`s for its event; HISTORY shows them
  under their event, as it does the brain's (§7).
- **A message is the whole sentence HISTORY shows.** The kit adds nothing
  to it but ` (in progress)` (§5.3).

## 5. Outputs

### 5.1 The protocol

```swift
protocol Action: AnyObject {
    var name: String { get }
    func questions(now: Event?, log: LogView) -> [Question]
    func run(_ answers: Answers, now: Event?, log: LogView) -> ActionResult?
}

struct Question { key, text, about, judgeBy: String; options: [Option] }
struct Option   { name, what: String; notFor: String? }       // `what` is what the option means
struct Answer   { choice: String; probabilities: [String: Double] }
typealias Answers = [String: Answer]                            // question key → answer
```

`h.output(action, openFor:)` registers one; they run in registration
order. `now` is the event the brain is answering, nil for a forced pass.

- **Questions are built for every call,** from NOW and the log, so
  options can follow anything: a graph, a streak, the time. Question keys
  must be unique across outputs (the kit refuses to start otherwise);
  options change freely.
- **All questions go in one request.** Each output's `run` gets only the
  answers to its own questions.
- **`run` returns** `.done(message)`, `.failed(why)`,
  `.started(message, pending)` (§5.3), or `nil` for "did nothing". Each
  may carry `facts` for your tools. A result becomes a `did`, `by`
  `brain`, `for` NOW; `nil` records nothing.
- **Outputs run one at a time, on the kit's queue.** Slow work is handed
  off: a `run` over **300 ms** is logged.

### 5.2 What HISTORY shows

A `did` that's `ok` shows under its event: plainly once done, with
` (in progress)` while open. One that failed, or that ended failed, isn't
shown: HISTORY shows only what was done or is being done. A `did` for no
event (a forced one) shows under the latest line before it.

### 5.3 Things that take a while

An animation, a sound or a line spoken plays on after `run` returns. The
output returns a handle and hands it to whatever will know how it went:

```swift
func run(_ a: Answers, now: Event?, log: LogView) -> ActionResult? {
    guard let pick = a["play"]?.choice, pick != "none" else { return nil }
    let p = Pending()
    link.do(pick, ended: p)                       // finishes p when the device says how it went
    return .started(pick == "wobble" ? "Beacon wobbled." : "Beacon cheered.", p)
}
```

The kit logs a `did` with `open: true` at once, and an `ended` when it
finishes. An open `did` ends in one of three ways, each an `ended`:

| How | `ended` |
| --- | --- |
| The handle finishes: `p.finish(.done)` or `p.finish(.failed("no device"))`. Only the first call counts, and one that comes before the kit has logged the `did` is kept until it has | `outcome` as given |
| Still open `openFor` after it started (**60 s** unless the output says), on the tick | `failed`, `no word it finished` |
| The app relaunched with it open: its handle went with the last launch | `failed`, `restarted` |

Whether a `did` is in progress is worked out from the log: open, with no
`ended` yet.

### 5.4 Forcing a pass

`h.force(["tone": "grim"], by: "dashboard")` hands the outputs answers
without asking the brain, each at probability 1, for no event. It needs
no brain, runs at once and leaves a call that's running alone; a choice
that isn't one of its question's options is left out. It's logged as a
`pass` with `by`. An output that acts outside a pass while a call runs
(`h.force(action) { … }`, or a forced pass) sits that call's answers out,
since they were about the state before.

## 6. `Choice`

The one ready-made output: a named value the brain can change, such as a
tone or a mood. It stores nothing. Its value is the `to` of its latest
`did` in the log, or its start.

```swift
let tone = Choice(name: "tone", start: "calm",
    question: "After NOW, how does Beacon feel?",
    about: "the NOW and HISTORY sections",
    judgeBy: "the TONE section, its reason to leave",
    said: { from, to in "Beacon went from \(from) to \(to)." },
    options: { current, now, log in
        current == "calm"
            ? [Option("calm", "Stay calm: NOW is no reason to worry."),
               Option("worried", "Failures keep coming.", notFor: "A single failure.")]
            : [Option("worried", "Stay worried: the build is still red."),
               Option("calm", "A build passed: all is well again.")]
    })
h.output(tone)
h.section { log in steering["tone/\(tone.value(log))"] }
```

- **Staying put isn't special.** Your options include the current value,
  worded as staying. If the brain picks it, nothing changes and nothing
  is logged.
- **A change** is a `did` with `from` and `to`. Its `at` is
  `tone.since(log)`.
- **After a relaunch** nothing needs restoring: the value is read from the
  log the same way. After a quiet day (no change in the log's 24 hours) it
  starts over at `start`.
- `tone.set("grim")` returns the result for a change forced from outside
  the brain, through `h.force(tone) { tone.set("grim") }`.

## 7. The prompt

### 7.1 Sections

```swift
h.section { log in steering["guide"] }
h.section { log in steering["personality"] }
h.section { log in steering["tone/\(tone.value(log))"] }
h.closing { now, log in tone.value(log) == "calm" ? nil : "Beacon has been \(tone.value(log)) for …." }
h.reachBack { now, log in log.last("build_failed")?.at }   // optional
```

A section is a function run for every call; a nil or empty one is left
out. `Steering(folder:)` loads a folder of Markdown files by path without
`.md` (`steering["tone/calm"]`), with `<!-- comments -->` and front
matter stripped (front matter is yours to read: `steering.frontMatter`).

### 7.2 The layout

The prompt is a pure function: the same log, sections and time always
give the same text. Parts are joined by a blank line:

1. **Your sections,** in order.
2. **How to read HISTORY and NOW** (`Harness.Options.reading`), unless you
   set it to nil and place your own in a section. The default:

   ```
   How to read HISTORY and NOW:
   - HISTORY is oldest first. Each line says how long ago it happened.
     Lines indented under it add to it: its notes, then what <name> did.
     A line of what <name> did ending in (in progress) hasn't finished yet.
   - NOW is what to react to. Its last line is what <name> already did on
     its own, by reflex.
   ```
3. **HISTORY:**

   ```
   HISTORY (oldest first; indented lines add to the line above)
   <when>: <line>
     <note>
     <did message>
   <closing line>
   ```

   - It holds the events with a line before NOW, from the last
     **10 minutes** (`historyMs`) or back to `reachBack`'s time if that's
     earlier, then at most the newest **40** (`historyLimit`), and any
     older one with a `did` still in progress.
   - `<when>` is relative to now: `just now` under a minute, `N min ago`
     under an hour, then `N h ago`.
   - Under each: its notes, then its `did`s in order (§5.2), each indented
     two spaces.
   - Then the closing line, if the closing function gives one.
4. **NOW:**

   ```
   NOW (<heading>)
   <line>
     <note>
   <each of the rules' did messages for it, or "<name> did nothing on its own.">
   ```

   The heading is `14:09, Wednesday` by default, from the wall clock
   (`Options.heading`).

## 8. The brain

```swift
protocol Brain: Sendable {
    var id: String { get }        // "jev:jev-latest", "scripted"
    func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers
}
```

Every question must come back answered with one of its own options, or
the whole answer is unusable. The kit ships two:

| Brain | For |
| --- | --- |
| `JevBrain(key:)` | TypeSafe's Jev, a small multiple-choice model: one request of about 0.2–0.3 s, with each option's probability ([harness/HARNESS.md](../harness/HARNESS.md) §7 has the request) |
| `ScriptedBrain` | Tests: a script sees the prompt and the questions and returns answers; `ScriptedBrain(always:)` gives the same ones every time |

A brain that has no probabilities reports its pick at 1.

## 9. The loop

**The only thing it keeps in memory is which call is running.** Which
event the brain answers next is worked out from the log whenever the
brain is free (a call ended, or an event that wakes it arrived):

1. **Waiting:** events of a kind with a `wake`, with a line, no `pass` yet,
   not the one running, and no older than **10 s** (`maxWaitMs`). So
   nothing from before a relaunch, and no backlog after the Mac slept, is
   ever answered.
2. **Stale:** one at `0` with any newer waiting event after it is passed
   over, and never answered.
3. **Next:** the highest `wake`, the oldest first within it.
4. Its **`when`** is asked now. If it says no, the kit logs a `pass` with
   `dropped` `when` (and the reason the check gives, if it gives one) and
   picks again.

Then one call: the prompt (§7) for that event and every output's
questions, fixed when the call starts, off the kit's queue to the brain,
with a **1.5 s** deadline (`deadlineMs`). A call past the deadline is
dropped: its `pass` says `late: no answer within 1500 ms`, and the answer,
when it comes, is only logged. A call that fails is dropped with the
brain's error. Either way no output runs. Otherwise each output's `run`
gets its answers, in order, and each result is logged. `onPass` hears of
every pass with the prompt it sent, for your own logs.

## 10. The tick and the clock

**The tick.** The kit ticks every second (`h.start()` runs its timer;
`h.tick()` ticks by hand). A tick ends any `did` open past its `openFor`,
then runs your timed checks: each a function of the time and the log that
returns an event to emit, or nil.

```swift
h.tick { now, log in
    guard let red = log.last("build_failed"), log.last("build_passed").map({ $0.seq < red.seq }) ?? true,
          now - red.at >= 3_600_000, log.count("still_red", since: red) == 0 else { return nil }
    return Event(source: "beacon", kind: "still_red")
}
```

A check keeps no state: it doesn't fire twice because the log says it
already did. It runs every second, so it must be cheap.

**The clock.** `Clock` has `now` (milliseconds, for events' `at`,
relative times and `openFor`) and `wall` (for NOW's heading). Both are
wall-clock milliseconds by default; an app may pass a steady clock for
`now` (Boop does). The deadline is a real timer. Tests pass their own
clock and tick by hand.

## 11. A worked example: Beacon

Beacon is a CI light with one button and three one-shots it plays:
`flash`, `wobble` and `cheer`. It's in the repo as
`internal/examples/Beacon/` (§14 step 6), and its test pins this
example (`BeaconTests`).

```swift
let h = Harness(name: "Beacon", brain: JevBrain(key: key), log: Log(folder: dir))
h.input("build_failed", wake: 1) { e, log in … }          // §3.1
h.input("build_passed", wake: 1) { e, log in
    log.last("build_failed").map { f in log.last("build_passed").map { $0.seq < f.seq } ?? true } == true
        ? "The build on \(e["branch"]!) passed after failing." : "The build on \(e["branch"]!) passed."
}
h.input("press", wake: 0) { … }                             // §3.1
h.on("build_failed") { e in link.do("flash"); h.did("Beacon flashed red on its own.", for: e, action: "flash") }
h.output(tone)                                              // §6
h.output(Play(link))                                        // §5.3: none | wobble | cheer
h.section { _ in steering["guide"] }
h.section { _ in steering["personality"] }
h.section { log in steering["tone/\(tone.value(log))"] }
h.emit(source: "ci", kind: "build_failed", data: ["branch": "main", "run": 812])
```

At 14:01 and 14:05 the build fails: each time the rule flashes red, and
the brain stays calm and plays nothing. At 14:06 you press the button. At
14:09 it fails a third time, and the log gets:

```json
{"seq":10,"at":1790690940000,"source":"ci","kind":"build_failed","data":{"branch":"main","run":814}}
{"seq":11,"at":1790690940000,"source":"self","kind":"did","data":{"action":"flash","by":"rule","for":10,"message":"Beacon flashed red on its own.","ok":true}}
```

The prompt the brain is sent ends:

```
HISTORY (oldest first; indented lines add to the line above)
8 min ago: The build on main failed.
  Beacon flashed red on its own.
4 min ago: The build on main failed again, 2 in a row.
  Beacon flashed red on its own.
3 min ago: You pressed the button.

NOW (14:09, Wednesday)
The build on main failed again, 3 in a row.
Beacon flashed red on its own.
```

The brain answers `tone: worried`, `play: wobble`: a `pass` and two
`did`s, the wobble open until the device says it's done. A press three
seconds later is sent:

```
just now: The build on main failed again, 3 in a row.
  Beacon flashed red on its own.
  Beacon went from calm to worried.
  Beacon wobbled. (in progress)

NOW (14:09, Wednesday)
You pressed the button.
Beacon did nothing on its own.
```

so the brain plays nothing, and the tone section is now `tone/worried`.
At 14:20 the build passes after failing, and the brain goes back to calm
and cheers. (The test's own run prints the whole log and every prompt.)

## 12. For a port

A port to another language matches three things exactly, and the rest is
its own business:

- **The log:** one JSON line per event as §2.1 writes it, and the kit's
  own events as §2.2 has them.
- **The prompt:** §7's layout, byte for byte.
- **Questions and answers:** §5.1's shapes, and one request per call.

Two sets of cases pin them: `BeaconTests` (the kit alone, §11) and
Boop's `GoldenStateTests`, which checks every state Boop's 60 eval
scenarios build, 387 of them, against
`internal/app/Tests/Fixtures/golden-states/`.

## 13. How Boop sits on top

Nothing Boop-specific is in the kit. What each of Boop's parts became:

| Boop | On the kit |
| --- | --- |
| Hooks, pokes, what you say, away and back | Events Boop emits: `kind` is the old type and phase (`turn_end`, `tool_wait`, `poke`, `presence_start`), and the old `specific_type`, `session`, `subagent` and `cwd` are in `data` ([harness/EVENTS.md](../harness/EVENTS.md) §1) |
| The core (screen, "needs you", one-shots, the mic) | Rules: the core takes every agent event and poke, and records `did`s for its wiggle and opened threads and `needs_you_start`/`needs_you_end` events of its own |
| The view (`TranscriptView`) | Transforms for the kinds with lines, and `when` checks for the gates. The agent lines need each thread's turn history: `Threads`, a fold of the log that catches up to the event it's asked about, so its answer depends on the log alone |
| Heartbeats | Timed checks |
| Mood | A `Choice`, its options Boop's mood graph |
| React | An output that returns `.started`, its handle finished by the moment schedule when the device's `ended` comes. A reaction your tap cut short is finished `done` once the pokes stop, so HISTORY shows it in progress while they go on |
| Jev's state | Sections: the guide (with Boop's own "how to read" and words), PERSONALITY and MOOD; the closing line; reach-back to the oldest working turn |
| `debug.jsonl`, the dashboard, `boopctl day` | `onLine` and `onPass`, and the log's own lines |
| The transcript | The kit's log, in `transcript/`; lines written before the kit are still read |

## 14. Migration

Each step keeps Boop working and `GoldenStateTests` green:

1. Move the generic files into their own `BrainKit` target, so the
   compiler lists every leak.
2. Open up `Event`, and move the transcript into the kit as its log.
3. The kit's harness: inputs, rules, outputs, `Choice`, the prompt, the
   loop and the tick, with its own tests.
4. Boop on the kit: the view as transforms, the pipeline as rules, mood as
   a `Choice`.
5. Beacon, the second tiny example, in the repo.

[evidence/2026-09-30-brain-kit/PLAN.md](../evidence/2026-09-30-brain-kit/PLAN.md)
tracks them.

## 15. Why it's shaped this way

| Choice | Why |
| --- | --- |
| Lines, not raw JSON, in the prompt | A small model, a budget of about 3k tokens and 1.5 s, and privacy (no code, commands or tool output to the brain); steering examples are written against lines. Not measured |
| Transforms look back instead of keeping state | Replaying the log gives the same prompts; a launch needs no saved view |
| Wake is registration, not a field | An event says what happened; whether it's worth waking the brain is the app's call |
| Messages are whole sentences, not phrases after the name | Boop's HISTORY stays byte-identical: rewording its lines is a steering change only an interleaved A/B eval with Jev could check |
| The queue is worked out from the log | Testable as a pure function; the log shows why each event was answered, passed over or dropped; relaunch and sleep need no code |
| `when` is asked only when an event's turn comes | One check instead of two. An event held back at arrival but allowed by its turn is now answered |
| One ready-made output, `Choice` | Nearly every personality has a named value that picks a Markdown section. A device's one-shots (`Play`) belong with piece C |
| No key-value store | A `Choice`'s value is already readable by sections and rules |
