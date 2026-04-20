"""BuddyState + pure reducer. Single source of truth at runtime.

Mirrors ``../../schema/state.ts``. The reducer is the only code that
mutates state. Everything else reads.

Contract (the invariants in ../README.md):

1. ``version`` is monotonic; ``reduce`` bumps by exactly 1 on change,
   returns the *same* state object otherwise.
2. Reducer is pure: no logging, no time lookup, no I/O. ``at`` is
   always passed in.
3. Prompt replacement is atomic: a heartbeat either keeps the current
   prompt (matching id), replaces it with a new id, or clears it to
   ``None``. Decisions live on ``prompt.decidedBy`` until upstream
   confirms the prompt gone (next heartbeat without it).
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, replace
from typing import Any, Literal

from .events import (
    BleConnected,
    BleDisconnected,
    ClientDecide,
    Event,
    Heartbeat,
    OwnerSet,
    StaleTick,
    TimeSync,
)

PetState = Literal["sleep", "idle", "busy", "attention", "celebrate", "dizzy", "heart"]
DesktopStatus = Literal["disconnected", "connected", "stale"]

STALE_MS = 30_000  # must match Config.stale_timeout_ms default


@dataclass(frozen=True, slots=True)
class DesktopLink:
    status: DesktopStatus = "disconnected"
    lastHeartbeatAt: int | None = None
    secure: bool = False


@dataclass(frozen=True, slots=True)
class SessionCounts:
    total: int = 0
    running: int = 0
    waiting: int = 0


@dataclass(frozen=True, slots=True)
class PendingDecision:
    clientId: str
    decision: Literal["once", "deny"]
    at: int


@dataclass(frozen=True, slots=True)
class Prompt:
    id: str
    tool: str
    hint: str
    arrivedAt: int
    source: str = "other"  # "cursor" | "claude-code" | "other"
    decidedBy: PendingDecision | None = None


@dataclass(frozen=True, slots=True)
class Pet:
    state: PetState = "sleep"
    oneShotUntil: int | None = None
    species: Literal["bufo"] = "bufo"


@dataclass(frozen=True, slots=True)
class BuddyState:
    version: int = 0
    updatedAt: int = 0
    desktop: DesktopLink = field(default_factory=DesktopLink)
    sessions: SessionCounts = field(default_factory=SessionCounts)
    msg: str = ""
    entries: tuple[str, ...] = ()
    tokens: int = 0
    tokensToday: int = 0
    prompt: Prompt | None = None
    pet: Pet = field(default_factory=Pet)
    owner: str = ""

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["entries"] = list(self.entries)
        return d


INITIAL_STATE = BuddyState()


# ---------------------------------------------------------------------------
# Reducer
# ---------------------------------------------------------------------------


def reduce(state: BuddyState, event: Event) -> BuddyState:
    """Pure state transition. Returns same object if nothing changed."""
    new = _reduce_inner(state, event)
    if new is state:
        return state
    return replace(
        new,
        version=state.version + 1,
        updatedAt=_event_at(event) or new.updatedAt,
    )


def _reduce_inner(state: BuddyState, event: Event) -> BuddyState:
    if isinstance(event, BleConnected):
        if state.desktop.status == "connected":
            return state
        return replace(
            state,
            desktop=DesktopLink(
                status="connected",
                lastHeartbeatAt=state.desktop.lastHeartbeatAt,
                secure=state.desktop.secure,
            ),
            pet=_derive_pet(state, state.prompt, state.sessions),
        )

    if isinstance(event, BleDisconnected):
        return replace(
            state,
            desktop=DesktopLink(
                status="disconnected",
                lastHeartbeatAt=state.desktop.lastHeartbeatAt,
                secure=False,
            ),
            pet=_derive_pet_disconnected(),
        )

    if isinstance(event, StaleTick):
        if state.desktop.lastHeartbeatAt is None:
            return state
        age = event.at - state.desktop.lastHeartbeatAt
        desired: DesktopStatus = (
            "stale" if age > STALE_MS else state.desktop.status
        )
        if desired == state.desktop.status:
            return state
        return replace(
            state,
            desktop=replace(state.desktop, status=desired),
            pet=_derive_pet_for(state.prompt, state.sessions, connected=False),
        )

    if isinstance(event, TimeSync):
        # Treat as a liveness signal but otherwise state-free for MVP.
        return replace(
            state,
            desktop=replace(
                state.desktop, status="connected", lastHeartbeatAt=event.at
            ),
        )

    if isinstance(event, OwnerSet):
        if state.owner == event.name:
            return state
        return replace(state, owner=event.name)

    if isinstance(event, Heartbeat):
        sessions = SessionCounts(
            total=event.total, running=event.running, waiting=event.waiting
        )
        prompt = _reconcile_prompt(state.prompt, event)
        return replace(
            state,
            desktop=replace(
                state.desktop,
                status="connected",
                lastHeartbeatAt=event.at,
            ),
            sessions=sessions,
            msg=event.msg,
            entries=tuple(event.entries),
            tokens=event.tokens,
            tokensToday=event.tokens_today,
            prompt=prompt,
            pet=_derive_pet_for(prompt, sessions, connected=True),
        )

    if isinstance(event, ClientDecide):
        # The bridge is responsible for validation (matching promptId,
        # race handling). The reducer records the outcome only.
        if state.prompt is None or state.prompt.id != event.prompt_id:
            return state
        if state.prompt.decidedBy is not None:
            return state
        new_prompt = replace(
            state.prompt,
            decidedBy=PendingDecision(
                clientId=event.client_id,
                decision=event.decision,
                at=event.at,
            ),
        )
        return replace(state, prompt=new_prompt)

    return state


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _reconcile_prompt(prev: Prompt | None, hb: Heartbeat) -> Prompt | None:
    if hb.prompt_id is None:
        return None
    if prev is not None and prev.id == hb.prompt_id:
        return prev
    return Prompt(
        id=hb.prompt_id,
        tool=hb.prompt_tool or "",
        hint=hb.prompt_hint or "",
        arrivedAt=hb.at,
        source=hb.prompt_source or "other",
        decidedBy=None,
    )


def _derive_pet(
    state: BuddyState, prompt: Prompt | None, sessions: SessionCounts
) -> Pet:
    return _derive_pet_for(
        prompt, sessions, connected=state.desktop.status == "connected"
    )


def _derive_pet_for(
    prompt: Prompt | None, sessions: SessionCounts, *, connected: bool
) -> Pet:
    # Mirrors derive() in src/main.cpp. Celebrate/dizzy/heart are
    # one-shots driven externally and are NOT chosen here (MVP omits
    # them; idle/sleep/busy/attention is enough to prove the loop).
    if not connected:
        return Pet(state="sleep")
    if prompt is not None and prompt.decidedBy is None:
        return Pet(state="attention")
    if sessions.running >= 3:
        return Pet(state="busy")
    return Pet(state="idle")


def _derive_pet_disconnected() -> Pet:
    return Pet(state="sleep")


def _event_at(event: Event) -> int | None:
    return getattr(event, "at", None)
