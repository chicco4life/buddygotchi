#!/usr/bin/env python3
"""Drives a headless Boop through a simulated day, for `boopctl day`'s test
fixture (see this folder's README.md): two launches on one state dir, the
second relaunched mid-day, with a fake board on the USB link that answers
each reaction's `ended` (PROTOCOL.md §4), hooks sent through the real
boop-hook, and dev lines for the clock, forced passes and moods
(harness/HARNESS.md §9). Needs `make build`; no board, Bluetooth or Jev.

    python3 plan/evidence/2026-09-28-tonight/daylog/drive_day.py [/tmp/bdl]

Leaves the state dir in ROOT/s: debug.1.jsonl (the first launch) and
debug.jsonl (the second)."""
from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
BUILD = REPO / ".build" / "debug"
ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/bdl")
STATE = ROOT / "s"
HOOK_SOCK = ROOT / "h.sock"
USB_SOCK = ROOT / "u.sock"
MIN = 60_000


class FakeBoard:
    """The device at the far end of the app's USB link. It says who it is
    when the app first speaks and answers each moment that has an id:
    `skipped` while needs-you shows, `cut needs_you` when needs-you starts
    while it plays, `cut tap` on a tap, else `done` 0.4 s later, unless
    `never` is queued in `ends`, when it never answers."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.lock = threading.Lock()
        self.conn: socket.socket | None = None
        self.server: socket.socket | None = None
        self.attn = None
        self.playing: dict[int, threading.Timer] = {}
        self.ends: list[str] = []
        self.up()

    def up(self) -> None:
        if self.path.exists():
            self.path.unlink()
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(self.path))
        server.listen(1)
        self.server = server
        threading.Thread(target=self._accept, args=(server,), daemon=True).start()

    def down(self) -> None:
        """The board unplugged: the app's link drops until `up`."""
        with self.lock:
            server, conn, self.server, self.conn = self.server, self.conn, None, None
        for s in (server, conn):
            if s:
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                s.close()
        if self.path.exists():
            self.path.unlink()

    def _accept(self, server: socket.socket) -> None:
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            with self.lock:
                self.conn = conn
            self._read(conn)

    def _read(self, conn: socket.socket) -> None:
        buf, spoke = b"", False
        while True:
            try:
                data = conn.recv(65536)
            except OSError:
                break
            if not data:
                break
            buf += data
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                if not spoke:
                    spoke = True
                    self.send({"t": "status", "v": 1, "id": "b00p-0000", "fw": "sim"})
                self._take(json.loads(raw))

    def send(self, msg: dict) -> None:
        with self.lock:
            conn = self.conn
        if conn:
            try:
                conn.sendall(json.dumps(msg, separators=(",", ":")).encode() + b"\n")
            except OSError:
                pass

    def _take(self, msg: dict) -> None:
        if msg.get("t") == "state":
            attn = msg.get("attn")
            if attn and not self.attn:
                for mid in list(self.playing):
                    self.end(mid, "cut", "needs_you")
            self.attn = attn
        elif msg.get("t") == "moment" and msg.get("id"):
            mid = msg["id"]
            if self.attn:
                self.send({"t": "ended", "id": mid, "how": "skipped"})
                return
            if self.ends and self.ends.pop(0) == "never":
                return
            timer = threading.Timer(0.4, self.end, (mid,))
            self.playing[mid] = timer
            timer.start()

    def end(self, mid: int, how: str = "done", why: str | None = None) -> None:
        timer = self.playing.pop(mid, None)
        if timer is None:
            return
        timer.cancel()
        self.send({"t": "ended", "id": mid, "how": how, **({"why": why} if why else {})})

    def tap(self) -> None:
        for mid in list(self.playing):
            self.end(mid, "cut", "tap")
        self.send({"t": "input", "k": "tap"})


def hook(agent: str, payload: dict) -> None:
    """One hook through the real boop-hook, as the agent would run it."""
    env = dict(os.environ, BOOP_SOCKET=str(HOOK_SOCK))
    subprocess.run([str(BUILD / "boop-hook"), agent], input=json.dumps(payload).encode(), env=env,
                   check=True, timeout=10)


