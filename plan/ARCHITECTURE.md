# Boop: architecture

Draft 10 · 2026-09-25. This is the overview: the parts, how they connect, and
the memory files they share. These documents go deeper:

- [Agent adapters](ADAPTERS.md): hooks, event mapping, and "needs you".
- [Harness and brain](HARNESS.md): how a trigger becomes a model call and
  back.
- [steering.md](steering.md): the first draft of Boop's read-only standing
  instructions.
- [Bluetooth protocol](PROTOCOL.md): the messages between the Mac app and
  the device.
- [Device behaviors and XP](BEHAVIORS.md): what Boop does for each trigger,
  plus XP and hunger.
- [Voice](VOICE.md): how the gibberish is built and played.
- [Device](DEVICE.md): the board, pins, firmware stack and bring-up.
- [Verification](VERIFICATION.md): how everything is checked, including
  the screen.
- [Plan](PLAN.md): build order, checks per milestone, and the morning
  checklist.

See [Vision](VISION.md) for why and [UX](UX.md) for what the person sees.

## 1. The shape of it

Boop has two parts: a Mac app that does all the thinking, and a cheap device
on your desk that draws the creature. Information flows one way, from your
agents to Boop to you. Boop watches and tells you things. It never acts on
your agents. When an agent needs approval, Boop gets your attention, and you
approve on the Mac as you normally would.

```
   Claude Code / Codex
          │ hooks: "this happened" (never waits for an answer)
          ▼
 ┌──────────────────────────── Boop Mac app ─────────────────────────────┐
 │                                                                        │
 │  Adapters ──► Core ───────────── state snapshots ──────────┐           │
 │               │  │                                         │           │
 │     rule      │  │ triggers                                │           │
 │   reactions   │  ▼                                         │           │
 │               │ Harness ──► Brain (any small LLM)          │           │
 │               │  │  ▲                                      │           │
 │               │  │  └── reads steering / long-term /       │           │
 │               │  │      short-term memory                  │           │
 │               ▼  ▼ tool calls                              ▼           │
 │              Actions ──► Voice (minion speech) ──►  Device link ───────┼──► device
 │              say, face,  Memory store (the .md files)                  │
 │              quiet, note…                                              │
 └────────────────────────────────────────────────────────────────────────┘
```

**Following one event:**

1. Codex finishes a task. Its hook sends a one-line message to the Mac app
   and returns immediately.
2. The Codex **adapter** turns it into the common event: "Codex, session
   a1b2, project landing, turn finished after 18 minutes".
3. The **core** updates its session table, adds XP, and by rule calls the
   `face` action with a cheer. Boop cheers in well under a second.
4. The core also hands the event to the **harness** as a trigger. The
   harness reads the memory files, asks the **brain**, and gets back a tool
   call: `say(feeling: proud, word: finally)`.
5. The harness passes that call, unchanged, to the **`say` action**. The
   action asks **Voice** to turn "proud + finally" into Minion speech
   (*"ma-po li… finally!"*) and sends it to the device through the
   **device link**.

The brain never sits between an event and the screen. Rules give the
immediate reaction, and the brain adds character a second or two later. If
the brain is slow, offline or missing, Boop still reacts to everything, just
with less personality.

## 2. Four loops at four speeds

| Loop | Runs on | Speed | Does | Never does |
| --- | --- | --- | --- | --- |
| Reflex | Device | < 20 ms | Tap feedback, blinking, idle life, blending faces, the nudge ladder | Wait for the Mac |
| Reactive | Core → actions | < 200 ms p95 | Agent event → rule → action → device; XP | Wait for the brain |
| Deliberative | Harness + brain → actions | 1–5 s, in the background | React with character, take notes, answer push-to-talk | Block the reactive loop |
| Reflective | Harness + brain, nightly | Minutes | Turn today into durable memory, grow the personality | Break the memory rules |

## 3. Components and boundaries

Each part has one job and knows as little as possible about the others. The
rule is that **decisions and effects are separate**. The core and the brain
decide *what* should happen. Actions make it happen. Nothing that decides
ever builds Minion speech, touches a file or talks to Bluetooth directly.

