# JHarness: the spec

Updated 2026-10-01. What JHarness does, exactly: events and the log,
inputs and their lines, rules, outputs and their questions, the one
ready-made output (`Choice`), the prompt, the brain, the loop that asks
it, and the tick. [README.md](README.md) is the overview. Code:
`Sources/JHarness/` (Foundation only, so it's meant to build on Linux
too; only macOS builds it so far), `jharness-emit` in
`Sources/JHarnessEmit/`, and the worked example, Beacon, in `Examples/`
(§11); tested by `Tests/JHarnessTests/` (`swift test`). The log format
(§2), the prompt's layout (§7) and the question-and-answer shape (§5) are
written so a port to another language is a translation; §12 says what a
port must match and what to test it against.

## 1. What it is

A small box with registration on both sides and a record in the middle.
Things happen and go into the log as events. For each kind of event you
can register a function that turns it into a line of English by looking
back at the log. When a kind you registered to wake the brain arrives,
JHarness builds a plain-text prompt (your sections, then HISTORY and
NOW), asks every output's multiple-choice questions in one request,
hands each output its own answers, and writes what the outputs did back
into the log.
Rules are your own code that reacts to an event at once and records what
it did. Everything app-specific (a mood graph, a voice, faces, who needs
you) is yours, on top.

```
 inputs (registered)          JHarness                                   outputs (registered)

 kind → line, wake  ──► log (every event, on disk)
                         │ a transform turns each into a line (looking back at the log)
                         ▼
                        prompt: your sections + HISTORY + NOW ──► brain ──► answers ──► output.run()
                         ▲                                                                    │
                         └──────────────── what it did, recorded as an event ◄───────────────┘
```

