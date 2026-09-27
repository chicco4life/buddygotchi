# Boop: architecture

Updated 2026-09-28. The parts of Boop, how they connect, what each one
keeps and where, the budgets, and the decisions still in force. The other
specs go deeper on each part; [README.md](README.md) lists them.

## 1. The shape of it

Boop has two parts: a Mac app that does all the thinking, and a cheap device
on your desk that draws the creature. Information flows one way, from your
agents to Boop to you. Boop watches and tells you things; it never acts on
your agents. When an agent needs approval, Boop gets your attention, and you
approve on the Mac as you normally would.

```
  Claude Code, Codex
    │ hook: JSON on stdin
    ▼
  boop-hook: one line on boop.sock, 50 ms budget, always exits 0
    │
┌───┼───────────────────────── Boop Mac app ──────────────────────────┐
│   ▼                                                                 │
│ Hook server ─► Adapter ─► Core ◄───────────── tap ◄────────────┐    │
│                            │  sessions, rules, 1 s tick        │    │
│     ┌──────────────┬───────┴───────┬───────────────┐           │    │
│     ▼              ▼               ▼               ▼           │    │
│   state      rule moment,        event          new day        │    │
│     │        chatter (Voice)       │               │           │    │
│     │              │               ▼               ▼           │    │
│     │              │     Harness ◄──► Jev     Memory store     │    │
│     │              │        │ answers                          │    │
│     │              │        ▼                                  │    │
│     │              │     Actions ── mood ─► mood file ─► Core  │    │
│     │              │        │                                  │    │
│     │              │      react ─► Voice ─► Moment schedule    │    │
│     │              │                              │            │    │
│     ▼              ▼                              ▼            │    │
│   Device link (Bluetooth, or USB through `boopctl bridge`) ────┘    │
└────────────────────────┬──────────────────────────▲─────────────────┘
                         │ state, moment            │ input, status, ended
                         ▼                          │
             Device: draws, plays, blinks, chirps, reports taps
```

**Following one event:**

1. Codex finishes a task. Its hook runs `boop-hook codex`, which sends one
   line to the app and exits at once.
2. The Codex **adapter** turns it into the common event: "Codex, session
   a1b2, project landing, turn finished".
3. The **core** marks the session idle and, by rule, plays a cheer, well
   under a second after the hook.
4. The core also hands the **harness** an event with its line: `codex
   finished turn 3 on "landing": done after 18 min, a very long turn, 24
   tools.` The event wakes the brain, so the harness asks **Jev** every
   action's questions about it in one request, and Jev answers, say,
   `react: proud`, `react.loops: once` and `word.feeling: yay`.
5. The **`react` action** asks **Voice** for Minion speech in proud's
   voice (*"ma-po li… yay!"*) and queues it with proud as its face, held
   once. No line is playing, so the **device link** sends it at once, and
   the device shows the rest of the cheer in proud's face while Boop
   mumbles. When the face and the mumble are over, the device says so
   (`ended`), and HISTORY stops showing the reaction as in progress.

The brain never sits between an event and the screen. Rules give the
immediate reaction, and the brain adds character a second or two later. If
the brain is slow, offline or missing, Boop still reacts to everything, just
with less personality.

## 2. Three loops at three speeds

| Loop | Runs on | Speed | Does | Never does |
| --- | --- | --- | --- | --- |
| Reflex | Device | < 20 ms | Tap feedback, blinks, playing moments, the needs-you chirp and light | Wait for the Mac |
| Reactive | Core → device link | < 200 ms p95 | Hook → rule → `state` or moment | Wait for the brain |
| Deliberative | Harness + Jev → actions | A pass has 1.25 s; its mumble then waits up to 5 s for its turn | A change of mood, a mumble with character | Block the reactive loop |

## 3. Components and boundaries

Each part has one job and knows as little as possible about the others.
The core and the brain decide *what* should happen, and actions make it
happen. Nothing that decides ever builds Minion speech, touches a file or
talks to the device.

| Part | Code | Does | Doesn't know about |
| --- | --- | --- | --- |
| Hook client | `app/BoopHook/`, `app/HookWire/` | Turns a hook's JSON into one hook line on the socket and exits 0 | Anything past the socket |
| Hook server | `Adapters/HookServer.swift` | Accepts hook lines on `boop.sock` and hands them to the runtime; never replies | What they mean |
| Adapter | `Adapters/Adapter.swift` | Turns a hook line into the common event: the agent's mapping, project, workspace, error class | Boop's state, the brain, the device |
| Core | `Core/` | Keeps the session table; decides what the device shows, the rule reactions, and the events for the harness | Minion speech, models, hook formats, files |
| Harness | `Harness/` | Keeps the transcript; for each event that wakes the brain, builds the state, asks every action's questions in one request, hands each action its answers and records what it did | Minion speech, the device, an event's facts, what an action does |
| Brain | `Brains/JevBrain.swift` | Jev: answers multiple-choice questions about a plain-text state, with probabilities | Everything else |
| Actions | `Actions/` | `mood` and `react`: carry out one call each, checking their own rules | Whether a rule or the brain called them |
| Moment schedule | `App/MomentSchedule.swift` | Decides when each brain moment plays: after any line playing, over an animation, or not at all | What's in it |
| Voice | `Voice/` | Turns a feeling and an optional word into Minion speech in this Boop's dialect | Who asked, or why |
| Memory store | `Memory/` | Reads and writes `long-term.md`, `short-term.md` and their snapshots | Models, the device |
| Mood store | `MoodStore` in `Actions/MoodAction.swift` | Reads and writes the `mood` file | Who changes it |
| Device link | `DeviceLink/` | Sends `state` and moments, receives taps and status, over Bluetooth or USB | What any of it means |
| Hook installer | `Install/` | Adds, repairs and removes Boop's entries in the agents' settings | Anything at runtime |
| Runtime | `App/Runtime.swift` | Wires the parts together, owns the queue and the timers, and carries out the core's effects | Any rule |
| Mac app | `app/Boop/` | The menu-bar icon and popover, setup and settings; places `boop-hook` and repairs hooks at launch | Any rule |

