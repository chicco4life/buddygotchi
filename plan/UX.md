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

- **Face.** Two Cozmo-style eyes and a small mouth, drawn procedurally,
  blending between expressions in 150 ms or less. It never cuts hard. The
  face has gen-2's look: the eyes are solid rounded rectangles in soft
  lavender-white (48 × 60 px, 134 px apart, so there's plenty of black
  between them), with no pupils or highlights, so they read as a character
  rather than real eyeballs. At rest the mouth is a short dash below them.
  They tint towards the cheer glow during `cheer`, `love`, `levelup` and
  `gobble`, and towards the oops red during `oops`. To look somewhere, the
  whole eye moves, and the eye on the side it looks towards grows a little,
  as if Boop turned its head. Where a lid meets the edge of an eye the
  corner is rounded, so a lid never leaves a sharp point. Happy eyes are
  thin "^" arches over a "u" smile: on the way, the eye squeezes to a short
  bar and the bar bends up. A tap, a big cheer, love and a level-up pop a
  rose heart in at the top right of the face. Asleep, a "zzZZ" climbs up
  from the right eye one letter at a time. Working, Boop strains every
  couple of seconds, and a sweat drop slides down beside the right eye
  ([BEHAVIORS.md](BEHAVIORS.md) §2).
- **Bubble.** Empty most of the time. It shows either a mumble's one real
  word, or who needs you.
- **Status strip.** How many sessions need you (amber, hidden at zero) and
  how many are working (grey), plus icons at the right for low battery, no
  app, quiet and focus.
- **Debug label.** A debug-only aid, off unless the firmware is built with
  `BOOP_DEBUG_LABEL=1` (the board build sets it in
  `firmware/platformio.ini`). On the face, needs-you and no-app screens,
  the name of what the face is showing sits in tiny faint 5×7 text at the
  top left: the moment's anim (`cheer`, `happy`, …) or else the look
  (`idle`, `working`, `asleep`, `no_app`, `needs_you`). Frames drawn with a
  frozen clock leave it out, so the simulator and scenario screenshots
  don't change.

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
need you come first. It shows up to 8 rows; the Mac drops rows from the end
when the `state` line would pass 512 bytes ([PROTOCOL.md](PROTOCOL.md) §3).
There's a little space between agents when there's room, and a long
project name ends in "..". The view closes after 10 s untouched
(*proposed*), and so does stats. Tapping anywhere above the strip goes back
to the face. A new "needs you" also goes back, to the needs-you screen.

**Stats.** The progress ring on the left with the level inside it, and the
name and days together on the right (a name too long for the large type
uses the small one, and one over 18 characters ends in ".."). No mood, hunger numbers or traits.

**No app.** A sleepy face with an unplugged icon in the strip.

## 4. Controls

The v1 board has one button, BOOT, and a resistive touchscreen that needs a
firm press ([DEVICE.md](DEVICE.md) §3). None of the controls affect your
agents.

| Input | Does |
| --- | --- |
| Press BOOT, or tap the face | Boop it; acknowledges a cheer; quiets the nudges if something needs you |
| Hold BOOT | Push-to-talk while held |
| Tap the status strip | Cycle screens: face → threads → stats → face (ignored on the no-app screen) |
| Touch and hold the status strip | Focus mode on or off |
| Touch and hold the face | A mumble and face that show how Boop feels (no face while something needs you) |

A press shorter than 400 ms is a tap, and holding for 400 ms or more starts
push-to-talk until you let go. A touch held for 600 ms or more is a
touch-and-hold. On the screens that show the face, every press and touch
gets visible feedback within 20 ms, before the Mac hears about it: pressing
BOOT or the face squashes it a little, and a finger on the strip lights its
top line amber. On threads and stats the strip still lights at once, but
anything else shows when the screen changes, on release (or when
push-to-talk starts).

When an external main button is added, it takes over BOOT's jobs, and BOOT
becomes a secondary button: a press cycles screens and a hold toggles focus.

## 5. Talking to Boop

Hold BOOT and speak, or click **Talk** in the popover, speak, and click
**Send**. Either way the Mac's mic records, and it's on only while you
hold the button or until you click Send.

1. **Hold, or click Talk:** the listening face appears at once, on the
   device and in the popover.
2. **Release, or click Send:** a thinking face covers the 2–3 s wait.
3. **Reply:** a mumble and a face. It's never a sentence, and never an
   answer to a question.