**The one rule JHarness keeps: the log is the only state.** Lines,
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
    var at: Int64                 // unix milliseconds: stamped by the log unless the emitter set it (§2.3)
    var source: String            // who it's from: "ci", "device", "claude", "self"
    var kind: String              // what it is: "build_failed", "press", "turn_end"
    var line: String?             // a line of its own, for a kind with no transform (§3)
    var data: [String: JSONValue] // everything else
}
```

`source` and `kind` are free strings. There are no fields for waking,
phases, sessions or anything else: an app that needs them puts them in
`data`. `e["branch"]` reads `data`, a `JSONValue`, which reads as itself
in a string: `"\(e["branch"]!)"` is `main`, a number or yes and no as
written, `null`, and an array or an object as JSON.

On disk and on the wire an event is one JSON line, the keys in this
order, `line` only when there is one, and `data`'s keys sorted:

```json
{"seq":408,"at":1790676542311,"source":"ci","kind":"build_failed","data":{"branch":"main","run":812}}
```

### 2.2 What JHarness writes itself

JHarness's own events have `source` `self` (`Event.harness`;
`e.fromHarness` says whether an event is one). Their `for` is the `seq` of
the event they answer.

| `kind` | When | `data` |
| --- | --- | --- |
| `did` | A rule or an output did something (§4, §5) | `for` (or null), `by` (`rule`, `brain`, or who forced it), `action` (the output's or rule's name), `message` (the line HISTORY shows), `ok`, `open` (true while something that takes a while plays, §5.3), `latency_ms` for an output, and the output's own facts, which JHarness never reads |
| `ended` | Something that took a while finished, or never will (§5.3) | `for` (the `did`), `action`, `by`, `outcome` (`done` or `failed`) and, when failed, `why` |
| `pass` | Every call to the brain, dropped ones included; every event held back when its turn came; and every forced pass (§9) | `for` (or null), `brain` (its `id`, or the one it would have asked) or `by` (who forced it), `answers` (each key's `choice`, and `p`, every option's probability to three places), `dropped` (why no output ran, or null), `held` (why the event was held back, only when it was), `ms` |

```json
{"seq":409,"at":1790676542312,"source":"self","kind":"did","data":{"action":"flash","by":"rule","for":408,"message":"Beacon flashed red on its own.","ok":true}}
{"seq":410,"at":1790676542601,"source":"self","kind":"pass","data":{"answers":{"play":{"choice":"wobble","p":{"cheer":0.06,"none":0.2,"wobble":0.74}},"tone":{"choice":"worried","p":{"calm":0.19,"worried":0.81}}},"brain":"jev:jev-latest","dropped":null,"for":408,"ms":286}}
```

### 2.3 The log

`Log` is append-only. Each event gets the next `seq`, and `at` if it had
none. An `at` never goes back before the last event's, and never past
the clock, so `seq` and `at` keep one order and one wrong clock can't
carry the rest into the future. With a folder, each event is written as
it's appended to `<folder>/<yyyy-mm-dd>.jsonl`, one file a day; files
older than **14 days** are deleted at launch and on the first event of
each new day, and `seq` counts on even when every file has gone. The
launch is `h.resume()`, called once on the harness's queue before the
first emit: it reads the files back into memory, deletes the old ones,
carries `seq` on, and ends any `did` the last launch left open as
`restarted` (§5.3). An app that emits without it starts `seq` over at 1
in today's file. It keeps the last **24 hours** in memory (`keepMs`,
which an app may raise); older events drop out of view on
every event and every tick, so a running app sees just what a launch at
that moment would read back, and their memory goes in batches, once
they're an eighth of what's kept. A line
that doesn't parse, such as one a crash cut short, is skipped, and a file
that ends mid-line is ended first so the next line isn't glued to it.
Without a folder (tests) it's in memory only. An app whose older files
hold another shape of line passes a `decode` for them.

### 2.4 Looking back: `LogView`

Every function you register gets a `LogView`, a read-only view of the log.
A transform's view stops just before its event, so replaying the log gives
the same lines; the others see everything so far. The `did`s, ends and
passes a view reports stop at its cut too.

```swift
struct LogView {
    var now: Int64                                                   // the event's `at`, or the clock
    var events: ArraySlice<Event>                                    // everything in view, oldest first
    func last(_ kind: String, where: ((Event) -> Bool)? = nil) -> Event?
    func lastDid(_ action: String, where: ((Event) -> Bool)? = nil) -> Event? // that output's or rule's newest `did`
    func all(_ kind: String, since: Event? = nil, where: ((Event) -> Bool)? = nil) -> [Event]
    func count(_ kind: String, since: Event? = nil, where: ((Event) -> Bool)? = nil) -> Int
    func count(_ kind: String, within ms: Int64) -> Int              // at or after now - ms
    func events(after seq: Int) -> ArraySlice<Event>                 // every kind, oldest first
    func recent(within ms: Int64) -> ArraySlice<Event>               // every kind, at or after now - ms
    func event(_ seq: Int) -> Event?
    func dids(for seq: Int) -> [Event]                               // the `did`s for that event (§5.2)
    func ended(_ did: Int) -> Event?                                 // that `did`'s `ended`, if any (§5.3)
    func answered(_ seq: Int) -> Bool                                // whether that event has a `pass` (§9)
    func shown(_ did: Event) -> (message: String, inProgress: Bool)? // how HISTORY shows a `did` (§5.2)
}
```

`since` means after that event; `since: nil` means everything in view.

## 3. Inputs

### 3.1 Registering a kind

```swift
h.input("build_failed", wake: 1) { e, log in
    let branch = e["branch"]?.string ?? "main"
    let streak = log.count("build_failed", since: log.last("build_passed"))
    return streak == 0 ? "The build on \(branch) failed."
                       : "The build on \(branch) failed again, \(streak + 1) in a row."
}
h.input("press", wake: 0) { e, log in
    let n = log.count("press", within: 3000)
    return n == 0 ? "You pressed the button." : "You pressed the button \(n + 1) times in a row."
}
h.hold("press") { e, log in log.count("press", within: 3000) >= 4 ? "the button is being mashed" : nil }
```

- **The transform** returns `nil` (the event is hidden: no line, and it
  never wakes the brain), a `String`, or `Line(text, notes:, facts:)`.
  Notes go indented under the line. Facts are for your logs and tools:
  JHarness hands them to `onLine` and never shows or stores them.
- **Its output is never stored.** JHarness works out each event's line
  once, as it's emitted and for every event read back at launch, in
  order, and keeps it in memory with the event.
- **A registered kind with no transform** shows the event's own `line`,
  or else a short rendering of its data: `hold: secs 2`. **A kind you
  never registered** has no line. Its events are still logged and
  readable by every look-back.
- **`wake`** is the kind's priority. Left out, the kind never wakes the
  brain. A higher number goes ahead of lower ones waiting; one at `0`
  gives way to any newer event that wakes the brain (§9).
- **`h.hold(kind) { e, log in … }`** is an optional check, asked when an
  event's turn to wake the brain comes (§9): a reason to hold it back, or
  nil. It can read your live state as well as the log.

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
| `EventServer`, a Unix socket that takes one JSON event per line (`{"source":…,"kind":…,"data":…}`), and the `jharness-emit` command line | Other processes: a CI script, a cron job. `jharness-emit --socket /tmp/beacon.sock ci build_failed branch=main run=812`. Each connection is read on its own and each line handed on as it ends; a connection quiet for half a second is closed, and one is read up to 1 MB. In `jharness-emit`, a value that's a whole number written plainly (`812`, `-3`, not `007`) is a number, `true` and `false` are yes and no, and the rest are strings |
| A device's own reports | Your device link emits them like your own code: `source` `device`, and a `did` for what it already did on its own |

## 4. Rules

A rule is your own code that runs at once on an event, before the brain
hears of it, and never waits for the brain.

```swift
h.on("build_failed") { e in
    link.do("flash", ["color": "red"])
    h.did("Beacon flashed red on its own.", for: e, action: "flash")
}
```

- `h.on("*")` runs for every event, JHarness's own included.
- Rules run in the order they were registered, right after the event is
  logged and before JHarness looks at waking the brain, so a hold sees
  what the rule changed. An event a rule emits runs its own rules at
  once, inside the first's.
- `h.batch { … }` runs several emits and your own code, and only then
  wakes the brain: for an app whose rules need more than the event, such
  as a core of its own that decides what an input means.
- `h.did(message, for:, action:, by: "rule")` records what a rule did as
  a `did`. NOW shows the rule's `did`s for its event; HISTORY shows them
  under their event, as it does the brain's (§7).
- **A message is the whole sentence HISTORY shows.** JHarness adds nothing
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

`h.output(action, openFor:, keepOpen:)` registers one (§5.3); they run
in registration order. `now` is the event the brain is answering, nil for a forced pass.

- **Questions are built for every call,** from NOW and the log, so
  options can follow anything: a graph, a streak, the time. Question keys
  must be unique across outputs, and within one; options change freely.
  A call whose questions repeat a key is dropped before it asks: its
  `pass` says `question keys must be unique across outputs: k asked
  twice`, and no output runs. A forced pass (§5.4) is dropped the same
  way.
- **All questions go in one request.** Each output's `run` gets only the
  answers to its own questions.
- **`run` returns** `.done(message)`, `.failed(why)`,
  `.started(message, pending)` (§5.3), or `nil` for "did nothing". Each
  may carry `facts` for your tools. A result becomes a `did`, `by`
  `brain`, `for` NOW; `nil` records nothing.
- **Outputs run one at a time, on JHarness's queue.** Slow work is handed
  off: a `run` over **300 ms** is logged.

### 5.2 What HISTORY shows

A `did` that's `ok` shows under its event: plainly once done, with
` (in progress)` while open. One that failed, or that ended failed, isn't
shown: HISTORY shows only what was done or is being done. A `did` for no
event (a forced one) shows under the latest event with a line before it.
`LogView.shown(did)` gives the same answer for your own tools: the
message and whether it's in progress, or nil.

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

JHarness logs a `did` with `open: true` at once, and an `ended` when it
finishes. Your own code may `p.bind { end in … }` too, to hear how it
ended. An open `did` ends in one of three ways, each an `ended`:

| How | `ended` |
| --- | --- |
| The handle finishes: `p.finish(.done)` or `p.finish(.failed("no device"))`. Only the first call counts, and one that comes before JHarness has logged the `did` is kept until it has | `outcome` as given |
| Still open `openFor` after it started (**60 s** unless the output says), on the tick, unless the output keeps it open | `failed`, `no word it finished` |
| The app relaunched with it open: its handle went with the last launch, so `h.resume()` ends it (§2.3) | `failed`, `restarted` |

An app that holds one past `openFor` on purpose, such as a reaction a
run of taps cut short and still holds, registers its output with
`keepOpen`: a function of the `did` and the log, asked on each tick once
`openFor` has passed. While it says true, the tick leaves the `did`
open.

Whether a `did` is in progress is worked out from the log: open, with no
`ended` yet.

### 5.4 Forcing a pass

`h.force(["tone": "grim"], by: "dashboard")` hands the outputs answers
without asking the brain, each at probability 1, for no event. It needs
no brain, runs at once and leaves a call that's running alone; a choice
that isn't one of its question's options is left out. It's logged as a
`pass` with `by`. `h.force(action, by: "dashboard") { … }` logs one
output's result, made outside any pass. An output that acts outside a
pass while a call runs sits that call's answers out, since they were
about the state before.

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
  is logged. A pick that isn't one of the options it offered changes
  nothing either.
- **A change** is a `did` with `from` and `to`. Its `at` is
  `tone.since(log)`.
- **After a relaunch** nothing needs restoring: the value is read from the
  log the same way. After a quiet day (no change in the log's 24 hours) it
  starts over at `start`.
- `tone.set("grim", log:)` returns the result for a change made outside
  the brain, whatever the options, through
  `h.force(tone, by: "dashboard") { tone.set("grim", log: h.log.view(now: h.clock.now())) }`.
- `tone.restore("grim", by: "upgrade", in: h)` carries over a value your
  app kept before the log did (its own file, say): a change for no event,
  by `by`, with no message, so HISTORY never shows it; `since` is when it
  was restored. Restoring the value it has logs nothing.

## 7. The prompt

### 7.1 Sections

```swift
h.section { log in steering["guide"] }
h.section { log in steering["personality"] }
h.section { log in steering["tone/\(tone.value(log))"] }
h.closing { e, now, log in tone.value(log) == "calm" ? nil : "Beacon has been \(tone.value(log)) for …." }
h.reachBack { e, now, log in log.last("build_failed") { $0.seq < e.seq }?.at }   // optional
```

The closing line and the reach-back each get NOW's event, the time and
the log as of now. The log may hold events newer than NOW's, when its
call starts after they came (§9), so go by the event, not by the log's
newest.

A section is a function run for every call; a nil or empty one is left
out. `Steering(folder:)` loads a folder of Markdown files by path without
`.md` (`steering["tone/calm"]`), with `<!-- comments -->` and front
matter stripped (front matter is yours to read: `steering.frontMatter`).

### 7.2 The layout

The prompt is a pure function: the same log, sections and time always
give the same text. Parts are joined by a blank line:

1. **Your sections,** in order.
2. **How to read HISTORY and NOW** (`Harness.Options.reading`), unless you
   set it to `.none` and place your own in a section, or give your own
   words (`.custom(text)`). The default:

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

JHarness hands each output whatever came back for its questions, so a
scripted brain may answer only some: an output does nothing with an
answer it hasn't, and a `Choice` ignores a pick it didn't offer. A brain
that has no probabilities reports its pick at 1. JHarness ships two:

| Brain | For |
| --- | --- |
| `JevBrain(key:)` | TypeSafe's Jev, a small multiple-choice model: one request of about 0.2–0.3 s, with each option's probability (below) |
| `ScriptedBrain` | Tests: a script sees the prompt and the questions and returns answers; `ScriptedBrain(always:)` gives the same ones every time |

**`JevBrain`** sends one `POST` to `https://api.typesafe.ai/v1/systemone`,
model `jev-latest`, with the prompt as the `state` and every question as
a choice question named by its `key`: its `text`, `about` and `judgeBy`
as `instructions`, and each option's `what` as its criterion (with
`not_for` when it has a `notFor`). Jev reads the state once and answers
each question on its own against it
([TypeSafe](https://docs.typesafe.ai/cookbooks/parallel_questions.md)).
The answer has each question's `choice` and `probabilities`; one left
out, or answered with an option it doesn't have, makes the whole answer
unusable, and the pass is dropped. A 429, any 5xx, or a connection that
failed (not one that timed out) is tried once more after **300 ms**
(`JevBrain.retryAfterMs`), unless the deadline would pass first. The HTTP
request's own timeout is the deadline's whole seconds plus 1, so the
deadline cuts it off first. What a dropped `pass` says when Jev failed:

| `dropped` | When |
| --- | --- |
| `jev: HTTP <status>` | Not 200, after the retry. Only the status is kept, since an error body may repeat the request |
| `jev: can't reach the server` | The connection failed, after the retry (offline, say), so no server answered |
| `jev: no answers` | The body had no `answers` object |
| `jev: no usable answer for <key>` | A question left out, or answered with an option it doesn't have |

When the body came back but couldn't be used, the app log gets its size,
never its text: `harness: jev:jev-latest answered what couldn't be used
(N bytes)`.

## 9. The loop

**The only thing it keeps in memory is which call is running.** Which
event the brain answers next is worked out from the log whenever the
brain is free (a call ended, or an event that wakes it arrived):

1. **Waiting:** events of a kind with a `wake`, with a line, no `pass` yet,
   not the one running, no older than **10 s** (`maxWaitMs`), and logged
   since the launch: nothing up to the last `seq` that `resume` read back
   is answered. So nothing from before a relaunch, however recent, and no
   backlog after the Mac slept, is ever answered.
2. **Stale:** one at `0` with any newer event that wakes the brain after
   it, answered or not, is passed over, and never answered. The app log
   says so once: `harness: press passed over for a newer build_failed`.
3. **Next:** the highest `wake`, the oldest first within it.
4. Its **hold** is asked now. If it gives a reason, JHarness logs a `pass`
   with `held` and the reason, the brain isn't asked, and it picks again.

Then one call: the prompt (§7) for that event and every output's
questions, fixed when the call starts, off JHarness's queue to the brain,
with a **1.5 s** deadline (`deadlineMs`), whose timer fires within 5 ms
of it (`deadlineLeewayMs`). A call past the deadline is dropped: its
`pass` says `late: no answer within 1500 ms`, and the answer, when it
comes, is only noted in the app log (`harness: jev:jev-latest answered
after 1702 ms, too late for the press pass`). A call that fails is
dropped with the brain's error. Either way no output runs. Otherwise each
output's `run` gets its answers, in order, and each result is logged.
`onPass` hears of every pass, held, dropped and forced ones included,
once its outputs have run, with the prompt it sent and what each output
did, for your own logs; `onLine` hears of each line as its event is
emitted (not the lines `resume` works out for the events it reads back).
`h.respond(to: e)` runs one event's call straight through, without the
loop, for evals (`Options.loop` false). `h.use(brain)` swaps the brain
from the next call on (nil for none, and then nothing wakes it); a pass
that asked the one before says so (`Pass.current` false). `h.idle` says
whether nothing runs and nothing waits.

## 10. The tick and the clock

**The tick.** JHarness ticks every second (`h.start()` runs its timer;
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
`now`, so setting the clock back can't stall it. The deadline is a real
timer. Tests pass their own clock and tick by hand.

## 11. A worked example: Beacon

Beacon is a CI light with one button and three one-shots it plays:
`flash`, `wobble` and `cheer`. It's in `Examples/Beacon/`, with its
steering folder (a guide, a personality and one file for each tone), and
`beacon` (`Examples/BeaconDemo/`) runs this example (`BeaconTests` pins
it). The wiring, from `Beacon.swift`:

```swift
let h = Harness(name: "Beacon", brain: brain, log: log, clock: clock, queue: queue, options: options)
h.input("build_failed", wake: 1) { e, log in … }             // §3.1
h.input("build_passed", wake: 1) { e, log in
    let branch = e["branch"]?.string ?? "main"
    let streak = log.count("build_failed", since: log.last("build_passed"))
    return streak == 0 ? "The build on \(branch) passed."
        : "The build on \(branch) passed after \(streak == 1 ? "failing" : "\(streak) failures")."
}
h.input("press", wake: 0) { … }                                // §3.1
h.hold("press") { … }                                          // §3.1: the button being mashed
h.input("still_red", wake: 1) { _, _ in "The build has been red for an hour." }
try h.load(steering.appendingPathComponent("events.json"))    // §3.2: deploy
h.on("build_failed") { e in light.do("flash", ["color": "red"]); h.did("Beacon flashed red on its own.", for: e, action: "flash") }
h.on("build_passed") { e in light.do("flash", ["color": "green"]); h.did("Beacon flashed green on its own.", for: e, action: "flash") }
h.output(tone)                                                 // §6: calm | worried | grim
h.output(Play(light), openFor: 20_000)                         // §5.3: none | wobble | cheer
h.section { _ in words["guide"] }
h.section { _ in words["personality"] }
h.section { log in words["tone/\(tone.value(log))"] }
h.reachBack { e, _, log in /* the red streak's first failure, while red as of NOW or NOW is its pass */ }
h.closing { _, now, log in /* "Beacon has been worried for 11 min." */ }
h.tick { now, log in /* still_red, once, after an hour of red */ }  // §10
```

On a clock from 14:00 on a Wednesday, the build fails at 14:01 and
14:05: each time the rule flashes red, and the brain stays calm and plays
nothing. At 14:06 you press the button. At 14:09 it fails a third time,
and the log gets:

```json
{"seq":9,"at":1791986940000,"source":"ci","kind":"build_failed","data":{"branch":"main","run":814}}
{"seq":10,"at":1791986940000,"source":"self","kind":"did","data":{"action":"flash","by":"rule","for":9,"message":"Beacon flashed red on its own.","ok":true}}
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
`did`s, the wobble open until the light says it's done:

```json
{"seq":11,"at":1791986940000,"source":"self","kind":"pass","data":{"answers":{"play":{"choice":"wobble","p":{"wobble":1}},"tone":{"choice":"worried","p":{"worried":1}}},"brain":"scripted","dropped":null,"for":9,"ms":0}}
{"seq":12,"at":1791986940000,"source":"self","kind":"did","data":{"action":"tone","by":"brain","for":9,"from":"calm","latency_ms":0,"message":"Beacon went from calm to worried.","ok":true,"to":"worried"}}
{"seq":13,"at":1791986940000,"source":"self","kind":"did","data":{"action":"play","by":"brain","for":9,"latency_ms":0,"message":"Beacon wobbled.","ok":true,"open":true}}
```

A press three seconds later is sent, with `tone/worried` as its TONE
section:

```
HISTORY (oldest first; indented lines add to the line above)
8 min ago: The build on main failed.
  Beacon flashed red on its own.
4 min ago: The build on main failed again, 2 in a row.
  Beacon flashed red on its own.
3 min ago: You pressed the button.
just now: The build on main failed again, 3 in a row.
  Beacon flashed red on its own.
  Beacon went from calm to worried.
  Beacon wobbled. (in progress)
Beacon has been worried for under a minute.

NOW (14:09, Wednesday)
You pressed the button.
Beacon did nothing on its own.
```

so the brain plays nothing. The light says the wobble is done at
14:09:08 (`{"seq":16,…,"kind":"ended","data":{"action":"play","by":"brain","for":13,"outcome":"done"}}`).
At 14:20 the build passes, and HISTORY reaches back past its 10 minutes
to the red streak's first failure:

```
HISTORY (oldest first; indented lines add to the line above)
19 min ago: The build on main failed.
  Beacon flashed red on its own.
15 min ago: The build on main failed again, 2 in a row.
  Beacon flashed red on its own.
14 min ago: You pressed the button.
11 min ago: The build on main failed again, 3 in a row.
  Beacon flashed red on its own.
  Beacon went from calm to worried.
  Beacon wobbled.
10 min ago: You pressed the button.
Beacon has been worried for 11 min.

NOW (14:20, Wednesday)
The build on main passed after 3 failures.
Beacon flashed green on its own.
```

The brain goes back to calm and cheers. `beacon` prints the whole log
and every prompt; `beacon listen --socket /tmp/beacon.sock` runs Beacon
live, taking events from `jharness-emit`.

## 12. For a port

A port to another language matches three things exactly, and the rest is
its own business:

- **The log:** one JSON line per event as §2.1 writes it, and JHarness's
  own events as §2.2 has them.
- **The prompt:** §7's layout, byte for byte.
- **Questions and answers:** §5.1's shapes, and one request per call.

Two sets of cases pin them: `JHarnessTests` (JHarness alone, with toy
outputs) and `BeaconTests` (§11). An app on JHarness pins its own the same
way: every prompt its scenarios build, checked against a golden copy.

## 13. Why it's shaped this way

| Choice | Why |
| --- | --- |
| Lines, not raw JSON, in the prompt | A small model, a budget of about 3k tokens and 1.5 s, and privacy (no code, commands or tool output to the brain); steering examples are written against lines. Not measured |
| Transforms look back instead of keeping state | Replaying the log gives the same prompts; a launch needs no saved view |
| Wake is registration, not a field | An event says what happened; whether it's worth waking the brain is the app's call |
| Messages are whole sentences, not phrases after the name | HISTORY reads exactly as each output words it: the harness rewording a line would be a steering change that only an A/B run against the brain could check |
| The queue is worked out from the log | Testable as a pure function; the log shows why each event was answered, passed over or dropped; sleep needs no code, and a relaunch only where the log it read back ends |
| A hold is asked only when an event's turn comes, and logged as a `held` pass | One check instead of two, and the log says why the brain wasn't asked. An event held back at arrival but allowed by its turn is now answered |
| One ready-made output, `Choice` | Nearly every personality has a named value that picks a Markdown section. A device's one-shots belong with the device's own code (Beacon's `Play` is one) |
| No key-value store | A `Choice`'s value is already readable by sections and rules |
