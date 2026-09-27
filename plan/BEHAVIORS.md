# Boop: behaviors

Updated 2026-09-27. What Boop does when things happen, and how its
personality changes it. How it sounds is in [VOICE.md](VOICE.md) and how it looks in
[UX.md](UX.md). Boop has **4 states** (asleep, idle, working, needs you),
**2 animations** (`cheer`, `wiggle`) and **2 personalities**
(`boop` and the debug `chatter`, §6); everything else is parked ([FUTURE.md](FUTURE.md)).
The numbers here (timings, thresholds, paces) are first guesses, to be
tuned once we've lived with Boop.

## 1. How behaviour is layered

What you see has three layers, and the top one wins: **attention**
(something needs you), then a **moment** (a cheer, a wiggle, a mumble), then the **base state** (asleep, idle, working). The core's
rules decide all three; all the brain can add to them is a mumble.

**Attention wins.** While something needs you, every moment is skipped,
one already playing when "needs you" starts is cut short, and no mumble
shows.

## 2. Base states

Each state shows its design in Boop's mood ([UX.md](UX.md) §2), which
moves on its own; the device adds the blinks.

| State | When | Loop |
| --- | --- | --- |
| Asleep | No sessions | The asleep design, the same in every mood: eyes shut, a small grey Z, a slow 8 s breath of a pixel or two. No blinks, backlight at 60/255 |
| Idle | Sessions open, none working | The mood's idle design, rising a pixel every 9 s. Blinks every 2–6 s |
| Working | At least one agent working | The mood's working design: a keyboard under the face, its keys lighting in the mood's rhythm, and the mood's own motion (a steady nod when determined, a bounce when excited, a key knocked loose when grumpy, tears when sad). Blinks every 2–5 s |

The first session wakes Boop, and needs you (§3.2) sits on top of
whichever state shows, and working looks the same however many agents
are busy. Awake, the backlight is full (255); it
eases between levels over the 150 ms a switch of design takes ([UX.md](UX.md) §2).

**No app** has its own design, with only the unplugged icon in the strip (§3.4).

**Working chatter.** While agents work, Boop mutters by rule, as often as
the personality says (§6). About half the time the word is a working session's
latest topic, picked at random among the sessions that have one, said as
a `curious` question (*"mi-ne? po… tests?"*); otherwise it's a `happy`
mumble with no word. Chatter is filler. It's skipped over a moment or a
waiting brain mumble, and while something needs you (§4).

## 3. What happens and what Boop does

The rules react at once. The brain may add a mumble a few seconds later,
if it answers in time (§6 says for what; [HARNESS.md](harness/HARNESS.md) §2 has
the deadlines). A brain mumble waits for whatever is playing, and is
dropped once it has waited 5 s ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).
A new rule moment replaces the one playing, so turns finishing together
look like one cheer.

### 3.1 Agent work

| When | What Boop does |
| --- | --- |
| You send a prompt | Working |
| A turn finishes | `cheer`, whatever its length and even while other sessions keep working |
| A turn fails | No moment; the session goes idle. The brain may react ([harness/DECISIONS.md](harness/DECISIONS.md)) |
| You interrupt a turn (Esc) | The session goes idle, with no moment and nothing for the brain. That happens at once if a tool was running, which also clears a request it was waiting on; otherwise when Claude reports itself idle about a minute later ([ADAPTERS.md](ADAPTERS.md) §3) |

A turn fails when Claude stops on an API error, or when the turn's last
test, build or deploy command failed, so a turn that leaves its tests
failing gets no cheer. A Codex turn always finishes, for now
([ADAPTERS.md](ADAPTERS.md) §3).

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.
When "needs you" starts and clears is in [ADAPTERS.md](ADAPTERS.md) §4.

| When | What Boop does |
| --- | --- |
| An agent needs approval | The mood's needs-you design: a lean toward you that plays once and an amber sign under the face. Amber light at half brightness; the strip shows agent and project; one soft chirp |
| More than one needs you | The strip shows the oldest, with "+N" for the rest |
| You tap Boop | The press dip only; it stays amber |
| You answer on the Mac | The agent carries on, and once nothing needs you, Boop blinks back to what it was doing |
| You deny with Esc | Claude sends nothing, so Boop stays amber until Claude reports itself idle about a minute later. A subagent's request stays until your next prompt or the safety net ([ADAPTERS.md](ADAPTERS.md) §4) |

The light stays steady and nothing repeats: one chirp when the strip
first shows a request, and another only when it switches to a different
agent or project. The brain is never involved.

### 3.3 You and Boop

| When | What Boop does |
| --- | --- |
| Tap the screen, or press BOOT | `wiggle`. The brain only hears of it |
| Poke it 4 times within 3 s | A `wiggle`, as always. The brain hears of the streak (at most once a minute) and may grumble. The count then starts again. Taps while something needs you don't count: there a tap means "I saw it" |

### 3.4 The link

With no `state` from the Mac for 30 s, the device shows the no-app design
(low eyes, a grey broken-link sign, the same in every mood; backlight
60/255) with only the unplugged icon in the strip, for as long as the
silence lasts. The session counts go, since it can no longer know them.
When the Mac comes back, it blinks into whatever the next `state` says.

## 4. Sound and light

| Output | Used for | Never |
| --- | --- | --- |
| Mumbles | Working chatter, as the personality sets (§6), and the brain's reactions | While something needs you |
| Chirp | Once when something starts needing you (§3.2): it's the one thing Boop must say | Anything else |
| Amber light | Something needs you | Decoration; with no app |
| Dimmed backlight | Asleep, no app | While something needs you |

Mute (volume 0) silences all sound but keeps the light.

## 5. Animation set

| Name | Used for | Look |
| --- | --- | --- |
| `cheer` | A finished turn | The mood's task-complete design: a result card rising onto a tray, the mood's gesture (a hop when excited, a nod when proud, a small escaped smile when grumpy), sparkles when happy, excited or proud; 2 s |
| `wiggle` | A tap | The design showing, on its own clock, swaying 3 px either way, with a pixel heart popping in at the top right; 0.7 s |

A mumble on its own (the brain's `react`, or chatter) plays over whatever
face is showing and doesn't change it. The brain has no faces of its own:
on the device a mumble is all it can add, and to stay silent it doesn't
react at all.

## 6. Personalities

How much Boop reacts is its personality's to say, chosen in Settings
([UX.md](UX.md) §6) and applied from the next event. A personality is a
file in `plan/steering/personality/`: its settings drive the core's rules
below, and its text steers the brain
([harness/DECISIONS.md](harness/DECISIONS.md) §2.2). "Needs you", the
cheer on every finished turn and the tap's wiggle are the same for every
personality.

| Setting | What it sets | `boop` (the default) | `chatter` (debugging) |
| --- | --- | --- | --- |
| `chatter` | Working chatter: every so many seconds, as a range, or `none` | 120–240 s | 30–60 s |
| `tool_uses` | Which tool uses wake the brain: `notable` (a failure, or a pass after failures) or `all` ([harness/EVENTS.md](harness/EVENTS.md) §4) | `notable` | `all` |

What the brain adds on top, whether a mumble or a mood change, is Jev's
call each time, steered by the personality's text: `boop` speaks up when
something stands out, and `chatter` reacts to everything, over the top.