`BoopKit` paths are under `app/BoopKit/`.

### 3.1 Adapters

Each adapter turns one agent's hook calls into the common event. Hooks
only report, so the agent carries on as normal ([ADAPTERS.md](ADAPTERS.md)).

### 3.2 Core

The core is plain rules in a pure state machine. Every input goes in with
the time, and effects come out; the runtime hands each effect to the part
that carries it out. So every rule and timing is testable on a virtual
clock.

| Input | From | Effects it can return |
| --- | --- | --- |
| `handle(event)` | A hook, through the adapter | `state` or `sessions`, the cheer, events, a new day |
| `input(tap)` | The device | `state`, a `tap` or `pokes` event, a new day |
| `tick(at:)` | The runtime, once a second | `state` or `sessions`, working chatter, a Codex request showing after its grace, a heartbeat |
| `setVolume`, `setMood` | Settings; the mood action | `state` |
| `setRules`, `setBrain`, `setWallClock` | A new personality; Jev's key read or changed; every tick | None: they change later decisions |

| Effect | Carried out by |
| --- | --- |
| `state(snapshot)`, only when something on it changed | The device link, and the menu bar's status |
| `sessions`, when the session list changed and the snapshot didn't | The menu bar's status, and `debug.jsonl`'s `status` line |
| `moment(anim, loops)`: a rule's `cheer`, with enough loops of the mood's design for its length ([BEHAVIORS.md](BEHAVIORS.md) §5) | The device link at once, cutting off whatever plays; the moment schedule notes it |
| `mumble(feeling, word)`: working chatter | Voice, then the device link, but only when nothing plays, no brain moment waits and nothing needs you |
| `event(Event)` | The harness ([harness/EVENTS.md](harness/EVENTS.md)) |
| `newDay(date)`: the first hook or tap of a new local day | The memory store (§4) |

**What the core keeps:** the sessions ([ADAPTERS.md](ADAPTERS.md) §4 has
their states), the taps of a poke streak and the last streak that reached
the brain, the heartbeat count, when chatter is next due, the last active
day, and its config: volume, mood, the personality's rules, whether
there's a brain, and every timing below.

**Its timers**, all in `Core.Config` and run by the tick:

| Timer | Value | Spec |
| --- | --- | --- |
| Codex grace before "needs you" shows | 2 s | [ADAPTERS.md](ADAPTERS.md) §4 |
| Safety net: a request clears after no events | 10 min | [ADAPTERS.md](ADAPTERS.md) §4 |
| A working session counts as idle after no events | 1 h | [ADAPTERS.md](ADAPTERS.md) §4 |
| A session is forgotten after no events | 24 h | [ADAPTERS.md](ADAPTERS.md) §4 |
| Poke streak: taps, within | 4, 3 s | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| A poke streak reaches the brain at most every | 60 s | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| Working chatter | The personality's range (120–240 s for `boop`) | [BEHAVIORS.md](BEHAVIORS.md) §2, §6 |
| Heartbeat while nothing works | Every hour with no hook or tap | [harness/EVENTS.md](harness/EVENTS.md) §4 |

**The snapshot** is derived, never stored: `asleep` with no sessions,
`working` while any works, `idle` otherwise; the mood; the session that
has needed you longest, with how many more do; how many work; the
volume ([PROTOCOL.md](PROTOCOL.md) §3). The popover's session list is
derived the same way, and can change while the snapshot doesn't, as
when a second idle session starts.

**Clocks.** Timers run on a steady clock that never steps and keeps
counting while the Mac sleeps, so setting the Mac's clock back can't
stall one. Days and times of day follow the wall clock, which the runtime
reports every tick.

