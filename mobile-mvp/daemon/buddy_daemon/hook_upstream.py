"""Hook-driven upstream.

Replaces the BLE/Claude-desktop peer with a local HTTP endpoint that
Cursor/Claude-Code hook scripts call. Each hook invocation becomes a
synthetic "permission_request" heartbeat pushed into the reducer; the
phone decides via the existing WS path; the decision is returned to
the hook script as an HTTP response.

This upstream mimics the Claude-desktop wire contract (``on_connect``,
``on_line``, ``send``) so the bridge and reducer do not change.

Design notes
------------

* We emit a periodic "idle" heartbeat (no prompt, 0 sessions) so the
  dashboard shows "connected" and the pet animates.
* When a hook arrives, we emit a single heartbeat carrying the prompt
  fields. The reducer creates ``state.prompt``; the WS broadcasts it;
  the phone renders the approval card.
* The bridge's ``handle_decide`` eventually calls ``self._upstream.send``
  with a serialized permission line. We parse that line and complete
  the pending future for the corresponding ``prompt_id``.
* After the decision, we emit another heartbeat *without* a prompt so
  the reducer clears it and the UI relaxes.
* Fail-open on timeouts: if nobody decides within ``timeout_s`` we
  return ``ask`` so the hook script can fall back to the host's native
  permission UI. Never block tool execution indefinitely.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
import uuid
from dataclasses import dataclass
from typing import Awaitable, Callable, Literal

log = logging.getLogger(__name__)


Decision = Literal["allow", "deny", "ask"]


@dataclass(slots=True)
class _Pending:
    prompt_id: str
    future: asyncio.Future[Decision]
    tool: str
    hint: str
    source: str


class HookUpstream:
    """Upstream implementation for hook-script-driven approvals."""

    # Seconds between idle heartbeats when nothing is pending. 5s keeps
    # the UI snappy but doesn't overwhelm the reducer.
    _IDLE_HEARTBEAT_S = 5.0

    def __init__(self) -> None:
        self._on_line: Callable[[str], Awaitable[None]] | None = None
        self._on_connect: Callable[[], Awaitable[None]] | None = None
        self._on_disconnect: Callable[[], Awaitable[None]] | None = None
        self._idle_task: asyncio.Task[None] | None = None
        self._pending: dict[str, _Pending] = {}
        self._lock = asyncio.Lock()
        self._tokens_today = 0
        self._started = False

    # --- Upstream protocol --------------------------------------------

    async def start(
        self,
        *,
        on_line: Callable[[str], Awaitable[None]],
        on_connect: Callable[[], Awaitable[None]],
        on_disconnect: Callable[[], Awaitable[None]],
    ) -> None:
        self._on_line = on_line
        self._on_connect = on_connect
        self._on_disconnect = on_disconnect
        self._started = True
        await on_connect()
        # Kick an immediate heartbeat so desktop.status flips to
        # "connected" with lastHeartbeatAt populated.
        await self._emit_heartbeat(prompt=None, running=0, waiting=0)
        self._idle_task = asyncio.create_task(
            self._idle_loop(), name="hook-upstream-idle"
        )
        log.info("hook upstream: ready (no BLE, no Claude desktop, just hooks)")

    async def send(self, payload: bytes) -> None:
        """Bridge -> upstream. We only care about permission lines."""
        try:
            line = payload.decode("utf-8").strip()
            if not line:
                return
            obj = json.loads(line)
        except (UnicodeDecodeError, json.JSONDecodeError):
            log.debug("hook upstream: ignoring non-JSON send: %r", payload[:80])
            return

        if not isinstance(obj, dict):
            return
        if obj.get("cmd") != "permission":
            # Acks and unpair confirmations are no-ops for us.
            return

        prompt_id = obj.get("id")
        raw_decision = obj.get("decision")
        if not isinstance(prompt_id, str) or not isinstance(raw_decision, str):
            log.warning("hook upstream: malformed permission: %s", obj)
            return

        decision: Decision
        if raw_decision == "once":
            decision = "allow"
        elif raw_decision == "deny":
            decision = "deny"
        else:
            log.warning("hook upstream: unexpected decision: %s", raw_decision)
            return

        async with self._lock:
            pending = self._pending.pop(prompt_id, None)

        if pending is None:
            log.warning("hook upstream: no pending request for %s", prompt_id)
            return

        if not pending.future.done():
            pending.future.set_result(decision)

        # Schedule the clearing heartbeat instead of awaiting it so
        # the bridge's handle_decide can finish applying ClientDecide
        # (which reads state.prompt) before we clear it.
        asyncio.create_task(
            self._emit_heartbeat(prompt=None, running=0, waiting=0),
            name="hook-upstream-clear",
        )

    async def stop(self) -> None:
        self._started = False
        if self._idle_task is not None:
            self._idle_task.cancel()
            try:
                await self._idle_task
            except asyncio.CancelledError:
                pass
            self._idle_task = None
        # Resolve any pending requests so hook scripts don't hang.
        async with self._lock:
            pending = list(self._pending.values())
            self._pending.clear()
        for p in pending:
            if not p.future.done():
                p.future.set_result("ask")
        if self._on_disconnect is not None:
            try:
                await self._on_disconnect()
            except Exception:  # noqa: BLE001
                pass

    # --- Public: hook script HTTP handler uses this -------------------

    async def request_decision(
        self, *, tool: str, hint: str, source: str = "other", timeout_s: float
    ) -> Decision:
        """Push a synthetic permission prompt; await phone decision."""
        if not self._started:
            return "ask"

        prompt_id = f"hook_{uuid.uuid4().hex[:12]}"
        loop = asyncio.get_running_loop()
        fut: asyncio.Future[Decision] = loop.create_future()
        pending = _Pending(
            prompt_id=prompt_id, future=fut, tool=tool, hint=hint, source=source
        )

        async with self._lock:
            self._pending[prompt_id] = pending

        # Emit the heartbeat that carries the prompt. waiting=1 so the
        # pet goes to "attention"; running=1 so "busy" could show if
        # there were multiple concurrent.
        await self._emit_heartbeat(
            prompt={
                "id": prompt_id,
                "tool": tool,
                "hint": hint,
                "source": source,
            },
            running=1,
            waiting=1,
            msg=_short_msg(tool, hint, source),
            entries=[_short_msg(tool, hint, source)],
        )

        try:
            return await asyncio.wait_for(fut, timeout=timeout_s)
        except asyncio.TimeoutError:
            async with self._lock:
                self._pending.pop(prompt_id, None)
            log.info("hook upstream: %s timed out after %ss", prompt_id, timeout_s)
            # Clear the prompt so the UI doesn't linger on it.
            await self._emit_heartbeat(prompt=None, running=0, waiting=0)
            return "ask"

    # --- Internals ----------------------------------------------------

    async def _idle_loop(self) -> None:
        try:
            while self._started:
                await asyncio.sleep(self._IDLE_HEARTBEAT_S)
                if not self._pending:
                    await self._emit_heartbeat(prompt=None, running=0, waiting=0)
        except asyncio.CancelledError:
            raise

    async def _emit_heartbeat(
        self,
        *,
        prompt: dict[str, object] | None,
        running: int,
        waiting: int,
        msg: str = "",
        entries: list[str] | None = None,
    ) -> None:
        if self._on_line is None:
            return
        body: dict[str, object] = {
            "total": running,
            "running": running,
            "waiting": waiting,
            "msg": msg,
            "entries": entries or [],
            "tokens": 0,
            "tokens_today": self._tokens_today,
        }
        if prompt is not None:
            body["prompt"] = prompt
        line = json.dumps(body, separators=(",", ":"))
        await self._on_line(line)


def _short_msg(tool: str, hint: str, source: str = "") -> str:
    """Human-friendly one-liner for the entries list."""
    base = tool or "tool"
    if source and source != "other":
        base = f"[{source}] {base}"
    if hint:
        short = hint if len(hint) <= 60 else hint[:57] + "..."
        return f"{base}: {short}"
    return base
