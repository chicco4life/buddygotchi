#!/usr/bin/env python3
"""Long-run hardware soak: randomized state/prompt/menu cycling with heap,
crash, and reboot monitoring over USB serial.

Exercises the paths a desk pet actually lives through — heartbeat state
changes, armed prompts answered both ways, menu open/navigate/close,
boops, screenshots — for hours, and fails loudly on any reboot, panic,
heap erosion, or wedged state. Deterministic (seeded) so a failing cycle
number reproduces.

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

PETS = ["idle", "busy", "thinking", "attention", "celebrate", "error", "sleep"]
SPECIES = ["blob", "cat", "duck", "owl", "robot", "capybara"]
ACTIVITIES = ["verify", "read", "write", "shell", "web", "work"]

# Heap can legitimately sink a little as BLE/NVS settle; below this floor
# something is leaking. Matches the hardening-test philosophy: generous,
# but a real leak crosses it within an hours-long run.
HEAP_MIN_FLOOR = 60_000


def send_json(s: buddyctl.SerialBuddy, payload: dict) -> None:
    s.write_line(json.dumps(payload, separators=(",", ":")))


def state(s: buddyctl.SerialBuddy) -> dict:
    return s.framed_json("state", "STATE", 5)


def ping(s: buddyctl.SerialBuddy) -> dict:
    return s.framed_json("ping", "PONG", 5)


def wait_state(s: buddyctl.SerialBuddy, timeout: float = 5.0, **want) -> dict:
    deadline = time.monotonic() + timeout
    last: dict = {}
    while time.monotonic() < deadline:
        last = state(s)
        if all(last.get(k) == v for k, v in want.items()):
            return last
        time.sleep(0.2)
    raise RuntimeError(f"state never matched {want}; last pet={last.get('pet')} menu={last.get('menu')}")


def press(s: buddyctl.SerialBuddy, which: str, ms: int = 120) -> bytes:
    s.write_line(f"press {which} {ms}")
    buf, _ = s.read_until(lambda b: f"<<PRESS {which} up>>".encode() in b, 4)
    return buf


def screenshot_ok(s: buddyctl.SerialBuddy) -> None:
    s.write_line("screenshot")
    buf, parsed = s.read_until(buddyctl.parse_screenshot, 25)
    begin, body_start, _body_end, end = parsed
    w, h = int(begin.group(1)), int(begin.group(2))
    body = re.sub(rb"\s+", b"", buf[body_start : body_start + end.start()])
    raw = base64.b64decode(body, validate=True)
    if len(raw) != w * h * 2 or int(end.group(2), 16) != (zlib.crc32(raw) & 0xFFFFFFFF):
        raise RuntimeError(f"screenshot integrity failed ({w}x{h}, {len(raw)} bytes)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--minutes", type=float, default=120.0)
    ap.add_argument("--port", default=None)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    deadline = time.monotonic() + args.minutes * 60
    failures: list[str] = []
    cycles = 0
    approvals = 0
    menus = 0
    shots = 0

    with buddyctl.SerialBuddy(args.port or buddyctl.find_port(), timeout=8) as s:
        base = ping(s)
        base_panics = base["panics"]
        last_up = base["up"]
        heap_first = base["heap"]
        heap_min_seen = base["heapMin"]
        print(f"soak start: fw={base['fw']} board={base['board']} heap={heap_first}", flush=True)

        while time.monotonic() < deadline and not failures:
            cycles += 1
            try:
                pet = rng.choice(PETS)
                payload = {
                    "pet": pet,
                    "species": rng.choice(SPECIES),
                    "total": rng.randint(1, 4),
                    "running": rng.randint(0, 2),
                    "waiting": 1 if pet == "attention" else 0,
                    "activity": rng.choice(ACTIVITIES),
                }
                send_json(s, payload)
                wait_state(s, pet=pet)

                if cycles % 4 == 0:
                    s.write_line("mockprompt")
                    s.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 4)
                    which = "a" if (cycles // 4) % 2 == 0 else "b"
                    buf = press(s, which)
                    if b'"cmd":"permission"' not in buf:
                        buf += s.drain_until_quiet(max_wait=0.5)
                    if b'"cmd":"permission"' not in buf:
                        raise RuntimeError(f"press {which} produced no decision")
                    approvals += 1
                    send_json(s, {"pet": "idle", "total": 1, "running": 0, "waiting": 0})
                    wait_state(s, promptId="")

                if cycles % 6 == 0:
                    press(s, "m")
                    wait_state(s, menu="root")
                    press(s, "m")
                    press(s, "b")
                    wait_state(s, menu="closed")
                    menus += 1

                if cycles % 5 == 0:
                    press(s, "a")   # boop

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

                time.sleep(6)
            except Exception as exc:  # noqa: BLE001 — record and stop
                failures.append(f"cycle {cycles}: {exc}")

        final = ping(s)

    summary = {
        "ok": not failures,
        "cycles": cycles,
        "approvals": approvals,
        "menus": menus,
        "screenshots": shots,
        "heap_first": heap_first,
        "heap_last": final["heap"],
        "heap_min_seen": heap_min_seen,
        "panics_delta": final["panics"] - base_panics,
        "uptime_s": final["up"] // 1000,
        "failures": failures,
    }
    print("SOAK " + json.dumps(summary), flush=True)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
