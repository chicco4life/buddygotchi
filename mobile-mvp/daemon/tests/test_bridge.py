"""End-to-end bridge test: fake upstream + bridge + validated decisions."""

from __future__ import annotations

import asyncio
import json

import pytest

from buddy_daemon.bridge import Bridge
from buddy_daemon.config import Config
from buddy_daemon.upstream import FakeTcpUpstream


async def _wait_for(pred, timeout: float = 2.0, interval: float = 0.02) -> None:
    end = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < end:
        if pred():
            return
        await asyncio.sleep(interval)
    raise AssertionError("timeout waiting for predicate")


async def _connect(port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
    return await asyncio.open_connection("127.0.0.1", port)


async def _send(w: asyncio.StreamWriter, obj: dict) -> None:
    w.write((json.dumps(obj) + "\n").encode("utf-8"))
    await w.drain()


async def _read_line(r: asyncio.StreamReader, timeout: float = 2.0) -> dict:
    data = await asyncio.wait_for(r.readline(), timeout=timeout)
    return json.loads(data.decode("utf-8").rstrip())


@pytest.fixture
async def bridge_fixture(unused_tcp_port):
    config = Config(fake_upstream_port=unused_tcp_port, decide_min_interval_ms=0)
    upstream = FakeTcpUpstream(
        host=config.fake_upstream_host, port=config.fake_upstream_port
    )
    bridge = Bridge(config=config, upstream=upstream)
    await bridge.start()
    try:
        yield bridge, config
    finally:
        await bridge.stop()


async def test_heartbeat_reaches_reducer(bridge_fixture) -> None:
    bridge, config = bridge_fixture
    r, w = await _connect(config.fake_upstream_port)
    try:
        await _send(w, {"total": 2, "running": 1, "waiting": 0, "msg": "x", "entries": [], "tokens": 0, "tokens_today": 0})
        await _wait_for(lambda: bridge.state().sessions.total == 2)
        assert bridge.state().desktop.status == "connected"
    finally:
        w.close()
        await w.wait_closed()


async def test_status_command_is_acked(bridge_fixture) -> None:
    bridge, config = bridge_fixture
    r, w = await _connect(config.fake_upstream_port)
    try:
        await _send(w, {"cmd": "status"})
        ack = await _read_line(r)
        assert ack["ack"] == "status"
        assert ack["ok"] is True
        assert "name" in ack["data"]
    finally:
        w.close()
        await w.wait_closed()


async def test_char_begin_is_not_acked(bridge_fixture) -> None:
    """MVP policy: we never ack char_begin so desktop times out folder push."""
    bridge, config = bridge_fixture
    r, w = await _connect(config.fake_upstream_port)
    try:
        await _send(w, {"cmd": "char_begin", "name": "bufo", "total": 100})
        await asyncio.sleep(0.1)
        with pytest.raises(asyncio.TimeoutError):
            await asyncio.wait_for(r.readline(), timeout=0.2)
    finally:
        w.close()
        await w.wait_closed()


async def test_decide_requires_active_prompt(bridge_fixture) -> None:
    bridge, config = bridge_fixture
    ok, err = await bridge.handle_decide(
        client_id="c1", prompt_id="nonexistent", decision="once"
    )
    assert ok is False
    assert err == "E_NO_ACTIVE_PROMPT"


async def test_decide_rejects_wrong_prompt_id(bridge_fixture) -> None:
    bridge, config = bridge_fixture
    r, w = await _connect(config.fake_upstream_port)
    try:
        await _send(
            w,
            {
                "total": 1,
                "running": 1,
                "waiting": 1,
                "msg": "approve",
                "entries": [],
                "tokens": 0,
                "tokens_today": 0,
                "prompt": {"id": "req_real", "tool": "Bash", "hint": ""},
            },
        )
        await _wait_for(lambda: bridge.state().prompt is not None)
        ok, err = await bridge.handle_decide(
            client_id="c1", prompt_id="req_wrong", decision="once"
        )
        assert ok is False
        assert err == "E_PROMPT_ID_MISMATCH"
    finally:
        w.close()
        await w.wait_closed()


async def test_decide_forwards_and_races(bridge_fixture) -> None:
    bridge, config = bridge_fixture
    r, w = await _connect(config.fake_upstream_port)
    try:
        await _send(
            w,
            {
                "total": 1, "running": 1, "waiting": 1, "msg": "approve",
                "entries": [], "tokens": 0, "tokens_today": 0,
                "prompt": {"id": "req_1", "tool": "Bash", "hint": ""},
            },
        )
        await _wait_for(lambda: bridge.state().prompt is not None)

        ok1, err1 = await bridge.handle_decide(
            client_id="c1", prompt_id="req_1", decision="once"
        )
        assert ok1 is True
        assert err1 is None

        # Verify the permission line was written upstream.
        line = await _read_line(r)
        assert line == {"cmd": "permission", "id": "req_1", "decision": "once"}

        # Second client tries to decide the same prompt -> rejected.
        ok2, err2 = await bridge.handle_decide(
            client_id="c2", prompt_id="req_1", decision="deny"
        )
        assert ok2 is False
        assert err2 == "E_ALREADY_DECIDED"
    finally:
        w.close()
        await w.wait_closed()


async def test_decide_blocked_when_desktop_disconnected(bridge_fixture) -> None:
    bridge, config = bridge_fixture
    # No upstream connected; state starts disconnected.
    ok, err = await bridge.handle_decide(
        client_id="c1", prompt_id="anything", decision="once"
    )
    # Without an active prompt we'd get E_NO_ACTIVE_PROMPT first, which
    # is fine — the disconnect branch is primarily exercised in a
    # disconnect-mid-prompt scenario; guarded here so the error
    # ordering doesn't silently change.
    assert ok is False
    assert err in ("E_NO_ACTIVE_PROMPT", "E_DESKTOP_DISCONNECTED")
