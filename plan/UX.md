# Boop: UX

Updated 2026-09-27. What the person sees and touches: the screen, the
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

- **Face.** Pixel art, after the owner's reference render (2026-09-26):
  everything is built from square 3 px blocks on one grid, with no
  anti-aliasing. The eyes are warm-white windows, 13 blocks (39 px) square
  and 144 px apart, each four panes around a one-block cross, with a pixel
  softened off each pane's corners. There are no pupils. Two pink blush
  blocks sit under each eye, towards the outside, and the mouth is a flat
  bar as wide as an eye, level with the cheeks. The face blends between
  expressions in 150 ms or less and never cuts hard; the grid makes it
  move a block at a time. That holds whatever changes mid-animation:
  "needs you" arriving under a cheer or `listening`, or the working count
  crossing 3, eases from the frame that was showing. The backlight eases
  over the same 150 ms. A blink shrinks the eye towards a one-block bar;
  an eye too thin for its panes is drawn as one bar. A lid takes whole rows
  of blocks off the top, and cuts each half of the eye flat at its own
  height, so a tilted lid steps once between the panes. To look somewhere
  the whole eye moves, and the eye on the side it looks towards grows a
  little, as if Boop turned its head. Every expression keeps the window
  eyes: arches and wide grins on boxy eyes read as uncanny (the owner,
  2026-09-26). Happy, the bottom of each eye rises (a squint, as if the
  cheeks pushed it up; the cheeks rise with it) and the top stays put. The
  mouth is drawn as small pixel shapes, not curves: the bar at rest, a
  small "u" smile, a frown, a small "o" while talking, and a small filled
  cup when it's happy and open. The eyes stay white. A tap and a cheer pop a pixel
  heart in at the top right of the face. Asleep, a pixel "zzZZ" climbs up
  from the right eye one letter at a time. Working, Boop strains every
  couple of seconds, and a pixel sweat drop slides down beside the right
  eye ([BEHAVIORS.md](BEHAVIORS.md) §2).
- **Bubble.** Empty most of the time. It shows either a mumble's one real
  word, or who needs you.
- **Status strip.** How many sessions need you (amber, hidden at zero) and
  how many are working (grey), plus icons at the right for quiet and no
  app.
- **Debug label.** A debug-only aid, off unless the firmware is built with
  `BOOP_DEBUG_LABEL=1` (the board build sets it in
  `firmware/platformio.ini`). On the face, needs-you and no-app screens,
  the name of what the face is showing sits in tiny faint 5×7 text at the
  top left: the moment's anim (`cheer`, `wiggle`, `listening`) or else the
  look (`idle`, `working`, `asleep`, `needs_you`; no app shows `asleep`). Frames drawn with a
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

**No app.** The asleep face with an unplugged icon in the strip
([BEHAVIORS.md](BEHAVIORS.md) §2).

There are no other screens. The threads and stats screens are parked
([FUTURE.md](FUTURE.md)).

## 4. Controls

The v1 board has one button, BOOT, and a resistive touchscreen that needs a
firm press ([DEVICE.md](DEVICE.md) §3). None of the controls affect your
agents.

| Input | Does |
| --- | --- |
| Press BOOT, or touch the screen anywhere | Boop it (`wiggle`); only the press squash if something needs you. Poking it over and over annoys it ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |
| Hold BOOT | Push-to-talk while held |

A press shorter than 400 ms is a tap, and holding BOOT for 400 ms or more
starts push-to-talk until you let go. A touch is a tap however long it's
held, and counts when you lift your finger. Every press and touch gets
visible feedback within 20 ms, before the Mac hears about it: the face
squashes a little.

When an external main button is added, it takes over BOOT's jobs. BOOT has
no job of its own after that until a second button is needed.

## 5. Talking to Boop

Hold BOOT and speak, or click **Talk** in the popover, speak, and click
**Send**. Either way the Mac's mic records, and it's on only while you
hold the button or until you click Send.

1. **Hold, or click Talk:** the listening face appears at once, on the
   device and in the popover.
2. **Release, or click Send:** the listening face stays for the 2–3 s
   wait, and at most 8 s.
3. **Reply:** usually a mumble, over the face that's showing. It's never
   a sentence, and never an answer to a question.

**You can always tell the mic is on.** While it is, the menu-bar icon
turns recording red with a bigger dot, the popover's line says
"Listening…" with a red dot, and Talk becomes a red Send button. macOS
also shows its own microphone indicator. The mic turns itself off after
30 s, and at once if the link to the device drops while BOOT is held
(its release could never arrive). What was heard up to then still goes to
Boop. The first time, macOS asks for Speech Recognition and then the
Microphone; if either is refused, on-device recognition isn't
available, or the Mac has no usable microphone, the listening face ends
and the popover says "*name* can't hear you" and why.

