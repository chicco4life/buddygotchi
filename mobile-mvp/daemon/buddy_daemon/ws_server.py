"""aiohttp WebSocket server implementing boundary [B].

One route (``/ws``), one auth gate (pairing), one outbound stream
(snapshot + patches), one inbound stream (decide/ping/subscribe).
Static assets are served when ``web_root`` is set.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
import uuid
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

from aiohttp import WSMsgType, web

from . import __version__
from .bridge import Bridge
from .config import Config
from .errors import ErrorCode
from .hook_upstream import HookUpstream
from .pairing import PairingManager
from .state import BuddyState

log = logging.getLogger(__name__)

SESSION_ID = uuid.uuid4().hex[:12]


# ---------------------------------------------------------------------------
# App wiring
# ---------------------------------------------------------------------------


def build_app(
    *,
    config: Config,
    bridge: Bridge,
    pairing: PairingManager,
    hook_upstream: HookUpstream | None = None,
    web_root: Path | None = None,
) -> web.Application:
    app = web.Application()
    app["config"] = config
    app["bridge"] = bridge
    app["pairing"] = pairing
    app["hook_upstream"] = hook_upstream
    app.router.add_get("/ws", ws_handler)
    app.router.add_get("/healthz", healthz)
    app.router.add_get("/pair/current", pair_current_handler)
    if hook_upstream is not None:
        app.router.add_post("/hook/request", hook_request_handler)
    if web_root is not None and web_root.is_dir():
        # Serve the SPA at / with index.html fallback. ``show_index=False``
        # because we always want index.html at the root.
        index_path = web_root / "index.html"

        async def serve_index(_req: web.Request) -> web.Response:
            if not index_path.is_file():
                return web.Response(status=404, text="index.html missing")
            return web.FileResponse(index_path)

        app.router.add_get("/", serve_index)
        app.router.add_static("/", web_root, show_index=False)
    return app


async def healthz(request: web.Request) -> web.Response:
    bridge: Bridge = request.app["bridge"]
    state = bridge.state()
    return web.json_response(
        {
            "ok": True,
            "serverVersion": __version__,
            "sessionId": SESSION_ID,
            "stateVersion": state.version,
            "desktop": state.desktop.status,
        }
    )


# ---------------------------------------------------------------------------
# Pairing code self-service (loopback only)
# ---------------------------------------------------------------------------


_LOOPBACK_PEERS = frozenset({"127.0.0.1", "::1"})


def _is_loopback(request: web.Request) -> bool:
    peer = request.transport.get_extra_info("peername") if request.transport else None
    if not peer:
        return False
    host = peer[0] if isinstance(peer, tuple) else peer
    return host in _LOOPBACK_PEERS


async def pair_current_handler(request: web.Request) -> web.Response:
    """Return the current pairing code, rotating if expired.

    Only the machine hosting the daemon can hit this. LAN clients (your
    phone) still must receive the code out-of-band (e.g. from the same
    browser tab on the Mac the daemon is running on) before first pair.
    """
    if not _is_loopback(request):
        return web.json_response(
            {"error": "loopback_only"},
            status=403,
        )
    pairing: PairingManager = request.app["pairing"]
    code = pairing.current_code()
    if code is None:
        code = pairing.rotate_code()
        rotated = True
    else:
        rotated = False
    config: Config = request.app["config"]
    return web.json_response(
        {"code": code, "ttlSeconds": config.pairing_code_ttl_s, "rotated": rotated}
    )


# ---------------------------------------------------------------------------
# Hook endpoint (Cursor / Claude Code / any PreToolUse integration)
# ---------------------------------------------------------------------------


async def hook_request_handler(request: web.Request) -> web.Response:
    """Accept a synthetic permission request from a hook script.

    Request JSON:  {"tool": str, "hint": str, "timeout_s"?: float}
    Response JSON: {"decision": "allow" | "deny" | "ask"}

    The route is intentionally unauthenticated: it only accepts
    connections bound to the daemon's HTTP host (loopback in the
    typical case). Phone clients never hit this path.
    """
    hook_upstream: HookUpstream | None = request.app["hook_upstream"]
    if hook_upstream is None:
        return web.json_response({"error": "hook_upstream_not_enabled"}, status=503)

    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "invalid_json"}, status=400)

    if not isinstance(body, dict):
        return web.json_response({"error": "body_not_object"}, status=400)

    tool = body.get("tool")
    hint = body.get("hint", "")
    source = body.get("source", "other")
    timeout_s = body.get("timeout_s", 30.0)

    if not isinstance(tool, str) or not tool:
        return web.json_response({"error": "missing_tool"}, status=400)
    if not isinstance(hint, str):
        return web.json_response({"error": "hint_not_string"}, status=400)
    if not isinstance(source, str):
        return web.json_response({"error": "source_not_string"}, status=400)
    if not isinstance(timeout_s, (int, float)) or timeout_s <= 0 or timeout_s > 600:
        return web.json_response({"error": "bad_timeout"}, status=400)

    decision = await hook_upstream.request_decision(
        tool=tool, hint=hint, source=source, timeout_s=float(timeout_s)
    )
    return web.json_response({"decision": decision})


# ---------------------------------------------------------------------------
# WS connection
# ---------------------------------------------------------------------------


async def ws_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse(heartbeat=20.0)
    await ws.prepare(request)
    conn = WsConnection(
        ws=ws,
        bridge=request.app["bridge"],
        pairing=request.app["pairing"],
    )
    try:
        await conn.run()
    finally:
        await conn.close()
    return ws


# ---------------------------------------------------------------------------
# Per-connection logic
# ---------------------------------------------------------------------------


class WsConnection:
    PROTOCOL_VERSION = 1

    def __init__(
        self, *, ws: web.WebSocketResponse, bridge: Bridge, pairing: PairingManager
    ) -> None:
        self._ws = ws
        self._bridge = bridge
        self._pairing = pairing
        self._client_id: str | None = None
        self._last_version: int = -1
        self._unsub: Any = None
        self._authed = False
        self._send_lock = asyncio.Lock()

    async def run(self) -> None:
        async for msg in self._ws:
            if msg.type == WSMsgType.TEXT:
                await self._handle_text(msg.data)
            elif msg.type in (WSMsgType.CLOSE, WSMsgType.CLOSING, WSMsgType.CLOSED):
                break
            elif msg.type == WSMsgType.ERROR:
                log.warning("ws error: %s", self._ws.exception())
                break

    async def close(self) -> None:
        if self._unsub is not None:
            try:
                self._unsub()
            except Exception:
                pass
            self._unsub = None
        if not self._ws.closed:
            await self._ws.close()

    # --- dispatch ------------------------------------------------------

    async def _handle_text(self, raw: str) -> None:
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            await self._send_error(None, "E_BAD_MESSAGE", "invalid_json")
            return
        if not isinstance(msg, dict):
            await self._send_error(None, "E_BAD_MESSAGE", "not_object")
            return

        mtype = msg.get("type")

        if mtype == "hello":
            await self._handle_hello(msg)
            return

        if not self._authed:
            await self._send_error(msg.get("reqId"), "E_PAIRING_REQUIRED")
            return

        if mtype == "decide":
            await self._handle_decide(msg)
            return
        if mtype == "ping":
            await self._send({"type": "ack", "reqId": msg.get("reqId"), "ok": True})
            return
        if mtype == "subscribe":
            # MVP: we always send state; log channel is not yet wired.
            await self._send({"type": "ack", "reqId": msg.get("reqId", ""), "ok": True})
            return

        await self._send_error(msg.get("reqId"), "E_UNSUPPORTED", f"type={mtype}")

    async def _handle_hello(self, msg: dict[str, Any]) -> None:
        proto_ver = msg.get("protocolVersion")
        if proto_ver != self.PROTOCOL_VERSION:
            await self._send_error(None, "E_UNSUPPORTED", f"protocol={proto_ver}")
            await self._ws.close()
            return

        client_id = msg.get("clientId")
        if not isinstance(client_id, str) or not client_id:
            await self._send_error(None, "E_BAD_MESSAGE", "missing_clientId")
            return
        self._client_id = client_id

        outcome = self._pairing.authorize(
            client_id=client_id,
            pairing_code=msg.get("pairingCode"),
            token=msg.get("token"),
        )
        if not outcome.ok:
            await self._send_error(None, outcome.error or "E_PAIRING_INVALID")
            return

        self._authed = True

        state = self._bridge.state()
        self._last_version = state.version
        welcome: dict[str, Any] = {
            "type": "welcome",
            "protocolVersion": self.PROTOCOL_VERSION,
            "serverVersion": __version__,
            "sessionId": SESSION_ID,
            "state": _state_to_jsonable(state),
        }
        if outcome.issued_token is not None:
            welcome["issuedToken"] = outcome.issued_token
        await self._send(welcome)

        last_seen = msg.get("lastVersion")
        if isinstance(last_seen, int) and last_seen > state.version:
            # Client saw something we no longer have (daemon restart).
            # Welcome already carried a fresh snapshot; nothing else to do.
            pass

        self._unsub = self._bridge.subscribe(self._on_state_change)

    async def _handle_decide(self, msg: dict[str, Any]) -> None:
        req_id = msg.get("reqId")
        prompt_id = msg.get("promptId")
        decision = msg.get("decision")
        if not isinstance(req_id, str) or not isinstance(prompt_id, str) or not isinstance(decision, str):
            await self._send_error(req_id, "E_BAD_MESSAGE")
            return
        assert self._client_id is not None
        ok, err = await self._bridge.handle_decide(
            client_id=self._client_id,
            prompt_id=prompt_id,
            decision=decision,
        )
        if ok:
            await self._send({"type": "ack", "reqId": req_id, "ok": True})
        else:
            await self._send_error(req_id, err or "E_BAD_MESSAGE")

    # --- outbound ------------------------------------------------------

    async def _on_state_change(self, prev: BuddyState, new: BuddyState) -> None:
        if self._ws.closed:
            return
        if new.version - self._last_version > 1 or prev.version != self._last_version:
            # Gap or we never saw prev; send a fresh snapshot.
            await self._send(
                {"type": "snapshot", "state": _state_to_jsonable(new)}
            )
        else:
            changes = _diff(prev, new)
            await self._send(
                {
                    "type": "patch",
                    "version": new.version,
                    "prevVersion": prev.version,
                    "changes": changes,
                }
            )
        self._last_version = new.version

    async def _send(self, obj: dict[str, Any]) -> None:
        async with self._send_lock:
            if self._ws.closed:
                return
            try:
                await self._ws.send_json(obj)
            except ConnectionResetError:
                pass

    async def _send_error(
        self, req_id: str | None, code: ErrorCode, detail: str | None = None
    ) -> None:
        payload: dict[str, Any] = {
            "type": "ack",
            "reqId": req_id or "",
            "ok": False,
            "error": code,
        }
        if detail is not None:
            payload["detail"] = detail
        await self._send(payload)


# ---------------------------------------------------------------------------
# Serialization helpers
# ---------------------------------------------------------------------------


def _state_to_jsonable(state: BuddyState) -> dict[str, Any]:
    return state.to_dict()


def _diff(prev: BuddyState, new: BuddyState) -> dict[str, Any]:
    """Compute a shallow diff suitable for Patch.changes.

    Nested objects (desktop, sessions, prompt, pet) are replaced
    atomically, per the protocol contract.
    """
    out: dict[str, Any] = {}
    for field in (
        "version",
        "updatedAt",
        "msg",
        "entries",
        "tokens",
        "tokensToday",
        "owner",
    ):
        if getattr(prev, field) != getattr(new, field):
            out[field] = _jsonable(getattr(new, field))

    for field in ("desktop", "sessions", "pet"):
        if getattr(prev, field) != getattr(new, field):
            out[field] = _jsonable(getattr(new, field))

    if prev.prompt != new.prompt:
        out["prompt"] = _jsonable(new.prompt)

    return out


def _jsonable(v: Any) -> Any:
    if v is None:
        return None
    if is_dataclass(v):
        return asdict(v)
    if isinstance(v, tuple):
        return list(v)
    return v