**Moments.** The rules' moments play at once, each replacing whatever is
playing ([BEHAVIORS.md](BEHAVIORS.md) §3). The brain's wait in the
moment schedule, one at a time, until no line or reaction's face plays;
they have no animation, so they play over one without cutting it, and an
animation stops any line on the device. One that has waited longer than
5 s is dropped, since a late reaction is worse than none. Each carries
its reaction's handle. It goes to the device with an `id`, and the
device's `ended` says how it went: played out, cut short or skipped
([PROTOCOL.md](PROTOCOL.md) §4). The schedule or the runtime ends the
handle from that, or when the moment can't have played
([harness/DECISIONS.md](harness/DECISIONS.md) §5). Working chatter still
waits until nothing plays at all. The app times each moment as the
device does, to give each its turn and to know how long to wait for its
`ended`: the cheer's loops of its design, a wiggle's 0.7 s, or a
reaction's face's loops of the design showing, and the mumble's
syllables plus two beats for a word, at the line's pace, then 1.2 s to
read the bubble, when that's longer. The design showing is the look and
mood of the last `state`, or the cheer's while one plays, and its loop
is `FaceLoops`' number for it, the one the device has
([PROTOCOL.md](PROTOCOL.md) §3). The device ends a face on a loop
boundary of its own clock, which the app doesn't know, so the face may
end up to a loop sooner than the app reckons, never later.

### 3.3 Harness and brain

The brain is TypeSafe's Jev: it reads a plain-text state and answers
multiple-choice questions with probabilities, all in one request of about
0.2–0.3 s. The harness keeps the transcript, builds the state from it and
the steering files, asks every action's questions, and hands each action
its answers. One pass runs at a time, and a newer event that wakes the
brain replaces one waiting. An action that started something is shown in
progress until it reports how it ended, or the harness gives up waiting.
Without Jev's key no pass runs, and Boop does only its rule reactions
([harness/HARNESS.md](harness/HARNESS.md)).

### 3.4 Actions

Actions are what the brain can make Boop do. Each declares its questions,
reads Jev's answers to them, checks its own rules, and reports
`(ok, message)`, or that it started something whose end it reports
later ([harness/DECISIONS.md](harness/DECISIONS.md)). They run in this
order:

| Action | Effect | Its own rules |
| --- | --- | --- |
| `mood` | Saves the new mood to the `mood` file; the core puts it in the next `state`, and it's the MOOD section of the next pass | Only one of the seven moods, and only a change |
| `react` | Queues a moment in the moment schedule: the chosen mood as its face, held for the loops Jev picked, and Voice's mumble in that mood's feeling, with the chosen word if Jev is sure enough. It's started, not done, until the device says how the moment ended | Nothing while something needs you |

The rules' own moments (the cheer, working chatter) don't go through them.

### 3.5 Voice

Voice turns `feeling + word` into a Minion line in this Boop's dialect,
picked by the seed in `long-term.md`, and checks it isn't accidentally
English ([VOICE.md](VOICE.md)).

### 3.6 Memory store

The memory store is the only code that reads or writes the memory files
and their snapshots (§4), and it writes atomically.

### 3.7 Device link

The device link sends `state` whenever the snapshot changes and again
every 10 s, sends moments, answers each `status` with the latest `state`,
sends it again on reconnect, and hands taps to the core and each
moment's `ended` to the runtime ([PROTOCOL.md](PROTOCOL.md)). Its transport is Bluetooth for normal use or
USB, through `boopctl bridge`'s socket, for development. Both carry
identical lines, and nothing above the link knows which is in use. A line
sent while disconnected is dropped; the next `state` catches the device
up. An agent can't launch the app with Bluetooth, so the whole
hook-to-screen path is tested over USB ([VERIFICATION.md](VERIFICATION.md)
L4).

### 3.8 Runtime: queues, threads and timers

All of Boop's state lives on one serial queue, `home`. Everything else
hops onto it.

| Where | What runs there |
| --- | --- |
| `home` queue | The adapter, the core, the harness's bookkeeping, the actions, the moment schedule, the device link and the memory store |
| `boop.hook-server` thread | Accepting hook connections; each line goes to `home` with the time it arrived |
| `boop.ble` queue or `boop.usb-link` thread | The transport; lines and connection changes go to `home` |
| A Swift task | Jev's request; the answers go back to `home` |
| A global queue | Reading Jev's key, since the Keychain may stop to ask; the brain is set on `home` |
| Main thread | The menu bar and popover; the runtime pushes a status (name, snapshot, sessions, link, personality, brain) after every change |

| Timer | On | Does |
| --- | --- | --- |
| Tick, every 1 s | `home` | Reports the wall clock, runs the core's timers, sends the 10 s keepalive, gives up on a brain moment whose `ended` hasn't come in time ([harness/DECISIONS.md](harness/DECISIONS.md) §5), and ends any action left in progress too long ([harness/HARNESS.md](harness/HARNESS.md) §5.1) |
| Moment pump | `home` | Plays the next brain moment when its turn comes |

At start the runtime takes the lock, reads the memory files (it won't run
before setup), settings and mood, builds the core, Voice, the actions and
the harness, then opens the socket, starts the link and the tick, and
reads Jev's key. Until the key is read, no event wakes the brain. The app
opts out of App Nap (without keeping the Mac awake), so the keepalive
isn't held back until the device thinks the app is gone.

The menu-bar app and `Boop --headless` run the same runtime; the evals
run the core and the harness with the same state parts. Headless has no
UI or Bluetooth, reads Jev's key only from `BOOP_JEV_KEY`, takes dev
lines on its socket, and can move its clock forward for tests
([VERIFICATION.md](VERIFICATION.md) §2, L4).

## 4. Memory and the state directory

