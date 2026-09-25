"""Canvas screenshots as PNGs, and exact pixel diffs between them."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

W, H = 240, 320


def rgb888(c: int) -> tuple[int, int, int]:
    r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)


def to_image(palette: list[int], pixels: bytes) -> Image.Image:
    img = Image.frombytes("P", (W, H), pixels)
    flat: list[int] = []
    for c in palette:
        flat.extend(rgb888(c))
    img.putpalette(flat)
    return img.convert("RGB")


def save_shot(palette: list[int], pixels: bytes, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    to_image(palette, pixels).save(path)
    return path


def diff(a: Path, b: Path, out: Path | None = None) -> int:
    """Number of differing pixels. Writes a highlighted diff image if asked."""
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        raise ValueError(f"sizes differ: {ia.size} vs {ib.size}")
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
