# Boop: behaviors

```
BOOP — HOW IT WORKS
═══════════════════════════════════════════════════════════════════════

  SCREEN  =  MOOD  ×  VISUAL        (a visual, acted out in a mood)

MOODS  (how Boop acts; a step at a time along the mood graph, fading
        a step toward calm after the minutes shown)
───────────────────────────────────────────────────────────────────────
  calm        settled, at rest; the default
  happy       good spirits: things are going well                10 min
  excited     a very long turn (5+ min) ended done, or thanks     5 min
  proud       a check passed after failing, hard work done        5 min
  curious     a poke, something new said to Boop                  2 min
  engaged     in the flow of steady work                          5 min
  determined  rooting for a retry, or a very long grind           5 min
  annoyed     one thing failed, or 2 pokes in a row               3 min
  irritated   failures or pokes keep coming                       3 min
  grumpy      a failed turn on top of trouble, or 4+ pokes        2 min
  whiny       sorry for itself: things keep going wrong           5 min
  wounded     hurt: rude words, or a big failure                 10 min
  sad         a very long turn ended failed, the agent gave      10 min
              up, or sad news you shared

VISUALS  (what Boop is doing)
───────────────────────────────────────────────────────────────────────
  asleep      no agent sessions open               ┐
  idle        sessions open, none working          │ states: always
  working     an agent is working, and at what:    │ reflect the truth
              testing · delegating · terminal ·    │
              searching · analyzing · tool_use ·   │
              waiting · planning, or plain working │
  needs you   an agent awaits your approval        │
  no app      device lost the Mac (30 s)           ┘
  starting    a session or a new task begins       ┐ the rules'
  stopped     you interrupted a turn               │ one-shots: once,
  error       a command failed                     │ at once
  helper      a helper came back                   ┘
  finish      task_complete or reply_ready (Jev)   ┐ animations:
  poked       a tap; from the 3rd in a row,        │ play for a moment
              tap_spam                             │
  listening   push-to-talk: mic on until the reply ┘

  Each mood × visual has a few variations, as its designs have. The
  Mac picks one at random each time the visual changes, never the last,
  and again when a new mood has fewer of it; then the device's looks
  take turns between them at loop ends.


AUTOMATIC  (plain rules, instant, no brain needed)
═══════════════════════════════════════════════════════════════════════
  • The agents' activity picks the state visual:
      asleep / idle / working / needs you / no app, and while working,
      what at: the running tool's (testing, a terminal…), §2
  • Starts, interrupts, failed commands and returning helpers play
    their one-shot at once (§3.1)
  • Needs you wins over everything: amber light, its alert, who's asking
  • A poke (a tap on the device) → the device plays its poke at once
  • Hold BOOT (or click Talk) → the Mac's mic listens, Boop shows
    listening until the reply
  • Needs you and no app are never Jev's to show


JEV  (the brain; decides everything expressive)
═══════════════════════════════════════════════════════════════════════
  Asked on view events:  turn start/end · tests/build/deploy fail or
                         pass · a poke · what you say to Boop ·
                         heartbeat (quiet work, or an idle hour)

  One request, multiple choice:

  SHIFT MOOD    mood             stay | a neighbour lasts; restyles all
  ─────────────────────────────────────────────────────────────────────
  REACT         react.mood       none | a mood      the face, or nothing
  (a moment)    react.animation  none | success |   a turn's finish,
                                 failure | reply    judged from its text
                react.loops      once … 4 times     how long it holds
  ─────────────────────────────────────────────────────────────────────
  SAY           say.feeling      none | upset |     how it feels
                                 glad | tickled
                say.about        none | tests,      what NOW is about
                                 work, …
                say.kind         sound | word |     how big, the nearest
                                 phrase | swear     kind when there's none
                → up to two recorded takes in the face's mood, the
                  feeling's then the topic's, or silence

  e.g. a failed turn that stings:
       mood → grumpy;  react: irritated, failure, once, "Shit"
  e.g. a 5 s routine turn:  nothing


WHAT JEV SEES  (built fresh for every ask; Jev keeps no memory)
═══════════════════════════════════════════════════════════════════════
  Every event is recorded raw in the transcript; the view folds them
  into view events, each with a line (harness/EVENTS.md).

  NOW       the view event being asked about, its notes, then what Boop
            did by reflex
  HISTORY   earlier view events, oldest first: the last 10 min, or back
            to the oldest turn still working, at most 40. Notes and what
            Boop did sit indented under each. Times: just now · 5 min
            ago · 2 h

  One HISTORY entry, piece by piece (a 6-minute turn ending; one line
  each in the state):

    just now: claude finished turn 9 on "api": done, a very long turn,
      40 tool calls.
      Its last message: "All 212 tests pass now."
      Boop's mood changed: determined → excited.
      Boop played a success in an excited face, held three times, and
        said "Bada bing bada boom". (in progress)

    piece                       what it is                   added by
    just now                    when, relative to now        harness
    claude finished turn 9      the agent, and which turn    view
    on "api"                    the thread (here, a project) view
    done                        outcome                      view
    a very long turn            length                       view
    40 tool calls               the turn's tool calls        view
    Its last message: "…"       the agent's words, cut short view
    Boop's mood changed: …      what the mood action did     mood
    Boop played … "…yay!"       what the react action did    react
    (in progress)               the reaction's state         harness

  Modifiers turn numbers into words or small counts, so Jev never
  compares, and there are few, so each line means one thing and tests
  can pin what Jev reads. A check is a tests, build or deploy command.

  modifier       on                  reads
  ─────────────────────────────────────────────────────────────────────
  outcome        turn ends           done · failed · stopped
                 routine tool lines  It failed.
                 checks              failed · passed … after failing
  length         turn ends, the      short (<1 min) · long (<5 min) ·
                 working heartbeat   very long (5+ min)
  tool calls     turn ends           12 tool calls · 1 tool call · none
  in a row       pokes               You poked Boop 4 times in a row.
  (in progress)  a reaction's line   still playing: don't repeat it

  Notes: a turn start's `You asked: "…"`, a turn end's `Its last
  message: "…"`, each cut to 300 characters, as is the line
  `You said to Boop: "…"`. No streaks, times, gaps,
  error reasons or topic lists; the view events' facts keep them for
  logs and evals. A reaction that didn't happen isn't shown, so it may
  be made again; one your tap cut short did happen, and stays, in
  progress while the pokes go on.

  CLOSING LINE  (end of HISTORY)
  ─────────────────────────────────────────────────────────────────────
  Boop has been grumpy for 2 min.
      from mood, only while not calm, after a change since launch.
      What the mood files' "fades to … once Boop has been … for N min"
      is read against


GUARANTEES
═══════════════════════════════════════════════════════════════════════
  • The truth never waits on Jev.
  • No Jev (no key, offline, slow) → mood never changes, nothing reacts;
    Boop still shows what agents are doing and when you're needed.
  • Boop only watches and tells. It never approves or blocks anything.
```

