#!/usr/bin/env python3
"""Long-run hardware soak on the RenderState v2 wire: randomized state,
card, boop, and screenshot cycling with heap, panic, and reboot monitoring
over USB serial. Quit the Boop app first (two writers confuse the parser).

Exercises what a desk pet lives through — state changes with effort and
cheer, cards answered both ways once armed, held boops, screenshots — for
as long as asked, and fails loudly on any reboot, panic, heap erosion, or
wedged state. Deterministic (seeded) so a failing cycle reproduces.

    tools/soak.py --minutes 120
"""
from __future__ import annotations

import argparse
import base64
import json
import random
import re
import sys
import time
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import buddyctl  # noqa: E402

STATES = ["asleep", "idle", "working", "done", "uhoh"]
EFFORTS = ["light", "hard", "grinding"]
CHEERS = ["hop", "cheer", "dance"]
OVERLAYS = ["greet", "boop"]
STAKES = ["fine", "checkIt", "careful"]
HEAP_MIN_FLOOR = 60_000


def state(s: buddyctl.SerialBuddy) -> dict:
    return s.framed_json("state", "STATE", 5)


def ping(s: buddyctl.SerialBuddy) -> dict:
    return s.framed_json("ping", "PONG", 5)


def frame(s: buddyctl.SerialBuddy, **fields) -> None:
    s.write_line(json.dumps({"v": 2, "state": "idle", **fields}, ensure_ascii=False, separators=(",", ":")))


def wait_state(s: buddyctl.SerialBuddy, timeout: float = 5.0, **want) -> dict:
    deadline = time.monotonic() + timeout
    last: dict = {}
    while time.monotonic() < deadline:
        last = state(s)
        if all(last.get(k) == v for k, v in want.items()):
            return last
        time.sleep(0.1)
    raise RuntimeError(f"state never matched {want}; last creature={last.get('creature')} card={last.get('card')} armed={last.get('armed')}")


def press(s: buddyctl.SerialBuddy, which: str, ms: int = 120) -> bytes:
    s.write_line(f"press {which} {ms}")
    buf, _ = s.read_until(lambda b: f"<<PRESS {which} up>>".encode() in b, ms / 1000 + 4)
    return buf


def has_command(buf: bytes, **want) -> bool:
    for line in buf.splitlines():
        try:
            obj = json.loads(line)
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(obj, dict) and all(obj.get(k) == v for k, v in want.items()):
            return True
    return False


def screenshot_ok(s: buddyctl.SerialBuddy) -> None:
    s.write_line("screenshot")
    buf, parsed = s.read_until(buddyctl.parse_screenshot, 60)
    begin, body_start, _body_end, end = parsed
    w, h = int(begin.group(1)), int(begin.group(2))
    body = re.sub(rb"\s+", b"", buf[body_start : body_start + end.start()])
    raw = base64.b64decode(body, validate=True)
    if len(raw) != w * h * 2 or int(end.group(2), 16) != (zlib.crc32(raw) & 0xFFFFFFFF):
        raise RuntimeError(f"screenshot integrity failed ({w}x{h}, {len(raw)} bytes)")


