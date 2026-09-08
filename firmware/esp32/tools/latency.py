#!/usr/bin/env python3
"""End-to-end latency scenario (plan/VERIFICATION.md §2, ARCHITECTURE.md §12).

Runs against the real Boop app connected to the buddy over BLE, with the
buddy also on USB so its state can be read without touching the BLE path:

  1. hook -> card:     a held PermissionRequest is posted to the app; the
                       device's state is polled over USB until the card shows.
  2. button -> decision: a synthetic primary press over USB; the held hook
                       call returning is the decision landing at the app.
  3. state -> frame:   a PreToolUse posted to the app; polled until the
                       creature reads "working".

Host-clock timestamps; the USB poll adds up to one serial round trip, so
every number is an upper bound. Budgets: 500 / 300 / 250 ms.

    tools/latency.py --rounds 5 --out ../../plan/evidence/phase-9/latency.md
"""
from __future__ import annotations

import argparse
import json
import statistics
import sys
import threading
import time
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import buddyctl  # noqa: E402

BUDGETS = {"hook -> card": 500, "button -> decision": 300, "state -> frame": 250}


def app_config() -> tuple[str, str]:
    cfg = json.loads((Path.home() / ".boop" / "config.json").read_text())
    return f"http://127.0.0.1:{cfg.get('httpPort', 21321)}", cfg["token"]


def post(base: str, token: str, path: str, body: dict, timeout: float = 30) -> str:
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"X-Boop-Token": token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 (localhost)
        return resp.read().decode()


def poll(buddy: buddyctl.SerialBuddy, ok, timeout: float) -> tuple[float, dict]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = buddy.framed_json("state", "STATE")
        if ok(state):
            return time.monotonic(), state
    raise buddyctl.BuddyError(f"device never reached the expected state within {timeout}s")


def one_round(buddy: buddyctl.SerialBuddy, base: str, token: str) -> dict[str, float]:
    session = "latency-" + uuid.uuid4().hex[:8]
    # Start from idle: end any previous turn and wait for the creature to settle.
    post(base, token, "/hook/event?source=claude-code", {"hook_event_name": "Stop", "session_id": session})
    poll(buddy, lambda s: s["creature"] != "needsYou" and not s["card"], 10)
    time.sleep(0.5)

    held: dict[str, float | str] = {}

    def hold() -> None:
        held["response"] = post(base, token, "/hook/approve?source=claude-code", {
            "hook_event_name": "PermissionRequest", "session_id": session,
            "tool_name": "Bash", "tool_input": {"command": "npm test"}}, timeout=60)
        held["returned"] = time.monotonic()

    t0 = time.monotonic()
    thread = threading.Thread(target=hold, daemon=True); thread.start()
    t1, _ = poll(buddy, lambda s: s["card"], 10)
    # The firmware ignores presses until the card arms (in-flight press guard).
    poll(buddy, lambda s: s["armed"], 10)
    hold_ms = 150
    t2 = time.monotonic()
    buddy.write_line(f"press a {hold_ms}")
    buddy.read_until(lambda b: b"<<PRESS a up>>" in b, 5)
    thread.join(timeout=10)
    if "returned" not in held:
        raise buddyctl.BuddyError("held approval never returned after the press")
    t3 = float(held["returned"])

    # State change to frame: a fresh tool call after the decision.
    poll(buddy, lambda s: not s["card"], 5)
    t4 = time.monotonic()
    post(base, token, "/hook/event?source=claude-code", {
        "hook_event_name": "PreToolUse", "session_id": session, "tool_name": "Bash", "tool_input": {"command": "ls"}})
    t5, _ = poll(buddy, lambda s: s["creature"] == "working", 10)
    post(base, token, "/hook/event?source=claude-code", {"hook_event_name": "Stop", "session_id": session})
    return {"hook -> card": (t1 - t0) * 1000,
            "button -> decision": (t3 - t2) * 1000 - hold_ms,  # the press is held 150 ms; the tap lands on release
            "state -> frame": (t5 - t4) * 1000}


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, round(p / 100 * (len(ordered) - 1))))
    return ordered[k]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--port")
    ap.add_argument("--out")
    args = ap.parse_args()
    base, token = app_config()
    rounds: list[dict[str, float]] = []
    with buddyctl.SerialBuddy(args.port, 5.0) as buddy:
        state = buddy.framed_json("state", "STATE")
        if not state.get("connected"):
            print("device is not connected to the app over BLE", file=sys.stderr); return 1
        fw = state.get("fw")
        for i in range(args.rounds):
            rounds.append(one_round(buddy, base, token))
            print(f"round {i + 1}: " + ", ".join(f"{k} {v:.0f} ms" for k, v in rounds[-1].items()))
    lines = [f"# Latency scenario, {time.strftime('%Y-%m-%d %H:%M')} local, fw {fw}, {args.rounds} rounds", "",
             "Host-clock upper bounds (USB state poll adds up to one serial round trip).", "",
             "| Path | p50 | p90 | max | budget | within |", "| --- | --- | --- | --- | --- | --- |"]
    ok_all = True
    for key, budget in BUDGETS.items():
        vals = [r[key] for r in rounds]
        p90 = percentile(vals, 90); ok = p90 <= budget; ok_all &= ok
        lines.append(f"| {key} | {statistics.median(vals):.0f} ms | {p90:.0f} ms | {max(vals):.0f} ms | {budget} ms | {'yes' if ok else 'NO'} |")
    text = "\n".join(lines) + "\n"
    print(text)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True); Path(args.out).write_text(text)
    return 0 if ok_all else 2


if __name__ == "__main__":
    sys.exit(main())
