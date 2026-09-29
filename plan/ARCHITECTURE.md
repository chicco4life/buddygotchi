# Boop: architecture

Updated 2026-09-29. The parts of Boop, how they connect, what each one
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
│ Hook server ─► Adapter ─► Pipeline ◄─────────── poke ◄─────────┐    │
│                             │ Transcript (raw events, on disk) │    │
│                  ┌──────────┴───────────┐                      │    │
│                  ▼                      ▼                      │    │
│  Core: sessions, rules, 1 s tick   View: view events           │    │
│     │              │                    │ that wake the brain  │    │
│     ▼              ▼                    ▼                      │    │
│   state         new day ─► Memory    Harness ◄──► Jev          │    │
│     │                                   │ answers              │    │
│     │                                   ▼                      │    │
│     │                                Actions ─ mood ─► Core    │    │
│     │                                   │                      │    │
│     │                                 react ─► Voice ─► Moment │    │
│     │                                                schedule  │    │
│     ▼                                                   ▼      │    │
│   Device link (Bluetooth, or USB through `boopctl bridge`) ────┘    │
└────────────────────────┬──────────────────────────▲─────────────────┘
                         │ state, moment            │ input, status, ended
                         ▼                          │
             Device: draws, plays, blinks, alerts, reports taps
```

**Following one event:**

1. Codex finishes a task. Its hook runs `boop-hook codex`, which sends one
   line to the app and exits at once.
2. The Codex **adapter** turns it into a raw event, a `turn` end from
   `Stop` in session a1b2 with its working directory and Codex's last
   message, and the **transcript** records it.
3. The **core** marks the session idle, so the device drops the working
   look well under a second after the hook. No rule celebrates a finish:
   that's the brain's call.
4. The **view** folds the event in: it knew the turn's start and its
   calls, so it makes a view event with its line, `codex finished turn 3
   on "landing": done, a very long turn, 40 tool calls.`, and the last
   message as a note. It wakes the brain, so the **harness** asks
   **Jev** every action's questions about it in one request, and Jev answers, say,
   `react.mood: proud`, `react.animation: success`, `react.loops: twice`,
   `say.feeling: glad`, `say.about: done` and `say.kind: phrase`.
5. The **`react` action** asks **Voice** for a line: a glad phrase in
   proud's mood, fit for a success (*"Nailed it"*), which plays alone,
   as a phrase does; and queues it as the
   finish, a success, in proud's face, held twice. No line is playing, so
   the **device link** sends it at once, and the device plays proud's
   task_complete scene for a success and says the take at its voice
   window. When the face and the take are over, the device says so
   (`ended`), and HISTORY stops showing the reaction as in progress.

Rules keep the screen true at once: the look (working, idle, asleep),
"needs you" and the tap's poke never wait for the brain. Everything
expressive is the brain's, a second or so later: the mood, and every
reaction, a finished turn's included. If the brain is slow, offline or
missing, Boop still shows what its agents are doing and when you're
needed, but it doesn't celebrate or react (decision log, 2026-09-28).

## 2. Three loops at three speeds

| Loop | Runs on | Speed | Does | Never does |
| --- | --- | --- | --- | --- |
| Reflex | Device | < 20 ms | Tap feedback, blinks, playing moments, the needs-you alert and light | Wait for the Mac |
| Reactive | Core → device link | < 200 ms p95 | Hook → rule → `state` or moment | Wait for the brain |
| Deliberative | Harness + Jev → actions | A pass has 1.5 s; its reaction then waits up to 5 s for its turn | A change of mood, every reaction (a face and what Boop says), a finished turn's included | Block the reactive loop |

## 3. Components and boundaries

Each part has one job and knows as little as possible about the others.
The core and the brain decide *what* should happen, and actions make it
happen. Nothing that decides ever picks a recording, touches a file or
talks to the device.

| Part | Code | Does | Doesn't know about |
| --- | --- | --- | --- |
| Hook client | `app/BoopHook/`, `app/HookWire/` | Turns a hook's JSON into one hook line on the socket and exits 0 | Anything past the socket |
| Hook server | `Adapters/HookServer.swift` | Accepts hook lines on `boop.sock` and hands them to the runtime; never replies | What they mean |
| Adapter | `Adapters/Adapter.swift` | Turns a hook line into a raw event: the agent's mapping to a type and phase, and the error class | Boop's state, the brain, the device |
| Transcript | `Harness/Transcript.swift` | Every raw event, in order, one file a day, read back at launch | What any of it means |
| Pipeline | `App/Pipeline.swift` | Records each input, hands it to the core and the view, records what the core did, and gates the view events | Any rule |
| Core | `Core/Core.swift`, `Core/Activity.swift` | Keeps the session table and each session's running calls; decides what the device shows, what the agents are doing included, and the rules' one-shots, and records its rule actions (the wiggle, "needs you") | Minion speech, models, hook formats, files, the brain |
| View | `Core/TranscriptView.swift` | Folds the transcript into view events, with their lines: turns, checks, pokes, what you said, heartbeats, who needs you, what Boop did | The device, what an action does |
| Harness | `Harness/` | For each view event that wakes the brain, builds the state, asks every action's questions in one request, hands each action its answers and records what it did | What Boop says, the device, a view event's facts, what an action does |
| Brain | `Brains/JevBrain.swift` | Jev: answers multiple-choice questions about a plain-text state, with probabilities | Everything else |
| Actions | `Actions/` | `mood` and `react`: carry out one call each, checking their own rules | Whether a rule or the brain called them |
| Moment schedule | `App/MomentSchedule.swift` | Decides when each brain moment plays: after any line playing, over an animation, or not at all | What's in it |
| Voice | `Voice/` | Turns a feeling, a topic, a kind and a face into a line of up to two of the recorded takes the board has, or none | Who asked, or why |
| Memory store | `Memory/` | Reads and writes `long-term.md`, `short-term.md` and their snapshots | Models, the device |
| Mood store | `MoodStore` in `Actions/MoodAction.swift` | Reads and writes the `mood` file | Who changes it |
| Device link | `DeviceLink/` | Sends `state` and moments, receives taps and status, over Bluetooth or USB | What any of it means |
| Hook installer | `Install/` | Adds, repairs and removes Boop's entries in the agents' settings | Anything at runtime |
| Runtime | `App/Runtime.swift` | Wires the parts together, owns the queue and the timers, and carries out the core's effects | Any rule |
| Mac app | `app/Boop/` | The menu-bar icon and popover, setup and settings; places `boop-hook` and repairs hooks at launch | Any rule |

`BoopKit` paths are under `app/BoopKit/`.

### 3.1 Adapters

Each adapter turns one agent's hook calls into raw events. Hooks only
report, so the agent carries on as normal ([ADAPTERS.md](ADAPTERS.md)).

### 3.2 Core

The core is plain rules in a pure state machine. Every input goes in with
the time, and effects come out; the runtime hands each effect to the part
that carries it out. So every rule and timing is testable on a virtual
clock.

| Input | From | Effects it can return |
| --- | --- | --- |
| `handle(event)` | A hook's raw event, once recorded | `state` or `sessions`, a `needs_you` action, a rule's one-shot `moment`, a new day |
| `input(tap, seq:)` | The device's poke, once recorded | `state`, the `wiggle` action, a new day |
| `input(talkOn)`, `input(talkOff)`, `listen(on)`, `linkDown` | BOOT held and let go, the popover's Talk button, the link dropping | `listen` (the mic on or off, and whose button); the runtime turns the mic on, tells the device to show `listening` for Talk, and ends it when no reply is coming ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |
| `tick(at:)` | The runtime, once a second | `state` or `sessions` (an activity's hold running out, or a call gone quiet, included), a Codex request showing after its grace, a request the safety net clears (their `needs_you` actions), the mic off at 30 s |
| `setVolume`, `setMood` | Settings; the mood action | `state` |
| `setWallClock` | Every tick | None: it changes later decisions |

| Effect | Carried out by |
| --- | --- |
| `state(snapshot)`, only when something on it changed | The device link, and the menu bar's status |
| `sessions`, when the session list changed and the snapshot didn't | The menu bar's status, and `debug.jsonl`'s `status` line |
| `record(Event)`: what the rules did, as an `action` | The transcript, right after the event that caused it, and so the view ([harness/EVENTS.md](harness/EVENTS.md) §2) |
| `moment(DeviceMoment)`: a rule's one-shot (`starting`, `stopped`, `error`, `helper_return`, [BEHAVIORS.md](BEHAVIORS.md) §3.1), after the `state` of the same input | The device link, unless a brain moment's line plays (Moments, below) |
| `newDay(date)`: the first hook or tap of a new local day | The memory store (§4) |

**What the core keeps:** the sessions ([ADAPTERS.md](ADAPTERS.md) §4 has
their states), each with its running calls, the helpers it saw start,
its plan mode and its activity held; the sessions "needs you" showed for
when last published, the visual showing, the activity showing and since
when, the variation each visual and one-shot showed last, when the
error one-shot last played, the last active day, and its config:
volume, mood and every timing below. What
the brain hears (turn numbers, lengths, checks, pokes, heartbeats) is the
view's ([harness/EVENTS.md](harness/EVENTS.md) §3–4).

**Its timers**, all in `Core.Config` and run by the tick:

| Timer | Value | Spec |
| --- | --- | --- |
| Codex grace before "needs you" shows | 2 s | [ADAPTERS.md](ADAPTERS.md) §4 |
| Safety net: a request clears after no events | 10 min | [ADAPTERS.md](ADAPTERS.md) §4 |
| A working session counts as idle after no events | 1 h | [ADAPTERS.md](ADAPTERS.md) §4 |
| A session is forgotten after no events | 24 h | [ADAPTERS.md](ADAPTERS.md) §4 |
| Push-to-talk: the mic is on at most | 30 s (`Core.listenLimitMs`) | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| `listening` waits for the reply after the mic is off | 8 s (`Core.replyWaitMs`, the device's own too) | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| An activity shows at least | 1.5 s (`Core.actHoldMs`) | [BEHAVIORS.md](BEHAVIORS.md) §2 |
| A call with nothing heard from its session shows waiting after | 20 s (`Core.waitingMs`) | [BEHAVIORS.md](BEHAVIORS.md) §2 |
| The error one-shot plays at most once in | 30 s (`Core.errorEveryMs`) | [BEHAVIORS.md](BEHAVIORS.md) §3.1 |


The view's, in `TranscriptView.Config`, which the tick asks it about:

| Timer | Value | Spec |
| --- | --- | --- |
| Pokes in a row: each within | 3 s | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| Working heartbeat, after no reaction from Boop | The personality's range (90–180 s for `boop`) | [BEHAVIORS.md](BEHAVIORS.md) §2, §6 |
| Heartbeat while nothing works | Every hour with no agent event or poke | [harness/EVENTS.md](harness/EVENTS.md) §4 |

**The snapshot** is derived, never stored: `asleep` with no sessions,
`working` while any works, `idle` otherwise; what the agents are doing
while working, as the core holds it; the mood; the session that has
needed you longest, with how many more do; how many work; the volume
([PROTOCOL.md](PROTOCOL.md) §3). The popover's session list is
derived the same way, and can change while the snapshot doesn't, as
when a second idle session starts. Each row names the project and,
small beside it, the thread: its name as its agent's app shows it, else
its workspace (a linked worktree's folder, else the branch), so several
sessions in one repo tell apart.

**Clocks.** Timers run on a steady clock that never steps and keeps
counting while the Mac sleeps, so setting the Mac's clock back can't
stall one. Days and times of day follow the wall clock, which the runtime
reports every tick. Every event's `ts` is the steady clock's, which
starts at the wall clock's time, so it reads as unix milliseconds. A
turn's length is the time between its start and its end in the
transcript, the time the Mac slept included: a lid closed overnight
between a turn's two minutes makes it a very long one.

**Moments.** A tap's poke, which the device plays on its own, plays at
once, replacing the animation playing but not a brain reaction's line or
face, which play on over it ([BEHAVIORS.md](BEHAVIORS.md) §3.3).
A rule's one-shot plays at once too, which the runtime sends right after the
`state` of the same input, except while a brain moment's line plays,
which it would cut: then it's dropped (`MomentSchedule.rulePlays`), since
a late one-shot is worse than none. A face held on after its line may be
replaced, which the device counts as done. A brain moment plays over a
rule's one-shot as over a poke, without waiting for it.
The brain's moments wait in the
moment schedule, one at a time, until no line or reaction's face plays,
except that a reaction's face held on for its loops after its take
holds up the brain's next only until that take has played, or for one
that said nothing until its face has shown for 1.2 s (with the
link's 0.5 s, below): the next goes then and replaces the face, which the
device counts as done ([PROTOCOL.md](PROTOCOL.md) §4). One with no
animation plays over a poke without cutting it, and a poke doesn't stop
a line, so one waiting behind a line still waits for it. One that has waited longer
than 5 s for its turn is dropped, since a late reaction is worse than
none: at once if it's still waiting then, whether or not a face still
holds the turn, and otherwise when its turn comes. The wait is counted
to when the turn came, so a pump that runs up to 1 s late
(`MomentSchedule.lateMs`) doesn't drop it. The schedule is asked again
when the first waiting one's 5 s run out, and on every tick, so a clock
jump can't leave one waiting for the harness's ceiling. Each carries its
reaction's handle. It goes to the device with an `id`, and the device's
`ended` says how it went: played out, cut short or skipped
([PROTOCOL.md](PROTOCOL.md) §4). The schedule or the runtime ends the
handle from that, or when the moment can't have played
([harness/DECISIONS.md](harness/DECISIONS.md) §5).

The app reckons how long each moment plays at most, as the device times
it: a tap's poke, the mood's poked design or, from the third tap in a
row, tap_spam's (`MomentSchedule` counts taps as the device does,
[BEHAVIORS.md](BEHAVIORS.md) §3.3), its longest variation; or a
reaction's loops of its design (the animation's when it has one, the
longest of the variations the device may play for its facts, else the
look's), and the take's length, then 1.2 s to read the bubble, when
that's longer; a take
that comes with an animation counts from the design's voice window
(`FaceLoops.voiceMs`, [VOICE.md](VOICE.md) §9). The look is the last `state`'s, drawn in the
reaction's mood; while an agent works it's what the agents are doing
(`act`), else the base. Its loop is `FaceLoops`' number for it, the one the device has
([PROTOCOL.md](PROTOCOL.md) §3), for the look's longest variation,
since the device's variations take turns without telling the app
([BEHAVIORS.md](BEHAVIORS.md) §2). The device ends a face on a loop
boundary of its own clock, which the app doesn't know, so the face may
end up to a loop sooner than the app reckons, never later. So a brain
moment on the device holds the schedule's line until the device's
`ended` for it, and only if that never comes until the app gives up on
it (its reckoning plus `endGraceMs`). The
brain's next moment waits only until its take has played, or a silent
face has shown for 1.2 s (`MomentSchedule.brainFree`), or its `ended` if that comes first. The schedule also hears what the device does on its own: a tap's
poke replaces the animation playing, "needs you" starting stops everything, and
while something needs you, or `listening` shows, a tap plays nothing
but still counts in the run. A tap leaves a brain moment's line to its `ended`, since the line plays on over the poke. A reaction whose turn comes with no
device connected plays nowhere and holds nothing. But a link that drops
doesn't stop what the device plays (the USB bridge reconnecting, or a
Bluetooth blip), so a moment sent before the drop still holds the line
until its `ended` comes once the link is back, or the app gives up on it.

### 3.3 Harness and brain

The brain is TypeSafe's Jev: it reads a plain-text state and answers
multiple-choice questions with probabilities, all in one request of about
0.2–0.3 s. The harness keeps the transcript, builds the state from it and
the steering files, asks every action's questions, and hands each action
its answers. One pass runs at a time, and a newer event that wakes the
brain replaces one waiting. An action that started something is shown in
progress until it reports how it ended, or the harness gives up waiting.
Without Jev's key no pass runs: Boop shows its looks, "needs you",
its one-shots and pokes, and nothing reacts or speaks
([harness/HARNESS.md](harness/HARNESS.md)).

### 3.4 Actions

Actions are what the brain can make Boop do. Each declares its questions,
reads Jev's answers to them, checks its own rules, and reports
`(ok, message)`, or that it started something whose end it reports
later ([harness/DECISIONS.md](harness/DECISIONS.md)). They run in this
order:

| Action | Effect | Its own rules |
| --- | --- | --- |
| `mood` | Saves the new mood to the `mood` file; the core puts it in the next `state`, and it's the MOOD section of the next pass | Only one of the current mood's moves on the mood graph, and only a change |
| `react` | Queues a moment in the moment schedule: the chosen mood as its face, with the finish Jev judged if NOW is a turn that finished (task_complete for a success or a failure, reply_ready for a reply), held for the loops Jev picked, and the line Voice finds for the feeling, topic and kind Jev picked in that mood, if Jev is sure enough and there are takes. It's started, not done, until the device says how the moment ended | Nothing while something needs you |

No rule makes a moment on the Mac: every face and take comes through them.

### 3.5 Voice

Voice picks what Boop says: of the recorded takes the board has on its
SD card (`Take.all`, which voicegen writes with the pack), one for the
feeling and one for the topic Jev picked, each performed in the face's
mood, fit for the finish, of the kind asked or the nearest, joined into
a line, or none ([VOICE.md](VOICE.md) §4).

### 3.6 Memory store

The memory store is the only code that reads or writes the memory files
and their snapshots (§4), and it writes atomically.

### 3.7 Device link

The device link sends `state` whenever the snapshot changes and again
every 10 s, sends moments, answers each `status` with the latest `state`,
sends it again on reconnect, and hands taps to the pipeline as pokes and
each moment's `ended` to the runtime ([PROTOCOL.md](PROTOCOL.md)). Its transport is Bluetooth for normal use or
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
| `boop.talk` queue | Push-to-talk's mic and speech recognition, in the app (`app/Boop/Talk.swift`); what it heard, or why it couldn't, goes to `home` ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |
| Main thread | The menu bar and popover; the runtime pushes a status (name, snapshot, sessions, link, personality, brain, the mic) after every change |

| Timer | On | Does |
| --- | --- | --- |
| Tick, every 1 s | `home` | Reports the wall clock, runs the core's timers, sends the 10 s keepalive, gives up on a brain moment whose `ended` hasn't come in time ([harness/DECISIONS.md](harness/DECISIONS.md) §5), runs the moment pump, and ends any action left in progress too long ([harness/HARNESS.md](harness/HARNESS.md) §5.1) |
| Moment pump | `home` | Plays the next brain moment when its turn comes, and drops one that has waited too long. Whatever frees the line sooner (a tap, the device's `ended`, "needs you") runs it at once, and so does a disconnect, though a brain moment still holds the line then (§3.2). Its timer has 5 ms of leeway, and counts the Mac's uptime, which stops while it sleeps, so one the clock has passed is replaced rather than waited for |

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
learns about you. Files from before 2026-09-27
have more sections; they still load, and the store leaves them be.

**A new day** starts at the day's first hook or tap, by the Mac's local
calendar. The memory store snapshots both files to `history/<date>/`,
where `<date>` is the date `short-term.md` held, the last day with
activity (after a weekend, Friday's files go under Friday), and writes
the new date to `short-term.md`. Setup also snapshots, under the day
Boop hatched.

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
and seeds the core's and the view's randomness. It lives only on the Mac, so reflashing or
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
| `mood` | Boop's mood, one word and a newline; missing or unknown reads as `calm`, the resting mood, an unknown one logged, and `cheerful` as `happy` ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3) | By the `mood` action, on a change |
| `boop.sock` | The hook socket, mode 0600 ([ADAPTERS.md](ADAPTERS.md) §2). Headless can put it elsewhere with `--socket` | Replaced at launch, removed at quit |
| `boop.lock` | Locked while an app runs on this folder; a second copy refuses to start. The file stays, the lock goes with the process | At launch |
| `boop.log` | The app's log, appended: startup, hook placement and repairs, the link connecting and dropping, the device's id and firmware, taps, memory recoveries, dropped brain moments, one `brain …` line per pass, and hooks only when armed or in debug mode. Never Jev's state ([harness/HARNESS.md](harness/HARNESS.md) §9) | Always |
| `transcript/<date>.jsonl` | Every raw event of that day, one JSON line each ([harness/HARNESS.md](harness/HARNESS.md) §5) | Appended as events happen; a launch deletes files older than 14 days and reads the last 2 back |
| `debug.jsonl` | Debug mode only: a `questions` line first, then every event, view event and pass, every line sent to the device and each status change, as JSON lines ([harness/HARNESS.md](harness/HARNESS.md) §9) | Emptied at each launch with `--debug`, after a copy of the last launch's goes to `debug.1.jsonl` |
| `debug.<n>.jsonl` | Earlier launches' `debug.jsonl`, `debug.1.jsonl` the latest, as many as [harness/HARNESS.md](harness/HARNESS.md) §9 keeps | At each launch with `--debug`; the oldest is let go |
| `bug-reports/<yyyy-MM-dd-HHmmss>/` | A bug report: this launch's debug lines, Jev's states included, the log's end, the settings, the mood and `about.json` ([harness/HARNESS.md](harness/HARNESS.md) §9) | When you press the bug button in the popover |
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
| Adapter → pipeline | A raw event | `Event` | [ADAPTERS.md](ADAPTERS.md) §1, [harness/EVENTS.md](harness/EVENTS.md) §2 |
| Device link → pipeline | A tap, recorded as a poke; BOOT held and let go, to the core | `Core.DeviceInput` | [PROTOCOL.md](PROTOCOL.md) §4 |
| App's mic → pipeline | What push-to-talk heard, recorded as a `talk` | `String` (`Runtime.said`) | [harness/EVENTS.md](harness/EVENTS.md) §2 |
| Pipeline → transcript → core, view | Each raw event, stamped with its `seq` | `Event` | [harness/HARNESS.md](harness/HARNESS.md) §2 |
| Device link → runtime | How a brain moment ended, by its `id` | `MomentEnded` | [PROTOCOL.md](PROTOCOL.md) §4 |
| Core → runtime | Effects | `CoreEffect` | §3.2 |
| View → harness | A view event: its type and phase, line and notes, what Boop did, whether it wakes the brain, what it's about, and facts the harness never reads | `ViewEvent` | [harness/EVENTS.md](harness/EVENTS.md) §3–4 |
| Actions, core → transcript | What Boop did, as an `action` event | `Event` | [harness/EVENTS.md](harness/EVENTS.md) §2 |
| Harness → Jev | The state as text, and every action's questions | One HTTPS request | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| Jev → actions | Each question's choice and probabilities, only to the action that asked | `Answers` | [harness/HARNESS.md](harness/HARNESS.md) §4 |
| Actions → harness | `(ok, message)`; a successful message goes into HISTORY. A started one also hands over a handle, and its end comes later | `ActionResult`, `Pending` | [harness/HARNESS.md](harness/HARNESS.md) §4 |
| `react` → moment schedule → device link | A face (`mood`) with its `loops` and what it says (`say`, one or two takes or nothing), and its handle, which the schedule or the runtime ends; it goes out with an `id` | `DeviceMoment`, `Pending` | [harness/DECISIONS.md](harness/DECISIONS.md) §5 |
| `mood` → mood store → core | The new mood | A word | [harness/DECISIONS.md](harness/DECISIONS.md) §4 |
| Device link ↔ device | `state` and `moment` out; `input`, `ended` and `status` in | JSON lines | [PROTOCOL.md](PROTOCOL.md) |
| Runtime → Mac app | Name, snapshot, sessions, link, device, personality, brain | `Runtime.Status` | `app/Boop/` |

## 6. Who keeps which state

| State | Kept by | Where | After a restart |
| --- | --- | --- | --- |
| Sessions and their turns ([ADAPTERS.md](ADAPTERS.md) §4) | Core | Memory | Gone: each comes back with its next hook, and Boop sleeps until then |
| Turn numbers, failure runs, pokes in a row, the idle heartbeat's count | View | Folded from the transcript | Folded again from the last 2 days' files |
| The working heartbeat's next time | View | Memory | Starts again |
| The last active day | Core, from `short-term.md` | Disk | Kept, so a restart doesn't start the day twice |
| The transcript | Transcript | `transcript/<date>.jsonl`, and `debug.jsonl` in debug mode | Kept 14 days; the last 2 read back |
| The pass running and the one waiting, and started actions still open | Harness | Memory | Gone: an open action is ended as failed at launch |
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
moments, runs its own short timers (blinks, the needs-you alert, the
no-app look after 30 s without a `state`), reports taps and says how
each brain reaction ended. It keeps no
personality or memory, only its touch calibration. What it does is in
[BEHAVIORS.md](BEHAVIORS.md); the hardware and firmware are in
[DEVICE.md](DEVICE.md).

## 8. When things go wrong

| Failure | What happens |
| --- | --- |
| App not running, or the Mac asleep | Hooks give up within 50 ms and agents carry on. The device shows it has no app after 30 s ([BEHAVIORS.md](BEHAVIORS.md) §3.4) |
| App restarted | Sessions are gone until their next hook; the mood, settings and memory stay (§6). A turn that was running goes idle when it finishes, but the brain isn't told of it, since Boop didn't see it start, so nothing celebrates it ([harness/EVENTS.md](harness/EVENTS.md) §7) |
| Device disconnected | The app keeps going and drops what it would send; on reconnect the latest `state` catches the device up. HISTORY says a reaction playing or sent meanwhile didn't happen ([harness/DECISIONS.md](harness/DECISIONS.md) §5), though one that was playing keeps the line until it ends (§3.2), since the device plays on |
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
| Brain, per pass | Jev's answer within 1.5 s, one retry included ([harness/HARNESS.md](harness/HARNESS.md) §7). A late answer is dropped |
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
  once v1 is verified.
- **Dev tools:** `internal/tools/boopctl` for the device and `boopdev` for
  the app ([VERIFICATION.md](VERIFICATION.md) §2).
- **Animation bank:** `internal/boop-design/` holds the SVG and
  procedural-SFX bank the device's designs and sounds are built from, and
  the mood-graph handover ([guide](../internal/boop-design/README.md)).
  No production target imports it: facegen and sfxgen, internal tools,
  build `firmware/assets/` from it ([DEVICE.md](DEVICE.md) §6,
  [VOICE.md](VOICE.md) §10).

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
line each, oldest first. When a decision is replaced, delete its row; git
keeps it. The full log up to 2026-09-27 is
`archived/plan-v1-build/decisions.md` at git tag `archived-final`.

| Date | Decision | Why | Where |
| --- | --- | --- | --- |
| 2026-09-25 | The personality is the product; usefulness comes second | It's why people keep Boop | [VISION.md](VISION.md) |
| 2026-09-25 | Boop speaks Minion gibberish with at most one real English word | A creature, not a chatbot; cheap, and needs no translation | [VOICE.md](VOICE.md) |
| 2026-09-25 | Boop only notifies; you approve in the agent, on the Mac | A bug in Boop can never approve anything | [ADAPTERS.md](ADAPTERS.md) §1 |
| 2026-09-25 | Memory is Markdown files on the Mac, open to hand edits, with no reset button; the steering files are read-only | Simple, inspectable, and independent of the device and the model | §4 |
| 2026-09-25 | Our own protocol, the same lines over Bluetooth and USB, with no pairing or encryption yet | Only our app talks to the device, and USB lets agents test the whole path | [PROTOCOL.md](PROTOCOL.md) |
| 2026-09-25 | The firmware starts on Arduino + LovyanGFX and moves to ESP-IDF + LVGL once v1 works; the drawing code stays independent of the display library | Fastest to a working face, and the drawing carries over | [DEVICE.md](DEVICE.md) §4 |
| 2026-09-26 | The renderer uses integer maths only | The board and the simulator draw the same pixels, so screenshots compare exactly | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | The core is a pure state machine that returns effects, driven by one-second ticks | Decisions stay apart from effects, and every rule is testable on a virtual clock | §3.2 |
| 2026-09-26 | One state directory per Boop; hooks call the copy of `boop-hook` kept there, and nothing is installed while it's missing | Hooks survive rebuilding or moving the app; entries calling a missing file dropped every event while Settings said "Connected" | §4.4, [ADAPTERS.md](ADAPTERS.md) §5 |
| 2026-09-26 | v1 is cut to 4 states and 2 animations (`cheer`, `wiggle`); everything else is parked | The surface had outgrown what the owner can hold in their head | [BEHAVIORS.md](BEHAVIORS.md) |
| 2026-09-26 | Four hero moments lead Boop's story: a cheer for a finished turn, annoyance at a failed one, sadness when yelled at, grumbling at a poke streak | Each has one clear cause and one clear feeling | [VISION.md](VISION.md) |
| 2026-09-26 | The brain's moments wait their turn behind the rules' and each other's, and are dropped after waiting 5 s | A brain mumble cut off the rules' cheer before it showed | §3.2 |
| 2026-09-26 | Durations and gaps reach the brain named (short, long, very long; right after, a while, a long break) | Keep arithmetic out of the brain: Jev read "took 45 s" as quick | [harness/EVENTS.md](harness/EVENTS.md) §5 |
| 2026-09-26 | Each feeling's and mood's meaning rules out its neighbours | Jev is literal: while "sad" also covered things going badly, a build complaint came out sad | [harness/DECISIONS.md](harness/DECISIONS.md) §3 |
| 2026-09-27 | One brain, Jev: one request asks the mood, the reaction and the word as multiple-choice questions over a plain-text state | Boop can only say its recorded words, so the word is a choice too; one request with probabilities replaces two models | [harness/HARNESS.md](harness/HARNESS.md) §1 |
| 2026-09-27 | Jev's state is plain text: the guide, PERSONALITY and MOOD from read-only files, then HISTORY and NOW from the transcript, rebuilt every pass | Jev keeps no session; named sections let each question point at what it judges by | [harness/HARNESS.md](harness/HARNESS.md) §6 |
| 2026-09-27 | The harness has two generic contracts: events in, actions out; an action reads its own answers and returns `(ok, message)` | New behaviour is a new action, with no harness change | [harness/HARNESS.md](harness/HARNESS.md) §3–4 |
| 2026-09-27 | A thread is named after its workspace, cleaned to `a-z0-9-` and 40 characters | Two agents in one project need telling apart, and an agent-chosen name mustn't carry words into Jev's state | [ADAPTERS.md](ADAPTERS.md) §3 |
| 2026-09-27 | Personalities replace modes: how much Boop speaks up is its personality file's to say | There's one brain now; a chattier Boop is a different character | [harness/DECISIONS.md](harness/DECISIONS.md) §2.2 |
| 2026-09-27 | Seven moods, the mood designs' set, with no minimum time between changes | The device's faces come in these seven, and the steering says when each mood leaves | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3 |
| 2026-09-27 | "Needs you" clears on the asking agent's next event or a turn-level one; the hook line keeps Claude's `agent_id` | Claude gives subagents their parent's session, so a sibling's tool call cleared a request still waiting | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-27 | Without Jev's key, or when Jev fails or is late, Boop does only its rule reactions; the evals fail without the key | Fine for everyday use, and an eval that can't ask Jev can't check it | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-27 | Jev's key is read and written through `/usr/bin/security` | Without an Apple-issued certificate, every rebuild asked for the key again. The cost: any program running as the owner can read it without a prompt | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-27 | One debug mode, `--debug` (`make debug`), in the menu-bar app and headless | Seeing what Boop does took four settings and two terminals | [harness/HARNESS.md](harness/HARNESS.md) §9 |
| 2026-09-27 | A terminal dashboard reads only `debug.jsonl` and drives the app with dev lines on the hook socket, which plain `make run` ignores | Checking a reaction meant waiting for Jev to pick it | [harness/HARNESS.md](harness/HARNESS.md) §9 |
| 2026-09-27 | The Mac app is one popover in the device's "Warm Terminal" colours; setup and settings open inside it | A setup window was jarring, and gen-2's colours clashed with the device | `app/Boop/Views/` |
| 2026-09-27 | Code that doesn't ship lives in `internal/`, in its own targets, and the build fails on an import that isn't a declared dependency | The compiler keeps production code from reaching test or dev code | §10 |
| 2026-09-27 | Every `state` carries the mood; a missing or unknown one reads as happy | A lost update fixes itself with the next `state` | [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-27 | The device draws the mood designs exactly, from `facegen`'s rectangles on whole pixels | The designs are the look, exact pixels can be checked, and a revised design is a rerun | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-27 | The face switches designs behind a 150 ms blink, and who needs you shows in the strip | Whole-pixel designs can't be eased into one another, and a blink reads as Boop's own | [BEHAVIORS.md](BEHAVIORS.md) §2 |
| 2026-09-27 | The wire carries only what's read; `state`'s `idle` and `wait` stay only for the dashboard | No device or tool read the dropped fields, and a resent `state` needn't be rebuilt | [PROTOCOL.md](PROTOCOL.md) §3–4 |
| 2026-09-27 | A reaction is a mood's face: `react` picks `none` or one of the seven moods (`annoyed` became `grumpy`), and its moment's `mood` draws the look in that mood's design while the mumble plays, then the mood comes back. The sound follows the face, with a temporary default voice for a mood that has none | The designs are what Boop's feelings look like; a reaction that only changed the gibberish's sound never showed on the face. The mood stays the backdrop, the reaction the moment | [harness/DECISIONS.md](harness/DECISIONS.md) §3, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-27 | A brain reaction waits only for a line playing, not for an animation: it plays over the cheer, which it doesn't cut. This replaces 2026-09-26's "wait behind the rules' moments" for animations | A mumble with no animation can't cut the cheer on the device, and a proud reaction to a long finish should show the cheer in proud's face, not the idle face after it | §3.2 |
| 2026-09-27 | An action can report that it started something rather than did it: HISTORY shows its line `(in progress)` until it reports `done`, or `failed` with why (`(didn't happen: …)`), as a `settle` entry; the harness ends any left open too long | HISTORY said Boop made a face that was still waiting its turn, or that the moment schedule had dropped and never showed. Only the action knows when its effect ends, so the harness only waits, with a ceiling in case it never hears | [harness/HARNESS.md](harness/HARNESS.md) §4–5 |
| 2026-09-27 | `react` is started, not done: its moment's handle ends when the device says how the moment ended, or `failed` when it was dropped, no device was connected or the device dropped. This replaces "HISTORY still says Boop made it" for a dropped reaction. The guide lets Jev make one that didn't happen again, but not repeat one in progress | Jev read reactions that never showed as made, and wouldn't retry them | [harness/DECISIONS.md](harness/DECISIONS.md) §5 |
| 2026-09-27 | A `moment` the Mac waits on carries an `id`, and the device answers it with `ended`: `done`, `cut` (and what cut it) or `skipped`. The Mac gives up on one that doesn't come by the moment's length plus a grace. This replaces the app's own timing, which ended a reaction `done` when it expected the moment to have played. No other moment is answered | Only the device knows whether a tap, "needs you" or a newer moment stopped a reaction, or whether it played at all. The grace keeps older firmware and a lost line from leaving a reaction in progress | [PROTOCOL.md](PROTOCOL.md) §4 |
| 2026-09-28 | Moments are counted in loops of a design, and whoever plays one says how many (`moment.loops`, 1–6). The cheer plays enough loops of the mood's task-complete design to last at least 2 s, replacing the fixed 2 s; a reaction's face holds the loops Jev picks (`react.loops`, once to four times), ending on a loop boundary of the design showing, and at least as long as its mumble. facegen reads each design's loop from its SVG timing and writes it for the device and the Mac alike | Every animation can loop, and the loopable designs coming next should end where they start rather than be cut mid-motion. A bigger moment can hold its face longer. One set of numbers keeps the Mac's timing of a moment with the device's | [PROTOCOL.md](PROTOCOL.md) §3, [harness/DECISIONS.md](harness/DECISIONS.md) §5 |
| 2026-09-28 | `state` drops `idle` and `wait`, replacing 2026-09-27's keeping them for the dashboard, which now counts the idle from its `status` line's sessions and the waiting from `attn`. A change to the session list the snapshot doesn't show is the core's `sessions` effect | Nothing read them but the dashboard, and `wait` was always 1 + `attn.more`. The idle count had quietly been what refreshed the popover when a second idle session came or went | [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-28 | Claude's idle notice (`idle_prompt`) clears a request whoever asked, a subagent included. This replaces "a subagent's request stays, since its prompt may still be up" | The notice means Claude sits at its own prompt with the turn over, which it doesn't do while any prompt is up. Keeping a subagent's request, which the notice also restarted the safety net for, left Boop amber about 11 minutes after you pressed Esc on a subagent's prompt, where BEHAVIORS.md §3.2 says a minute | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-28 | `state`'s `attn` carries the request's number (`attn.id`), and the device chirps when it changes, not only when the agent or project does. Requests are ordered by when they started showing, then by number | BEHAVIORS.md §3.2 says a different request shown chirps, but the device could only compare agent and project, so two worktrees of one repo, or two subagents in one session, took turns in silence; and two requests in the same millisecond were shown in the order their sessions were first seen | [PROTOCOL.md](PROTOCOL.md) §3, [BEHAVIORS.md](BEHAVIORS.md) §2, §3.2 |
| 2026-09-28 | A brain moment on the device holds the moment schedule's line until the device's `ended` for it, or until the app gives up on it; the schedule hears taps and "needs you", runs its pump whenever the line frees, and counts a wait to when the turn came. This replaces giving the next one its turn when the app's own reckoning of a face ran out | The reckoning is an upper bound, up to a whole loop (9 s over idle) per hold too long, so a reaction arriving meanwhile was dropped although the face was long over; and a line sent just as the reckoning ran out could still reach the device before its face ended there, and cut it | §3.2 |
| 2026-09-28 | The needs-you strip names the thread that asks: `boop-hook` reads the thread's name on the hooks that ask for you (Claude's last title in its transcript, Codex's session index), and `state` carries it as `attn.name`, shown in the project's place. The hook client's words are now your prompt, the last message and the thread's name | With several threads in one project, "claude · buddygotchi" didn't say which was asking. Only the title leaves the transcript, it never reaches the brain, and firmware without `name` still shows the project | [ADAPTERS.md](ADAPTERS.md) §2, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-28 | A reaction's face that something ends early after its mumble has played leaves its moment `done`, not `cut`: only a stopped animation or line cuts a moment | With loops, a face holds up to 36 s past its roughly 2 s mumble, so most cuts came after the line was heard. HISTORY then said the reaction didn't happen, and the guide let Jev make it again: Boop said "…finally!" twice | [PROTOCOL.md](PROTOCOL.md) §4 |
| 2026-09-28 | `react`'s `none` also covers a reaction HISTORY shows Boop still making, and isn't for an Example Boop isn't already doing. This replaces "not for anything PERSONALITY's Examples react to" | That wording beat the guide's "don't repeat what Boop is still doing": a comeback's finish got a second proud "…finally!" while the first still showed, in every eval run | [harness/DECISIONS.md](harness/DECISIONS.md) §3 |
| 2026-09-28 | `perf --motion` passes when the board drew a frame in every second it moved and none took over 40 ms, replacing its 10 fps floor | The mood designs step a few times a second, so `fps` follows the design: 6–7 a second through the cheer, in the simulator as on the board, which drew every change in 14 ms at most and still failed the floor | [VERIFICATION.md](VERIFICATION.md) L2 |
| 2026-09-28 | Boop's mood moves only for something lasting (a run of failures, a fix after one, a turn of 10 minutes or more ending, an hour of nothing) and never for a routine turn, and any mood but happy fades back to happy once HISTORY no longer shows the change. Reactions come to anything that stands out, with strong faces held longer for bigger moments, and small ones to routine finishes. All steering text, except two `mood` options: `excited` no longer means "several wins in a row", and `grumpy` means "poked again right after the last time", with each a `not_for` | On the owner's first evening with faces, Jev changed the mood 11 times in an hour, flipping between happy, proud and excited on routine turns, while its reactions were mostly plain. In a scripted working day the tuning took mood changes from 52–53 to 16 a day, and those on a routine line that weren't a fade from 17–18 to 1, with a reaction to every notable line. The mood files alone didn't stop a turn of a few minutes reading as "several wins in a row", nor a first poke streak turning Boop grumpy; the new `excited` option fixed the first, and the text and the new `grumpy` option together only made Jev less sure of the second (0.93 to 0.8) | [harness/DECISIONS.md](harness/DECISIONS.md) §2, [evidence](evidence/2026-09-28-tonight/tune/README.md) |
| 2026-09-28 | A session that ended stays ended for a day: its later hooks are ignored until a `session_start` or a prompt | Hooks from just before the end land after it, and each brought the session back as needing you, working or idle | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-28 | A link that drops doesn't free the moment schedule's line, and a tap doesn't free a brain moment's: both wait for the device's `ended`, or the app giving up. This replaces "with no device connected nothing holds the line" | The device plays on through a link blip, and a moment may reach it just after a tap: freeing the line on a guess let the next reaction cut one still playing | §3.2 |
| 2026-09-28 | A pass's request goes on past the deadline, off the pass, so the log says when the brain answered; the answer is still thrown away. This replaces cancelling it | A dropped pass's latency was only the deadline's timer, so the night's evidence took the timer's 1.3 s for Jev's | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-28 | A routine finish gets a face only when it has something to show (40 s of work or more, or checks passing), and the faces lean strong: excited at a clean win, proud at a hard-won one, curious with "hmm" at a stopped turn, and never grumpy at a win. "yay" is kept for bigger wins; a routine face says its topic, or no word. Proud's file ties its staying to HISTORY still showing the change. All steering text | The first tuning left 68% of a working day's faces happy and "yay" in 80% of reactions, where the owner asked for vivid reactions that use grumpy, sad, proud, excited and determined where they fit. In the scripted day happy went to 35% of the faces, those five to 64%, and "yay" to 34% of the reactions with a word, while every notable line still got a face and the mood changed 16–18 times a day (16 before). Without the change to proud's file, the new personality kept Boop proud past its HISTORY in `13-proud-fades` | [harness/DECISIONS.md](harness/DECISIONS.md) §2, [evidence](evidence/2026-09-28-tonight/tune2/README.md) |
| 2026-09-28 | A sad Boop stays sad through more failures, and leaves only for proud when what failed works, or back to happy as it fades; it no longer turns determined at the next failure. Steering text | In the scripted working day, Jev took sad's old way out to determined at the next failure in 3 of 6 runs of the second tuning, a coin flip in the check's reruns (determined 0.45 and 0.53 against sad 0.49 and 0.39), one mood change a day over the calm the owner asked for. With the change it stays sad there at 0.96–0.97, goes straight to proud at the fix, and both reruns changed mood 16 times | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3, [evidence](evidence/2026-09-28-tonight/tune2-check/README.md) |
| 2026-09-28 | A poke streak never changes Boop's mood: the core names the `mood` action in the event's `sitsOut`, and the harness leaves that action's question out of the pass. Jev still picks the face and word | Steering alone couldn't stop Jev turning a first streak grumpy (0.65–0.91 over four wordings), and a grumpy mood then outlasted the poke by 20–30 minutes. Leaving the question out makes it certain, and the harness stays generic | [harness/EVENTS.md](harness/EVENTS.md) §6, [harness/HARNESS.md](harness/HARNESS.md) §3 |
| 2026-09-28 | The deadline for a pass is 1.5 s, not 1.25 s, with no warm-up pass | Jev's first answers on new steering, and a few in a working day, came just past 1.25 s and were dropped | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-28 | Jev chooses among six moods: curious is gone from the `mood` and `react` options and its steering file. The device keeps its curious designs and draws them if a state or moment names it; the Mac never sends it, and a saved `mood` file saying curious reads as happy | Nothing in the steering led to the curious mood, and its face was only ever the stopped turn's; an option with no way in is only noise to the other choices. boop's stopped turn is now a happy face with "hmm" | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-28 | HISTORY ends with a line naming Boop's last reaction and how long ago it started (`Boop's last reaction, just now: an excited face and "…tests!".`), before the status line. `react` supplies it through the runtime's `parts`, so the harness only places it | Once a reaction had played out, Jev made the same one at the next line that called for it (an excited "…tests!" up to 8 times in a row; a comeback's "…finally!" twice within a minute), and steering text alone didn't stop it. The owner chose naming the last reaction over giving quick passes no face (decision 8a) | [harness/DECISIONS.md](harness/DECISIONS.md) §5, [harness/HARNESS.md](harness/HARNESS.md) §5.3 |
| 2026-09-28 | A routine finish gets a face from 20 s of work, down from 40 s. Steering text | Round 2 reacted to 0.47–0.49 of finished turns, and the owner wanted Boop less quiet (decision 9) | [harness/DECISIONS.md](harness/DECISIONS.md) §2.2 |
| 2026-09-28 | Once a brain reaction's mumble has played (and the link's 0.5 s), the next brain reaction may be sent, and replaces the face the first holds on for its loops; the first still ends `done`. Rule moments and working chatter still wait for the device's `ended`. This replaces "a brain moment holds the line until its `ended`" for the brain's own next moment | A face held two to four times kept the line 16–36 s (9 s for one loop over the idle look), and a reaction waits at most 5 s, so another thread's failure meanwhile got no face. The owner chose this over a shorter idle loop or a cap on the first loop (decision 5c) | §3.2, [PROTOCOL.md](PROTOCOL.md) §3–4 |
| 2026-09-28 | A finished turn no longer cheers by rule: the cheer is the brain's, a reaction's `react.animation`, played in the reaction's face, and with no brain a finish gets none. The tap's wiggle stays the device's. This replaces 2026-09-27's "every finished turn cheers", and loosens "the brain is never on the event path" to the screen's truth (looks, needs you, the wiggle) | A rule cheer gave a 5-second turn and a 40-minute comeback the same moment, and the brain could only paint a face over it. The finalized scenes make the cheer Boop's biggest moment, so it should mean something | [BEHAVIORS.md](BEHAVIORS.md) §3.1, §5, [harness/DECISIONS.md](harness/DECISIONS.md) §3 |
| 2026-09-28 | No rule mumbles: working chatter becomes a working heartbeat, an event that wakes the brain after a quiet stretch of work (the personality's `working_heartbeat`, restarted by Boop's reactions since the row below), and Jev decides whether Boop mumbles, with which face and word. With no brain, Boop works silently | Chatter was the last expressive thing a rule did; a mumble that ignores Boop's mood and what just happened reads as filler. The timer stays a rule so the brain is asked at a steady pace | [BEHAVIORS.md](BEHAVIORS.md) §2, [harness/EVENTS.md](harness/EVENTS.md) §4 |
| 2026-09-28 | The device draws the finalized animation pack: 7 moods × 6 states, with three variations each and working five, which the core (the look) and `react` (the cheer) pick at random, never the last one, and send as `variant`. Needs you's performance plays once, then holds. facegen bakes the pack's scaling, fades and translucency into whole-pixel steps and a blend table, and checks it against Chrome (a blended pixel within one RGB565 step). The partition stays as it is. Its sound came next (the row below) | The owner accepted the pack as Boop's look. A rule picks the variation for now so it can move into the harness later without a device change; the tables (278 KB) fit the current app slot | [BEHAVIORS.md](BEHAVIORS.md) §2, [DEVICE.md](DEVICE.md) §6, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-28 | The device plays the animation pack's sound effects with its designs: sfxgen renders the pack's 47 procedural effects once into 8-bit 11.025 kHz clips (146 KB) with the loudness range square-rooted, and the device follows each design's timeline and policy (working every loop, the cheer and needs you once, idle at most every 45 s, asleep and no app silent). No message carries them. They mix under a mumble at half level, except needs you's alert clips | The owner wanted the pack's sounds, low quality being fine. Storing each design's whole soundtrack would take about 7 MB and synthesising on the board is too slow, so the clips are stored once and sequenced, as the voice's syllables are. The owner chose effects under the mumble, with the ding always heard | [VOICE.md](VOICE.md) §10, [BEHAVIORS.md](BEHAVIORS.md) §4, [DEVICE.md](DEVICE.md) §5, [evidence](evidence/2026-09-28-sound-effects/README.md) |
| 2026-09-28 | The needs-you chirp is gone. Needs you's own performance, with its knocks and ding, is the alert: it plays when a request starts showing, and a different request shown starts it over behind a blink. `dbg.state` reports `alert` (when it last started) instead of `sfx` | The owner dropped the chirp once the pack gave needs you a sound; restarting the performance keeps the rule that each request shown is announced once | [BEHAVIORS.md](BEHAVIORS.md) §3.2, [VOICE.md](VOICE.md) §10, [PROTOCOL.md](PROTOCOL.md) §5 |
| 2026-09-28 | Boop's mood shifts visibly during ordinary work, and a change shows: a first failure while the agent works on makes it determined, a failed turn grumpy, a fix proud, a third clean finish in a row or a clean turn of 5 minutes or more excited, and a turn of 5 minutes or more failing sad (the "long turn" line drops from 10 minutes to 5). Every mood but happy fades back after 5 minutes (sad 10), or once the change leaves HISTORY; the guide asks for a reaction in the new mood's face with each change, a happy one on the way back. Steering text, plus the `mood` options' meanings (`excited` is again for a run of wins, now three; `grumpy` for a failed turn) and `sad`'s face at 5 minutes. This loosens the earlier row's "only something lasting moves it", while one or two routine finishes, a turn start and a stopped turn still never do | The owner wanted to see Boop's personality shift while normally using it. After that tuning the mood left happy only for a test fight or a turn of 10 minutes or more, which ordinary work rarely brings, and a change only swapped the faces behind everything, so it went unnoticed. The aim is roughly 35–45 changes on the scripted working day, from 16, still tied to lines that mean something, not the 11 an hour of routine flips of 2026-09-27 | [harness/DECISIONS.md](harness/DECISIONS.md) §2.1, §2.3 |
| 2026-09-28 | A poke streak can make Boop grumpy, and grumpy blows over 2 minutes after it began (or once the change leaves HISTORY), where other moods take 5 and sad 10. Its pass asks the mood question like any other, so the event's `sitsOut` and the harness's leaving out of an action, which only the poke streak used, are gone. This replaces the morning's "a poke streak never changes the mood" | The owner wanted poking to show on Boop's mood, but only briefly. A short grumpy is a flare-up the person causes and sees end, not a lasting sulk, and a 2-minute fade reads in HISTORY's whole minutes | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3, [harness/EVENTS.md](harness/EVENTS.md) §6 |
| 2026-09-28 | Two lines tell Jev what it would otherwise have to count: `mood` closes HISTORY with how long Boop has been in a mood other than happy (`Boop has been proud for 7 min.`), and the core ends a finish line with `3 clean finishes in a row.` from the second clean finish in a row, across threads (`Core.cleanRun`). The mood files' fades and the excited trigger (exactly 3) are read against them | Jev didn't do the sums: it kept Boop proud 7 minutes after the change where proud lasts 5, and went excited at the second clean finish. With the lines, `13-proud-fades` and `10-run-of-wins` pass 3 of 3, and triggering only at exactly 3 took the scripted day from 135 mood changes to 75 | [harness/DECISIONS.md](harness/DECISIONS.md) §4, [harness/EVENTS.md](harness/EVENTS.md) §8, [evidence](evidence/2026-09-28-expressive-moods/README.md) |
| 2026-09-28 | Jev's input state keeps three modifiers: an outcome (`done`, `failed`, `stopped`, ` It failed.` on a routine tool line, and `after failing` on a pass), a turn's length band (short under 1 min, long under 5, very long from 5, the moods' own lengths), and `(in progress)` on a reaction still playing. Gone from the lines: failure streaks (`failed again …, 3 in a row`), clean runs (`3 clean finishes in a row.`, and `Core.cleanRun` with its fact), time taken, gaps, tool counts, error reasons, a finish's topics and its comeback sentence, and the working heartbeat's topic; a reaction that didn't happen is left out of HISTORY instead of marked; HISTORY's closing lines `Boop's last reaction, …` and `Working now: …` are gone, leaving `mood`'s time in its mood. The moods follow: determined at a failed check, grumpy at a failed turn or a poke streak, proud at a pass after failing, excited or sad at a very long turn done or failed. This replaces the row above's clean-run line and the streak-based moods (grumpy at 3 failures in a row, excited at a third clean finish) | The owner wanted a simpler input state: with many modifiers, what Jev read on a given line was hard to pin down, so behaviour was hard to test. Each line now means one thing and the mood rules read straight off it. The facts keep everything for logs and evals. The evals will be reworked next; `harness/EXAMPLE.md` is a recording from before and shows the old lines | [harness/EVENTS.md](harness/EVENTS.md) §4.1, §5, §8, [harness/HARNESS.md](harness/HARNESS.md) §5.3, §6, [harness/DECISIONS.md](harness/DECISIONS.md) §2, §4, §5, [BEHAVIORS.md](BEHAVIORS.md) |
| 2026-09-28 | The working heartbeat's wait starts again when Boop reacts, not at any event that woke the brain; and `boop` gives every finish done a small face, repeats and all | In the scripted day a 22-minute turn went 16 minutes with no reaction while another thread's quick turns, each answered with nothing, kept restarting the wait. The owner wants Boop to react often and is fine with it repeating itself | [harness/EVENTS.md](harness/EVENTS.md) §4, [BEHAVIORS.md](BEHAVIORS.md) §2, [evidence](evidence/2026-09-28-liveliness/README.md) |
| 2026-09-28 | One transcript of raw events, kept on disk, and a view over it: every agent hook, poke, heartbeat and action is recorded in one shape (top-level metadata, `data` per type), with seven generic types (`session`, `turn`, `tool`, `subagent`, `poke`, `heartbeat`, `action`), a `phase` for those with a lifetime, and the hook's own name as `specific_type`. The core keeps only the screen's rules and records what it did by rule (`wiggle`, `needs_you` start and end) as actions. The view folds the transcript into view events, a raw type and phase with derived facts and a line, kept by a rule held as data. Passes go to `debug.jsonl` only; state snapshots, device lines and `ended` aren't events. A file a day, 14 days kept, the last 2 read back at launch; no launch or quit events, so a turn open across a restart counts the downtime | The owner wanted generic, simple concepts: what the brain heard was built inside the core from state it lost at every restart, three shapes deep. Now there's one record, what the brain hears is derived from it and can be rebuilt exactly, and turn numbers carry across a relaunch | [harness/EVENTS.md](harness/EVENTS.md) §1–4, [harness/HARNESS.md](harness/HARNESS.md) §2, §5, [ADAPTERS.md](ADAPTERS.md) §1, §3 |
| 2026-09-28 | Your prompt and the agent's last message reach the transcript and the brain, each up to 2,000 characters from `boop-hook` and cut to 300 in the state, as notes under the turn's start and end. No other words do: no commands, tool input or output, file contents, error text or transcripts. This replaces 2026-09-25's "no prompts or agent transcripts go to the brain" | The owner's call: they say what a turn was about and how it ended, which the lines alone couldn't | [harness/EVENTS.md](harness/EVENTS.md) §8–9, [ADAPTERS.md](ADAPTERS.md) §2 |
| 2026-09-28 | A turn end's line says how many tool calls it made (`, 12 tool calls.`), but not how many failed. This undoes the three-modifier row's "no tool counts" for that one count | The owner wanted the size of a turn visible; plenty of calls fail in a turn that succeeds, so the failures stay in the facts | [harness/EVENTS.md](harness/EVENTS.md) §4.1, §8 |
| 2026-09-28 | Every poke wakes the brain, even while something needs you, and its line counts the pokes in a row (each within 3 s): no streak rule and no once-a-minute limit. The rules still wiggle, and record it, except while something needs you | The owner wanted the steering, not a rule, to decide how Boop takes being poked; a count tells Jev a single poke from a barrage | [BEHAVIORS.md](BEHAVIORS.md) §3.3, [harness/EVENTS.md](harness/EVENTS.md) §4, §6 |
| 2026-09-28 | A turn's length includes the time the Mac slept; the runtime no longer tells the core how long it slept | The view derives lengths from the transcript alone, which has no sleep events, and one fewer kind of input keeps it simple | §3.2 |
| 2026-09-28 | A look's variations take turns on the device: the Mac's shows first, and after 5 s each loop end moves to another with a 2 in 3 chance (first 8 s and 1 in 2; the owner wanted it a little faster), blinking across and bringing its sounds. This replaces "it holds while the visual does". The Mac times a reaction's face by the look's longest variation | A working turn could loop one design for minutes. The device knows its loop ends to the millisecond, so it can switch where a design comes back to rest; the Mac would land mid-loop | [BEHAVIORS.md](BEHAVIORS.md) §2, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-28 | The brain's exclamations gain "nice", already recorded, for a long turn done but not one ending just after its fix, and "yay" narrows to a very long turn done. No reflash | Long finishes had no word at all. "wow" (a very long turn that fought back) and the topic "fix" (a turn done after its fix) were tried and dropped: "wow" hangs on a HISTORY line Jev doesn't connect to the finish minutes later (0 of 3 in a scenario), and steering that tied "fix" to a comeback made Jev repeat proud faces (`11-comeback-still-showing` 7 of 10, from 10 of 10) | [harness/DECISIONS.md](harness/DECISIONS.md) §3, [VOICE.md](VOICE.md) §6 |
| 2026-09-28 | A reaction a tap cut short stays in HISTORY, `(in progress)` while the pokes go on (each within 3 s) and plain after, where any other reaction that ended failed is left out. And a poke doesn't wake the brain while the brain's reaction to its run's pokes in a row is in progress, unless the mood changed since it started. This narrows the row above's "every poke wakes the brain" | Each barrage of pokes got two "nope"s: the tap that cut the first one's pass saw no reaction and made it again. Keeping it in HISTORY alone still left Jev repeating it on half the passes (it matches PERSONALITY's Example word for word), and steering that stopped the repeats also stopped later rounds getting their face. A single poke's reaction doesn't hold the run, so a barrage can still turn a happy poke grumpy (eval `23`) | [harness/EVENTS.md](harness/EVENTS.md) §6–7 |
| 2026-09-28 | The topic words gain "bug", "merge" and "review", already recorded, which Jev reads from your prompt and the agent's last message rather than a hook's tag. PERSONALITY names them in one line, with no Examples | The notes made these topics visible without new detection. Three Examples put `boop` at 729 tokens, over its 600 budget, and the option meanings alone got 10 of 10 in each new scenario | [harness/DECISIONS.md](harness/DECISIONS.md) §3, [VOICE.md](VOICE.md) §6, [evidence](evidence/2026-09-28-topic-words/README.md) |
| 2026-09-28 | In a long grind Boop's mood may ease back to happy between check-ins and return to determined; `18-long-grind` drops its limit of 3 mood changes and keeps the one against flipping back within a minute | The owner's call: with check-ins every 1.5–3 minutes, happy → determined → happy → determined → excited over twenty minutes is expected, and the limit failed on main in 10 of 15 runs | [EVALS.md](EVALS.md) §4 |
| 2026-09-28 | A cheer for a thread's turn names it: `moment.who` (agent and thread) goes with the cheer, and the strip shows it on a black band while the cheer plays. The popover's rows show each session's thread beside its project. Needs a reflash | A cheer said something finished but not which of several agents in one repo, and the popover listed six rows all named `buddygotchi` | [PROTOCOL.md](PROTOCOL.md) §3, [BEHAVIORS.md](BEHAVIORS.md) §5 |
| 2026-09-28 | Push-to-talk comes back, and this time what you say reaches the brain: hold BOOT 400 ms (or click Talk) and the Mac's mic listens, up to 30 s, with on-device recognition; the words are a `talk` event from the new source `mic` (2,000 characters in the transcript, 300 in the state as `You said to Boop: "…"`) that always wakes the brain, even while something needs you. The device shows `listening` from the pack until the reply, a mumble, or the empty moment when no reaction comes, or 8 s. It's the third kind of words that reach the brain, after your prompt and the agent's last message (an earlier 2026-09-28 row). Quiet mode and the yell meter stay out. A personality's token budget goes from 600 to 700, since `boop` was at 592 before its talk rule and three Examples. Without the Examples Jev let a plain question go unanswered (0 of 5 runs, 1 of 5 with the rule alone); with them it answers every time | The owner wanted to talk to Boop again. The earlier version (removed at `ef142e7f`) listened but its words went nowhere | [BEHAVIORS.md](BEHAVIORS.md) §3.3, [harness/EVENTS.md](harness/EVENTS.md) §2, §4, §6, §8–9, [PROTOCOL.md](PROTOCOL.md) §3–4 |
| 2026-09-28 | `boop-hook` reads the thread's name on every hook, not only on the ones that ask for you, and every event carries it, so the popover and a cheer show the name you gave the thread from its first titled turn on, and follow a rename at its next hook. A tool call's hooks read only the last 256 KB of Claude's transcript | Before, a thread that had never asked showed its worktree folder. Titles sit within 30 KB of a transcript's end, so the read costs under 10 ms; the name still never reaches the brain, whose lines name the workspace | [ADAPTERS.md](ADAPTERS.md) §2 |
| 2026-09-28 | The topic words gain the agents' names, `claude` and `codex`, newly recorded: the filler when no other topic fits, so a routine finish says whose it was. PERSONALITY's short-turn Example says "claude" instead of no word. Needs a reflash | The owner wanted Boop to say which agent it means, mostly for the cheer. Jev picks it like any topic word, so the exclamation still comes first at a cheer; the name fills the routine finishes that had no word. The option is tied to a turn ending: with only "not for work still going", every quiet check-in said the name (`15` 0 of 3), and it says any other topic's word wins: after main's talk Examples, a bug fix split "claude" and "bug" near even (`30` 1 of 3) | [harness/DECISIONS.md](harness/DECISIONS.md) §3, [VOICE.md](VOICE.md) §6, [evidence](evidence/2026-09-28-agent-words/README.md) |
| 2026-09-29 | The mood spectrum is integrated whole: 13 moods on the owner's mood graph and 22 states, 770 designs with their sounds, from the animation bank (`internal/boop-design/`), which becomes the one source: facegen runs its generator into an ignored build dir, sfxgen imports it, the copied SVGs and scores are gone, and facegen stops if an older mood's design differs from the bank's fingerprints | The owner's call: "incorporate everything" of the V4 package, planned in phases with its decisions written down first ([PLAN](evidence/2026-09-28-mood-spectrum/PLAN.md)). One source leaves no second copy to drift | [DEVICE.md](DEVICE.md) §6, [VOICE.md](VOICE.md) §10, [evidence](evidence/2026-09-28-mood-spectrum/README.md) |
| 2026-09-29 | Flash is `huge_app.csv`: one 3 MB app slot and no second one, NVS still at 0x9000. The firmware is 2.50 MB, 79% of it. This replaces "the partition stays as it is" | 13 moods' faces take 1.19 MB, which `min_spiffs.csv`'s 1.875 MB slots can't hold with the rest; nothing updates over the air yet (D1) | [DEVICE.md](DEVICE.md) §5 |
| 2026-09-29 | Each mood × state has its own variations (1–9), some made for a result (task_complete's success or failure) or a start (new task, session, carrying on); the Mac and the device pick among those that fit, never the last. A flip-book design uses the face and mouth of the step that shows, blinks on its own clock, and a switch to or from one shows its blink step | The bank's V4 art: the older moods have one or two of the newer states, the new ones three; its flip-books can't shut their eyes on the device's clock, so switches would cut hard | [DEVICE.md](DEVICE.md) §6, [BEHAVIORS.md](BEHAVIORS.md) §2, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-29 | Sound effects take the bank's voice-first mix for every mood: quiet states silent, routine contacts thinned and picked per loop (8 loops baked, seed 53), sparse counted in loops, and ducking by design (needs you, the finish and an error never; the rest to a quarter) instead of by `alert*` clip names. 49 clips, 157,609 bytes | D6: the voice comes first, and the bank's player is the reference | [VOICE.md](VOICE.md) §10 |
| 2026-09-29 | The `state` line carries `act`, what the agents are doing while working (testing, delegating, terminal, searching, analyzing, tool_use, waiting, planning), from running calls, helpers and plan mode, in that priority, held at least 1.5 s; the working session heard from last picks. Waiting (a call quiet 20 s, or Codex's grace) replaces the call's own look | The spectrum's sustained states; the hooks already say which tool runs, and a floor keeps quick tools from flickering. Ranked below the tool states with a running tool as its evidence, waiting could never show | [BEHAVIORS.md](BEHAVIORS.md) §2, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-29 | The rules play one-shots as moments with no `id`: starting (with its context), stopped, error (exit code or timeout, at most every 30 s) and helper_return. They play at once, a brain moment plays over one without waiting, one is dropped while a brain line plays, and they stay out of the transcript like the look. This replaces "the rules add no moment" | They're facts of the hooks, not the brain's to choose; waiting behind one would drop most reactions to a prompt, and cutting a brain line would break its `ended` | [BEHAVIORS.md](BEHAVIORS.md) §3.1, §3.2, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-29 | Claude's `SubagentStart` is hooked (14 hooks), `boop-hook` keeps SessionStart's `source` and the hooks' `permission_mode`, a shell command that only reads gets the topic `inspect`, and a request answered by anything but its call's result drops that call from the look | Delegating, helper_return, starting's context and planning need them; Codex's reads come through its shell; Claude sends no hook for a denial, so the call would show until the turn ends | [ADAPTERS.md](ADAPTERS.md) §3–5, [BEHAVIORS.md](BEHAVIORS.md) §2 |
| 2026-09-29 | The mood question is built on every pass from the saved mood: staying, plus that mood's moves on the owner's graph, dramatic ones with a "not for" a fresh, big event; the action takes nothing else. No timer in code: how long a mood lasts stays the steering's. The dashboard may set any of the 13. This replaces the fixed list of six | The owner's graph (D3) and pacing in steering (D5): Jev picks only a step the graph allows, so grumpy never goes straight to happy | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3, §4 |
| 2026-09-29 | Calm is the resting mood: a new Boop starts calm, fades go one step toward it, HISTORY's closing line is quiet while calm, and a missing or unknown saved word reads as calm (logged). This replaces happy as the mood every mood fades to | The handover's suggestion (D4, D11): a settled creature, with happy a mood that means something | [harness/DECISIONS.md](harness/DECISIONS.md) §2.3, §4 |
| 2026-09-29 | `react.animation` is `none`, `success`, `failure` or `reply`: the brain judges each finish's outcome from NOW's line and the agent's last message, and the reaction plays task_complete for that outcome or reply_ready; there's no code override for a failed turn (HISTORY already says it failed, and an always-eval pins it). This replaces the cheer | The owner's call (D2): the harness should decide success or failure from the turn-end text, as a multiple-choice answer, with a failure never showing a trophy | [harness/DECISIONS.md](harness/DECISIONS.md) §5, [BEHAVIORS.md](BEHAVIORS.md) §5 |
| 2026-09-29 | The harness's ceiling for an action in progress goes from 60 to 90 s; a pass's `debug.jsonl` line names the options it asked where they differ from the launch's `questions` line; the scripted brain keeps the mood and plays each finish's outcome | Wounded's 13 s idle held four times, with the wait and the grace, came to 61 s; the mood's options now change with the mood | [harness/HARNESS.md](harness/HARNESS.md) §5.1, §9 |
| 2026-09-29 | A tap plays the mood's `poked` design, and `tap_spam` from the third tap within 3 s, which the device counts itself with the Mac's numbers; the sway and heart are gone, and a `wiggle` moment means poked. The screen's priority is no app, listening, needs you, a poke and the moments, then the look | The bank has a poke for each mood; counting on the device keeps a barrage instant | [BEHAVIORS.md](BEHAVIORS.md) §3.3, §5 |
| 2026-09-29 | The rules' action for a poke keeps its name, `wiggle`, and its words, `Boop wiggled on its own.`, which Jev reads, though the device now plays a poke | Jev ran out of credit before new words could be checked; the poke evals pass with these | [harness/EVENTS.md](harness/EVENTS.md) §2 |
| 2026-09-29 | A line that comes with an animation starts in the design's voice window (after its attention cue, about 5 s into a finish) and the animation holds until the line and its bubble end; the Mac reckons the same from `FaceLoops.voiceMs`. A brain moment that has waited over 5 s is still dropped, so a reaction just after a finish can be | The bank's handover: the voice enters after the cue, never sped up to fit | [VOICE.md](VOICE.md) §9, §3.2 |
| 2026-09-29 | The bubble takes the bottom lane (y ≥ 192) in place of the strip while a line plays, and props are no longer hidden under it; only a `say` or the empty moment ends `listening` | The new designs keep that lane free and their props are the action (D10); a rule's one-shot must not end push-to-talk | [DEVICE.md](DEVICE.md) §4, [PROTOCOL.md](PROTOCOL.md) §3 |
| 2026-09-29 | Evals cost fewer Jev requests: an `always` scenario runs 3 times (was 5) and the rest once (was 3), a scenario can set its own `runs` (`53` runs once), and `boopdev eval` counts a run's requests with the scripted brain first and stops over a budget of 100 unless `--budget N` or `--no-budget` (`make eval`, the final pass) says. A full eval goes from about 1,340 requests to about 620 | The owner's call: evals ran too often against a limited API budget (Jev ran out of credit the same day). While developing, run only the scenarios a change touches; the whole eval is the final pass | [EVALS.md](EVALS.md) §1–3, [VERIFICATION.md](VERIFICATION.md) L5 |
| 2026-09-29 | What the person says to Boop moves its mood at once: the guide lets talk move the mood in its first minute, as a poke does; saying sorry moves grumpy to irritated or annoyed, irritated to annoyed and annoyed to calm; sad news moves most moods to sad and keeps Boop there, and taking it back or cheering it up leaves sad for calm or happy. The mood question's meanings (`MoodAction.moods`) and a dramatic move's "not for" say the same, and PERSONALITY answers sad news with a sad face | The owner's brief: the mood should change faster while the person talks to Boop, and one apology should do. Before, the first-minute hold and grumpy's rules (it cooled only after 2 min or at thanks) meant saying sorry twice. Scenarios `56`–`59` check it; all passed, and `make eval` passed but for the known gap `20` ([evidence](evidence/2026-09-29-talk-moves-mood/README.md)) | [harness/DECISIONS.md](harness/DECISIONS.md) §2.1, §2.3, [EVALS.md](EVALS.md) §4 |
| 2026-09-29 | Boop says recorded takes, not gibberish: Jev picks a meaning (the takes' intents, each naming the faces that can say it) and a kind (sound, word, phrase, swear), and Voice finds a take of that meaning performed in the face's mood, fit for the finish (success takes only on a success, swears only on a failure), stepping down to a plainer kind, never the last take again while another fits; with none, the face plays in silence. All 40 of the bank's takes go on the board unreviewed; the six in moods Boop lacks are mapped to the nearest. The gibberish, dialects, unintelligibility check and one-real-word rule go | The owner's choice (2026-09-29) of option B: Jev picks from a dozen meanings and four kinds, however many recordings there are; silence rather than another mood's voice, with the steering asking for a face that can speak; swears by personality | [VOICE.md](VOICE.md), [harness/DECISIONS.md](harness/DECISIONS.md) §3, §5 |
| 2026-09-29 | A tap's poke replaces only the animation playing: a brain reaction's line, bubble and face play on over it, the poke drawn in the reaction's mood, where before the poke cut the whole reaction. A finish's animation is still replaced, and reported `cut` by `tap`; "needs you", a newer moment and push-to-talk still cut the line | In a barrage the brain answers once (EVENTS.md §6), and that answer usually landed mid-barrage, so the next tap cut it and you never heard it. The taps still get their animation at once | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| 2026-09-29 | The screen turns half a turn: `kRotation` 3, USB-C on the left seen from the front (was 1, on the right). The test pattern's USB-C bar, its colour blocks and the webcam check move with it; a touch calibration saved at rotation 1 is ignored until `boopctl calibrate` runs again | The owner holds Boop the other way up, and the picture had the face upside down that way | [DEVICE.md](DEVICE.md) §4, [VERIFICATION.md](VERIFICATION.md) L3 |
| 2026-09-29 | Boop's whole voice is on the board's microSD card: all 2,722 of Federico's takes, the 40 before them included, in one pack voicegen builds (`.build/voice/voice.bin`, not checked in), which the board reads at 10 MHz on SPI3 and the Mac checks by version (`status`'s `voice`). With no card, or another pack, Boop has no voice; its faces and sound effects, still in flash, carry on. Touch moves to bit-banged SPI so the card can have the second bus. `Takes.swift` is written as one `append` per take | The owner wanted every take, even overlapping ones, for more choice, and no difference between the old and the new; at 30.5 MB they can't fit the 4 MB flash, and the card reads about eighty times faster than a line needs (probe, [evidence](evidence/2026-09-29-voice-sd/PLAN.md)). One array literal of 2,722 takes ran the Swift compiler out of memory (63 GB) | [VOICE.md](VOICE.md) §3, §8, [DEVICE.md](DEVICE.md) §2, §5, [PROTOCOL.md](PROTOCOL.md) §3–5 |
| 2026-09-29 | What Boop says is two answers again, as the mumble's exclamation and topic word were: how it feels (`say.feeling`: upset, glad, tickled) and what NOW is about (`say.about`: 15 topics), played as a line of up to two takes, 180 ms apart, at most 2.8 s, a phrase alone; `say.meaning` goes. Every face has takes for every answer. Voice takes the nearest kind either way, never a swear nobody asked for. A failed turn's face is irritated, which swears; sad is for an agent giving up. The bubble drops to the small font for a line too long for the large one | The owner's rule: every face and every answer has something to play, and the topic words (Launch, Rerun, Cleared, Test) are the content half of the old pair. Sad and wounded were silent at the failures that matter most. The changed scenarios pass once each (15 of 15) | [VOICE.md](VOICE.md) §4, [harness/DECISIONS.md](harness/DECISIONS.md) §3, §5, [DEVICE.md](DEVICE.md) §4, [evidence](evidence/2026-09-29-voice-sd/eval.txt) |
