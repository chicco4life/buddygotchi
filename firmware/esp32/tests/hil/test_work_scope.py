"""Persistent scope uses the real parser and leaves dashboard/attention intact."""
import time
import pytest
from test_usb import stick, clean, frame, state, wait_state

ROWS = [dict(source="codex", working=5, idle=1),
        dict(source="claude-code", working=1, idle=0)]


def test_scope_persists_with_counts_and_omission_clears(stick):
    text = "Boop polish and shop website updates"
    frame(stick, state="working", agents=ROWS, scope=text)
    wait_state(stick, scope=text, layer="face", workingCount=6, idleCount=1)
    time.sleep(4.5)
    assert state(stick)["scope"] == text
    frame(stick, state="working", agents=ROWS)
    wait_state(stick, scope="", layer="face")


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
    wait_state(stick, layer="face", scope=text)


def test_scope_yields_to_thread_pages_and_completion(stick):
    from test_usb import press
    fields = dict(state="working", agents=ROWS, scope="App and website polish",
                  threads=[[0, 1, "Fix layout"]], threadTotal=1)
    frame(stick, **fields)
    press(stick)
    wait_state(stick, layer="threads")
    press(stick)
    wait_state(stick, layer="face", scope="App and website polish")
    frame(stick, **fields, recent=[[990, 0, "Fix layout"]],
          notice=dict(id=990, count=1, age=0, left=5000, cheer="hop"))
    wait_state(stick, layer="completion", scope="App and website polish")
