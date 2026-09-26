# Boop: architecture

Updated 2026-09-26. The parts of Boop, how they connect, the memory files
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
   a1b2, project landing, turn finished".
3. The **core** updates its session table, works out from when the turn
   started that it took 18 minutes, adds XP, and by rule calls the `face`
   action with a cheer. Boop cheers in well under a second.
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
| Memory store | The only code that reads or writes `long-term.md` and `short-term.md`: supplies all three memory files' text and applies changes within limits | Models, the device |
| Device link | Sends snapshots and moments; receives taps, talk and the device's other inputs; over Bluetooth or USB | What any of it means |

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
  changes, in [BEHAVIORS.md](BEHAVIORS.md) §1's layers: something needing
  you wins, a moment (a cheer, an oops, a reply) plays over the base
  state, and the base state is working while any agent works, asleep with
  no sessions or at night with nothing working, and otherwise idle;
- calls actions for the immediate reactions (a cheer, an oops, a nod) and
  for Boop's occasional working chatter;
- turns events, taps and talk into triggers for the harness. It merges
  bursts within 3 s. While something needs you, or during quiet and focus
  mode, it sends only `talk` and the daily reflection;
- keeps XP, hunger, mood, quiet, focus and "away", all by rule
  ([BEHAVIORS.md](BEHAVIORS.md)).

In code the core is a pure state machine: each event, input or one-second
tick goes in with the time, and a list of effects comes out (a snapshot, a
moment for `face`, a mumble for `say`, a trigger, a Happened line, new
Growth, a new day, start or stop listening). The app hands each effect to
the part that carries it out, which keeps the core testable on a virtual
clock.

Trigger merging is leading-edge: the first trigger after a quiet spell goes
out at once, and any that follow within 3 s are held and sent as one when
the window ends, keeping the most important line (a failure, then a long
finish, then a finish or a tap, then a start) with "+N more".

The brain adds to the rules' reaction and never cuts it off. The app
estimates how long each rule moment plays with the device's own rule: the
animation's length scaled by `pace`, with a cheer's size adjusted by
`energy`, or, if longer, the mumble's syllables (the word is two beats)
plus 1.2 s to read the bubble. It holds a moment from a brain tool call
until the last rule moment and the core's pending follow-ups (`side_eye`
after `oops`, `yawn` after `stretch`, `gobble`) are over. `listening` and
`thinking` don't hold anything back: the brain's reply is meant to replace
`thinking`.

### 3.3 Harness and brain

The harness is a small, generic loop ([HARNESS.md](HARNESS.md)). It builds
a typed situation (the trigger, memory, recent turns) and menu (the tools
and their limits), asks the brain to decide, checks the tool calls it gets
back and routes them, without knowing what the tools do or what kind of
model decided. The brain is whatever is plugged in: Apple's on-device model
by default, the rules-only brain, or Jev, a "system one" model reached with
the person's own API key, which answers questions rather than writing and
leaves the writing to Apple's model. A cloud language model is an interface
only in v1 (`cloud:<model>`), switched on later ([FUTURE.md](FUTURE.md)). The brain is assumed to be small, so the tools are
few, flat and mostly multiple choice. Event, tap and talk calls share a
short conversation with the brain that starts over instead of being
compacted.

### 3.4 Actions

Actions are Boop's tools. The same actions serve the core's rules and the
brain, so a cheer looks the same whichever of them asked for it.