Things worth saying: "be quiet" (Boop zips its mouth and goes quiet for a
while), "good job", "remember the demo is on Thursday" (kept for today),
"remember I ship on Fridays" (kept for good, under What Boop remembers), or
just mumbling at it.
Yelling at it, or telling it off, makes it sad but doesn't quiet it. Audio
is thrown away at once; Boop keeps only whether you yelled
([BEHAVIORS.md](BEHAVIORS.md) §3.3). What you said stays in the brain's
transcript, in memory only, until its window moves past it
([HARNESS.md](HARNESS.md) §4).

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
3. The app finds `Boop-XXXX` over Bluetooth and connects. There's no
   pairing code in v1
   ([PROTOCOL.md](PROTOCOL.md) §2). With no sessions yet Boop sleeps, and
   the first agent session wakes it ([BEHAVIORS.md](BEHAVIORS.md) §2).
4. Boop's brain needs no setup. It starts in normal mode, where Jev, a
   "system one" model online, decides what Boop does once you add your own
   API key in Settings, and plain rules decide until then; Apple's
   on-device model writes its words. Settings also has chatty and calm
   ([BEHAVIORS.md](BEHAVIORS.md) §6, [HARNESS.md](HARNESS.md) §6). On Macs without
   Apple's model nothing writes: Boop still reacts to everything, but its
   mumbles have no real word and it remembers nothing you tell it.

## 7. The Mac app

It never pops up by itself after setup and never sends notifications. The
device does the nudging.

**The menu-bar icon** is Boop's window eyes and a pixel smile, drawn from
the device's face on whole points so it's crisp at 1× and 2×: closed while
Boop is asleep, open while agents are idle, with a small dot while they
work, amber when something needs you, and recording red with a bigger dot
while the Mac's mic is on (§5). On a light menu bar the amber is a deeper
one that keeps 3:1, since the device's is too pale there.

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
| Modes | Small reminders only when something isn't the usual: Chatty or Calm (normal shows nothing), Quiet with minutes left, Muted |
| Notices | "Restart your agent sessions" after hooks change (dismissable), why Boop couldn't start (in plain words: another copy is running, or it can't listen for hooks, or look in `boop.log`), or "*name* can't hear you" when push-to-talk can't use the mic (dismissable; the next Talk clears it) |
| Needs you | An amber card: agent · project (the agent alone when the project has no name), "Answer it in the agent's window", and "+N more" |
| Sessions | Grouped by agent, Claude Code then Codex whatever their state: one row per session, waiting first, with a coloured edge and a status chip (needs you, working, idle). Empty: "No agents awake" |
| Footer | Settings on the left, Quit on the right. In Settings, the left holds the app's version and the device's firmware |

**Settings**, one scrolling pane with Back at the top:

| Group | Controls |
| --- | --- |
| Sound | Volume (0–10, 0 shows "Off") |
| Agents | Claude Code and Codex: connected, not connected, not found or needs a repair, with Connect, Repair or Remove (not found has no button; opening the popover looks again). If `boop-hook` isn't built, each says so ("Run make build, then restart Boop") with no button. A Connect, Repair or Remove that fails says why on the row ("Couldn't change its hooks: …"), and only one that worked asks you to restart your agents |
| Device | Whether Boop's body is connected and how (Bluetooth or USB); its firmware version is in the footer. Not its id. A Reconnect button drops the link and looks for the device again at once ([PROTOCOL.md](PROTOCOL.md) §2, "Reconnecting") |
| Mode | Chatty, Normal or Calm, one segmented control ([BEHAVIORS.md](BEHAVIORS.md) §6), with a line saying what the chosen one does. It takes effect at once. A line under it says when Apple's model can't run, so mumbles have no word; it reads the model's availability as it is now. In Normal only, the Jev API key under it, kept in the Keychain; its caption says that with Jev, what happens and Boop's memory go to TypeSafe with each call. Without a key, Normal decides with its own table on this Mac. Saving one brings Jev in at once |
| What Boop remembers | Each line of About you and Preferences, the durable facts you told Boop, with a button to forget it. With none yet: "Nothing yet. Tell *name* something lasting about you, like "remember I ship on Fridays", and it keeps it here." |

Name and nature are set once, at setup, and don't change.

**The look** is the device's "Warm Terminal" ([VISION.md](VISION.md)
"Look"), in light and dark: warm paper and ink, black glass with an oat
label for filled buttons (oat with a glass label on dark paper, where glass
would read as a hole), and one amber accent, used
only for needs you. Working and idle are greys, as on the device's status
strip; sage means connected and a switch that's on, clay means trouble, and
recording red means the mic is on. Sections are separated by space and a
small tracked-out label, not rules, and grouped into raised cards with a
hairline edge. Names, titles and numbers use the rounded system face. Every
text tone, button labels included, clears 4.5:1 on what it sits on (the
paper, a card, the well, its own chip), a filled button stands 3:1 off its
card, and
`Boop --snapshots` checks it; the faint tone is for decoration only.
The face tile uses the device's own colours (black glass, warm-white
window eyes, pink cheeks), its face geometry and its pixel mouths (§2),
drawn in square blocks on a grid snapped to the screen's pixels: as crisp
as the device, and moving a block at a time. Its looks follow the
device's (working lowers the lids and looks down, needs you leans in).
Looping motion is limited to the face and the dot while something is
live. Tokens live in `app/Boop/Views/Theme.swift`.
