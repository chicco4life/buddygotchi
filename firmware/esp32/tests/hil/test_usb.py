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


# Press once and wait for BOTH the expected marker and the synthetic
# release. Sending the next `press` for the same button before the previous
# one releases just extends the still-held press (schedulePress overwrites
# releaseAt), so no new edge fires — the up-marker join makes each press a
# complete, observable click before the test moves on.
def press_expect(stick, which, marker, timeout=2):
    stick.write_line(f"press {which} 120")
    up = f"<<PRESS {which} up>>".encode()
    buf, _ = stick.read_until(lambda b: marker in b and up in b, timeout)
    return buf


# Recover from a previous test that died with the menu open — REJECT walks
# any screen back to closed.
def ensure_menu_closed(stick):
    for _ in range(3):
        if state(stick).get("menu") == "closed":
            return
        stick.write_line("press b 120")
        stick.read_until(lambda b: b"<<PRESS b up>>" in b, 2)
    wait_state(stick, menu="closed")


def test_menu_open_navigate_close(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    press_expect(stick, "m", b"<<MENU screen=root item=character>>")
    press_expect(stick, "m", b"<<MENU screen=root item=sound>>")
    wait_state(stick, menu="root")
    press_expect(stick, "b", b"<<MENU close>>")
    tail = stick.drain_until_quiet(max_wait=0.3)
    assert b'"cmd":"permission"' not in tail
    wait_state(stick, menu="closed")


def test_menu_character_preview_reverts_on_back(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    before = state(stick)["speciesLocal"]
    stick.drain_until_quiet(max_wait=0.2)

    press_expect(stick, "m", b"<<MENU screen=root item=character>>")
    press_expect(stick, "a", b"<<MENU screen=character>>")
    press_expect(stick, "m", b"<<MENU species=")
    got = wait_state(stick, menu="character")
    assert got["speciesLocal"] != before
    press_expect(stick, "b", b"<<MENU screen=root item=character>>")
    wait_state(stick, menu="root", speciesLocal=before)
    press_expect(stick, "b", b"<<MENU close>>")


def test_prompt_takes_over_menu(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    press_expect(stick, "m", b"<<MENU screen=root item=character>>")
    stick.write_line("mockprompt")
    stick.read_until(
        lambda b: b"<<MENU close>>" in b and b"<<BTN mockprompt armed>>" in b, 2
    )
    wait_state(stick, menu="closed", promptId="DEBUG")
    stick.write_line("press a 120")
    buf, _ = stick.read_until(lambda b: b'"decision":"allow"' in b, 3)
    assert b'"cmd":"permission"' in buf


def test_fresh_prompt_arming_delay_swallows_early_press(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    # "fresh" keeps the real arrival time, so this press lands inside the
    # 600ms arming window and must be swallowed (no permission, no boop-
    # approval confusion), leaving the prompt still answerable.
    stick.write_line("mockprompt fresh")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.write_line("press a 120")
    buf, _ = stick.read_until(lambda b: b"<<PRESS a up>>" in b, 2)
    tail = stick.drain_until_quiet(max_wait=0.3)
    assert b'"cmd":"permission"' not in buf + tail
    wait_state(stick, promptId="DEBUG", responseSent=False)

    time.sleep(0.5)  # comfortably past the arming window by now
    stick.write_line("press a 120")
    buf, _ = stick.read_until(lambda b: b'"decision":"allow"' in b, 3)
    assert b'"cmd":"permission"' in buf


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
    buf, parsed = stick.read_until(buddyctl.parse_screenshot, 45)
    begin, body_start, _body_end, end = parsed
    w = int(begin.group(1))
    h = int(begin.group(2))
    body = re.sub(rb"\s+", b"", buf[body_start : body_start + end.start()])
    raw = base64.b64decode(body, validate=True)
    assert len(raw) == w * h * 2
    assert end.group(1) is not None
    assert int(end.group(1)) == len(raw)
    assert int(end.group(2), 16) == (zlib.crc32(raw) & 0xFFFFFFFF)


def test_boop_emits_upstream_frame(stick):
    """A boop outside a prompt must flash the heart locally AND tell the
    desktop ({"cmd":"boop"}), so the Mac blob reacts in kind."""
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "promptId": ""})
    if state(stick).get("screenOff"):
        # A wake-press never doubles as an action — burn one.
        stick.write_line("press a 120")
        stick.read_until(lambda b: b"<<PRESS a up>>" in b, 2)
    stick.write_line("press a 120")
    buf, _ = stick.read_until(lambda b: b'"cmd":"boop"' in b and b"<<PRESS a up>>" in b, 3)
    assert find_json_line(buf, cmd="boop")
    # Both together: a state dump issued the same loop iteration as the
    # release can still carry the previous iteration's persona.
    wait_state(stick, boop=True, activePersona="P_HEART")


def test_imu_face_down_naps_and_face_up_wakes(stick):
    """Face-down 2s → nap (screen off); face-up 700ms → wake. Injection
    drives the same detector the real accelerometer feeds."""
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "promptId": ""})
    stick.write_line("imu set 0 0 -1.0")
    stick.read_until(lambda b: b"<<IMU inject" in b, 2)
    time.sleep(2.3)   # entry debounce is 2s
    wait_state(stick, napping=True, screenOff=True)

    stick.write_line("imu set 0 0 1.0")
    stick.read_until(lambda b: b"<<IMU inject" in b, 2)
    time.sleep(0.9)   # exit debounce is 700ms
    wait_state(stick, napping=False, screenOff=False)
    stick.write_line("imu clear")
    stick.read_until(lambda b: b"<<IMU inject cleared>>" in b, 2)


