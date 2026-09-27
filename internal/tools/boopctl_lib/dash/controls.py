"""What the dashboard's keys send (plan/DASHBOARD.md §4): `{"dev":…}` lines
for the app's hook socket (common.send_line), built from the `questions`
line, and Preview's own lines for its sim. The socket never replies, so a
command counts as landed when its entry shows up in debug.jsonl."""
from __future__ import annotations

import random
import time
from typing import Any, Callable

from boopctl_lib.common import boopdev_voice
from boopctl_lib.dash.feed import Line, kind

CONFIRM_S = 2.0
# Preview's looks: the device's bases, and something needing you.
LOOKS = ["idle", "working", "asleep", "needs you"]


def options(question: Line) -> list[str]:
    return [o["name"] for o in question["options"]]


def asked_by(questions: list[Line], action: str) -> list[Line]:
    """An action's questions, in the order it asks them."""
    return [q for q in questions if q["action"] == action]


def confirms(line: Line) -> Callable[[Line], bool]:
    """Which debug.jsonl line shows that a dev line landed."""
    if line["dev"] == "answer":
        return lambda o: kind(o) == "pass" and o["pass"].get("by") == "dashboard"
    if line["dev"] == "mood":
        return lambda o: kind(o) == "action" and o["action"].get("by") == "dashboard" and o["action"]["name"] == "mood"
    return lambda o: kind(o) == "sent" and o["sent"].get("anim") == line["anim"] and "say" not in o["sent"]


class Pending:
    """Dev lines sent and not yet seen landing."""

    def __init__(self) -> None:
        self.waiting: list[tuple[float, str, Callable[[Line], bool]]] = []

    def add(self, line: Line, now: float | None = None) -> None:
        self.waiting.append(((time.monotonic() if now is None else now) + CONFIRM_S, line["dev"], confirms(line)))

    def seen(self, line: Line) -> str | None:
        """The command this line confirms, if any."""
        for item in self.waiting:
            if item[2](line):
                self.waiting.remove(item)
                return item[1]
        return None

    def late(self, now: float | None = None) -> list[str]:
        """Commands with nothing in debug.jsonl after CONFIRM_S."""
        now = time.monotonic() if now is None else now
        out = [name for due, name, _ in self.waiting if due <= now]
        self.waiting = [item for item in self.waiting if item[0] > now]
        return out


# Preview: lines for the dashboard's own sim only, never the app or the board.

def preview_state(latest: Line | None, look: str, mood: str | None = None) -> Line:
    """The latest state the app sent, showing `look`, and `mood` if given,
    instead."""
    state: dict[str, Any] = dict(latest or {"t": "state", "v": 1, "busy": 0, "idle": 0, "wait": 0,
                                              "vol": 6})
    state.pop("attn", None)
    if mood:
        state["mood"] = mood
    if look == "needs you":
        state.update(base="idle", wait=max(1, state.get("wait", 0)),
                     attn={"agent": "claude", "project": "preview", "more": 0})
    else:
        state.update(base=look, wait=0)
    return state


def preview_mumble(face: str, word: str | None) -> Line:
    """A reaction as the react action sends it: the line the app's Voice
    builds for that mood's face, from `boopdev voice MOOD --json`, and the
    face as the moment's `mood` (PROTOCOL.md §3)."""
    return {"t": "moment", "say": boopdev_voice(face, word, 1, random.randint(1, 1 << 30))[0], "mood": face}
