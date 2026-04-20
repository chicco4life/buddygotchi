"""Internal events fed into the reducer.

Events come from three sources:

* the upstream (BLE or fake TCP) layer, after line parsing
* the WS server, when a web client sends a decide
* the bridge's own staleness ticker

Events are plain dataclasses. The reducer is the only thing allowed to
turn an event into a new ``BuddyState``.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, Union


# ---------------------------------------------------------------------------
# BLE / upstream-sourced events
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class BleConnected:
    at: int


@dataclass(slots=True)
class BleDisconnected:
    at: int


@dataclass(slots=True)
class Heartbeat:
    at: int
    total: int
    running: int
    waiting: int
    msg: str
    entries: list[str]
    tokens: int
    tokens_today: int
    # Present only when the desktop reports a pending permission prompt.
    prompt_id: str | None = None
    prompt_tool: str | None = None
    prompt_hint: str | None = None
    prompt_source: str | None = None


@dataclass(slots=True)
class TimeSync:
    at: int
    epoch_s: int
    tz_offset_s: int


@dataclass(slots=True)
class OwnerSet:
    at: int
    name: str


@dataclass(slots=True)
class StaleTick:
    at: int


# ---------------------------------------------------------------------------
# Web-client-sourced events
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class ClientDecide:
    at: int
    client_id: str
    prompt_id: str
    decision: Literal["once", "deny"]


Event = Union[
    BleConnected,
    BleDisconnected,
    Heartbeat,
    TimeSync,
    OwnerSet,
    StaleTick,
    ClientDecide,
]
