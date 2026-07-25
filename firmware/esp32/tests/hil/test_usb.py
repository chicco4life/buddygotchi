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


@pytest.fixture(scope="session")
def landscape(stick):
    """Skip on the portrait M5.

    The face-first redesign (PEBBLE-UX) is guarded on HAL_LANDSCAPE — the M5
    keeps its permanent HUD and stays the regression rig, so glance cards,
    moods, and orbs simply don't exist there.
    """
    board = stick.framed_json("state", "STATE", 3).get("board", "?")
    if board != "ws-amoled164":
        pytest.skip(f"landscape-only behavior; attached board is {board}")
    return board


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
def press_expect(stick, which, marker, timeout=2, ms=120):
    stick.write_line(f"press {which} {ms}")
    up = f"<<PRESS {which} up>>".encode()
    buf, _ = stick.read_until(lambda b: marker in b and up in b, max(timeout, ms / 1000 + 1.5))
    return buf


# "Look" is two verbs on the landscape board (PEBBLE-UX §5): a tap summons
# the glance card, a hold opens the menu carousel. Opening the menu
# therefore needs a press past BTN_M_LONG_MS (500ms); once it's open, MENU
# reverts to its old meaning (next item) and plain taps are correct again.
MENU_HOLD_MS = 700


def menu_open_expect(stick, marker, timeout=3):
    return press_expect(stick, "m", marker, timeout=timeout, ms=MENU_HOLD_MS)


# Recover from a previous test that died with the menu open — REJECT walks
# any screen back to closed. It also dismisses a stray glance card, which
# is the other thing "look" can leave on screen.
def ensure_menu_closed(stick):
    for _ in range(4):
        snap = state(stick)
        if snap.get("menu") == "closed" and snap.get("glance") in ("closed", "closing"):
            return
        stick.write_line("press b 120")
        stick.read_until(lambda b: b"<<PRESS b up>>" in b, 2)
    wait_state(stick, menu="closed")


def test_glance_card_tap_pages_and_dismisses(stick, landscape):
    """A look-tap summons the glance card; tapping pages through it.

    This is the summoned tier (PEBBLE-UX §6): the resting screen carries no
    status text at all, so the card is the only place the literal facts
    live. Paging past the last page puts it away, which is how you dismiss
    without reaching for the other button.
    """
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    press_expect(stick, "m", b"<<GLANCE open page=1>>")
    assert state(stick)["glance"] == "page1"
    press_expect(stick, "m", b"<<GLANCE page=2>>")
    assert state(stick)["glance"] == "page2"
    # Past the last page the card closes rather than wrapping.
    press_expect(stick, "m", b"<<GLANCE close (paged past end)>>")
    assert state(stick)["glance"] in ("closed", "closing")
    # The card must never have spoken for the user.
    assert b'"cmd":"permission"' not in stick.drain_until_quiet(max_wait=0.3)


def test_glance_card_dismissed_by_reject_and_by_prompt(stick, landscape):
    """REJECT puts the card away, and a prompt takes the screen instantly.

    Doctrine #3: the demanded tier outranks the summoned tier. A card still
    on screen when an approval arrives would be covering the one thing the
    human has to answer.
    """
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    press_expect(stick, "m", b"<<GLANCE open page=1>>")
    press_expect(stick, "b", b"<<GLANCE close>>")
    assert state(stick)["glance"] in ("closed", "closing")

    press_expect(stick, "m", b"<<GLANCE open page=1>>")
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    got = wait_state(stick, promptId="DEBUG")
    assert got["glance"] in ("closed", "closing"), got["glance"]
    # Leave the prompt answered so the next test starts clean.
    stick.write_line("press a 120")
    stick.read_until(lambda b: b'"decision":"allow"' in b, 3)


def test_glance_card_auto_dismisses(stick, landscape):
    """The card is summoned, not sticky: 4s of no input and it slides away."""
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    press_expect(stick, "m", b"<<GLANCE open page=1>>")
    stick.read_until(lambda b: b"<<GLANCE close (timeout)>>" in b, 8)
    assert state(stick)["glance"] in ("closed", "closing")


