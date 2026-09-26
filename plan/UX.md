# Boop: UX

Updated 2026-09-26. What the person sees and touches: the screen, the
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

The screen is a 2.4" IPS panel behind a tinted window, so the backlit black
reads as black glass. Boop sits sideways, so the screen is landscape,
320×240, with the USB-C port on the right ([DEVICE.md](DEVICE.md) §4).

```
┌──────────────────────────────────┐
│                                  │
│       ▐██▌        ▐██▌           │  face, the top 204 px when alone
│               ‿                  │  moves up and shrinks when the bubble shows
│                                  │
├──────────────────────────────────┤
│       ~ ~ ~  tests?  ~           │  bubble, 60 px, only when it shows
├──────────────────────────────────┤
│ ● 1 needs you  ◦ 4          ⊙ ▯  │  status strip, the bottom 36 px
└──────────────────────────────────┘
```

Alone, the face is centred in the 204 px above the strip. When the bubble
shows, the face eases up into the top 144 px at three-quarters size.

- **Face.** Two big Cozmo-style eyes and a small mouth, drawn
  procedurally, blending between expressions in 150 ms or less. It never
  cuts hard. The eyes are solid rounded rectangles in one soft colour, a
  bit taller than wide and set wide apart, with no pupils or highlights,
  so they read as a character rather than real eyeballs. To look
  somewhere, the whole eye moves, and the eye on the side it looks towards
  grows a little, as if Boop turned its head. Where a lid meets the edge
  of an eye the corner is rounded, so a lid never leaves a sharp point.
- **Bubble.** Empty most of the time. It shows either a mumble's one real
  word, or who needs you.
- **Status strip.** How many sessions need you (amber, hidden at zero) and
  how many are working (grey), plus icons at the right for low battery, no
  app, quiet and focus.

## 3. Screens

**Face.** The default. Everything in [BEHAVIORS.md](BEHAVIORS.md) happens here.

**Needs you.** The face moves up and the bubble says who:

```
┌──────────────────────────────────┐
│           ▐██▌    ▐██▌           │
├──────────────────────────────────┤
│ codex · landing                  │  agent · project, in amber
│ needs you on the Mac     +1 more │  "+N more" in grey, at the right
├──────────────────────────────────┤
│ ● 2 needs you  ◦ 1               │
└──────────────────────────────────┘
```

**Threads.** What every agent is doing, grouped by agent, one row per
session with the agent's name on its first row:

```
 Codex    landing              needs you ●
          buddygotchi            working
 Claude   jetpack                working
          notes                     idle
```

Rows show agent, project and status, never prompts or commands. Rows that
need you come first. All 8 sessions fit, with a little space between
agents when there's room; a long project name ends in "..". The view
closes after 10 s untouched (*proposed*), and so does stats. Tapping
anywhere above the strip goes back to the face. A new "needs you" also
goes back, to the needs-you screen.

**Stats.** The progress ring on the left with the level inside it, and the
name and days together on the right (a name too long for the large type
uses the small one). No mood, hunger numbers or traits.

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
before the Mac hears about it: pressing BOOT or the face squashes it a
little, and a finger on the strip lights its top line amber.

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
