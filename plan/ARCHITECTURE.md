# Boop: architecture

Updated 2026-09-25. The parts of Boop, how they connect, the memory files
they share, and the decisions behind them. The other specs go deeper on
each part; [README.md](README.md) lists them all.

## 1. The shape of it

Boop has two parts: a Mac app that does all the thinking, and a cheap device
on your desk that draws the creature. Information flows one way, from your
agents to Boop to you. Boop watches and tells you things; it never acts on
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
 │               │ Harness ──► Brain (a small LLM)            │           │
 │               │  │  ▲                                      │           │
 │               │  │  └── memory text, from the memory store │           │
 │               ▼  ▼ tool calls                              ▼           │
 │              Actions ──► Voice (Minion speech) ───►  Device link ──────┼──► device
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
   harness builds a prompt from the memory files, asks the **brain**, and
   gets back a tool call: `say(feeling: proud, word: finally)`.
5. The harness passes that call, unchanged, to the **`say` action**, which
   asks **Voice** to turn "proud + finally" into Minion speech
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
| Reflective | Harness + brain, once a day | Minutes | Turn yesterday into lasting memory, grow the personality | Break the memory rules |

## 3. Components and boundaries

Each part has one job and knows as little as possible about the others. The
rule is that **decisions and effects are separate**. The core and the brain
decide *what* should happen, and actions make it happen. Nothing that
decides ever builds Minion speech, touches a file or talks to the device
directly.

| Part | Does | Doesn't know about |
| --- | --- | --- |
| Adapters | Turn agent hooks into common events | Boop's state, the brain, the device |
| Core | The session table, what the device shows, XP, hunger, mood, quiet and focus; calls actions for rule reactions; sends triggers to the harness | Minion speech, models, hook formats |
| Harness | Trigger → prompt → one brain call → shape check → hand each tool call to its action | Minion speech, the device, memory rules, which model it's talking to |
| Brain | Picks which tools to call, with what arguments | Everything else |
| Actions | Carry out one tool call each, checking their own rules | Whether a rule or the brain called them |
| Voice | Turns a feeling and an optional word into Minion speech | Who asked, or why |
| Memory store | The only code that touches the three Markdown files: supplies their text and applies changes within limits | Models, the device |
| Device link | Sends snapshots and moments; receives taps and talk; over Bluetooth or USB | What any of it means |

### 3.1 Adapters

Each adapter turns one agent's hook calls into the common event (§5). Hooks
only report: the hook client writes one line to the app's socket and exits
without returning a decision, so the agent always carries on with its
normal flow, including its own approval prompt. If the Boop app isn't
running, the hook exits at once. See [ADAPTERS.md](ADAPTERS.md).

### 3.2 Core

The core is plain rules with no queue. It keeps a table of sessions (agent,
project, and whether each is working, idle or needs you) and:

- works out what the device shows and sends a new snapshot when that
  changes. The highest true item wins: something needs you, then a task just
  finished, then you're interacting with Boop, then something is working,
  then idle;
- calls actions for the immediate reactions (a cheer, an oops, a nod) and
  for Boop's occasional working chatter;
- turns events, taps and talk into triggers for the harness. It merges
  bursts within 3 s. While something needs you, or during quiet and focus
  mode, it sends only `talk` and the daily reflection;
- keeps XP, hunger, mood, quiet, focus and "away", all by rule
  ([BEHAVIORS.md](BEHAVIORS.md)).

### 3.3 Harness and brain

The harness is a small, generic loop ([HARNESS.md](HARNESS.md)). It builds a
prompt, calls a model and routes tool calls, without knowing what the tools
do. The brain is whatever model is plugged in: Apple's on-device model by
default, or a cloud model with the person's own API key. It's assumed to be
small, so the tools are few, flat and mostly multiple choice.

### 3.4 Actions

Actions are Boop's tools. The same actions serve the core's rules and the
brain, so a cheer looks the same whichever of them asked for it.

