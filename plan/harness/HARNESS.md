# Boop: the harness

Updated 2026-10-01. How Boop's brain runs on JHarness, the generic
multiple-choice harness in `jharness/`
([its spec](../../jharness/SPEC.md)): what Boop registers on it, how an
event becomes questions for Jev, how Jev's answers become something Boop
does, and the transcript it all comes from. What JHarness does in general
is its spec's; this says what Boop adds and chooses. The events
and their lines are in [EVENTS.md](EVENTS.md), Boop's questions and
actions in [DECISIONS.md](DECISIONS.md), and [EXAMPLE.md](EXAMPLE.md)
follows one real pass through all of it.

## 1. What this is

Boop has one brain, TypeSafe's **Jev** ([docs](https://docs.typesafe.ai/api)).
Jev doesn't write text. It reads a plain-text state and answers
multiple-choice questions, giving every option a probability, all in one
request of about 0.2–0.3 s. The **harness** around it is JHarness's
`Harness`, generic, with Boop's registrations on it:

| Boop registers | What | Where |
| --- | --- | --- |
| **Lines** ([EVENTS.md](EVENTS.md) §3–4) | A transform for each kind the brain hears of, its `wake`, and a hold: the view | `TranscriptView.register` |
| **Rules** | The core's, run on each input before the brain hears of it; the mood's change passed to the device; a tap-cut reaction ended once the pokes stop | `Pipeline`, `Runtime` |
| **Outputs** ([DECISIONS.md](DECISIONS.md)) | `mood`, JHarness's `Choice`, then `react` | `Runtime.harness` |
| **Sections** (§6) | The guide with how to read the rest, PERSONALITY, MOOD; the line that closes HISTORY; reaching back to the oldest working turn | `Runtime.harness` |
| **Timed checks** | The heartbeats ([EVENTS.md](EVENTS.md) §4) | `TranscriptView.register` |
| **The brain** (§7) | Jev, or none without a key | `Runtime.useBrain` |

The harness never reads an event's facts or an action's answers, never
picks what Boop says or talks to the device. The brain is never on the
screen's path: by the time the brain hears of an event, the core has
already updated the look and "needs you". Every reaction, a finished
turn's included, is the brain's.

### 1.1 How Boop sits on top

Nothing Boop-specific is in JHarness, and BoopKit imports it like any
app would (`import JHarness`, the `jharness` package's product). What
each of Boop's parts is on it:

| Boop | On JHarness |
| --- | --- |
| Hooks, pokes, what you say, away and back | Events Boop emits: `kind` is the type and phase (`turn_end`, `tool_wait`, `poke`, `presence_start`), and `specific_type`, `session`, `subagent` and `cwd` are in `data` ([EVENTS.md](EVENTS.md) §2) |
| The core (screen, "needs you", one-shots, the mic) | Rules: the pipeline hands the core every agent event and poke in the same batch, and the core records `did`s for its wiggle and opened threads, and `needs_you_start`/`needs_you_end` events of its own |
| The view (`TranscriptView`) | Transforms for the kinds with lines, their wakes, and holds for the gates. The agent lines need each thread's turn history: a fold of the log (`TranscriptView.Fold`) that catches up to the event it's asked about, so its answer depends on the log alone |
| Heartbeats | Timed checks. The working heartbeat's random wait is the view's own timer, reset when it sees a reaction start in the log |
| Mood | A `Choice`, its options Boop's mood graph |
| React | An output that returns `.started`, its handle finished through JHarnessLink's `do(…, pending:)`, as the app's `Reactions` reads it, when the device's `ended` comes, or when the link says none will. A reaction your tap cut short is finished `done` once the pokes stop, so HISTORY shows it in progress while they go on |
| Jev's state | Sections: the guide (with Boop's own "how to read" and words), PERSONALITY and MOOD; the closing line; reach-back to the oldest working turn |
| `debug.jsonl`, the dashboard, `boopctl day` | `onLine` and `onPass`, and the log's own lines |
| The transcript | JHarness's log, in `transcript/`; lines written before JHarness are still read (`Event.legacy`, the log's `decode`) |

## 2. Data flow

Everything but the brain call runs on `home`, the runtime's one serial
queue, which is JHarness's. Every input takes the same way, the
`Pipeline` (`app/BoopKit/App/Pipeline.swift`): in one of JHarness's
batches ([jharness/SPEC.md](../../jharness/SPEC.md) §4), it's logged (an
agent's event without the thread name, app and mode its session already
has, [EVENTS.md](EVENTS.md) §2), JHarness works out its line, the core has
it, and what the core did by rule is logged after it. Only then may the
brain hear of it.

```
 agent hooks ─► adapters ─┐
 device pokes ────────────┤
 what you say (the mic) ──┼─► Pipeline: one batch ─► JHarness's log ─► transcript/<day>.jsonl, debug.jsonl
 away and back (presence)─┘        │   each event's line (the view's transforms, EVENTS.md §3)
                                   ├─► Core ─► state ─► device link
                                   │     └─► did (wiggle, open_thread), needs_you_start/_end ─► the log
 heartbeats (the view's timed checks, on the tick) ─► the log
                                   ▼
                    JHarness's loop (jharness/SPEC.md §9): the brain free and there is one?
                      ├─ no ─► the event waits, by its wake, under 10 s old
                      ▼ yes: the next event, worked out from the log
                    its hold (EVENTS.md §6)? ─ yes ─► a `pass` with `held` ─► the next one
                           ▼ no
                    the state (§5.3, §6) + every output's questions            on `home`
                           ▼                                                   off `home`
                    Brain.answer(state, questions, 1.5 s) ──────► Jev (§7)
                           ▼                                                   back on `home`
                    a `pass` event: the answers, or why it was dropped
                           ▼ not dropped
                    each output in order: run(its own answers) ─► a `did`
                        mood  ─► the log ─► Core.setMood (the runtime's rule) ─► next `state`
                        react ─► Voice line ─► device link: a `do` (waits its turn on the device)
```

