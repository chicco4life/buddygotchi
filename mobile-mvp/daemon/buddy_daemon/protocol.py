"""Pure parser/serializer for boundary [A], BLE Nordic UART lines.

No I/O in this module. It accepts raw bytes or strings, validates
against the schema in ``../../schema/ble-upstream.ts``, and returns
typed events (or an ``UnknownLine`` sentinel). The ``bridge`` module
is responsible for translating successful parses into reducer events.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Any, Final, Union

from .events import Heartbeat, OwnerSet, TimeSync

# ---------------------------------------------------------------------------
# Parse results
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class CommandInbound:
    """Desktop -> device command that requires an ack from the daemon."""

    cmd: str
    payload: dict[str, Any]


@dataclass(slots=True)
class TurnEventInbound:
    """Accepted and dropped per project decision (no UI exposure)."""

    role: str


@dataclass(slots=True)
class FolderPushInbound:
    """We do not support folder push in MVP; parsed for completeness only."""

    cmd: str
    payload: dict[str, Any]


@dataclass(slots=True)
class UnknownLine:
    reason: str
    raw: str


ParseResult = Union[
    Heartbeat,
    TimeSync,
    OwnerSet,
    CommandInbound,
    TurnEventInbound,
    FolderPushInbound,
    UnknownLine,
]


FOLDER_PUSH_CMDS: Final[frozenset[str]] = frozenset(
    {"char_begin", "file", "chunk", "file_end", "char_end"}
)
ACKABLE_CMDS: Final[frozenset[str]] = frozenset({"status", "name", "owner", "unpair"})


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def parse_line(line: str, *, now_ms: int | None = None) -> ParseResult:
    """Parse a single \\n-stripped NUS line into a typed event/command.

    Never raises; returns ``UnknownLine`` for any malformed or unsupported
    input. ``now_ms`` lets tests inject deterministic timestamps.
    """
    if now_ms is None:
        now_ms = _now_ms()

    line = line.strip()
    if not line:
        return UnknownLine("empty", line)

    try:
        obj = json.loads(line)
    except json.JSONDecodeError as e:
        return UnknownLine(f"invalid_json: {e.msg}", line)

    if not isinstance(obj, dict):
        return UnknownLine("not_an_object", line)

    # --- unsolicited shapes ---

    if "time" in obj:
        t = obj.get("time")
        if isinstance(t, list) and len(t) == 2 and all(isinstance(x, int) for x in t):
            return TimeSync(at=now_ms, epoch_s=int(t[0]), tz_offset_s=int(t[1]))
        return UnknownLine("malformed_time", line)

    if obj.get("evt") == "turn":
        role = obj.get("role")
        if isinstance(role, str):
            return TurnEventInbound(role=role)
        return UnknownLine("malformed_turn", line)

    # Heartbeat has no top-level "cmd" and does have the counters.
    if "cmd" not in obj and _looks_like_heartbeat(obj):
        hb = _parse_heartbeat(obj, now_ms=now_ms)
        if hb is not None:
            return hb
        return UnknownLine("malformed_heartbeat", line)

    # --- cmd-bearing shapes ---

    cmd = obj.get("cmd")
    if not isinstance(cmd, str):
        return UnknownLine("no_cmd", line)

    if cmd == "owner":
        name = obj.get("name")
        if isinstance(name, str):
            return OwnerSet(at=now_ms, name=name)
        return UnknownLine("malformed_owner", line)

    if cmd in ACKABLE_CMDS or cmd in FOLDER_PUSH_CMDS:
        if cmd in FOLDER_PUSH_CMDS:
            return FolderPushInbound(cmd=cmd, payload=obj)
        return CommandInbound(cmd=cmd, payload=obj)

    return UnknownLine(f"unsupported_cmd:{cmd}", line)


def _looks_like_heartbeat(obj: dict[str, Any]) -> bool:
    return (
        "total" in obj
        and "running" in obj
        and "waiting" in obj
        and isinstance(obj.get("total"), int)
        and isinstance(obj.get("running"), int)
        and isinstance(obj.get("waiting"), int)
    )


def _parse_heartbeat(obj: dict[str, Any], *, now_ms: int) -> Heartbeat | None:
    entries = obj.get("entries", [])
    if not isinstance(entries, list):
        return None
    entries_s = [str(x) for x in entries[:8]]

    msg = obj.get("msg", "")
    if not isinstance(msg, str):
        return None

    prompt = obj.get("prompt")
    pid = ptool = phint = psrc = None
    if isinstance(prompt, dict):
        pid_raw = prompt.get("id")
        if not isinstance(pid_raw, str) or not pid_raw:
            return None
        pid = pid_raw
        ptool = str(prompt.get("tool", ""))
        phint = str(prompt.get("hint", ""))
        src_raw = prompt.get("source")
        psrc = str(src_raw) if isinstance(src_raw, str) and src_raw else None

    return Heartbeat(
        at=now_ms,
        total=int(obj["total"]),
        running=int(obj["running"]),
        waiting=int(obj["waiting"]),
        msg=msg,
        entries=entries_s,
        tokens=int(obj.get("tokens", 0) or 0),
        tokens_today=int(obj.get("tokens_today", 0) or 0),
        prompt_id=pid,
        prompt_tool=ptool,
        prompt_hint=phint,
        prompt_source=psrc,
    )


# ---------------------------------------------------------------------------
# Serialization (device -> desktop)
# ---------------------------------------------------------------------------


def serialize_permission(prompt_id: str, decision: str) -> bytes:
    if decision not in ("once", "deny"):
        raise ValueError(f"invalid decision: {decision}")
    payload = {"cmd": "permission", "id": prompt_id, "decision": decision}
    return (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")


def serialize_ack(
    cmd: str, *, ok: bool, data: dict[str, Any] | None = None, error: str | None = None
) -> bytes:
    obj: dict[str, Any] = {"ack": cmd, "ok": ok}
    if data is not None:
        obj["data"] = data
    if error is not None:
        obj["error"] = error
    return (json.dumps(obj, separators=(",", ":")) + "\n").encode("utf-8")


# ---------------------------------------------------------------------------
# Line buffer
# ---------------------------------------------------------------------------


class LineBuffer:
    """Accumulates bytes, yields complete \\n-terminated lines.

    NUS notifications fragment at MTU boundaries; the device accumulates
    until it sees \\n. Same story on our side.
    """

    __slots__ = ("_buf",)

    def __init__(self) -> None:
        self._buf = bytearray()

    def feed(self, chunk: bytes) -> list[str]:
        self._buf.extend(chunk)
        lines: list[str] = []
        while True:
            nl = self._buf.find(b"\n")
            if nl < 0:
                break
            raw = bytes(self._buf[:nl])
            del self._buf[: nl + 1]
            try:
                lines.append(raw.decode("utf-8"))
            except UnicodeDecodeError:
                continue
        return lines


def _now_ms() -> int:
    return int(time.time() * 1000)
