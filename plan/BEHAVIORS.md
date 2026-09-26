# Boop: behaviors

Updated 2026-09-26. What Boop does on the device for each trigger, and how
XP, hunger and mood work. How it sounds is in [VOICE.md](VOICE.md). Numbers
marked *proposed* are first guesses, to be tuned once we've lived with Boop.

## 1. How behaviour is layered

What you see is built from four layers. The top one wins where they
conflict.

| Layer | Examples | Decided by |
| --- | --- | --- |
| 1. Attention | Something needs you: amber, looking at you, nudges | Core (rules) |
| 2. Moment | Cheer, oops, mumble, reply to talk | Core, sometimes flavoured by the brain |
| 3. Base state | Asleep, idle, working | Core (rules) |
| 4. Colour | Mood, hunger, time of day | Core; applied by the device |

Colour changes *how* Boop does things, never *what*. A hungry, tired Boop
still clearly cheers when a task finishes. It just cheers smaller.

**Attention wins.** While something needs you, the device plays only the
moments that answer you directly: `nod`, `listening`, `thinking`, `shrug`
and `zip`. Other moments (a cheer for another session, an oops, a face) are
skipped, and a moment that's playing when "needs you" starts is cut short.
Mumbles never show while something needs you.

**How the device shapes a moment** (it's a rule on the device, from the
`mood` in `state`): moments play faster or slower with `pace` (clamped to
70–140%), except `listening` and `thinking`, whose limits are fixed times, and a cheer is one size smaller when `energy` is under 60 and one
size bigger at 140 or more. A cheer's jingle and warm light follow the
adjusted size.

## 2. Base states

| State | When | Loop |
| --- | --- | --- |
| Asleep | No sessions, or night with nothing working | Eyes closed, slow breathing, dimmed |
| Idle | Sessions open, none working | Blinks every 2–6 s, looks around, small self-amusements |
| Working | At least one agent working | Focused gaze; busier with more sessions; occasional chatter |
| No app | No `state` from the Mac for 30 s | Sleepy, unplugged icon, slow idle loop |

**Working chatter.** About every 2–4 minutes while agents work
(*proposed*), the core has Boop mutter by rule: a feeling from its mood, and
about half the time a working session's latest topic as the word, picked
at random among the working sessions that have one (*"mi-ne? po… tests?"*).

**Night** is 23:00–07:00 local time (*proposed*).

**Idle life on the device.** Something small happens every 2–6 s while idle
(slower when tired, hungry or at night): most often a blink, otherwise a
glance to one side, a peek up, or a little bob to itself. Working Boop
blinks and glances down at the work, more often with 3 or more sessions
busy. Asleep, it breathes slowly and never blinks. With no app it only
blinks, every 5–9 s. The backlight dims to about 45% at night, 25% asleep
(15% asleep at night) and 30% with no app, but never while something needs
you.

## 3. Triggers and what Boop does

"Rules" happen immediately. "Brain may add" arrives 1–5 s later from the
[harness](HARNESS.md), and is dropped if the moment has passed. It never
cuts the rules' reaction short: a brain moment waits until the rule moment
(and any follow-up, like the `side_eye` after an `oops`) has finished
playing ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).

### 3.1 Agent work

| Trigger | Rules | Brain may add |
| --- | --- | --- |
| You send a prompt | Base becomes working | Never a mumble: the brain never speaks on a turn start ([HARNESS.md](HARNESS.md) §5). Rarely a face |
| Turn finishes, under 30 s | `nod` | Usually nothing |
| Turn finishes, 30 s–5 min | `cheer` size 1 | A mumble, e.g. *"ba-ba ti… done!"* |
| Turn finishes, 5–20 min | `cheer` size 2, jingle, warm light | A mumble, e.g. *"…finally!"* |
| Turn finishes, over 20 min | `cheer` size 3, jingle, warm light | A proud mumble; maybe a note |
| Several finish at once | One cheer; a bigger finish within 3 s upgrades it | One mumble |
| Turn fails | `oops`, then `side_eye` at the agent | Sass at the agent, e.g. *"tu-ka… tests."* |

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.

| When | What Boop does |
| --- | --- |
| An agent needs approval | Turns to you, leans in, amber light; the bubble shows agent and project; one soft chirp |
| 45 s later (*proposed*) | Leans further, second chirp |
| 2 min later (*proposed*) | One short buzz, then stays amber and quiet. With no motor (the v1 board): three strong amber light pulses |
| More than one needs you | The bubble shows the oldest, with "+1 more" |
| You tap Boop | A small nod; nudges stop for that session (no more chirps, no pulses, the lean stops growing); it stays amber |
| You answer on the Mac | The agent carries on, Boop sees the activity, nods, and goes back to what it was doing. The device plays the nod itself when `attn` leaves the `state` |

