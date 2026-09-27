# Boop: behaviors

Updated 2026-09-28. What Boop does when things happen. Plain rules decide
everything you see at once: the Mac's core (`app/BoopKit/Core/`) keeps
the sessions and says what to show, and the device
(`firmware/src/app/behaviour.*`) shows it, adds its own life and answers
your touch. The brain only adds a mumble or changes the mood, a moment
later or not at all ([harness/DECISIONS.md](harness/DECISIONS.md)). How
Boop looks is in [UX.md](UX.md), and how it sounds in [VOICE.md](VOICE.md).

## 1. How behaviour is layered

What you see has three layers, and the top one wins:

1. **Attention**: something needs you.
2. **A moment**: a `cheer`, a tap's `wiggle`, a mumble, or the brain's
   reaction: a mumble with another mood's face (§5).
3. **The base state**: asleep, idle or working.

Boop's **mood** sits across all three: it picks which set of faces
everything is drawn in (§2), except while a reaction borrows another
mood's for a moment.

**Attention wins.** While something needs you, no animation or mumble
plays, one already playing is cut short, a tap only dips the face,
working chatter is skipped, and no event wakes the brain
([harness/EVENTS.md](harness/EVENTS.md) §6).

**How it flows.** The core is a pure state machine: each input goes in
with the time, effects come out, and the app hands each to its owner.
Settings are the volume, the personality's rules and whether there's a
brain.

```
hook events ─┐                ┌─► state ─────────► device (PROTOCOL.md §3)
device taps ─┤                ├─► cheer, chatter ► device
1 s tick ────┼─► core rules ──┼─► event ─► harness ─► brain ─┬─► mumble ─► device
settings ────┘                └─► new day ─► memory          └─► mood ───► core
```

## 2. Base states

### Sessions and the base

The core keeps one entry per agent session, each **working**, **idle** or
**needs you**. How events and timers move a session between them is in
[ADAPTERS.md](ADAPTERS.md) §4. Every change sends the device a new
`state` ([PROTOCOL.md](PROTOCOL.md) §3):

- `base` is `working` if any session works, else `asleep` with no
  sessions, else `idle`. How many agents are busy never changes the look.
- `attn` names the session that has waited longest (requests that
  arrive in the same millisecond keep their order), how many more wait,
  and the number of the request shown, so the device can tell a
  different request by it.

### The looks

The device takes the first look that applies, draws it in the mood's
design ([UX.md](UX.md) §2–3), and adds blinks of its own (180 ms,
`kBlinkMs`):

| Look | When | Blinks |
| --- | --- | --- |
| No app | 30 s with no `state` (§3.4) | None |
| Needs you | The `state` has `attn` (§3.2) | At the base's pace |
| Working | `base` is `working` | Every 2–5 s |
| Idle | `base` is `idle` | Every 2–6 s |
| Asleep | `base` is `asleep` | None |

No blink shows during a cheer or a wiggle. A change to another look, or
another mood, blinks into the new design rather than cutting
([UX.md](UX.md) §2).

### Mood

The mood is one of seven: happy, excited, proud, curious, determined,
grumpy or sad ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3). Only
the brain's mood action changes it (§4 there; the dashboard can force
one), and a new Boop starts happy. The next
`state` carries it and the device blinks into the new set of faces. No
rule depends on the mood.

### Working chatter

While agents work, Boop mutters by rule, as often as the personality says
(§6): each wait is drawn at random from its range, and the first starts
when work starts. If a working session has a latest topic (tests, build,
deploy or docs), about half the time Boop asks about one of them, picked
at random, as a `curious` mumble with that word (`mumble curious tests`);
otherwise it's a `happy` mumble with no word (`mumble happy`). Chatter is
filler: it's skipped while anything plays or waits, and while something
needs you.

## 3. What happens and what Boop does

The rules react at once. The brain may add a mumble or a mood change a
moment later, if it answers within its deadline
([harness/HARNESS.md](harness/HARNESS.md) §7). Which events wake it is in
[harness/EVENTS.md](harness/EVENTS.md) §4.

**Moments take turns.** A rule moment (a cheer, a tap's wiggle) plays at
once and replaces whatever is playing, mumble included, so turns
finishing together look like one cheer. A brain reaction waits until no
line or reaction's face is playing (it plays over an animation, which it
doesn't cut: the cheer then shows in the reaction's face), which the
device's word that the last one ended settles, and is dropped once it
has waited 5 s for its turn (`MomentSchedule.maxWaitMs`,
[ARCHITECTURE.md](ARCHITECTURE.md) §3.2). Working chatter plays only
when nothing is playing or waiting. The device tells the Mac how each
brain reaction ended: played out, cut short by a tap, "needs you" or a
newer moment, or skipped because something needed you
([PROTOCOL.md](PROTOCOL.md) §4), and HISTORY says so
([harness/DECISIONS.md](harness/DECISIONS.md) §5).

### 3.1 Agent work

| When | What Boop does |
| --- | --- |
| A session starts or ends | Nothing but the popover's list: the first one wakes Boop, and the last one ending puts it to sleep |
| You send a prompt | The working look. The brain hears of it |
| A tool call starts or finishes | Nothing on screen; the latest topic is kept for chatter. A test, build or deploy that fails, or passes after failing, reaches the brain; with `tool_uses: all` every tool use does (§6) |
| A turn finishes | `cheer`, whatever its length and even while other sessions keep working. The brain hears of it. None while another session needs you (§1): the device would drop it, so the Mac neither sends nor claims it |
| A turn finishes, but its last test, build or deploy command failed | No cheer: it counts as a failed turn, and the brain hears of that |
| A turn fails (Claude stops on an API error) | No moment. The brain hears of it |
| You interrupt a turn (Esc) | No moment. The brain hears it was stopped. It happens at once if a tool was running, else when Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §3) |

