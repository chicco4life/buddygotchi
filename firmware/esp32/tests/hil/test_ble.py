from __future__ import annotations

import asyncio
import sys
from argparse import Namespace
from pathlib import Path

import pytest


TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))
import buddyctl  # noqa: E402


pytestmark = pytest.mark.ble


def ble_args(**extra):
    base = {
        "address": None,
        "name": "Claude",
        "timeout": 8.0,
        "json": True,
        "secs": 2.0,
        "until": None,
    }
    base.update(extra)
    return Namespace(**base)


@pytest.fixture(scope="session")
def paired_ble_address():
    try:
        from bleak import BleakScanner
        from bleak.exc import BleakBluetoothNotAvailableError
    except ImportError:
        pytest.skip("bleak is not installed")

    async def scan():
        devices = await BleakScanner.discover(timeout=5.0, return_adv=True)
        for device, adv in devices.values():
            name = device.name or adv.local_name or ""
            uuids = {u.lower() for u in (adv.service_uuids or [])}
            if name.startswith("Claude") or buddyctl.NUS_SERVICE_UUID in uuids:
                return device.address
        return None

    try:
        address = asyncio.run(scan())
    except BleakBluetoothNotAvailableError as exc:
        pytest.skip(f"Bluetooth is not available: {exc}")
    if not address:
        pytest.skip("no BLE Buddy advertising")
    return address


def test_ble_status_ack_schema(paired_ble_address):
    args = ble_args(address=paired_ble_address)
    args.until = r'"ack"\s*:\s*"status"'
    args.secs = args.timeout
    lines = asyncio.run(buddyctl.ble_collect(args, [{"cmd": "status"}]))
    status = next((line for line in lines if line.get("ack") == "status"), None)
    assert status is not None
    assert status.get("ok") is True
    # PROTOCOL.md: telemetry is flat on the status ack.
    assert status.get("contract") == 2 and status.get("board") and status.get("fw") and status.get("git")


def test_ble_timesync_sets_rtc(paired_ble_address):
    args = ble_args(address=paired_ble_address)
    rc = asyncio.run(buddyctl.ble_timesync(args))
    assert rc == 0
