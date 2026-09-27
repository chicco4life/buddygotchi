# Boop: UX

Updated 2026-09-27. What you see and touch: the device's screen and
controls, setup, and the Mac app. What Boop does in each situation is in
[BEHAVIORS.md](BEHAVIORS.md), and how it sounds is in [VOICE.md](VOICE.md).

## 1. Surfaces

| Surface | Role |
| --- | --- |
| The device | The creature: face, bubble, status strip, amber light, speaker, the BOOT button and a touchscreen |
| The Mac app | A quiet menu-bar app for setup, settings and your sessions |
| The agent's own window | Where you approve or deny. Boop only tells you something is waiting |

Most days the device is the only one you look at.

## 2. The screen

Boop sits sideways, so its screen is landscape, 320×240, with the USB-C
port on the right ([DEVICE.md](DEVICE.md) §4). Everything is drawn on
black, which the backlit panel shows as black glass.

```
┌──────────────────────────────────┐
│                                  │
│       ▐██▌        ▐██▌           │  face, the top 144 px
│     ▪▪        ‿        ▪▪        │
│                                  │
├──────────────────────────────────┤
│           [ keyboard ]           │  props, or the bubble when it shows: 60 px
├──────────────────────────────────┤
│ ● 1 needs you  ◦ 4             ▯ │  status strip, the bottom 36 px
└──────────────────────────────────┘
```

**The face is its mood design.** Every mood (the seven are in
[harness/DECISIONS.md](harness/DECISIONS.md) §2.3) has a design for each look and for the
cheer: idle, working, needs you and task complete. Asleep and no app are
one design each, the same in every mood. The designs are the designer's
animated SVGs in `internal/tools/facegen/design/` (their README says what
each one shows), and the device draws them exactly, pixel for pixel, as
Chrome draws the SVGs ([DEVICE.md](DEVICE.md) §6). A mood picks the set,
and the look or the cheer picks the design in it
([BEHAVIORS.md](BEHAVIORS.md) §2, §5). [This
sheet](evidence/2026-09-27-mood-faces/designs-vs-device.png) has every
one, 2.5 s in.

- **Shared by every design.** Warm-white window eyes, four panes each,
  with a small mouth and two coral cheek blocks under each eye, on black.
  Moods change the lids (stepped, never curved), the eyes' size and the
  mouth. Every shape sits on whole pixels, with no anti-aliasing.
- **Props.** Below the face, in the band the bubble uses: a keyboard
  while working, an amber "?" sign while something needs you, a result
  card on a tray for the cheer, and a grey broken-link sign with no app.
  Asleep has a small grey Z by the right eye.
- **Motion.** Each design moves in whole-pixel steps on its own clock,
  which starts when its look or cheer starts: a breath, keys lighting in
  the mood's rhythm, a lean toward you that plays once when something
  needs you, the card rising once for the cheer.
- **What the device adds.** Blinks, at the device's own pace
  ([BEHAVIORS.md](BEHAVIORS.md) §2), show the design's closed eyes. A tap's
  wiggle keeps the design and its clock, sways the face 3 px either way
  and pops a pixel heart in at the top right, small then full size, a
  stronger coral than the cheeks. A press dips the face 2 px at once
  (§4). While Boop mumbles, the bubble takes the props' band, and the
  mouth is a small "o" for the first half of each syllable.
- **Switching designs.** The face never cuts hard: a change to another
  design (another look, the cheer, the mood) shuts the eyes for 150 ms
  and opens them on the new one, and so does a new cheer over a cheer.
  The new design's clock starts with its look; the mood changing mid-cheer
  keeps the cheer's clock. The backlight eases over the same 150 ms.

**The bubble** is empty most of the time. It shows a mumble, as its one
real word in amber among grey squiggles for the gibberish. The squiggles give up their room before the word is cut, so a
word ends in ".." only when it's too long for the bubble on its own. A
project name too long for the device arrives already cut, ending ".."
([PROTOCOL.md](PROTOCOL.md) §3). Accented letters show plain (é as e),
and anything else the font lacks as "?".

**The status strip** shows who needs you (amber, hidden when nothing
does; §3) and how many sessions are working (grey), with an icon at the
right for no app. With no app, only its icon shows. With nothing to show
it's bare glass with no divider, and the face doesn't move when it fills.

