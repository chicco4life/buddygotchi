"""The dashboard's live check (README.md here): a headless Boop with the
scripted brain whose USB link goes to a boop-sim standing in for the board,
the e2e Claude session replayed into it, taps on the sim's screen, and the
real dashboard, with its own sim as the face, driven key by key through
Textual's pilot. Saves SVGs of the dashboard, and the run's debug.jsonl.

    internal/tools/.venv/bin/python plan/evidence/2026-09-28-tonight/dash/drive.py
"""
import asyncio
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO / "internal" / "tools"))

from boopctl_lib.cli import SIM_PROGRAM, build_sim  # noqa: E402
from boopctl_lib.dash.app import Dash, StateView  # noqa: E402
from boopctl_lib.dash.face import SimFace  # noqa: E402
from boopctl_lib.e2e import BIN, FIXTURES  # noqa: E402

OUT = Path(__file__).parent
STATE = Path("/tmp/bdash2")
USB = STATE / "usb.sock"
SOCKET = STATE / "boop.sock"


class SimBoard:
    """A second boop-sim as the board on the app's USB link: the app's
    lines go to its stdin, and its lines (`ended`, `tap`, `status`) back."""

    def __init__(self) -> None:
        self.proc = subprocess.Popen([str(SIM_PROGRAM)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(USB))
        self.server.listen(1)
        self.lock = threading.Lock()
        self.write({"t": "dbg.clock", "run": True})
        threading.Thread(target=self.serve, daemon=True).start()
        threading.Thread(target=self.tick, daemon=True).start()

    def tick(self) -> None:
        """boop-sim's clock moves only as lines come in, so a line every
        100 ms keeps it moving: a tap's release, and a moment's end."""
        while self.proc.poll() is None:
            try:
                self.write({"t": "dbg.ping"})
            except (OSError, ValueError):
                return
            time.sleep(0.1)

    def write(self, msg: dict | bytes) -> None:
        import json
        data = msg if isinstance(msg, bytes) else json.dumps(msg).encode() + b"\n"
        with self.lock:
            self.proc.stdin.write(data)
            self.proc.stdin.flush()

    def serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return  # stopped
            threading.Thread(target=self.up, args=(conn,), daemon=True).start()
            buf = b""
            while chunk := conn.recv(65536):
                buf += chunk
                *lines, buf = buf.split(b"\n")
                for line in lines:
                    self.write(line + b"\n")

    def up(self, conn: socket.socket) -> None:
        for line in self.proc.stdout:
            if b'"t":"dbg.' in line.replace(b" ", b""):
                continue  # replies to our own dbg lines stay here
            try:
                conn.sendall(line)
            except OSError:
                return

    def tap(self) -> None:
        self.write({"t": "dbg.touch", "x": 160, "y": 80, "ms": 60})

    def stop(self) -> None:
        self.proc.stdin.close()
        self.proc.wait(timeout=5)
        self.server.close()


async def main() -> None:
    build_sim()
    shutil.rmtree(STATE, ignore_errors=True)
    STATE.mkdir(parents=True)
    board = SimBoard()
    boop = subprocess.Popen([BIN / "Boop", "--headless", "--state-dir", STATE, "--link", f"usb:{USB}", "--socket", SOCKET,
                             "--debug", "--brain", "scripted", "--name", "Pip"],
                            stdout=open(STATE / "headless.out", "w"), stderr=subprocess.STDOUT)
    try:
        while not SOCKET.exists():
            time.sleep(0.1)
        app = Dash(STATE / "debug.jsonl", str(SOCKET),
                   make_face=lambda on_frame, on_error: SimFace(str(SIM_PROGRAM), on_frame, on_error))
        async with app.run_test(size=(200, 62)) as pilot:
            async def until(what: str, check, timeout: float = 20) -> None:
                deadline = time.monotonic() + timeout
                while not check():
                    if time.monotonic() > deadline:
                        raise SystemExit(f"timed out waiting for {what}")
                    await pilot.pause(0.1)
                print("ok:", what)

            async def shot(name: str) -> None:
                await pilot.pause(0.5)
                app.save_screenshot(f"{name}.svg", str(OUT))

            async def pick(key: str, *downs: int) -> None:
                await pilot.press(key)
                for down in downs:
                    await pilot.pause(0.2)
                    await pilot.press(*["down"] * down, "enter")

            def landed() -> bool:
                return not app.pending.waiting

            def text(name: str) -> str:
                return str(app.columns[name].content)

            await until("the board connected", lambda: app.board.status.get("connected"))
            await pilot.pause(1)
            await pick("m", 4)  # grumpy, so the first pass changes it back
            await until("the forced mood landed", landed)
            replay = subprocess.run([BIN / "boopdev", "replay", FIXTURES / "claude" / "session.jsonl",
                                     "--socket", SOCKET, "--gap-ms", "400"], capture_output=True, text=True)
            assert replay.returncode == 0, replay.stderr
            await until("the session's passes", lambda: sum(1 for r in app.board.decided if r["event"]) >= 4)
            await pilot.pause(2)
            await pick("r", 3, 2, 1, 0)  # proud, three times, "finally", no topic
            await until("the forced reaction landed", landed)
            await until("the reaction playing", lambda: "▶ playing" in text("decided"), 5)
            await shot("02-playing")
            await until("the reaction played", lambda: "✓ played" in text("decided").split("forced by dashboard", 1)[1], 30)
            await pick("r", 0, 0, 0, 0)  # none: stays quiet
            await until("the quiet pass landed", landed)
            await pick("a", 0)  # cheer
            await until("the cheer landed", landed)
            await pilot.pause(1)
            for _ in range(4):  # a poke streak: taps, then a pokes pass the mood sits out
                board.tap()
                await asyncio.sleep(0.7)
            await until("the poke streak's pass", lambda: "mood sat out" in text("mood"), 10)
            await pilot.pause(2)
            await shot("01-wide")
            await pilot.press("t")
            await shot("03-timeline")
            await pilot.press("t")
            await pilot.resize_terminal(110, 90)
            await shot("04-narrow")
            await pilot.resize_terminal(200, 62)
            await pilot.press("s")
            await until("the state view", lambda: isinstance(app.screen, StateView))
            await pilot.press("escape")
            await pilot.press("q")
    finally:
        boop.terminate()
        boop.wait()
        board.stop()
    shutil.copy(STATE / "debug.jsonl", OUT / "debug.jsonl")
    print("saved", OUT / "debug.jsonl")


if __name__ == "__main__":
    asyncio.run(main())