def test_menu_open_navigate_close(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle"})
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", promptId="", menu="closed")
    stick.drain_until_quiet(max_wait=0.2)

    menu_open_expect(stick, b"<<MENU screen=root item=character>>")
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

    menu_open_expect(stick, b"<<MENU screen=root item=character>>")
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

    menu_open_expect(stick, b"<<MENU screen=root item=character>>")
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


def corner_pixel(stick, timeout=45):
    """Top-left pixel of the sprite, as RGB888.

    The mood system's whole job is the overall luminance of the field, so a
    single corner pixel is a precise and very cheap oracle for it: black in
    Night, the exact cream in Lantern, mid-transition during a bloom.
    """
    stick.write_line("screenshot")
    buf, parsed = stick.read_until(buddyctl.parse_screenshot, timeout)
    begin, body_start, _body_end, end = parsed
    body = re.sub(rb"\s+", b"", buf[body_start : body_start + end.start()])
    raw = base64.b64decode(body, validate=True)
    # Reuse the tool's own converter rather than rounding by hand: a
    # different rounding rule here reports 172 where buddyctl reports 173,
    # and then the test and every screenshot on disk disagree about what
    # the panel showed.
    return tuple(buddyctl.rgb565le_to_rgb888(raw[:2], 1, 1)[:3])


def clear_prompt(stick):
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "idle",
                      "promptId": "", "promptApproval": False})
    wait_state(stick, promptId="")


def test_mood_night_field_is_true_black(stick, landscape):
    """At rest the field is pure black — doctrine #1 and #2.

    Black pixels are off on this AMOLED, so this is simultaneously the look,
    the burn-in strategy, and the baseline the alert channel is measured
    against.
    """
    clear_prompt(stick)
    ensure_menu_closed(stick)
    wait_state(stick, pet="idle", mood="night")
    assert corner_pixel(stick) == (0, 0, 0)


def test_mood_lantern_inverts_the_field_for_approvals(stick, landscape):
    """A pending approval flips the whole panel dark->light (§2.1).

    This is the one genuine luminance inversion in the product, which is
    what makes it unmissable in peripheral vision. The exact tone matters:
    FIELD_LANTERN is an RGB332 lattice point, so it must land with zero
    quantization error rather than drifting to a neighbouring cream.
    """
    clear_prompt(stick)
    send_json(stick, {"total": 2, "running": 1, "waiting": 1, "pet": "attention",
                      "promptId": "req_mood", "promptTool": "Bash",
                      "promptHint": "git push --force", "promptSource": "claude-code",
                      "promptApproval": True})
    wait_state(stick, promptId="req_mood", mood="lantern")
    # `mood` flips when the bloom starts; the light front needs ~350ms to
    # pass the screen corners, and moodLit only reports once it has.
    time.sleep(1.2)
    got = state(stick)
    assert got["moodLit"] == 100, got["moodLit"]
    assert got["moodInk"] == 100, got["moodInk"]
    # The field breathes +-6%, but RGB332 is coarse enough to absorb that:
    # the whole breath cycle quantizes to the same lattice point, which is
    # what makes an exact-tone assertion stable here.
    assert corner_pixel(stick) == (255, 219, 173)   # #FFDBAD
    # Answer it so the next test doesn't inherit a lit field.
    stick.write_line("press a 120")
    stick.read_until(lambda b: b'"decision":"allow"' in b, 3)
    clear_prompt(stick)


def test_mood_ember_for_error(stick, landscape):
    """Errors get a dim warm field, not a bright one.

    Ember says "something's off"; the lantern is reserved for "act now".
    Spending light on a state the human can't immediately resolve would
    cost the lantern its meaning (§2.1).
    """
    clear_prompt(stick)
    send_json(stick, {"total": 1, "running": 0, "waiting": 0, "pet": "error"})
    wait_state(stick, pet="error", mood="ember")
    # `mood` flips as soon as the crossfade starts; ember takes ~500ms to
    # reach full (errors are not startling). Sampling early caught it at
    # (32,0,0) — one lattice level in, not the settled tone.
    time.sleep(1.2)
    r, g, b = corner_pixel(stick)
    assert r > 0 and g > 0, (r, g, b)          # lifted off black
    assert r < 140 and b < 60, (r, g, b)       # but nowhere near lantern
    clear_prompt(stick)


def test_mood_returns_to_night_after_a_decision(stick, landscape):
    """Approving snuffs the field back out — the light must not linger."""
    clear_prompt(stick)
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    wait_state(stick, mood="lantern")
    stick.write_line("press a 120")
    stick.read_until(lambda b: b'"decision":"allow"' in b, 3)
    # Snuff is ~250ms; give it room but require it to actually finish.
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if state(stick)["mood"] == "night":
            break
        time.sleep(0.2)
    else:
        pytest.fail("field never snuffed back to night")
    assert corner_pixel(stick) == (0, 0, 0)
    clear_prompt(stick)


