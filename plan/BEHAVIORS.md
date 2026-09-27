# Boop: behaviors

Updated 2026-09-27. What Boop does on the device when things happen. How
it sounds is in [VOICE.md](VOICE.md). Numbers marked *proposed* are first
guesses, to be tuned once we've lived with Boop.

This is the minimal set: **4 states** (asleep, idle, working, needs you)
and **3 animations** (`cheer`, `wiggle`, `listening`), in **3 modes**
(chatty, normal, calm; §6) that set how much Boop reacts. On 2026-09-26
everything beyond it was cut, in two steps, so the surface is small
enough to hold in your head; features come back one at a time
([FUTURE.md](FUTURE.md), "Parked"). The code from before the first cut is
at git tag `v1-full`.

## 1. How behaviour is layered

What you see is built from three layers. The top one wins where they
conflict.

| Layer | Examples | Decided by |
| --- | --- | --- |
| 1. Attention | Something needs you: amber, looking at you | Core (rules) |
| 2. Moment | Cheer, wiggle, listening, a mumble | Core, sometimes flavoured by the brain |
| 3. Base state | Asleep, idle, working | Core (rules) |

**Attention wins.** While something needs you, the device plays only
`listening`, so push-to-talk still works. Other moments (a cheer for
another session, a tap's wiggle) are skipped, and a moment that's playing
when "needs you" starts is cut short. Mumbles never show while something
needs you.

## 2. Base states

| State | When | Loop |
| --- | --- | --- |
| Asleep | No sessions | Eyes closed, slow breathing, a "zzZZ" climbing every 2.4 s, never blinks, backlight at 60/255 |
| Idle | Sessions open, none working | Blinks every 2–6 s |
| Working | At least one agent working | Focused gaze, a sweat drop, blinks every 2–5 s (1.2–3.5 s with 3+ busy); every 2.6 s (1.8 s with 3+ busy) a 0.8 s strain: eyes squeeze, mouth tightens, the face dips a block |

Needs you (§3.2) sits on top of whichever of these is showing.
Otherwise the backlight is full (255), and always while something needs
you. It dims and brightens over the face's 150 ms blend
([UX.md](UX.md) §2).

**No app.** With no `state` from the Mac for 30 s the device shows the
asleep look (backlight 60/255), with the unplugged icon in the strip so
you can tell it from having no sessions (§3.4).

**Working chatter.** While agents work, the core has Boop mutter by rule,
as often as the mode says: every 45–90 s in chatty, every 2–4 minutes in
normal, never in calm (*proposed*, §6). About half the time the
word is a working session's latest topic, picked at random among the
working sessions that have one, said as a `curious` question
(*"mi-ne? po… tests?"*); otherwise it's a `happy` mumble with no word.

## 3. What happens and what Boop does

"Rules" happen immediately. "Brain may add" arrives 1–5 s later from the
[brain](HARNESS.md), and is dropped if the moment has passed. Whether it
adds anything is up to its classifier, and a mumble's word is up to its
writer ([HARNESS.md](HARNESS.md) §6); the mode picks both (§6). The tables
say what normal mode's brain may add; §6 has chatty and calm. What it adds is a mumble; the brain's
faces are parked ([FUTURE.md](FUTURE.md)). It never cuts the rules'
reaction short, or its own: a brain mumble waits until the rule moment,
and any brain mumble before it, has finished playing
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).

### 3.1 Agent work

| When | Rules | Brain may add |
| --- | --- | --- |
| You send a prompt | Base becomes working | Usually nothing |
| Turn finishes | `cheer`, even while other sessions keep working; in calm, only for a very long turn (over a minute) | Under 15 s, nothing. From 15 s, a proud mumble, e.g. *"ba-ba ti… yay!"*; past a minute, nearly always with a word, e.g. *"…finally!"* |
| Turn fails | No moment; the session goes idle | Sass at the agent, as an annoyed mumble, e.g. *"tu-ka… tests."* |

A new moment replaces one that's playing, so several turns finishing
together look like one cheer.

A turn fails when Claude stops on an API error, or when the last test,
build or deploy command in the turn failed. A turn that ends with its tests
still failing is a failed turn, not a finish: no cheer and no XP. Codex
doesn't report whether a command failed, so its turns always finish
([ADAPTERS.md](ADAPTERS.md) §3).

A turn you interrupt (Esc) ends there: the session goes idle at once, with
no moment and nothing for the brain, and a request it was waiting on clears. Claude sends no `Stop` for it, so the
interrupt itself, or Claude sitting at its prompt for a minute, ends it
([ADAPTERS.md](ADAPTERS.md) §3).

### 3.2 Something needs you

Boop only tells you. You approve on the Mac, in the agent's own prompt.

| When | What Boop does |
| --- | --- |
| An agent needs approval | Turns to you, leans in, amber light; the bubble shows agent and project; one soft chirp |
| More than one needs you | The bubble shows the oldest, with "+1 more" |
| You tap Boop | The press squash only; it stays amber |
| You answer on the Mac | The agent carries on, Boop sees the activity and blends back to what it was doing when `attn` leaves the `state` |