**The debug label**, off unless the firmware is built with
`-DBOOP_DEBUG_LABEL=1` (`firmware/platformio.ini`), shows what the face is
following in tiny faint 5×7 text at the top left of the face, needs-you
and no-app screens: the animation, or else the look (`idle`, `working`,
`asleep`, `needs_you`, `no_app`). Frozen-clock frames leave
it out, so simulator and scenario screenshots don't change.

## 3. Screens

**Face.** The default. Everything in [BEHAVIORS.md](BEHAVIORS.md) happens
here.

**Needs you.** The mood's needs-you design, with its amber sign, and the
strip says who: the oldest waiting session's agent and project in amber,
cut to fit, then "+N" in grey for the others, then the working count
(the `plus-one-more` shot of
`internal/firmware/test/scenarios/needs_you.jsonl`):

```
┌──────────────────────────────────┐
│       ▐██▌        ▐██▌           │
│               ‿                  │
├──────────────────────────────────┤
│              [ ? ]               │  the sign, in the props' band
├──────────────────────────────────┤
│ ● codex · landing +1  ◦ 1        │  who, in amber; "+1" and the count in grey
└──────────────────────────────────┘
```

**No app.** The no-app design, low eyes and a grey broken-link sign, with
only the unplugged icon in the strip ([BEHAVIORS.md](BEHAVIORS.md) §3.4).

The only other screen is the debug test pattern
([VERIFICATION.md](VERIFICATION.md) §3). The threads and stats screens are
parked ([FUTURE.md](FUTURE.md)).

## 4. Controls

The v1 board has one button, BOOT, and a resistive touchscreen that needs
a firm press ([DEVICE.md](DEVICE.md) §1). Neither affects your agents.

| Input | Does |
| --- | --- |
| Press BOOT, or touch the screen anywhere | Boop it: `wiggle`, or only the press dip while something needs you. Poking it over and over annoys it ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |

Every press and touch dips the face 2 px at once, before the Mac
hears about it ([ARCHITECTURE.md](ARCHITECTURE.md) §9 has the budget). A
press or touch is a tap however long it's held, and counts when you lift
your finger; the strip is part of the screen, so a touch there counts too. The
panel misses readings under a light press, so a touch counts as lifted
only after 50 ms without contact, timed in real milliseconds so it ends
even while a test tool has the clock frozen. BOOT ignores an edge within
15 ms of the last one. Its timing runs on the device clock, so a press
made while a tool has the clock frozen resolves when the clock next
moves.

v1 has no job for a second button. An external main button, if one is
added, takes over BOOT's jobs ([DEVICE.md](DEVICE.md) §3).

## 5. Setup

1. Plug the device into USB power.
2. Install and open the app. The first time, its popover opens under the
   menu-bar icon by itself and walks through setup one step at a time,
   with Back from the second step on. Closing the popover halfway keeps
   your place; clicking the icon brings it back.
   1. **Hello:** Boop's face and one sentence about what it does.
   2. **Name:** a name, for keeps (up to 23 bytes, the protocol's limit;
      [ARCHITECTURE.md](ARCHITECTURE.md) §4.2 has its other rules), and
      one question: sweet or cheeky?
   3. **Agents:** Claude Code and Codex, each found on this Mac or not,
      with a switch to watch it ([ADAPTERS.md](ADAPTERS.md) §5). "See
      exactly what gets added" shows each settings file and its hooks. If
      `boop-hook` isn't built, the switches are off and a line says to run
      `make build`, restart Boop, then connect the agents in Settings.
   4. **Wake up:** what comes next (plug in the body; macOS asks for
      Bluetooth), then
      **Wake *name* up**, which saves Boop, adds the chosen hooks and
      starts it.
3. The app finds `Boop-XXXX` over Bluetooth and connects, with no pairing
   in v1 ([PROTOCOL.md](PROTOCOL.md) §2). With no sessions yet Boop
   sleeps; the first agent session wakes it.
4. The brain needs no setup. Boop starts with the `boop` personality,
   and does only its rule reactions until you add a Jev API key in
   Settings (§7, [HARNESS.md](harness/HARNESS.md) §7).

## 6. The Mac app

After setup it never opens by itself and never sends notifications. The
device does the nudging.