def test_imu_shake_goes_dizzy_and_recovers(stick):
    """A sustained >1g deviation must cross the shake threshold within a
    few 50ms samples and wear the dizzy face for ~3s."""
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "promptId": ""})
    stick.write_line("imu set 0 0 3.0")
    stick.read_until(lambda b: b"<<IMU inject" in b, 2)
    st = wait_state(stick, dizzy=True)
    assert st["activePersona"] == "P_DIZZY"

    stick.write_line("imu set 0 0 1.0")   # back to rest — stop re-triggering
    stick.read_until(lambda b: b"<<IMU inject" in b, 2)
    time.sleep(3.2)   # dizzy window is 3s
    wait_state(stick, dizzy=False)
    stick.write_line("imu clear")
    stick.read_until(lambda b: b"<<IMU inject cleared>>" in b, 2)


def test_hold_from_dark_screen_arms_power_down_ladder(stick):
    """Regression (found on hardware): a long hold that STARTS on a dark
    screen must still arm the power-down ladder. The wake-press guard may
    only eat taps — an overnight pet's screen is off, and that's exactly
    when you want the 4s hold to work."""
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "promptId": ""})
    wait_state(stick, screenOff=False)
    # Stage 1 from a lit screen: sleeps the panel (existing behavior).
    stick.write_line("press a 1600")
    stick.read_until(lambda b: b"<<PRESS a up>>" in b, 3)
    wait_state(stick, screenOff=True, ladder=False)   # flag resets on release
    # Hold starting from OFF: wakes the panel, does NOT re-sleep it, but
    # the ladder must arm mid-hold so 4s would power down.
    stick.write_line("press a 2500")
    stick.read_until(lambda b: b"<<PRESS a down>>" in b, 2)
    time.sleep(2.0)
    st = state(stick)
    assert st["screenOff"] is False, "hold-from-off should leave the panel lit"
    assert st["ladder"] is True, "ladder must arm even when the hold began as a wake-press"
    stick.read_until(lambda b: b"<<PRESS a up>>" in b, 2)
    wait_state(stick, ladder=False)


def test_button_press_ends_nap(stick):
    """A physical press must end a nap immediately — it's the escape hatch
    if the accelerometer wedges while the nap gate holds the screen dark
    and touch is ignored."""
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle", "promptId": ""})
    stick.write_line("imu set 0 0 -1.0")
    stick.read_until(lambda b: b"<<IMU inject" in b, 2)
    time.sleep(2.3)
    wait_state(stick, napping=True, screenOff=True)
    # Sensor still says face-down; the press must win anyway.
    stick.write_line("press a 120")
    stick.read_until(lambda b: b"<<PRESS a up>>" in b, 2)
    wait_state(stick, napping=False, screenOff=False)
    stick.write_line("imu clear")   # before the 2s debounce re-naps
    stick.read_until(lambda b: b"<<IMU inject cleared>>" in b, 2)
    wait_state(stick, napping=False)


def test_imu_shake_never_interrupts_prompt(stick):
    """Doctrine: motion is display-only. While a prompt is pending the
    shake detector must not fire — the approval card owns the screen."""
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.write_line("imu set 0 0 3.0")
    stick.read_until(lambda b: b"<<IMU inject" in b, 2)
    time.sleep(0.6)
    st = state(stick)
    assert st["dizzy"] is False
    assert st["activePersona"] != "P_DIZZY"
    stick.write_line("imu clear")
    stick.read_until(lambda b: b"<<IMU inject cleared>>" in b, 2)
    # Answer the mock prompt so later tests start clean.
    stick.write_line("btn b")
    stick.read_until(lambda b: b"<<BTN b deny sent>>" in b, 2)


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


def ping_retry(stick, deadline_s: float) -> dict:
    """Ping until the device answers (used across the sleep/restart gap)."""
    deadline = time.monotonic() + deadline_s
    last_exc: Exception | None = None
    while time.monotonic() < deadline:
        try:
            return stick.framed_json("ping", "PONG", 2)
        except Exception as exc:
            last_exc = exc
            time.sleep(0.5)
    pytest.fail(f"device did not answer ping within {deadline_s}s: {last_exc}")


# Deliberately the last test in the file: the device disappears off the
# bus for several seconds and other tests shouldn't race the re-enumeration.
@pytest.mark.slow
def test_deepsleep_roundtrip(stick):
    """'deepsleep 4000' must power down and come back on the timer wake
    with a clean boot — same code path as the 4s physical BOOP hold
    (which wakes on the button instead). No panic, no safe mode."""
    baseline = stick.framed_json("ping", "PONG", 3)
    stick.write_line("deepsleep 4000")
    stick.read_until(lambda b: b"<<DEEPSLEEP ok" in b, 3)
    time.sleep(9.0)   # night-night beat + 4s sleep + boot splash
    pong = ping_retry(stick, 30)
    assert pong["up"] < 60_000, "device did not actually restart"
    assert pong["panics"] == baseline["panics"], "sleep path panicked"
    assert pong["safe"] == 0