The amber light is steady at half brightness until nothing needs you.
There's one chirp per request: a new `attn` (a different agent or project)
chirps again. The brain is never involved here.

### 3.3 You and Boop

| When | Rules | Brain may add |
| --- | --- | --- |
| Tap the screen, or press BOOT | `wiggle`: a happy squint, a small smile and a heart at the top right, swaying gently | Nothing: a tap is the rules' alone ([HARNESS.md](HARNESS.md) §2) |
| Poke it 4 times within 3 s (*proposed*) | The fourth is a `wiggle` like the others. Not while something needs you, where a tap means "I saw it" | A grumble, as an annoyed mumble, e.g. *"ba-ka… nope!"*. The streak reaches the brain at most once a minute (*proposed*) |
| Hold BOOT (push-to-talk) | `listening` at once, while held (at most 30 s) and then while Boop waits for the reply. The Mac's mic goes off on release, after 30 s, or when the link drops | Usually a mumble, as in [steering.md](steering.md). Asked to be quiet ("quiet" in your words), quiet mode for the minutes asked. Told off or yelled at, a sad mumble, and never quiet mode. Told something to remember, a line where it belongs: a project or session fact for today, a durable fact about you for good ([HARNESS.md](HARNESS.md) §5) |
| Talk in the popover, then Send | The Mac sends `listening` when the mic turns on. 8 s after Send (or after the 30 s limit) it sends an empty moment, which ends `listening` if no reply came. A mic that can't start sends the empty moment at once | As for holding BOOT |
| The reply | A mumble ends `listening` and plays over the face | — |
| No reply | After BOOT is released, the device waits at most 8 s for the reply, then the face blends back | — |

**Asked to be quiet, told off or yelled at.** Only words with "quiet" in
them, as a whole word ("be quiet"), let `quiet` run, whoever decided it:
only then is it on the brain's menu, and the action checks too. What counts as telling Boop off is the if-else
classifier's table ([HARNESS.md](HARNESS.md) §6). You yelled if, while the
Mac's mic was on, it heard you at −18 dBFS or louder for 300 ms or more in
all (*proposed*), even if it caught no words; the app measures a few
milliseconds of audio at a time and keeps only that yes or no
([UX.md](UX.md) §5).

### 3.4 The link

| When | Behaviour |
| --- | --- |
| No `state` for 30 s | The asleep look, with the unplugged icon (§2), for as long as the silence lasts |
| Reconnect | Quick blink, then whatever the next `state` says |

## 4. Sound and light

| Output | Used for | Never |
| --- | --- | --- |
| Mumbles | Working chatter, and the brain's reactions to agents and to what you say, as the mode allows (§6) | In quiet mode; while something needs you |
| Chirp | Once when something starts needing you | Anything else |
| Amber light | Something needs you | Decoration |
| Dimmed backlight | Asleep, no app | While something needs you |

Mute (volume 0) silences all sound but keeps the light.

## 5. Animation set

| Name | Used for |
| --- | --- |
| `cheer` | Finished turns: three hops, then a happy squint, a small open smile and a heart, 2 s |
| `wiggle` | Taps |
| `listening` | Push-to-talk: while the mic is on and while Boop waits for the reply |

A mumble on its own (the brain's `react`, or chatter) plays over whatever
face is showing and doesn't change it.

## 6. Modes

How much Boop reacts is the person's choice, in Settings
([UX.md](UX.md) §7). A new mode takes effect at once: the core's rules
from the next event, the brain from the next input
([HARNESS.md](HARNESS.md) §3). "Needs you" (§3.2), quiet mode and the
tap's wiggle are the same in every mode, and quiet wins over all of them.

| | Chatty | Normal (the default) | Calm |
| --- | --- | --- | --- |
| For | Maximal interaction, and debugging: the same events always get the same decisions | A balance | Only what you need to know |
| Decides with | The chatty if-else table | Jev, or the chatty table without Jev's key | The calm if-else table |
| Writes with | Apple's model, asked again for a word it leaves out | Apple's model | Apple's model |
| Agent starts | A curious mumble | Usually nothing | Nothing |
| Turn finishes, a short turn (under 15 s) | `cheer` and a happy mumble | `cheer` | Nothing |
| Turn finishes, a long turn (15 s up to a minute) | `cheer` and a proud mumble | `cheer` and a proud mumble | Nothing |
| Turn finishes, a very long turn (over a minute) | `cheer` and an excited mumble | `cheer` and a proud mumble | `cheer` |
| Turn fails | An annoyed mumble | An annoyed mumble | An annoyed mumble: the one alert besides "needs you" |
| Poked again and again | An annoyed mumble | An annoyed mumble | The wiggle only |
| You talk to Boop | A mumble back (§3.3) | A mumble back | A mumble back; told off or yelled at, nothing |
| Working chatter | Every 45–90 s | Every 2–4 minutes | Never |

Normal's column is what Jev is steered toward (`steering.md`); Jev decides
each time, so it can differ. The if-else tables are in
[HARNESS.md](HARNESS.md) §6. The numbers are *proposed*.
