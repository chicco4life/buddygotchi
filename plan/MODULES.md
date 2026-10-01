# Boop: the three pieces and how they join

Updated 2026-10-01. Boop is three small libraries and the app that joins
them. Each library solves one problem, builds and tests on its own, has a
README (the overview) and a SPEC (the contract), and knows nothing of
Boop or of each other.
Everything that makes Boop Boop, the core's rules, the mood graph, faces,
voice and steering, is app code on top. This page is how they fit; each
piece's own pages say how it works.

```
  Claude Code, Codex
        │ hooks
        ▼
 ┌────────────────────┐
 │ A  agent-hooks     │  hooks → events, sessions, "needs you"
 └─────────┬──────────┘
           │ AgentEvent
           ▼
 ┌────────────────────┐   events    ┌────────────────────┐
 │ Boop's Mac app     │ ──────────► │ B  JHarness        │  log → prompt → one
 │ (BoopKit, Boop)    │ ◄────────── │                    │  request → outputs
 └─────────┬──────────┘   answers   └────────────────────┘
           │ state, do      ▲ hello, ev
           ▼                │
 ┌────────────────────┐
 │ C  LinkKit (host)  │  the only way to the board
 └─────────┬──────────┘
           │ JSON lines over Bluetooth or USB
 ┌─────────▼──────────┐
 │ C  LinkKit device  │  the turn: decides when a request plays
 │ + Boop's firmware  │  faces, voice, behaviour
 └────────────────────┘
```

| Piece | Folder | What it does | Products | Contract |
| --- | --- | --- | --- | --- |
| A | [agent-hooks/](../agent-hooks/README.md) | Coding agents' hooks become one kind of event; it keeps each session's state and "needs you" | `AgentHooks`, `agent-hook`, `agent-hooks` | [SPEC](../agent-hooks/SPEC.md) |
| B | [jharness/](../jharness/README.md) | A personality from Markdown plus multiple choice: a log of events, a line for each, one question request per pass, outputs that act | `JHarness`, `jharness-emit`, `beacon` | [SPEC](../jharness/SPEC.md) |
| C | [linkkit/](../linkkit/README.md) | A host and a small device: four messages, and the device decides what plays when | `LinkKit`, `linkkit-bridge`; the C++ library in [linkkit/device/](../linkkit/device/README.md) | [SPEC](../linkkit/SPEC.md) |
| Boop | `app/`, `firmware/` | The desk creature on top of all three | `Boop`, `BoopKit`; the firmware | this folder |

## The rules that keep them apart

- **Dependencies point one way.** Boop depends on A, B and C; none of
  them depends on Boop or on each other. The app is the only thing that
  talks to the board, and only through LinkKit; JHarness never touches
  the device: it hands its answers back to Boop's own outputs.
- **The build enforces it.** Each piece is its own package (Swift) or
  library (PlatformIO, with its own project for its tests) with nothing
  outside its folder, `make build`'s explicit import check
  fails a target that imports what it doesn't declare, and
  `linkkit/device/tools/check_includes.py` fails every firmware env's
  build if the device library includes a header that isn't its own, a
  Boop header among them.
- **Each speaks in its own terms.** A says `AgentEvent` (a kind and a
  phase), B says `Event` (source, kind, data) and lines, C says `state`,
  `do` and `ev`. Boop translates between them in a few small places,
  below, and nowhere else.

## Where they join

| From → to | Where | How |
| --- | --- | --- |
| A → Boop | `app/BoopKit/Adapters/Adapter.swift`, `Runtime.hook` | agent-hooks' `HookServer` hands each hook line to the runtime, which makes it an event with `Adapter.event(from:)`: agent-hooks' `Mapping` makes an `AgentEvent`, and Boop keeps it as a JHarness `Event` whose `data` holds its facts ([ADAPTERS.md](ADAPTERS.md)) |
| A → Boop's rules | `app/BoopKit/Core/Core.swift` | The core's `SessionTracker` (agent-hooks) folds the same events into sessions and "needs you"; the core adds the look, the priority and the one-shots ([BEHAVIORS.md](BEHAVIORS.md)) |
| Boop → B | `app/BoopKit/App/Pipeline.swift` | Each event goes into the harness in one `batch` with the core's rules; `TranscriptView` registers the transforms that give each kind its line and wake, and `Runtime` the outputs (`MoodAction`, a `Choice`, and `ReactAction`) ([harness/HARNESS.md](harness/HARNESS.md)) |
| Boop → C (the look) | `app/BoopKit/App/Runtime.swift` | Every change of the core's snapshot is `link.update(state: snapshot.fields)` on LinkKit's `DeviceLink`; it sends it on change, on connect, in answer to `hello` and every 10 s |
| Boop → C (one-shots) | `Runtime.playRule` | A rule's one-shot is `link.do(name, args:, play: .ifFree, by: .rule)`: at once, never waiting for the brain, and skipped by the device (`busy`) while a brain reaction holds the turn busy, its line or a finish |
| B → C (reactions) | `ReactAction` → `Runtime.queue` | JHarness hands Jev's answers to Boop's own output, `ReactAction`, which sends `link.do(name, args:, play: .next, ttl: BoopDevice.reactionTTL, by: .brain)`, a 5 s wait at most; the reaction's `Pending` stays open until the device's `ended`, which `Reactions.read` makes done or failed, or holds while the pokes go on after your tap cut it ([harness/DECISIONS.md](harness/DECISIONS.md) §5); `Reactions.sent` keeps whose thread a tap on a finish opens, and `Runtime.harness` wires the hold's end for the app and the evals alike |
| C → Boop | `Runtime.device`, `Runtime.deviceEvent` | The link finishes each `do` from its `ended` itself, and hands on every other `ev`: `tap` (with `on`, the finish it landed on, whose thread it opens) becomes a `poke` through the pipeline, and `talk_on` and `talk_off` turn the core's mic on and off ([PROTOCOL.md](PROTOCOL.md) §4). A line the link doesn't know is checked for the `status` of Boop's firmware from before the kit, which the link then counts as too old |

