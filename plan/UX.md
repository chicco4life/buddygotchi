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
shows, the face eases up into the top 144 px at 85% size. Leaning in makes
the needs-you face bigger, so at 85% its eyes match the idle face's.

**The face** is pixel art:

- **Grid.** Every part is built from square 3 px blocks, with no
  anti-aliasing. The face's origin snaps to the grid and every part sits
  a whole number of blocks from it, so the face moves a block at a time,
  as one sprite, and no part lags behind another.
- **Eyes.** Warm-white windows 13 blocks (39 px) square, 144 px apart:
  four panes around a one-block cross, each pane's corners softened by a
  pixel. No pupils, and every expression keeps the windows.
- **Looking.** The whole eye moves. On a big sideways look the near eye
  grows a pair of blocks and the far one shrinks as much, as if Boop
  turned its head; a small look (working's) keeps them equal.
- **Lids.** A lid takes whole rows off the top, straight across; happy
  takes rows off the bottom instead, a squint as if the cheeks pushed it
  up. A pane left under two blocks tall goes altogether, so no sliver
  floats like a brow. An eye too thin for panes is one bar, and a shut eye
  is two blocks thick, as heavy as the mouth.
- **Cheeks.** Two coral blocks side by side under each eye, towards the
  outside, level with the mouth. They rise with the happy squint.
- **Mouth.** Small pixel shapes, never curves: a flat bar as wide as an
  eye at rest (narrower in some looks), a small "u" smile, a small "o"
  when open, and a small filled cup when happy and open. It follows the
  eyes' look a little.
- **Extras.** A tap and a cheer pop a pixel heart in at the top right,
  small then full size, a stronger coral than the cheeks so the pinks
  don't clash. Working, a sky-blue sweat drop slides down beside the right
  eye; it goes whenever the heart shows, since they share a spot. Asleep,
  a "zzZZ" climbs up from the right eye a letter at a time, two small z's
  then two big Z's, clear of the screen's edges even with the bubble. When
  each plays is in [BEHAVIORS.md](BEHAVIORS.md) §2 and §5.
- **Motion.** The face eases between any two expressions in 150 ms or
  less and never cuts hard: whatever changes mid-blend or mid-animation
  ("needs you" arriving under a cheer or `listening`, the working count
  crossing 3), the blend starts from the frame that was showing. The
  backlight eases over the same 150 ms. Breathing and listening bob the
  whole face a block instead of pulsing its size, which would pop single
  parts.

**The bubble** is empty most of the time. It shows a mumble, as its one
real word in amber among grey squiggles for the gibberish, or who needs
you (§3). The squiggles give up their room before the word is cut, so a
word ends in ".." only when it's too long for the bubble on its own. A
project name too long for the device arrives already cut, ending ".."
([PROTOCOL.md](PROTOCOL.md) §3). Accented letters show plain (é as e),
and anything else the font lacks as "?".

**The status strip** shows how many sessions need you (amber, hidden at
zero) and how many are working (grey), with icons at the right for quiet
mode and no app. With no app, only its icon shows. With nothing to show
it's bare glass with no divider, and the face doesn't move when it fills.

**The debug label**, off unless the firmware is built with
`-DBOOP_DEBUG_LABEL=1` (`firmware/platformio.ini`), shows what the face is
following in tiny faint 5×7 text at the top left of the face, needs-you
and no-app screens: the animation, or else the look (`idle`, `working`,
`asleep`, `needs_you`; no app shows `asleep`). Frozen-clock frames leave
it out, so simulator and scenario screenshots don't change.

## 3. Screens

**Face.** The default. Everything in [BEHAVIORS.md](BEHAVIORS.md) happens
here.

**Needs you.** The face moves up and the bubble says who (the
`plus-one-more` shot of `firmware/test/scenarios/needs_you.jsonl`):

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

**No app.** The asleep face, with only the unplugged icon in the strip
([BEHAVIORS.md](BEHAVIORS.md) §3.4).

The only other screen is the debug test pattern
([VERIFICATION.md](VERIFICATION.md) §3). The threads and stats screens are
parked ([FUTURE.md](FUTURE.md)).

## 4. Controls

The v1 board has one button, BOOT, and a resistive touchscreen that needs
a firm press ([DEVICE.md](DEVICE.md) §1). Neither affects your agents.

| Input | Does |
| --- | --- |
| Tap BOOT (under 400 ms), or touch the screen anywhere | Boop it: `wiggle`, or only the press squash while something needs you or `listening` waits for the reply. Poking it over and over annoys it ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |
| Hold BOOT (400 ms or more) | Push-to-talk until you let go (§5) |

Every press and touch squashes the face a little at once, before the Mac
hears about it ([ARCHITECTURE.md](ARCHITECTURE.md) §9 has the budget). A
touch is a tap however long it's held, and counts when you lift your
finger; the strip is part of the screen, so a touch there counts too. The
panel misses readings under a light press, so a touch counts as lifted
only after 50 ms without contact, timed in real milliseconds so it ends
even while a test tool has the clock frozen. BOOT ignores an edge within
15 ms of the last one. Its timing runs on the device clock, so a press
made while a tool has the clock frozen resolves when the clock next
moves.

v1 has no job for a second button. An external main button, if one is
added, takes over BOOT's jobs ([DEVICE.md](DEVICE.md) §3).

## 5. Talking to Boop

Hold BOOT and speak, or click **Talk** in the popover, speak and click
**Send**. Either way the Mac's microphone records; the device has none.
The mic is on only while you hold the button or until you click Send, and
it also turns itself off ([BEHAVIORS.md](BEHAVIORS.md) §3.3 has the
limits and how Boop replies).

**You can always tell the mic is on.** The device and the popover's face
show `listening`, big eyes looking up; the menu-bar icon turns recording
red with a bigger dot; the popover's line says "Listening…" by a pulsing
red dot, and Talk becomes a red **Send**; and macOS shows its own
microphone indicator.

**Permissions.** The first time, macOS asks for Speech Recognition, then
the Microphone. If either is refused, on-device recognition isn't
available, or the Mac has no usable microphone, the listening face ends
and the popover says "*name* can't hear you" and why (for a refusal,
where to allow it in System Settings). The next Talk clears the notice.

**Privacy.** Recognition runs on the Mac, and the audio is thrown away as
it's heard; only whether you yelled is kept. How long your words are kept,
and what goes to TypeSafe with Jev, is in [HARNESS.md](harness/HARNESS.md) §4 and
§6.

## 6. Setup

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
      Bluetooth, and for the microphone the first time you talk), then
      **Wake *name* up**, which saves Boop, adds the chosen hooks and
      starts it.
