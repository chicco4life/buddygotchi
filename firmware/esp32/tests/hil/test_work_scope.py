"""Transient device scope retains host text without replaying it."""
import time
import pytest
from test_usb import stick, clean, frame, state, wait_state, clock

ROWS = [dict(source="codex", working=5, idle=1),
        dict(source="claude-code", working=1, idle=0)]


def test_scope_is_retained_as_data_but_never_pops_up(stick):
    base = state(stick)["now"]
    clock(stick, base)
    for index, text in enumerate(("Polishing settings", "A different summary", "")):
        frame(stick, state="working", agents=ROWS, scope=text)
        clock(stick, base + (index + 1) * 300)
        wait_state(stick, scope=text, scopeVisible=False, scopeAmount=0,
                   workingCount=6, idleCount=1)


@pytest.mark.parametrize("text", ["x" * 121, "한" * 41, 123, {"text": "bad"}])
def test_invalid_scope_rejects_atomically(stick, text):
    frame(stick, state="working", scope="Boop", agents=ROWS)
    before = state(stick)
    frame(stick, scope=text)
    after = state(stick)
    assert after["badFrames"] == before["badFrames"] + 1
    assert after["scope"] == "Boop"
    assert after["workingCount"] == 6


def test_scope_does_not_replace_attention_or_bubble(stick):
    text = "Boop과 웹사이트를 다듬고 있어요"
    frame(stick, state="needsYou", scope=text, agents=ROWS,
          card=dict(id="scope-attention", tool="Question", gloss="Check editor", n=1, of=1))
    wait_state(stick, layer="card")
    frame(stick, state="idle", scope=text, bubble="Hello")
    wait_state(stick, layer="bubble")
    frame(stick, state="working", scope=text)
    wait_state(stick, layer="face", scope=text, scopeVisible=False)


def test_scope_yields_to_thread_pages_and_completion(stick):
    from test_usb import press
    fields = dict(state="working", agents=ROWS, scope="App and website polish",
                  threads=[[0, 1, "Fix layout"]], threadTotal=1)
    frame(stick, **fields)
    press(stick)
    wait_state(stick, layer="threads")
    press(stick)
    wait_state(stick, layer="face", scope="App and website polish", scopeVisible=False)
    frame(stick, **fields, recent=[[990, 0, "Fix layout"]],
          notice=dict(id=990, count=1, age=0, left=5000, cheer="hop"))
    wait_state(stick, layer="completion", scope="App and website polish")


def test_scope_interrupted_by_request_never_returns(stick):
    text = "Checking the build"
    frame(stick, state="working", scope=text)
    wait_state(stick, scopeVisible=False)
    frame(stick, state="needsYou", scope=text,
          card=dict(id="scope-cutoff", tool="Question", gloss="Check editor", n=1, of=1))
    wait_state(stick, layer="card", scopeVisible=False)
    frame(stick, state="working", scope=text)
    wait_state(stick, layer="face", scopeVisible=False)


def test_hint_pixels_stay_fixed_through_phrase_fades(stick):
    from test_usb import screenshot
    base = state(stick)["now"]
    clock(stick, base)
    frame(stick, state="working", agents=ROWS, scope="Device spacing check")
    images = []
    for age in (125, 600, 3800, 4000):
        clock(stick, base + age)
        images.append(screenshot(stick)[-456*35*2:])
    assert any(images[0])
    assert all(image == images[0] for image in images[1:])