| Part | Does | Doesn't know about |
| --- | --- | --- |
| Adapters | Turn agent hooks into common events | Boop's state, the brain, the device |
| Core | Session table, what the device shows, XP, quiet mode; calls actions for rule reactions; sends triggers to the harness | Minion speech, models, hook formats |
| Harness | Trigger → context → one brain call → schema check → hand each tool call to its action | Minion speech, the device, memory rules, which model it's talking to |
| Brain | Picks which tools to call, with what arguments | Everything else |
| Actions | Carry out one tool call each: `say`, `face`, `quiet`, `note`, and the nightly memory tools. Each checks its own rules | Whether a rule or the brain called it |
| Voice | Turns a feeling and an optional word into Minion speech | Who asked, or why |
| Memory store | Reads and writes the three Markdown files, enforcing their limits | Models, the device |
| Device link | Sends snapshots and moments to the device and receives taps and talk, over Bluetooth or USB | What any of it means |

### 3.1 Adapters

Each adapter turns one agent's hook calls into the common event (§5).
Hooks only report. The hook client writes one line to the app's socket and
exits without returning a decision, so the agent always carries on with its
normal flow, including its own approval prompt. If the Boop app isn't
running, the hook exits at once. [ADAPTERS.md](ADAPTERS.md) has the
details.

### 3.2 Core

The core is plain rules with no queue. It keeps a table of sessions (agent,
project, and whether each is working, idle or needs you) and:

- works out what the device shows now, and sends a new snapshot when that
  changes. The highest true item wins: something needs you, then a task just
  finished, then you're interacting with Boop, then something is working,
  then idle;
- calls actions for the immediate, rule-based reactions (a cheer, an oops, a
  nod);
- turns events, taps and talk into triggers for the harness;
- keeps XP, quiet mode and Boop's mood, all by rule
  ([BEHAVIORS.md](BEHAVIORS.md)).

### 3.3 Harness and brain

The harness is the small generic loop from [HARNESS.md](HARNESS.md). It
knows how to build a prompt, call a model and route tool calls. It doesn't
know what the tools do. The brain is whatever model is plugged in: Apple's
on-device model by default, or a cloud model with the person's own API key.
It's assumed to be small, so the tools are few, flat and mostly multiple
choice.

### 3.4 Actions

Actions are Boop's tools. The same actions serve the core's rules and the
brain, so a cheer looks the same whichever of them asked for it.

| Action | Arguments | What it does |
| --- | --- | --- |
| `say` | `feeling`, `word?` | Asks Voice for a Minion line, then sends it to the device as a moment |
| `face` | `name` | Sends an animation to the device as a moment |
| `quiet` | `minutes` | Tells the core to stop mumbles for a while |
| `note` | `text` | Adds a line to today's notes in short-term memory |
| `remember`, `forget`, `temperament`, `moment` | short text | Nightly only: change long-term memory within its limits |

Each action checks its own rules and quietly drops anything that breaks
them. For example, `say` drops a word that isn't in its vocabulary, and
`note` drops text that's too long. The action's tool definition, the part
the brain sees, is owned by the action too. That's where the list of
allowed words lives, as a multiple-choice field.

### 3.5 Voice

Voice turns `feeling + word` into a Minion line: syllables from this Boop's
dialect, the real word, a tune and a tempo. It checks the line isn't
accidentally English. It's the only code that knows what Minion speech
sounds like. See [VOICE.md](VOICE.md).

### 3.6 Memory store

The memory store is the only code that reads or writes the Markdown files
(§4). It enforces their limits and takes the nightly snapshots.

### 3.7 Device link

The device link sends snapshots and moments, and receives taps and
push-to-talk presses ([PROTOCOL.md](PROTOCOL.md)). It has two transports
carrying identical messages:

- **Bluetooth**, for normal use.
- **USB serial**, for development and automated tests. An agent can't launch
  the app with Bluetooth on, so the whole hook-to-screen path is tested over
  USB instead ([VERIFICATION.md](VERIFICATION.md) L4).

Nothing above the device link knows which one is in use.

### 3.8 Push-to-talk

The device has no mic, so holding its button records from the Mac's mic.
The app turns speech into text locally, and the core gives it to the
harness as a `talk` trigger. Audio is discarded immediately, and the
transcript once the brain has answered.

