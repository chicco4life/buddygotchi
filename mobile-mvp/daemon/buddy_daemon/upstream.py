"""Upstream abstraction.

The daemon never imports a concrete upstream; it takes an ``Upstream``
instance at wire-up time. Production wiring uses ``HookUpstream``
(see ``hook_upstream.py``). ``FakeTcpUpstream`` below is kept **only
as a test fixture** for ``tests/test_bridge.py`` — it lets tests push
raw upstream JSON lines and read the daemon's responses without
spinning up the hook HTTP path.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable, Protocol

from .protocol import LineBuffer

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------


class Upstream(Protocol):
    """Abstract duplex line transport against Claude desktop."""

    async def start(
        self,
        *,
        on_line: Callable[[str], Awaitable[None]],
        on_connect: Callable[[], Awaitable[None]],
        on_disconnect: Callable[[], Awaitable[None]],
    ) -> None: ...

    async def send(self, payload: bytes) -> None: ...

    async def stop(self) -> None: ...


# ---------------------------------------------------------------------------
# Test fixture (not wired into production main.py)
# ---------------------------------------------------------------------------


class FakeTcpUpstream:
    """Loopback TCP upstream, used exclusively by tests.

    Each new TCP connection counts as "upstream connected". Lines are
    ``\\n``-terminated JSON. Bytes written via ``send()`` echo back
    over the socket so tests can assert outbound messages.

    ``__DISCONNECT__\\n`` is a sentinel that simulates a disconnect
    without closing the socket.
    """

    def __init__(self, *, host: str, port: int) -> None:
        self._host = host
        self._port = port
        self._server: asyncio.base_events.Server | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._on_line: Callable[[str], Awaitable[None]] | None = None
        self._on_connect: Callable[[], Awaitable[None]] | None = None
        self._on_disconnect: Callable[[], Awaitable[None]] | None = None

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
        self._server = await asyncio.start_server(
            self._handle_client, host=self._host, port=self._port
        )
        log.info("fake upstream listening on tcp://%s:%s", self._host, self._port)

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        if self._writer is not None:
            log.warning("fake upstream: second client rejected")
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return

        peer = writer.get_extra_info("peername")
        log.info("fake upstream: connected %s", peer)
        self._writer = writer
        assert self._on_connect and self._on_line and self._on_disconnect
        await self._on_connect()

        buf = LineBuffer()
        try:
            while True:
                chunk = await reader.read(4096)
                if not chunk:
                    break
                for line in buf.feed(chunk):
                    if line.strip() == "__DISCONNECT__":
                        log.info("fake upstream: synthetic disconnect")
                        await self._on_disconnect()
                        # Stay listening for more lines; next real line
                        # triggers a fresh on_connect.
                        await self._on_connect()
                        continue
                    await self._on_line(line)
        except ConnectionResetError:
            pass
        finally:
            log.info("fake upstream: disconnected %s", peer)
            self._writer = None
            await self._on_disconnect()
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def send(self, payload: bytes) -> None:
        w = self._writer
        if w is None or w.is_closing():
            log.warning("fake upstream: send dropped, no client")
            return
        w.write(payload)
        try:
            await w.drain()
        except (ConnectionResetError, BrokenPipeError):
            self._writer = None

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
        if self._writer is not None:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except Exception:
                pass
            self._writer = None
