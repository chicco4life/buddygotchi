# Boop: behaviors

```
BOOP — HOW IT WORKS
═══════════════════════════════════════════════════════════════════════

  SCREEN  =  MOOD  ×  VISUAL        (a visual, acted out in a mood)

MOODS  (how Boop acts; fades back to happy after the minutes shown)
───────────────────────────────────────────────────────────────────────
  happy       good spirits; the default
  excited     3 clean finishes in a row, or a clean 5+ min turn   5 min
  proud       something that failed works                         5 min
  determined  a failure while the agent works on                  5 min
  grumpy      a failed turn, 3+ failures in a row, a poke streak  2 min
  sad         a 5+ min turn ended failing                        10 min

VISUALS  (what Boop is doing)
───────────────────────────────────────────────────────────────────────
  asleep      no agent sessions open               ┐
  idle        sessions open, none working          │ states: always
  working     an agent is working                  │ reflect the truth
  needs you   an agent awaits your approval        │
  no app      device lost the Mac (30 s)           ┘
  cheer       big celebration (trophy, podium…)    ┐ animations:
  wiggle      sway + heart, on a tap               ┘ play for a moment

  Each mood × visual has a few variations (working 5, the rest 3). The
  Mac picks one at random each time the visual changes, never the last.


AUTOMATIC  (plain rules, instant, no brain needed)
═══════════════════════════════════════════════════════════════════════
  • The agents' activity picks the state visual:
      asleep / idle / working / needs you / no app
  • Needs you wins over everything: amber light, its alert, who's asking
  • A tap → the device plays the wiggle at once
  • Needs you and no app are never Jev's to show


JEV  (the brain; decides everything expressive)
═══════════════════════════════════════════════════════════════════════
  Asked on events:  turn start/end · tests/build/deploy fail or pass ·
                    poke streak · heartbeat (quiet work, or an idle hour)

  One request, multiple choice:

  SHIFT MOOD    mood             happy … sad        lasts; restyles all
  ─────────────────────────────────────────────────────────────────────
  REACT         react.mood       none | a mood      the face, or nothing
  (a moment)    react.animation  none | cheer       more as art arrives
                react.loops      once … 4 times     how long it holds
  ─────────────────────────────────────────────────────────────────────
  SAY           word.feeling     none | yay, oops, again, finally, …
                word.about       none | tests, build, deploy, docs
                → at most one real word, inside Minion gibberish

  e.g. tests pass after 3 failures:
       mood → proud;  react: proud × cheer, twice, "…finally!"
  e.g. a 5 s routine turn:  nothing

  What Jev sees:  NOW, and HISTORY: the last 10 min (or back to the
  oldest working turn), at most 40 events, what Boop did under each.
  No memory between asks. Lines carry modifiers, so Jev never counts:
    short / long / very long turn   right after · a while · a long break
    tests failed again, 3 in a row  A comeback on tests.
    3 clean finishes in a row.      (in progress) · (didn't happen: …)
  HISTORY ends:  Boop's last reaction, 4 min ago: a proud face …
                 Boop has been grumpy for 2 min.
                 Working now: …


GUARANTEES
═══════════════════════════════════════════════════════════════════════
  • The truth never waits on Jev.
  • No Jev (no key, offline, slow) → mood never changes, nothing reacts;
    Boop still shows what agents are doing and when you're needed.
  • Boop only watches and tells. It never approves or blocks anything.
```

Updated 2026-09-28. What Boop does when things happen. Plain rules keep
the screen true at once: the Mac's core (`app/BoopKit/Core/`) keeps the
sessions and says which visual to show, and the device
(`firmware/src/app/behaviour.*`) shows it, adds its own life and answers
your touch. The brain decides everything expressive, a moment later or
not at all ([harness/DECISIONS.md](harness/DECISIONS.md)). How Boop
sounds is in [VOICE.md](VOICE.md).

## 1. How it fits together

The summary above is the model. The rest of this section is how the
layers meet.

**Attention wins.** While something needs you, no animation or mumble
plays, one already playing is cut short, a tap only dips the face,
and no event wakes the brain
([harness/EVENTS.md](harness/EVENTS.md) §6).

**How it flows.** The core is a pure state machine: each input goes in
with the time, effects come out, and the app hands each to its owner.
Settings are the volume, the personality's rules and whether there's a
brain.