The amber light is steady at half brightness; the three rung-3 pulses are
200 ms at full brightness with 200 ms gaps.

The brain is never involved here. In focus mode this is visual only (§6).

### 3.3 You and Boop

| Trigger | Rules | Brain may add |
| --- | --- | --- |
| Tap the face, or press BOOT | `wiggle`, happy squint | A small mumble or face |
| Hold BOOT (push-to-talk) | `listening` at once (for at most 30 s), `thinking` on release | A mumble reply and a face; on "shut up", a `sulky` face and quiet, as in [steering.md](steering.md) |
| Brain too slow to reply | The device ends `thinking` with a `shrug` itself after 8 s | — |
| Touch and hold the face | The device shows a face from its mood at once (`sleepy` when tired or at night, `curious` when hungry, `worried` when starving, `love` when very bouncy, otherwise `happy`) and sends `input` `feel`; the Mac may add a mumble. While something needs you there's no face (§1) | — |
| First activity of the day | `stretch`, then `yawn` | — |

### 3.4 Time and the device

| Trigger | Behaviour |
| --- | --- |
| Night | Drowsier, dimmer, fewer mumbles; sleeps once nothing is working |
| Low battery | Small battery icon (later; the v1 board has no battery) |
| Reconnect | Quick blink, then whatever the next `state` says |

## 4. XP and hunger

Deliberately simple for now. XP and hunger are rules in the core; the brain
can't touch them.

- **Earning:** +1 XP for each agent turn that finishes (`turn_end`; a
  failed turn earns nothing), and +5 for the first activity of the day.
  Nothing else earns XP: not approvals, tokens, taps or time.
- **Levels:** a new level every 50 XP (*proposed*), so level = XP ÷ 50,
  rounded down, plus 1. A level-up plays `levelup` at the next calm moment.
- **Days together:** calendar days since setup, counting the day of setup
  as day 1.
- **Hunger:** XP is food. The core remembers when Boop last earned any
  ("last fed" in `long-term.md`).

| Time since last fed | Boop is | How it shows (only when you look) |
| --- | --- | --- |
| Under 2 days | Fed | Normal |
| 2–5 days | Hungry | An occasional tummy rumble, hopeful glances, slower idle |
| Over 5 days | Starving | Sits by an empty bowl, low energy; loses 1 XP a day |

On the device, hungry means a tummy rumble now and then and hopeful peeks
up at you; starving adds heavy lids, a lower face and the empty bowl beside
it on the face screen.

- It never drops below the start of its current level, never dies, and
  never runs away.
- Hunger never makes a sound, lights up, buzzes or interrupts.
- The first XP after being hungry plays `gobble`, and Boop is delighted to
  see you. It never sulks.
- "I'm away" in the app pauses hunger.

## 5. Mood

Boop's mood is set by rule in the core, from how the work is going (wins,
failures, long grinds) and the time of day. It doesn't read your prompts.
Mood shows only in behaviour (how bouncy Boop is, how often it mumbles, the
pitch of its voice), never as a value, label or sentence outside debug
mode.

| Signal | Boop's response |
| --- | --- |
| A run of failures | Calmer, slower, fewer mumbles; side-eye at the agent, as if on your side |
| Quick wins | Bouncier, bigger cheers, higher voice |
| Night | Drowsier, dimmer, quieter |

Mood drifts back to neutral over about half an hour.

## 6. Sound, light and buzz

| Output | Used for | Never |
| --- | --- | --- |
| Mumbles | Moments, replies, working chatter | In quiet or focus mode; while something needs you |
| Chirp | The first two "needs you" rungs | Anything else; focus mode |
| Jingle | Bigger cheers | Focus mode |
| Buzz | The top "needs you" rung | Anything else, including hunger; focus mode |
| Amber light | Something needs you | Decoration |
| Warm light | Cheers of size 2 and 3, while the cheer plays | Anything else |
| Dimmed backlight | Asleep, night, no app | Hiding "needs you" |

Mute silences all sound but keeps the light and buzz. Focus mode is visual
only: no sound and no buzz (on the v1 board, no pulses in its place). The
face, its animations and the light carry on.

## 7. Animation set

| Name | Used for |
| --- | --- |
| `nod` | Quick finishes; after "needs you" clears |
| `cheer` | Finished turns (sizes 1–3) |
| `oops`, `side_eye` | Failed turns; sass at agents |
| `wiggle` | Taps |
| `stretch`, `yawn` | The first activity of the day |
| `listening`, `thinking`, `shrug` | Push-to-talk |
| `zip` | Drawn, but nothing plays it in v1: neither the rules nor the brain's `face` choices |
| `gobble`, `rumble` | Hunger |
| `levelup` | Level-ups |
| `happy`, `proud`, `smug`, `curious`, `sleepy`, `worried`, `sulky`, `love`, `side_eye` | Faces the brain can pick with `face` |
