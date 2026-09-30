# LinkKit

A Mac app talking to a small device with a screen, a light or a speaker,
over Bluetooth or USB. LinkKit is the protocol between them, four JSON
messages, and a library for each side: Swift for the host, C++ for the
device. The host says how things are and asks the device to play things;
the device draws them its own way, decides what plays when, and says
what happened.

It's for a desk gadget driven by a Mac app: a status light, a little
screen with a face, a buzzer. It was pulled out of Boop, a desk creature
that watches your coding agents, and Boop's app and firmware both use it.

[SPEC.md](SPEC.md) says exactly what it does; this page is the overview.

## The four messages

Each is one JSON line of at most 512 bytes, the same over Bluetooth and
USB:

| Message | Way | What |
| --- | --- | --- |
| `state` | host → device | How things are now, the app's own map, sent whole on every change and every 10 s |
| `do` | host → device | Please play this: a name the device plays, how it takes the turn (`play`), and the app's `args`. Exactly one `ended` comes back |
| `hello` | device → host | Who it is (`app`, `id`, `fw`), the protocol's version (`kit`) and the names it plays (`does`). The host asks for it with a bare `{"t":"hello"}`, first on every link-up |
| `ev` | device → host | Something happened: a tap, a held button, and how each `do` ended (`ended`) |

```json
{"t":"state","base":"working","mood":"calm","busy":1,"vol":6}
{"t":"do","id":44,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success"}}
{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.4.0","does":["react","starting","listening"],"voice":"1aace295d219"}
{"t":"ev","kind":"tap","did":"poked"}
{"t":"ev","kind":"ended","data":{"id":44,"how":"cut","why":"tap"}}
```

The kit owns a few field names and the app owns the rest: all of
`state`, a `do`'s `args`, an `ev`'s kinds and `data`, and any other field
in `hello`. Tools also send `dbg.*` messages over USB (SPEC.md §7).

## The turn, in five lines

