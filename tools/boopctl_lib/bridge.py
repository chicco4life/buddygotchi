"""`boopctl bridge`: owns the board's serial port and shares it through a
Unix socket (plan/VERIFICATION.md §2, L4).

Every complete line from the board goes to every client; every complete line
from a client goes to the board whole, so lines from different clients never
interleave. The Mac app's USB transport and other boopctl commands can use
the board at the same time.
"""
from __future__ import annotations

import os
import select
import signal
import socket
import stat
import sys

from boopctl_lib.device import Device

DEFAULT_SOCKET = "/tmp/boop-bridge.sock"


def bridge_path() -> str:
    return os.environ.get("BOOP_BRIDGE") or DEFAULT_SOCKET


def bridge_running(path: str | None = None) -> bool:
    path = path or bridge_path()
    try:
        if not stat.S_ISSOCK(os.stat(path).st_mode):
            return False
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            s.connect(path)
        return True
    except OSError:
        return False


def serve(port: str | None, path: str, quiet: bool = False) -> int:
    if bridge_running(path):
        print(f"boopctl: a bridge is already running on {path}", file=sys.stderr)
        return 2
    with Device(port, direct=True) as dev:
        ser = dev._ser
        assert ser is not None
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        if os.path.exists(path):
            os.unlink(path)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path)
        os.chmod(path, 0o600)
        server.listen(8)
        clients: dict[socket.socket, bytearray] = {}
        board = bytearray()
        stopping = False

        def stop(*_: object) -> None:
            nonlocal stopping
            stopping = True

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        if not quiet:
            print(f"bridge: {dev.port} ⇄ {path}", flush=True)
        try:
            while not stopping:
                try:
                    readable, _, _ = select.select([ser.fileno(), server, *clients], [], [], 0.2)
                except InterruptedError:
                    continue
                for r in readable:
                    if r is server:
                        conn, _ = server.accept()
                        clients[conn] = bytearray()
                        if not quiet:
                            print(f"bridge: client joined ({len(clients)})", flush=True)
                    elif r == ser.fileno():
                        board.extend(ser.read(65536))
                        while (nl := board.find(b"\n")) >= 0:
                            line = bytes(board[: nl + 1])
                            del board[: nl + 1]
                            for c in list(clients):
                                try:
                                    c.sendall(line)
                                except OSError:
                                    clients.pop(c).clear()
                                    c.close()
                    else:
                        conn = r
                        try:
                            data = conn.recv(65536)
                        except OSError:
                            data = b""
                        if not data:
                            clients.pop(conn, None)
                            conn.close()
                            if not quiet:
                                print(f"bridge: client left ({len(clients)})", flush=True)
                            continue
                        buf = clients[conn]
                        buf.extend(data)
                        while (nl := buf.find(b"\n")) >= 0:
                            ser.write(bytes(buf[: nl + 1]))
                            del buf[: nl + 1]
                        ser.flush()
        finally:
            for c in clients:
                c.close()
            server.close()
            if os.path.exists(path):
                os.unlink(path)
            if not quiet:
                print("bridge: stopped", flush=True)
    return 0