Updated 2026-09-30. What Boop does when things happen. Plain rules keep
the screen true at once: the Mac's core (`app/BoopKit/Core/`) keeps the
sessions and says which visual to show, and the device
(`firmware/src/app/behaviour.*`) shows it, adds its own life and answers
your touch. The brain decides everything expressive, a moment later or
not at all ([harness/DECISIONS.md](harness/DECISIONS.md)). How Boop
sounds is in [VOICE.md](VOICE.md).

## 1. How it fits together

The summary above is the model. The rest of this section is how the
layers meet.

**Attention wins.** While something needs you, no animation, line or
face plays but `listening`, so push-to-talk still works; one already playing
is cut short (`listening` plays on), a tap only dips the face and opens
the waiting thread on the Mac (§3.2), the rules send no one-shot, and no
view event but what you say wakes the brain
([harness/EVENTS.md](harness/EVENTS.md) §6).

**What shows first,** on the device: no app (§3.4), then `listening`,
then needs you, then a tap's poke and the moments (the brain's, and the
rules' one-shots), then the look (what the agents are doing, working,
idle or asleep). Whatever outranks the moments holds the face: a tap
there only dips it, and a moment's animation is skipped.

**How it flows.** The core is a pure state machine: each input goes in
with the time, effects come out, and the app hands each to its owner.
Settings are the volume, the personality's rules and whether there's a
brain.

```
hook events ──┐                 ┌─► core rules ─┬─► state ─────► device (PROTOCOL.md §3)
device pokes ─┤                 │               ├─► one-shot ──► device
              │                 │               └─► new day ───► transcript pruning
what you say ─┼─► transcript ───┤
heartbeats ───┘                 └─► view ─► harness ─► brain ─┬─► react ──► device
1 s tick: core timers, the view's heartbeats                  └─► mood ───► core
```