3. The app finds `Boop-XXXX` over Bluetooth and connects, with no pairing
   in v1 ([PROTOCOL.md](PROTOCOL.md) §2). With no sessions yet Boop
   sleeps; the first agent session wakes it.
4. The brain needs no setup. Boop starts with the `boop` personality,
   and does only its rule reactions until you add a Jev API key in
   Settings (§7, [HARNESS.md](harness/HARNESS.md) §7).

## 7. The Mac app

After setup it never opens by itself and never sends notifications. The
device does the nudging.

**The menu-bar icon** is Boop's window eyes and a pixel "u" smile, drawn
on whole points so it's crisp at 1× and 2×, in the menu bar's own ink:
eyes shut to bars while Boop is asleep, open while agents are idle, and a
small dot at the top right while they work. When something needs you it
turns amber, dot and all (a deeper amber on a light menu bar, where the
device's is too pale), and while the Mac's mic is on it's recording red
with a bigger dot.

**The popover** is one 360 pt column on warm paper. Settings and setup
open inside it, never in windows. Escape or a click outside closes it;
closing it from Settings returns to the overview next time, while
unfinished setup keeps its place. Its height follows its content, and a
long pane scrolls. ⌘, opens Settings, ⌘[ goes back and ⌘Q quits.

**Overview**, top to bottom. It only shows; every control is in Settings,
except Talk, which is there to be used in the moment.

| Area | Content |
| --- | --- |
| Header | A small copy of Boop's face on black glass (below) and its name. At the right, whether the body is "Connected", "Looking…" or "No device", and the Talk button (§5) |
| Status line | Under the name, a dot and one line: "Listening…", "Needs you" (or "*N* sessions need you"), "Working on *N* sessions", "Hanging out" or "Napping"; "Waking up…" until Boop starts, or "Not running" if it couldn't |
| Chips | Small chips, only when something isn't the usual: the personality when it isn't `boop` ("Chatter"), "Quiet · *N* min", Muted |
| Notices | "Boop couldn't start", with why in plain words (another copy is running, it can't listen for hooks, or look in `boop.log`). "*name* can't hear you" when push-to-talk can't use the mic, and "Restart your agent sessions" after hooks change, both dismissable |
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
| What *name* remembers | Each lasting fact you told Boop (About you and Preferences in `long-term.md`), with a button to forget it. With none yet: "Nothing yet. Tell *name* something lasting about you, like "remember I ship on Fridays", and it keeps it here." |

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
strip; sage means connected or on, clay means trouble, and recording red
means the mic is on.

Every text tone, button labels included, clears 4.5:1 on what it sits on
(the paper, a card, the well, its own chip, the needs-you card). A filled
button stands 3:1 off its card, and the coloured menu-bar icons 3:1 off a
light or dark menu bar. `Boop --snapshots DIR` checks it all on every run.
The faint tone is only for decoration and disabled things.

The face tile uses the device's colours, geometry and pixel mouths (§2),
in square blocks snapped to the screen's pixels, so it's as crisp as the
device and moves a block at a time. Its looks follow the device's: working
lowers the lids, looks down and glances about; needs you leans in with an
amber rim; listening looks up wide-eyed; asleep shuts its eyes. It blinks
every few seconds, except asleep or with Reduce Motion on. Only the face
and the status dot loop, and the dot pulses only while something is live:
working, needs you or listening.
