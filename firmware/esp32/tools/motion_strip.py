#!/usr/bin/env python3
"""Motion review strip: freeze the virtual clock at several offsets after a
moment starts and stitch the screenshots side by side, so an animation can
be judged from a still image (plan/UX-DEVICE.md §20).

    tools/motion_strip.py boop --out /tmp/boop.png
    tools/motion_strip.py done-dance --offsets 0,300,600,900,1200,1800,2400

Cells send a distinct state first so `stateAt` and the moment's own anchor
coincide, then freeze with `clock settle <offset>` before each capture.
Requires Pillow. One serial session per step, like the contact sheet.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from argparse import Namespace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import buddyctl  # noqa: E402

BASE = {"v": 2, "posture": "desk", "mute": 0, "cosmetic": {}, "snap": {"level": 1, "streak": 0}}
CELLS = {
    "boop": ({**BASE, "state": "idle", "overlay": "boop"}, [0, 100, 200, 350, 500, 700, 900, 1200]),
    "greet-3": ({**BASE, "state": "idle", "overlay": "greet", "greetLevel": 3}, [0, 300, 600, 900, 1200, 1600, 2100]),
    "greet-1": ({**BASE, "state": "idle", "overlay": "greet", "greetLevel": 1}, [0, 150, 300, 450, 600, 900]),
    "done-hop": ({**BASE, "state": "done", "cheer": "hop"}, [0, 100, 200, 350, 500, 800, 1200]),
    "done-cheer": ({**BASE, "state": "done", "cheer": "cheer"}, [0, 200, 400, 700, 1000, 1500, 2200]),
    "done-dance": ({**BASE, "state": "done", "cheer": "dance"}, [0, 250, 500, 900, 1300, 1800, 2400]),
    "needsYou": ({**BASE, "state": "needsYou"}, [0, 80, 160, 300, 600]),
    "working": ({**BASE, "state": "working", "effort": "light"}, [0, 800, 1500, 1700, 2000, 3100, 3300, 4800]),
    "working-grinding": ({**BASE, "state": "working", "effort": "grinding"}, [0, 400, 800, 1500, 2200, 3000]),
}


def send(port: str, lines: list[str], settle: float = 0.15) -> None:
    with buddyctl.SerialBuddy(port, 5.0) as s:
        for line in lines:
            s.write_line(line)
            time.sleep(settle)


def capture(port: str, out: Path) -> None:
    buddyctl.capture_screenshot(Namespace(port=port, timeout=60, out=str(out), scale=1, json=True, retry=1))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cell", choices=sorted(CELLS))
    ap.add_argument("--offsets", help="comma-separated ms offsets from the moment's start")
    ap.add_argument("--out", default=None)
    ap.add_argument("--port")
    args = ap.parse_args()
    port = args.port or buddyctl.find_port()
    frame, offsets = CELLS[args.cell]
    if args.offsets:
        offsets = [int(x) for x in args.offsets.split(",")]
    out = Path(args.out or f"/tmp/boop-motion/{args.cell}.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    # Distinct prior state so the moment's anchor is fresh, then the moment.
    send(port, ["clock clear", "imu set 0 0 0.98", json.dumps({**BASE, "state": "working"})], settle=0.4)
    send(port, [json.dumps(frame)], settle=0.2)
    frames = []
    for offset in offsets:
        send(port, [f"clock settle {offset}"])
        shot = out.parent / f"{args.cell}-{offset:04d}.png"
        capture(port, shot)
        frames.append((offset, shot))
    send(port, ["clock clear"])
    from PIL import Image, ImageDraw  # noqa: E402

    images = [Image.open(p).convert("RGB") for _, p in frames]
    w, h = images[0].size
    strip = Image.new("RGB", (w * len(images), h + 18), "black")
    draw = ImageDraw.Draw(strip)
    for i, ((offset, _), img) in enumerate(zip(frames, images)):
        strip.paste(img, (i * w, 18))
        draw.text((i * w + 4, 3), f"{args.cell} +{offset} ms", fill="white")
    strip.save(out)
    print(f"strip {out} ({len(images)} frames)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