## 2. Base states

### Sessions and the base

The core keeps one entry per agent session, each **working**, **idle** or
**needs you**. How events and timers move a session between them is in
[ADAPTERS.md](ADAPTERS.md) §4. Every change sends the device a new
`state` ([PROTOCOL.md](PROTOCOL.md) §3):

- `base` is `working` if any session works, else `asleep` with no
  sessions, else `idle`. How many agents are busy never changes the look.
- `act` says what the agents are doing, while `base` is `working` and
  nothing needs you, when it's something the look shows (below).
- `attn` names the session that has waited longest (requests that
  arrive in the same millisecond keep their order), how many more wait,
  and the number of the request shown, so the device can tell a
  different request by it.

### The looks

The device takes the first look that applies, draws it in the mood's
design, and adds blinks of its own (180 ms,
`kBlinkMs`); the new moods' designs are flip-books that blink on their
own clock. The designs are the animation bank's (the facegen designs,
[DEVICE.md](DEVICE.md) §6): each look has three variations in every
mood, and working five, which loop, except that needs you's plays its
performance once and then holds its pending pose. What the agents are
doing and the one-shots have one to nine, by mood (§3.1).

**Which variation.** Each time the visual changes (a look, what the
agents are doing, or needs you starting), the core picks one of its
variations at random, never the one that visual showed last, and every
`state` carries it ([PROTOCOL.md](PROTOCOL.md) §3). A new mood keeps the
variation showing, unless the new mood has fewer of that visual: then
it picks one of the new mood's the same way. With no app the device has
no one to pick, and shows the first. This is a rule for now; the harness
may take the choice over later.

**Taking turns.** A look that loops on (idle, working, what the agents
are doing, asleep) doesn't play one variation for minutes: the device
moves between them. The Mac's
variation shows first. Once one has shown 5 s (`kTurnMinMs`), each end
of its loop moves to another at random, never itself, with a 2 in 3
chance (`kTurnPct`), and otherwise plays another loop. The move blinks,
as any change of design does, and the new one starts from the beginning
of its loop, with its own sounds ([VOICE.md](VOICE.md) §10). A new mood
doesn't start the turns over; a new visual, or a new variation from the
Mac, does. Needs you and no app don't take turns, and nor does a look
while a moment or its expression plays over it: the turn waits for a
later loop end. The Mac doesn't hear which variation shows, so it times
a reaction's face by the look's longest variation
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).

| Look | When | Blinks |
| --- | --- | --- |
| No app | 30 s with no `state` (§3.4) | None |
| Needs you | The `state` has `attn` (§3.2): its performance once, then its pending pose | At the base's pace |
| What the agents are doing | `base` is `working` and the `state` has `act`: its design (below) | As working |
| Working | `base` is `working` | Every 2–5 s |
| Idle | `base` is `idle` | Every 2–6 s |
| Asleep | `base` is `asleep` | None |

No blink of the device's shows during an animation, or on a new mood's
flip-book, which blinks on its own clock. A change to another look, an
animation, or another mood, blinks into the new design rather than
cutting: the first pack's designs shut their eyes, and a flip-book
shows its own blink step, for 150 ms (`render::kBlendMs`).

### What the agents are doing

While an agent works, the look shows what at, from its hooks alone
(`app/BoopKit/Core/Activity.swift`): the tool calls running, each from
its start to its result (by `tool_use_id`, else the last call of that
tool by the same agent), the helpers it sent off and Claude's plan mode.
The `state` carries it as `act`, and the device draws that design in
working's place ([PROTOCOL.md](PROTOCOL.md) §3). With nothing to show,
the look is plain working.