def require_exclusive(s) -> None:
    """Refuse to drive the device while the Boop app is connected over BLE.

    Two writers on one screen silently corrupts every capture: the app's own
    frames (real cards, session dots) land between ours and the screenshot.
    That produced a set of contaminated goldens before this guard existed.
    """
    if s.framed_json("state", "STATE", 3).get("connected"):
        raise SystemExit(
            "The Boop app is connected to this buddy over Bluetooth and is pushing its own\n"
            "frames. Quit Boop (menu bar, Quit) and run this again; captures taken now are\n"
            "not reproducible."
        )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--minutes", type=float, default=120.0)
    ap.add_argument("--port", default=None)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    deadline = time.monotonic() + args.minutes * 60
    failures: list[str] = []
    cycles = approvals = boops = shots = 0
    with buddyctl.SerialBuddy(args.port or buddyctl.find_port(), timeout=8) as s:
        base = ping(s)
        if base.get("contract") != 2:
            print(f"firmware speaks contract {base.get('contract')}, this soak needs 2", file=sys.stderr)
            return 1
        base_panics, last_up, heap_first, heap_min_seen = base["panics"], base["up"], base["heap"], base["heapMin"]
        require_exclusive(s)
        s.write_line("imu set 0 0 1")  # face up: never nap during the run
        print(f"soak start: fw={base['fw']} board={base['board']} heap={heap_first}", flush=True)
        while time.monotonic() < deadline and not failures:
            cycles += 1
            try:
                st = rng.choice(STATES)
                fields = {"state": st, "effort": rng.choice(EFFORTS), "dots": rng.randint(0, 4)}
                if st == "done":
                    fields["cheer"] = rng.choice(CHEERS)
                if st == "idle" and rng.random() < 0.3:
                    fields["overlay"] = rng.choice(OVERLAYS)
                frame(s, **fields)
                wait_state(s, creature=st)
                if cycles % 4 == 0:
                    card_id = f"soak{cycles}"
                    stakes = rng.choice(STAKES)
                    frame(s, state="needsYou", card={"id": card_id, "tool": "Bash", "gloss": "runs tests",
                                                     "stakes": stakes, "approval": True, "n": 1, "of": 1})
                    wait_state(s, card=True, armed=True)
                    # Tap primary = allow (careful stakes need a 2 s hold); secondary = deny.
                    which = "a" if (cycles // 4) % 2 == 0 else "b"
                    buf = press(s, which, 2100 if which == "a" and stakes == "careful" else 120)
                    if not has_command(buf, cmd="decision", id=card_id):
                        buf += s.drain_until_quiet(max_wait=0.5)
                    if not has_command(buf, cmd="decision", id=card_id):
                        raise RuntimeError(f"press {which} produced no decision for {card_id}")
                    approvals += 1
                    frame(s, state="working")
                    wait_state(s, card=False, creature="working")
                    time.sleep(1.6)  # decision feedback clears
                if cycles % 5 == 0 and st not in ("asleep", "uhoh"):
                    press(s, "a", 1100)  # held primary with no card = local boop
                    boops += 1
                if cycles % 10 == 0:
                    screenshot_ok(s)
                    shots += 1
                if cycles % 5 == 0:
                    p = ping(s)
                    if p["up"] < last_up:
                        raise RuntimeError(f"REBOOT detected (up {last_up} -> {p['up']}, reset={p['reset']})")
                    last_up = p["up"]
                    if p["panics"] > base_panics:
                        raise RuntimeError(f"panic count rose {base_panics} -> {p['panics']}")
                    heap_min_seen = min(heap_min_seen, p["heapMin"])
                    if p["heapMin"] < HEAP_MIN_FLOOR:
                        raise RuntimeError(f"heapMin {p['heapMin']} below floor {HEAP_MIN_FLOOR}")
                if cycles % 20 == 0:
                    print(f"cycle {cycles}: heap={p['heap']} heapMin={heap_min_seen} approvals={approvals}", flush=True)
                time.sleep(rng.uniform(1.0, 4.0))
            except Exception as exc:  # noqa: BLE001 — record and stop
                failures.append(f"cycle {cycles}: {exc}")
        try:
            s.write_line("imu clear")
            final = ping(s)
        except Exception:  # noqa: BLE001 — the board may be wedged; report what we have
            final = {"heap": -1, "panics": base_panics, "up": last_up}
    summary = {
        "ok": not failures, "cycles": cycles, "approvals": approvals, "boops": boops, "screenshots": shots,
        "heap_first": heap_first, "heap_last": final["heap"], "heap_min_seen": heap_min_seen,
        "panics_delta": final["panics"] - base_panics, "uptime_s": final["up"] // 1000, "failures": failures,
    }
    print("SOAK " + json.dumps(summary), flush=True)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
