# Boop: UX

Updated 2026-09-25. What the person sees and touches: the screen, the
controls, setup and the Mac app. What Boop *does* in each situation is in
[BEHAVIORS.md](BEHAVIORS.md), and how it sounds is in [VOICE.md](VOICE.md).

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

**Face.** The default. Everything in [BEHAVIORS.md](BEHAVIORS.md) happens here.

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

**Stats.** Name, level with a progress ring, and days together. No
mood, hunger numbers or traits.

**No app.** A sleepy face with an unplugged icon in the strip.

## 4. Controls

The v1 board has one button, BOOT, and a resistive touchscreen that needs a
firm press ([DEVICE.md](DEVICE.md) §3). None of the controls affect your
agents.

| Input | Does |
| --- | --- |
| Press BOOT, or tap the face | Boop it; acknowledges a cheer; quiets the nudges if something needs you |
| Hold BOOT | Push-to-talk while held |
| Tap the status strip | Cycle screens: face → threads → stats → face |
| Touch and hold the status strip | Focus mode on or off |
| Touch and hold the face | A mumble and face that show how Boop feels |

A press shorter than 400 ms is a tap, and holding for 400 ms or more starts
push-to-talk until you let go. A touch held for 600 ms or more is a
touch-and-hold. Every press and touch gets visible feedback within 20 ms,
before the Mac hears about it.

When an external main button is added, it takes over BOOT's jobs, and BOOT
becomes a secondary button: a press cycles screens and a hold toggles focus.

## 5. Talking to Boop

Hold BOOT and speak. The Mac's mic is on only while you hold it.

1. **Hold:** the listening face appears at once.
2. **Release:** a thinking face covers the 2–3 s wait.
3. **Reply:** a mumble and a face. It's never a sentence, and never an
   answer to a question.

Things worth saying: "shut up" (Boop goes quiet for a while), "good job",
"remember I ship on Fridays", or just mumbling at it. Audio and transcripts
are thrown away after the reply.

## 6. Setup

1. Plug the device into USB power.
2. Install and open the app. It finds `Boop-XXXX` over Bluetooth and
   connects. There's no pairing code in v1 ([PROTOCOL.md](PROTOCOL.md) §2).
3. The app finds Claude Code and Codex, shows the hooks it will add, and
   installs them with one click each ([ADAPTERS.md](ADAPTERS.md) §5).
4. Name Boop and answer one question: sweet or cheeky? Boop wakes up on the
   device for the first time.
5. Boop uses Apple's on-device model by default, with no setup. You can add
   your own API key in settings. On Macs without Apple's model and without
   a key, Boop still works fully on rules, with a simpler personality.

## 7. The Mac app

A menu-bar icon mirrors Boop: a dot while agents are working, amber when
something needs you. Clicking it shows:

- sessions grouped by agent, like the threads screen;
- Boop's name, level and days together;
- focus mode, "I'm away" (pauses hunger) and volume;
- Boop's record: totals across all projects (tasks finished, how many
  projects, days together, XP and level), never broken down by project;
- settings: agents and hooks, the device, the brain and API key, and what
  Boop remembers about you (view and delete).

It never pops up by itself and never sends notifications. The device does
the nudging.
