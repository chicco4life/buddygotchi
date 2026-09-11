"""Glanceable completion and explicit thread pages on the real display."""
import pytest
from test_usb import stick, clean, frame, state, wait_state, press, clock, screenshot

ROWS = [dict(source="codex", working=2, idle=1)]
THREADS = [[0, 1, "Fix layout"], [0, 1, "Run checks"], [0, 0, "Write docs"]]

def tap(stick, x=220, y=130):
    stick.write_line(f"tap {x} {y}")
    stick.read_until(lambda b: b"<<TAP ok>>" in b, 3)


def activity(stick, **extra):
    frame(stick, state="working", agents=ROWS, threads=THREADS, threadTotal=3, **extra)

def finished(stick, ident, count=1, age=0, left=5000):
    activity(stick, recent=[[ident+count-1, 0, "Fix layout"], [ident-1, 1, "Write docs"]],
             notice=dict(id=ident, count=count, age=age, left=left, cheer="hop"))

def test_mixed_stays_working_and_tap_opens_threads(stick):
    activity(stick)
    wait_state(stick, dashboard=False, workingCount=2, layer="face")
    press(stick)
    wait_state(stick, layer="threads", threadPage=0, threadCount=3)
    press(stick)
    wait_state(stick, layer="face", threadPage=-1)

def test_completion_repeated_frames_do_not_extend_or_replay(stick):
    activity(stick)
    finished(stick, 100)
    origin=state(stick)["now"]
    wait_state(stick, layer="completion", noticeCount=1)
    clock(stick, origin+4500)
    finished(stick, 100)
    clock(stick, origin+5100)
    wait_state(stick, layer="face", noticeVisible=False)
    finished(stick, 100)
    wait_state(stick, layer="face", noticeVisible=False)

def test_overlap_hard_cap_and_priority(stick):
    activity(stick)
    finished(stick, 200)
    origin=state(stick)["now"]
    clock(stick, origin+4400)
    finished(stick, 200, count=2, age=4400, left=2000)
    wait_state(stick, layer="completion", noticeCount=2)
    clock(stick, origin+6300)
    finished(stick, 200, count=3, age=6300, left=1700)
    clock(stick, origin+8100)
    wait_state(stick, layer="face", noticeVisible=False)
    finished(stick, 300)
    frame(stick, state="needsYou", card=dict(id="ask", tool="Question", gloss="Choose", n=1, of=1))
    wait_state(stick, layer="card", noticeVisible=False)
    activity(stick)
    wait_state(stick, layer="face", noticeVisible=False)

def test_table_updates_without_interruption_and_history_pages(stick):
    activity(stick)
    press(stick)
    wait_state(stick, layer="threads")
    finished(stick, 400)
    wait_state(stick, layer="threads", recentCount=2, noticeVisible=False)
    tap(stick, 400, 255)
    wait_state(stick, layer="threads", threadPage=1)
    press(stick)
    wait_state(stick, layer="face", threadPage=-1, noticeVisible=False)

@pytest.mark.parametrize("extra", [
    dict(threads=[[0,1,"x"]]*13), dict(threads=[[0,1,"x\ny"]]), dict(threads=[[0,9,"x"]]),
    dict(threads=[[0,1,"한"*16]]), dict(threads=[[True,1,"x"]]),
    dict(recent=[[0,0,"x"]]), dict(threadTotal=1),
    dict(notice=dict(id=1,count=1,age=7900,left=2000,cheer="hop")),
])
def test_invalid_details_preserve_last_frame(stick, extra):
    activity(stick)
    before=state(stick)
    fields=dict(agents=ROWS, threads=THREADS, threadTotal=3)
    fields.update(extra)
    frame(stick, **fields)
    after=state(stick)
    assert after["badFrames"]==before["badFrames"]+1
    assert after["creature"]=="working" and after["threadCount"]==3


def test_panel_tap_exits_without_traversing_multiple_pages(stick):
    rows = [[0, 1, f"Thread {i}"] for i in range(8)]
    frame(stick, state="working", agents=ROWS, threads=rows, threadTotal=8,
          recent=[[901,0,"Recent finish"],[900,1,"Earlier finish"]])
    tap(stick)
    wait_state(stick, layer="threads", threadPage=0)
    tap(stick)
    wait_state(stick, layer="face", threadPage=-1)
    tap(stick)
    tap(stick, 400, 255)
    wait_state(stick, layer="threads", threadPage=1)
    tap(stick, 45, 250)
    wait_state(stick, layer="face", threadPage=-1)


def test_next_wraps_and_history_can_exit_directly(stick):
    activity(stick, recent=[[902,0,"Finished"]])
    tap(stick)
    tap(stick, 400, 255)
    wait_state(stick, layer="threads", threadPage=1)
    tap(stick, 400, 255)
    wait_state(stick, layer="threads", threadPage=0)
    tap(stick)
    wait_state(stick, layer="face")
    tap(stick, 200, 255)  # the removed footer has no special history shortcut
    wait_state(stick, layer="threads", threadPage=0)
    tap(stick, 400, 255)
    wait_state(stick, layer="threads", threadPage=1)
    tap(stick)
    wait_state(stick, layer="face", threadPage=-1)


@pytest.mark.parametrize("creature", ["idle", "working", "done"])
def test_recent_history_does_not_draw_a_persistent_footer(stick, creature):
    frame(stick, state=creature, agents=ROWS, threads=THREADS, threadTotal=3)
    clock(stick, state(stick)["now"]+2500)
    before = screenshot(stick)
    frame(stick, state=creature, agents=ROWS, threads=THREADS, threadTotal=3,
          recent=[[999,0,"This must not appear below the face"]])
    after = screenshot(stick)
    assert state(stick)["recentCount"] == 1
    assert before[-456*35*2:] == after[-456*35*2:]


def test_hidden_bubble_does_not_consume_dashboard_exit(stick):
    activity(stick)
    tap(stick)
    activity(stick, bubble="A new line behind the table")
    wait_state(stick, layer="threads")
    press(stick)
    wait_state(stick, threadPage=-1)
    # Panel taps also exit even when a new bubble arrives while browsing.
    activity(stick)
    tap(stick)
    activity(stick, bubble="Another hidden line")
    tap(stick)
    wait_state(stick, threadPage=-1)


@pytest.mark.parametrize("command", ["tap -1 100", "tap 456 100", "tap 40 280", "tap 40 40 extra"])
def test_invalid_panel_coordinates_do_not_navigate(stick, command):
    activity(stick)
    tap(stick)
    stick.write_line(command)
    stick.read_until(lambda b: b"<<TAP error>>" in b, 3)
    wait_state(stick, layer="threads", threadPage=0)
