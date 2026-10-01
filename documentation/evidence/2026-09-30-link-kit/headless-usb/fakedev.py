"""A fake Boop device on a Unix socket, as `boopctl bridge` presents the
board: it answers as linkkit/device's kit does over USB. The app counts as
there while it has spoken in the last 30 s, across socket connections, as
the board can't see the app's socket close; the app's first line after that
silence gets a `hello`, and so does the app's own `{"t":"hello"}` ask. Each
`do` ends `done` 1.5 s after it arrives. Every line the app sends is
written to `heard.jsonl` beside this file, with the connection's number.

    python3 fakedev.py SOCKET VOICE
"""
import json
import os
import socket
import sys
import threading
import time

path, voice = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
if os.path.exists(path):
    os.unlink(path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(1)
HELLO = {"t": "hello", "kit": 1, "app": "boop", "id": "b00p-fake", "fw": "1.0.0",
         "does": ["react", "task_complete", "reply_ready", "starting", "stopped", "error", "helper_return",
                  "listening", "stop_listening", "poked", "tap_spam"], "voice": voice}
HOST_GONE_S = 30
heard_at = None  # when the app last spoke, over any connection
log = open(os.path.join(here, "heard.jsonl"), "w")
n = 0
while True:
    conn, _ = srv.accept()
    n += 1
    lock = threading.Lock()

    def send(msg, conn=conn, lock=lock):
        with lock:
            try:
                conn.sendall((json.dumps(msg, separators=(",", ":")) + "\n").encode())
            except OSError:
                pass

    buf = b""
    while True:
        data = conn.recv(4096)
        if not data:
            break
        buf += data
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            msg = json.loads(raw)
            log.write(json.dumps({"connection": n, "line": msg}, separators=(",", ":")) + "\n")
            log.flush()
            now = time.monotonic()
            live = heard_at is not None and now - heard_at < HOST_GONE_S
            heard_at = now
            if not live:
                send(HELLO)
            elif msg.get("t") == "hello":
                send(HELLO)
            if msg.get("t") == "do" and isinstance(msg.get("id"), int):
                i = msg["id"]
                threading.Timer(1.5, lambda i=i: send({"t": "ev", "kind": "ended", "data": {"id": i, "how": "done"}})).start()
    conn.close()
