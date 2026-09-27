# Boop: UX

Updated 2026-09-28. What you see and touch: the device's screen and
controls, setup, and the Mac app. The device is the creature and the Mac
app stays out of the way. What Boop does in each situation is in
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

### The designs

**The face is its mood's design.** Each of the seven moods has four
designs: idle, working, needs you, and task complete for the cheer.
Asleep and no app are one design each, shared by every mood: 30 in all.
They're the designer's animated SVGs in `internal/tools/facegen/design/`
(its README says what each shows). `facegen` turns them into
`firmware/assets/faces.h`, and the device draws them pixel for pixel as
Chrome does ([DEVICE.md](DEVICE.md) §6). The mood picks the set, and the
look or the cheer picks the design in it ([BEHAVIORS.md](BEHAVIORS.md)
§2, §5). [This sheet](evidence/2026-09-27-mood-faces/designs-vs-device.png)
has every one, 2.5 s in.

Every design has warm-white window eyes of four panes each, a small
mouth and two coral cheek blocks under each eye, on black. Moods change
the lids (stepped, never curved), the eyes' size and the mouth. Every
shape sits on whole pixels, with no anti-aliasing, and moves in
whole-pixel steps.

| Mood | Face | Working | Cheer |
| --- | --- | --- | --- |
| Happy | Gently smiling eyes | A gentle bob | A sway, with sparkles |
| Excited | Taller, brighter eyes | A bounce, with sparks by the keyboard | A hop, with sparkles |
| Proud | Uneven half-lids and a smirk | Lifts its chin now and then | A bow, with sparkles |
| Curious | Lopsided eyes | Leans side to side | A step sideways |
| Determined | Lids drawn in | A steady nod | A small nod, and the face softens |
| Grumpy | A deep scowl | A jolt that knocks a key loose | A small dip, and a smile escapes |
| Sad | Raised inner corners, blue tears, a quivering mouth | Slumps, typing through tears | A dip, tears and a relieved smile |

For needs you, each mood's face moves once and settles: most lean up
toward you, while grumpy and sad sink a little.

| Look | Prop, in the band under the face | Motion |
| --- | --- | --- |
| Asleep | A small grey Z by the right eye; the eyes are shut bars | A 2 px breath every 8 s |
| Idle | None | Rises a pixel briefly every 9 s |
| Working | A keyboard, keys lighting in the mood's rhythm | The mood's working motion, looping |
| Needs you | An amber "?" sign that rises in | The lean, once |
| Task complete (the cheer) | A result card rising onto a tray | The mood's gesture, once each loop of the cheer |
| No app | A grey broken-link sign; the eyes are low | The same breath as asleep |

**Clocks.** A look's design runs on a clock that starts with the look. A
mood change keeps that clock, so the new face picks up mid-loop. The
cheer's design runs from the cheer's start and starts over each loop,
and a mood change mid-cheer keeps its clock too.

**Loops.** A design's loop is how long it takes to play once through:
its longest animation, leaving out the blink, which the device times on
its own (1 s for a design with nothing else moving). `facegen` reads it
from each SVG's timing, so a new design brings its own, and writes it
for the device and the Mac alike ([DEVICE.md](DEVICE.md) §6). Loops
are what moments are counted in: the cheer plays a number of them, and
a reaction's face holds a number of loops of the design it's drawn in,
ending on a boundary of that design's clock, where a design made to
loop is back at its start ([PROTOCOL.md](PROTOCOL.md) §3).

### What the device adds

