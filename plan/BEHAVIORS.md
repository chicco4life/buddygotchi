# Boop: device behaviors and XP

Draft 3 · 2026-09-25. Part of the [architecture](ARCHITECTURE.md). This page
says what Boop does on the device for each trigger, and how XP and hunger
work. Numbers marked *proposed* are first guesses to tune.

## 1. How behaviour is layered

What you see is built from four layers. The top one wins where they
conflict.

| Layer | Examples | Decided by |
| --- | --- | --- |
| 1. Attention | Something needs you: amber, looking at you, nudges | Core (rules) |
| 2. Moment | Cheer, oops, mumble, reply to talk | Core, sometimes flavoured by the brain |
| 3. Base state | Asleep, idle, working | Core (rules) |
| 4. Colour | Mood, hunger, time of day | Core, from memory; applied by the device |

Colour changes *how* Boop does things and never *what*. A hungry, tired Boop
still clearly cheers when a task finishes. It just cheers smaller.

## 2. Base states

| State | When | Loop |
| --- | --- | --- |
| Asleep | No sessions, or night with nothing working | Eyes closed, slow breathing, dimmed |
| Idle | Sessions open, none working | Blinks, looks around, small self-amusements |
| Working | At least one agent working | Focused gaze, occasional mumble; busier with more sessions |
| No app | No `state` from the Mac for 30 s | Sleepy, unplugged icon, slow idle loop |

## 3. Triggers and what Boop does

"Rules" happen immediately. "Brain may add" arrives 1–5 s later from the
[harness](HARNESS.md) and is dropped if the moment has passed.

### 3.1 Agent work

| Trigger | Rules | Brain may add |
| --- | --- | --- |
| You send a prompt | Perks up; base becomes working | Occasionally a short mumble |
| Turn finishes, < 30 s | `nod` | Usually nothing |
| Turn finishes, 30 s–5 min | `cheer` size 1, short chirp | A mumble, e.g. *"ba-ba ti… done!"* |
| Turn finishes, > 5 min | `cheer` size 2–3, jingle, warm light | A mumble, e.g. *"…finally!"* |
| Several finish at once | One cheer at the biggest size | One mumble |
| Turn fails | `oops`, then `side_eye` at the agent, low "hmm" | Sass at the agent, e.g. *"pff… tests."* |

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.

| When | What Boop does |
| --- | --- |
| An agent needs approval | Turns to you, leans in, amber light; the bubble shows agent and project; one soft chirp |
| 45 s later (*proposed*) | Leans further, second chirp |
| 2 min later (*proposed*) | One short buzz (on the bare v1 board, with no motor: three strong amber light pulses), then stays amber and quiet |
| You tap Boop | A small nod; nudges stop for that session; stays amber |
| You approve or deny on the Mac | The agent carries on, Boop sees the activity, gives a small nod, and goes back to work |
| More than one needs you | Bubble shows "2 need you" |

The brain is never involved here. In focus mode, "needs you" is visual
only: the face, the lean and the amber light, with no chirps and no buzz.
Mute drops all sound, but the buzz stays.

### 3.3 You and Boop

| Trigger | Rules | Brain may add |
| --- | --- | --- |
| Tap | `wiggle`, happy squint | A tiny mumble or face |
| Hold the button (talk) | `listening` at once, then `thinking` on release | Mumble reply and a face; on "shut up", `zip` and quiet |
| Brain too slow to reply | `shrug`, *"hmm?"* | — |
| First activity of the day | `stretch`, `yawn` | A morning mumble |

### 3.4 Time and the device

| Trigger | Behaviour |
| --- | --- |
| Night | Drowsier, dimmer, fewer mumbles; sleeps once nothing is working |
| Low battery | Small battery icon |
| Reconnect | Quick blink, then whatever the next `state` says |

## 4. XP and hunger

This is kept deliberately simple for now, and we'll tune it once we've lived
with it. XP and hunger are rules in the core. The brain can't touch them.

**Earning:**

- +1 XP for each agent turn that finishes.
- +5 XP for the first activity of the day.

That's it. Approvals, tokens, taps and time don't earn XP.

**Levels:** every 50 XP is a level (*proposed*). A level-up plays
`levelup` at the next calm moment.

**Hunger:** XP is food. Boop remembers when it last earned any ("last fed"
in `long-term.md`).

| Time since last fed | Boop is | How it shows (only when you look) |
| --- | --- | --- |
| < 2 days | Fed | Normal |
| 2–5 days | Hungry | Occasional tummy rumble, hopeful glances, slower idle |
| > 5 days | Starving | Sits by an empty bowl, low energy; loses 1 XP a day |

- It never drops below the start of its current level, never dies, and
  never runs away.
- Hunger never makes a sound, lights up, buzzes or interrupts.
- The first XP after being hungry plays `gobble`, and Boop is delighted to
  see you. It never sulks.
- "I'm away" in the app pauses hunger.

**Life stages:** Hatchling → Grown → Veteran, by days together and level.
The exact thresholds come later.

## 5. Mood

Boop's mood is set by rule in the core, from how the work is going (wins,
failures, long grinds) and the time of day. It doesn't read your prompts. Mood shows only in behaviour: how bouncy Boop is, how often it
mumbles, the pitch of its voice. It's never shown as a value, label or
sentence outside debug mode.

| Signal | Boop's response |
| --- | --- |
| A run of failures | Calmer, slower, fewer mumbles; side-eye at the agent, as if on your side |
| Quick wins | Bouncier, bigger cheers, higher voice |
| Late night | Drowsier, dimmer, quieter |
| Unsure | Neutral calm |

Mood drifts back to Boop's temperament over about half an hour.

## 6. Sound, light and buzz

What the gibberish sounds like is in [VOICE.md](VOICE.md). This covers when
each output is used.

| Output | Used for | Never used for |
| --- | --- | --- |
| Mumbles | Moments, replies, occasional working chatter | Quiet or focus mode; while something needs you |
| Chirp | The first two "needs you" rungs | Anything else; focus mode |
| Jingle | Bigger cheers | Focus mode |
| Buzz | The top "needs you" rung only | Anything else, including hunger; focus mode |
| Amber light | Something needs you | Decoration |
| Dimmed backlight | Asleep, night, no app | Hiding "needs you" |

Mute in the app silences all sound, but the light and buzz still work. Focus
mode is fully silent and still: no sound and no buzz, only the face and the light.

## 7. Animation set

| Name | Used for |
| --- | --- |
| `nod` | Quick finishes; after "needs you" clears |
| `cheer` | Finished turns (sizes 1–3) |
| `oops`, `side_eye` | Failed turns, sass at agents |
| `wiggle` | Taps |
| `stretch`, `yawn` | Mornings |
| `listening`, `thinking`, `shrug`, `zip` | Push-to-talk |
| `gobble`, `rumble` | Hunger |
| `levelup` | Level-ups |
| `happy`, `proud`, `smug`, `curious`, `sleepy`, `worried`, `sulky`, `love` | Faces the brain can pick |
