"""Interruptions and departures on the live USB-only presentation integrator."""
import time
import pytest
from test_usb import stick, clean, frame, state, wait_state, clock


def require_debug(stick):
    assert stick.framed_json("ping", "PONG", 3).get("usbOnly"), "Use the USB-only image for pose telemetry"


def settle(stick, offset):
    stick.framed_json(f"clock settle {offset}", "CLOCK", 3)
    time.sleep(0.08)


def test_interrupted_dance_eases_head_back_to_rest(stick):
    require_debug(stick)
    frame(stick, state="done", cheer="dance")
    settle(stick, 1500)  # 1.5 Hz sway at its positive peak
    assert state(stick)["poseTilt"] > 0.24
    clock(stick, "clear")
    frame(stick, state="idle")
    after = state(stick)
    assert 0.015 < after["poseTilt"] < 0.24, after
    time.sleep(0.5)
    assert abs(state(stick)["poseTilt"]) < 0.01


def test_interrupted_greeting_retracts_without_flipping_arm(stick):
    require_debug(stick)
    frame(stick, state="idle", overlay="greet", greetLevel=3)
    settle(stick, 500)
    before = state(stick)
    assert before["armR"] > 0.8 and before["armAngleR"] > 2
    clock(stick, "clear")
    frame(stick, state="idle")
    after = state(stick)
    assert 0.03 < after["armR"] < before["armR"], after
    assert after["armAngleR"] > 2, after
    time.sleep(0.6)
    assert state(stick)["armR"] < 0.01


def test_card_departure_is_monotonic_without_spring_undershoot(stick):
    require_debug(stick)
    frame(stick, state="needsYou", card=dict(id="ease", tool="Question", gloss="Choose", n=1, of=1))
    settle(stick, 700)
    assert state(stick)["cardProgress"] == 1
    clock(stick, "clear")
    frame(stick, state="idle")
    samples = []
    departing = []
    for _ in range(15):
        current = state(stick)
        samples.append(current["cardProgress"])
        departing.append(current["cardDeparting"])
        time.sleep(0.02)
    assert all(0 <= value <= 1 for value in samples), samples
    assert all(b <= a for a, b in zip(samples, samples[1:])), samples
    assert samples[-1] < 0.01, samples
    assert departing[0], departing
    # The position sample can already be below 1% while the final subpixel
    # tail is still retracting. Verify eventual removal within a real deadline,
    # independently of how many serial samples fit in the window.
    wait_state(stick, timeout=1, cardDeparting=False)


@pytest.mark.parametrize("cover,layer", [
    (dict(card=dict(kind="update", text="Updating")), "system"),
    (dict(bubble="hello"), "bubble"),
    (dict(state="asleep"), "face"),
])
def test_departing_footer_yields_to_cover(stick, cover, layer):
    require_debug(stick)
    frame(stick, state="needsYou", card=dict(id="covered", tool="Question", gloss="Choose"))
    settle(stick, 700)
    clock(stick, "clear")
    frame(stick, **(dict(state="idle") | cover))
    current = state(stick)
    assert current["layer"] == layer, current
    assert not current["cardDeparting"], current


def test_system_card_cancels_completion_without_replay(stick):
    require_debug(stick)
    frame(stick, state="working")
    notice = dict(id=81001, count=1, age=0, left=5000, cheer="dance")
    recent = [[81001, 0, "Checked behavior"]]
    frame(stick, state="idle", recent=recent, notice=notice)
    wait_state(stick, layer="completion")
    frame(stick, state="idle", recent=recent, notice=notice, card=dict(kind="update", text="Updating"))
    wait_state(stick, layer="system", noticeVisible=False)
    frame(stick, state="idle", recent=recent, notice=notice)
    wait_state(stick, layer="face", noticeVisible=False)