| Addition | What it does | When |
| --- | --- | --- |
| Blink | The design's closed eyes, briefly | At the device's own pace ([BEHAVIORS.md](BEHAVIORS.md) §2) |
| Switch | The eyes shut for 150 ms (`kBlendMs`) and open on the new design, and the backlight eases over the same time. The face never cuts hard | Any change of design: another look, the cheer, another mood, a reaction's face coming or going, or a new cheer over a cheer |
| Wiggle | Keeps the design and its clock, sways the face 3 px either way twice, and pops a pixel heart in at the top right, small for 100 ms then full size, a stronger coral than the cheeks | A tap, for 0.7 s |
| Press | The face drops 2 px, drawn at once | While BOOT or the screen is held (§4) |
| Talking | The bubble takes the props' band, and the mouth is a small "o" for the first half of each syllable | While a mumble plays |
| Reaction | The look, or the cheer, drawn in the reaction's mood's design instead of Boop's mood, switching in and out behind the usual blink; the design's clock carries on | While the brain's reaction plays: its loops of the design, and at least its mumble and bubble ([BEHAVIORS.md](BEHAVIORS.md) §5) |

### The bubble and the strip

**The bubble** is empty most of the time. A mumble shows as its one real
word in amber among grey squiggles, up to three on each side, placed as
the word falls among the syllables; with no word, up to three squiggles.
The squiggles give up their room before the word is cut, so a word ends
in ".." only when it's too long for the bubble on its own. The bubble
stays up 1.2 s after the last syllable (`kBubbleReadMs`). Accented
letters show plain (é as e), and anything else the font lacks as "?".

**The status strip**, left to right: who needs you (an amber dot and
"agent · project" in amber, cut with ".." to fit), "+N" in grey for the
others waiting, then a grey ring and how many sessions are working
(hidden at zero). A project name too long for the device arrives already
cut, ending ".." ([PROTOCOL.md](PROTOCOL.md) §3). With no app, only the
unplugged icon shows, at the right. With nothing to show it's bare glass
with no divider, and the face doesn't move when it fills.

**The debug label**, off unless the firmware is built with
`-DBOOP_DEBUG_LABEL=1` (`firmware/platformio.ini`), shows what the face is
following in tiny faint text at the top left: the animation (`cheer`,
`wiggle`), or else the look (`idle`, `working`, `asleep`, `needs_you`,
`no_app`). Frozen-clock frames leave it out, so simulator and scenario
screenshots don't change.

## 3. Screens

The device picks one, top row first:

| Screen | When | Shows |
| --- | --- | --- |
| Test pattern | A `dbg.pattern` over USB, until the next `state` ([PROTOCOL.md](PROTOCOL.md) §5) | A fixed pattern, a solid fill or a calibration cross. Touches do nothing |
| No app | 30 s without a `state` ([BEHAVIORS.md](BEHAVIORS.md) §3.4) | The no-app design, with only the unplugged icon in the strip |
| Needs you | The last `state` has `attn` | The mood's needs-you design, and the strip says who |
| Face | Otherwise | The base look or the animation playing, the bubble, and the working count |

The needs-you screen, as the `plus-one-more` shot of
`internal/firmware/test/scenarios/needs_you.jsonl` has it:

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

## 4. Controls

The v1 board has one button, BOOT, and a resistive touchscreen that needs
a firm press ([DEVICE.md](DEVICE.md) §1). Neither affects your agents.

| Input | Does |
| --- | --- |
| Press BOOT, or touch the screen anywhere, strip included | The face dips 2 px at once. Letting go is a tap: `wiggle`, or only the dip while something needs you, and an `input` to the Mac ([PROTOCOL.md](PROTOCOL.md) §4). Poking it over and over annoys it ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |

- **A tap is a release.** A press or touch is one tap however long it's
  held, and counts when you let go.
- **The dip comes first.** It's drawn at once, ahead of the redraw cap and
  before the Mac hears anything ([ARCHITECTURE.md](ARCHITECTURE.md) §9 has
  the budget).
- **Touch.** The panel misses readings under a light press, so a touch
  ends only after 50 ms without contact (`kTouchReleaseMs`), timed in
  real milliseconds so it ends even while a test tool has the clock
  frozen.
- **BOOT.** An edge within 15 ms of the last one is ignored
  (`ButtonGesture::kDebounceMs`). It's timed on the device clock, so a
  press made while a tool has the clock frozen resolves when the clock
  next moves.

v1 has no job for a second button. An external main button, if one is
added, takes over BOOT's jobs ([DEVICE.md](DEVICE.md) §3).