**The menu-bar icon** is Boop's window eyes and a pixel "u" smile, drawn
on whole points so it's crisp at 1× and 2×, in the menu bar's own ink:
eyes shut to bars while Boop is asleep, open while agents are idle, and a
small dot at the top right while they work. When something needs you it
turns amber, dot and all (a deeper amber on a light menu bar, where the
device's is too pale).

**The popover** is one 360 pt column on warm paper. Settings and setup
open inside it, never in windows. Escape or a click outside closes it;
closing it from Settings returns to the overview next time, while
unfinished setup keeps its place. Its height follows its content, and a
long pane scrolls. ⌘, opens Settings, ⌘[ goes back and ⌘Q quits.

**Overview**, top to bottom. It only shows; every control is in Settings.

| Area | Content |
| --- | --- |
| Header | A small copy of Boop's face on black glass (below) and its name. At the right, whether the body is "Connected", "Looking…" or "No device" |
| Status line | Under the name, a dot and one line: "Needs you" (or "*N* sessions need you"), "Working on *N* sessions", "Hanging out" or "Napping"; "Waking up…" until Boop starts, or "Not running" if it couldn't |
| Chips | Small chips, only when something isn't the usual: the personality when it isn't `boop` ("Chatter"), Muted |
| Notices | "Boop couldn't start", with why in plain words (another copy is running, it can't listen for hooks, or look in `boop.log`), and "Restart your agent sessions" after hooks change, dismissable |
| Needs you | An amber card for the session that has waited longest: agent · project, the name in full, "Waiting for you. Answer it in the agent's window.", and "+*N* more" |
| Sessions | Grouped by agent, Claude Code then Codex: one row per session, with its project, a coloured edge and a status chip (needs you, working, idle), waiting first, then working, then idle. With none: "No agents awake" |
| Footer | Settings on the left, Quit on the right. In Settings, the left shows the app's version and the device's firmware |

After you approve a long command, the needs-you card stays until the
command finishes ([ADAPTERS.md](ADAPTERS.md) §4).

**Settings** is one scrolling pane with Back at the top:

| Group | Controls |
| --- | --- |
| Sound | Volume, 0–10 (0 shows "Off") |
| Agents | Claude Code and Codex, each with its state and a button (below) |
| Device | *Name*'s body: connected over Bluetooth or USB, or still looking, with a Reconnect button that drops the link and looks again at once ([PROTOCOL.md](PROTOCOL.md) §2, "Reconnecting") |
| Personality | Boop or Chatter, with one line on what the chosen one does ([BEHAVIORS.md](BEHAVIORS.md) §6); it takes effect from the next event. Below it, the Jev API key, kept in the Keychain; its caption says that with Jev, what happens and Boop's personality and mood go to TypeSafe with each call, and that without a key Boop does only its rule reactions. A saved key is used from the next event, and saving an empty one removes it |

Each agent's row in Agents:

| State | Button |
| --- | --- |
| Connected | Remove |
| Not connected | Connect |
| Needs a repair | Repair |
| Not found on this Mac | None |
| Can't read its settings: … | None |
| boop-hook isn't built. Run make build, then restart Boop. | None |

Without a button, opening the popover looks again. A change that fails
says why on the row ("Couldn't change its hooks: …"); one that works asks
you to restart open agent sessions.

The board's id never shows. The name and sweet-or-cheeky are set once, at
setup, and never change.

**The look** is the device's "Warm Terminal" ([VISION.md](VISION.md),
"Look"), in light and dark, with its tokens in `app/Boop/Views/Theme.swift`.
Warm paper and ink; sections separated by space and a small tracked-out
label, with no divider lines, and grouped into raised cards with a
hairline edge; names, titles and numbers in the rounded system face. The
one filled button on a screen is black glass with an oat label, or oat
with a glass label on dark paper, where glass would read as a hole. Amber
is only for needs you. Working and idle are greys, as on the device's
strip; sage means connected or on, and clay means trouble.

Every text tone, button labels included, clears 4.5:1 on what it sits on
(the paper, a card, the well, its own chip, the needs-you card). A filled
button stands 3:1 off its card, and the coloured menu-bar icons 3:1 off a
light or dark menu bar. `Boop --snapshots DIR` checks it all on every run.
The faint tone is only for decoration and disabled things.

The face tile shows the face of the device's design for Boop's mood and
look (§2), without the props, as its look starts: idle, working, needs
you (with an amber rim) or asleep. `facegen` writes those faces into
`app/Boop/Views/FaceDesigns.swift` from the same designs as the device's,
in the designs' own colours. Setup's sweet and cheeky previews are the
happy and the proud idle faces. It blinks every few seconds, and into a
new face when the mood or the look changes, except asleep or with Reduce
Motion on. Only the face
and the status dot loop, and the dot pulses only while something is live:
working or needs you.