| Action | Arguments | What it does |
| --- | --- | --- |
| `say` | `feeling`, `word?` | Asks Voice for a Minion line, then sends it to the device as a moment |
| `face` | `name` | Sends an animation to the device as a moment |
| `quiet` | `minutes` | Tells the core to stop mumbles for a while |
| `note` | `text` | Adds a line to today's notes |
| `remember`, `forget`, `temperament`, `moment` | short text | Reflection only: change long-term memory within its limits |

Each action checks its own rules and quietly drops (and logs) anything that
breaks them. For example, `say` drops a word that isn't in its vocabulary,
and `note` drops text that's too long. Each action also owns its tool
definition, the part the brain sees. That's where the allowed words live, as
a multiple-choice field.

### 3.5 Voice

Voice turns `feeling + word` into a Minion line: syllables from this Boop's
dialect, the real word, a tune and a tempo. It checks the line isn't
accidentally English. It's the only code that knows what Minion speech
sounds like. See [VOICE.md](VOICE.md).

### 3.6 Memory store

The memory store is the only code that reads or writes the Markdown files
(§4). It hands their text to the harness for each prompt, applies changes
from actions within each section's limits, writes atomically, and snapshots
the files before each reflection.

### 3.7 Device link

The device link sends snapshots and moments and receives taps and
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
Every brain call includes all three.

| File | What it is | Changes |
| --- | --- | --- |
| `steering.md` | How Boop behaves: character, how to act, examples, what never to do | Never at runtime. Ships with the app and changes only in an announced release |
| `long-term.md` | Who this Boop has become, and lasting facts and preferences about you | Once a day, at reflection, within limits; XP by the core |
| `short-term.md` | Today: Boop's mood, notes about what you're doing and said, what happened | Throughout the day; starts fresh after reflection |

**Reflection** runs once a day, at the first activity of a new day. The
memory store snapshots both writable files to `history/<date>/`. The brain
reads yesterday's `short-term.md` and updates `long-term.md` through the
reflection actions. Then `short-term.md` starts fresh.

The files are plain text. Hand edits are allowed, and a file that won't
parse is restored from its last snapshot.

### 4.1 `steering.md`

This is Boop's AGENTS.md: the standing instructions every Boop shares. It's
read-only. Neither the brain, the app nor the person can change it at
runtime, because a different `steering.md` makes a different creature. It
covers character, how to act through tools, examples for each trigger,
reflection, what never to do, and the fallback table the rules-only brain
uses. The current version is [steering.md](steering.md).

### 4.2 `long-term.md`

```markdown
## Boop
name: Pip · hatched: 2026-10-02 · nature: cheeky · seed: 7f3a

### Temperament
Nosy and a bit smug. Trusts Codex more than it used to.
Gets huffy about flaky tests.

### Moments
- 2026-10-09: first all-nighter together; the migration finally passed.

### Growth
xp: 1240 · level: 25 · last fed: 2026-10-14

## About you
- Ships on Fridays.
- Mostly works on landing and jetpack.

## Preferences
- Likes it quiet before 10am.
```

| Section | Written by | Rule |
| --- | --- | --- |
| Boop (name line) | App, at setup | Never changes. `nature` is the person's one answer (sweet or cheeky); `seed` is random and picks Boop's voice dialect |
| Temperament | Reflection | At most one sentence changed a day |
| Moments | Reflection | At most 20; at most one new a day |
| Growth | Core | [BEHAVIORS.md](BEHAVIORS.md) §4 |
| About you | Reflection | At most 30 lines of at most 100 characters; no code, paths, secrets or other people's names |
| Preferences | Reflection | At most 15 lines; same limits |

The Boop section is who this Boop is. It lives only on the Mac, so
reflashing or replacing the device doesn't change it, and the app has no
reset button. In the app you can view and delete lines in About you and
Preferences; the Boop section isn't shown.

### 4.3 `short-term.md`

```markdown
## Today
2026-10-14 · first seen 08:52 · mood: a bit frazzled

## Notes
- landing: flaky tests, third attempt
- jetpack: long refactor finally done
- said "shut up for an hour" at 13:10

## Happened
- 14:02 codex · landing · tests · failed
- 14:05 claude · jetpack · finished (18 min)
```

