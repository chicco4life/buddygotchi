# Boop: UX

Draft 7 · 2026-09-25. What the person sees and touches: the screens, the
controls, setup and the Mac app. What Boop *does* in each situation is in
[Behaviors](BEHAVIORS.md), and how it sounds is in [Voice](VOICE.md).

## 1. Surfaces

| Surface | Role |
| --- | --- |
| The device | The creature: face, bubble, status strip, light, speaker, buzz, buttons, touch |
| The Mac app | A quiet menu-bar app for setup, settings, sessions and Boop's record. Never opens windows on its own |
| The agent's own window | Where you approve or deny. Boop only tells you it's waiting |

Most days the device is the only surface you look at.

## 2. The screen

The screen is a 240×320 portrait IPS panel behind a tinted window, so the
backlit black reads as black glass.

```
┌──────────────────────┐
│                      │
│      ( o )  ( o )    │  face, ~200 px
│          ‿           │  moves up and shrinks when the bubble needs room
│                      │
├──────────────────────┤
│   ~ ~ ~  tests?      │  bubble, ~80 px
│                      │
├──────────────────────┤
│ ● 1 needs you  ◦ 4   │  status strip, ~40 px
└──────────────────────┘
```

- **Face.** Two big Cozmo-style eyes and a small mouth, drawn
  procedurally, blending between expressions in 150 ms or less. It never
  cuts hard.
- **Bubble.** Empty most of the time. It shows either a mumble's one real
  word, or who needs you.
- **Status strip.** How many sessions need you (amber, hidden at zero) and
  how many are working (grey), plus icons at the right for low battery, no
  app, quiet and focus.

## 3. Screens

**Face.** The default. Everything in [Behaviors](BEHAVIORS.md) happens here.

**Needs you.** The face moves up and the bubble says who:

```
┌──────────────────────┐
│    (◉)  (◉)          │
├──────────────────────┤
│ codex · landing      │  agent · project
│ needs you on the Mac │
│              +1 more │
└──────────────────────┘
```

**Threads.** What every agent is doing, grouped by agent:

```
 Codex
   landing         needs you ●
   buddygotchi     working
 Claude
   jetpack         working
   notes           idle
```

Rows show agent, project and status, never prompts or commands. Rows that
need you come first. The view closes after 10 s untouched (*proposed*).

**Stats.** Name, level with a progress ring, stage and days together. No
mood, hunger numbers or traits.

**No app.** A sleepy face with an unplugged icon in the strip.

## 4. Controls

The device has a main button (external), a secondary button (BOOT) and a
resistive touchscreen that needs a firm press. None of them affect your
agents.

| Input | Does |
| --- | --- |
| Main press, or tap the face | Boop it; acknowledges a cheer; quiets the nudges if something needs you |
| Main hold | Push-to-talk while held |
| Secondary press | Cycle screens: face → threads → stats → face |
| Secondary hold | Focus mode on or off |
| Tap the status strip | Threads |
| Touch and hold the face | A mumble and expression that show how Boop feels, with no text |

Every press and touch gets visible feedback on the device within 20 ms,
before the Mac hears about it.

**On the bare v1 board** there's no external button yet
([DEVICE.md](DEVICE.md) §3), so BOOT is the main button and touch covers the
secondary button's jobs:

| Input | Does |
| --- | --- |
| BOOT press, or tap the face | Boop it; acknowledges a cheer; quiets the nudges if something needs you |
| BOOT hold | Push-to-talk while held |
| Tap the status strip | Cycle screens: face → threads → stats → face |
| Touch and hold the status strip | Focus mode on or off |
| Touch and hold the face | A mumble and expression that show how Boop feels |

A BOOT press shorter than 400 ms is a tap, and holding it for 400 ms or more
starts push-to-talk until you let go. A touch held for 600 ms or more is a
touch-and-hold.

## 5. Talking to Boop

Hold the main button and speak. The Mac's mic is on only while you hold it.

1. **Hold:** the listening face appears at once.
2. **Release:** a thinking face covers the 2–3 s wait.
3. **Reply:** a mumble and a face. It's never a sentence, and never an
   answer to a question.

Things worth saying: "shut up" (Boop goes quiet for a while), "good job",
"remember I ship on Fridays", or just mumbling at it. Audio and transcripts
are thrown away after the reply.

## 6. Setup

1. Plug in the device. It shows a 6-digit pairing code.
2. Install and open the app. It finds the device, and you type the code
   into macOS's pairing prompt.
3. The app finds Claude Code and Codex, shows
   the hooks it will add, and installs them with one click each
   ([ADAPTERS.md](ADAPTERS.md)).
4. Hatching: an egg appears on the device. You name Boop, answer one
   question (earnest or impish?), and it hatches.
5. Brain: Boop uses Apple's on-device model by default, which needs no
   setup. You can add your own API key in settings for a wittier Boop. On
   Macs without Apple's model and without a key, Boop still works fully on
   rules, with a simpler personality.

## 7. The Mac app

A menu-bar icon mirrors Boop: a dot while agents are working, amber when
something needs you. Clicking it shows:

- sessions grouped by agent, like the threads screen;
- Boop's name, level, stage and days together;
- focus mode, "I'm away" (pauses hunger) and volume;
- Boop's record: tasks finished and days together, with an optional
  shareable buddy card;
- settings: agents and hooks, device and firmware, brain and API key, what
  Boop remembers about you (view and delete), backup (opt-in, encrypted),
  and Retire.

It never pops up by itself and never sends notifications. The device does
the nudging.

**Retire** is the only way to end a Boop. It takes several deliberate steps
and produces a memorial card. The next Boop starts fresh.