| `act` | While | From |
| --- | --- | --- |
| `testing` | A call that runs tests is running (its topic is `tests`, [ADAPTERS.md](ADAPTERS.md) §3) | Claude, Codex |
| `delegating` | The main agent's `Task` or `Agent` call runs, or a helper Boop saw start (`SubagentStart`) hasn't ended. Never from a helper's end, or its call, alone | Claude |
| `terminal` | A shell command runs: `Bash`, `shell`, `exec_command`, `local_shell` | Claude, Codex |
| `searching` | `WebSearch` or `WebFetch` runs | Claude |
| `analyzing` | `Read`, `Grep`, `Glob` or `LS` runs, or a shell command that only looks at files (topic `inspect`) | Claude, Codex |
| `tool_use` | Any other call runs: an edit, an MCP tool… | Claude, Codex |
| `waiting` | A call has run with nothing heard from its session for 20 s (`Core.waitingMs`): waiting on the machine. Or Codex's request is in its 2 s grace, waiting on its reviewer ([ADAPTERS.md](ADAPTERS.md) §4). A helper at work never counts as waiting | Claude, Codex |
| `planning` | Claude is in plan mode (`permission_mode` `plan`), or a `TodoWrite`, `ExitPlanMode` or Codex `update_plan` call runs. Never from the gap between a prompt and the first call | Claude; Codex if its hooks report `update_plan` |

- **Priority.** With several at once, the higher shows: `testing`, then
  `delegating`, `terminal`, `searching`, `analyzing`, `tool_use`,
  `waiting`, `planning`. So a helper's tests show as testing, and a
  read in plan mode as analyzing.
- **At least 1.5 s** (`Core.actHoldMs`). A higher one shows at once. A
  lower one, or none, replaces the one showing only once 1.5 s have
  passed since its last call ended, and since it started showing, so a
  burst of quick reads is one stretch of analyzing rather than a
  flicker. The core's 1 s tick ends a hold, so it can run up to a
  second longer.
- **Several sessions.** The working session heard from last shows what
  it's doing, among those doing something. A session that needs you, or
  isn't working, shows nothing, and starts fresh when it works again.
- **What ends a call** besides its result: its turn ending or a new
  prompt (a call whose result never came, such as one you pressed Esc
  on), its subagent ending, and the agent moving on from a request (you
  denied the call, which sends no hook, [ADAPTERS.md](ADAPTERS.md) §4).

Codex reports no web search, helpers or plan in its hooks, so it never
shows searching or delegating, and planning only if its hooks report
`update_plan`.

### Mood

The mood is one of 13: happy, excited, proud, curious, determined,
grumpy, sad, calm, engaged, annoyed, irritated, whiny or wounded
([harness/DECISIONS.md](harness/DECISIONS.md) §2.3). Only the brain's
mood action changes it (§4 there; the dashboard can force any), and a
new Boop starts calm, the resting mood. It moves one step at a time,
only to a neighbour on the owner's mood graph (grumpy never straight to
happy), a dramatic jump only for a fresh, big event. It's meant to
shift visibly during ordinary work, step by step rather than flailing:
a failed check, a failed turn, pokes in a row, a fix or a very long
turn ending moves it, a long grind turns it engaged and then
determined, it fades a step toward calm after a few minutes, and each
change comes with a reaction in the new mood's face. The next `state`
carries it and the device blinks into the new set of faces. No rule
depends on the mood.

### Reacting while agents work

No rule reacts. While agents work, the view sends the brain a working
heartbeat as often as the personality says (§6), each wait drawn at
random from its range and started again whenever Boop reacts, so it
comes after a stretch of work with no reaction, however busy other
threads are
([harness/EVENTS.md](harness/EVENTS.md) §4). Jev decides whether Boop
reacts then, with which face and what it says, as for any other event.
With no brain, Boop works silently.

## 3. What happens and what Boop does

The rules react at once. The brain may add a reaction or a mood change a
moment later, if it answers within its deadline
([harness/HARNESS.md](harness/HARNESS.md) §7). Which events wake it is in
[harness/EVENTS.md](harness/EVENTS.md) §4.

**Moments take turns.** A tap's poke plays at once on the device and
replaces the animation playing, but not a brain reaction's line or its
face: the line plays on over the poke, which is drawn in the reaction's
mood, so a barrage of taps doesn't cut short the one answer it gets
(§3.3). A rule's one-shot (§3.1) replaces whatever is playing, a line
included, but none is sent while a brain reaction's line
plays, which it would cut, and it's dropped then rather than sent late.
A brain reaction waits
until no line or reaction's face is playing (it plays over a poke or
a rule's one-shot, which it doesn't cut: the one-shot's design, drawn in
the reaction's mood), which the device's word that
the last one ended settles. A reaction's face held on
for its loops after its take doesn't hold up the next reaction, which
replaces it once the take has played, or, if it said nothing, once its
face has shown for 1.2 s. One is dropped once it
has waited 5 s for its turn (`MomentSchedule.maxWaitMs`,
[ARCHITECTURE.md](ARCHITECTURE.md) §3.2). The device tells the Mac how each
brain reaction ended: played out, cut short by a tap (only a finish
that names nobody, whose animation the poke replaces; its line plays on), "needs you" or a
newer moment, or skipped because something needed you
([PROTOCOL.md](PROTOCOL.md) §4), and HISTORY says so
([harness/DECISIONS.md](harness/DECISIONS.md) §5).

