"""Reducer invariants (Part A §A.2 / README.md §Invariants)."""

from __future__ import annotations

from buddy_daemon.events import (
    BleConnected,
    BleDisconnected,
    ClientDecide,
    Heartbeat,
    OwnerSet,
    StaleTick,
    TimeSync,
)
from buddy_daemon.state import INITIAL_STATE, reduce


def _hb(**kw):
    base = dict(
        at=1_000,
        total=0,
        running=0,
        waiting=0,
        msg="",
        entries=[],
        tokens=0,
        tokens_today=0,
        prompt_id=None,
        prompt_tool=None,
        prompt_hint=None,
    )
    base.update(kw)
    return Heartbeat(**base)


def test_initial_state() -> None:
    s = INITIAL_STATE
    assert s.version == 0
    assert s.desktop.status == "disconnected"
    assert s.prompt is None
    assert s.pet.state == "sleep"


def test_ble_connected_bumps_version_once() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    assert s.version == 1
    assert s.desktop.status == "connected"


def test_duplicate_connect_is_noop() -> None:
    s1 = reduce(INITIAL_STATE, BleConnected(at=1))
    s2 = reduce(s1, BleConnected(at=2))
    assert s2 is s1  # same object, no version bump


def test_heartbeat_updates_sessions_and_pet() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(s, _hb(at=2, total=4, running=3, waiting=0, msg="busy"))
    assert s.sessions.running == 3
    assert s.pet.state == "busy"


def test_heartbeat_with_prompt_triggers_attention() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(
        s,
        _hb(
            at=2,
            total=1,
            running=1,
            waiting=1,
            prompt_id="req_1",
            prompt_tool="Bash",
            prompt_hint="ls",
        ),
    )
    assert s.pet.state == "attention"
    assert s.prompt is not None
    assert s.prompt.id == "req_1"
    assert s.prompt.decidedBy is None


def test_same_prompt_id_keeps_decided_by() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(s, _hb(at=2, running=1, waiting=1, prompt_id="req_1", prompt_tool="Bash"))
    s = reduce(
        s,
        ClientDecide(at=3, client_id="c1", prompt_id="req_1", decision="once"),
    )
    assert s.prompt is not None
    assert s.prompt.decidedBy is not None
    # Another heartbeat still carrying the same prompt must NOT wipe
    # decidedBy (invariant 3: decision persists until prompt disappears
    # upstream).
    s2 = reduce(s, _hb(at=4, running=1, waiting=1, prompt_id="req_1", prompt_tool="Bash"))
    assert s2.prompt is not None
    assert s2.prompt.decidedBy is not None


def test_prompt_clears_when_heartbeat_drops_it() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(s, _hb(at=2, running=1, waiting=1, prompt_id="req_1"))
    s = reduce(s, _hb(at=3, running=1, waiting=0))
    assert s.prompt is None
    assert s.pet.state == "idle"


def test_disconnect_flips_desktop_and_sleep() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(s, _hb(at=2, running=5, waiting=0))
    assert s.pet.state == "busy"
    s = reduce(s, BleDisconnected(at=3))
    assert s.desktop.status == "disconnected"
    assert s.pet.state == "sleep"


def test_stale_tick_only_fires_after_threshold() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1_000))
    s = reduce(s, _hb(at=1_000))
    s_before = reduce(s, StaleTick(at=1_000 + 5_000))
    assert s_before.desktop.status == "connected"
    s_after = reduce(s, StaleTick(at=1_000 + 40_000))
    assert s_after.desktop.status == "stale"


def test_client_decide_without_prompt_is_noop() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s2 = reduce(
        s,
        ClientDecide(at=2, client_id="c1", prompt_id="req_1", decision="once"),
    )
    assert s2 is s


def test_client_decide_mismatched_id_is_noop() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(s, _hb(at=2, running=1, waiting=1, prompt_id="req_1"))
    s2 = reduce(
        s,
        ClientDecide(at=3, client_id="c1", prompt_id="WRONG", decision="deny"),
    )
    assert s2 is s


def test_second_decide_does_not_overwrite_first() -> None:
    s = reduce(INITIAL_STATE, BleConnected(at=1))
    s = reduce(s, _hb(at=2, running=1, waiting=1, prompt_id="req_1"))
    s = reduce(s, ClientDecide(at=3, client_id="c1", prompt_id="req_1", decision="once"))
    s2 = reduce(
        s,
        ClientDecide(at=4, client_id="c2", prompt_id="req_1", decision="deny"),
    )
    assert s2 is s


def test_owner_set_bumps_only_on_change() -> None:
    s1 = reduce(INITIAL_STATE, OwnerSet(at=1, name="Felix"))
    assert s1.owner == "Felix"
    s2 = reduce(s1, OwnerSet(at=2, name="Felix"))
    assert s2 is s1


def test_time_sync_marks_connected() -> None:
    s = reduce(INITIAL_STATE, TimeSync(at=1, epoch_s=1_000, tz_offset_s=0))
    assert s.desktop.status == "connected"
