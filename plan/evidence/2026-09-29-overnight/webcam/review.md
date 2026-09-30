# Webcam review, 2026-09-29 overnight (L3, limited)

MacBook Air camera, 30 fps, the board on the desk with USB-C to the right
of the frame (the picture is upside down in the camera). Clips stayed
local; this note is all that's kept. Consecutive frames reviewed as image
sheets, not real-time playback.

| Clip | Firmware | What moved | Verdict |
| --- | --- | --- | --- |
| Engaged working face, then a `task_complete` | `a0d75321` (main), 40 MHz, full-width 12-row bands | Blinks and the finish. Three single camera frames (3.27 s, 3.43 s, 4.80 s) catch the panel mid-push: half the old eye and half the new, the push taking about 19 ms | Pass, with visible tearing on single frames |
| Test pattern at backlight 40 | 80 MHz SPI, changed columns of 6-row bands | Still | Pass: the six colours, the grey field, the arrow and the labels clean; no noise, shifted rows or wrong colours |
| Engaged working face, a failure finish, then a poke | The same | Blinks, the finish's badge and keyboards, the poke | Pass: crisp, no corruption |
| Working with a busy strip ("02"), then needs you for 8 s | `d95fbcb1`, the same push | The working props, the strip's divider and ring, the sign rising, "CLAUDE NEEDS YOU", the head peeking and blinking | Pass |

Limits: the camera's 30 fps and exposure hide anything shorter than a
frame, so "no tearing" can't be proven; single frames at 80 MHz showed no
mid-push split in these clips, where the 40 MHz clip showed three.
Colour is judged against the pattern only. Sound wasn't recorded.
