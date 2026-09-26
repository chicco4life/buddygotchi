"""Canvas screenshots as PNGs, and exact pixel diffs between them."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

# A screenshot as Link.shot() returns it: 256 RGB565 palette entries, one
# index per pixel, and the (width, height) the device reported.
Shot = tuple[list[int], bytes, tuple[int, int]]


def rgb888(c: int) -> tuple[int, int, int]:
    r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)


def to_image(shot: Shot) -> Image.Image:
    palette, pixels, size = shot
    img = Image.frombytes("P", size, pixels)
    flat: list[int] = []
    for c in palette:
        flat.extend(rgb888(c))
    img.putpalette(flat)
    return img.convert("RGB")


def save_shot(shot: Shot, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    to_image(shot).save(path)
    return path


def diff(a: Path, b: Path, out: Path | None = None) -> int:
    """Number of differing pixels. If any differ and `out` is given, writes a
    diff image there: a in grey with the changed pixels in magenta. Pictures
    of different sizes (a portrait golden against a landscape shot) differ
    everywhere: every pixel of the larger one counts, and the diff image
    shows the two side by side on magenta."""
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        if out is not None:
            gap = 8
            sheet = Image.new("RGB", (ia.width + gap + ib.width, max(ia.height, ib.height)), (255, 0, 255))
            sheet.paste(ia, (0, 0))
            sheet.paste(ib, (ia.width + gap, 0))
            out.parent.mkdir(parents=True, exist_ok=True)
            sheet.save(out)
        return max(ia.size[0] * ia.size[1], ib.size[0] * ib.size[1])
    pa, pb = ia.tobytes(), ib.tobytes()
    changed = [i // 3 for i in range(0, len(pa), 3) if pa[i : i + 3] != pb[i : i + 3]]
    if out is not None and changed:
        hl = ia.convert("L").convert("RGB")
        px = hl.load()
        w = ia.size[0]
        for i in changed:
            px[i % w, i // w] = (255, 0, 255)
        out.parent.mkdir(parents=True, exist_ok=True)
        hl.save(out)
    return len(changed)