What the picture leaves out:

- **Which event goes next** is JHarness's (jharness/SPEC.md §9), by each
  kind's `wake` (`TranscriptView.wakes`): a finished turn 1 and what you
  said 2, the rest 0. So another agent's routine event can't take a
  finish's pass, and what you said goes ahead of the finishes waiting:
  the next pass is the reply, and no finish waiting ends `listening` with
  its reaction. A pass already running, or one that starts before what
  you said is logged (the mic hands its words over after it stops),
  still does: the runtime takes any reaction as the reply, and the reply
  waits behind its line. A finish that waited has its pass after the
  reply's, so its HISTORY, which holds only what came before NOW (§5.3),
  leaves out what you said and Boop's reply, while MOOD already has the
  mood the reply left. One at 0 is passed over for any newer event that
  wakes the brain, and still shows in HISTORY. The app log says
  `harness: turn_start passed over for a newer tool_end`.
- **A hold** ([EVENTS.md](EVENTS.md) §6) is asked when the event's turn
  comes: while something needs you only what you say may wake the
  brain, a tap that opened a thread doesn't, and a poke doesn't while
  Boop is answering its run. JHarness logs a `pass` with `held` and the
  reason (`something needs you`, `Boop is answering these pokes`), and
  the brain isn't asked. The app log says `brain poke 0 ms → held: …`.
