# JHarness

Give anything a personality with Markdown and multiple choice. JHarness
is a small Swift library that sits between the things that happen to
your app and a brain that only answers multiple-choice questions: it
logs every event, turns each into a line of English, and when one is
worth a thought, asks the brain what to do in one request, hands each of
your outputs its own answers, and logs what they did.

It's for a desk gadget, a status light, a companion in a menu bar:
something that should react to what happens with a character of its
own, without free text. It was pulled out of Boop, a desk creature
that watches your coding agents, and Boop's brain runs on it.

[SPEC.md](SPEC.md) says exactly what it does; this page is the overview.

## Install

It builds from source with Swift 6 (Xcode or the Command Line Tools) on
macOS 13 or later, and depends on nothing but Foundation:

```swift
// Package.swift
.package(path: "../jharness"),
// and in a target's dependencies:
.product(name: "JHarness", package: "jharness"),
```

`swift build` in this folder also builds its two tools, `jharness-emit`
and `beacon`, into `.build/debug/`.

## How it works

```
 inputs (registered)          JHarness                                   outputs (registered)

 kind → line, wake  ──► log (every event, on disk)
                         │ a transform turns each into a line (looking back at the log)
                         ▼
                        prompt: your sections + HISTORY + NOW ──► brain ──► answers ──► output.run()
                         ▲                                                                    │
                         └──────────────── what it did, recorded as an event ◄───────────────┘
```

- **The log is the only state.** Every event is one JSON line in
  `<folder>/<day>.jsonl`, kept 14 days, the last 24 hours in memory and
  read back at launch. Lines, questions, a `Choice`'s value and which
  event the brain answers next are all worked out from it.
- **Inputs** register a kind: its line, from the event and the log before
  it, and its `wake`, a priority. Only a kind with a `wake` wakes the
  brain; a `hold` can hold one back when its turn comes, and the log says
  why.
- **Rules** are your own code, run at once on an event, before the brain
  hears of it. `h.did(...)` records what a rule did, so NOW shows it.
- **Outputs** each ask their own multiple-choice questions, built for
  every call, and get only their own answers. What they return is logged
  as a `did`, in progress until something that takes a while (an
  animation, a sound) says it ended. `Choice` is the one ready-made
  output: a named value the brain can change, such as a mood.
- **The prompt** is your sections (Markdown, from a `Steering` folder or
  your code), then HISTORY (the last 10 minutes of lines, with what was
  done under each) and NOW (the event and what the rules did about it).
  The same log always gives the same prompt.
- **The loop** asks one call at a time, with a 1.5 s deadline. The next
  event is the highest `wake` waiting, oldest first; nothing older than
  10 s, and nothing from before a launch, is answered. A call that's late
  or fails is dropped and no output runs. `h.tick { ... }` adds timed
  checks, run every second.
- **The brain** is TypeSafe's Jev (`JevBrain`, with your API key), or a
  `ScriptedBrain` for tests. Anything that answers `Brain`'s one method
  will do.

## An example

A desk lamp that watches CI and worries when the build keeps failing:

```swift
import Foundation
import JHarness

let queue = DispatchQueue(label: "light")  // the harness's one queue
// Jev with a key, or a stand-in that always worries.
let brain: any Brain = ProcessInfo.processInfo.environment["JEV_KEY"].map { JevBrain(key: $0) }
    ?? ScriptedBrain(always: ["tone": Answer(choice: "worried")])
let h = Harness(name: "Light", brain: brain, log: Log(folder: URL(fileURLWithPath: "log")), queue: queue)

// Inputs: each kind's line, from the event and the log before it. With a
// `wake`, it wakes the brain.
h.input("build_failed", wake: 1) { e, log in
    let branch = e["branch"]?.string ?? "main"
    let streak = log.count("build_failed", since: log.last("build_passed"))
    return streak == 0 ? "The build on \(branch) failed." : "The build on \(branch) failed again, \(streak + 1) in a row."
}
h.input("build_passed", wake: 1) { e, _ in "The build on \(e["branch"]?.string ?? "main") passed." }

// A rule: your code, at once, before the brain hears of the event.
h.on("build_failed") { e in
    print("(flashing red)")
    h.did("Light flashed red on its own.", for: e, action: "flash")
}

// An output: a value the brain can change, its options built for each call.
let tone = Choice(name: "tone", start: "calm", question: "After NOW, how does Light feel?",
                  judgeBy: "the GUIDE section") { current, _, _ in
    current == "calm"
        ? [Option("calm", "Stay calm: NOW is no reason to worry."), Option("worried", "Failures keep coming.")]
        : [Option("worried", "Stay worried: the build is still red."), Option("calm", "A build passed.")]
}
h.output(tone)

// The prompt: your sections, then HISTORY and NOW.
h.section { log in "GUIDE\nYou are Light, a desk lamp that watches CI builds. You feel \(tone.value(log))." }

h.onPass = { pass in print("\(pass.prompt ?? "")\n→ \(pass.answers.mapValues(\.choice))\n") }
queue.sync {
    h.resume()  // the launch, before any emit: reads the log back
    h.start()   // ticks every second
}
let server = EventServer(path: "/tmp/light.sock") { e in queue.async { h.emit(e) } }
try server.start()
dispatchMain()
```