## 4. Memory files

All of Boop's memory is three Markdown files in the app's data directory.
The harness puts all three into every brain call. `steering.md` is
read-only. The other two are written only by the memory store, through
actions that enforce each section's limits. Before each nightly update, both are snapshotted to
`history/<date>/`, so every change can be traced.

| File | What it is | Changes |
| --- | --- | --- |
| `steering.md` | How Boop behaves: character, voice, how to respond to each trigger | Never at runtime. Ships with the app and changes only in an announced release |
| `long-term.md` | Who this Boop has become, and durable facts and preferences about you | Nightly, within caps; XP by the core |
| `short-term.md` | Today: Boop's mood, notes about what you're doing and said, what happened | Throughout the day; starts fresh each night |

### 4.1 `steering.md`

This is Boop's AGENTS.md: the standing instructions every Boop shares. It's
read-only. Neither the brain, the app nor the person can change it at
runtime. It changes only when we ship a new version, as an announced update,
because a different `steering.md` makes a different creature. The current
draft is [steering.md](steering.md).

It covers character, voice rules, how to respond to each trigger, what Boop
must never do, the always-allowed interjection words, and the fallback table
the rules-only brain uses.

### 4.2 `long-term.md`

```markdown
## Boop
name: Pip · hatched: 2026-10-02 · nature: impish

### Temperament
Nosy and a bit smug. Trusts Codex more than it used to.
Gets huffy about flaky tests.

### Moments
- 2026-10-09: first all-nighter together; the migration finally passed.

### Growth
xp: 1240 · level: 12 · last fed: 2026-10-14

## About you
- Ships on Fridays.
- Mostly works on landing and jetpack.

## Preferences
- Likes it quiet before 10am.
```

| Section | Written by | Rule |
| --- | --- | --- |
| Boop (name line) | App, at hatching | Never changes |
| Temperament | Nightly reflection | At most one sentence changed per night |
| Moments | Nightly reflection | At most 20; at most one new per night |
| Growth | Core | See [BEHAVIORS.md](BEHAVIORS.md) §4 |
| About you | Nightly reflection | At most 30 lines, each ≤ 100 characters; no code, paths, secrets or other people's names |
| Preferences | Nightly reflection | At most 15 lines; same limits |

The **Boop** section is what the "can't be reset" promise protects. The file
lives on the Mac and in the opt-in encrypted backup, never on the device.
Retiring Boop archives it and makes a memorial card from it. You can view
and delete lines in About you and Preferences in the app. The Boop section
isn't shown.

### 4.3 `short-term.md`

```markdown
## Today
2026-10-14 · first seen 08:52 · Boop's mood: a bit frazzled

## Notes
- landing: flaky tests, third attempt
- jetpack: long refactor finally done
- said "shut up for an hour" at 13:10

## Happened
- 14:02 codex · landing · failed
- 14:05 claude · jetpack · finished (18 min)
```

| Section | Written by | Rule |
| --- | --- | --- |
| Today | Core | Date, first activity, and Boop's current mood (set by rule) |
| Notes | `note` action (from the brain) | At most 10 lines of at most 80 characters; the oldest line drops first |
| Happened | Core | One line per notable event, summaries only; the last 40 lines |

Nightly reflection reads everything and updates `long-term.md` through the
nightly actions, and then `short-term.md` starts fresh. Mood is internal
and only visible in debug mode.

## 5. Common event shape

```json
{"agent":"codex","session":"a1b2","project":"landing","event":"turn_end",
 "detail":{"duration_s":1080},"ts":1790000000123}
```

| Field | Meaning |
| --- | --- |
| `agent` | `claude_code`, `codex` |
| `session` | Stable session/thread ID |
| `project` | Short project name, from the working directory |
| `event` | `session_start`, `turn_start`, `needs_you`, `activity`, `turn_end`, `turn_failed`, `session_end` |
| `detail` | Small and event-specific: duration, tool name. Never prompt text |
| `ts` | Milliseconds |

Adding an agent later means one new adapter that produces this shape.

## 6. When an agent needs you