A Codex turn never fails, since Codex reports no failures yet
([ADAPTERS.md](ADAPTERS.md) §3).

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.

| When | What Boop does |
| --- | --- |
| An agent needs approval | The needs-you look and its amber sign, the amber light, the strip naming agent and project, and one soft chirp. A moment or mumble playing stops |
| More than one needs you | The strip shows the one waiting longest, with "+N" for the rest |
| A different request becomes the one shown | One more chirp: another session's, even in the same project, or another subagent's in the same session once the first is answered |
| You tap Boop | The press dip only; it stays amber (§3.3) |
| You answer on the Mac | The agent carries on; once nothing needs you, Boop blinks back to its base look. A long command you approved keeps "needs you" up until it finishes ([ADAPTERS.md](ADAPTERS.md) §4) |
| You deny with Esc | Claude sends nothing, so Boop stays amber until Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §4) |
| You deny a Claude subagent | It carries on, and Boop stays amber until its next tool call or until it ends ([ADAPTERS.md](ADAPTERS.md) §4) |

The light stays steady and nothing repeats. The brain is never involved.

### 3.3 You and Boop

| When | What Boop does |
| --- | --- |
| You press BOOT or touch the screen | The face dips 2 px at once, until you let go |
| You let go: a tap | `wiggle`, replacing whatever is playing, a cheer or a mumble included. Asleep and with no app too. The Mac hears of it; the brain doesn't |
| 4 taps within 3 s: a poke streak | A `wiggle`, as always. The brain hears of the streak and may grumble, at most once a minute (`pokeTaps`, `pokeWindowMs`, `pokedEveryMs`); a sooner streak is only recorded. The count starts again after each streak |
| A tap while something needs you | The press dip only, and the count starts again: there a tap means "I saw it" |

### 3.4 The link

With no `state` from the Mac for 30 s (`kNoAppMs`; the Mac's keepalive is
in [PROTOCOL.md](PROTOCOL.md) §3), the device shows the no-app look, with
only the unplugged icon in the strip, for as long as the silence lasts.
The session counts and the amber light go, since it can no longer know
them. A tap still wiggles. When the Mac comes back, Boop blinks into
whatever the next `state` says.

### 3.5 Quiet time

While no agent works, an hour with no hook or tap brings the brain a
heartbeat, and another each hour after
([harness/EVENTS.md](harness/EVENTS.md) §4), so a mood can fade back to
happy. Nothing shows on screen. The first activity of a new day starts
short-term memory fresh ([ARCHITECTURE.md](ARCHITECTURE.md) §4.3).

## 4. Sound and light

| Output | Used for | Never |
| --- | --- | --- |
| Mumbles | Working chatter (§2) and the brain's reactions | While something needs you |
| Chirp | Once when something starts needing you, and when the request shown changes (§3.2) | Anything else |
| Amber light | Something needs you: amber at half (`#805800`) | Any other time, or with no app |
| Backlight | Full (255) awake; 60/255 asleep and with no app; eases with each switch of design | Dimmed while something needs you |

Mute (volume 0) silences all sound, but mumbles still show in the bubble
and the light is unchanged. A `state` that brings "needs you" or volume 0
stops a line that's playing.

## 5. Animation set

| Name | Used for | Look ([UX.md](UX.md) §2) | Length |
| --- | --- | --- | --- |
| `cheer` | A finished turn | The mood's task-complete design: a result card rising onto a tray and the mood's gesture | As many loops of that design as make at least 2 s (`Core.cheerMinMs`) |
| `wiggle` | A tap | The look's own design, swaying, with a pixel heart | 0.7 s |

Whoever plays an animation says how many loops of its design play
([PROTOCOL.md](PROTOCOL.md) §3). The rules' cheer works its loops out
from the mood's design (`FaceLoops`, the loop lengths facegen gives the
Mac and the device alike), so a mood whose cheer is short plays it again
rather than cheer for less than 2 s.

A mumble on its own (chatter) plays over whatever face is showing and
doesn't change it. The brain's reaction is a mumble with a face:
whatever is showing (a look, or the cheer) is drawn in the reaction's
mood for the loops of its design that Jev picked, at least while the
mumble plays, then Boop's own mood comes back
([PROTOCOL.md](PROTOCOL.md) §3). Happy and working, a failing test gets
a loop of working × grumpy with "…ugh!", then working × happy again;
curious when a long turn finishes, the cheer shows in proud's face while
Boop mumbles "…finally!", held three times. The brain has no animations
of its own: a reaction is all it can add, and to stay quiet it doesn't
react at all.

## 6. Personalities

How much Boop reacts is its personality's to say, chosen in Settings
([UX.md](UX.md) §6) and applied from the next event. A personality is a
file in `plan/steering/personality/`: its front matter sets the core's
rules below, and its text steers the brain
([harness/DECISIONS.md](harness/DECISIONS.md) §2.2). "Needs you", the
cheer on every finished turn and the tap's wiggle are the same for every
personality.

| Setting | What it sets | `boop` (the default) | `chatter` (debugging) |
| --- | --- | --- | --- |
| `chatter` | Working chatter: every so many seconds, as a range, or `none` | 120–240 s | 30–60 s |
| `tool_uses` | Which tool uses reach the brain: `notable` (a failure, or a pass after failures) or `all` ([harness/EVENTS.md](harness/EVENTS.md) §4) | `notable` | `all` |

A missing or unreadable setting keeps the default. Changing personality
restarts chatter's wait at the new pace. What the brain adds on top is
Jev's call each time, steered by the text: `boop` reacts to anything
that stands out and with small faces to routine finishes, and `chatter`
reacts to everything, over the top.
