"""USB serial access to the board: one JSON message per line at 921600 baud.

Only one process may hold the port. A lock file in /tmp makes concurrent
boopctl commands wait their turn instead of corrupting each other's lines.
"""
from __future__ import annotations

import fcntl
import glob
import json
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Any, Callable

import serial

BAUD = 921600
PORT_PATTERNS = ("/dev/cu.usbserial-*", "/dev/cu.wchusbserial*", "/dev/cu.SLAB_USBtoUART*")


class DeviceError(Exception):
    pass


def list_ports() -> list[str]:
    ports: list[str] = []
    for pattern in PORT_PATTERNS:
        ports.extend(sorted(glob.glob(pattern)))
    return ports


def find_port() -> str:
    env = os.environ.get("BOOP_PORT")
    if env:
        return env
    ports = list_ports()
    if not ports:
        raise DeviceError("no Boop board found on USB (looked for /dev/cu.usbserial-*)")
    return ports[0]


def port_holder(port: str) -> str:
    try:
        out = subprocess.run(["lsof", "-Fpc", port], text=True, capture_output=True, timeout=2).stdout
    except Exception:
        return ""
    return out.strip().replace("\n", " ")


class Device:
    """A locked, open serial connection to the board."""

    def __init__(self, port: str | None = None, timeout: float = 3.0) -> None:
        self.port = port or find_port()
        self.timeout = timeout
        self._ser: serial.Serial | None = None
        self._lock_fd: int | None = None
        self._buf = bytearray()

    def __enter__(self) -> "Device":
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", Path(self.port).name)
        self._lock_fd = os.open(f"/tmp/boopctl-{safe}.lock", os.O_CREAT | os.O_RDWR, 0o666)
        fcntl.flock(self._lock_fd, fcntl.LOCK_EX)
        try:
            # Keep DTR/RTS low so opening the port doesn't reset the board.
            ser = serial.Serial()
            ser.port, ser.baudrate, ser.timeout = self.port, BAUD, 0
            ser.dtr = False
            ser.rts = False
            ser.open()
            self._ser = ser
        except serial.SerialException as exc:
            holder = port_holder(self.port)
            raise DeviceError(f"can't open {self.port}: {exc}" + (f" (held by {holder})" if holder else ""))
        self._ser.reset_input_buffer()
        return self

    def __exit__(self, *_: object) -> None:
        if self._ser is not None:
            self._ser.close()
        if self._lock_fd is not None:
            fcntl.flock(self._lock_fd, fcntl.LOCK_UN)
            os.close(self._lock_fd)

    def send(self, message: dict[str, Any] | str) -> None:
        assert self._ser is not None
        line = message if isinstance(message, str) else json.dumps(message, separators=(",", ":"))
        self._ser.write(line.encode() + b"\n")
        self._ser.flush()

    def read_line(self, deadline: float) -> bytes | None:
        assert self._ser is not None
        while time.monotonic() < deadline:
            nl = self._buf.find(b"\n")
            if nl >= 0:
                line = bytes(self._buf[:nl]).rstrip(b"\r")
                del self._buf[: nl + 1]
                return line
            chunk = self._ser.read(8192)
            if chunk:
                self._buf.extend(chunk)
            else:
                time.sleep(0.005)
        return None

    def wait_for(self, match: Callable[[dict[str, Any]], bool], timeout: float | None = None) -> dict[str, Any]:
        deadline = time.monotonic() + (timeout or self.timeout)
        while True:
            line = self.read_line(deadline)
            if line is None:
                raise DeviceError(f"timed out waiting for the board on {self.port}")
            if not line.startswith(b"{"):
                continue  # boot log or other noise
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if match(msg):
                return msg

    def request(self, message: dict[str, Any], timeout: float | None = None) -> dict[str, Any]:
        """Send a debug message and return the reply with the same type."""
        self.send(message)
        return self.wait_for(lambda m: m.get("t") == message["t"], timeout)