- **The state and the questions are fixed when a pass starts,** so a mood
  that changes meanwhile doesn't change what it sent. An action the
  dashboard makes act meanwhile (a mood it sets, or a forced pass's
  result that's `ok`) sits that pass's answers out, since they're about
  the state from before the change: Jev's "stay happy" from a state that
  showed happy would undo the dashboard's grumpy. The app log says
  `harness: mood sat out the pass: it changed while the pass ran`.
- **After every pass,** held and dropped ones included, the runtime hears
  of it (`onPass`) and writes its app log line and its `debug.jsonl`
  lines (§9), and whether Jev is failing (§7).
- **A reaction that started something** reports its end later, on
  `home`, as its `ended` (jharness/SPEC.md §5.3). The runtime's 1 s tick
  ticks the pipeline, which ticks JHarness: it ends any left open too long
  (§5.1) and runs the heartbeats' checks.

`harness.use(brain)` swaps the brain from the next pass on; the runtime
sets it once Jev's key is read, or to none (§7). With none, nothing wakes
the brain.

## 3. Lines: the input contract

What the brain hears of an event is its **line**, which the view's
transform for its kind works out once, from the log up to it
(jharness/SPEC.md §3, [EVENTS.md](EVENTS.md) §3–4): the line, the notes
under it (your prompt, the agent's last message), and facts for the logs
and the evals. An event with no line (a tool call's start, a session
starting) is logged and read by the lines after it, but never shown.

- **The line and notes are final.** The view writes them; the harness only
  adds the time in front.
- **What Boop did** is the log's: the `did`s `for` the event, rule
  actions first, each done or in progress ([EVENTS.md](EVENTS.md) §7).
- **Whether it wakes the brain** is its kind's `wake`, and its hold when
  its turn comes ([EVENTS.md](EVENTS.md) §6). An event that doesn't
  wake the brain still gets its line in HISTORY, so the next pass knows
  it happened.
- **For debug mode and tests,** the pipeline reports each input's lines
  as `ViewEvent`s (`app/BoopKit/Core/TranscriptView.swift`): the event's
  `seq` as its `id`, its type and phase, line, notes, facts, the thread
  it's `about`, whether it woke the brain as it came, and what the rules
  did. The harness reads none of it.

## 4. Actions: the output contract

An action is one of JHarness's outputs (`jharness/Sources/JHarness/Contracts.swift`,
[jharness/SPEC.md](../../jharness/SPEC.md) §5):

```swift
protocol Action: AnyObject {
    var name: String { get }                                                 // "react"
    func questions(now: Event?, log: LogView) -> [Question]                  // built for every pass
    func run(_ answers: Answers, now: Event?, log: LogView) -> ActionResult? // its own answers; nil means "did nothing"
}

struct Question { key, text, about, judgeBy: String; options: [Option] }
struct Option   { name, what: String; notFor: String? }   // `what` is Jev's criterion
struct Answer   { choice: String; probabilities: [String: Double] }
typealias Answers = [String: Answer]                        // by question key
struct ActionResult { ok: Bool; message: String; pending: Pending?; facts: [String: JSONValue] } // ok: its line in HISTORY; not ok: why

// .done(message), .failed(why), or .started(message, pending): begun, and ends later
final class Pending {
    enum End { case done, failed(String) }  // failed: why it never happened
    func finish(_ end: End)                  // on `home`; only the first call counts
}
```

**What the harness guarantees an action:**

- Its questions go in the same request as every other action's, on
  every pass. Keys are unique across all actions; the harness won't
  start a pass otherwise.
- It gets the answers to its own questions and no others. From Jev
  that's all of them, since an answer missing one is dropped whole (§7).
- It gets the event the pass answers (`now`, nil for a forced pass), so
  `react`'s finish names the thread NOW is about, and the log.
- Actions run one at a time, in registration order, on `home`. A body
  with slow work hands it off and returns at once. One that takes over
  **300 ms** (`Harness.Options.actionSlowMs`) is logged, since it holds
  up everything behind it.
- A result becomes a `did` in the transcript ([EVENTS.md](EVENTS.md)
  §2), `for` the event, `by` `brain`; `nil` records nothing. The
  result's `facts`, for the tools, join the `did`'s data as they are
  (JHarness's own keys win a clash); the harness never reads them.
- A successful result's message becomes its line in HISTORY, indented
  under the event it answered. A failed one is logged but never shown
  to Jev, because Boop didn't do anything.
- **A started result** (`.started(message, pending)`) is for something
  that plays out after `run` returns, such as a moment on the device. The
  action, or whatever it hands the `Pending` to (`react` hands it on with
  its moment, [DECISIONS.md](DECISIONS.md) §5), finishes it when it knows
  how things went: `done`, or `failed` with why it never happened. Until
  then HISTORY shows its line as in progress (§5.3). Its end is its
  `ended`. An end that comes before the harness has logged the result is
  kept and logged right after it. A result that's done, failed or `nil`
  has no end to wait for.

**An action owns** its questions and their wording, how it reads its
answers (which choice means "do nothing", any probability floor), its own
rules, its dependencies (passed in when it's made), its effect and its
message. Adding one is writing those and registering it in
`Runtime.harness`; nothing else changes.

## 5. The transcript

### 5.1 Keeping it

| Recorded | By |
| --- | --- |
| An agent's hook, as its adapter maps it | The pipeline, as it arrives, before the core has it |
| A poke | The pipeline, before the core has it |
| What you said on push-to-talk | The pipeline, once the mic is off and macOS has turned it into words |
| A heartbeat | JHarness's tick, when the view's check says one is due |
| A rule's action (`wiggle`, `open_thread`) and "needs you" (`needs_you_start`, `needs_you_end`) | The core, as an effect of the event that caused it, logged right after that event |
| A pass, an action's result, and a started one's end | JHarness, as the pass ends, right after the action runs, and when the end reaches it or it's left open too long (below) |
| The dashboard's forced passes and actions | JHarness, `by` `dashboard`, for no event |

- **Append-only.** Each event gets the next `seq`, which counts on across
  days and launches, and is never changed.
- **It's JHarness's log** ([jharness/SPEC.md](../../jharness/SPEC.md)
  §2.3, `Transcript.log`). On disk, one file a day:
  `<state-dir>/transcript/<date>.jsonl` (`Transcript.folderName`), the
  day in Boop's time zone, each event its line, written as it's appended.
  Files older than **14 days** (`Transcript.keptDays`, today included)
  are deleted at launch and at each new day
  ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.2), so an app left running
  for weeks keeps no more. The last **24 hours** of events stay in
  memory (`Log.Options.keepMs`). A launch reads them back
  (`Pipeline.readBack`): JHarness works out every event's line in order,
  and the core folds them, so turn numbers, failure runs, the sessions,
  a request still waiting and the mood carry on. A line that doesn't
  parse, such as one a crash cut short, is skipped (a file that ends
  mid-line is ended there first, so the next line written isn't glued to
  it; a cut inside a character spoils only that line), and `seq` goes on
  from the newest file's last event. A line written before JHarness
  is read as the event it would be now ([EVENTS.md](EVENTS.md) §2). A
  transcript with no folder (the evals, tests) is in memory only.
- **A started action that was still in progress** when the last launch
  quit can't end now, since its handle went with that launch, so the
  launch records its end as failed, `restarted`.
- **Debug mode** also writes each event to `debug.jsonl` (§9).
- **Privacy.** Your prompt, the agent's last message and what you say
  to Boop on push-to-talk are the only words in it
  ([EVENTS.md](EVENTS.md) §9).
- **Started actions stay open** until their end is recorded: open, and
  no `ended` for it yet, which JHarness works out from the log. Only the
  first end of each counts. One still open **90 s**
  (`ReactAction.openForMs`, react's `openFor`) after its result is ended
  as failed with `no word it finished`, on the tick, unless it's a
  reaction your tap cut short that the pokes still hold (react's
  `keepOpen`, [DECISIONS.md](DECISIONS.md) §5), and the app log says
  `harness: <name> was still in progress after <N> ms; ended it`. So
  HISTORY never says in progress for good, whatever the action forgot.
  The ceiling sits past the link's own give-up on a reaction's `ended`,
  its 5 s `ttl` plus 60 s, 65 s in all, and the longest reaction the
  device plays, held four times in the design with the longest loop of
  the 13 moods (wounded's idle, 13 s: 52 s), ends before the link gives
  up ([DECISIONS.md](DECISIONS.md) §5, `RuntimeTests`).

### 5.2 Passes

Every pass is a `pass` event ([jharness/SPEC.md](../../jharness/SPEC.md)
§2.2): `for` (the event it answered, or null for a forced one), `brain`
(the brain it asked, or would have) or `by` (who forced it), `answers`
(each question's `choice`, and `p`, every option's probability to three
places), `dropped` (why no action ran, or null), `held` (why the event
was held back, when it was) and `ms`. An event with a `pass` is never
asked about again. Debug mode's `pass` line has more (§9).

### 5.3 The text form

JHarness builds the state's HISTORY and NOW for each pass
([jharness/SPEC.md](../../jharness/SPEC.md) §7.2). It's a pure function of
the log, the sections and the clock, so a logged pass can be rebuilt
exactly from the log up to its `seen` (§9): its state is the `head` line
before it and its own `state`. An action's end recorded while Jev
answered lands in the log before the pass line, but the state was built
when the pass started, without it, and `seen` leaves it out. JHarness
places lines, notes and actions' messages and never writes them, apart
from marking a started action's progress (step 3).

1. **NOW** is the event the pass is for.
2. **HISTORY's events** are those with a line before NOW, from the last
   **10 minutes** (`Harness.Options.historyMs`) or since the oldest turn
   still working began (Boop's `reachBack`), whichever reaches further
   back, then at most the newest **40** (`historyLimit`), and any older
   one in that time whose started action is still in progress (step 3),
   so a pass sees what Boop is still doing however many events came
   since. JHarness ends a started action within a minute and a half
   (§5.1), so few ever stay.
3. **Under each** go its notes, then what Boop did: its `did` lines in
   order, rule actions and the brain's. A started one's message ends in
   ` (in progress)` until its end; after that it's plain if it was done,
   and left out if it didn't happen, so HISTORY shows only what Boop did
   or is doing. A forced action counts as done about the latest event
   with a line before it.
4. **Each event** is written oldest first as `<when>: <line>`, with
   `<when>` relative to now: `just now` under a minute, then `N min
   ago`, then `N h ago`. Its notes and what Boop did follow, indented two
   spaces, one line each.
5. **HISTORY closes** with Boop's closing line, if any: how long Boop
   has been in a mood other than calm, the resting mood, from the mood's
   latest change in the log ([DECISIONS.md](DECISIONS.md) §4), which the
   moods' fades are read against:

   ```
   Boop has been grumpy for under a minute.
   ```
6. **NOW** is a heading with the time and weekday, NOW's line and notes,
   then what the rules did about it or `Boop did nothing on its own.`

## 6. The state

One plain-text document in five parts, always in this order, built
fresh for every pass since Jev keeps no session:

| Part | Kind | Source |
| --- | --- | --- |
| The guide (no heading) | Static, then generated | [steering/guide.md](../steering/guide.md), then how to read HISTORY and NOW (§6.1) |
| `PERSONALITY` | Static, the one chosen in Settings | `plan/steering/personality/<name>.md` ([boop](../steering/personality/boop.md), [chatter](../steering/personality/chatter.md)) |
| `MOOD` | Static, the current mood's | `plan/steering/mood/<mood>.md` ([calm](../steering/mood/calm.md), …, one for each of the 13 moods), the mood the log has at each pass |
| `HISTORY (oldest first; indented lines add to the line above)` | Built by JHarness | The lines, what Boop did, and the closing line (§5.3) |
| `NOW (14:23, Tuesday)` | Built by JHarness | The event this pass is for (§5.3) |

The guide and its generated part are joined by single line breaks; the
other parts follow, each after a blank line. The first three are the
JHarness's sections, which Boop registers in `Runtime.harness` (for the app
and the evals alike) with the line that closes HISTORY, how far back it
reaches (the view's oldest working turn) and NOW's heading, in Boop's
time zone. Boop places its own "how to read" in the guide's section, so
JHarness's is off (`Harness.Options.reading`). The harness never reads
any of them.

**The steering files** are read once at launch from the app's bundled
copy of `plan/steering/` (`Steering`), and never written. HTML comments
are left out. A personality's front matter goes to the core's rules
([BEHAVIORS.md](../BEHAVIORS.md) §6) and never reaches Jev. A missing
file stops the app from starting, and an unknown mood reads as calm's
file. What the files say is [DECISIONS.md](DECISIONS.md) §2.

### 6.1 How to read HISTORY and NOW

The guide ends with an explanation of the format, kept next to the code
that builds it, so the two can't drift. The layout part is Boop's own
words for JHarness's layout (`EventLine.reading`); the words part is the
events' ([EVENTS.md](EVENTS.md) §8.1):

```
How to read HISTORY and NOW:
- HISTORY is oldest first. Each line says how long ago it happened.
  Lines indented under it add to it: an agent's last message, then
  what Boop did. A line of what Boop did ending in (in progress)
  hasn't finished yet.
- NOW is what to react to. Its last line is what Boop already did on
  its own, by reflex.
[EVENTS.md §8.1]
```

### 6.2 Sizes

Each static part has a budget in tokens (`Steering.Budget`), counted as
bytes ÷ 4, which overestimates English: the guide 300 (now 297), a
personality 750 (`boop` 726, `chatter` 491), raised from 600 when `boop` took what you say to it and its Examples ([BEHAVIORS.md](../BEHAVIORS.md) §3.3), and from 700 when it took coming back to the Mac ([EVENTS.md](EVENTS.md) §2.1), and a mood 175 (the 13 files 123–175), raised from 150 when the moods took four reasons from the notes ([DECISIONS.md](DECISIONS.md) §2.3): Jev reads only the current mood's file, so it costs at most 25 tokens a request.
A part over its budget is logged at launch (`steering: over budget: …`),
and a test keeps every file within it. The generated reading part is
about 200 tokens and HISTORY's 40 lines about 1,200, and each
prompt, last message or thing you said quoted in one adds up to about
80 more (300 characters). With the questions a request is about 4,100 tokens with
nothing quoted, and could reach about 7,200 in the worst case, every one
of the 40 quoting 300 characters: the 13 moods' faces, the finish's
outcomes and a `mood` question of up to nine options (a mood with eight
moves, and staying) added about 700 to the questions. The evals' states came to 1,000–1,550,
and a busy working day's ([EVALS.md](../EVALS.md) §5) to 1,250–2,100,
before prompts and last messages were quoted.

## 7. Asking Jev

**The request and the answer** are JHarness's `JevBrain`'s
([jharness/SPEC.md](../../jharness/SPEC.md) §8): one request with the
state and every action's questions, each answered on its own against
the state, with one retry on a busy or failing server.
[EXAMPLE.md](EXAMPLE.md) §5 shows one, built from a real pass.

**The deadline** for the whole pass is JHarness's default, **1.5 s**
(`Harness.Options.deadlineMs`), which Boop keeps: about five times Jev's
usual time, with room for one retry and for a slower first answer on
steering Jev hasn't seen. There's no warm-up pass. Its timer fires within
5 ms of it (`deadlineLeewayMs`): the system's default leeway would let it
fire up to 7% late. The HTTP request's own timeout, 2 s, is cut off by it
first.

**A dropped pass** runs no action, so Boop does only its rule
reactions. The `pass` line's `dropped` says why:

| `dropped` | When |
| --- | --- |
| `late: no answer within 1500 ms` | The deadline passed. The pass's `latency_ms` is then the deadline's, not the brain's, so the request goes on to its end (the HTTP timeout at most), off the pass, and the app log says when it came: `harness: jev:jev-latest answered after 1702 ms, too late for the turn_start pass`, with `: ` and why if it failed. Its answer is thrown away |
| `jev: HTTP <status>`, `jev: can't reach the server`, `jev: no answers`, `jev: no usable answer for <key>` | Jev failed, or its answer couldn't be used ([jharness/SPEC.md](../../jharness/SPEC.md) §8 says when each). Each counts toward "Jev isn't answering", the Mac offline included |
| `question keys must be unique across outputs: <key> asked twice` | Two questions shared a key, so nothing was asked. Boop's seven keys are fixed and unique ([DECISIONS.md](DECISIONS.md) §3), so it never happens |
| `cancelled`, or an error's own text | The pass's task was cancelled, or the request failed some other way |

A pass held back when its event's turn came (`held`, §2) never asked Jev
and isn't dropped: its line says `held` and why, and has no state.

**When Jev keeps failing, the popover says so.** The runtime counts the
passes that asked Jev and dropped in a row (`Runtime.trouble`, a
`BrainTrouble`), and the Overview pane shows a "Jev isn't answering"
notice with the reason. An HTTP 401 or 403 (the key) or 402 (out of
credit) shows it at once, since only the person can fix those; anything
else shows it after **3** in a row (`BrainTrouble.showAfter`), so one
slow answer doesn't. The next pass that runs clears it, and so does a new
key. A pass that never asked Jev (one held back) doesn't count,
and neither does one that asked it with the key before, which may end
after a new key is saved or the key is cleared.

**The key** comes from `BOOP_JEV_KEY`, else, in the menu-bar app only,
the Keychain, which Boop reads through `/usr/bin/security`
([ARCHITECTURE.md](../ARCHITECTURE.md) §11). `Boop --headless` and
`boopdev` read only the variable, so a run from an agent shell never
uses the owner's key. Every read, Settings' included, goes through the
runtime's `readJevKey` option, so tests and headless runs decide it. The runtime reads it off `home` and the main
thread, since a Keychain prompt would stall both. Until it's read, and
without one, there's no brain: no event wakes it
([EVENTS.md](EVENTS.md) §6), and nothing reacts to what agents do. A key saved in Settings takes effect
from the next event.

**The brains:**

| Brain | `id` | Used by |
| --- | --- | --- |
| `JevBrain` | `jev:jev-latest` | The app with a key, and the evals |
| `ScriptedBrain` | `scripted` | Tests: a script sees the state and questions and returns answers. `Boop --headless --brain scripted` uses `pipelineCheck`, which answers every pass with the mood kept (the `mood` question's first option), `react.mood: excited`, `react.loops: once`, `say.feeling: none`, `say.about: start`, `say.kind: word` (an excited start: "Go" or the like), and `react.animation: success` when NOW is a turn finished done, `failure` when one finished failed, else `none`; an answer a question doesn't offer is its first option |

## 8. Designing for Jev

Jev is literal and small: good at judging a short, clearly labelled
state against clear options, bad at arithmetic and at reading between
the lines. Events, questions and steering files all follow these rules
(the evidence is in [ARCHITECTURE.md](../ARCHITECTURE.md) §11):

- **Named sections,** and every question says which it's about and
  which to judge by.
- **The format explained once,** at the end of the guide, by the code
  that builds it.
- **Examples in the state's own lines,** so Jev compares like with like.
- **No arithmetic:** relative times, named bands for durations and gaps
  ([EVENTS.md](EVENTS.md) §5), small counts, and facts worked out
  beforehand rather than left for Jev to count.
- **One question per decision,** with the full list of options, each
  saying what it's not when two are easily confused.

## 9. Logging and debug mode

**The app log** (`boop.log`) gets one line per pass that asked the brain
or was held back, debug mode or not: `brain <type and phase> <ms> ms →
<result>`, where `<result>` is the actions that returned something
(`mood, react`, with ` (failed)` after a failed one), `nothing`,
`dropped: <why>` or `held: <why>`. It never holds an action's message or
the state. JHarness also logs an event passed over for a newer one, a
dropped or held pass, when the brain answered a pass it was late for
(§7), an action that sat a pass out (§2), a slow action, an unusable
answer's size, forced answers it left out, and a started action it ended
for staying open too long (§5.1), each starting `harness: `.

**Debug mode** is `Boop --debug`, in the menu-bar app (`make debug`) or
headless. It prints to the terminal that started the app: each hook with
what the adapter made of it, every line sent to the device, and each
event with a line, pass and action, readably. From a headless run with the
scripted brain and no device (`--link none`), as `boopdev watch` prints
its `debug.jsonl`:

```
▸ 1 turn start: claude started turn 1 on "jetpack".
    You asked: "PRIVATE_PROMPT_7001 fix the flaky test"
  pass scripted 1 ms: mood calm 1.00 · react.animation none 1.00 · react.loops once 1.00 · react.mood excited 1.00 · say.about start 1.00 · say.feeling none 1.00 · say.kind word 1.00
    │ <the whole state for the first pass, then only its HISTORY and NOW>
  … react: Boop made an excited face, held once, and said "Andiamo".
  ✗ react (3) didn't happen: no device connected
  … needs_you (rule): Boop showed that claude needs you.
▸ 7 tool wait (no pass): claude needs you on "jetpack".
  · needs_you (rule) ended
```

Each event with a line is marked `▸` with its `seq`; one that doesn't
wake the brain is marked `(no pass)`, and a failed action `✗`. A started
action is marked `…`, and its end prints as a line of its own when it
comes, naming the action and its `seq`: `  ✓ react (15) done`, or
`  ✗ react (15) didn't happen: <why>`. A rule's action is marked
`(rule)`, and a pass held back says `held: <why>`. Of the raw events
only actions print: the lines say the rest. (The eval's queue ends a reaction at once,
`done` unless its step says otherwise, [EVALS.md](../EVALS.md) §1.) The
state goes to the terminal only, never `boop.log`.

**`debug.jsonl`,** in the state directory, is emptied in place at every
launch. Before emptying it, the app keeps a copy of the last launch's
lines as `debug.1.jsonl`, moving older copies up to `debug.10.jsonl`
(`DebugLog.keptLaunches`) and letting the oldest go, so relaunching
mid-day doesn't lose the morning. An empty file isn't kept.
`boopdev watch [FILE]` prints it as the terminal does, following it as it
grows. Each line has one kind and `received_at_ms`, the app's clock,
which headless `advance` moves:

| Line | When | Holds |
| --- | --- | --- |
| `event` | Every event the transcript records ([EVENTS.md](EVENTS.md) §2), passes included. What a pass's actions did waits for its `pass` line, so it comes after it (`DebugLog.Writer`) | The event, as its transcript line |
| `view` | Every event with a line, once its input is done (§3) | `id` (the event's `seq`), `type`, `phase`, `from`, `line`, `notes`, `wakes_brain` (as it came) and `facts` |
| `pass` | Every pass (§5.2), dropped and held ones included | `for`, `now` (the event's `id`, `type`, `phase` and `line`), `answers`, `dropped` and `latency_ms`. A Jev pass also has `state` (the state sent, from its HISTORY on: the rest is the `head` line before it), `questions` (the keys asked, in order), `brain` (its `id`) and `seen` (the transcript's last `seq` when its state was built, so a rebuild reads the log up to it, §5.3). A held one has `held` (why) and `brain`, and no `state`. A forced pass has `questions` (the keys it answered) and `by`, and no `state` or `brain`. Any has `options`, the option names it asked by key, for the questions whose options differ from the `questions` line's |
| `head` | Before a Jev pass whose state's head differs from the last `head` line's: the launch's first, and after a new personality or mood | The head, as a string: the state up to HISTORY, that is the guide, PERSONALITY and MOOD (§6), which the passes after it share. `boopdev watch` and the terminal print it with the first pass; `watch --new` prints the latest one before the end of the file with the first pass it shows |
| `questions` | As the file's first line, before the launch's read-back's lines (whose ends of actions left in progress are events, §5.1), the socket's or the link's: the questions as they stand at launch, once the log is read back. A pass that asked other options, such as the mood's moves once it has moved, names them itself (`options`, below) | Every action's questions in order: `action`, `key`, `text`, and each option's `name`, `what` and `not_for` |
| `sent` | Every line sent to the device, whatever the link, none included | The line, verbatim ([PROTOCOL.md](../PROTOCOL.md) §3, and the link's `{"t":"hello"}` asking for the device's own, [ARCHITECTURE.md](../ARCHITECTURE.md) §3.7), and beside it `by`: `brain` for the brain's reactions (a forced pass's included), `rule` for everything else, states included. `boop.log`'s `link brain →` and `link rules →` in debug mode say the same, but for a `state` the same as the last one sent (the 10 s keepalive, a reply to `hello`), which only `debug.jsonl` keeps: the dashboard reads it as a sign the app is running. A `do` goes only to a device that's connected and has said `hello`. `{"sent":{"t":"do","id":1044930537,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"phase1.nonverbal.delight.mm-hm__proud__contained"},"mood":"proud","loops":2}},"by":"brain","received_at_ms":1790777600448}` |
| `ended` | Every `ended` the device sends ([linkkit/SPEC.md](../../linkkit/SPEC.md) §4): the device decides what plays, so a `do` sent may have been skipped | `id` (the `do`'s), `how` (`done`, `cut` or `skipped`) and `why` when there is one. `boop.log`'s `device: do N ended …` says the same. `{"ended":{"how":"skipped","id":1,"why":"busy"},"received_at_ms":9}` |
| `status` | When the personality, the brain, the sessions or the connection changes | `personality`, `brain` (an `id`, or `none`), `sessions` (`agent`, `project`, `status`) and `connected`; the mood is in `sent`'s `state` |

The last four are for the dashboard (`internal/tools/boopctl dash`),
which marks a rule's one-shot the device skipped on its reflex;
the terminal and `boopdev watch` skip them. What a reaction said is the
`takes` its action's start records, the ones Voice picked
([VOICE.md](../VOICE.md) §4, [EVENTS.md](EVENTS.md) §2); the dashboard
and `boopctl workday` read them there.

**Dev lines.** Headless, or in debug mode, the hook socket also takes
`{"dev":…}` lines; plain `make run` ignores them. Nothing replies: what a
line did shows in `debug.jsonl`. Any other `dev` value is ignored.

| Line | Does |
| --- | --- |
| `{"dev":"advance","ms":N}` | Headless only: moves the app's clock forward N ms, then ticks |
| `{"dev":"answer","answers":{"react.mood":"grumpy","say.about":"work"}}` | A **forced pass**: each choice at probability 1, handed to the actions exactly as Jev's answers would be. It runs at once on `home`, needs no brain or key, and leaves a running or waiting pass alone. A choice that isn't one of its question's options is left out. The actions keep their own rules. Logged as a `pass` line, and its actions recorded `by` `dashboard`, for no event; no `brain` line in `boop.log` |
| `{"dev":"mood","mood":"grumpy"}` | Sets the mood at once through the mood action, device included ([DECISIONS.md](DECISIONS.md) §4). Recorded as a `did` of `mood`, for no event, `by` `dashboard`, refusals included |
| `{"dev":"listen","on":true}` | The popover's Talk button: the mic on (`true`) or off, as clicking it does ([BEHAVIORS.md](../BEHAVIORS.md) §3.3). With no mic (headless) turning it off hears nothing |
| `{"dev":"said","words":"are the tests passing?","by":"device"}` | What push-to-talk heard, with no mic: recorded as a `talk` event after `by`'s button (`app` unless it says), whose pass replies or ends `listening` ([EVENTS.md](EVENTS.md) §2) |
| `{"dev":"tap"}` | A tap on the board, with no board and never on a finish: a poke, or while something needs you, the waiting thread opened on the Mac ([BEHAVIORS.md](../BEHAVIORS.md) §3.2; headless `--no-open` only logs where) |
| `{"dev":"presence","signal":"locked"}` | Headless only: a signal from the Mac to the presence detector, `locked`, `unlocked`, `asleep` or `woke`, as macOS's notification would send; what it records, if anything, is the detector's call on the next tick ([EVENTS.md](EVENTS.md) §2.1) |
| `{"dev":"presence","idle_ms":1800000}` | Headless only: the Mac's idle time the detector reads from the next tick on, in place of the real one, which headless never reads (0 until a line sets it). With `advance` it tests the idle away |
| `{"dev":"report"}` | Saves a bug report, as the button does (below) |

A forced pass that plays a finish: the pass's event, its `pass` line,
the action and the action's end, from a headless run with no device
(`--link none`), so the reaction never played
([DECISIONS.md](DECISIONS.md) §5):

```jsonl
{"event":{"seq":1,"at":1790764089883,"source":"self","kind":"pass","data":{"answers":{"react.animation":{"choice":"success","p":{"success":1}},"react.loops":{"choice":"twice","p":{"twice":1}},"react.mood":{"choice":"proud","p":{"proud":1}},"say.feeling":{"choice":"glad","p":{"glad":1}},"say.kind":{"choice":"phrase","p":{"phrase":1}}},"by":"dashboard","dropped":null,"for":null,"ms":0}},"received_at_ms":1790764089883}
{"pass":{"answers":{"react.animation":{"choice":"success","p":{"success":1}},"react.loops":{"choice":"twice","p":{"twice":1}},"react.mood":{"choice":"proud","p":{"proud":1}},"say.feeling":{"choice":"glad","p":{"glad":1}},"say.kind":{"choice":"phrase","p":{"phrase":1}}},"by":"dashboard","dropped":null,"for":null,"latency_ms":0,"questions":["react.mood","react.animation","react.loops","say.feeling","say.kind"]},"received_at_ms":1790764089914}
{"event":{"seq":2,"at":1790764089913,"source":"self","kind":"did","data":{"action":"react","by":"dashboard","for":null,"latency_ms":27,"message":"Boop played a success in a proud face, held twice, and said \"Smooth operator\".","ok":true,"open":true,"takes":["phase1.phrase.pride.smooth-operator__proud__contained"]}},"received_at_ms":1790764089913}
{"event":{"seq":3,"at":1790764089913,"source":"self","kind":"ended","data":{"action":"react","by":"dashboard","for":2,"outcome":"failed","why":"no device connected"}},"received_at_ms":1790764089913}
```

**A bug report.** The ladybug button in the popover's footer (⌘B)
saves everything needed to work out afterwards what Boop saw and did
this launch, debug mode or not, then shows it in Finder and copies its
path, to hand to an agent. For that, outside debug mode the app keeps
this launch's `debug.jsonl` lines in memory (`DebugLog.Recent`), states
and all, up to 8 MB of them, the oldest let go first, as their bytes
alone in one buffer taken once; they go nowhere until the button is
pressed. In debug mode the file already has them, so none are kept. The
report is a new folder,
`bug-reports/<yyyy-MM-dd-HHmmss>/` in the state directory (the
transcript's own files are beside it, in `transcript/`, §5.1):

| File | Holds |
| --- | --- |
| `debug.jsonl` | Those lines, or in debug mode the file's last 8 MB from the start of a line, in the format above, so `boopdev watch` prints it. When the launch's `questions` line and the `head` line in force where they start come before them, those two come first |
| `boop.log` | The log's last megabyte, from the start of a line: events passed over, late answers, actions that sat a pass out |
| `settings.json` | A copy, when it exists. The mood is the transcript's ([DECISIONS.md](DECISIONS.md) §4) |
| `about.json` | The app's and firmware's versions (and `device_trouble`, why the device connected gets no `do`, when its firmware doesn't fit), the link, whether it's connected, debug mode, the personality, mood, brain and sessions, and when it was taken (`taken_at_ms` on the app's clock, `taken_at_wall_ms`) |

**A day's summary.** `boopctl day` (`make day` for the everyday app,
[VERIFICATION.md](../VERIFICATION.md) §2) reads `debug.jsonl` and the
kept launches', oldest first, and sums up one local day by the hour from
the lines alone:

| It counts | From |
| --- | --- |
| Finishes, and working chatter in older logs | A `sent` `do` named `task_complete` or `reply_ready` (a `moment` with that `anim` in logs from before the device took turns), the brain's since 2026-09-29, unless its `ended` says the device skipped it or something other than your tap cut it, or `cheer`, as older logs have it (the brain's from 2026-09-28; older logs also have ones the dashboard played, which only their `sent` line records); and the rules' chatter: a `sent` moment with a `say` whose `by` is `rule`, or, in logs from before `by`, a `say` without a `mood` |
| The brain's reactions, and their faces | A `react` action for a Jev pass, started or refused, in the face its pass's `react.mood` answer chose (`react` in older logs). Those `by` the dashboard were forced, and are counted apart |
| Alerts, and each time something needed you | A `sent` state whose `attn` is new, or has a different `id`, agent or project ([PROTOCOL.md](../PROTOCOL.md) §3; a missing `id` reads as 0). Needing you lasts from the `state` that brings `attn` to the first without it, or to the end of its launch |
| Mood changes, and what made each | A `sent` state's `mood`, and the `mood` action right after it: the event it was for, or `by` the dashboard. A launch's first `state` in a mood other than the last launch's changed between launches |
| Brain passes, dropped ones, and ones that chose `none` | `pass` lines with a `brain`; forced ones and held ones (`held`, which asked no brain) are counted apart. The median and slowest times are of the passes answered in time, since a dropped pass's `latency_ms` is the deadline's (§7). An event that woke the brain with no `pass` for it was passed over for a newer one while a pass ran |
| Reactions that didn't happen, and why | A `react` action with `ok: false` (its message is the reason), or an action's `end` that isn't `done` (its `why`); the forced ones apart |
| Pokes | `poke` `view` lines |
| Time running, and with the device connected | Each launch's first and last lines, and `status` lines' `connected` |

## 10. Where it lives

| Part | File | Job |
| --- | --- | --- |
| JHarness | `jharness/Sources/JHarness/` ([jharness/SPEC.md](../../jharness/SPEC.md)) | The log, lines, rules, outputs, the prompt, the loop, the tick; `respond(to:)`, one event straight through for the evals |
| Contracts | `jharness/Sources/JHarness/Contracts.swift`, `jharness/Sources/JHarness/Event.swift`, `app/BoopKit/Core/Event.swift` | `Action`, `Question`, `Option`, `Answer`, `ActionResult`, `Pending`, `JSONValue`; `Event`, and Boop's reading of it |
| Transcript | `app/BoopKit/Harness/Transcript.swift` | JHarness's log in the state directory, with the older lines read |
| Pipeline | `app/BoopKit/App/Pipeline.swift` | Each input in one batch: logged, its line, the core's rules; the view events it made, for debug mode and tests |
| The view | `app/BoopKit/Core/TranscriptView.swift` | Boop's lines, wakes, holds and heartbeats, registered on JHarness ([EVENTS.md](EVENTS.md)) |
| Steering | `jharness/Sources/JHarness/Steering.swift`, `app/BoopKit/Harness/Steering.swift` | JHarness's folder of Markdown; Boop's parts of it, read-only, and their budgets |
| Brain | `jharness/Sources/JHarness/Brain.swift`, `jharness/Sources/JHarness/JevBrain.swift`, `app/BoopKit/Brains/` | The `Brain` protocol and `ScriptedBrain`, and Jev, in JHarness; Jev's key and the pipeline check's scripted answers, Boop's |
| Debug log | `app/BoopKit/Harness/DebugLog.swift` | The `debug.jsonl` lines in order (`Writer`), and printing them readably, an action's end by its name |
| Wiring | `app/BoopKit/App/Runtime.swift` | Registers the outputs and sections (`Runtime.harness`), the mood's and the tap's rules, reads the key, takes dev lines, reads the transcript back, ticks the pipeline every second, and hears every pass (`passed`) |
| Rule actions | `app/BoopKit/Core/Core.swift` | The wiggle, opened threads and "needs you" ([EVENTS.md](EVENTS.md) §2) |
| Actions | `app/BoopKit/Actions/` | [DECISIONS.md](DECISIONS.md) |