Run it, then send it two failures from a shell:

```sh
jharness-emit --socket /tmp/light.sock ci build_failed branch=main run=812
jharness-emit --socket /tmp/light.sock ci build_failed branch=main run=813
```

The second prompt it prints, from a real run:

```
(flashing red)
GUIDE
You are Light, a desk lamp that watches CI builds. You feel worried.

How to read HISTORY and NOW:
- HISTORY is oldest first. Each line says how long ago it happened.
  Lines indented under it add to it: its notes, then what Light did.
  A line of what Light did ending in (in progress) hasn't finished yet.
- NOW is what to react to. Its last line is what Light already did on
  its own, by reflex.

HISTORY (oldest first; indented lines add to the line above)
just now: The build on main failed.
  Light flashed red on its own.
  tone changed: calm → worried.

NOW (21:48, Wednesday)
The build on main failed again, 2 in a row.
Light flashed red on its own.
→ ["tone": "worried"]
```

[Examples/Beacon/](Examples/Beacon/Beacon.swift) is the fuller version
the spec walks through (§11): a button, a hold, a one-shot that plays in
progress until the light says it's done, a steering folder of Markdown,
a reach-back and a timed check.

## Events

Every event is one JSON line, the same on disk and on the socket:
`seq` and `at` (unix milliseconds) stamped by the log, `source` and
`kind` (free strings), `line` when it brings its own, and `data` with its
keys sorted. From the run above:

```json
{"seq":1,"at":1790772508761,"source":"ci","kind":"build_failed","data":{"branch":"main","run":812}}
{"seq":2,"at":1790772508763,"source":"self","kind":"did","data":{"action":"flash","by":"rule","for":1,"message":"Light flashed red on its own.","ok":true}}
{"seq":3,"at":1790772508763,"source":"self","kind":"pass","data":{"answers":{"tone":{"choice":"worried","p":{"worried":1}}},"brain":"scripted","dropped":null,"for":1,"ms":0}}
{"seq":4,"at":1790772508763,"source":"self","kind":"did","data":{"action":"tone","by":"brain","for":1,"from":"calm","latency_ms":0,"message":"tone changed: calm → worried.","ok":true,"to":"worried"}}
```

JHarness's own events are `self`'s: a `did` for what a rule or an output
did, an `ended` for how something that took a while finished, and a
`pass` for every call to the brain, held, dropped and forced ones
included, `for` the event it answered. Events come in three ways, all
ending in the same `emit`: your own code (`h.emit`), the socket
(`EventServer`, one JSON event per line), and `jharness-emit` from a
shell or a CI script.

## The command line

| Command | What it does |
| --- | --- |
| `jharness-emit --socket PATH SOURCE KIND [key=value ...] [--line TEXT]` | Sends one event to a harness's socket. A whole number written plainly (`812`, `-3`, not `007`) is a number, `true` and `false` are yes and no, the rest strings |
| `beacon [--steering DIR]` | Runs the worked example on a virtual clock and prints every event the log wrote and every prompt the brain was sent |
| `beacon listen --socket PATH [--steering DIR]` | Beacon live on a socket, a scripted brain answering, printing each line and pass as it happens |

## Caveats

- **One queue.** Everything but the brain call runs on the queue you
  give the harness; call its methods there. Outputs run on it too, so
  slow work is handed off (a `run` over 300 ms is logged).
- **Keys are unique.** Question keys must be unique across outputs; a
  call that repeats one is dropped with why, and asks nothing.
- **No free text.** The brain only picks among options, and HISTORY
  shows your outputs' messages word for word. What it says is what you
  wrote.
- **macOS so far.** It's Foundation only and meant to build on Linux,
  but only macOS builds it yet.

## Development

```sh
swift test --scratch-path .build/tests
```

The tests use Swift Testing: `JHarnessTests` checks the harness with toy
outputs, `JevBrainTests` Jev's request and answer, and `BeaconTests` the
worked example, pinned as the spec quotes it. The package depends on
nothing but Foundation, and on nothing outside this folder.
