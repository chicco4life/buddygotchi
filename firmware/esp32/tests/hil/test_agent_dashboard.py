"""Count-board lifecycle and atomic wire validation on the real display."""
import time
import pytest
from test_usb import stick, clean, frame, state, wait_state, press

ROWS = [dict(source="codex", working=2, idle=1),
        dict(source="claude-code", working=1, idle=0)]


def test_mixed_persists_and_exits(stick):
    frame(stick, state="working", agents=ROWS)
    wait_state(stick, dashboard=True, workingCount=3, idleCount=1, layer="dashboard")
    time.sleep(10.5)
    assert state(stick)["layer"] == "dashboard"
    frame(stick, state="working", agents=[dict(source="codex", working=4, idle=0)])
    wait_state(stick, dashboard=False, workingCount=4, idleCount=0, layer="face")
    frame(stick, agents=[dict(source="codex", working=0, idle=4)])
    wait_state(stick, dashboard=False, idleCount=4, creature="idle")
    press(stick)
    wait_state(stick, layer="overlay")  # affection, not dashboard navigation


def test_attention_and_omission(stick):
    frame(stick, state="needsYou", agents=ROWS,
          card=dict(id="dashboard-attention", tool="Bash", gloss="Run tests", n=1, of=1))
    wait_state(stick, dashboard=False, layer="card")
    frame(stick, state="working", agents=ROWS)
    wait_state(stick, dashboard=True)
    frame(stick, state="working")
    wait_state(stick, dashboard=False, workingCount=0, idleCount=0)


@pytest.mark.parametrize("rows", [
    [dict(source="codex", working=-1, idle=1)],
    [dict(source="codex", working=1, idle=100)],
    [dict(source="codex", working=True, idle=1)],
    [dict(source="codex", working=1)],
    [dict(source="unknown", working=1, idle=1)],
    [ROWS[0], ROWS[0]],
    ROWS * 3,
    "bad",
])
def test_bad_counts_preserve_last_frame(stick, rows):
    frame(stick, state="working", agents=ROWS)
    before = state(stick)
    frame(stick, agents=rows)
    after = state(stick)
    assert after["badFrames"] == before["badFrames"] + 1
    assert after["workingCount"] == 3
    assert after["idleCount"] == 1
    assert after["creature"] == "working"


def test_dashboard_labels_survive_repeated_animation_frames(stick):
    from test_usb import screenshot, clock
    frame(stick, state="working", agents=ROWS)
    time.sleep(0.8)
    now = state(stick)["now"]
    clock(stick, now + 600)
    a = screenshot(stick)
    clock(stick, now + 1800)
    b = screenshot(stick)
    # The buddy moves above y=70; the board below it must stay unchanged.
    assert a[70*456*2:] == b[70*456*2:]
    for x, y, w, h in [(200, 70, 110, 24), (20, 98, 110, 24),
                        (235, 98, 40, 24), (355, 141, 40, 24)]:
        lit = sum(a[(yy*456+xx)*2:(yy*456+xx)*2+2] != b"\0\0"
                  for yy in range(y, y+h) for xx in range(x, x+w))
        assert lit > 10, (x, y, lit)


def test_dashboard_board_is_static_through_full_gesture_loop(stick):
    from test_usb import screenshot, clock
    def capture():
        # USB dumps can lose a chunk. Retry only integrity failures, never
        # a valid image whose board pixels differ.
        for attempt in range(3):
            try:
                return screenshot(stick)
            except AssertionError:
                if attempt == 2:
                    raise
                time.sleep(0.1)
    reference = None
    for phase in [0,650,1250,1950,3000,3500,4830]:
        clock(stick, "clear")
        frame(stick, state="working", agents=ROWS)
        time.sleep(0.65)
        info = state(stick)
        origin = info["now"] - info["dashboardAge"]
        clock(stick, origin + (info["dashboardAge"]//5600+1)*5600 + phase)
        board = capture()[70*456*2:]
        if reference is None:
            reference = board
        else:
            assert board == reference, f"dashboard labels changed at phase {phase}"