Boop's memory is two Markdown files in the state directory (§4.4):
`long-term.md`, who this Boop is, and `short-term.md`, which day Boop last
saw. Jev's state doesn't include them, and nothing records what Boop
learns about you ([FUTURE.md](FUTURE.md)). Files from before 2026-09-27
have more sections; they still load, and the store leaves them be.

**A new day** starts at the day's first hook or tap, by the Mac's local
calendar. The memory store snapshots both files to `history/<date>/`,
where `<date>` is the day before, and writes the new date to
`short-term.md`. Setup also snapshots, under the day Boop hatched.

**Hand edits** are welcome: the store reads a file again whenever it has
changed on disk, so an edit isn't overwritten. A file that won't parse is
copied to `<file>.broken`. `long-term.md` is then restored from its
newest snapshot that reads, or else from the copy the store last read.
`short-term.md` snapshots are always of an earlier day, so it keeps just
the file's date if one can be found, so the day doesn't start twice, and
otherwise starts fresh.

### 4.1 The steering files

Boop's AGENTS.md: the guide that opens Jev's state, each personality
(with its settings for the core's rules) and each mood
([harness/DECISIONS.md](harness/DECISIONS.md) §2). Nothing changes them at
runtime, because different steering makes a different creature.
`plan/steering/` is the single source; the app bundles a copy in
`app/Boop/Resources/steering/`, and a test checks the two match.

### 4.2 `long-term.md`

From the memory tests (`MemoryTests.sample`):

```markdown
## Boop
name: Pip · hatched: 2026-10-02 · nature: cheeky · seed: 7f3a
```

The app writes it at setup and never changes it. The name is 1–23
characters without `·` or `:`; `nature` is the person's one answer (sweet
or cheeky), kept and not yet used; `seed` is random, 1 to `ffff` in hex,
and picks Boop's voice dialect. It lives only on the Mac, so reflashing or
replacing the device doesn't change it, and the app has no reset button.

### 4.3 `short-term.md`

From the memory tests (`testANewDaySnapshotsAndStartsFresh`):

```markdown
## Today
2026-10-15
```

The core's new day writes it: the date alone. It's how a restart knows
the day has already started. Anything after the date on the Today line,
like the `first seen` time older files have, is ignored.

### 4.4 State directory

Everything a Boop keeps on the Mac lives in one folder,
`~/Library/Application Support/Boop`. `Boop --state-dir DIR` points the app
elsewhere, and headless runs and tests always do, so they never touch the
everyday Boop.

| Path | What it is | Written |
| --- | --- | --- |
| `long-term.md` | Who this Boop is (§4.2) | At setup |
| `short-term.md` | Today's date (§4.3) | At each new day |
| `history/<date>/long-term.md`, `short-term.md` | Both memory files as they were at the end of that day, or at setup | At setup and each new day |
| `<file>.broken` | The last memory file that wouldn't parse, kept for you to look at | When one doesn't parse |
| `settings.json` | The personality and the volume (0–10), `boop` and 6 while it's missing. Keys it doesn't know, from older versions, are ignored, and an unknown personality reads as `boop` | When you change either in Settings |
| `mood` | Boop's mood, one word and a newline; missing or unknown reads as `happy` ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3) | By the `mood` action, on a change |
| `boop.sock` | The hook socket, mode 0600 ([ADAPTERS.md](ADAPTERS.md) §2). Headless can put it elsewhere with `--socket` | Replaced at launch, removed at quit |
| `boop.lock` | Locked while an app runs on this folder; a second copy refuses to start. The file stays, the lock goes with the process | At launch |
| `boop.log` | The app's log, appended: startup, hook placement and repairs, the link connecting and dropping, the device's id and firmware, taps, memory recoveries, dropped brain moments, one `brain …` line per pass, and hooks only when armed or in debug mode. Never Jev's state ([harness/HARNESS.md](harness/HARNESS.md) §9) | Always |
| `debug.jsonl` | Debug mode only: a `questions` line first, then every transcript entry, every line sent to the device and each status change, as JSON lines ([harness/HARNESS.md](harness/HARNESS.md) §9, [DASHBOARD.md](DASHBOARD.md) §3) | Emptied at each launch with `--debug`, after a copy of the last launch's goes to `debug.1.jsonl` |
| `debug.<n>.jsonl` | Earlier launches' `debug.jsonl`, `debug.1.jsonl` the latest, as many as [harness/HARNESS.md](harness/HARNESS.md) §9 keeps | At each launch with `--debug`; the oldest is let go |
| `doctor-armed` | While it's under 10 minutes old, the app logs every hook ([ADAPTERS.md](ADAPTERS.md) §6) | By the `doctor` skill; the app removes an older one |
| `bin/boop-hook` | The copy of the hook client every hook entry calls ([ADAPTERS.md](ADAPTERS.md) §5) | By the everyday menu-bar app, at launch, when it differs |

Outside the folder, Jev's key is in the login Keychain (service
`com.boopcomputer.boop`, account `jev`), read and written through
`/usr/bin/security`; `BOOP_JEV_KEY` wins over it
([harness/HARNESS.md](harness/HARNESS.md) §7). The hooks are in
`~/.claude/settings.json`, `~/.codex/hooks.json` and
`~/.codex/config.toml` ([ADAPTERS.md](ADAPTERS.md) §5).

## 5. Data flow

What crosses each boundary, in the order an event travels:

