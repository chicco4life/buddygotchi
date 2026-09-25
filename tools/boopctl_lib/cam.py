"""Webcam helpers for L3 (plan/VERIFICATION.md §5, §6). Opt-in only.

Clips are short, video only, and stay in /tmp. `frame` finds the screen by
recording it solid white and then with the backlight off; `pattern` checks the
bring-up pattern's colours and orientation through the camera.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

from boopctl_lib.device import Device, DeviceError

REPO = Path(__file__).resolve().parents[2]
WEBCAM = REPO / "tools" / "webcam" / "webcam.sh"
CAMERA = "6C707041-05AC-0010-000D-000000000001"  # MacBook Air Camera
WORK = Path("/tmp/boop-cam")
CROP = WORK / "crop.json"


def still(name: str, seconds: float = 3.0, at: float = 1.0, camera: str = CAMERA) -> Image.Image:
    """Records a short clip and returns one full-resolution frame from it.

    The camera takes about a second to start, so a 3 s request yields about
    2 s of video; `at` skips the first frames while exposure settles.
    """
    clip, frames = WORK / f"{name}-clip", WORK / f"{name}-frames"
    for d in (clip, frames):
        shutil.rmtree(d, ignore_errors=True)
    run = [str(WEBCAM), "record", "--camera", camera, "--seconds", str(int(seconds)), "--out", str(clip)]
    subprocess.run(run, check=True, capture_output=True, text=True, timeout=60)
    subprocess.run(
        [str(WEBCAM), "analyze", "--input", str(clip / "capture.mov"), "--out", str(frames),
         "--start", str(at), "--seconds", "0.1"],
        check=True, capture_output=True, text=True, timeout=60,
    )
    img = Image.open(frames / "preview.png").convert("RGB")
    shutil.rmtree(clip, ignore_errors=True)  # raw video never lingers
    return img


def find_screen(lit: Image.Image, dark: Image.Image) -> tuple[int, int, int, int] | None:
    """The box that got brighter when the backlight was on."""
    diff = ImageChops.subtract(lit.convert("L"), dark.convert("L")).reduce(4)
    # The lit screen also lights up the board around it, so the cut-off is
    # relative to the screen itself: the brightest 2% of the change. The
    # screen is solid white, so all of it changes by about that much.
    hist = diff.histogram()
    total, seen, top = sum(hist), 0, 255
    while top > 0 and seen + hist[top] < total * 0.02:
        seen += hist[top]
        top -= 1
    if top < 30:
        return None
    cut = top * 0.6
    small = diff.point(lambda v: 255 if v > cut else 0)
    w, h = small.size
    px = small.load()
    cols = [sum(1 for y in range(h) if px[x, y]) for x in range(w)]
    rows = [sum(1 for x in range(w) if px[x, y]) for y in range(h)]
    if max(cols, default=0) < 10:
        return None
    xs = [x for x, c in enumerate(cols) if c > max(cols) * 0.6]
    ys = [y for y, c in enumerate(rows) if c > max(rows) * 0.6]
    return xs[0] * 4, ys[0] * 4, (xs[-1] + 1) * 4, (ys[-1] + 1) * 4


def upright(img: Image.Image, box: tuple[int, int, int, int], usb: str) -> Image.Image:
    """Crops the screen and turns it so USB-C is at the bottom, 240×320."""
    crop = img.crop(box)
    turn = {"bottom": 0, "right": 90, "top": 180, "left": 270}[usb]  # clockwise degrees
    if turn:
        crop = crop.rotate(-turn, expand=True)
    return crop.resize((240, 320))


def frame(dev: Device, usb: str) -> dict:
    WORK.mkdir(parents=True, exist_ok=True)
    dev.request({"t": "dbg.pattern", "fill": 1})  # solid white
    dev.request({"t": "dbg.light", "bl": 255})
    lit = still("lit")
    dev.request({"t": "dbg.light", "bl": 0})
    try:
        dark = still("dark")
    finally:
        dev.request({"t": "dbg.light", "bl": 255})
        dev.request({"t": "dbg.pattern"})
    lit.save(WORK / "lit.png")
    dark.save(WORK / "dark.png")
    box = find_screen(lit, dark)
    if box is None:
        return {"ok": False, "reason": "no screen found; skip L3 for this run"}
    x0, y0, x1, y1 = box
    info = {"ok": True, "box": list(box), "usb": usb, "camera_size": list(lit.size), "at": time.time()}
    CROP.write_text(json.dumps(info))
    upright(lit, box, usb).save(WORK / "frame.png")
    info["crop_png"] = str(WORK / "frame.png")
    if (x1 - x0) * (y1 - y0) < 0.005 * lit.size[0] * lit.size[1]:
        info.update(ok=False, reason="screen box is implausibly small")
    return info


def load_crop() -> dict:
    if not CROP.exists():
        raise DeviceError("no framing yet; run `boopctl cam frame` first")
    return json.loads(CROP.read_text())


def mean(img: Image.Image, x: int, y: int, w: int, h: int) -> tuple[float, float, float]:
    """Average colour of the inner half of a rectangle, which absorbs framing error."""
    box = (x + w // 4, y + h // 4, x + w - w // 4, y + h - h // 4)
    r, g, b = ImageStat.Stat(img.crop(box)).mean[:3]
    return r, g, b


# The same rectangles as firmware/src/render/pattern.h.
BLOCKS = {
    "red": (8, 122, 108, 56), "green": (124, 122, 108, 56),
    "blue": (8, 182, 108, 56), "white": (124, 182, 108, 56),
    "black": (8, 242, 108, 56), "amber": (124, 242, 108, 56),
}
ARROW = (98, 70, 44, 14)  # top of the arrow's shaft, above the "UP" text
BELOW = (98, 299, 44, 10)  # the grey strip at the same x, near USB-C


def judge(colors: dict[str, tuple[float, float, float]]) -> list[str]:
    problems = []
    r, g, b = colors["red"]
    if not (r > 1.3 * g and r > 1.3 * b):
        problems.append(f"red block reads {colors['red']}: " + ("looks blue, so BGR order" if b > r else "not red"))
    r, g, b = colors["green"]
    if not (g > 1.2 * r and g > 1.2 * b):
        problems.append(f"green block reads {colors['green']}")
    r, g, b = colors["blue"]
    if not (b > 1.2 * r and b > g):
        problems.append(f"blue block reads {colors['blue']}: " + ("looks red, so BGR order" if r > b else "not blue"))
    white, black = sum(colors["white"]) / 3, sum(colors["black"]) / 3
    if white < black + 60:
        problems.append(f"white ({white:.0f}) isn't much brighter than black ({black:.0f}): inverted?")
    r, g, b = colors["amber"]
    if not (r > g > b and r > 1.5 * b):
        problems.append(f"amber block reads {colors['amber']}")
    if sum(colors["arrow"]) < sum(colors["below"]) + 60:
        problems.append("the UP arrow isn't at the end away from USB-C: rotation")
    return problems


def pattern(dev: Device) -> dict:
    crop = load_crop()
    dev.request({"t": "dbg.pattern"})
    dev.request({"t": "dbg.light", "bl": 255})
    img = upright(still("pattern"), tuple(crop["box"]), crop["usb"])
    img.save(WORK / "pattern.png")
    colors = {name: mean(img, *rect) for name, rect in BLOCKS.items()}
    colors["arrow"] = mean(img, *ARROW)
    colors["below"] = mean(img, *BELOW)
    problems = judge(colors)
    return {
        "ok": not problems,
        "problems": problems,
        "colors": {k: [round(v) for v in c] for k, c in colors.items()},
        "crop_png": str(WORK / "pattern.png"),
    }


# Live clips (plan/VERIFICATION.md §5 L3): the clock runs, so the camera sees
# real motion. Each is a list of (seconds after recording starts, message).
_WORKING = {"t": "state", "v": 1, "base": "working", "busy": 1, "idle": 0, "wait": 0}
_ATTN = {**_WORKING, "attn": {"agent": "codex", "project": "landing", "more": 0}, "wait": 1}
CLIPS = {
    "idle": [(0.0, {"t": "state", "v": 1, "base": "idle", "idle": 1})],
    "needs_you": [(0.0, _WORKING), (2.0, _ATTN), (5.0, _ATTN)],
    "cheer": [(0.0, _WORKING), (1.5, {"t": "moment", "anim": "cheer", "size": 3, "ttl": 5,
                                      "say": {"syl": "bi do ba na", "word": "done!", "at": 4, "ms": 120}}),
              (5.0, _WORKING)],
    # The ladder with a sped-up clock: jump to just before rung 2, then to
    # just before rung 3 (three amber pulses), then a tap hushes it.
    "ladder": [(0.0, _WORKING), (1.0, _ATTN),
               (3.0, {"t": "dbg.clock", "step": 42500}), (3.0, _ATTN), (3.0, {"t": "dbg.clock", "run": True}),
               (5.5, {"t": "dbg.clock", "step": 72500}), (5.5, _ATTN), (5.5, {"t": "dbg.clock", "run": True}),
               (8.0, {"t": "dbg.press", "ms": 100})],
    "cheers": [(0.0, _WORKING), (0.5, {"t": "moment", "anim": "cheer", "size": 1, "ttl": 5}),
               (3.0, {"t": "moment", "anim": "cheer", "size": 2, "ttl": 5}), (3.0, _WORKING),
               (5.8, {"t": "moment", "anim": "cheer", "size": 3, "ttl": 5})],
    "tap": [(0.0, {"t": "state", "v": 1, "base": "idle", "idle": 1}), (1.0, {"t": "dbg.press", "ms": 100}),
            (3.0, {"t": "dbg.touch", "x": 120, "y": 120, "ms": 100}), (5.0, {"t": "dbg.press", "ms": 100})],
}


def clip(dev: Device, name: str, seconds: int = 8, frames: int = 18) -> dict:
    """Records a bounded clip while the steps play, then saves a contact sheet
    of upright, cropped frames. The raw video is deleted straight away."""
    from PIL import ImageDraw

    if name not in CLIPS:
        raise DeviceError(f"no clip {name!r}; choose from {', '.join(CLIPS)}")
    seconds = min(seconds, 10)
    crop = load_crop()
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / f"clip-{name}"
    shutil.rmtree(out, ignore_errors=True)
    dev.request({"t": "dbg.clock", "run": True})
    dev.request({"t": "dbg.light", "bl": 255})
    dev.send({"t": "state", "v": 1, "base": "idle"})
    run = [str(WEBCAM), "record", "--camera", CAMERA, "--seconds", str(seconds), "--out", str(out)]
    rec = subprocess.Popen(run, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    time.sleep(1.0)  # the camera takes about a second to start
    start = time.monotonic()
    for at, message in CLIPS[name]:
        time.sleep(max(0.0, at - (time.monotonic() - start)))
        dev.send(message)
    if rec.wait(timeout=60) != 0:
        raise DeviceError(f"recording failed: {rec.stderr.read()[-400:]}")
    movie = out / "capture.mov"
    shots = []
    try:
        usable = seconds - 1.2
        for i in range(frames):
            t = round(0.1 + usable * i / frames, 2)
            fdir = out / f"f{i:02d}"
            subprocess.run([str(WEBCAM), "analyze", "--input", str(movie), "--out", str(fdir),
                            "--start", str(t), "--seconds", "0.1"], check=True, capture_output=True, timeout=60)
            img = Image.open(fdir / "preview.png").convert("RGB")
            shots.append((t, upright(img, tuple(crop["box"]), crop["usb"])))
            shutil.rmtree(fdir, ignore_errors=True)
    finally:
        movie.unlink(missing_ok=True)  # raw video never lingers
    cols = 6
    sheet = Image.new("RGB", (cols * 250, ((len(shots) + cols - 1) // cols) * 340), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for i, (t, img) in enumerate(shots):
        x, y = (i % cols) * 250, (i // cols) * 340
        sheet.paste(img, (x + 5, y + 16))
        draw.text((x + 6, y + 2), f"{t:.2f} s", fill=(255, 255, 255))
    path = WORK / f"clip-{name}.png"
    sheet.save(path)
    return {"ok": True, "clip": name, "frames": len(shots), "sheet": str(path)}
