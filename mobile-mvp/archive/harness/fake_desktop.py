#!/usr/bin/env python3
"""Replay a JSONL scenario against the daemon's fake upstream.

Each line is sent verbatim as a NUS line to the daemon, with an
optional inter-line delay to simulate real heartbeat cadence.

Special tokens recognised in the scenario file:

    __DISCONNECT__      instructs the fake upstream to synthesize a BLE
                        disconnect; the TCP socket stays open so the
                        next real line reconnects.
    __SLEEP:<seconds>__ pause between the previous and next line.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
import time
from pathlib import Path


async def replay(path: Path, host: str, port: int, default_delay: float) -> None:
    reader, writer = await asyncio.open_connection(host, port)
    print(f"[fake_desktop] connected to {host}:{port}", file=sys.stderr)

    # Reader task: prints every line the daemon writes back (acks,
    # permission decisions).
    async def _drain() -> None:
        while True:
            line = await reader.readline()
            if not line:
                return
            print(f"[daemon -> device] {line.decode('utf-8').rstrip()}", file=sys.stderr)

    drain_task = asyncio.create_task(_drain())

    try:
        with path.open("r", encoding="utf-8") as fh:
            for raw in fh:
                raw = raw.rstrip("\n")
                if not raw.strip():
                    continue
                if raw.startswith("__SLEEP:"):
                    secs = float(raw[len("__SLEEP:"):-2])
                    await asyncio.sleep(secs)
                    continue
                writer.write((raw + "\n").encode("utf-8"))
                await writer.drain()
                print(f"[desktop -> daemon] {raw}", file=sys.stderr)
                await asyncio.sleep(default_delay)

        # Keep the socket open so the daemon continues to see us
        # as connected; useful when eyeballing the web client.
        print("[fake_desktop] scenario done. Ctrl-C to exit.", file=sys.stderr)
        await asyncio.Event().wait()
    finally:
        drain_task.cancel()
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", type=Path, help="JSONL scenario file")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument(
        "--delay",
        type=float,
        default=1.0,
        help="Seconds between lines (default 1.0)",
    )
    args = ap.parse_args()
    if not args.scenario.exists():
        ap.error(f"scenario not found: {args.scenario}")
    try:
        asyncio.run(replay(args.scenario, args.host, args.port, args.delay))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