```
 Agent                    Mac app (core)                 Device
   │ needs approval            │                            │
   ├── hook: needs_you ───────►│ session → "needs you"      │
   │ (agent shows its own      ├── snapshot: attention ────►│ amber, looks at you,
   │  prompt as normal)        │                            │ nudge ladder
   │                           │                            │
   │ you approve on the Mac    │                            │
   ├── hook: activity ────────►│ session → "working"        │
   │                           ├── snapshot: calm ─────────►│ back to work
```

- A session stops needing you when any later event arrives from it (the
  tool ran, the turn ended, or you sent a new prompt), when it ends, or
  after 10 minutes as a safety net (*proposed*).
- Tapping Boop while it's asking for attention quiets the nudges for that
  session. It doesn't answer anything.
- Boop can't approve or deny. That keeps the product simple and safe: a bug
  in Boop can never let an agent do something you didn't agree to.

## 7. Device

The device is a thin client. It draws what the latest snapshot says, plays
moments, runs its own short timers (blinks, idle life, the nudge ladder) and
reports taps and push-to-talk. It holds no personality or memory, just its
Bluetooth bond, a device ID, and its animation and syllable library.
[BEHAVIORS.md](BEHAVIORS.md) lists what it does for each trigger.

The board, wiring and firmware are in [DEVICE.md](DEVICE.md).

## 8. When things go wrong

| Failure | Behaviour |
| --- | --- |
| App not running | Hooks exit at once; agents are unaffected. The device idles with a sleepy "no app" face |
| Device disconnected | The app keeps going; the next snapshot catches the device up on reconnect |
| Brain offline, slow or invalid | Rules still drive every reaction; mumbles use the fallbacks in `steering.md`; memory doesn't grow that day |
| Memory file invalid | The harness uses the last snapshot from `history/` |
| Mac asleep | The device drifts to sleep after 30 s without a message |

## 9. Budgets

| Path | Target |
| --- | --- |
| Agent event → pixel | < 200 ms p95 |
| Tap → visible feedback | < 20 ms, on-device |
| Hook overhead | Single-digit ms; never waits |
| Brain call, live triggers | 5 s deadline; late results are dropped |
| Nightly reflection | Minutes, on power |

## 10. Stack

- **Mac app:** a Swift menu-bar app, using CoreBluetooth, Apple's
  Foundation Models and the Speech framework. It's built with SwiftPM from
  `app/`.
- **Hook client:** `boop-hook`, a small Swift executable in the same
  package.
- **Firmware v1:** PlatformIO + Arduino core + LovyanGFX + NimBLE-Arduino,
  in `firmware/` ([DEVICE.md](DEVICE.md) §4). A later milestone ports it to
  ESP-IDF + LVGL, once v1 is verified ([PLAN.md](PLAN.md)).
- **Dev tools:** `tools/boopctl` for the device and `boopdev` for the app
  ([VERIFICATION.md](VERIFICATION.md) §2).

The stable contracts are the event shape (§5), the memory files (§4), the
brain interface ([HARNESS.md](HARNESS.md)) and the protocol
([PROTOCOL.md](PROTOCOL.md)).

## 11. Decisions

**Decided (2026-09-25):**

- **Claude Cowork is out of v1.** Its sandbox doesn't run Claude Code hooks
  yet ([ADAPTERS.md](ADAPTERS.md) §7).
- **Apple's on-device model is the default brain.** Your own API key is an
  optional upgrade. Everything is designed to work well on the small model.
- **Hand edits to `long-term.md` are allowed.** There's no checksum. The
  promise is that there's no reset button, not that the file is locked. A
  file that won't parse is restored from last night's snapshot.
- **Prompt text is never sent to the brain.** Mood is set by rule.
- **Focus mode is visual only** ([BEHAVIORS.md](BEHAVIORS.md) §3.2).
- **Threads show agent and project only** ([UX.md](UX.md) §3).
- **Voice** is synthesised, English only, and mumble back matches your
  energy ([VOICE.md](VOICE.md) §10).
- **Codex waits 2 s before "needs you"**, which is long enough for its
  automatic reviewer ([ADAPTERS.md](ADAPTERS.md) §4).
- **The prompt fits** the ~3,000-token budget, and the small model follows
  `steering.md` well enough. We assume both and design as if they hold.
- **Numbers marked *proposed*** are v1 defaults. We'll tune them by trying
  Boop out.
