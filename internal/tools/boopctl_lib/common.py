"""What boopctl's commands and the dashboard share: the repo, the
animations and moods, the board's voice takes, a line to the app's hook
socket, and noticing a board reset."""
from __future__ import annotations

import json
import socket
import struct
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any

from boopctl_lib.device import DeviceError
from facegen.facegen import MOODS  # noqa: F401  Boop's moods, as `state` carries them, in the device's order

REPO = Path(__file__).resolve().parents[3]

# The animations a `moment` plays (BEHAVIORS.md §5, PROTOCOL.md §3): the
# brain's finish, the rules' one-shots and a tap's, each its design's state.
ANIMS = ["task_complete", "reply_ready", "starting", "stopped", "error", "helper_return", "poked", "tap_spam"]
# The older names the device still reads, as the animation it plays.
OLD_ANIMS = {"cheer": "task_complete", "wiggle": "poked"}
# The one-shots the rules send, never the brain (PROTOCOL.md §3 `moment`).
RULE_ONE_SHOTS = {"starting", "stopped", "error", "helper_return"}
# The moments that play a turn's finish (PROTOCOL.md §3 `moment`): the
# brain's task_complete and reply_ready, and their older names in older
# logs (the cheer).
FINISHES = {"task_complete", "reply_ready"}
FINISHES |= {old for old, anim in OLD_ANIMS.items() if anim in FINISHES}
# The facts that pick an animation's variations (PROTOCOL.md §3).
OUTCOMES = ["success", "failure"]
CTXS = ["new_task", "session", "continuation"]


PACK = REPO / ".build" / "voice" / "voice.bin"


@dataclass(frozen=True)
class Take:
    """One of the board's recorded takes: its id (a `say`'s `take`), the
    bubble's text, and how long it plays, in ms rounded down (PROTOCOL.md §3,
    DEVICE.md §4)."""
    id: str
    text: str
    ms: int


@cache
def takes() -> tuple[Take, ...]:
    """The takes in the voice pack the board plays from its card
    (.build/voice/voice.bin, which voicegen writes; VOICE.md §8), by id."""
    if not PACK.exists():
        raise DeviceError(f"no voice pack at {PACK}: run make -C internal voice")
    data = PACK.read_bytes()
    magic, _, count, size, index, rate, _ = struct.unpack_from("<8s16sIIIII", data)
    if magic != b"BOOPVOX1":
        raise DeviceError(f"{PACK} isn't a voice pack")
    out = []
    for i in range(count):
        rec = data[index + i * size:index + (i + 1) * size]
        key, text = (rec[a:b].split(b"\0")[0].decode() for a, b in ((0, 72), (72, 108)))
        out.append(Take(key, text, struct.unpack_from("<I", rec, 112)[0] * 1000 // rate))
    return tuple(out)


def take(key: str) -> Take | None:
    """A take by its id."""
    return next((t for t in takes() if t.id == key), None)


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