```
hook events ─┐                ┌─► state ─────────► device (PROTOCOL.md §3)
device taps ─┤                │
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
design, and adds blinks of its own (180 ms,
`kBlinkMs`). The designs are the animation pack's (the facegen designs,
[DEVICE.md](DEVICE.md) §6): each look has three variations, and working
five, which loop, except that needs you's plays its performance once and
then holds its pending pose.

**Which variation.** Each time the visual changes (a look, or needs you
starting), the core picks one of its variations at random, never the one
that visual showed last, and every `state` carries it
([PROTOCOL.md](PROTOCOL.md) §3). It holds while the visual does, a new
mood included. With no app the device has no one to pick, and shows the
first. This is a rule for now; the harness may take the choice over
later.

| Look | When | Blinks |
| --- | --- | --- |
| No app | 30 s with no `state` (§3.4) | None |
| Needs you | The `state` has `attn` (§3.2): its performance once, then its pending pose | At the base's pace |
| Working | `base` is `working` | Every 2–5 s |
| Idle | `base` is `idle` | Every 2–6 s |
| Asleep | `base` is `asleep` | None |

No blink shows during a wiggle. A change to another look, or
another mood, blinks into the new design rather than cutting.

### Mood

The mood is one of six: happy, excited, proud, determined, grumpy or
sad ([harness/DECISIONS.md](harness/DECISIONS.md) §2.3). Only
the brain's mood action changes it (§4 there; the dashboard can force
one), and a new Boop starts happy. It's meant to shift visibly during
ordinary work: a first failure, a failed turn, a poke streak, a fix or
a third clean finish in a row moves it, it fades back to happy after a
few minutes, and each change comes with a reaction in the new mood's
face. The next
`state` carries it and the device blinks into the new set of faces. No
rule depends on the mood.

### Mumbling while agents work

No rule mumbles. While agents work, the core sends the brain a working
heartbeat as often as the personality says (§6), each wait drawn at
random from its range and started again by any event that wakes the
brain, so it only comes in a quiet stretch of work
([harness/EVENTS.md](harness/EVENTS.md) §4). Jev decides whether Boop
mumbles then, with which face and word, as for any other event. With no
brain, Boop works silently.

## 3. What happens and what Boop does

The rules react at once. The brain may add a mumble or a mood change a
moment later, if it answers within its deadline
([harness/HARNESS.md](harness/HARNESS.md) §7). Which events wake it is in
[harness/EVENTS.md](harness/EVENTS.md) §4.

**Moments take turns.** A tap's wiggle plays at once on the device and
replaces whatever is playing, mumble included. A brain reaction waits
until no line or reaction's face is playing (it plays over a wiggle,
which it doesn't cut), which the device's word that the last one ended
settles. A reaction's face held on
for its loops after its mumble doesn't hold up the next reaction, which
replaces it once the mumble has played. One is dropped once it
has waited 5 s for its turn (`MomentSchedule.maxWaitMs`,
[ARCHITECTURE.md](ARCHITECTURE.md) §3.2). The device tells the Mac how each
brain reaction ended: played out, cut short by a tap, "needs you" or a
newer moment, or skipped because something needed you
([PROTOCOL.md](PROTOCOL.md) §4), and HISTORY says so
([harness/DECISIONS.md](harness/DECISIONS.md) §5).

### 3.1 Agent work

| When | What Boop does |
| --- | --- |
| A session starts or ends | Nothing but the popover's list: the first one wakes Boop, and the last one ending puts it to sleep |
| You send a prompt | The working look. The brain hears of it |
| A tool call starts or finishes | Nothing on screen; the latest topic is kept for the working heartbeat. A test, build or deploy that fails, or passes after failing, reaches the brain; with `tool_uses: all` every tool use does (§6) |
| A turn finishes | The session goes idle; no rule celebrates. The brain hears of it and decides whether the finish gets a face, and whether a cheer, for how long and with which word ([harness/DECISIONS.md](harness/DECISIONS.md) §5). With no brain, a finish shows only the change of look |
| A turn finishes, but its last test, build or deploy command failed | It counts as a failed turn, and the brain hears of that |
| A turn fails (Claude stops on an API error) | No moment. The brain hears of it |
| You interrupt a turn (Esc) | No moment. The brain hears it was stopped. It happens at once if a tool was running, else when Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §3) |

A Codex turn never fails, since Codex reports no failures yet
([ADAPTERS.md](ADAPTERS.md) §3).

Only a turn that's open finishes: a second `Stop`, or one after the turn
stopped, does nothing. The brain hears only of turns Boop saw start: one
it joined partway (the app launched, or forgot the session, after the
prompt) just goes idle when it finishes: Boop can't say how long it
ran, so the brain isn't told and nothing celebrates it
([harness/EVENTS.md](harness/EVENTS.md) §7).

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.

| When | What Boop does |
| --- | --- |
| An agent needs approval | The needs-you look and its amber sign, the amber light, the strip naming agent and project, and the alert: the needs-you performance with its knocks and ding, once ([VOICE.md](VOICE.md) §10). A moment or mumble playing stops |
| More than one needs you | The strip shows the one waiting longest, with "+N" for the rest |
| A different request becomes the one shown | The alert again, the performance starting over behind a blink: another session's, even in the same project, or another subagent's in the same session once the first is answered |
| You tap Boop | The press dip only; it stays amber (§3.3) |
| You answer on the Mac | The agent carries on; once nothing needs you, Boop blinks back to its base look. A long command you approved keeps "needs you" up until it finishes ([ADAPTERS.md](ADAPTERS.md) §4) |
| You deny with Esc | Claude sends nothing, so Boop stays amber until Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §4) |
| You deny a Claude subagent | It carries on, and Boop stays amber until its next tool call or until it ends ([ADAPTERS.md](ADAPTERS.md) §4) |

The light stays steady and nothing repeats. The brain is never involved.

### 3.3 You and Boop

| When | What Boop does |
| --- | --- |
| You press BOOT or touch the screen | The face dips 2 px at once, until you let go |
| You let go: a tap | `wiggle`, replacing whatever is playing, a mumble included. Asleep and with no app too. The Mac hears of it; the brain doesn't |
| 4 taps within 3 s: a poke streak | A `wiggle`, as always. The brain hears of the streak and may grumble, at most once a minute (`pokeTaps`, `pokeWindowMs`, `pokedEveryMs`); a sooner streak is only recorded. A streak can make Boop grumpy for a couple of minutes ([harness/EVENTS.md](harness/EVENTS.md) §6). The count starts again after each streak |
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
| Mumbles | The brain's reactions | While something needs you |
| Sound effects | The face's design: working's clicks every loop, the cheer's fanfare, needs you's knocks and ding (the alert, once per request shown, §3.2), idle's swish at most every 45 s ([VOICE.md](VOICE.md) §10) | Asleep, no app, or a test pattern. Under a mumble they're half as loud, except needs you's |
| Amber light | Something needs you: amber at half (`#805800`) | Any other time, or with no app |
| Backlight | Full (255) awake; 60/255 asleep and with no app; eases with each switch of design | Dimmed while something needs you |