def test_approval_card_rises_and_leaves_with_the_decision(stick, landscape):
    """The card is up exactly while the decision is owed (§7).

    The face never leaves the screen — the card rises alongside it rather
    than replacing it — and both the card and the lantern must clear once
    the human has answered, or the device keeps shouting about a question
    that's already been settled.
    """
    clear_prompt(stick)
    send_json(stick, {"total": 2, "running": 1, "waiting": 1, "pet": "attention",
                      "promptId": "req_card", "promptTool": "Bash",
                      "promptHint": "git push --force origin main",
                      "promptSource": "claude-code", "promptApproval": True})
    wait_state(stick, promptId="req_card", card=True, mood="lantern")

    # The bloom finishes (~350ms) before the 600ms arming window does, so
    # wait_state can return while a press would still — correctly — be
    # swallowed. Wait the window out rather than racing it.
    time.sleep(0.8)
    stick.write_line("press a 120")
    stick.read_until(lambda b: b'"decision":"allow"' in b, 3)
    # Card pops (~150ms) ahead of the field's snuff (~250ms).
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        snap = state(stick)
        if not snap["card"] and snap["mood"] == "night":
            break
        time.sleep(0.2)
    else:
        pytest.fail(f"card/field never cleared after approve; last={snap}")
    clear_prompt(stick)


def test_approval_card_has_no_wait_counter(stick, landscape):
    """§14: the numeric "waiting Ns" counter is gone from this board.

    Urgency is the field warming and its breath quickening (§7) — light and
    motion, which read peripherally far better than a stopwatch nobody is
    looking at. This asserts the seconds text never appears on the panel.
    """
    clear_prompt(stick)
    send_json(stick, {"total": 1, "running": 0, "waiting": 1, "pet": "attention",
                      "promptId": "req_nc", "promptTool": "Bash",
                      "promptHint": "sleep 30", "promptSource": "claude-code",
                      "promptApproval": True})
    wait_state(stick, promptId="req_nc", card=True)
    time.sleep(12)          # well past the 10s escalation threshold
    got = state(stick)
    assert got["mood"] == "lantern"
    # The field escalated instead of counting.
    r, g, b = corner_pixel(stick)
    assert (r, g, b) != (255, 219, 173), "field never warmed past base lantern"
    assert r == 255 and g < 219, (r, g, b)
    stick.write_line("press b 120")
    stick.read_until(lambda b: b'"decision":"deny"' in b, 3)
    clear_prompt(stick)


def imu(stick):
    return stick.framed_json("imu", "IMU", 4)


def test_pickup_starts_dangle_mode(stick, landscape):
    """A sustained calm tilt reads as being picked up (§10.2).

    A unit-magnitude rotation leaves the shake accumulator at rest, which is
    exactly what separates a lift from a shake: both move the vector, but
    only a lift moves it and KEEPS it moved without energy.
    """
    clear_prompt(stick)
    stick.write_line("imu clear")
    time.sleep(0.6)
    assert imu(stick)["dangling"] is False

    stick.write_line("imu set 0.70 0.10 0.70")
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        got = imu(stick)
        if got["dangling"]:
            break
        time.sleep(0.15)
    else:
        pytest.fail(f"never entered dangle; last={got}")
    assert got["tilt"] > 0.38, got
    assert got["shake"] < 1.2, got     # calm, not a shake

    # Holding steady ends it after ~1s — the injected sample stops changing,
    # which is the same signal as a hand going still.
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if not imu(stick)["dangling"]:
            break
        time.sleep(0.2)
    else:
        pytest.fail("dangle never ended on stillness")
    stick.write_line("imu clear")


def test_shake_does_not_start_dangle(stick, landscape):
    """A shake must read as dizzy, never as a pick-up.

    They share a sample stream and a lift is easy to confuse with the start
    of a shake, so dangle is explicitly gated on the shake accumulator being
    below threshold.
    """
    clear_prompt(stick)
    stick.write_line("imu clear")
    time.sleep(0.6)
    # Alternating large magnitudes: high energy, no sustained orientation.
    for _ in range(8):
        stick.write_line("imu set 2.5 0 0")
        time.sleep(0.08)
        stick.write_line("imu set -2.5 0 0")
        time.sleep(0.08)
    got = imu(stick)
    assert got["dangling"] is False, got
    stick.write_line("imu clear")
    time.sleep(0.5)


