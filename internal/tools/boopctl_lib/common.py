"""What boopctl's commands and the dashboard share: the repo, the
animations and moods, the Mac's Voice lines, a line to the app's hook
socket, and noticing a board reset."""
from __future__ import annotations

import json
import socket
import subprocess
from pathlib import Path
from typing import Any

from boopctl_lib.device import DeviceError

REPO = Path(__file__).resolve().parents[3]

# The animation set (BEHAVIORS.md §5).
ANIMS = ["cheer", "wiggle"]
# Boop's moods, as `state` carries them, in the device's order (PROTOCOL.md §3,
# harness/DECISIONS.md §2.3).
MOODS = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad",
         "calm", "engaged", "annoyed", "irritated", "whiny", "wounded"]


def boopdev_voice(feeling: str, word: str | None, count: int, seed: int | None = None) -> list[dict]:
    """Lines as the Mac's Voice builds them, through `boopdev voice --json`."""
    boopdev = REPO / ".build" / "debug" / "boopdev"
    if not boopdev.exists():
        raise DeviceError(f"{boopdev} is missing; run `make build` first")
    cmd = [str(boopdev), "voice", feeling] + ([word] if word else []) + ["--count", str(count), "--json"]
    if seed is not None:
        cmd += ["--seed", str(seed)]
    run = subprocess.run(cmd, capture_output=True, text=True)
    if run.returncode:  # a word outside the vocabulary: boopdev lists the ones it knows
        raise DeviceError(f"`boopdev voice {feeling}{' ' + word if word else ''}` failed. "
                          + (run.stderr.strip() or f"exit {run.returncode}"))
    return [json.loads(row) for row in run.stdout.splitlines() if row.startswith("{")]


def syllables(say: dict[str, Any]) -> int:
    """A mumble's syllables: `syl` separates words by spaces and their
    syllables by `-` (PROTOCOL.md §3)."""
    return len(say.get("syl", "").replace("-", " ").split())


def send_line(path: str, line: dict[str, Any]) -> str | None:
    """Writes one JSON line to the app's hook socket, which never replies;
    returns the problem, if it can't."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            s.connect(path)
            s.sendall(json.dumps(line, separators=(",", ":")).encode() + b"\n")
    except OSError as exc:
        return f"can't reach Boop's socket {path}: {exc.strerror or exc}"
    return None


def restarted(ups: list[int]) -> bool:
    """Whether the board reset between samples of its uptime: one didn't rise."""
    return any(b <= a for a, b in zip(ups, ups[1:]))
