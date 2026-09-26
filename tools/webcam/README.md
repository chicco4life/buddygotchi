# The webcam recorder

A small AVFoundation recorder and frame extractor for looking at Boop's
physical screen. When and how to use the camera is the
[`webcam-verify` skill](../../skills/webcam-verify/SKILL.md): it's opt-in,
and the L3 checks ([plan/VERIFICATION.md](../../plan/VERIFICATION.md) L3,
§6) run through `tools/boopctl cam`. This page is the recorder itself.

It needs macOS 14+ and Command Line Tools, and no FFmpeg or Python
packages. `webcam.sh` compiles `Webcam.swift` into `.build/webcam` on first
use. Run it from the repository root.

## Camera permission

macOS gives camera access to the app that launched the process, not to the
script. On this Mac, recording works only from a terminal the Claude app
opens (its Terminal panel); from an agent's own shell the camera is
missing or denied. If macOS asks, allow it in System Settings → Privacy &
Security → Camera. Listing cameras never records.

## Commands

```sh
tools/webcam/webcam.sh list                      # cameras and their exact ids
tools/webcam/webcam.sh record --camera ID --seconds 3 --out /tmp/boop-camera-framing
tools/webcam/webcam.sh record --camera ID --seconds 10 --fps 30 --out /tmp/boop-camera-cheer
tools/webcam/webcam.sh analyze --input /tmp/boop-camera-cheer/capture.mov \
  --out /tmp/boop-camera-cheer-review --roi 0.35,0.3,0.3,0.5 --start 1 --seconds 5
```

`record` prints `RECORDING …` once frames arrive, then stops by itself
(1–60 s); trigger the moment after that line. Video only: no microphone,
no upload. The camera must support the requested rate; 60 fps is never
assumed. `boopctl cam` uses the MacBook's own camera unless given
`--camera ID` or `BOOP_CAMERA`.

`--roi` crops with normalized **top-left** `x,y,width,height`; pick it from
the framing clip's `preview.png`.

## What it writes

- `capture.mov` and `capture.json` (record): the original video, which
  shows the whole room, and the camera's settings. Keep it local and out
  of git.
- `preview.png` (analyze): the first selected frame at full crop
  resolution, for framing and focus.
- `sequence-000.png`, … (analyze): every decoded frame in the interval,
  30 per sheet, left to right and top to bottom, with timestamps. These
  are consecutive frames, not sparse keyframes.
- `frames.csv`: every presentation timestamp and the interval to the next.
- `report.json`: the observed capture cadence, gaps over 1.5× the median
  interval, the crop and interval, and an explicitly **unreviewed**
  verdict.

A gap in the capture voids any smoothness claim across it, and regular
timestamps don't prove the firmware's frame rate: duplicate camera frames,
auto-exposure, motion blur, the panel's scan and rolling shutter can hide
or mimic stutter.

## Tests

`make tools-test` generates a moving-square MOV with one frame missing and
checks gap detection, that consecutive frames are kept, interval selection,
evidence overwrite protection and bad arguments. It never opens a camera.