| Action | Arguments | What it does |
| --- | --- | --- |
| `say` | `feeling`, `word?` | Asks Voice for a Minion line, then sends it to the device as a moment |
| `face` | `name` | Sends an animation to the device as a moment |
| `quiet` | `minutes` | Tells the core to stop mumbles for a while |
| `note` | `text` | Adds a line to today's notes |
| `remember` | `text` (short), `kind` (`about_you` or `preference`) | Reflection only: adds a line to About you or Preferences within its limits |
| `forget`, `temperament`, `moment` | short text | Reflection only: change long-term memory within its limits (v1 reflection doesn't offer `forget`, §11) |

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

The memory store is the only code that reads or writes `long-term.md` and
`short-term.md` (§4). `steering.md` is bundled read-only in the app and
passed to the store as text. The store hands all three files' text to the
harness for each prompt, applies changes from actions within each
section's limits, writes atomically, and snapshots the files before each
reflection.

### 3.7 Device link

The device link sends snapshots and moments and receives taps,
push-to-talk presses and the device's other inputs
([PROTOCOL.md](PROTOCOL.md) §4). It has two transports carrying identical
messages:

- **Bluetooth**, for normal use.
- **USB serial**, for development and automated tests. An agent can't launch
  the app with Bluetooth on, so the whole hook-to-screen path is tested over
  USB instead ([VERIFICATION.md](VERIFICATION.md) L4).

Nothing above the device link knows which one is in use.

### 3.8 Push-to-talk

The device has no mic, so holding its button, or clicking Talk in the
popover, records from the Mac's mic. The core decides when the mic is on
(`listen` effects): from `talk_on` or Talk until `talk_off`, Send, 30 s,
or, for the device's button, the link dropping. The menu bar shows it
while it's on ([UX.md](UX.md) §5). The app asks for Speech Recognition and
the Microphone on first use, turns speech into text locally, and the core
gives it to the harness as a `talk` trigger. Audio is discarded immediately. The words stay
in the brain's conversation, in memory only, until it starts over
([HARNESS.md](HARNESS.md) §4).

## 4. Memory files

All of Boop's memory is three Markdown files. `steering.md` is bundled
read-only in the app and passed in as text; `long-term.md` and
`short-term.md` live in the app's state directory (§11). Every brain call
includes all three.

| File | What it is | Changes |
| --- | --- | --- |
| `steering.md` | How Boop behaves: character, how to act, examples, what never to do | Never at runtime. Ships with the app and changes only in an announced release |
| `long-term.md` | Who this Boop has become, and lasting facts and preferences about you | Once a day, at reflection, within limits; XP by the core |
| `short-term.md` | Today: Boop's mood, notes about what you're doing and said, what happened | Throughout the day; starts fresh after reflection |

**Reflection** runs once a day, at the first activity of a new day. The
memory store snapshots both writable files to `history/<date>/`, where
`<date>` is the day being reflected on (setup also snapshots, under the
day Boop hatched). Then `short-term.md` starts fresh, and the brain reads
yesterday's copy from the snapshot and updates `long-term.md` through the
reflection actions.

The files are plain text. Hand edits are allowed: the store reads a file
again when it changes on disk, before its next change, so an edit isn't
overwritten. A file that won't parse is kept as `<file>.broken`.
`long-term.md` is restored from its newest snapshot that reads.
`short-term.md` snapshots are always of an earlier day, so it starts fresh
instead, keeping the file's date if one can be found so the day doesn't
start (and reflect) twice.

Each file also has a size budget, so the whole prompt stays within
[HARNESS.md](HARNESS.md) §4 without trimming: `long-term.md` at most
3,200 bytes (about 800 tokens) and `short-term.md` at most 2,400 bytes
(about 600). The line limits below mostly keep them there; when they
don't, a change to long-term memory is refused ("full") and short-term
memory drops its oldest Happened lines.

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
| Temperament | Reflection | At most one sentence changed a day: `temperament` adds one sentence of at most 120 characters, and past five sentences it replaces the oldest |
| Moments | Reflection | At most 20 of at most 80 characters; at most one a day, dated the day reflected on. Past 20, the oldest drops |
| Growth | Core | [BEHAVIORS.md](BEHAVIORS.md) §4. While Boop is starving the line also carries `lost: N`, the XP lost since it was last fed, so a restart doesn't take a day's XP twice |
| About you | Reflection | At most 30 lines of at most 100 characters; no code, paths, secrets or other people's names. A new line when full is refused; in v1 the person frees room by editing the file |
| Preferences | Reflection | At most 15 lines; same limits |

The checks are simple rules in the memory store: one line, no links,
addresses, backticks, braces, `=`, `;` or `$`, nothing path-shaped, nothing
that looks like a key, and no capitalised word mid-sentence other than
days, months, agents, acronyms and Boop's own name. They err on the side
of refusing.

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
| Notes | `note` action (from the brain) | At most 10 lines of at most 80 characters; the oldest drops first. No code, paths or secrets |
| Happened | Core | One line per notable event, summaries only; the last 40 lines |

Mood is internal. It shapes behaviour and is only visible in debug mode.

## 5. Common event shape

```json
{"agent":"claude_code","detail":{"tool":"Bash","topic":"tests"},"event":"activity",
 "project":"landing","session":"a1b2","ts":1790000000123}
```

| Field | Meaning |
| --- | --- |
| `agent` | `claude_code` or `codex` |
| `session` | Stable session or thread ID |
| `project` | Short project name, from the working directory |
| `event` | `session_start`, `turn_start`, `needs_you`, `activity`, `turn_end`, `turn_failed`, `session_end` |
| `detail` | Small and event-specific: `tool` and `topic` on `activity`, `tool` on `needs_you`, and `error`, an error class, on `turn_failed` ([ADAPTERS.md](ADAPTERS.md) §2–3); nothing on the others. Never prompt text, commands or file contents. The core measures how long a turn took itself, from its start |
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
reports taps, push-to-talk, focus and touch-and-hold. It holds no
personality or memory, just a device ID, its touch calibration, and its
animation and syllable library.
What it does for each trigger is in [BEHAVIORS.md](BEHAVIORS.md); the
hardware and firmware are in [DEVICE.md](DEVICE.md).

## 8. When things go wrong

| Failure | Behaviour |
| --- | --- |
| App not running | Hooks exit at once; agents are unaffected. The device idles with a sleepy "no app" face |
| Device disconnected | The app keeps going; the next snapshot catches the device up on reconnect |
| Brain offline, slow or invalid | Rules still drive every reaction; the rules-only fallbacks in `steering.md` fill in; memory doesn't grow that day |
| Memory file won't parse | `long-term.md` comes back from its newest snapshot that reads; `short-term.md` starts fresh (§4) |
| Mac asleep | The device drifts to sleep after 30 s without a `state` |

## 9. Budgets

| Path | Target |
| --- | --- |
| Agent event → pixel | < 200 ms p95 |
| Tap → visible feedback | < 20 ms, on the device |
| Hook overhead | Single-digit ms. When the app is slow, the hook waits at most 50 ms in total, then gives up |
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
| 2026-09-26 | A speaker is attached to the bench board | The owner added one, so sound is now checked by ear | [DEVICE.md](DEVICE.md) §3 |
| 2026-09-26 | `dbg.light` and `dbg.pattern`'s `fill` join the debug channel | Bring-up needs the LED and backlight on command, and the webcam finds the screen by lighting it solid white | [VERIFICATION.md](VERIFICATION.md) §3 |
| 2026-09-26 | The renderer uses integer maths only, with anti-aliasing from palette ramps | Floating point can round differently on the ESP32 and the Mac, and screenshots must match pixel for pixel | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | The fonts are Geist Mono (SIL Open Font License), 13 px and 22 px, generated by `tools/fontgen` | Legible anti-aliased text in the "Warm Terminal" style, free to embed | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | `dbg.reset` joins the debug channel, and every scenario starts with it | The board keeps state between scenarios while the simulator starts fresh; both must start from the same place | [VERIFICATION.md](VERIFICATION.md) §3–4 |
| 2026-09-26 | Webcam clips are named live presets (`idle`, `needs_you`, `cheer`) with the clock running, not scenario files | Scenarios freeze the clock for exact screenshots, so they don't move on camera | [VERIFICATION.md](VERIFICATION.md) §5 |
| 2026-09-26 | While something needs you, the device plays only `nod`, `listening`, `thinking`, `shrug` and `zip`, and no mumbles | BEHAVIORS §1 says attention wins; replies to the person still need to show | [BEHAVIORS.md](BEHAVIORS.md) §1 |
| 2026-09-26 | The device plays the nod when `attn` clears, the fallback shrug after 8 s of thinking, and the mood face on touch-and-hold, and sends a new `input` `feel` | Feedback within 20 ms can't wait for the Mac, and a snapshot protocol has no "cleared" event | [BEHAVIORS.md](BEHAVIORS.md) §3, [PROTOCOL.md](PROTOCOL.md) §4 |
| 2026-09-26 | Over USB, the device sends `status` when the Mac first speaks, or speaks after 30 s of silence | USB has no connection event, and the Mac replies to the first `status` with a `state` either way | [PROTOCOL.md](PROTOCOL.md) §4 |
| 2026-09-26 | `dbg.ping` reports Bluetooth's state (`ble`) and advertised name | L2 checks advertising over USB without touching the Mac's Bluetooth | [VERIFICATION.md](VERIFICATION.md) §3 |
| 2026-09-26 | `dbg.state` reports `sfx` cues (chirp, jingle, pulse) before there's a sound player | The ladder's sound timing is testable now, and F5 plays the same cues | [VERIFICATION.md](VERIFICATION.md) §3 |
| 2026-09-26 | `boop-hook` and the app share a small Foundation-only `HookWire` target (the hook line, topic tags, the socket) | The hook client stays small and fast without linking the rest of the app, and both sides agree on the line by construction | [PLAN.md](PLAN.md) §2, [ADAPTERS.md](ADAPTERS.md) §2 |
| 2026-09-26 | The core is a pure state machine that returns effects, with one-second ticks for its timers | Decisions stay separate from effects, and every rule and timing is testable on a virtual clock | §3.2 |
| 2026-09-26 | Trigger merging is leading-edge with a held follow-up; finishes within 3 s make one cheer, upgraded if a later one is bigger | Holding every trigger for 3 s would make the brain late every time, and the reactive loop can't wait | §3.2, [BEHAVIORS.md](BEHAVIORS.md) §3.1 |
| 2026-09-26 | A late `Notification` within 5 s of a clear is ignored; an hour without events makes a working session idle, and a day forgets it | A quick approval could otherwise turn Boop amber again with nothing waiting, and a missed `SessionEnd` would keep it busy | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-26 | `state` cuts names to 23 bytes and drops thread rows to stay within 512 bytes | Eight rows of long project names overflow a line, and the device keeps names in 24-byte fields | [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-26 | Days together count the day of setup as day 1; failed turns earn no XP; the Growth line carries `lost` while starving | The stats screen shouldn't say 0 days, "finishes" means `turn_end`, and starving must survive restarts | [BEHAVIORS.md](BEHAVIORS.md) §4 |
| 2026-09-26 | The memory files have byte budgets (3,200 and 2,400), enforced by the store | The line limits alone allow about 1,600 tokens of long-term memory, twice its share of the prompt | §4 |
| 2026-09-26 | A broken `short-term.md` starts fresh (keeping its date); a broken file is kept as `.broken`; the store rereads files changed on disk | Short-term snapshots are always of an earlier day, and hand edits shouldn't be lost or overwritten | §4 |
| 2026-09-26 | `temperament` adds a sentence (up to five, replacing the oldest); `moment` drops the oldest past 20; `remember` refuses when full | Flat, one-argument tools a small model can use, and memory that keeps growing without breaking its limits | §4.2, [HARNESS.md](HARNESS.md) §6 |
| 2026-09-26 | Doubled syllables skip the English word list, except common doubles like `mama`; Voice re-rolls a failing gibberish word while building | The word list rejects most doubles (`kiki`, `pipi`, `baba`), which are the Minion bounce; with whole-line retries alone one dialect in three hummed about 5% of the time | [VOICE.md](VOICE.md) §7 |
| 2026-09-26 | The full syllable set is 64, with 40 vocabulary words | Fixed now so F5's assets and the `say` tool agree | [VOICE.md](VOICE.md) §3, §6 |
| 2026-09-26 | `say` plays the face for its feeling under the mumble, and drops the call in quiet, focus or while something needs you | The device only speaks over an animation, and a reply shouldn't break quiet | [HARNESS.md](HARNESS.md) §6 |
| 2026-09-26 | `event` offers only `say` and `face`; `note` stays on `talk` | An event line holds nothing the core's Happened line doesn't, and Apple's model filled notes by copying old ones (14 of 92 calls dropped) | [HARNESS.md](HARNESS.md) §5 |
| 2026-09-26 | `forget` picks from the lines that exist, rebuilt for each call | Multiple choice suits a small model; free text named lines that weren't there | [HARNESS.md](HARNESS.md) §6 |
| 2026-09-26 | One answer format for every brain (`{"calls":[…]}`); Apple's schema starts with a `react` choice | The shape check stays one piece of code; without the choice Apple's model answered every trigger | [HARNESS.md](HARNESS.md) §3, §7 |
| 2026-09-26 | The rules-only brain reads its table from the prompt, like any brain. Replaced below: it matches the trigger itself | Same interface, same prompt; nothing special-cased | [HARNESS.md](HARNESS.md) §7 |
| 2026-09-26 | v1 reflection doesn't offer `forget` | Apple's model forgot the true line "Ships on Fridays." in nearly every L5 reflection, even with a `none` choice and explicit steering. Forgetting destroys memory and is rarely needed; the action stays, tested, for a later brain | [HARNESS.md](HARNESS.md) §5 |
| 2026-09-26 | Apple's schema starts every choice with `none` | Without it the model filled `word` with the vocabulary's first entry (`tests`) on greetings and praise | [HARNESS.md](HARNESS.md) §7 |
| 2026-09-26 | `moment` refuses a text that retells an earlier moment | Apple's model copied the sample's old moment for a new day | [HARNESS.md](HARNESS.md) §6 |
| 2026-09-26 | `boopctl bridge` shares the serial port on a Unix socket; every board line goes to every client, and other `boopctl` commands use a running bridge | The headless app and the checks need the board at the same time, and only one process can open the port | [VERIFICATION.md](VERIFICATION.md) §2 |
| 2026-09-26 | The app's state lives in `~/Library/Application Support/Boop` (memory files, their `history/` snapshots and any `*.broken` copies, `settings.json`, the socket, `boop.lock`, `boop.log`, `doctor-armed` while the doctor is armed, `bin/boop-hook`); hooks call that copy of `boop-hook` | One place per Boop, and hooks survive rebuilding or moving the app | [ADAPTERS.md](ADAPTERS.md) §5 |
| 2026-09-26 | Installing Codex hooks also sets `codex_hooks = true` in `~/.codex/config.toml`; removing leaves it | Codex ignores `hooks.json` without it, and other hooks may rely on it | [ADAPTERS.md](ADAPTERS.md) §5 |
| 2026-09-26 | Headless mode accepts `{"dev":"talk","words":…}` on the hook socket, for `boopdev talk`; the menu-bar app ignores it | Push-to-talk needs the Mac's mic, which tests can't use; the socket is already private to the user | [VERIFICATION.md](VERIFICATION.md) §2 |
| 2026-09-26 | The app logs hooks only while `doctor-armed` exists in its state directory | The doctor needs to see a hook arrive; logging every tool call the rest of the time is noise | [ADAPTERS.md](ADAPTERS.md) §6 |
| 2026-09-26 | Boop's record (tasks finished, number of projects) is kept in `settings.json` by the app, not the core | It's only for the popover, and counting needs no rule | [UX.md](UX.md) §7 |
| 2026-09-26 | `Info.plist` (usage descriptions, `LSUIElement`) is linked into the `Boop` binary with `-sectcreate` | SwiftPM builds no app bundle here, and macOS reads usage descriptions from that section | [PLAN.md](PLAN.md) A4 |
| 2026-09-26 | The brain's moments wait until the rules' moment and the core's follow-ups have played | The rules brain answers in 0 ms and Apple's in about 1.5 s, so a `face` replaced the cheer or the oops before it showed (found by J1's pipeline check) | §3.2, [BEHAVIORS.md](BEHAVIORS.md) §3 |
| 2026-09-26 | Headless mode's clock can be moved forward (`{"dev":"advance"}` on its socket), hooks are timed on the runtime's clock, and `--trace` logs every hook and every line sent to the device, marked rules or brain | The pipeline check must finish a 6-minute turn in seconds, and show that the brain's moments come after the rules' | [VERIFICATION.md](VERIFICATION.md) L4 |
| 2026-09-26 | `dbg.state` counts the `state` and `moment` messages received (`rx`) | Hook-to-device latency needs the moment the board has the new `state`, not a guess from its screen | [VERIFICATION.md](VERIFICATION.md) §3 |
| 2026-09-26 | The DAC streams all the time (silence when idle), and the amp is on only while something plays | ESP-IDF's synchronous DAC writes stop getting buffers back once the DMA runs dry; found on the board in F5 | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | The harness limits brain speech in code: `say` on `event` at most once every 10 minutes and never on a turn start, on `tap` once every 5 minutes; a tool past its limit isn't offered | L5 with Apple's model: nearly every event got a mumble, and steering didn't make it choose silence. The owner chose a limit in code over relying on the model (PROGRESS.md 2026-09-26 05:36). Plain data per trigger kind, so the harness stays generic | [HARNESS.md](HARNESS.md) §3, §5 |
| 2026-09-26 | L5 counts guardrail refusals apart and measures valid shape over the answers given; its triggers run 3 minutes apart under one limit history | A refusal is dropped safely (Boop keeps the rule reaction), and isn't a badly shaped answer. Speech has to be judged after the limits. Owner's decision, 2026-09-26 | [VERIFICATION.md](VERIFICATION.md) L5 |
| 2026-09-26 | The hums `mm` and `nn` are synthesised tones, not `say` | `say` gives 0.85 s of speech for them, most likely the letter names, not a hum | [VOICE.md](VOICE.md) §8 |
| 2026-09-26 | A line lasts exactly beats × `ms` (the word is two beats); timing jitter moves within pairs of beats | The mouth, the bubble and the sound share one timeline, and `dbg.state` can check it | [VOICE.md](VOICE.md) §8 |
| 2026-09-26 | Touch calibration is an affine map fitted on the Mac by `boopctl calibrate` and sent with a new `dbg.touchcal`; the board only stores and applies it | A full affine (not LovyanGFX's own 4-corner routine) copes with swapped or skewed axes, keeps the fit testable in Python and the map in pure C++, and keeps drawing independent of the display library | [DEVICE.md](DEVICE.md) §4, [VERIFICATION.md](VERIFICATION.md) §2–3 |
| 2026-09-26 | The screen is landscape, 320×240, with USB-C on the right (F6). The canvas is 320×240 and LovyanGFX turns the physical 240×320 panel with one constant, `kRotation` (1, or 3 if the board shows that upside down). Touch maps raw readings in pure C++ even before calibration, turned by the same constant; a stored calibration keeps the screen size and rotation it was fitted on, and one for any other screen is ignored (the portrait build's record is deleted). The test pattern gains a black bar down the USB-C edge | The owner uses Boop sideways, as the gen-2 face was. Letting the panel controller turn the picture keeps the push in row order with no per-pixel work, and the drawing code only ever sees the canvas size. A portrait calibration applied to the landscape screen would send taps to the wrong place. In landscape the UP arrow no longer points away from USB-C, so the pattern needs its own mark for the port's side | [UX.md](UX.md) §2, [DEVICE.md](DEVICE.md) §4 and §7, [VERIFICATION.md](VERIFICATION.md) §3 and L3 |
| 2026-09-26 | The eyes are solid rounded rectangles with no pupil, iris or highlight (F6). A look moves the whole eye, and the eye on the side looked towards grows a little; `Pose::pupil` became `Pose::eyeSize`; where a lid meets the edge of an eye the corner is rounded | The owner found the pupils too realistic: cream eyes with a dark pupil read as real eyeballs, and gen-2's solid eyes were cuter. Without pupils, the size of the whole eye takes over from pupil size: curious, listening, needs you and love bigger, worried and busy smaller, as their pupils were, while startled now widens its eyes where it used to shrink its pupils. Thinking can't roll its pupils up any more, so it lifts round-topped eyes instead of lidding them, which would make it the working face mirrored. A sharp lid corner was the last hard point on a soft face, so the corner is rounded wherever a lid meets the edge of an eye, with a smaller radius where 8 px doesn't fit | [UX.md](UX.md) §2, [PLAN.md](PLAN.md) F6 |
| 2026-09-26 | Setup and settings open inside the popover, not in windows; volume, focus and "I'm away" move from the overview to Settings; the board's id isn't shown; the app takes gen-2's "Boop Cream" look, with a small copy of the face in the popover and as the menu-bar icon | The owner found the setup window jarring, the overview crowded with controls and debug data, and preferred gen-2's styling and flow | [UX.md](UX.md) §6–7 |
| 2026-09-26 | The cloud brain is an interface only in v1: `cloud:<model>` refuses every call, and settings offers Apple's model or rules | Apple's model is the default and needs no key; wiring and testing a provider can wait | §3.3, [HARNESS.md](HARNESS.md) §7, [FUTURE.md](FUTURE.md) |
| 2026-09-26 | The brain contract is typed: `decide(situation, menu) → calls`. The conversation is kept as typed turns (trigger, limit lines, calls that ran). Language models share a text adapter that renders today's prompt from the turns and checks the answer JSON; the harness checks every brain's calls against the menu. The rules brain matches the trigger itself | The owner asked for a third brain, Jev, which answers typed questions and can't read a prompt or write JSON. Typed input and output let any kind of model decide, and keep the history when brains change or share a call. Apple's model sees exactly the prompt it saw before (the conversation tests pass unchanged) | [HARNESS.md](HARNESS.md) §1, §3–4, §7 |
| 2026-09-26 | A third brain, `jev`: TypeSafe's Jev with the person's own API key (the existing Keychain field; `BOOP_API_KEY` for `boopdev` and headless runs). The situation goes to TypeSafe as JSON: `steering.md`, both memory files, recent turns and now, with the person's words | The owner wanted to try a "system one" model in place of the on-device one. In L5 it answered every trigger in about 0.2 s against Apple's 2 s, with no refusals, and followed talk requests (quiet for 15 or 60 minutes) that Apple's model missed. It leaves the Mac, so the settings say so | [HARNESS.md](HARNESS.md) §4, §7, [UX.md](UX.md) §7, [VISION.md](VISION.md) §7 |
| 2026-09-26 | Jev asks whether to write as its own yes/no per tool that needs words, not as an `act` option; on a yes, Apple's model writes only that call (a `Writer`: one tool, must call it) | As an `act`, `note` never beat staying quiet (0.21–0.29 against up to 0.70). Given the whole decision again, Apple's model chose to stay quiet on both notes Jev had said yes to (0.92–0.93). Deciding and writing are separate jobs | [HARNESS.md](HARNESS.md) §7 |
| 2026-09-26 | The Mac answers every `status` with a `state`, not only the first after connecting | It's one extra `state` a minute, and it covers a connect-time `status` sent before the Mac subscribed over Bluetooth | [PROTOCOL.md](PROTOCOL.md) §4–5 |
| 2026-09-26 | The installer installs and repairs nothing while its copy of `boop-hook` is missing, and settings and setup say so; `make run` builds everything first | `make run` built only the app, so there was no `boop-hook` to copy, and launch repair swapped the owner's gen-2 entries for ones calling a missing file: every Claude and Codex event was dropped, while settings said "Connected" | [ADAPTERS.md](ADAPTERS.md) §5, [UX.md](UX.md) §6–7 |
| 2026-09-26 | Event, tap and talk calls share a short conversation with the brain, sent in the same order every call and never compacted: it starts over when its opening changes, when it's full, or after a failed answer. Talk words stay in it until then | The owner asked for a running transcript modelled on pi, kept simple (start over rather than compact) and in an order a cloud provider's prompt cache can reuse. With history, Apple's model answers quiet much more often; tuning is PLAN.md A6 | [HARNESS.md](HARNESS.md) §4 |
| 2026-09-26 | Event, tap and talk are offered the same four tools. A tool past its limit, or outside the trigger's allowed list, is named in the prompt (`say limit: …`) and a call to it is dropped, instead of not being offered. This replaces the earlier rows "`event` offers only `say` and `face`" and the "isn't offered" part of the speech-limit row | A conversation's tools can't change between calls. In L5 the `say` line holds, but Apple's model calls `note` on most events; the harness drops those calls (PLAN.md A6) | [HARNESS.md](HARNESS.md) §5 |
| 2026-09-26 | The face takes gen-2's look (F6 follow-up): smaller lavender-white eyes, a short dash mouth, thin "^" arches for happy eyes, a heart at the top right for affection (`Pose::heart`), a climbing "zzZZ" when asleep (`Pose::zzz`), a strain and a sweat drop while working (`Pose::sweat`), a gentle sway for the tap, and open eyes glancing up for no app | On the board the owner found the F6 eyes less cute than gen-2's, the tap's solid crescents frightening (a dome with a bite out of the bottom reads as a hooded glare), and the sleepy no-app face droopy, and asked for the older faces. Seeing those, they asked for a heart instead of pink cheeks, a "zzZZ" and some effort. The new parts are pose fields, so they ease in and out with every blend, and the simulator draws them as the board does | [UX.md](UX.md) §2, [BEHAVIORS.md](BEHAVIORS.md) §2–3, [PLAN.md](PLAN.md) F6 |
| 2026-09-26 | Push-to-talk can also start from a Talk button in the popover. The core owns whether the mic is on, and turns it off after 30 s, or when the link drops while the device's button is held; the menu-bar icon turns red while it's on. The app asks for mic access on first use, not at launch | The owner found no way to talk from the Mac and no sign the Mac was recording. The mic stopped only on `talk_off`, so a dropped link or a lost line (USB drops the odd one) left it on until the app quit | [UX.md](UX.md) §5, §7 |