| From → to | What | Type | Spec |
| --- | --- | --- | --- |
| Agent → `boop-hook` | The hook's JSON on stdin | The agent's own | [ADAPTERS.md](ADAPTERS.md) §2 |
| `boop-hook` → hook server | One JSON line of the kept fields | `HookLine` | [ADAPTERS.md](ADAPTERS.md) §2 |
| Adapter → core | The common event | `BoopEvent` | [ADAPTERS.md](ADAPTERS.md) §1 |
| Device link → core | A tap | `Core.DeviceInput` | [PROTOCOL.md](PROTOCOL.md) §4 |
| Device link → runtime | How a brain moment ended, by its `id` | `MomentEnded` | [PROTOCOL.md](PROTOCOL.md) §4 |
| Core → runtime | Effects | `CoreEffect` | §3.2 |
| Core → harness | An event: its line, the rule reaction, whether it wakes the brain, what it's about, and facts the harness never reads | `Event` | [harness/EVENTS.md](harness/EVENTS.md) |
| Harness → Jev | The state as text, and every action's questions | One HTTPS request | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| Jev → actions | Each question's choice and probabilities, only to the action that asked | `Answers` | [harness/HARNESS.md](harness/HARNESS.md) §4 |
| Actions → harness | `(ok, message)`; a successful message goes into HISTORY. A started one also hands over a handle, and its end comes later | `ActionResult`, `Pending` | [harness/HARNESS.md](harness/HARNESS.md) §4 |
| `react` → moment schedule → device link | A mumble and its face (`mood`) with its `loops`, and its handle, which the schedule or the runtime ends; it goes out with an `id` | `DeviceMoment`, `Pending` | [harness/DECISIONS.md](harness/DECISIONS.md) §5 |
| `mood` → mood store → core | The new mood | A word | [harness/DECISIONS.md](harness/DECISIONS.md) §4 |
| Device link ↔ device | `state` and `moment` out; `input`, `ended` and `status` in | JSON lines | [PROTOCOL.md](PROTOCOL.md) |
| Runtime → Mac app | Name, snapshot, sessions, link, device, personality, brain | `Runtime.Status` | [UX.md](UX.md) §6 |

## 6. Who keeps which state

| State | Kept by | Where | After a restart |
| --- | --- | --- | --- |
| Sessions and their turns ([ADAPTERS.md](ADAPTERS.md) §4) | Core | Memory | Gone: each comes back with its next hook, and Boop sleeps until then |
| Poke streak, heartbeat count, chatter's next time | Core | Memory | Start again |
| The last active day | Core, from `short-term.md` | Disk | Kept, so a restart doesn't start the day twice |
| Transcript, the pass running and the one waiting | Harness | Memory, and `debug.jsonl` in debug mode | Gone |
| Brain moments waiting with their handles, when the device is free, and the look and mood of the last `state`, which time a moment's loops | Moment schedule | Memory | Gone |
| Brain moments on the device, by `id`, with their handles and when to give up waiting for their `ended` | Runtime | Memory | Gone |
| The latest snapshot, the device's status, whether it's connected | Device link | Memory | Rebuilt at start |
| Project and workspace by folder (up to 512) | Adapter | Memory | Read again |
| Name, hatch day, nature, voice seed | Memory store | `long-term.md` | Kept |
| Mood | Mood store | `mood` | Kept |
| Volume, personality | Runtime | `settings.json` | Kept |
| Jev's key | The Keychain | Login Keychain | Kept |
| Touch calibration | Device | Its flash ([DEVICE.md](DEVICE.md) §5) | Kept |

## 7. Device

The device is a thin client. It draws what the latest `state` says, plays
moments, runs its own short timers (blinks, the needs-you chirp, the
no-app look after 30 s without a `state`), reports taps and says how
each brain reaction ended. It keeps no
personality or memory, only its touch calibration. What it does is in
[BEHAVIORS.md](BEHAVIORS.md); the hardware and firmware are in
[DEVICE.md](DEVICE.md).

## 8. When things go wrong

| Failure | What happens |
| --- | --- |
| App not running, or the Mac asleep | Hooks give up within 50 ms and agents carry on. The device shows it has no app after 30 s ([BEHAVIORS.md](BEHAVIORS.md) §3.4) |
| App restarted | Sessions are gone until their next hook; the mood, settings and memory stay (§6) |
| Device disconnected | The app keeps going and drops what it would send; on reconnect the latest `state` catches the device up. HISTORY says a reaction playing or sent meanwhile didn't happen ([harness/DECISIONS.md](harness/DECISIONS.md) §5) |
| Jev slow, offline or wrong | Rules still drive every reaction. A pass Jev fails, is late for, or answers off its options is dropped, and no action runs ([harness/HARNESS.md](harness/HARNESS.md) §7) |
| No Jev key | No pass runs; events are still recorded |
| A memory file won't parse | It's kept as `.broken` and recovered (§4) |
| A second copy of Boop on the same state directory | It refuses to start (`boop.lock`), and the popover says another copy is running |
| The hook socket can't open | The popover says Boop can't listen for hooks. Headless refuses a socket path over 103 bytes before starting |
| `bin/boop-hook` missing, or an agent's settings file unreadable | Nothing is installed or repaired, and Settings says why ([ADAPTERS.md](ADAPTERS.md) §5) |
| The bundled steering folder missing or broken | The app exits with a message before the runtime starts |
| The Keychain asks for access | Only the key's reader waits; hooks, ticks and the device carry on |
| The Mac's clock changes | Timers don't; days and times of day follow it |