Mute (volume 0) silences all sound, effects included, but mumbles still
show in the bubble and the light is unchanged. A `state` that brings "needs you" or volume 0
stops a line that's playing.

## 5. Animation set

| Name | Used for | Look | Length |
| --- | --- | --- | --- |
| `cheer` | A reaction the brain cheers with (`react.animation`, [harness/DECISIONS.md](harness/DECISIONS.md) §3) | The task-complete scene of the reaction's mood: a trophy, a curtain call or a podium | The loops Jev picks, of 6.4–7.2 s each |
| `wiggle` | A tap | The look's own design, swaying, with a pixel heart | 0.7 s |

The device plays the wiggle on its own, at once. Only the brain cheers:
no rule does, so a finished turn is celebrated only when Jev reacts to
it with `react.animation: cheer`. Which of the cheer's three variations
plays is picked at random, never the last one, by `react` when it cheers
([harness/DECISIONS.md](harness/DECISIONS.md) §5); the brain never sees
them.

The brain's reaction is a mumble with a face:
whatever look is showing is drawn in the reaction's
mood for the loops of its design that Jev picked, at least while the
mumble plays, then Boop's own mood comes back
([PROTOCOL.md](PROTOCOL.md) §3). Happy and working, a failing test gets
a loop of working × grumpy with "…ugh!", then working × happy again;
determined when a long turn finishes, Boop cheers in proud's face while
it mumbles "…finally!", held three times. The brain has no animations
of its own: a reaction is all it can add, and to stay quiet it doesn't
react at all.

## 6. Personalities

How much Boop reacts is its personality's to say, chosen in Settings and applied from the next event. A personality is a
file in `plan/steering/personality/`: its front matter sets the core's
rules below, and its text steers the brain
([harness/DECISIONS.md](harness/DECISIONS.md) §2.2). "Needs you" and the
tap's wiggle are the same for every personality.

| Setting | What it sets | `boop` (the default) | `chatter` (debugging) |
| --- | --- | --- | --- |
| `working_heartbeat` | How often a quiet stretch of work reaches the brain: every so many seconds, as a range, or `none` | 120–240 s | 30–60 s |
| `tool_uses` | Which tool uses reach the brain: `notable` (a failure, or a pass after failures) or `all` ([harness/EVENTS.md](harness/EVENTS.md) §4) | `notable` | `all` |

A missing or unreadable setting keeps the default. Changing personality
restarts the working heartbeat's wait at the new pace. What the brain adds on top is
Jev's call each time, steered by the text: `boop` reacts to anything
that stands out, and to a routine finish only when it has something to
show, and `chatter` reacts to everything, over the top.