## One event's journey

A Claude turn finishes while Boop is idle and calm.

1. Claude Code runs its `Stop` hook, `agent-hook claude --keep-text`,
   which writes one line to every socket in `~/.agent-hooks/sockets/`
   (Boop's `boop.sock` among them) and exits: it never waits for an
   answer and can't block the agent (A).
2. agent-hooks' `HookServer`, in Boop's app, reads it, and
   `Adapter.event(from:)` makes a `turn_end` event. In one `batch`, the core folds it (the session is
   idle now) and the harness logs it (B).
3. The core's snapshot changed, so the device gets the look at once,
   before any brain (C):
   `{"t":"state","base":"idle","mood":"calm","busy":0,"vol":6,"variant":2}`
4. `TranscriptView`'s transform gives the event its line, looking back at
   the log for the turn's start and its tool calls (`claude finished
   turn 12 on "api": done, a long turn, 8 tool calls.`), and it wakes
   the brain. JHarness builds the prompt (Boop's sections, then HISTORY
   and NOW), asks every output's questions in one request to Jev, and
   hands each output its answers.
5. `ReactAction` picks the finish, a face and a take, and sends it (C):
   `{"t":"do","id":558386703,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","variant":2,"who":{"agent":"claude","thread":"api"},"say":{"take":"new.d02"},"mood":"proud"}}`
   JHarness logs a `did` that's open: HISTORY says it's in progress.
6. On the board, LinkKit's turn is free, so the call takes it at once
   (had another reaction's line been playing, it would wait up to its
   5 s). Boop's app plays the animation, the line in its voice window and
   the bubble; a finish never rests, so another reaction waits behind
   it. When all of it is over the app tells the kit, which answers (C):
   `{"t":"ev","kind":"ended","data":{"id":558386703,"how":"done"}}`
7. `Reactions` reads the `ended` and finishes the `Pending` done; JHarness logs its `ended`, and the next
   prompt's HISTORY says what Boop did, plainly.

A tap on the screen goes the other way: the board pokes at once on its
own, then sends `{"t":"ev","kind":"tap","did":"poked"}`; Boop records a
`poke` that the next prompt reads.

## Using a piece on its own

- **A alone:** `agent-hooks install`, then `agent-hooks tail --sessions`
  prints every hook as an event and each session's state as it changes;
  an app links `AgentHooks` and runs a `HookServer`
  ([agent-hooks/README.md](../agent-hooks/README.md), Examples).
- **B alone:** Beacon, a CI build light with a personality, is the worked
  example: `swift run --package-path jharness beacon` plays its day on a
  virtual clock and prints every prompt; `beacon listen` takes events
  from `jharness-emit` ([jharness/README.md](../jharness/README.md)).
- **C alone:** the device library's lamp (a level, a blink, a button) is
  a complete app in [linkkit/device/README.md](../linkkit/device/README.md),
  and `LampHost` in [linkkit/README.md](../linkkit/README.md) drives it
  from a Mac, over USB through `linkkit-bridge`.

## Building and testing

| Piece | Build | Tests |
| --- | --- | --- |
| A | `swift build --package-path agent-hooks` | `swift test` in `agent-hooks/` |
| B | `swift build --package-path jharness` | `swift test` in `jharness/` |
| C, host | `swift build --package-path linkkit` | `swift test` in `linkkit/` |
| C, device | through an app's firmware (`make -C internal fw` for Boop's); `python3 linkkit/device/tools/check_includes.py` checks its includes alone | `pio test -d linkkit/device -e native`: `test_turn`, `test_kit` and `test_helpers`, with a fake app (`linkkit/device/test/kit_fakes.h`) |
| Boop | `make build`: the Mac app on A, B and C's libraries, `boopdev` and the tests' runner, then `agent-hook`, `jharness-emit`, `beacon` and `linkkit-bridge`; the firmware, on C's device library, with `make -C internal fw` | `make -C internal test` runs Boop's tests, then each package's `swift test`; `make -C internal fw-test` runs the firmware's suites, then the device library's; `sim` and the board checks are in [VERIFICATION.md](VERIFICATION.md) |