### 3.1 Agent work

| When | What Boop does |
| --- | --- |
| A session starts | `starting` plays once: a fresh session when it started or was cleared, carrying on when it was resumed or compacted (Codex's are never compacted, [ADAPTERS.md](ADAPTERS.md) §5). The first session wakes Boop |
| A session ends | Nothing but the popover's list: the last one ending puts Boop to sleep |
| You send a prompt | `starting` plays once for a new task, then the working look. The brain hears of it, with what you asked |
| A tool call starts or finishes | The working look shows what it does while it runs (§2); the latest topic is kept for the working heartbeat. A test, build or deploy that fails, or passes after failing, reaches the brain; with `tool_uses: all` every tool use does (§6) |
| A command fails: it exits with an error or times out | `error` plays once, at most once every 30 s (`Core.errorEveryMs`), and never for a call you denied or one that failed otherwise. Claude only: Codex reports no failures |
| A Claude helper starts, then comes back | Delegating while it works (§2). `helper_return` plays once when a helper Boop saw start (`SubagentStart`) ends while its turn goes on; with hooks from before that, when the main agent's `Task` or `Agent` call returns. Never after the turn ended |
| A turn finishes | The session goes idle; no rule plays the finish. The brain hears of it, with how many tool calls it made and the agent's last message, and decides whether the finish gets a face, judges its outcome (a success, a failure, or only a reply), and picks how long it holds and which word ([harness/DECISIONS.md](harness/DECISIONS.md) §5). With no brain, a finish shows only the change of look |
| A turn finishes, but its own last test, build or deploy command failed | It counts as a failed turn, and the brain hears of that |
| A turn fails (Claude stops on an API error) | No moment. The brain hears of it |
| You interrupt a turn (Esc, or Codex's `Interrupt`) | `stopped` plays once, if a turn was open: Claude's idle notice after a turn that finished plays nothing. The brain hears it was stopped. It happens at once if a tool was running, else when Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §3) |

A Codex turn never fails, since Codex reports no failures yet
([ADAPTERS.md](ADAPTERS.md) §3).

**The rules' one-shots** (`starting`, `stopped`, `error`,
`helper_return`) are plain rules in the core, sent as a `moment` right
after the `state` of the same hook ([PROTOCOL.md](PROTOCOL.md) §3). Each
plays once, at once, in Boop's mood, with one of its variations at
random (for `starting`, one for what started), never the one it played
last; the device plays the one named when it fits, and otherwise picks
one that does the same way. Then the look comes back. None is sent
while something needs you or `listening` shows, from any session. The
brain doesn't pick them and isn't told of them: it hears of the events
behind them. A finished
turn's `task_complete` or `reply_ready` is the brain's
([harness/DECISIONS.md](harness/DECISIONS.md) §5).

Only a turn that's open finishes: a second `Stop`, or one after the turn
stopped, does nothing. The brain hears only of turns the view saw
start. A launch reads the last two days of the transcript back, so a
turn that ran across a relaunch still finishes, its length counting the
time the app was down; one older than that just goes idle when it
finishes, and the brain isn't told ([harness/EVENTS.md](harness/EVENTS.md)
§4.1).

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt,
and a tap on Boop takes you there.

| When | What Boop does |
| --- | --- |
| An agent needs approval | Boop holds up an amber sign naming the agent and the thread (its name, else its project) in large type, and peeks over its top edge, hopping between the corners and the middle ([DEVICE.md](DEVICE.md) §6); the amber light; and the alert: the needs-you performance with its knocks and ding, once ([VOICE.md](VOICE.md) §10). A moment or mumble playing stops |
| More than one needs you | The sign shows the one waiting longest, with "+N more" for the rest |
| A different request becomes the one shown | The alert again, the performance starting over behind a blink and the sign rising again: another session's, even in the same project, or another subagent's in the same session once the first is answered |
| You tap Boop | The press dip only; it stays amber. The Mac opens the thread the sign names (below), and records the tap as a poke with the rule's `open_thread` action under it; it doesn't wake the brain (§3.3) |
| You click the card in the popover | The same thread opens. A click on any session's row in the popover opens that one, waiting or not |
| You answer on the Mac | The agent carries on; once nothing needs you, Boop blinks back to its base look. A long command you approved keeps "needs you" up until it finishes ([ADAPTERS.md](ADAPTERS.md) §4) |
| You deny with Esc | Claude sends nothing, so Boop stays amber until Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §4) |
| You deny a Claude subagent | It carries on, and Boop stays amber until its next tool call or until it ends ([ADAPTERS.md](ADAPTERS.md) §4) |

