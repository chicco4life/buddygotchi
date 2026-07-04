from __future__ import annotations

import base64
import json
import re
import subprocess
import sys
import time
import zlib
from pathlib import Path

import pytest


TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))
import buddyctl  # noqa: E402


@pytest.fixture(scope="session")
def stick():
    try:
        port = buddyctl.find_port()
        serial = buddyctl.SerialBuddy(port, timeout=5)
        serial.__enter__()
        serial.framed_json("ping", "PONG", 3)
    except buddyctl.BuddyError as exc:
        pytest.skip(f"no ESP32 Buddy attached: {exc}")
    try:
        yield serial
    finally:
        serial.__exit__(None, None, None)


def local_git_sha() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short=12", "HEAD"],
            cwd=Path(__file__).resolve().parents[3],
            text=True,
        ).strip()
    except Exception:
        return "unknown"


def send_json(stick, payload: dict) -> None:
    stick.write_line(json.dumps(payload, separators=(",", ":")))
    time.sleep(0.15)


def state(stick) -> dict:
    return stick.framed_json("state", "STATE", 3)


def wait_state(stick, **want):
    deadline = time.monotonic() + 5
    last = {}
    while time.monotonic() < deadline:
        last = state(stick)
        if all(last.get(k) == v for k, v in want.items()):
            return last
        time.sleep(0.2)
    pytest.fail(f"state did not match {want}; last={last}")


def find_json_line(buf: bytes, **want):
    for raw in buf.splitlines():
        try:
            obj = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            continue
        if all(obj.get(k) == v for k, v in want.items()):
            return obj
    return None


def test_ping_reports_build(stick):
    pong = stick.framed_json("ping", "PONG", 3)
    assert pong["fw"]
    assert pong["up"] >= 0
    want = local_git_sha()
    if want != "unknown":
        assert pong["git"] == want


def test_default_state_is_sleep(stick):
    send_json(stick, {"total": 0, "running": 0, "waiting": 0, "pet": "sleep", "desktop": "disconnected"})
    got = wait_state(stick, pet="sleep", connected=True)
    assert got["mode"] == "live"


@pytest.mark.parametrize(
    ("pet", "persona"),
    [
        ("sleep", "P_SLEEP"),
        ("idle", "P_IDLE"),
        ("busy", "P_BUSY"),
        ("attention", "P_ATTENTION"),
        ("celebrate", "P_CELEBRATE"),
        ("error", "P_DIZZY"),
        ("thinking", "P_BUSY"),
    ],
)
def test_heartbeat_states(stick, pet, persona):
    send_json(stick, {"total": 2, "running": 1, "waiting": int(pet == "attention"), "pet": pet, "species": "cat"})
    got = wait_state(stick, pet=pet, species="cat")
    assert got["persona"] == persona


def test_mute_heartbeat_updates_state(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "mute": True})
    got = wait_state(stick, pet="idle", muted=True)
    assert got["muted"] is True

    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "mute": False})
    got = wait_state(stick, pet="idle", muted=False)
    assert got["muted"] is False


def test_display_brightness_tiers(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 1, "pet": "attention"})
    got = wait_state(stick, pet="attention", brightness=220, screenOff=False)
    assert got["screen"] != "off"

    send_json(stick, {"total": 0, "running": 0, "waiting": 0, "pet": "sleep"})
    got = wait_state(stick, pet="sleep", brightness=120, screenOff=False)
    assert got["screen"] != "off"


def test_approval_usb(stick):
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.write_line("press a 120")
    buf, _ = stick.read_until(lambda b: b'"cmd":"permission"' in b and b"<<PRESS a up>>" in b, 3)
    text = buf.decode("utf-8", "replace")
    assert '"id":"DEBUG"' in text
    assert '"decision":"allow"' in text


