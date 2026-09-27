#!/usr/bin/env python3
"""Relaunches a headless Boop --debug 12 times on one state dir while the
dashboard's Follower follows debug.jsonl: each relaunch should read as a
restart, debug.1.jsonl should hold the launch before, and no more than 10
kept files should pile up (harness/HARNESS.md §9, DASHBOARD.md §3). Needs
`make build`; no board, Bluetooth or Jev.

    python3 plan/evidence/2026-09-28-tonight/daylog-check/relaunch_check.py [/tmp/bdc]"""
import json, os, signal, socket, subprocess, sys, time, shutil
from pathlib import Path
LANE = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(LANE / "internal/tools"))
from boopctl_lib.dash.feed import Follower
ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/bdc"); STATE = ROOT / "s"; SOCK = ROOT / "h.sock"
shutil.rmtree(ROOT, ignore_errors=True); ROOT.mkdir()
BOOP = LANE / ".build/debug/Boop"; HOOK = LANE / ".build/debug/boop-hook"

def dev(line):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(str(SOCK)); s.sendall(json.dumps(line).encode() + b"\n")

def launch():
    app = subprocess.Popen([str(BOOP), "--headless", "--state-dir", str(STATE), "--link", "none", "--socket", str(SOCK),
                            "--brain", "scripted", "--debug"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        time.sleep(0.1)
        try:
            dev({"dev": "probe"}); break
        except OSError:
            continue
    time.sleep(0.5)
    return app

f = Follower(STATE / "debug.jsonl")
restarts, firsts, ok = 0, [], True
prev_text = None
for n in range(1, 13):
    app = launch()
    env = dict(os.environ, BOOP_SOCKET=str(SOCK))
    subprocess.run([str(HOOK), "claude"], input=json.dumps({"hook_event_name": "SessionStart", "session_id": f"s{n}", "cwd": f"/tmp/p{n}"}).encode(), env=env, timeout=10)
    subprocess.run([str(HOOK), "claude"], input=json.dumps({"hook_event_name": "UserPromptSubmit", "session_id": f"s{n}", "cwd": f"/tmp/p{n}", "prompt": "x"}).encode(), env=env, timeout=10)
    time.sleep(0.8)
    restarted, lines = f.read()
    restarts += restarted
    first = lines[0] if lines else None
    if n > 1 and not restarted:
        print("launch", n, "NOT seen as a restart"); ok = False
    if n > 1:
        kept1 = (STATE / "debug.1.jsonl").read_text()
        if not prev_text or not kept1.startswith(prev_text):
            print("launch", n, "debug.1.jsonl isn't the previous launch's"); ok = False
    app.send_signal(signal.SIGTERM); app.wait(timeout=15)
    prev_text = (STATE / "debug.jsonl").read_text()
    kept = sorted(p.name for p in STATE.glob("debug*.jsonl"))
    print(f"launch {n:2}: restart seen={restarted}, lines now {len(prev_text.splitlines())}, files {len(kept)}: {' '.join(kept)}")
names = sorted(p.name for p in STATE.glob("debug*.jsonl"))
print("restarts seen:", restarts, "of 11; files:", len(names), "(debug.jsonl + 10 kept expected)")
print("projects per kept file, oldest first:")
for p in [STATE / f"debug.{i}.jsonl" for i in range(10, 0, -1)] + [STATE / "debug.jsonl"]:
    proj = sorted({s["project"] for l in p.read_text().splitlines() if '"status"' in l for s in json.loads(l).get("status", {}).get("sessions", [])})
    print(" ", p.name, proj)
print("OK" if ok and restarts == 11 and len(names) == 11 else "FAILED")