def claude(event: str, **fields) -> None:
    hook("claude", {"hook_event_name": event, "session_id": "day-claude", "cwd": "/tmp/jetpack", **fields})


def codex(event: str, **fields) -> None:
    hook("codex", {"hook_event_name": event, "session_id": "day-codex", "cwd": "/tmp/landing", **fields})


def dev(line: dict) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(str(HOOK_SOCK))
        s.sendall(json.dumps(line).encode() + b"\n")
    time.sleep(0.05)


def advance(ms: int, step: int = MIN, pause: float = 0.05) -> None:
    """Moves the app's clock forward in steps, each ticking the app."""
    while ms > 0:
        dev({"dev": "advance", "ms": min(step, ms)})
        ms -= step
        time.sleep(pause)


def answer(**choices: str) -> None:
    dev({"dev": "answer", "answers": {k.replace("_", "."): v for k, v in choices.items()}})


def tool(agent, name: str, command, ok: bool = True) -> None:
    """A tool call; a failed one ends in Claude's PostToolUseFailure."""
    agent("PreToolUse", tool_name=name, tool_input={"command": command})
    if ok:
        agent("PostToolUse", tool_name=name, tool_input={"command": command}, tool_response={"stdout": "PRIVATE_OUTPUT"})
    else:
        agent("PostToolUseFailure", tool_name=name, tool_input={"command": command}, error="Exit code 1")


def work(minutes: int, agents=(claude,)) -> None:
    """Routine tool calls a minute apart, so working chatter can play."""
    for _ in range(minutes):
        for agent in agents:
            tool(agent, "Bash" if agent is claude else "shell", "ls PRIVATE_ARG")
        advance(MIN, pause=0.3)


def launch() -> subprocess.Popen:
    out = (ROOT / "boop-out.log").open("a")
    app = subprocess.Popen([str(BUILD / "Boop"), "--headless", "--state-dir", str(STATE), "--link", f"usb:{USB_SOCK}",
                            "--socket", str(HOOK_SOCK), "--brain", "scripted", "--debug"], stdout=out, stderr=out)
    for _ in range(100):
        time.sleep(0.1)
        try:
            dev({"dev": "probe"})
            break
        except OSError:
            continue
    time.sleep(2)  # the brain, and the link's first state
    return app


def stop(app: subprocess.Popen) -> None:
    app.send_signal(signal.SIGTERM)
    app.wait(timeout=15)


def first_launch() -> None:
    """Real time, a couple of minutes: a Claude turn with a needs-you, a
    comeback and a cheer, then a proud reaction the dashboard forced."""
    claude("SessionStart", source="startup")
    claude("UserPromptSubmit", prompt="PRIVATE_PROMPT fix the nav")
    time.sleep(2)
    tool(claude, "Bash", "swift test PRIVATE_ARG", ok=False)
    time.sleep(2)
    claude("PreToolUse", tool_name="Bash", tool_input={"command": "git push PRIVATE_ARG"})
    claude("PermissionRequest", tool_name="Bash", tool_input={"command": "git push PRIVATE_ARG"})
    time.sleep(12)
    claude("PostToolUse", tool_name="Bash", tool_response={"stdout": "PRIVATE_OUTPUT"})
    time.sleep(1)
    tool(claude, "Bash", "swift test PRIVATE_ARG")
    time.sleep(2)
    claude("Stop", last_assistant_message="PRIVATE_CLOSING")
    time.sleep(3)
    answer(mood="proud", react="proud", react_loops="twice", word_feeling="finally")
    time.sleep(3)


