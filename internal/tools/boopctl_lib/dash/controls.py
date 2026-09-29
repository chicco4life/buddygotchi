"""What the dashboard's keys send: `{"dev":…}` lines
for the app's hook socket (common.send_line), built from the `questions`
line, and Preview's own lines for its sim. The socket never replies, so a
command counts as landed when its entry shows up in debug.jsonl."""
from __future__ import annotations

import time
from typing import Any, Callable

from boopctl_lib.common import takes
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
    return lambda o: (kind(o) == "event" and o["event"].get("type") == "action"
                      and o["event"].get("data", {}).get("by") == "dashboard" and o["event"].get("specific_type") == "mood")


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
    state: dict[str, Any] = dict(latest or {"t": "state", "busy": 0, "vol": 6})
    state.pop("attn", None)
    if mood:
        state["mood"] = mood
    if look == "needs you":
        state.update(base="idle", attn={"agent": "claude", "project": "preview", "more": 0})
    else:
        state["base"] = look
    return state


def preview_reaction(face: str, take: str | None, loops: int = 1, anim: str | None = None) -> Line:
    """A reaction as the react action sends it: the face as the moment's
    `mood`, held `loops` times, `anim` if one was picked, and the take
    with id `take`, or `{}` for one that says nothing (PROTOCOL.md §3)."""
    line: Line = {"t": "moment", "mood": face, "loops": loops, "say": {"take": take} if take else {}}
    if anim:
        line["anim"] = anim
    return line
