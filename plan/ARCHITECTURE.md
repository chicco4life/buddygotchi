# Boop: architecture

Updated 2026-09-27. The parts of Boop, how they connect, what they keep on
disk, and the decisions behind them. The other specs go deeper on each
part; [README.md](README.md) lists them all.

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
 │     rule      │  │ events                                  │           │
 │   reactions   │  ▼                                         │           │
 │               │ Harness ──► Brain: Jev, questions + answers│           │
 │               │  │  ▲                                      │           │
 │               │  │  └── steering files: guide,            │           │
 │               │  │      personality, mood                  │           │
 │               ▼  ▼ answers                                 ▼           │
 │              Actions ──► Voice (Minion speech) ───►  Device link ──────┼──► device
 │              react,      mood store (the mood file)                    │
 │              mood                                                      │
 └────────────────────────────────────────────────────────────────────────┘
```

**Following one event:**

1. Codex finishes a task. Its hook sends one line to the Mac app and
   returns at once.
2. The Codex **adapter** turns it into the common event: "Codex, session
   a1b2, project landing, turn finished".
3. The **core** sees the turn took 18 minutes and, by rule, plays a
   cheer, well under a second after the hook.
4. The core also hands the **harness** an event, with its line: "codex
   finished turn 3 on "landing": done after 18 min, a very long turn…".
   The harness asks **Jev** every action's questions about it in one
   request, and Jev answers: `react: proud`, `word.feeling: finally`.
5. The **`react` action** reads its answers, asks **Voice** for Minion
   speech (*"ma-po li… finally!"*) and sends it through the **device
   link**, to play over whatever face is showing.

The brain never sits between an event and the screen. Rules give the
immediate reaction, and the brain adds character a second or two later. If
the brain is slow, offline or missing, Boop still reacts to everything, just
with less personality.

## 2. Three loops at three speeds

| Loop | Runs on | Speed | Does | Never does |
| --- | --- | --- | --- | --- |
| Reflex | Device | < 20 ms | Tap feedback, blinking, blending faces, the needs-you chirp and light | Wait for the Mac |
| Reactive | Core → actions | < 200 ms p95 | Agent event → rule → action → device | Wait for the brain |
| Deliberative | Harness + brain → actions | 1–5 s, in the background | React with character, answer push-to-talk, note what you tell it | Block the reactive loop |

## 3. Components and boundaries

Each part has one job and knows as little as possible about the others.
The core and the brain decide *what* should happen, and actions make it
happen. Nothing that decides ever builds Minion speech, touches a file or
talks to the device.

| Part | Does | Doesn't know about |
| --- | --- | --- |
| Adapters | Turn agent hooks into common events | Boop's state, the brain, the device |
| Core | Keeps the session table; decides what the device shows, the rule reactions, quiet, when the mic is on, and the events for the harness and which wake the brain | Minion speech, models, hook formats |
| Harness | Keeps the transcript; for each event that wakes the brain, builds the state, asks every action's questions in one request, hands each action its answers and records what it did | Minion speech, the device, an event's facts, what an action does |
| Brain | Jev: answers multiple-choice questions about a plain-text state, with probabilities | Everything else |
| Actions | Carry out one call each, checking their own rules | Whether a rule or the brain called them |
| Voice | Turns a feeling and an optional word into Minion speech | Who asked, or why |
| Memory store | Reads and writes the memory files and their snapshots; supplies their text and applies changes within limits | Models, the device |
| Device link | Sends snapshots and moments, and receives taps, talk and the device's other messages, over Bluetooth or USB | What any of it means |

### 3.1 Adapters

Each adapter turns one agent's hook calls into the common event. Hooks
only report, so the agent carries on as normal ([ADAPTERS.md](ADAPTERS.md)).

### 3.2 Core

The core is plain rules with no queue. It keeps a table of sessions (agent,
project, and whether each is working, idle or needs you), works out what
the device shows in [BEHAVIORS.md](BEHAVIORS.md) §1's layers, plays the
rules' reactions and working chatter, and keeps quiet mode and the mic
(§3.8). It turns agents starting and finishing, what you say and a poke
streak into the brain's inputs ([HARNESS.md](harness/HARNESS.md) §2); taps and
"needs you" stay the rules' own.

In code the core is a pure state machine. Each event, device input or
one-second tick goes in with the time, and effects come out: a snapshot, a
moment or a mumble to play, an event for the harness, a
Happened line or a new day for the memory store, the mic on or off. The
app hands each effect to the part that carries it out, so every rule is
testable on a virtual clock. Timers run on a steady clock that never steps
and keeps counting while the Mac sleeps, so setting the Mac's clock back
can't stall one; days and times of day follow the wall clock.

One pass runs at a time; a newer event that wakes the brain replaces one
waiting ([HARNESS.md](harness/HARNESS.md) §3).

The brain's moments never cut another moment off. The rules' moments play
at once, each new one replacing whatever is playing
([BEHAVIORS.md](BEHAVIORS.md) §3). The brain's wait their turn
(`MomentSchedule`), one at a time, and one that has waited longer than its
`ttl` (5 s) is dropped, since a late reaction is worse than none. The app
times each moment as the device does: the animation's length or, if
longer, the mumble's syllables plus two beats for the word, then 1.2 s to
read the bubble. `listening` holds nothing back, and the mic turning on
drops any brain moment still waiting ([BEHAVIORS.md](BEHAVIORS.md) §3.3).

### 3.3 Harness and brain

The brain is TypeSafe's Jev: it reads a plain-text state and answers
multiple-choice questions with probabilities, all in one request of
about 0.2–0.3 s. The harness keeps the transcript, builds the state from
it and the steering files, asks every action's questions, and hands each
action its answers ([harness/HARNESS.md](harness/HARNESS.md)). Without Jev's
key no pass runs, and Boop does only its rule reactions.

### 3.4 Actions

Actions are what the brain can make Boop do: `mood` (Boop's mood, which
picks the MOOD section of the next state) and `react` (a mumble with a
feeling and maybe one real word). Each declares the questions it needs,
reads Jev's answers to them, checks its own rules, and reports what it
did ([harness/DECISIONS.md](harness/DECISIONS.md)). The rules' own moments
(a cheer, a wiggle, working chatter) don't go through them.

### 3.5 Voice

Voice turns `feeling + word` into a Minion line in this Boop's dialect and
checks it isn't accidentally English ([VOICE.md](VOICE.md)).

### 3.6 Memory store

The memory store is the only code that reads or writes the memory files
and their snapshots (§4), and it writes atomically.

### 3.7 Device link

The device link sends snapshots and moments and receives the device's
inputs and status ([PROTOCOL.md](PROTOCOL.md)), over Bluetooth for normal
use or USB serial for development. Both carry identical messages, and
nothing above the link knows which is in use. An agent can't launch the
app with Bluetooth, so the whole hook-to-screen path is tested over USB
([VERIFICATION.md](VERIFICATION.md) L4). The app opts out of App Nap
(without keeping the Mac awake), so its regular `state`
([PROTOCOL.md](PROTOCOL.md) §3) isn't held back until the device thinks
the app is gone.

### 3.8 Push-to-talk

The device has no mic, so push-to-talk, from its button or the popover's
Talk, records from the Mac's. The core decides when the mic is on and off
([BEHAVIORS.md](BEHAVIORS.md) §3.3). The app turns speech into text on the
Mac, measures whether you yelled and drops the audio at once. For now the
words go nowhere: talk is out of the brain until it comes back
([FUTURE.md](FUTURE.md)).

## 4. Memory files

Boop's memory is two Markdown files in the state directory (§4.4):
`long-term.md`, who this Boop is and what it knows about you, and
`short-term.md`, today, which starts fresh each day. They're out of the
brain for now: nothing writes facts to them, and Jev's state doesn't
include them ([FUTURE.md](FUTURE.md)). The steering files that shape the
brain are read-only and live with the app (§4.1).

**A new day** starts at the day's first activity: an agent event, a tap or
pressing Talk. The memory store snapshots both writable files to
`history/<date>/`, where `<date>` is the day before (setup also snapshots,
under the day Boop hatched), and `short-term.md` starts fresh. Nothing
looks back on the day, so Temperament and Moments change only by hand.

The files are plain text, and hand edits are welcome: the store reads a
file again when it changes on disk, before its next change, so an edit
isn't overwritten. A file that won't parse is kept as `<file>.broken`.
`long-term.md` is then restored from its newest snapshot that reads.
`short-term.md` snapshots are always of an earlier day, so it starts fresh
instead, keeping the file's date if one can be found so the day doesn't
start twice.

Each file has a size budget, so it can go back into the brain's state
without trimming: `long-term.md` at most 3,200
bytes (about 800 tokens) and `short-term.md` at most 2,400 bytes (about
600). The line limits below mostly keep them there; when they don't, a
change to long-term memory is refused ("full") and short-term memory drops
its oldest Happened lines.

### 4.1 The steering files

Boop's AGENTS.md: the guide that opens Jev's state, each personality
(with its settings for the core's rules) and each mood
([harness/DECISIONS.md](harness/DECISIONS.md) §2). Nothing changes them at
runtime, because different steering makes a different creature.
`plan/steering/` is the single source; the app bundles a copy.

### 4.2 `long-term.md`

From the memory tests (`MemoryTests.sample`):

```markdown
## Boop
name: Pip · hatched: 2026-10-02 · nature: cheeky · seed: 7f3a