**You can always tell the mic is on.** While it is, the menu-bar icon
turns recording red with a bigger dot, the popover's line says
"Listening…" with a red dot, and Talk becomes a red Send button. macOS
also shows its own microphone indicator. The mic turns itself off after
30 s, and at once if the link to the device drops while BOOT is held
(its release could never arrive). What was heard up to then still goes to
Boop. The first time, macOS asks for Speech Recognition and then the
Microphone; if either is refused, or on-device recognition isn't
available, the device shrugs and the popover says "*name* can't hear you"
and where to allow it.

Things worth saying: "shut up" (Boop goes quiet for a while), "good job",
"remember I ship on Fridays", or just mumbling at it. Audio is thrown away at
once. What you said stays in Boop's short conversation with its brain, in
memory only, until that starts over ([HARNESS.md](HARNESS.md) §4).

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
      "See exactly what gets added" shows each file and its hooks. If
      `boop-hook` isn't built, the switches are off and a line says to run
      `make build`, restart Boop, and connect the agents in Settings.
   4. **Wake up:** what happens next (plug in the body; macOS asks for
      Bluetooth, and for the microphone on the first push-to-talk), then
      "Wake *name* up". This saves Boop, adds the chosen hooks and starts
      it.
3. The app finds `Boop-XXXX` over Bluetooth and connects, and the device
   gets Boop's name. There's no pairing code in v1
   ([PROTOCOL.md](PROTOCOL.md) §2). With no sessions yet Boop sleeps; its
   first activity, a hook or a tap, wakes it with a stretch and a yawn
   ([BEHAVIORS.md](BEHAVIORS.md) §3.3).
4. Boop uses Apple's on-device model by default, with no setup. Settings
   has a field for your own API key, for cloud brains, which come later
   ([FUTURE.md](FUTURE.md)). On Macs without Apple's model, Boop still works
   fully on rules, with a simpler personality.

## 7. The Mac app

It never pops up by itself after setup and never sends notifications. The
device does the nudging.

**The menu-bar icon** is Boop's eyes and little smile, drawn from the
device's face: closed while Boop is asleep, open while agents are idle,
with a small dot while they work, amber when something needs you, and
recording red with a bigger dot while the Mac's mic is on (§5).

**The popover** is one 360 pt column on warm paper (the look below).
Clicking the icon opens it on the overview. Settings and setup open inside
it, never in separate windows. Escape or a click outside closes it, and
closing it from Settings returns to the overview next time. Its height
follows its content, and a long pane scrolls.

**Overview**, top to bottom. It only shows; every control is in Settings,
except Talk, which is there to be used in the moment.

| Area | Content |
| --- | --- |
| Header | A small copy of Boop's face on black glass (it blinks, glances about while agents work, looks up with an amber rim when something needs you, sleeps with its eyes closed, and looks up wide-eyed while listening), Boop's name, a tone dot with one short line ("Listening…", "Working on 2 sessions", "Needs you", "Hanging out", "Napping"), whether the body is connected ("Connected", "Looking…" or "No device"), and under it the Talk button (§5), which turns into a red Send while the mic is on. Which board it is never shows |
| Modes | Small reminders only when a mode is on: Focus, Quiet with minutes left, Muted, Away |
| Notices | "Restart your agent sessions" after hooks change (dismissable), why Boop couldn't start, or "*name* can't hear you" when push-to-talk can't use the mic (dismissable; the next Talk clears it) |
| Needs you | An amber card: agent · project, "Answer it in the agent's window", and "+N more" |
| Sessions | Grouped by agent, like the threads screen: one row per project with a coloured edge and a status chip (needs you, working, idle). Empty: "No agents awake" |
| Together | Boop's record, as totals across all projects: the level ring with the level inside and the percentage to the next, then tasks finished, projects and days together. Never broken down by project |
| Footer | Settings on the left, Quit on the right |

**Settings**, one scrolling pane with Back at the top:

| Group | Controls |
| --- | --- |
| Sound & focus | Volume (0–10, 0 shows "Off"), focus mode, "I'm away" (pauses hunger) |
| Agents | Claude Code and Codex: connected, not connected, not found or needs a repair, with Connect, Repair or Remove. If `boop-hook` isn't built, each says so ("Run make build, then restart Boop") with no button |
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
glass, lavender-white eyes) and its face geometry (§2). Looping motion is limited to the face and the dot while
something is live. Tokens live in `app/Boop/Views/Theme.swift`.