## 5. Setup

1. Plug the device into USB power.
2. Install and open the app. The first time, its popover opens under the
   menu-bar icon by itself and walks through setup one step at a time,
   with a row of progress dots and Back from the second step on. Closing
   the popover halfway keeps your place; clicking the icon brings it back.

   | Step | What it asks |
   | --- | --- |
   | Hello | Boop's face, "Hi! I'm Boop." and one sentence about what it does. **Let's go** |
   | Name | A name, for keeps: at most 23 bytes, the protocol's limit ([ARCHITECTURE.md](ARCHITECTURE.md) §4.2 has its other rules). Then sweet ("Warm and encouraging") or cheeky ("Playful, a bit sassy"), with the face previewing each. **Continue** needs a name |
   | Agents | Claude Code and Codex, each found on this Mac or not, with a switch to watch it, on for each one found ([ADAPTERS.md](ADAPTERS.md) §5). "See exactly what gets added" shows each chosen settings file and its hooks. If `boop-hook` isn't built, the switches are off and a line says to run `make build`, restart Boop, then connect the agents in Settings |
   | Ready | What comes next: plug in the body, which finds the Mac over Bluetooth; macOS asks for Bluetooth; restart open agent sessions if any were chosen. **Wake *name* up** saves Boop, adds the chosen hooks, starts it and shows the overview. If saving fails, it says so and points at `boop.log` |

3. The app finds `Boop-XXXX` over Bluetooth and connects, with no pairing
   in v1 ([PROTOCOL.md](PROTOCOL.md) §2). With no sessions yet Boop
   sleeps; the first agent session wakes it.
4. The brain needs no setup. Boop starts with the `boop` personality,
   and does only its rule reactions until you add a Jev API key in
   Settings (§6, [harness/HARNESS.md](harness/HARNESS.md) §7).

## 6. The Mac app

After setup it never opens by itself and never sends notifications. The
device does the nudging.

**The menu-bar icon** is just two rounded eyes, 20×18 pt, drawn on whole
points so it's crisp at 1× and 2×. It doesn't copy the device's face,
which is too detailed to read at that size. Clicking it opens
or closes the popover.

| Boop is | Icon |
| --- | --- |
| Asleep, or not running yet | Eyes shut to bars, in the menu bar's own ink |
| Idle | Eyes open, in the menu bar's ink |
| Working | Eyes open, and a small round dot at the top right |
| Something needs you | Amber, dot and all: the device's amber on a dark menu bar, a deeper one on a light bar, where the device's is too pale |