### Temperament
Nosy and a bit smug. Trusts Codex more than it used to.
Gets huffy about flaky tests.

### Moments
- 2026-10-09: first all-nighter together; the migration finally passed.

## About you
- Ships on Fridays.
- Mostly works on landing and jetpack.

## Preferences
- Likes it quiet before 10am.
```

| Section | Written by | Rule |
| --- | --- | --- |
| Boop (name line) | The app, at setup | Never changes. The name is 1–23 characters without `·` or `:`; `nature` is the person's one answer (sweet or cheeky); `seed` is random and picks Boop's voice dialect |
| Temperament | You, by hand | Only the first five lines are kept |
| Moments | You, by hand | Only the newest 20 are kept. Each starts with its date; one without makes the file unreadable |
| About you | You, by hand; the brain again once memory writes come back ([FUTURE.md](FUTURE.md)) | At most 30 lines of at most 100 characters: durable facts about you. A new line when full is refused; you free room in Settings or by editing the file |
| Preferences | You, by hand; the brain again later, as above | At most 15 lines; the same limits. How you like things done |

A line's checks are simple rules in the memory store, and they err on the
side of refusing: one line, nothing already there, no links or addresses,
no code (backticks, braces, `=`, `;`, `$`, `<`, `>`), nothing path-shaped,
nothing that looks like a key, and no capitalised word mid-sentence other
than days, months, agents, acronyms and Boop's own name, since long-term
memory keeps no one else's name.

The Boop section is who this Boop is. It lives only on the Mac, so
reflashing or replacing the device doesn't change it, and the app has no
reset button. In Settings you can see and delete lines in About you and
Preferences; the Boop section isn't shown.

### 4.3 `short-term.md`

From the test fixtures (`app/Tests/Fixtures/memory/short-term.md`):

```markdown
## Today
2026-10-14 · first seen 08:52