def second_launch(board: FakeBoard) -> None:
    """The rest of the day on an advanced clock."""
    # Morning: Codex and Claude both work, and both need you at once.
    codex("SessionStart", source="startup")
    codex("UserPromptSubmit", prompt="PRIVATE_PROMPT deploy the landing page")
    time.sleep(2)
    work(12, agents=(claude, codex))
    codex("PreToolUse", tool_name="shell", tool_input={"command": ["bash", "-lc", "vercel --prod"]})
    codex("PermissionRequest", tool_name="shell", tool_input={"command": ["bash", "-lc", "PRIVATE_COMMAND"]})
    advance(3000)  # past Codex's grace: needs you
    time.sleep(1)
    claude("UserPromptSubmit", prompt="PRIVATE_PROMPT and the footer")  # no pass while something needs you
    time.sleep(1)
    claude("PreToolUse", tool_name="Bash", tool_input={"command": "rm -rf PRIVATE_ARG"})
    claude("PermissionRequest", tool_name="Bash", tool_input={"command": "rm -rf PRIVATE_ARG"})
    advance(MIN, step=30_000)
    answer(react="happy")  # refused: something needs you
    advance(3 * MIN, step=30_000)
    codex("PostToolUse", tool_name="shell", tool_response="PRIVATE_OUTPUT")  # Claude's is shown now: a chirp
    advance(2 * MIN, step=30_000)
    claude("PostToolUse", tool_name="Bash", tool_response={"stdout": "PRIVATE_OUTPUT"})
    time.sleep(1.5)
    answer(react="curious", react_loops="once", word_about="docs")
    time.sleep(0.1)
    board.tap()  # cuts it short
    time.sleep(1.5)
    work(15, agents=(claude, codex))
    codex("Stop", last_assistant_message="PRIVATE_CLOSING")
    time.sleep(3)
    for _ in range(3):
        tool(claude, "Bash", "swift test PRIVATE_ARG", ok=False)
        time.sleep(2.5)
        advance(MIN, pause=0.3)
    answer(mood="determined", react="determined", react_loops="twice", word_about="tests")
    time.sleep(3)
    claude("StopFailure", error="rate_limit", last_assistant_message="PRIVATE_CLOSING")
    time.sleep(3)

    # Midday: nobody works; heartbeats each hour, the board unplugged a while.
    advance(40 * MIN, step=5 * MIN, pause=0.5)
    board.ends.append("never")
    answer(react="curious")
    time.sleep(0.5)
    board.down()  # before it said how that one ended
    advance(20 * MIN, step=MIN, pause=0.2)
    board.up()
    time.sleep(2)
    advance(95 * MIN, step=5 * MIN, pause=1.0)
    for _ in range(4):  # a poke streak
        board.tap()
        time.sleep(0.2)
    time.sleep(3)
    answer(mood="grumpy")
    time.sleep(1)
    dev({"dev": "mood", "mood": "grumpy"})  # refused: already grumpy
    time.sleep(4)
    board.ends.append("never")
    answer(react="sad", react_loops="once")
    time.sleep(1)
    advance(30_000, step=30_000)  # no `ended` comes: the app gives up on it
    time.sleep(1)
    answer(react="happy", react_loops="four times", word_feeling="yay")
    answer(react="excited", react_loops="once")  # waits behind the first...
    time.sleep(0.6)
    advance(30_000, step=30_000)  # ...too long
    time.sleep(8)

    # Afternoon: a long Claude turn with a needs-you, then both sessions end.
    claude("UserPromptSubmit", prompt="PRIVATE_PROMPT refactor the store")
    time.sleep(2)
    work(25)
    claude("PreToolUse", tool_name="Bash", tool_input={"command": "git push PRIVATE_ARG"})
    claude("PermissionRequest", tool_name="Bash", tool_input={"command": "git push PRIVATE_ARG"})
    advance(7 * MIN, step=30_000)
    claude("PostToolUse", tool_name="Bash", tool_response={"stdout": "PRIVATE_OUTPUT"})
    time.sleep(1)
    work(10)
    claude("Stop", last_assistant_message="PRIVATE_CLOSING")
    time.sleep(3)
    claude("SessionEnd", reason="exit")
    codex("SessionEnd", reason="exit")
    time.sleep(1)
    advance(30 * MIN, step=5 * MIN, pause=0.5)


def main() -> None:
    shutil.rmtree(ROOT, ignore_errors=True)
    ROOT.mkdir(parents=True)
    board = FakeBoard(USB_SOCK)
    app = launch()
    try:
        first_launch()
    finally:
        stop(app)
    time.sleep(1)
    app = launch()
    try:
        second_launch(board)
    finally:
        stop(app)
        board.down()
    for f in sorted(STATE.glob("debug*.jsonl")):
        print(f, sum(1 for _ in f.open()), "lines")


if __name__ == "__main__":
    main()