The light stays steady and nothing repeats. The brain never shows or
clears it, and nothing but what you say wakes it meanwhile
(push-to-talk still works, §3.3). That pass can
change the mood, which shows once nothing needs you (the sign is the
same in every mood), and no reaction plays until then.

**Where a thread opens.** The hook client notes the app each agent runs
in ([ADAPTERS.md](ADAPTERS.md) §2), and `ThreadLink` picks where its
thread opens, with `open`:

| The agent runs in | What opens |
| --- | --- |
| The Claude app | That session, at `claude://code/continue?session=local_…`, by the app's own ID for it |
| The Codex app, or Codex with no app named | That thread, at `codex://threads/<id>`, by its thread ID (the hook's session) |
| A terminal or another app | That app, brought to the front: which tab is the agent's is out of reach |
| Claude with no app named | Nothing; the Mac logs why |

Headless, `--no-open` only logs where a thread would have opened
([VERIFICATION.md](VERIFICATION.md) §2).

### 3.3 You and Boop

| When | What Boop does |
| --- | --- |
| You press BOOT or touch the screen | The face dips 2 px at once, until you let go |
| You let go within 400 ms, or lift your finger: a tap | The mood's `poked` design, once, from its start, replacing the animation playing; asleep too. A brain reaction playing goes on: its line and bubble play over the poke, which is drawn in the reaction's mood until the reaction's face ends. From the third tap in a row on, `tap_spam` instead (below). The Mac records it as a poke, with the rule's `wiggle` action under it, and the brain hears of it, but not while it's answering the pokes before ([harness/EVENTS.md](harness/EVENTS.md) §6) |
| Pokes in a row | Each within 3 s of the last (`TranscriptView.inARowMs`): the line counts them, `You poked Boop 4 times in a row.`, so Jev can tell a single poke from a barrage. The device counts them too, every tap, those that only dip the face included: from the third in a row (`answersRunFrom`), it plays the mood's `tap_spam` design instead of `poked` (`Behaviour::kTapRunMs` 3000 and `kTapSpamFrom` 3, the same numbers). How Boop reacts is the steering's: curious or glad at one poke; a little miffed at two in a row, turning annoyed; fed up at three or more, irritated and then grumpy, for a couple of minutes ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3). The device plays its own tap animations, so no reaction plays one, and the taps after a reaction don't cut it short. From the third poke on, while the brain's reaction to them is in progress, a tap-cut one included, the pokes after it don't wake the brain, unless the mood changed since, so a barrage gets one "nope" ([harness/EVENTS.md](harness/EVENTS.md) §6) |
| A tap while something needs you | The press dip only, with no poke: there a tap means "take me there", and the Mac opens the waiting thread (§3.2). It counts in the run, but doesn't wake the brain ([harness/EVENTS.md](harness/EVENTS.md) §6) |
| A tap while the brain's finish names whose turn it was (the strip's tick, cross or dots and the thread) | The same: the press dip only, the finish plays on, and the Mac opens that thread where it runs (§3.2), recorded as the rule's `open_thread` action. It counts in the run, but doesn't wake the brain. The device sends the finish's id with the tap, so the thread is the one on screen ([PROTOCOL.md](PROTOCOL.md) §4) |
| Hold BOOT 400 ms, or click Talk in the popover | Push-to-talk, below: `listening` shows at once, the device sends `talk_on` at 400 ms and `talk_off` on release, or by itself after 30 s ([DEVICE.md](DEVICE.md) §4). No tap |
| A tap while `listening` shows | The press dip only: nothing replaces `listening`, and nothing opens, even while something needs you. The brain still hears of the poke |

