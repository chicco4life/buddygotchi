# Boop: UX

Updated 2026-09-26. What the person sees and touches: the screen, the
controls, setup and the Mac app. What Boop *does* in each situation is in
[BEHAVIORS.md](BEHAVIORS.md), and how it sounds is in [VOICE.md](VOICE.md).

## 1. Surfaces

| Surface | Role |
| --- | --- |
| The device | The creature: face, bubble, status strip, light, speaker, buzz, buttons, touch |
| The Mac app | A quiet menu-bar app for setup, settings, sessions and Boop's record. Opens on its own only once, for setup |
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
2. Install and open the app. The first time, its popover opens under the
   menu-bar icon on its own and walks through setup there, one step at a
   time, with Back on each step. Closing the popover halfway keeps your
   place; clicking the icon brings it back.
   1. **Hello:** Boop's face and one sentence about what it does.
   2. **Name:** a name (up to 23 bytes, for keeps) and one question:
      sweet or cheeky?
   3. **Agents:** Claude Code and Codex, each marked found or not found on
      this Mac, with a switch to watch it ([ADAPTERS.md](ADAPTERS.md) §5).
      "See exactly what gets added" shows each file and its hooks.
   4. **Wake up:** what happens next (plug in the body; macOS asks for
      Bluetooth, and for the microphone on the first push-to-talk), then
      "Wake *name* up". This saves Boop, adds the chosen hooks and starts
      it.
3. The app finds `Boop-XXXX` over Bluetooth and connects, and Boop wakes up
   on the device for the first time. There's no pairing code in v1
   ([PROTOCOL.md](PROTOCOL.md) §2).
4. Boop uses Apple's on-device model by default, with no setup. You can add
   your own API key in settings. On Macs without Apple's model and without
   a key, Boop still works fully on rules, with a simpler personality.

## 7. The Mac app

It never pops up by itself after setup and never sends notifications. The
device does the nudging.

**The menu-bar icon** is Boop's eyes and little smile, drawn from the
device's face: closed while Boop is asleep, open while agents are idle,
with a small dot while they work, and amber when something needs you.

**The popover** is one 360 pt column on warm paper (the look below).
Clicking the icon opens it on the overview. Settings and setup open inside
it, never in separate windows. Escape or a click outside closes it, and
closing it from Settings returns to the overview next time. Its height
follows its content, and a long pane scrolls.

**Overview**, top to bottom. It only shows; every control is in Settings.

| Area | Content |
| --- | --- |
| Header | A small copy of Boop's face on black glass (it blinks, glances about while agents work, looks up with an amber rim when something needs you, and sleeps with its eyes closed), Boop's name, a tone dot with one short line ("Working on 2 sessions", "Needs you", "Hanging out", "Napping"), and whether the body is connected ("Connected", "Looking…" or "No device"). Which board it is never shows |
| Modes | Small reminders only when a mode is on: Focus, Quiet with minutes left, Muted, Away |
| Notices | "Restart your agent sessions" after hooks change (dismissable), or why Boop couldn't start |
| Needs you | An amber card: agent · project, "Answer it in the agent's window", and "+N more" |
| Sessions | Grouped by agent, like the threads screen: one row per project with a coloured edge and a status chip (needs you, working, idle). Empty: "No agents awake" |
| Together | Boop's record, as totals across all projects: the level ring with the level inside and the percentage to the next, then tasks finished, projects and days together. Never broken down by project |
| Footer | Settings on the left, Quit on the right |

**Settings**, one scrolling pane with Back at the top:

| Group | Controls |
| --- | --- |
| Sound & focus | Volume (0–10, 0 shows "Off"), focus mode, "I'm away" (pauses hunger) |
| Agents | Claude Code and Codex: connected, not connected, not found or needs a repair, with Connect, Repair or Remove |
| Device | Whether Boop's body is connected and how (Bluetooth or USB), and its firmware version. Not its id |
| Brain | Apple's on-device model or rules only (takes effect on restart), and the API key, kept in the Keychain; cloud brains are shown as not yet available |
| What Boop remembers | Each line, with a button to forget it |
| About | The app's version |

Name and nature are set once, at setup, and don't change.

**The look** is gen-2's "Boop Cream", in light and dark: warm paper and
ink, terracotta for actions and working, amber for needs you, sage for
calm and connected, clay for trouble. Sections are separated by space and
a small tracked-out label, not rules, and grouped into raised cards with a
hairline edge. Names, titles and numbers use the rounded system face.
Each coloured text tone clears 4.5:1 on its own paper; the faint tone is
for decoration only. The face tile uses the device's own colours (black
glass, oat eyes). Looping motion is limited to the face and the dot while
something is live. Tokens live in `app/Boop/Views/Theme.swift`.
