#!/usr/bin/env python3
"""Phase 2.a -- standalone BLE probe.

Advertises the Nordic UART Service from this Mac as a fake Hardware Buddy.
Logs every GATT operation and every line Claude desktop writes to us. Does
NOT run the reducer or the daemon WebSocket; this is strictly a "can a BLE
link be established between Claude desktop and this Mac" probe. If this
script doesn't work, nothing else in Phase 2 matters.

Usage (outside sandbox, so macOS BT permission can be granted):

    .venv/bin/python src/archive/harness/ble_probe.py

Then on this same Mac:

    1. Open Claude (desktop app).
    2. Help -> Troubleshooting -> Enable Developer Mode.
    3. Developer -> Open Hardware Buddy...
    4. Click Connect, pick the advertised name (default "Claude-Buddy-Mac").
    5. Watch this script's stdout.

Success signs (in order):
    [adv]         advertising NUS with name ...
    [connect]     central subscribed to TX
    [rx <- line]  {"time":[...]}           <- one-shot on connect
    [rx <- line]  {"cmd":"owner",...}
    [rx <- line]  {"total":..,"running":..,...}   <- first heartbeat

At that point the BLE transport works and Phase 2.b (BleUpstream) is
plumbing. Hitting 'a' + Enter will send an approve for the most recent
prompt id the desktop sent us -- proves TX-notify back to the desktop
works too.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import signal
import sys
import time
from typing import Any, Optional

from bless import (  # type: ignore[import-not-found]
    BlessServer,
    BlessGATTCharacteristic,
    GATTCharacteristicProperties as Prop,
    GATTAttributePermissions as Perm,
)

NUS_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # desktop -> device (write)
NUS_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # device -> desktop (notify)

log = logging.getLogger("ble_probe")


class Probe:
    def __init__(self, name: str) -> None:
        self._name = name
        self._server: Optional[BlessServer] = None
        self._rx_buf = bytearray()
        self._last_prompt_id: Optional[str] = None
        self._connected = False
        self._byte_count = 0

    # bless calls these on every GATT op. Signature changed between versions;
    # accept (char, value) or (char=..., value=...) either way.
    def _on_write(self, characteristic: BlessGATTCharacteristic, value: bytearray) -> None:
        self._byte_count += len(value)
        log.info("[rx <- %3d bytes] %s", len(value), value[:80].decode("utf-8", "replace"))
        self._rx_buf.extend(value)
        while b"\n" in self._rx_buf:
            line, _, rest = self._rx_buf.partition(b"\n")
            self._rx_buf = bytearray(rest)
            if not line.strip():
                continue
            text = line.decode("utf-8", "replace").strip()
            log.info("[rx <- line] %s", text)
            self._maybe_capture_prompt(text)
            self._auto_ack(text)

    def _on_read(self, characteristic: BlessGATTCharacteristic, **_: Any) -> bytearray:
        log.info("[read req] %s -> (empty)", characteristic.uuid)
        return bytearray()

    def _maybe_capture_prompt(self, line: str) -> None:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            return
        prompt = obj.get("prompt") if isinstance(obj, dict) else None
        if isinstance(prompt, dict) and "id" in prompt:
            self._last_prompt_id = prompt["id"]
            log.info("[probe] captured prompt id=%s", self._last_prompt_id)

    def _auto_ack(self, line: str) -> None:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            return
        if not isinstance(obj, dict):
            return
        cmd = obj.get("cmd")
        if not isinstance(cmd, str):
            return
        if cmd == "char_begin":
            log.info("[probe] ignoring char_begin (folder push not supported)")
            return
        ack = {"ack": cmd, "ok": True, "n": 0}
        if cmd == "status":
            ack["data"] = {
                "name": self._name,
                "sec": False,
                "bat": {"pct": 100, "usb": True},
                "sys": {"up": int(time.monotonic()), "heap": 0},
                "stats": {"appr": 0, "deny": 0, "vel": 0, "nap": 0, "lvl": 1},
            }
        self._send(ack)

    async def _send_permission(self, decision: str) -> None:
        if not self._last_prompt_id:
            log.warning("[probe] no prompt id captured yet")
            return
        self._send({
            "cmd": "permission",
            "id": self._last_prompt_id,
            "decision": decision,
        })

    def _send(self, obj: dict) -> None:
        if self._server is None:
            return
        data = (json.dumps(obj, separators=(",", ":")) + "\n").encode("utf-8")
        char = self._server.get_characteristic(NUS_TX_UUID)
        if char is None:
            log.error("[tx] TX characteristic missing")
            return
        char.value = data
        ok = self._server.update_value(NUS_SERVICE, NUS_TX_UUID)
        log.info("[tx -> %3d bytes] %s  (notify=%s)", len(data), data[:80].decode("utf-8", "replace").rstrip(), ok)

    async def _connection_watcher(self) -> None:
        while True:
            if self._server is None:
                await asyncio.sleep(0.25)
                continue
            try:
                is_conn = await self._server.is_connected()
            except Exception as e:
                log.warning("[probe] is_connected error: %s", e)
                is_conn = False
            if is_conn and not self._connected:
                log.info("[connect] central connected")
                self._connected = True
            elif not is_conn and self._connected:
                log.info("[disconnect] central gone; re-advertising on next client write")
                self._connected = False
                self._rx_buf.clear()
            await asyncio.sleep(0.5)


    async def _stdin_loop(self) -> None:
        loop = asyncio.get_event_loop()
        log.info("[probe] type 'a' + Enter to APPROVE last prompt, 'd' to DENY, 'q' to quit")
        while True:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                return
            cmd = line.strip().lower()
            if cmd in ("a", "approve"):
                await self._send_permission("once")
            elif cmd in ("d", "deny"):
                await self._send_permission("deny")
            elif cmd in ("q", "quit", "exit"):
                return
            elif cmd:
                log.info("[probe] unknown; use a/d/q")

    async def run(self) -> None:
        self._server = BlessServer(name=self._name)
        self._server.read_request_func = self._on_read
        self._server.write_request_func = self._on_write

        await self._server.add_new_service(NUS_SERVICE)
        await self._server.add_new_characteristic(
            NUS_SERVICE,
            NUS_RX_UUID,
            Prop.write | Prop.write_without_response,
            None,
            Perm.writeable,
        )
        await self._server.add_new_characteristic(
            NUS_SERVICE,
            NUS_TX_UUID,
            Prop.notify,
            None,
            Perm.readable,
        )
        log.info("[probe] services registered (NUS)")

        # prioritize_local_name=False forces the NUS service UUID into the
        # 28-byte advertisement packet. REFERENCE.md requires clients to
        # filter on the service UUID, so without this we are invisible to
        # Claude desktop's picker.
        await self._server.start(prioritize_local_name=False)
        log.info(
            "[adv] advertising as name=%r service=%s -- open Claude desktop, "
            "Developer -> Open Hardware Buddy and pick this device",
            self._name,
            NUS_SERVICE,
        )

        watcher = asyncio.create_task(self._connection_watcher())
        stop_event = asyncio.Event()

        loop = asyncio.get_event_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, stop_event.set)
            except NotImplementedError:
                pass

        wait_tasks = [asyncio.create_task(stop_event.wait())]
        if sys.stdin.isatty():
            wait_tasks.append(asyncio.create_task(self._stdin_loop()))
        else:
            log.info("[probe] no TTY on stdin -- running until SIGINT/SIGTERM")

        done, _pending = await asyncio.wait(
            wait_tasks, return_when=asyncio.FIRST_COMPLETED
        )
        log.info("[probe] stopping...")
        watcher.cancel()
        try:
            await self._server.stop()
        except Exception as e:
            log.warning("[probe] stop() error: %s", e)
        log.info("[probe] bye -- total bytes received: %d", self._byte_count)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--name",
        default="Claude",
        help="BLE advertised local name. The advertisement packet has a "
             "31-byte cap; with a 128-bit service UUID (18 bytes) + flags "
             "(3 bytes) the name TLV must be <=10 bytes total, so the name "
             "itself must be <=8 chars for macOS CoreBluetooth to keep it "
             "in the primary ad packet. 'Claude' (6) is the safe maximum "
             "that also satisfies REFERENCE.md's 'starts with Claude' filter.",
    )
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    if not args.name.startswith("Claude"):
        print(
            "warning: REFERENCE.md says the device picker filters for names "
            "starting with 'Claude'. You may not see this device in the list.",
            file=sys.stderr,
        )

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-5s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )

    try:
        asyncio.run(Probe(name=args.name).run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