1. One call holds the turn at a time: busy (don't cut me) or resting
   (the part that matters is over, and anyone may take over).
2. `now` takes the turn at once, cutting a busy holder; `next` waits its
   turn, up to its `ttl` (5 s by default); `if_free` plays only if
   nothing busy holds it.
3. The device's app says when its holder rests or ends, what it refuses,
   and what cuts it (a tap, a button).
4. Every `do` gets exactly one `ended`: `done`, `cut` or `skipped`, with
   a short word why (`now`, `late`, `busy`, `tap`).
5. The host never times what the device plays: it sends at once and
   waits for the `ended`, giving up only at the `ttl` plus 60 s.

## The host, in Swift

It builds from source with Swift 6 (Xcode or the Command Line Tools) on
macOS 13 or later, on Foundation and CoreBluetooth, with
[../jharness](../jharness/README.md) beside it (below, With JHarness):

```swift
// Package.swift
.package(path: "../linkkit"),
// and in a target's dependencies:
.product(name: "LinkKit", package: "linkkit"),
```

A `Link` keeps the device's picture true with `state`, sends each `do`
and hands its end to a completion called exactly once, and passes on
every other `ev`. It runs on one queue of yours: the transport calls back
on its own thread, so hop to the queue, and tick the link about once a
second for the keepalive and the give-ups. This drives the lamp from the
device library's example (below) through a USB bridge's socket:

```swift
import Foundation
import LinkKit

/// Drives a lamp over its USB bridge: its level, a blink, its button.
final class LampHost: @unchecked Sendable {
    let queue = DispatchQueue(label: "lamp")  // the link's one queue
    let link = Link(app: "lamp", transport: SocketTransport(path: "/tmp/lamp.sock"), log: { print($0) })
    var keep: [Any] = []

    func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func start() {
        link.onEvent = { ev in
            if ev.kind == "press" { print("pressed; the lamp \(ev.did ?? "did nothing")") }
        }
        link.transport?.start(
            onLine: { [self] line in queue.async { [self] in link.receive(line, now: now()) } },
            onConnection: { [self] up in queue.async { [self] in link.connection(up, now: now()) } })
        queue.async { [self] in link.update(state: ["level": 40], now: now()) }
        let tick = DispatchSource.makeTimerSource(queue: queue)
        tick.schedule(deadline: .now() + 1, repeating: 1)
        tick.setEventHandler { [self] in link.tick(now: now()) }
        tick.resume()
        keep = [tick]
    }

    /// Blinks twice once the lamp's turn is free, and says how it went.
    func blink() {
        queue.async { [self] in
            link.do("blink", args: ["times": 2], now: now()) { outcome in print("blink:", outcome) }
        }
    }
}
```

- **Ids** start somewhere random each launch and count up, so a call an
  earlier launch left on the device can't be mistaken for a new one.
- **A `do` fails at once**, with nothing sent, when there's no link, no
  `hello` yet, the name isn't in `hello.does` or the line would be too
  long; later when the link drops or no `ended` comes in time. The
  completion's `Outcome` says which, in plain words. A `state` too long
  for a line isn't sent either: the last one that fit stands.
- **`hello`** is `link.hello`, the app's own fields among it; `onHello`
  hears a new one. The link asks for it (`{"t":"hello"}`, which the
  device library answers) when the link comes up, and every 10 s until
  it comes, since a device that still counts the host as there (an app
  relaunched within 30 s, or one taking over a Bluetooth link macOS
  kept) doesn't say it unasked. A device whose `kit` or `app` doesn't
  fit, or one your app finds too old by a line of its own
  (`link.incompatible`, for firmware from before it had a `hello`),
  still gets `state` but no `do`, its `ev`s are dropped, and
  `link.trouble` says what to do about it, for your settings screen.
- **Bluetooth:** `BLETransport(prefix: "Lamp")` finds `Lamp-XXXX` on the
  Nordic UART service, cuts lines to the write size and keeps a newer
  `state` from queueing behind an old one. macOS kills a process that
  touches Bluetooth without the right to, so tests, and anything started
  from an agent's shell, use `SocketTransport`.

`Wire` builds and reads the lines themselves, and `JSON` and `JSONObject`
(keys in order) are the app's parts of them.

## The device, in C++

The device's half is in [device/](device/README.md): C++17 on
ArduinoJson, with no Arduino headers in its portable part, so it runs on
a Mac for tests and simulators. Its `Kit` reads the host's lines, keeps
the links, says `hello`, runs the turn, routes `ev` and answers the
`dbg.*` messages; your `App` says what it plays, draws it, and reports
when its holder rests, ends or is cut. Its README has the lamp, whole.
Boop's firmware is another app on it.

## With JHarness

`JHarnessLink`, a second product, glues a device into an app whose brain
runs on [JHarness](../jharness/README.md). LinkKit itself never imports
JHarness, but the package depends on `../jharness` for it, and SwiftPM
resolves a package's dependencies whichever product an app takes, so
JHarness's folder must be beside this one even for `LinkKit` alone.

```swift
.product(name: "JHarnessLink", package: "linkkit"),
```

- **`link.do(…, pending:)`** finishes a JHarness `Pending` from the
  `do`'s end, so an output that plays something returns
  `.started(message, pending)` and HISTORY shows it in progress until
  the device says. `Link.end` is the default reading (`done`, `cut short:
  tap`, `skipped: late`, `the device disconnected`); pass your own `map`,
  and return nil to finish it yourself later.
- **`DeviceEvents`** logs every `ev` as an event from `device`, what the
  device did about it as a `did` in your words, and `device_up` and
  `device_down`.
- **`Play`** is a ready-made output: the brain picks one of the names you
  describe that the device's `hello` says it plays, or none, and it plays
  with `play: next`.

On the harness's queue, which must be the link's:

```swift
import JHarness
import JHarnessLink
import LinkKit

func wire(_ harness: Harness, to link: Link, clock: @escaping () -> Int64) {
    _ = DeviceEvents(link: link, harness: harness) { ev in ev.did == "stopped" ? "The lamp stopped blinking." : nil }
    harness.input("press", wake: 1) { _, _ in Line("You pressed the lamp's button.") }
    harness.output(Play(link: link, question: "Should the lamp blink at NOW?", judgeBy: "NOW's line",
                        options: [Option("blink", "Blink: something went wrong.")], clock: clock))
}
```

## Boop

Boop's vocabulary on it, its `state` fields, `do` names, `hello`'s
`voice` and its taps, is in [plan/PROTOCOL.md](../plan/PROTOCOL.md); the
app's side is `app/BoopKit/DeviceLink/BoopDevice.swift`, and the
firmware's `firmware/src/app/device.cpp`.

## Development

```sh
swift test --scratch-path .build/tests
```

The tests use Swift Testing: `LinkKitTests` (framing and chunking, the
Bluetooth outbox and reconnect timing, the socket transport, the wire,
the keepalive, `hello` and trouble, ids, exactly one end, the give-up
and a link that drops), each naming the SPEC.md section it checks, and
`JHarnessLinkTests`. The device half's tests run with the firmware's
(`make -C internal fw-test`). The package depends on nothing but
Foundation, CoreBluetooth and `../jharness` (which only `JHarnessLink`
imports, though SwiftPM needs it for either product), and on nothing
else outside this folder.