def test_prompt_suppresses_dangle(stick, landscape):
    """Affection and play may never delay a decision the human owes."""
    clear_prompt(stick)
    stick.write_line("imu clear")
    time.sleep(0.6)
    stick.write_line("mockprompt")
    stick.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
    stick.write_line("imu set 0.70 0.10 0.70")
    time.sleep(1.2)
    assert imu(stick)["dangling"] is False
    stick.write_line("imu clear")
    stick.write_line("press a 120")
    stick.read_until(lambda b: b'"decision":"allow"' in b, 3)
    clear_prompt(stick)


def test_touch_reports_a_contact_point(stick, landscape):
    """Touch now carries coordinates, which is what gaze tracking needs.

    Synthetic contact drives the same path a finger does, so this covers
    the plumbing (command -> point -> sprite coordinates). It deliberately
    does NOT cover the FT3168's own coordinate mapping: that inverts the
    panel rotation and can only be confirmed by touching a known spot on
    real glass.
    """
    clear_prompt(stick)
    stick.write_line("touch up")
    stick.read_until(lambda b: b"<<TOUCH up>>" in b, 2)
    got = stick.framed_json("touch", "TOUCH", 3)
    assert got["point"] is False, got

    stick.write_line("touch down 30 140")
    stick.read_until(lambda b: b"<<TOUCH down 30 140>>" in b, 2)
    got = stick.framed_json("touch", "TOUCH", 3)
    assert got["point"] is True and got["x"] == 30 and got["y"] == 140, got

    stick.write_line("touch down 426 140")
    stick.read_until(lambda b: b"<<TOUCH down 426 140>>" in b, 2)
    got = stick.framed_json("touch", "TOUCH", 3)
    assert got["x"] == 426, got

    stick.write_line("touch up")
    stick.read_until(lambda b: b"<<TOUCH up>>" in b, 2)
    assert stick.framed_json("touch", "TOUCH", 3)["point"] is False


def test_touch_point_is_clamped_to_the_panel(stick, landscape):
    """Out-of-range injections clamp rather than deflecting the gaze past
    its limits or indexing off the sprite."""
    clear_prompt(stick)
    stick.write_line("touch down 9999 9999")
    stick.read_until(lambda b: b"<<TOUCH down " in b, 2)
    got = stick.framed_json("touch", "TOUCH", 3)
    assert got["x"] == 455 and got["y"] == 279, got
    stick.write_line("touch up")
    stick.read_until(lambda b: b"<<TOUCH up>>" in b, 2)


def wait_orbs(stick, want, timeout=8):
    """Orb counts settle over time — spawns stagger ~150ms apart and each
    one grows in over ~400ms, so the sky never flickers when several
    sessions start at once (§3.2)."""
    deadline = time.monotonic() + timeout
    last = {}
    while time.monotonic() < deadline:
        last = state(stick)
        if last.get("orbs") == want:
            return last
        time.sleep(0.2)
    pytest.fail(f"orbs never reached {want}; last orbs={last.get('orbs')}")


def test_orbs_track_session_counts(stick, landscape):
    """One orb per session, driven by counts already on the wire (§3.2)."""
    clear_prompt(stick)
    send_json(stick, {"total": 3, "running": 2, "waiting": 1, "pet": "busy"})
    got = wait_orbs(stick, 3)
    assert got["orbsOverflow"] == 0
    send_json(stick, {"total": 1, "running": 1, "waiting": 0, "pet": "busy"})
    wait_orbs(stick, 1)


def test_orbs_cap_at_six_and_report_overflow(stick, landscape):
    """Beyond six the sky stops growing and the excess becomes 'many'.

    Exact numbers are the glance card's job; the resting screen only carries
    how much is going on.
    """
    clear_prompt(stick)
    send_json(stick, {"total": 9, "running": 8, "waiting": 1, "pet": "busy"})
    got = wait_orbs(stick, 6)
    assert got["orbsOverflow"] == 3, got["orbsOverflow"]
    send_json(stick, {"total": 1, "running": 1, "waiting": 0, "pet": "busy"})
    got = wait_orbs(stick, 1)
    assert got["orbsOverflow"] == 0


def test_orbs_clear_when_asleep(stick, landscape):
    """A sleeping buddy isn't watching anything, so the sky goes out."""
    clear_prompt(stick)
    send_json(stick, {"total": 2, "running": 2, "waiting": 0, "pet": "busy"})
    wait_orbs(stick, 2)
    send_json(stick, {"total": 2, "running": 2, "waiting": 0, "pet": "sleep"})
    wait_orbs(stick, 0)


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