**Push-to-talk.** Hold BOOT and speak, or click Talk in the popover,
speak and click Send. The Mac's mic records and macOS turns it into text
on the Mac; the device has no mic.

1. `listening` shows as soon as the mic turns on: at once on the
   device for BOOT, and on the Mac's word (a `moment` with
   `"anim":"listening"`) for Talk.
2. The mic goes off when you let go or click Send, after 30 s
   (`Core.listenLimitMs`; the device's own button stops at the same
   limit), or if the link drops while BOOT is held.
3. What it heard is recorded as what you said
   ([harness/EVENTS.md](harness/EVENTS.md) §2), and always wakes the
   brain, even while something needs you; its pass goes ahead of the
   agents' events waiting for theirs ([harness/HARNESS.md](harness/HARNESS.md) §2).
   A reaction is the reply, and
   ends `listening` as it plays, even one that says nothing. If the brain's pass on it (or on
   anything newer) makes no reaction, if there's no brain, if the mic
   heard nothing or couldn't start, the Mac ends `listening` at once with
   the empty `moment` ([PROTOCOL.md](PROTOCOL.md) §3). The device gives
   up waiting 8 s after the mic went off (`Core.replyWaitMs`).

While the mic is on nothing else speaks: the brain's reactions are
refused (`Core.reactionBlock`) and any waiting their turn are dropped,
since a reaction would end `listening` before you've finished. How Boop
answers is the personality's: it can't talk back, only react, and
`boop` always answers with a face ([harness/DECISIONS.md](harness/DECISIONS.md) §2.2).

**You can always tell the mic is on.** The device shows `listening`; the
popover's status line says "Listening…" by a pulsing red dot, and Talk
becomes a filled Send; and macOS shows its own microphone indicator.

**Permissions.** The first time, macOS asks for Speech Recognition, then
the Microphone. If either is refused, on-device recognition isn't
available, or the Mac has no usable microphone, `listening` ends and the
popover says "*name* can't hear you" and why (for a refusal, where to
allow it in System Settings) until you dismiss it or talk again. The
audio goes only to the recognizer and is never kept; what reaches the
brain is in [harness/EVENTS.md](harness/EVENTS.md) §9.

### 3.4 The link