## 9. Budgets

| Path | Target |
| --- | --- |
| Agent event → pixel | < 200 ms p95 |
| Tap → visible feedback | < 20 ms, on the device |
| Hook overhead | Single-digit ms. Connecting and writing share 50 ms, then the hook gives up; it exits within 1 s whatever happens. It reads at most 256 KB and keeps fields of at most 200 characters |
| Hook entry timeout | 5 s in the agent's settings; never reached |
| Hook server | A connection is read until it closes, is quiet for 200 ms, or reaches 64 KB |
| Brain, per pass | Jev's answer within 1.25 s, one retry included ([harness/HARNESS.md](harness/HARNESS.md) §7). A late answer is dropped |
| A brain moment's wait | 5 s, then it's dropped |
| An action | Logged if it takes over 300 ms |
| `state` keepalive | Every 10 s; the device gives up on the app after 30 s |
| Protocol line | At most 512 bytes, names at most 23 bytes ([PROTOCOL.md](PROTOCOL.md) §2–3) |

## 10. Stack

- **Mac app:** Swift, built with SwiftPM from the repo root's
  `Package.swift` (sources in `app/`), using CoreBluetooth and TypeSafe's
  API for Jev when the person has a key. SwiftPM builds no app bundle
  here, so the app's `Info.plist` (the Bluetooth usage description,
  `LSUIElement`) is linked into the `Boop` binary with `-sectcreate`.
- **Firmware:** PlatformIO + Arduino core + LovyanGFX + NimBLE-Arduino in
  `firmware/` ([DEVICE.md](DEVICE.md) §4), to be ported to ESP-IDF + LVGL
  once v1 is verified ([PLAN.md](PLAN.md) §4).
- **Dev tools:** `internal/tools/boopctl` for the device and `boopdev` for
  the app ([VERIFICATION.md](VERIFICATION.md) §2).

What ships is in `app/` and `firmware/`; everything else (tests, evals,
dev tools, skills, the firmware's simulator and unit tests) is in
`internal/` ([its README](../internal/README.md)). The Swift targets:

| Target | Kind | Sources | Ships |
| --- | --- | --- | --- |
| `HookWire` | Library | `app/HookWire/` | Yes |
| `BoopKit` | Library, on `HookWire` | `app/BoopKit/` | Yes |
| `Boop` | The app | `app/Boop/`, plus `internal/app/Boop/` for `--headless` and `--snapshots` | Yes |
| `BoopHook` (`boop-hook`) | The hook client, on `HookWire` | `app/BoopHook/` | Yes |
| `BoopDevKit` | Library: the evals and hook replay | `internal/app/BoopDevKit/` | No |
| `BoopDev` (`boopdev`) | The developer CLI | `internal/app/BoopDev/` | No |
| `BoopTests` | The unit tests; without Xcode, an executable on the `XCTest` shim target | `internal/app/Tests/` | No |

The production targets never depend on internal ones. The build makes an
import of a target that isn't a declared dependency an error (SwiftPM's
own default is a warning), so a production file can't reach internal
code. `Package.swift` is at the repo root because SwiftPM takes no target
outside the package's root.

The stable contracts are the common event ([ADAPTERS.md](ADAPTERS.md) §1),
the memory files (§4), the harness's two contracts, events in and actions
out ([harness/HARNESS.md](harness/HARNESS.md) §3–4), and the protocol
([PROTOCOL.md](PROTOCOL.md)).

## 11. Decision log

When a change departs from the spec, change the spec first and add a row
here saying why. This table keeps only the decisions still in force, one
line each, oldest first. When a decision is replaced, its row moves to the
"Superseded later" section of
[archived/plan-v1-build/decisions.md](../archived/plan-v1-build/decisions.md),
which also has the full log up to 2026-09-27.