def test_button_edges(stick):
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.write_line("press a 350")
    buf, _ = stick.read_until(lambda b: b"<<PRESS a down>>" in b, 1)
    assert b'"cmd":"permission"' not in buf
    buf, _ = stick.read_until(lambda b: b'"decision":"allow"' in b and b"<<PRESS a up>>" in b, 2)
    assert b'"decision":"allow"' in buf

    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.write_line("press b 350")
    buf, _ = stick.read_until(lambda b: b'"decision":"deny"' in b, 1)
    assert b"<<PRESS b down>>" in buf


def test_long_press_without_prompt_toggles_screen_without_permission(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 1, "pet": "attention"})
    wait_state(stick, pet="attention", screenOff=False)
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    wait_state(stick, pet="idle", promptId="", screenOff=False)
    stick.drain_until_quiet(max_wait=0.2)

    stick.write_line("press a 1600")
    buf, _ = stick.read_until(lambda b: b"<<PRESS a up>>" in b, 3)
    tail = stick.drain_until_quiet(max_wait=0.5)
    assert b'"cmd":"permission"' not in buf + tail
    wait_state(stick, screenOff=True)

    stick.write_line("press a 120")
    buf, _ = stick.read_until(lambda b: b"<<PRESS a up>>" in b, 2)
    tail = stick.drain_until_quiet(max_wait=0.5)
    assert b'"cmd":"permission"' not in buf + tail
    wait_state(stick, screenOff=False)


def test_long_press_with_prompt_does_not_approve(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 1, "pet": "attention"})
    wait_state(stick, pet="attention", screenOff=False)
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.drain_until_quiet(max_wait=0.2)

    stick.write_line("press a 1600")
    buf, _ = stick.read_until(lambda b: b"<<PRESS a up>>" in b, 3)
    tail = stick.drain_until_quiet(max_wait=0.5)
    assert b'"cmd":"permission"' not in buf + tail
    got = wait_state(stick, promptId="DEBUG", responseSent=False)
    assert got["promptApproval"] is True

    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    wait_state(stick, promptId="")


def test_ota_rejects_invalid_begin_and_chunk_without_session(stick):
    stick.drain_until_quiet(max_wait=0.2)
    stick.write_line(
        json.dumps(
            {"cmd": "ota_begin", "size": 0, "sha256": "0" * 64, "version": "test"},
            separators=(",", ":"),
        )
    )
    _, begin = stick.read_until(lambda b: find_json_line(b, ack="ota_begin", ok=False), 2)
    assert begin["error"] == "size=0"

    stick.write_line(json.dumps({"cmd": "ota_chunk", "seq": 0, "d": ""}, separators=(",", ":")))
    _, chunk = stick.read_until(lambda b: find_json_line(b, ack="ota_chunk", ok=False), 2)
    assert chunk["error"] == "no_session"


def test_screenshot_integrity(stick):
    stick.write_line("screenshot")
    buf, parsed = stick.read_until(buddyctl.parse_screenshot, 15)
    begin, body_start, _body_end, end = parsed
    w = int(begin.group(1))
    h = int(begin.group(2))
    body = re.sub(rb"\s+", b"", buf[body_start : body_start + end.start()])
    raw = base64.b64decode(body, validate=True)
    assert len(raw) == w * h * 2
    assert end.group(1) is not None
    assert int(end.group(1)) == len(raw)
    assert int(end.group(2), 16) == (zlib.crc32(raw) & 0xFFFFFFFF)


@pytest.mark.slow
def test_connection_timeout(stick):
    send_json(stick, {"total": 1, "running": 1, "waiting": 0, "pet": "busy"})
    wait_state(stick, pet="busy", connected=True)
    deadline = time.monotonic() + 35
    last = {}
    while time.monotonic() < deadline:
        last = state(stick)
        if last.get("connected") is False and last.get("pet") == "sleep":
            return
        time.sleep(1)
    pytest.fail(f"device did not return to sleep after heartbeat timeout; last={last}")
