#!/usr/bin/env python3
"""Drive the device into a transient state and screenshot it, in one session.

`buddyctl screenshot` opens its own serial session, which is fine for a
resting screen but useless for anything that times out: the glance card
lives 4s, a lantern bloom 350ms, a celebrate burst 2.5s. By the time a
second `buddyctl` invocation has found the port and settled the line, the
thing under test is gone.

This runs a sequence of serial commands and the screenshot dump on a single
open port, so the delay between "set up the state" and "capture it" is a few
milliseconds of write latency rather than a process launch.

    tools/shot.py --out /tmp/glance.png --cmd "press m 150" --wait 0.4
    tools/shot.py --out /tmp/hot.png --cmd mockprompt --wait 11 --state

--state additionally dumps the `state` JSON captured in the same session, so
the screenshot and the state assertion describe the same instant.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import time
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from buddyctl import (  # noqa: E402
    BuddyError,
    SerialBuddy,
    parse_screenshot,
    rgb565le_to_rgb888,
    scale_rgb,
    write_png,
)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="PNG path")
    ap.add_argument("--cmd", action="append", default=[],
                    help="serial command to send before capture (repeatable)")
    ap.add_argument("--wait", type=float, default=0.3,
                    help="seconds to wait after the last --cmd before capturing")
    ap.add_argument("--gap", type=float, default=0.15,
                    help="seconds between successive --cmd sends")
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--port", default=None)
    ap.add_argument("--timeout", type=float, default=25.0)
    ap.add_argument("--state", action="store_true",
                    help="also dump `state` JSON from the same session")
    args = ap.parse_args()

    with SerialBuddy(args.port, args.timeout) as buddy:
        for i, cmd in enumerate(args.cmd):
            buddy.write_line(cmd)
            if i < len(args.cmd) - 1:
                time.sleep(args.gap)
        if args.cmd:
            time.sleep(args.wait)

        state = None
        if args.state:
            # Read state BEFORE the dump: the screenshot blocks loop() for
            # seconds, so a state read afterwards describes a later instant.
            state = buddy.framed_json("state", "STATE", args.timeout)

        buddy.write_line("screenshot")
        buf, parsed = buddy.read_until(parse_screenshot, args.timeout)

    if not parsed:
        raise BuddyError("no screenshot framing found", 2)
    begin, body_start, _body_end, end = parsed
    w, h, rot = int(begin.group(1)), int(begin.group(2)), int(begin.group(3))
    body = re.sub(rb"\s+", b"", buf[body_start: body_start + end.start()])
    raw = base64.b64decode(body, validate=True)
    if end.group(1):
        want_len, want_crc = int(end.group(1)), int(end.group(2), 16)
        got = zlib.crc32(raw) & 0xFFFFFFFF
        if len(raw) != want_len or got != want_crc:
            raise BuddyError(
                f"integrity mismatch len={len(raw)}/{want_len} crc={got:08x}/{want_crc:08x}", 2)
    if len(raw) != w * h * 2:
        raise BuddyError(f"decoded {len(raw)} bytes, expected {w * h * 2}", 2)

    rgb = rgb565le_to_rgb888(raw, w, h)
    out_rgb, out_w, out_h = scale_rgb(rgb, w, h, args.scale)
    write_png(Path(args.out), out_w, out_h, out_rgb)

    result = {"ok": True, "out": args.out, "w": w, "h": h, "rot": rot}
    if state is not None:
        result["state"] = state
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BuddyError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(exc.code)
