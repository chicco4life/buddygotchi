"""Wires upstream (boundary [A]) <-> reducer <-> WS server (boundary [B]).

Responsibilities:

* Feed parsed upstream lines as events into the reducer.
* Ack desktop commands per MVP policy.
* Accept WS-originated decisions; validate them against current state
  and, if accepted, write the BLE permission line and record via reducer.
* Periodically tick staleness so the UI flips to "stale" when heartbeats
  stop arriving.
* Broadcast snapshot/patch to all subscribed WS clients on every state
  version bump.

All side effects live here. The reducer remains pure.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import replace
from typing import Awaitable, Callable

from . import protocol as proto
from .config import Config
from .events import (
    BleConnected,
    BleDisconnected,
    ClientDecide,
    Event,
    StaleTick,
)
from .errors import ErrorCode
from .state import INITIAL_STATE, BuddyState, reduce
from .upstream import Upstream

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public API used by ws_server / main
# ---------------------------------------------------------------------------


class Bridge:
    """Owns the authoritative BuddyState and the upstream link."""

    def __init__(self, *, config: Config, upstream: Upstream) -> None:
        self._config = config
        self._upstream = upstream
        self._state: BuddyState = INITIAL_STATE
        self._prev_state: BuddyState = INITIAL_STATE
        self._lock = asyncio.Lock()
        self._listeners: set[Callable[[BuddyState, BuddyState], Awaitable[None]]] = set()
        self._stale_task: asyncio.Task[None] | None = None
        self._client_last_decide: dict[str, int] = {}

    # --- lifecycle -----------------------------------------------------

    async def start(self) -> None:
        await self._upstream.start(
            on_line=self._on_upstream_line,
            on_connect=self._on_upstream_connect,
            on_disconnect=self._on_upstream_disconnect,
        )
        self._stale_task = asyncio.create_task(self._stale_loop(), name="stale-tick")

    async def stop(self) -> None:
        if self._stale_task is not None:
            self._stale_task.cancel()
            try:
                await self._stale_task
            except asyncio.CancelledError:
                pass
        await self._upstream.stop()

    # --- state access --------------------------------------------------

    def state(self) -> BuddyState:
        return self._state

    def subscribe(
        self, cb: Callable[[BuddyState, BuddyState], Awaitable[None]]
    ) -> Callable[[], None]:
        self._listeners.add(cb)

        def unsub() -> None:
            self._listeners.discard(cb)

        return unsub

    # --- inbound from WS ----------------------------------------------

    async def handle_decide(
        self,
        *,
        client_id: str,
        prompt_id: str,
        decision: str,
    ) -> tuple[bool, ErrorCode | None]:
        """Validate + forward a web-client decision.

        Returns (ok, error_code). When ok, the decision has been written
        to upstream and recorded in state.
        """
        if decision not in ("once", "deny"):
            return False, "E_BAD_MESSAGE"

        now = _now_ms()

        # Rate limit per client.
        last = self._client_last_decide.get(client_id, 0)
        if now - last < self._config.decide_min_interval_ms:
            return False, "E_RATE_LIMIT"

        async with self._lock:
            cur = self._state
            if cur.prompt is None:
                return False, "E_NO_ACTIVE_PROMPT"
            if cur.prompt.id != prompt_id:
                return False, "E_PROMPT_ID_MISMATCH"
            if cur.prompt.decidedBy is not None:
                return False, "E_ALREADY_DECIDED"
            if cur.desktop.status != "connected":
                return False, "E_DESKTOP_DISCONNECTED"

            try:
                await self._upstream.send(
                    proto.serialize_permission(prompt_id, decision)
                )
            except Exception as e:  # noqa: BLE001
                log.exception("BLE write failed")
                return False, "E_BLE_WRITE_FAILED"

            self._client_last_decide[client_id] = now
            await self._apply_event(
                ClientDecide(
                    at=now,
                    client_id=client_id,
                    prompt_id=prompt_id,
                    decision=decision,  # type: ignore[arg-type]
                )
            )
            return True, None

    # --- inbound from upstream ----------------------------------------

    async def _on_upstream_connect(self) -> None:
        await self._apply_event(BleConnected(at=_now_ms()))

    async def _on_upstream_disconnect(self) -> None:
        await self._apply_event(BleDisconnected(at=_now_ms()))

    async def _on_upstream_line(self, line: str) -> None:
        result = proto.parse_line(line, now_ms=_now_ms())

        if isinstance(result, proto.UnknownLine):
            log.debug("unknown upstream line: %s (%s)", result.reason, result.raw[:80])
            return

        if isinstance(result, proto.CommandInbound):
            await self._handle_command(result)
            return

        if isinstance(result, proto.FolderPushInbound):
            # MVP intentionally does NOT ack char_begin so desktop times
            # out. Other folder-push messages are silently ignored.
            return

        if isinstance(result, proto.TurnEventInbound):
            # Per project decision, turn events are dropped for MVP.
            return

        # Heartbeat, TimeSync, OwnerSet are reducer events directly.
        await self._apply_event(result)

    async def _handle_command(self, cmd: proto.CommandInbound) -> None:
        if cmd.cmd == "status":
            data = {
                "name": "Claude-MVP01",
                "sec": self._state.desktop.secure,
            }
            await self._upstream.send(
                proto.serialize_ack("status", ok=True, data=data)
            )
            return
        if cmd.cmd in ("name", "owner", "unpair"):
            # owner-as-unsolicited is handled via parse_line's OwnerSet
            # branch; this arm only covers the ackable variant.
            if cmd.cmd == "owner":
                name = cmd.payload.get("name")
                if isinstance(name, str):
                    from .events import OwnerSet

                    await self._apply_event(OwnerSet(at=_now_ms(), name=name))
            await self._upstream.send(proto.serialize_ack(cmd.cmd, ok=True))
            return
        await self._upstream.send(
            proto.serialize_ack(cmd.cmd, ok=False, error="unsupported")
        )

    # --- reducer plumbing ---------------------------------------------

    async def _apply_event(self, event: Event) -> None:
        async with self._lock if not self._lock.locked() else _null_cm():
            prev = self._state
            new = reduce(prev, event)
            if new is prev:
                return
            self._prev_state = prev
            self._state = new
        await self._notify(prev, new)

    async def _notify(self, prev: BuddyState, new: BuddyState) -> None:
        if not self._listeners:
            return
        coros = [cb(prev, new) for cb in list(self._listeners)]
        await asyncio.gather(*coros, return_exceptions=True)

    # --- periodic staleness detection ---------------------------------

    async def _stale_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(2.0)
                await self._apply_event(StaleTick(at=_now_ms()))
        except asyncio.CancelledError:
            raise


def _now_ms() -> int:
    return int(time.time() * 1000)


# Tiny no-op async context manager used when we're already inside the
# bridge lock (re-entry from command handlers).
class _null_cm:
    async def __aenter__(self) -> None:
        return None

    async def __aexit__(self, *exc: object) -> None:
        return None