| Date | Decision | Why | Where |
| --- | --- | --- | --- |
| 2026-09-25 | The personality is the product; usefulness comes second | It's why people keep Boop | [VISION.md](VISION.md) |
| 2026-09-25 | Boop speaks Minion gibberish with at most one real English word | A creature, not a chatbot; cheap, and needs no translation | [VOICE.md](VOICE.md) |
| 2026-09-25 | Boop only notifies; you approve in the agent, on the Mac | A bug in Boop can never approve anything | [ADAPTERS.md](ADAPTERS.md) §1 |
| 2026-09-25 | Memory is Markdown files on the Mac, open to hand edits, with no reset button; the steering files are read-only | Simple, inspectable, and independent of the device and the model | §4 |
| 2026-09-25 | No code, prompts, file contents or agent transcripts go to the brain | Privacy | [harness/EVENTS.md](harness/EVENTS.md) §9 |
| 2026-09-25 | Our own protocol, the same lines over Bluetooth and USB, with no pairing or encryption yet | Only our app talks to the device, and USB lets agents test the whole path | [PROTOCOL.md](PROTOCOL.md) |
| 2026-09-25 | The firmware starts on Arduino + LovyanGFX and moves to ESP-IDF + LVGL once v1 works; the drawing code stays independent of the display library | Fastest to a working face, and the drawing carries over | [DEVICE.md](DEVICE.md) §4 |
| 2026-09-26 | The renderer uses integer maths only | The board and the simulator draw the same pixels, so screenshots compare exactly | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | The core is a pure state machine that returns effects, driven by one-second ticks | Decisions stay apart from effects, and every rule is testable on a virtual clock | §3.2 |
| 2026-09-26 | One state directory per Boop; hooks call the copy of `boop-hook` kept there, and nothing is installed while it's missing | Hooks survive rebuilding or moving the app; entries calling a missing file dropped every event while Settings said "Connected" | §4.4, [ADAPTERS.md](ADAPTERS.md) §5 |
| 2026-09-26 | v1 is cut to 4 states and 2 animations (`cheer`, `wiggle`); everything else is parked | The surface had outgrown what the owner can hold in their head | [BEHAVIORS.md](BEHAVIORS.md), [FUTURE.md](FUTURE.md) |
| 2026-09-26 | Four hero moments lead Boop's story: a cheer for a finished turn, annoyance at a failed one, sadness when yelled at, grumbling at a poke streak | Each has one clear cause and one clear feeling | [VISION.md](VISION.md) |
| 2026-09-26 | The brain's moments wait their turn behind the rules' and each other's, and are dropped after waiting 5 s | A brain mumble cut off the rules' cheer before it showed | §3.2 |
| 2026-09-26 | Durations and gaps reach the brain named (short, long, very long; right after, a while, a long break) | Keep arithmetic out of the brain: Jev read "took 45 s" as quick | [harness/EVENTS.md](harness/EVENTS.md) §5 |
| 2026-09-26 | Each feeling's and mood's meaning rules out its neighbours | Jev is literal: while "sad" also covered things going badly, a build complaint came out sad | [harness/DECISIONS.md](harness/DECISIONS.md) §3 |
| 2026-09-26 | No cooldowns on the brain's mumbles, apart from the poke streak's once a minute | Fewer rules; Jev chooses silence itself | [harness/EVENTS.md](harness/EVENTS.md) §6 |
| 2026-09-27 | One brain, Jev: one request asks the mood, the reaction and the word as multiple-choice questions over a plain-text state | Boop can only say its recorded words, so the word is a choice too; one request with probabilities replaces two models | [harness/HARNESS.md](harness/HARNESS.md) §1 |
| 2026-09-27 | Five events can wake the brain: turn start, turn end, a notable tool use, a poke streak and an hourly heartbeat | Tool results carry the moments worth a word, and the heartbeat lets a mood go | [harness/EVENTS.md](harness/EVENTS.md) §4 |
| 2026-09-27 | Jev's state is plain text: the guide, PERSONALITY and MOOD from read-only files, then HISTORY and NOW from the transcript, rebuilt every pass | Jev keeps no session; named sections let each question point at what it judges by | [harness/HARNESS.md](harness/HARNESS.md) §6 |
| 2026-09-27 | The harness has two generic contracts: events in, actions out; an action reads its own answers and returns `(ok, message)` | New behaviour is a new action, with no harness change | [harness/HARNESS.md](harness/HARNESS.md) §3–4 |
| 2026-09-27 | A thread is named after its workspace, cleaned to `a-z0-9-` and 40 characters | Two agents in one project need telling apart, and an agent-chosen name mustn't carry words into Jev's state | [ADAPTERS.md](ADAPTERS.md) §3 |
| 2026-09-27 | Personalities replace modes: how much Boop speaks up is its personality file's to say | There's one brain now; a chattier Boop is a different character | [harness/DECISIONS.md](harness/DECISIONS.md) §2.2 |
| 2026-09-27 | Every finished turn cheers, whatever the personality | A setting nobody varies is just a rule | [BEHAVIORS.md](BEHAVIORS.md) §3.1 |
| 2026-09-27 | Seven moods, the mood designs' set, with no minimum time between changes | The device's faces come in these seven, and the steering says when each mood leaves | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3 |
| 2026-09-27 | "Needs you" clears on the asking agent's next event or a turn-level one; the hook line keeps Claude's `agent_id` | Claude gives subagents their parent's session, so a sibling's tool call cleared a request still waiting | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-27 | Without Jev's key, or when Jev fails or is late, Boop does only its rule reactions; the evals fail without the key | Fine for everyday use, and an eval that can't ask Jev can't check it | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-27 | Jev's key is read and written through `/usr/bin/security` | Without an Apple-issued certificate, every rebuild asked for the key again. The cost: any program running as the owner can read it without a prompt | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-27 | One debug mode, `--debug` (`make debug`), in the menu-bar app and headless | Seeing what Boop does took four settings and two terminals | [harness/HARNESS.md](harness/HARNESS.md) §9 |
| 2026-09-27 | A terminal dashboard reads only `debug.jsonl` and drives the app with dev lines on the hook socket, which plain `make run` ignores | Checking a reaction meant waiting for Jev to pick it | [DASHBOARD.md](DASHBOARD.md) |
| 2026-09-27 | The Mac app is one popover in the device's "Warm Terminal" colours; setup and settings open inside it | A setup window was jarring, and gen-2's colours clashed with the device | [UX.md](UX.md) §6 |
| 2026-09-27 | Code that doesn't ship lives in `internal/`, in its own targets, and the build fails on an import that isn't a declared dependency | The compiler keeps production code from reaching test or dev code | §10 |
| 2026-09-27 | Every `state` carries the mood; a missing or unknown one reads as happy | A lost update fixes itself with the next `state` | [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-27 | The device draws the mood designs exactly, from `facegen`'s rectangles on whole pixels | The designs are the look, exact pixels can be checked, and a revised design is a rerun | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-27 | The face switches designs behind a 150 ms blink, and who needs you shows in the strip | Whole-pixel designs can't be eased into one another, and a blink reads as Boop's own | [UX.md](UX.md) §2–3 |
| 2026-09-27 | The wire carries only what's read; `state`'s `idle` and `wait` stay only for the dashboard | No device or tool read the dropped fields, and a resent `state` needn't be rebuilt | [PROTOCOL.md](PROTOCOL.md) §3–4 |
| 2026-09-27 | A reaction is a mood's face: `react` picks `none` or one of the seven moods (`annoyed` became `grumpy`), and its moment's `mood` draws the look in that mood's design while the mumble plays, then the mood comes back. The sound follows the face, with a temporary default voice for a mood that has none | The designs are what Boop's feelings look like; a reaction that only changed the gibberish's sound never showed on the face. The mood stays the backdrop, the reaction the moment | [harness/DECISIONS.md](harness/DECISIONS.md) §3, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-27 | A brain reaction waits only for a line playing, not for an animation: it plays over the cheer, which it doesn't cut. This replaces 2026-09-26's "wait behind the rules' moments" for animations | A mumble with no animation can't cut the cheer on the device, and a proud reaction to a long finish should show the cheer in proud's face, not the idle face after it | §3.2 |
| 2026-09-27 | An action can report that it started something rather than did it: HISTORY shows its line `(in progress)` until it reports `done`, or `failed` with why (`(didn't happen: …)`), as a `settle` entry; the harness ends any left open too long | HISTORY said Boop made a face that was still waiting its turn, or that the moment schedule had dropped and never showed. Only the action knows when its effect ends, so the harness only waits, with a ceiling in case it never hears | [harness/HARNESS.md](harness/HARNESS.md) §4–5 |
| 2026-09-27 | `react` is started, not done: its moment's handle ends when the device says how the moment ended, or `failed` when it was dropped, no device was connected or the device dropped. This replaces "HISTORY still says Boop made it" for a dropped reaction. The guide lets Jev make one that didn't happen again, but not repeat one in progress | Jev read reactions that never showed as made, and wouldn't retry them | [harness/DECISIONS.md](harness/DECISIONS.md) §5 |
| 2026-09-27 | A `moment` the Mac waits on carries an `id`, and the device answers it with `ended`: `done`, `cut` (and what cut it) or `skipped`. The Mac gives up on one that doesn't come by the moment's length plus a grace. This replaces the app's own timing, which ended a reaction `done` when it expected the moment to have played. No other moment is answered | Only the device knows whether a tap, "needs you" or a newer moment stopped a reaction, or whether it played at all. The grace keeps older firmware and a lost line from leaving a reaction in progress | [PROTOCOL.md](PROTOCOL.md) §4 |
| 2026-09-28 | Moments are counted in loops of a design, and whoever plays one says how many (`moment.loops`, 1–6). The cheer plays enough loops of the mood's task-complete design to last at least 2 s, replacing the fixed 2 s; a reaction's face holds the loops Jev picks (`react.loops`, once to four times), ending on a loop boundary of the design showing, and at least as long as its mumble. facegen reads each design's loop from its SVG timing and writes it for the device and the Mac alike | Every animation can loop, and the loopable designs coming next should end where they start rather than be cut mid-motion. A bigger moment can hold its face longer. One set of numbers keeps the Mac's timing of a moment with the device's | [PROTOCOL.md](PROTOCOL.md) §3, [harness/DECISIONS.md](harness/DECISIONS.md) §5 |
| 2026-09-28 | `state` drops `idle` and `wait`, replacing 2026-09-27's keeping them for the dashboard, which now counts the idle from its `status` line's sessions and the waiting from `attn`. A change to the session list the snapshot doesn't show is the core's `sessions` effect | Nothing read them but the dashboard, and `wait` was always 1 + `attn.more`. The idle count had quietly been what refreshed the popover when a second idle session came or went | [PROTOCOL.md](PROTOCOL.md) §3, [DASHBOARD.md](DASHBOARD.md) §2 |
| 2026-09-28 | Claude's idle notice (`idle_prompt`) clears a request whoever asked, a subagent included. This replaces "a subagent's request stays, since its prompt may still be up" | The notice means Claude sits at its own prompt with the turn over, which it doesn't do while any prompt is up. Keeping a subagent's request, which the notice also restarted the safety net for, left Boop amber about 11 minutes after you pressed Esc on a subagent's prompt, where BEHAVIORS.md §3.2 says a minute | [ADAPTERS.md](ADAPTERS.md) §4 |
