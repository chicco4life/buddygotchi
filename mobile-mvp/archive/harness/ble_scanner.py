#!/usr/bin/env python3
"""Phase 2.a diagnostic -- independent BLE central scanner.

Scans for BLE advertisements and prints anything that looks like a
Claude Buddy (name starts with 'Claude' OR advertises the Nordic UART
Service). Use this to independently confirm the probe is actually
broadcasting on the air, separately from whether Claude desktop's
picker is seeing us.

Run in a DIFFERENT terminal while ble_probe.py is advertising:

    .venv/bin/python mobile-mvp/harness/ble_scanner.py

If the scanner sees 'Claude-Mac' but Claude desktop's picker doesn't,
the problem is Claude-side (permission, filter, same-host quirk). If
the scanner also sees nothing, the probe isn't advertising for real.
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from bleak import BleakScanner  # type: ignore[import-not-found]
from bleak.backends.device import BLEDevice  # type: ignore[import-not-found]
from bleak.backends.scanner import AdvertisementData  # type: ignore[import-not-found]

NUS_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"

_seen: set[str] = set()
_show_all = False


def _log(msg: str) -> None:
    print(msg, flush=True)


def _cb(device: BLEDevice, adv: AdvertisementData) -> None:
    name = adv.local_name or device.name or ""
    uuids = [u.lower() for u in (adv.service_uuids or [])]
    hit_name = name.lower().startswith("claude")
    hit_uuid = NUS_SERVICE in uuids
    tagged = hit_name or hit_uuid
    if not tagged and not _show_all:
        return
    key = device.address
    if key in _seen and not tagged:
        return
    _seen.add(key)
    prefix = "[MATCH]" if tagged else "[dev]  "
    _log(
        f"{prefix} addr={device.address}  name={name!r}  rssi={adv.rssi}  "
        f"uuids={uuids}  nus={'YES' if hit_uuid else 'no'}  "
        f"name_match={'YES' if hit_name else 'no'}"
    )


async def main() -> None:
    global _show_all
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--all",
        action="store_true",
        help="print every BLE advertisement, not just Claude-matching ones",
    )
    ap.add_argument("--seconds", type=float, default=0.0)
    args = ap.parse_args()
    _show_all = args.all

    _log(f"[scan] start. --all={args.all} NUS={NUS_SERVICE}  Ctrl-C to stop.")
    async with BleakScanner(detection_callback=_cb):
        try:
            if args.seconds > 0:
                await asyncio.sleep(args.seconds)
            else:
                while True:
                    await asyncio.sleep(2.0)
                    _log(f"[scan] ... {len(_seen)} device(s) observed so far")
        except asyncio.CancelledError:
            pass


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[scan] stopped. matches: {}".format(len(_seen)), file=sys.stderr)
