# Webcam check: looks, the cheer, reactions and a tap

2026-09-28, about 05:10, by the orchestrator. The owner asked for webcam
verification tonight and set the camera up before bed; it was pointed at the
board. It's L3 in [VERIFICATION.md](../../../VERIFICATION.md), done with the
`webcam-verify` skill.

**Setup.** The camera was the MacBook Air Camera at 30 fps. Each clip ran
29.9 fps with no capture gaps in the reviewed windows. The board ran
firmware `1.0.0`, `sha e13cc1245e` (`main`'s firmware), driven over USB.
Bluetooth was only advertising and `link` read `usb`, so nothing else wrote
to the board. The clock was running. Every scenario after the first ran at
`vol 0`, because it was 5 am. The cheer preset played its mumble at the
default volume once.

Clip lengths are 7–14 s each, and I read every frame of the windows below.
I reviewed image sequences, not real-time playback. The room footage stays
in `/tmp/boop-cam/`; only the screen crops here are in git.

## What I looked at

| Scenario | How it was driven | What happened | Verdict |
| --- | --- | --- | --- |
| Cheer (`boopctl cam clip cheer`) | The preset | Working switches behind a blink (0.86 s). The card rises onto the tray with the mood's sparkles, 1.2–2.4 s. Blink back to working (3.1 s), the "done" bubble with the "o" mouth, then the keyboard. [cheer-sheet.png](cheer-sheet.png) | Pass |
| Reaction: grumpy face over happy working, 2 loops | `moment` with `mood: grumpy`, `loops: 2`, `id` | The switch blink runs 2.27–2.40 s. Then grumpy's stepped scowl appears, the bubble ("again ~~~") takes the keyboard's band, and the mouth talks. After the line, grumpy's working design carries on (a key knocked loose at 7.4 s). It was still grumpy when the 10 s clip ended: grumpy-working loops every 4.2 s, so two loops end about 11 s in. [reaction-grumpy-arrives.png](reaction-grumpy-arrives.png) | Pass (the end is after the clip) |
| Reaction: proud face, 1 loop, then a tap | `moment` with `mood: proud`, `loops: 1`; then `anim: wiggle` | Proud's smirk and uneven lids from 1.85 s, with the "finally" bubble up to about 3.6 s. It held through a normal blink at 6.2 s. At 7.63–7.73 s the switch blink opened on happy's working face, 5.8 s after it began, within proud-working's 7 s loop. The tap at about 10.8 s swayed the face with the pixel heart, then settled. [reaction-proud-returns.png](reaction-proud-returns.png) | Pass |
| Looks in four moods | `state` lines | Sad idle has raised inner corners and a quivering mouth. Excited working has taller eyes and the keyboard with its count. Determined idle has drawn-in lids and a bare strip, which is right for nothing working. Grumpy needs-you has the amber "?" sign and "claude · buddygotchi +1". [moods.png](moods.png) | Pass |

## Deviations and limits

- **Sad's tears aren't visible on camera.** The design draws them as two
  8×3 px blue bars at the bottom edge of each eye (`sad--idle.svg`), and at
  full backlight the camera's glow around the eyes swallows them. The
  device draws the designs pixel for pixel (`facegen --check`, 337 frames),
  so this is inconclusive on camera, not a defect. A crop at `dbg.light bl
  40` would show them, but `play` and `state` reset the light.
- **Holds are long with today's designs.** A "once" hold lasted 5.8 s over
  proud's working look, whose loop is 7 s. "Twice" over grumpy's working
  look is about 8–11 s. That's the loop table working as specified, and
  it's why the morning report asks about capping a face's first loop. The
  loopable designs coming today will change these lengths.
- The switch blinks sometimes catch a frame with both designs' props (the
  cheer at 3.1 s). The panel's scan and the camera's rolling shutter can
  make that; it isn't a hard cut.
- These are a few scenarios, not a full hardware pass: no asleep, no-app,
  or Bluetooth.
