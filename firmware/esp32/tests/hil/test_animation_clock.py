"""Host-only source guard: presentation code must use the virtual clock."""
from pathlib import Path
import re


def test_animation_clock():
    root = Path(__file__).resolve().parents[2] / "firmware"
    for name in ("face.h", "presence.h"):
        assert not re.search(r"\b(?:millis|random)\s*\(", (root / name).read_text())
    source = (root / "main.cpp").read_text()
    for name in ("ritualTick", "colorAmount", "cosmeticAmount", "ritualName", "render", "onFrame", "beginRetire"):
        start = source.index(name + "(")
        body = source.index("{", start)
        depth, end = 1, body + 1
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        assert not re.search(r"\b(?:millis|random)\s*\(", source[body:end]), name
