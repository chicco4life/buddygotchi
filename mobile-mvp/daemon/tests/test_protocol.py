"""Contract tests for boundary [A] parser/serializer."""

from __future__ import annotations

import json

from buddy_daemon.events import Heartbeat, OwnerSet, TimeSync
from buddy_daemon.protocol import (
    CommandInbound,
    FolderPushInbound,
    LineBuffer,
    TurnEventInbound,
    UnknownLine,
    parse_line,
    serialize_ack,
    serialize_permission,
)


def test_parse_time_sync() -> None:
    r = parse_line('{"time":[1775731234,-25200]}', now_ms=1_000)
    assert isinstance(r, TimeSync)
    assert r.epoch_s == 1775731234
    assert r.tz_offset_s == -25200
    assert r.at == 1_000


def test_parse_heartbeat_without_prompt() -> None:
    r = parse_line(
        json.dumps(
            {
                "total": 3,
                "running": 1,
                "waiting": 0,
                "msg": "busy",
                "entries": ["a", "b"],
                "tokens": 100,
                "tokens_today": 50,
            }
        ),
        now_ms=2_000,
    )
    assert isinstance(r, Heartbeat)
    assert r.total == 3
    assert r.running == 1
    assert r.msg == "busy"
    assert r.entries == ["a", "b"]
    assert r.prompt_id is None


def test_parse_heartbeat_with_prompt() -> None:
    r = parse_line(
        json.dumps(
            {
                "total": 1,
                "running": 1,
                "waiting": 1,
                "msg": "approve: Bash",
                "entries": [],
                "tokens": 0,
                "tokens_today": 0,
                "prompt": {"id": "req_1", "tool": "Bash", "hint": "ls"},
            }
        )
    )
    assert isinstance(r, Heartbeat)
    assert r.prompt_id == "req_1"
    assert r.prompt_tool == "Bash"
    assert r.prompt_hint == "ls"


def test_parse_owner_unsolicited() -> None:
    r = parse_line('{"cmd":"owner","name":"Felix"}')
    assert isinstance(r, OwnerSet)
    assert r.name == "Felix"


def test_parse_turn_event_accepted_and_dropped() -> None:
    r = parse_line('{"evt":"turn","role":"assistant","content":[]}')
    assert isinstance(r, TurnEventInbound)


def test_parse_ackable_commands() -> None:
    for cmd in ("status", "name", "unpair"):
        r = parse_line(f'{{"cmd":"{cmd}"}}')
        assert isinstance(r, CommandInbound)
        assert r.cmd == cmd


def test_parse_folder_push_returns_folder_marker() -> None:
    r = parse_line('{"cmd":"char_begin","name":"bufo","total":1024}')
    assert isinstance(r, FolderPushInbound)
    assert r.cmd == "char_begin"


def test_parse_unknown_cmd() -> None:
    r = parse_line('{"cmd":"mystery"}')
    assert isinstance(r, UnknownLine)
    assert "mystery" in r.reason


def test_parse_invalid_json() -> None:
    r = parse_line("not json at all")
    assert isinstance(r, UnknownLine)


def test_parse_empty_line() -> None:
    r = parse_line("")
    assert isinstance(r, UnknownLine)


def test_serialize_permission() -> None:
    out = serialize_permission("req_abc", "once")
    assert out.endswith(b"\n")
    obj = json.loads(out)
    assert obj == {"cmd": "permission", "id": "req_abc", "decision": "once"}


def test_serialize_ack_ok() -> None:
    out = serialize_ack("status", ok=True, data={"name": "x", "sec": False})
    obj = json.loads(out)
    assert obj["ack"] == "status"
    assert obj["ok"] is True
    assert obj["data"] == {"name": "x", "sec": False}


def test_serialize_ack_error() -> None:
    out = serialize_ack("mystery", ok=False, error="unsupported")
    obj = json.loads(out)
    assert obj == {"ack": "mystery", "ok": False, "error": "unsupported"}


def test_line_buffer_reassembles_fragments() -> None:
    buf = LineBuffer()
    assert buf.feed(b'{"time":[1,') == []
    assert buf.feed(b"2]}\n") == ['{"time":[1,2]}']


def test_line_buffer_multiple_lines_in_one_chunk() -> None:
    buf = LineBuffer()
    out = buf.feed(b'{"a":1}\n{"b":2}\n')
    assert out == ['{"a":1}', '{"b":2}']


def test_line_buffer_ignores_trailing_partial() -> None:
    buf = LineBuffer()
    assert buf.feed(b'{"a":1}\n{"b":') == ['{"a":1}']
    assert buf.feed(b"2}\n") == ['{"b":2}']