## Notes
- jetpack is the payments service
- landing launches Monday
- said "shut up for an hour" at 13:10

## Happened
- 09:13 claude · jetpack · finished (4 min)
- 11:20 codex · landing · build · failed
- 14:02 codex · landing · tests · failed
- 14:05 claude · jetpack · finished (18 min)
- 17:55 codex · jetpack · finished (26 min)
```

| Section | Written by | Rule |
| --- | --- | --- |
| Today | Core | The date and the time of the first activity |
| Notes | You, by hand; the brain again later, as above | At most 10 lines of at most 80 characters: facts about a project or this session. The oldest drops first. The checks above, but names are fine |
| Happened | Core | A line for each finish of 30 s or more and each failed turn; the last 40 |

### 4.4 State directory

Everything a Boop keeps on the Mac lives in one folder,
`~/Library/Application Support/Boop`. `Boop --state-dir DIR` points the app
elsewhere, and headless runs and tests always do, so they never touch the
everyday Boop. Jev's key is in the Keychain, not here.

| Path | What it is | Written by |
| --- | --- | --- |
| `long-term.md`, `short-term.md` | The memory files (§4.2–4.3) | Memory store |
| `history/<date>/` | Both memory files as they were at the end of that day, and at setup | Memory store |
| `<file>.broken` | A memory file that wouldn't parse, kept for you to look at | Memory store |
| `settings.json` | The personality and the volume. Keys it doesn't know, from older versions, are ignored | The app, when you change them |
| `boop.sock` | The hook socket, readable only by you. `boop-hook` writes one line per hook to it ([ADAPTERS.md](ADAPTERS.md) §2) | The app, at launch; removed at quit |
| `boop.lock` | Held while an app runs here; a second copy on the same folder refuses to start | The app |
| `mood` | Boop's current mood, one word ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3) | The mood store |
| `boop.log` | The app's log, appended: startup, hook repairs, device inputs, dropped calls and one line per brain pass. Never Jev's state ([harness/HARNESS.md](harness/HARNESS.md) §9) | The app |
| `debug.jsonl` | Debug mode only: every brain pass and aside as a JSON line, emptied at each launch ([HARNESS.md](harness/HARNESS.md) §9) | The harness |
| `doctor-armed` | While it exists, the app logs every hook ([ADAPTERS.md](ADAPTERS.md) §6) | The `doctor` skill |
| `bin/boop-hook` | The copy of the hook client every hook entry calls, refreshed at launch so rebuilding or moving the app doesn't break hooks ([ADAPTERS.md](ADAPTERS.md) §5) | The everyday menu-bar app |

## 5. Common event shape

The event every adapter produces is in [ADAPTERS.md](ADAPTERS.md) §1, and
what each hook becomes in its §3.

## 6. When an agent needs you

How "needs you" is detected and cleared is in [ADAPTERS.md](ADAPTERS.md)
§4; what Boop does about it is in [BEHAVIORS.md](BEHAVIORS.md) §3.2.

## 7. Device

The device is a thin client. It draws what the latest snapshot says, plays
moments, runs its own short timers (blinks, the needs-you chirp, the reply
wait after push-to-talk) and reports taps and push-to-talk. It keeps no
personality or memory, only its touch calibration. What it does is in
[BEHAVIORS.md](BEHAVIORS.md); the hardware and firmware are in
[DEVICE.md](DEVICE.md).

## 8. When things go wrong

| Failure | What happens |
| --- | --- |
| App not running, or the Mac asleep | Hooks exit at once and agents carry on. The device soon shows it has no app ([BEHAVIORS.md](BEHAVIORS.md) §3.4) |
| Device disconnected | The app keeps going; on reconnect the next `state` catches the device up |
| Brain slow, offline or wrong | Rules still drive every reaction. A pass Jev fails, is late for, or answers off its options is dropped, and no action runs ([harness/HARNESS.md](harness/HARNESS.md) §7) |
| Memory file won't parse | It's kept as `.broken` and recovered (§4) |
| A second copy of Boop on the same state directory | It refuses to start (`boop.lock`), and the popover says another copy is running |

## 9. Budgets

| Path | Target |
| --- | --- |
| Agent event → pixel | < 200 ms p95 |
| Tap → visible feedback | < 20 ms, on the device |
| Hook overhead | Single-digit ms. When the app is slow, the hook waits at most 50 ms in all, then gives up |
| Brain, per pass | Jev's answer within 1.25 s ([harness/HARNESS.md](harness/HARNESS.md) §7). A late answer is dropped |

## 10. Stack

- **Mac app:** Swift, built with SwiftPM from `app/`, using CoreBluetooth,
  the Speech framework, and TypeSafe's API for Jev when the person has a
  key. SwiftPM builds no app bundle here, so
  the app's `Info.plist` (usage descriptions, `LSUIElement`) is linked
  into the `Boop` binary with `-sectcreate`.
- **Hook client:** `boop-hook`, a small Swift executable in the same
  package. It shares only `HookWire` with the app: the hook line, topic
  tags and the socket, in Foundation alone, so the client stays small and
  fast and both sides agree on the line by construction.
- **Firmware:** PlatformIO + Arduino core + LovyanGFX + NimBLE-Arduino in
  `firmware/` ([DEVICE.md](DEVICE.md) §4), to be ported to ESP-IDF + LVGL
  once v1 is verified ([PLAN.md](PLAN.md) §4).
- **Dev tools:** `tools/boopctl` for the device and `boopdev` for the app
  ([VERIFICATION.md](VERIFICATION.md) §2).

The stable contracts are the common event ([ADAPTERS.md](ADAPTERS.md) §1), the
memory files (§4), the harness's two contracts, events in and actions out
([harness/HARNESS.md](harness/HARNESS.md) §3–4), and the protocol ([PROTOCOL.md](PROTOCOL.md)).

## 11. Decision log

When a change departs from the spec, change the spec first and add a row
here saying why. When a new decision replaces an old one, replace its row.
This table keeps only the decisions still in force, newest last; the full
log up to 2026-09-27 is in
[archived/plan-v1-build/decisions.md](../archived/plan-v1-build/decisions.md).

| Date | Decision | Why | Where |
| --- | --- | --- | --- |
| 2026-09-25 | The personality is the product; usefulness comes second | It's why people keep Boop | [VISION.md](VISION.md) |
| 2026-09-25 | Boop speaks synthesised Minion gibberish with at most one real word, in English | A creature, not a chatbot; cheap to make, and the gibberish needs no translation | [VOICE.md](VOICE.md) |
| 2026-09-25 | Boop only notifies; you approve in the agent, on the Mac | Simpler, and a bug in Boop can never approve anything | [ADAPTERS.md](ADAPTERS.md) §1 |
| 2026-09-25 | Memory is Markdown files on the Mac; the steering files are read-only; hand edits are allowed, and there's no reset button | Simple and inspectable, independent of the device and the model, and permanent without extra machinery | §4 |
| 2026-09-25 | No code, prompts, file contents or agent transcripts go to the brain; your own words on push-to-talk are the one exception | Privacy | [harness/HARNESS.md](harness/HARNESS.md) §5 |
| 2026-09-25 | Our own protocol, with the same messages over Bluetooth and USB, and no pairing or encryption yet | Only our app talks to the device, and USB lets agents test the whole path | [PROTOCOL.md](PROTOCOL.md) |
| 2026-09-25 | The firmware starts on Arduino + LovyanGFX and moves to ESP-IDF + LVGL once v1 works; drawing code stays independent of the display library | Fastest to a working face, with the drawing carried over to the production stack | [DEVICE.md](DEVICE.md) §4 |
| 2026-09-26 | The renderer uses integer maths only | The board and the simulator must draw the same pixels, so screenshots can be compared exactly | [DEVICE.md](DEVICE.md) §6 |
| 2026-09-26 | The core is a pure state machine that returns effects, with one-second ticks | Decisions stay apart from effects, and every rule and timing is testable on a virtual clock | §3.2 |
| 2026-09-26 | One state directory per Boop; hooks call the copy of `boop-hook` kept there, and nothing is installed while that copy is missing | Hooks survive rebuilding or moving the app. Entries calling a missing file silently dropped every event while settings said "Connected" | §4.4, [ADAPTERS.md](ADAPTERS.md) §5 |
| 2026-09-27 | One brain, Jev: one request asks the mood, the reaction and the word as multiple-choice questions over a plain-text state. Apple's writer and the if-else tables are removed | Boop can only say its recorded words, so the word is a choice too; one request of about 0.25 s, with probabilities that say when Jev is guessing, replaces two models and a handoff | [harness/HARNESS.md](harness/HARNESS.md) §1, [harness/DECISIONS.md](harness/DECISIONS.md) |
| 2026-09-27 | Five events reach the brain: turn start, turn end, a notable tool use (a failure, or a pass after failures), pokes and an hourly heartbeat while nothing happens. Talk and memory writes are out for now | Tool results carry the moments worth a word ("finally" after three failed test runs); the heartbeat lets a mood go when nothing else would wake the brain | [harness/EVENTS.md](harness/EVENTS.md) |
| 2026-09-26 | No cooldowns on the brain's mumbles: apart from the poke streak's once a minute ([BEHAVIORS.md](BEHAVIORS.md) §3.3), Jev decides every time whether Boop mumbles | Fewer rules to remember; the classifiers choose silence themselves | [harness/EVENTS.md](harness/EVENTS.md) §6 |
| 2026-09-26 | Push-to-talk also starts from the popover's Talk button; the core owns the mic and turns it off after 30 s or when the link drops | There was no way to talk from the Mac, and a lost `talk_off` left the mic on until the app quit | §3.8, [BEHAVIORS.md](BEHAVIORS.md) §3.3, [UX.md](UX.md) §5 |
| 2026-09-26 | Four hero moments lead Boop's story: a cheer for a finished turn, frustration at a failed one (including one that leaves its tests failing), sadness when yelled at, annoyance at a poke streak. Past the cheer, the brain's mumbles tell them | Each has one clear cause and one clear feeling, and the device keeps its 4 states and 3 animations | [VISION.md](VISION.md), [BEHAVIORS.md](BEHAVIORS.md) §3 |
| 2026-09-27 | Being told off or yelled at makes Boop sad and never quiets it; only words with "quiet" do, asking it to stop being quiet ends quiet (`quiet(0)`), and the `quiet` action runs only the way you asked | Being mad at Boop shouldn't silence it, and asking should. Before 0 was a choice, "stop being quiet" restarted the 30 minutes | [BEHAVIORS.md](BEHAVIORS.md) §3.3 |
| 2026-09-26 | v1 is cut to 4 states and 3 animations; everything else is parked | The surface had grown past what the owner can hold in their head; features come back one at a time | [BEHAVIORS.md](BEHAVIORS.md), [FUTURE.md](FUTURE.md) |
| 2026-09-26 | The face is pixel art after the owner's reference render: window eyes, pink cheeks and small pixel mouths on a 3 px grid | The owner asked for every animation to match the reference | [UX.md](UX.md) §2 |
| 2026-09-26 | The brain's moments take turns behind the rules' and each other's, and are dropped past their `ttl` | An if-else classifier answers in 0 ms, so a brain mumble cut off the rules' cheer before it showed, and a later mumble cut off an earlier one | §3.2 |
| 2026-09-26 | Durations and gaps arrive named (short, long, very long; right after, a while, a long break) | Keep arithmetic out of the brain: Jev read "took 45 s" as quick | [harness/EVENTS.md](harness/EVENTS.md) §5 |
| 2026-09-26 | Each feeling's meaning rules out its neighbours ("sad" is only hurt; a failed turn is "annoyed") | Jev is literal: while "sad" also covered things going badly, a complaint about a build came out sad | [harness/DECISIONS.md](harness/DECISIONS.md) §3 |
| 2026-09-27 | Personalities replace modes: how much Boop speaks up is its personality file's to say, chosen in Settings | Modes picked brains, and there's one brain now; a chattier or quieter Boop is a different character | [harness/DECISIONS.md](harness/DECISIONS.md) §2.2 |
| 2026-09-26 | The new-day input and its reflection are removed; a new day only starts short-term memory fresh | Only Jev could reflect, and the if-else tables couldn't | §4, [FUTURE.md](FUTURE.md) |
| 2026-09-27 | "Needs you" clears on the asking agent's next event or a turn-level one; the hook line keeps Claude's `agent_id` | Claude gives subagents their parent's session, so a sibling's tool call cleared a request Claude was still waiting on | [ADAPTERS.md](ADAPTERS.md) §4 |
| 2026-09-27 | Without Jev's key, or when Jev fails or is late, Boop does only its automatic reactions; the evals fail without the key | Fine for everyday use, and an eval that can't ask Jev can't check it | [harness/HARNESS.md](harness/HARNESS.md) §7 |
| 2026-09-27 | Two outputs: `mood(to)`, between cheerful and grumpy, at most once every 10 minutes, and `react(feeling, word)` with five feelings; `mood` and `react` are separate questions, read as Jev chose | A mood gives Boop a longer arc than single mumbles; separate questions keep each one simple, and GUIDE asks for them to agree | [harness/DECISIONS.md](harness/DECISIONS.md) |
| 2026-09-27 | One debug mode, `--debug` (`make debug`), in the menu-bar app and headless | Seeing what Boop does took four settings and two terminals, and the menu-bar app couldn't show hooks | [harness/HARNESS.md](harness/HARNESS.md) §9 |
| 2026-09-27 | The Mac app is one popover in the device's "Warm Terminal" colours; setup and settings open inside it | A setup window was jarring, and gen-2's terracotta clashed with the device's greys and needs-you amber | [UX.md](UX.md) §7 |
| 2026-09-27 | Jev's state is plain text in five parts: an unheaded guide that opens "You are…" and ends with a generated explanation of the lines, then PERSONALITY and MOOD, all from read-only files in `plan/steering/`; then HISTORY and NOW built from a typed transcript for every pass | Jev keeps no session, so everything is rebuilt each time; named sections let each question point at what it judges by, and swapping a personality or mood is swapping a file | [harness/HARNESS.md](harness/HARNESS.md) §5, §6 |
| 2026-09-27 | A thread is named after its workspace (worktree folder or git branch), cleaned to `a-z0-9-` and 40 characters | Two agents in one project need telling apart, and an agent-chosen branch name mustn't carry words into Jev's state | [harness/EVENTS.md](harness/EVENTS.md) §3 |
| 2026-09-27 | The harness has two generic contracts. An event arrives with its line, its rule reaction and whether it wakes the brain. An action declares its questions, reads Jev's answers to them in its own body and returns `(ok, message)`; the harness records answers and results and puts successful messages in HISTORY | New behaviour is a new action, with no harness changes; the harness never reads an event's facts or an action's answers, so it stays small and generic | [harness/HARNESS.md](harness/HARNESS.md) §3, §4 |
| 2026-09-27 | Boop reads and writes Jev's key through `/usr/bin/security`, and `make sign` is gone | Without an Apple-issued certificate the Keychain knows an app only by its exact build, so every rebuild asked for the key again, even when signed with a self-made certificate. The cost: any program running as the owner, agent shells included, can read the key that way without a prompt | [harness/HARNESS.md](harness/HARNESS.md) §7 |
