# Webcam verification

> v1's L3 checks run through `tools/boopctl cam`, which wraps this recorder
> ([plan/VERIFICATION.md](../../plan/VERIFICATION.md) L3 and §6). This page
> is for using it by hand.

Record Boop's physical screen with a Mac camera and review consecutive
frames over time. Requires macOS 14+, Command Line Tools, and camera permission;
no FFmpeg or third-party Python packages. Run commands from the repository root.
The wrapper compiles a small native AVFoundation executable into `.build/webcam`.

## Opt-in use

Use `$webcam-verify` or explicitly ask for webcam verification, then confirm
the board is positioned for that session. This mode is never automatically enabled
by animation edits or ordinary verification requests. Setup confirmation covers
the requested clips in the current session, not future sessions or background
monitoring. Normal tests do not require a camera. The reusable skill is
[`skills/webcam-verify/SKILL.md`](../../skills/webcam-verify/SKILL.md).

## Setup and recording

1. Place the board steadily in front of the laptop camera, screen facing the lens.
   Keep the whole display visible and large enough to judge the eyes. Use even
   lighting; move it farther away if the fixed-focus camera makes it blurry.
2. List cameras, then explicitly choose the laptop camera ID:

   ```sh
   tools/webcam/webcam.sh list
   tools/webcam/webcam.sh record --camera CAMERA_ID --seconds 3 --out /tmp/boop-camera-framing
   ```

   macOS may request camera access for the launching app. If denied, enable it
   in System Settings → Privacy & Security → Camera. A sandbox that hides cameras
   needs camera access outside that sandbox. Listing cameras does not record.
3. Inspect a short framing sequence:

   ```sh
   tools/webcam/webcam.sh analyze --input /tmp/boop-camera-framing/capture.mov \
     --out /tmp/boop-camera-framing-review --seconds 0.1
   ```

   Read the full-resolution `preview.png` and `sequence-000.png`. If the screen is blurry, clipped, reflecting light,
   or overexposed, reposition and take another short clip before judging motion.
4. Record one named scenario per clip, starting before triggering it:

   ```sh
   tools/webcam/webcam.sh record --camera CAMERA_ID --seconds 10 --fps 30 \
     --out /tmp/boop-camera-cheer
   ```

   Wait for `RECORDING …` before triggering the moment in a second terminal or
   a separate agent tool call. Recording stops automatically (1–60 seconds).
   The camera must support the requested rate; 60 fps is optional, never assumed.
   Video only: no microphone input, audio capture, or upload. The original MOV
   includes the whole camera view; keep local recordings out of Git and only
   attach deliberately selected, cropped evidence.

## Drive the device

For a natural app/Bluetooth session, leave the owner's Boop running and
trigger the ordinary flow. For deterministic USB injection, the Mac app
mustn't be connected: its `state` messages replace injected ones. Check
`tools/boopctl ping` before injecting: `ble` must not be `conn`, and `link`
must not be `ble`. Don't launch or quit the app yourself; ask the owner.
Keep the `ping` output (`fw`, `sha`) with the evidence for the firmware
identity. Never flash or reboot merely to enable webcam mode.

For USB, let the device clock run before recording (from the repo root):

```sh
tools/boopctl clock run
```

Then set a distinct starting state before starting the camera:

```sh
tools/boopctl send '{"t":"state","v":1,"base":"working","busy":1,"idle":0,"wait":0}'
```

After the camera says `RECORDING`, trigger a cheer:

```sh
tools/boopctl send '{"t":"moment","anim":"cheer","ttl":5}'
```

Do not use `clock freeze`, `clock step` or screenshot loops during video:
they freeze or perturb the animation being observed. Keep command responses
beside the recording, and check `tools/boopctl state` afterward for
unexpected writers. Host command times are not exact screen-onset times;
measure onset from the video. `tools/boopctl cam clip <name>` does all of
this for the L3 presets.

## Review

Crop around the screen using normalized **top-left** `x,y,width,height`:

```sh
tools/webcam/webcam.sh analyze --input /tmp/boop-camera-cheer/capture.mov \
  --out /tmp/boop-camera-cheer-review --roi 0.35,0.3,0.3,0.5 --start 1 --seconds 5
```

The ROI above is an example; choose it from the actual framing image.
The tool writes:

- `capture.mov` and `capture.json` when recording: original video and camera settings.
- `preview.png`: the first selected frame at full crop resolution for framing/focus checks.
- `sequence-000.png`, etc. when analyzing: every decoded frame in the selected
  interval, in left-to-right, top-to-bottom order, 30 per sheet, with timestamps.
  These are consecutive temporal evidence, not sparse animation keyframes.
- `frames.csv`: all decoded presentation timestamps and adjacent intervals.
- `report.json`: observed capture cadence, gaps over 1.5× the median interval,
  selected ROI/time interval, and an explicitly **unreviewed** verdict.

Watch the original at normal speed when a video player is available, and inspect
all sequence sheets covering the motion, including its end. An agent limited
to image tools can inspect these timestamped sequences but must state that it
has not watched real-time playback. Reanalyze a shorter interval for detailed
inspection. Compare before/after clips with the same camera, crop, lighting,
state trigger and frame rate. Record findings in a separate `review.md`: scenario,
firmware ID, usable capture rate/focus, observed motion and timestamps, deviations
from [plan/UX.md](../../plan/UX.md) and [plan/BEHAVIORS.md](../../plan/BEHAVIORS.md) §5,
and pass/fail/inconclusive with evidence links.

Start with the L3 presets: idle blinks, needs you, a cheer with a mumble
after it, and a tap wiggle. Check continuous motion, overshoot/settling, repeated or
abrupt jumps, and the return to rest. Review timings relative to visible onset,
allowing camera-frame quantization (about 33 ms at 30 fps).

Capture gaps invalidate a smoothness claim across those gaps. Even regular video
timestamps do not establish firmware FPS: duplicate camera frames, auto-exposure,
motion blur, display scan/PWM and rolling shutter can hide or mimic stutter.
Do not automatically fail firmware for camera banding or pass motion merely
because the recording is 30 fps. Mark unclear cases inconclusive and recapture.

## Tool checks

```sh
make webcam-test
```

The tests generate a real moving-square MOV with one intentionally missing frame,
then verify gap detection, consecutive-frame preservation, interval selection,
evidence overwrite protection and invalid arguments. They do not open a camera
and do not substitute for a live review of the board.