| Section | Written by | Rule |
| --- | --- | --- |
| Today | Core | Date, first activity, and Boop's current mood |
| Notes | `note` action (from the brain) | At most 10 lines of at most 80 characters; the oldest drops first |
| Happened | Core | One line per notable event, summaries only; the last 40 lines |

Mood is internal. It shapes behaviour and is only visible in debug mode.

## 5. Common event shape

```json
{"agent":"codex","session":"a1b2","project":"landing","event":"turn_end",
 "detail":{"duration_s":1080,"topic":"tests"},"ts":1790000000123}
```

| Field | Meaning |
| --- | --- |
| `agent` | `claude_code` or `codex` |
| `session` | Stable session or thread ID |
| `project` | Short project name, from the working directory |
| `event` | `session_start`, `turn_start`, `needs_you`, `activity`, `turn_end`, `turn_failed`, `session_end` |
| `detail` | Small and event-specific: duration, tool name, a topic tag ([ADAPTERS.md](ADAPTERS.md) §3). Never prompt text, commands or file contents |
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
   │                           ├── snapshot: calm ─────────►│ a nod, back to work
```

- Claude shows "needs you" immediately. Codex waits 2 s first, because its
  automatic reviewer may approve the request without asking you
  ([ADAPTERS.md](ADAPTERS.md) §4).
- A session stops needing you when any later event arrives from it, when
  it ends, or after 10 minutes as a safety net (*proposed*).
- Tapping Boop quiets the nudges for that session. It doesn't answer
  anything.
- Boop can't approve or deny. That keeps it simple and safe: a bug in Boop
  can never let an agent do something you didn't agree to.

## 7. Device

The device is a thin client. It draws what the latest snapshot says, plays
moments, runs its own short timers (blinks, idle life, the nudge ladder) and
reports taps and push-to-talk. It holds no personality or memory, just a
device ID, its touch calibration, and its animation and syllable library.
What it does for each trigger is in [BEHAVIORS.md](BEHAVIORS.md); the
hardware and firmware are in [DEVICE.md](DEVICE.md).

## 8. When things go wrong

| Failure | Behaviour |
| --- | --- |
| App not running | Hooks exit at once; agents are unaffected. The device idles with a sleepy "no app" face |
| Device disconnected | The app keeps going; the next snapshot catches the device up on reconnect |
| Brain offline, slow or invalid | Rules still drive every reaction; the rules-only fallbacks in `steering.md` fill in; memory doesn't grow that day |
| Memory file won't parse | The memory store restores its last snapshot |
| Mac asleep | The device drifts to sleep after 30 s without a message |

## 9. Budgets

| Path | Target |
| --- | --- |
| Agent event → pixel | < 200 ms p95 |
| Tap → visible feedback | < 20 ms, on the device |
| Hook overhead | Single-digit ms; never waits |
| Brain call, live triggers | 3–5 s deadline; late results are dropped |
| Reflection | Minutes, in the background |

## 10. Stack

- **Mac app:** Swift, built with SwiftPM from `app/`, using CoreBluetooth,
  Apple's Foundation Models and the Speech framework.
- **Hook client:** `boop-hook`, a small Swift executable in the same
  package.
- **Firmware:** PlatformIO + Arduino core + LovyanGFX + NimBLE-Arduino in
  `firmware/` ([DEVICE.md](DEVICE.md) §4), to be ported to ESP-IDF + LVGL
  once v1 is verified ([PLAN.md](PLAN.md) P1).
- **Dev tools:** `tools/boopctl` for the device and `boopdev` for the app
  ([VERIFICATION.md](VERIFICATION.md) §2).

The stable contracts are the event shape (§5), the memory files (§4), the
brain interface ([HARNESS.md](HARNESS.md)) and the protocol
([PROTOCOL.md](PROTOCOL.md)).

## 11. Decision log

When a spec changes direction, add a row here saying why.

| Date | Decision | Why | Where |
| --- | --- | --- | --- |
| 2026-09-25 | The personality is the product; usefulness comes second | It's why people keep Boop | [VISION.md](VISION.md) |
| 2026-09-25 | Boop speaks Minion gibberish with at most one real word | A creature, not a chatbot; fast and cheap | [VOICE.md](VOICE.md) |
| 2026-09-25 | Boop only notifies; approving stays in the agent on the Mac | Simpler, and a Boop bug can never approve anything | §6 |
| 2026-09-25 | The brain is a small, swappable LLM behind a generic, pi-style harness; Apple's on-device model is the default, with the person's own API key optional | Private and free by default; model choice stays invisible to the rest | [HARNESS.md](HARNESS.md) |
| 2026-09-25 | Memory is three Markdown files; `steering.md` is read-only; the personality lives in `long-term.md` on the Mac | Simple, inspectable, and independent of the device and the model | §4 |
| 2026-09-25 | No reset button, but no lock either: hand edits are allowed | Permanence without extra machinery | §4 |
| 2026-09-25 | No prompt text goes to the brain; mood is set by rule | Privacy, and one less thing to get wrong | [BEHAVIORS.md](BEHAVIORS.md) §5 |
| 2026-09-25 | Claude Cowork is out of v1 | Its sandbox doesn't run Claude Code hooks yet | [ADAPTERS.md](ADAPTERS.md) §7 |
| 2026-09-25 | Codex waits 2 s before "needs you" | Its automatic reviewer may approve without asking you | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-25 | Our own protocol, with the same messages over Bluetooth and USB; no pairing or encryption for the first test | Only our app talks to the device; USB makes it testable by agents | [PROTOCOL.md](PROTOCOL.md) |
| 2026-09-25 | Firmware starts on Arduino + LovyanGFX and moves to ESP-IDF + LVGL once v1 works | Fastest to a working face; production path later | [DEVICE.md](DEVICE.md) §4 |
| 2026-09-25 | v1 runs on the bare board: BOOT is the main button; no speaker, motor or battery | That's the hardware on the bench | [DEVICE.md](DEVICE.md) §3 |
| 2026-09-25 | The voice is synthesised, and the real word is English only | Cheap to iterate; the gibberish needs no translation | [VOICE.md](VOICE.md) |
| 2026-09-25 | Focus mode is visual only; threads show agent and project only | Quiet when asked; private by default | [BEHAVIORS.md](BEHAVIORS.md), [UX.md](UX.md) |
| 2026-09-25 | Life stages, Retire, backup and the buddy card wait | Keep v1 small | [FUTURE.md](FUTURE.md) |
| 2026-09-26 | USB serial runs at 460800 baud, not 921600 | The board's CH340 bridge on macOS's own driver garbles 921600, for flashing and for messages alike | [DEVICE.md](DEVICE.md) §7, [PROTOCOL.md](PROTOCOL.md) §2 |
| 2026-09-26 | NimBLE is linked only from F4 on | Linking it reserves the Bluetooth controller's 39 KB at boot, even while Bluetooth is off | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | `dbg.light` and `dbg.pattern`'s `fill` join the debug channel | Bring-up needs the LED and backlight on command, and the webcam finds the screen by lighting it solid white | [VERIFICATION.md](VERIFICATION.md) §3 |
| 2026-09-26 | The renderer uses integer maths only, with anti-aliasing from palette ramps | Floating point can round differently on the ESP32 and the Mac, and screenshots must match pixel for pixel | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | The fonts are Geist Mono (SIL Open Font License), 13 px and 22 px, generated by `tools/fontgen` | Legible anti-aliased text in the "Warm Terminal" style, free to embed | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | `dbg.reset` joins the debug channel, and every scenario starts with it | The board keeps state between scenarios while the simulator starts fresh; both must start from the same place | [VERIFICATION.md](VERIFICATION.md) §3–4 |
| 2026-09-26 | Webcam clips are named live presets (`idle`, `needs_you`, `cheer`) with the clock running, not scenario files | Scenarios freeze the clock for exact screenshots, so they don't move on camera | [VERIFICATION.md](VERIFICATION.md) §5 |