**The popover** is one 360 pt column on warm paper, with three panes:
overview, settings and setup. They open inside it, never in windows.
Escape or a click outside closes it. Closing it from Settings returns to
the overview next time, while unfinished setup keeps its place. Its
height follows its content and a long pane scrolls; setup is a fixed
height. Opening it looks at the hooks again and refreshes everything.
⌘, opens Settings, ⌘[ goes back from it, Return presses setup's main
button and ⌘Q quits.

The footer has Settings on the left in the overview, the app's version
and the device's firmware there in Settings, and nothing there in setup;
Quit is always on the right.

### Overview

Top to bottom. It only shows; every control is in Settings.

| Area | Content |
| --- | --- |
| Header | The face tile (§7) and Boop's name. At the right, the body: "Connected", "Looking…", or "No device" when this copy runs without one |
| Status line | Under the name, a dot and one line: "Needs you" (or "*N* sessions need you"), "Working on *N* session(s)", "Hanging out" or "Napping"; "Waking up…" until Boop starts, or "Not running" if it couldn't. The dot is amber for needs you and grey otherwise, and pulses while working or needed |
| Chips | Only when something isn't the usual: "Chatter" for that personality, "Muted" at volume 0 |
| Notices | "Boop couldn't start", with why in plain words (another copy is running; it can't listen for hooks; or look in `boop.log`). "Restart your agent sessions" after hooks were added, removed or repaired, which you can dismiss |
| Needs you | An amber card for the session that has waited longest: agent · project with the project in full, "Waiting for you. Answer it in the agent's window.", and "+*N* more" |
| Sessions | "Sessions · *N*", grouped by agent, Claude Code then Codex. One row per session: its project ("Unknown project" if none), a coloured edge and a status chip (needs you in amber, working, idle), waiting first (oldest first), then working, then idle. With none: "No agents awake" and "Start Claude Code or Codex and *name* will notice." |

### Settings

One scrolling pane with Back at the top:

| Group | Controls |
| --- | --- |
| Sound | Volume, 0–10 (0 shows "Off"; 6 to start), "How loud *name* mumbles." |
| Agents | Claude Code and Codex, each with its state and a button (below). After a change that worked: "Restart open agent sessions to pick up the change." |
| Device | *Name*'s body: "Connected over Bluetooth" (or USB), "Looking for it over Bluetooth. Plug it into USB power.", or "This copy of Boop runs without a device". Reconnect drops the link and looks again at once ([PROTOCOL.md](PROTOCOL.md) §2, "Reconnecting") |
| Personality | Boop or Chatter, with one line on what the chosen one does ([BEHAVIORS.md](BEHAVIORS.md) §6); it takes effect from the next event. Without a brain, a line says *name* only cheers, wiggles and chatters by rule. Below, the Jev API key with Save, then "Saved"; its caption says it's kept in the Keychain and that with Jev, what happens and Boop's personality and mood go to TypeSafe with each call. A saved key is used from the next event, and saving an empty one removes it |

Each agent's row:

| State | Button |
| --- | --- |
| Connected | Remove |
| Not connected | Connect |
| Needs a repair | Repair |
| Not found on this Mac | None; opening the popover looks again |
| Can't read its settings: … | None |
| boop-hook isn't built. Run make build, then restart Boop. | None |
| Couldn't change its hooks: … | As for its state. Only the everyday copy of Boop changes hooks ([ADAPTERS.md](ADAPTERS.md) §5) |

The board's id never shows. The name and sweet-or-cheeky are set once,
at setup, and never change.

### The look

The device's "Warm Terminal" ([VISION.md](VISION.md), "Look"), in light
and dark, with its tokens in `app/Boop/Views/Theme.swift`. Warm paper and
ink; sections separated by space and a small tracked-out label, with no
divider lines, and grouped into raised cards with a hairline edge; names,
titles and numbers in the rounded system face. The one filled button on a
screen is black glass with an oat label, or oat with a glass label on
dark paper, where glass would read as a hole. Amber is only for needs
you. Working and idle are greys, as on the device's strip; sage means
connected or on, and clay means trouble. Only the face tile and the
status dot loop.

Every text tone, button labels included, clears 4.5:1 on what it sits on
(the paper, a card, the well, its own chip, the needs-you card). A filled
button stands 3:1 off its card, and the amber menu-bar icon 3:1 off a
light or dark menu bar. `Boop --snapshots DIR` checks it all on every run.
The faint tone is only for decoration and disabled things.

## 7. The face tile

The overview's header and setup show a small copy of Boop's face on a
black-glass tile: the face of the device's design for Boop's mood and
look, as the look starts, without the props. `facegen` writes those faces
into `app/Boop/Views/FaceDesigns.swift` from the same SVGs as the
device's, in the designs' own colours.

| Where | Face |
| --- | --- |
| Overview, asleep or not running | The shared asleep face, a little dimmed |
| Overview, idle or working | The mood's idle or working face |
| Overview, needs you | The mood's needs-you face, with an amber rim |
| Setup: Hello, Ready, and Name with sweet | Happy's idle face |
| Setup: Name with cheeky | Proud's idle face |

It blinks for 180 ms every 2.4–5.2 s, and blinks into a new face when
the mood or the look changes, as the device does. It holds still while
asleep and with Reduce Motion on. It follows the `state`, not moments,
so it never shows a reaction's borrowed face: the Mac doesn't play
moments.
