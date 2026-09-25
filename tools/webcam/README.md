# Webcam verification

> For v1, drive the device with `tools/boopctl` and follow `plan/VERIFICATION.md`
> (L3). The `buddyctl` commands below belong to the gen-2 firmware.

Record the physical Buddy screen with a Mac camera and review consecutive
frames over time. Requires macOS 14+, Command Line Tools, and camera permission;
no FFmpeg or third-party Python packages. Run commands from the repository root.
The wrapper compiles a small native AVFoundation executable into `.build/webcam`.

## Opt-in use

Use `$webcam-verify` or explicitly ask for webcam verification, then confirm
Buddy is positioned for that session. This mode is never automatically enabled
by animation edits or ordinary verification requests. Setup confirmation covers
the requested clips in the current session, not future sessions or background
monitoring. Normal tests do not require a camera. The reusable skill is
[`skills/webcam-verify/SKILL.md`](../../skills/webcam-verify/SKILL.md).

## Setup and recording

1. Place Buddy steadily in front of the laptop camera, screen facing the lens.
   Keep the whole display visible and large enough to judge the eyes. Use even
   lighting; move it farther away if the fixed-focus camera makes it blurry.
2. List cameras, then explicitly choose the laptop camera ID:

   ```sh
   make webcam ARGS='list'
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
     --out /tmp/boop-camera-dance
   ```

   Wait for `RECORDING …` before triggering the moment in a second terminal or
   a separate agent tool call. Recording stops automatically (1–60 seconds).
   The camera must support the requested rate; 60 fps is optional, never assumed.
   Video only: no microphone input, audio capture, or upload. The original MOV
   includes the whole camera view; keep local recordings out of Git and only
   attach deliberately selected, cropped evidence.

## Drive the device

For a natural app/BLE session, leave Boop running and trigger the ordinary flow.
For deterministic USB injection, quit Boop first: concurrent BLE keepalives
replace injected frames. Check `buddyctl state --json` before injecting. `connected` means a recent
valid data frame, including USB; it is not a BLE-only flag. Conservatively pause
if already true and establish that Boop is quit before proceeding. It will
normally become true after your own USB frame. Record `buddyctl ping --json` with the evidence for board
and firmware identity. Never flash or reboot merely to enable webcam mode.

For USB, resume the presentation clock before recording (from the repo root):

```sh
python3 - <<'PY'
import sys
sys.path.insert(0, 'firmware/esp32/tools')
from buddyctl import SerialBuddy
with SerialBuddy() as buddy:
    if buddy.framed_json('state', 'STATE').get('connected'):
        raise SystemExit('Recent data activity; verify Boop is quit and let activity expire before retrying')
    buddy.write_line('clock clear')
PY
```

Then set a distinct initial state before starting the camera:

```sh
python3 firmware/esp32/tools/buddyctl.py frame --json '{"v":2,"state":"working","effort":"light","posture":"desk"}'
```

After the camera says `RECORDING`, trigger the dance:

```sh
python3 firmware/esp32/tools/buddyctl.py frame --json '{"v":2,"state":"done","cheer":"dance","posture":"desk"}'
```

Do not use `--t`, `clock freeze`, `clock settle`, screenshot loops, or
`motion_strip.py` during video: those freeze or perturb the animation being
observed. Keep command responses beside the recording, and inspect device
state afterward for unexpected writers. Host command times are not exact
screen-onset times; measure onset from the video.

## Review

Crop around the screen using normalized **top-left** `x,y,width,height`:

```sh
tools/webcam/webcam.sh analyze --input /tmp/boop-camera-dance/capture.mov \
  --out /tmp/boop-camera-dance-review --roi 0.35,0.3,0.3,0.5 --start 1 --seconds 5
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
from `plan/UX-DEVICE.md` §20, and pass/fail/inconclusive with evidence links.

Start with idle/blink, working gaze, boop, hop, cheer, dance, and card arrival /
dismissal. Check continuous motion, overshoot/settling, repeated or abrupt jumps,
particle count, and the return to rest. For example, dance ends at 2.5 seconds;
boop produces one heart and returns from its eye squish. Review timings relative
to visible onset, allowing camera-frame quantization (about 33 ms at 30 fps).

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
and do not substitute for a live Buddy animation review.
