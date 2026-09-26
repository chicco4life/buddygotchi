"""Links to the board (USB serial at 460800 baud) and to boop-sim: one JSON
message per line in each direction.

Only one process may hold the port. A lock file in /tmp makes concurrent
boopctl commands wait their turn instead of corrupting each other's lines.
"""
from __future__ import annotations

import base64
import fcntl
import glob
import json
import os
import re
import socket
import struct
import subprocess
import time
import zlib
from pathlib import Path
from typing import Any, Callable

import serial

BAUD = 460800  # the CH340 on macOS can't do 921600 (plan/DEVICE.md §7)
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
        others = sorted(glob.glob("/dev/cu.*"))
        raise DeviceError(f"no Boop board found on USB: nothing matches {', '.join(PORT_PATTERNS)}"
                          + (f" (serial ports here: {', '.join(others)})" if others else ""))
    return ports[0]


def port_holder(port: str) -> str:
    try:
        out = subprocess.run(["lsof", "-Fpc", port], text=True, capture_output=True, timeout=2).stdout
    except Exception:
        return ""
    return out.strip().replace("\n", " ")


class Link:
    """One JSON message per line in each direction: the board or boop-sim."""

    timeout = 3.0

    def __init__(self) -> None:
        self._buf = bytearray()

    def __enter__(self) -> "Link":
        return self

    def __exit__(self, *_: object) -> None:
        pass

    def _write(self, data: bytes) -> None:
        raise NotImplementedError

    def _read(self) -> bytes:
        """Whatever bytes are available now, possibly none."""
        raise NotImplementedError

    def send(self, message: dict[str, Any] | str) -> None:
        line = message if isinstance(message, str) else json.dumps(message, separators=(",", ":"))
        self._write(line.encode() + b"\n")

    def read_line(self, deadline: float) -> bytes | None:
        while time.monotonic() < deadline:
            nl = self._buf.find(b"\n")
            if nl >= 0:
                line = bytes(self._buf[:nl]).rstrip(b"\r")
                del self._buf[: nl + 1]
                return line
            chunk = self._read()
            if chunk:
                self._buf.extend(chunk)
            else:
                time.sleep(0.002)
        return None

    def wait_for(self, match: Callable[[dict[str, Any]], bool], timeout: float | None = None) -> dict[str, Any]:
        deadline = time.monotonic() + (timeout or self.timeout)
        while True:
            line = self.read_line(deadline)
            if line is None:
                raise DeviceError(f"timed out waiting for {self.name}")
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

    def shot(self) -> tuple[list[int], bytes, tuple[int, int]]:
        """The canvas: 256 RGB565 palette entries, one index per pixel, and
        the (width, height) from the header, so a PNG has the device's shape."""
        head = self.request({"t": "dbg.shot"}, timeout=5)
        line = self.read_line(time.monotonic() + 10)
        if line is None:
            raise DeviceError(f"screenshot data never arrived from {self.name}")
        raw = base64.b64decode(line)
        if len(raw) != head["bytes"] or zlib.crc32(raw) != head["crc"]:
            raise DeviceError(f"screenshot from {self.name} is corrupt ({len(raw)} of {head['bytes']} bytes)")
        palette = list(struct.unpack("<256H", raw[:512]))
        size = (int(head["w"]), int(head["h"]))
        if size[0] * size[1] != len(raw) - 512:
            raise DeviceError(f"screenshot from {self.name} is {size[0]}×{size[1]} but has {len(raw) - 512} pixels")
        return palette, raw[512:], size

    name = "the board"


class Sim(Link):
    """boop-sim as a subprocess: the device core on the Mac."""

    name = "boop-sim"

    def __init__(self, program: str) -> None:
        super().__init__()
        self._program = program
        self._proc: subprocess.Popen[bytes] | None = None

    def __enter__(self) -> "Sim":
        self._proc = subprocess.Popen([self._program], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        os.set_blocking(self._proc.stdout.fileno(), False)  # type: ignore[union-attr]
        return self

    def __exit__(self, *_: object) -> None:
        if self._proc:
            self._proc.stdin.close()  # type: ignore[union-attr]
            self._proc.wait(timeout=5)

    def _write(self, data: bytes) -> None:
        assert self._proc and self._proc.stdin
        self._proc.stdin.write(data)
        self._proc.stdin.flush()

    def _read(self) -> bytes:
        assert self._proc and self._proc.stdout
        try:
            return os.read(self._proc.stdout.fileno(), 65536)
        except BlockingIOError:
            return b""


class Device(Link):
    """A locked, open serial connection to the board, or, while
    `boopctl bridge` runs, a connection to the bridge's socket."""

    def __init__(self, port: str | None = None, timeout: float = 3.0, direct: bool = False) -> None:
        super().__init__()
        self.timeout = timeout
        self._ser: serial.Serial | None = None
        self._sock: socket.socket | None = None
        self._lock_fd: int | None = None
        from boopctl_lib.bridge import bridge_path, bridge_running

        self._bridged = not direct and not port and bridge_running()
        if self._bridged:
            self.port = bridge_path()
            self.name = f"the board through the bridge on {self.port}"
        else:
            self.port = port or find_port()
            self.name = f"the board on {self.port}"

    def __enter__(self) -> "Device":
        if self._bridged:
            self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self._sock.connect(self.port)
            self._sock.setblocking(False)
            return self
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", Path(self.port).name)
        self._lock_fd = os.open(f"/tmp/boopctl-{safe}.lock", os.O_CREAT | os.O_RDWR, 0o666)
        fcntl.flock(self._lock_fd, fcntl.LOCK_EX)
        try:
            # Leave DTR and RTS as macOS sets them on open (both asserted).
            # Changing one before the other pulses EN through the board's
            # auto-reset circuit and reboots it.
            ser = serial.Serial()
            ser.port, ser.baudrate, ser.timeout = self.port, BAUD, 0
            ser.open()
            self._ser = ser
        except serial.SerialException as exc:
            holder = port_holder(self.port)
            raise DeviceError(f"can't open {self.port}: {exc}" + (f" (held by {holder})" if holder else ""))
        self._ser.reset_input_buffer()
        return self

    def __exit__(self, *_: object) -> None:
        if self._sock is not None:
            self._sock.close()
        if self._ser is not None:
            self._ser.close()
        if self._lock_fd is not None:
            fcntl.flock(self._lock_fd, fcntl.LOCK_UN)
            os.close(self._lock_fd)

    def _write(self, data: bytes) -> None:
        if self._sock is not None:
            self._sock.setblocking(True)
            self._sock.sendall(data)
            self._sock.setblocking(False)
            return
        assert self._ser is not None
        self._ser.write(data)
        self._ser.flush()

    def _read(self) -> bytes:
        if self._sock is not None:
            try:
                data = self._sock.recv(65536)
            except BlockingIOError:
                return b""
            if not data:
                raise DeviceError("the bridge closed the connection")
            return data
        assert self._ser is not None
        return self._ser.read(65536)