With no `state` from the Mac for 30 s (`kNoAppMs`; the Mac's keepalive is
in [PROTOCOL.md](PROTOCOL.md) §3), the device shows the no-app look, with
only the unplugged icon in the strip, for as long as the silence lasts.
At power-on no Mac has spoken yet, so the board starts in no app until the
first `state` (`dbg.reset` starts on the face, so scenarios don't wait).
The session counts and the amber light go, since it can no longer know
them. No app shows over everything: a tap only dips the face, and
nothing the Mac might still send plays. When the Mac comes back, Boop
blinks into whatever the next `state` says.

### 3.5 Quiet time

While no agent works, an hour with no agent event, poke, word to Boop
or coming back to the Mac brings the
brain a heartbeat, and another each hour after
([harness/EVENTS.md](harness/EVENTS.md) §4), so a mood can fade back to
happy. Nothing shows on screen. The first activity on a day after the
one the app opened on only deletes transcript files past 14 days
([harness/HARNESS.md](harness/HARNESS.md) §5.1).

## 4. Sound and light

| Output | Used for | Never |
| --- | --- | --- |
| Mumbles | The brain's reactions | While something needs you; while the mic is on (§3.3) |
| Sound effects | The face's design: a few of working's clicks (and what the agents are doing's) each loop, the finish's fanfare or sputter, a one-shot's and a poke's contacts once, needs you's knocks and ding (the alert, once per request shown, §3.2) ([VOICE.md](VOICE.md) §10) | Idle, asleep, no app, listening, waiting, or a test pattern. Under a take they're a quarter as loud, except needs you's, the finish's and an error's |
| Amber light | Something needs you: amber at half (`#805800`) | Any other time, or with no app |
| Backlight | Full (255) awake; 60/255 asleep and with no app; eases with each switch of design | Dimmed while something needs you |

Mute (volume 0) silences all sound, effects included, but lines still
show in the bubble, their text and the talking mouth, and the light is unchanged. A `state` that brings "needs you" or volume 0
stops a line that's playing.

## 5. Animation set

| Name | Used for | Look | Length |
| --- | --- | --- | --- |
| `task_complete` | A turn's finish the brain judged a success or a failure (`react.animation`, [harness/DECISIONS.md](harness/DECISIONS.md) §3), with that `outcome` | The mood's task-complete design for that outcome: a success's trophy, curtain call or podium, or a failure's | The loops Jev picks, of 5.2–7.2 s each, and at least until its line and bubble end |
| `reply_ready` | A turn's finish the brain judged only a reply: an answer or a question back | The mood's reply-ready design: an answer handed over | Likewise, of 3.2–7.9 s |
| `cheer` | Older firmware's name for task_complete's success, which the device still reads; the Mac no longer sends it | As task_complete's success | As task_complete's |
| `poked` | A tap; the dashboard's `wiggle` | The mood's poked design | Once, 2.1–7.9 s |
| `tap_spam` | The third tap in a row and each after it (§3.3) | The mood's tap-spam design | Once, 2.9–7.9 s |
| `starting` | A session starting, or a prompt (§3.1) | The mood's starting design for what started: a new task, a fresh session, or carrying on | Once |
| `stopped` | An interrupt that ends a turn (§3.1) | The mood's stopped design: the tools put down | Once |
| `error` | A command that failed or timed out, at most every 30 s (§3.1) | The mood's error design | Once |
| `helper_return` | A helper coming back (§3.1) | The mood's helper-return design: a report delivered | Once |
| `listening` | Push-to-talk (§3.3): BOOT held, or the Mac's mic on | The mood's listening scene from the animation bank, one of three at random (focus corners, headphones or an ear trumpet), silent ([DEVICE.md](DEVICE.md) §4) | Until the reply; 8 s after the mic goes off at most, and 30 s + 8 s in all |

The device plays a tap's poke and, for BOOT, `listening` on its own, at
once; nothing replaces `listening` but the reply. The brain judges each
finish's outcome: no rule plays a finish, so a finished turn shows its
task_complete or reply_ready only when Jev reacts to it, with
`react.animation` `success`, `failure` or `reply`. Which variation
plays is picked at random among those made for its outcome, never the
last one, by `react` ([harness/DECISIONS.md](harness/DECISIONS.md) §5);
the brain never sees them. While the finish for a thread's turn plays
(`task_complete` or `reply_ready` with `who`), the strip says whose: a
mark for the result, a tick for a success, a cross for a failure or
three dots for a reply, then the agent and the thread (`codex ·
fix-nav`: its name as the agent's app shows it, else the worktree or
branch, else the project), in white on a black band, since the finish's
design is colour to the edges. It goes with the finish: when it ends,
or a tap's poke or needs you cuts it. While its line's bubble shows, the
bubble has the lane ([DEVICE.md](DEVICE.md) §4).

The brain's reaction is a face, and what Boop says in it:
whatever look is showing is drawn in the reaction's
mood for the loops of its design that Jev picked, at least while its
take plays, then Boop's own mood comes back
([PROTOCOL.md](PROTOCOL.md) §3). Happy and working, a failing test gets
a loop of working × annoyed with "Tsk...", then working × happy again;
determined when a long turn finishes, Boop plays the finish, a success,
in proud's face while it says "Tiny genius", held three times. The brain has no animations
of its own: a reaction is all it can add, and to stay quiet it doesn't
react at all.

## 6. Personalities

How much Boop reacts is its personality's to say, chosen in Settings and applied from the next event. A personality is a
file in `plan/steering/personality/`: its front matter sets the view's
rules below, and its text steers the brain
([harness/DECISIONS.md](harness/DECISIONS.md) §2.2). "Needs you" and the
tap's poke are the same for every personality.

| Setting | What it sets | `boop` (the default) | `chatter` (debugging) |
| --- | --- | --- | --- |
| `working_heartbeat` | How often a quiet stretch of work reaches the brain: every so many seconds, as a range, or `none` | 90–180 s | 30–60 s |
| `tool_uses` | Which tool calls' ends the view keeps, and the brain hears of: `notable` (a failure, or a pass after failures) or `all` ([harness/EVENTS.md](harness/EVENTS.md) §3) | `notable` | `all` |

A missing or unreadable setting keeps the default. Changing personality
restarts the working heartbeat's wait at the new pace. What the brain adds on top is
Jev's call each time, steered by the text: `boop` reacts to anything
that stands out, gives every finish done and each working heartbeat a
small face, so a long stretch of work never sits on one look for
long, and `chatter` reacts to everything, over the top.
