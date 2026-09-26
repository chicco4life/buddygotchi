# Boop: behaviors

Updated 2026-09-26. What Boop does on the device for each trigger. How it
sounds is in [VOICE.md](VOICE.md). Numbers marked *proposed* are first
guesses, to be tuned once we've lived with Boop.

This is the minimal set. On 2026-09-26 everything beyond it was cut so
the surface is small enough to hold in your head; features come back one
at a time ([FUTURE.md](FUTURE.md), "Parked"). The code from before the cut
is at git tag `v1-full`.

## 1. How behaviour is layered

What you see is built from three layers. The top one wins where they
conflict.

| Layer | Examples | Decided by |
| --- | --- | --- |
| 1. Attention | Something needs you: amber, looking at you | Core (rules) |
| 2. Moment | Cheer, nod, wiggle, a mumble, push-to-talk | Core, sometimes flavoured by the brain |
| 3. Base state | Asleep, idle, working, no app | Core (rules); no app is the device's own |

**Attention wins.** While something needs you, the device plays only the
moments that answer you directly: `nod`, `listening`, `thinking` and
`shrug`. Others (a cheer for another session) are skipped, and a moment
that's playing when "needs you" starts is cut short. Mumbles never show
while something needs you.

## 2. Base states

| State | When | Loop |
| --- | --- | --- |
| Asleep | No sessions | Eyes closed, slow breathing, a "zzZZ" climbing every 2.4 s, never blinks, backlight at 60/255 |
| Idle | Sessions open, none working | Blinks every 2–6 s |
| Working | At least one agent working | Focused gaze, a sweat drop, blinks every 2–5 s (1.2–3.5 s with 3+ busy); every 2.6 s (1.8 s with 3+ busy) a 0.8 s strain: eyes squeeze, mouth tightens, a small shiver |
| No app | No `state` from the Mac for 30 s | Eyes open, glancing up and aside as if waiting, blinks every 5–9 s; unplugged icon; backlight at 70/255 |

Otherwise the backlight is full (255), and always while something needs
you.

**Working chatter.** About every 2–4 minutes while agents work
(*proposed*), the core has Boop mutter by rule. About half the time the
word is a working session's latest topic, picked at random among the
working sessions that have one, said as a `curious` question
(*"mi-ne? po… tests?"*); otherwise it's a `happy` mumble with no word.

## 3. Triggers and what Boop does

"Rules" happen immediately. "Brain may add" arrives 1–5 s later from the
[harness](HARNESS.md), and is dropped if the moment has passed. It never
cuts the rules' reaction short: a brain mumble waits until the rule moment
has finished playing ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).

### 3.1 Agent work

| Trigger | Rules | Brain may add |
| --- | --- | --- |
| You send a prompt | Base becomes working | Nothing: the brain never speaks on a turn start ([HARNESS.md](HARNESS.md) §5) |
| Turn finishes | `cheer`, even while other sessions keep working | A mumble, e.g. *"ba-ba ti… done!"* |
| Turn fails | No moment; the session goes idle | Sass at the agent, e.g. *"tu-ka… tests."* |

A new moment replaces one that's playing, so several turns finishing
together look like one cheer.

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.

| When | What Boop does |
| --- | --- |
| An agent needs approval | Turns to you, leans in, amber light; the bubble shows agent and project; one soft chirp |
| More than one needs you | The bubble shows the oldest, with "+1 more" |
| You tap Boop | A small nod; it stays amber |
| You answer on the Mac | The agent carries on, Boop sees the activity, nods, and goes back to what it was doing. The device plays the nod itself when `attn` leaves the `state` |

The amber light is steady at half brightness until nothing needs you.
There's one chirp per request: a new `attn` (a different agent or project)
chirps again. The brain is never involved here.

### 3.3 You and Boop

| Trigger | Rules | Brain may add |
| --- | --- | --- |
| Tap the screen, or press BOOT | `wiggle`: "^ ^" eyes, a smile and a heart at the top right, swaying gently | A small mumble |
| Hold BOOT (push-to-talk) | `listening` at once (for at most 30 s), `thinking` on release. The Mac's mic goes off on release, after 30 s, or when the link drops | A mumble reply; on "shut up", quiet, as in [steering.md](steering.md) |
| Talk in the popover, then Send | The Mac sends `listening`, then `thinking` on Send or after 30 s. A mic that can't start sends `shrug` | As for holding BOOT |
| Brain too slow to reply | The device ends `thinking` with a `shrug` itself after 8 s | — |

### 3.4 The link

| Trigger | Behaviour |
| --- | --- |
| No `state` for 30 s | The no-app state (§2) |
| Reconnect | Quick blink, then whatever the next `state` says |

## 4. Sound and light

| Output | Used for | Never |
| --- | --- | --- |
| Mumbles | Working chatter, the brain's replies to events, taps and talk | In quiet mode; while something needs you |
| Chirp | Once when something starts needing you | Anything else |
| Amber light | Something needs you | Decoration |
| Dimmed backlight | Asleep, no app | While something needs you |

Mute (volume 0) silences all sound but keeps the light.

## 5. Animation set

| Name | Used for |
| --- | --- |
| `cheer` | Finished turns: arches, warm eyes and a heart, 2 s |
| `nod` | After "needs you" clears, and a tap while it shows |
| `wiggle` | Taps |
| `listening`, `thinking`, `shrug` | Push-to-talk |

A mumble on its own (the brain's `say`, or chatter) plays over whatever
face is showing and doesn't change it.
