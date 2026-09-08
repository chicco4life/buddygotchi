#!/usr/bin/env python3
# /// script
# dependencies = ["bleak>=0.22", "pyserial>=3.5", "pytest>=8.0"]
# ///
"""Unified host control tool for the ESP32 Buddy hardware."""

from __future__ import annotations

import argparse
import asyncio
import base64
import fcntl
import glob
import json
import os
import re
import struct
import subprocess
import sys
import termios
import time
import zlib
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
NUS_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
NUS_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"


class BuddyError(Exception):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


def emit(obj: dict[str, Any], as_json: bool = False) -> None:
    if as_json:
        print(json.dumps(obj, separators=(",", ":"), sort_keys=True))
    else:
        print(json.dumps(obj, indent=2, sort_keys=True))


def find_port() -> str:
    for pat in ("/dev/cu.usbserial-*", "/dev/cu.wchusbserial*", "/dev/cu.usbmodem*"):
        ports = sorted(glob.glob(pat))
        if ports:
            return ports[0]
    raise BuddyError("no ESP32 serial port found", 2)


def lock_path(port: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", Path(port).name)
    return Path("/tmp") / f"buddyctl-{safe}.lock"


class SerialBuddy:
    def __init__(self, port: str | None = None, timeout: float = 5.0) -> None:
        self.port = port or find_port()
        self.timeout = timeout
        self.fd: int | None = None
        self.lock_fd: int | None = None

    def __enter__(self) -> "SerialBuddy":
        self.lock_fd = os.open(lock_path(self.port), os.O_CREAT | os.O_RDWR, 0o666)
        fcntl.flock(self.lock_fd, fcntl.LOCK_EX)
        try:
            self.fd = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        except OSError as exc:
            holder = port_holder(self.port)
            suffix = f" holder={holder}" if holder else ""
            raise BuddyError(f"failed to open {self.port}: {exc}{suffix}", 2)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = termios.IGNBRK
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = termios.B115200
        attrs[5] = termios.B115200
        cc = list(attrs[6])
        cc[termios.VMIN] = 0
        cc[termios.VTIME] = 0
        attrs[6] = cc
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)
        self.drain_until_quiet()
        return self

    def __exit__(self, *_: object) -> None:
        if self.fd is not None:
            os.close(self.fd)
        if self.lock_fd is not None:
            fcntl.flock(self.lock_fd, fcntl.LOCK_UN)
            os.close(self.lock_fd)

    def read_some(self) -> bytes:
        assert self.fd is not None
        try:
            return os.read(self.fd, 8192)
        except BlockingIOError:
            return b""

    def write_line(self, line: str) -> None:
        assert self.fd is not None
        # The fd is non-blocking; at 115200 baud a burst of large lines
        # fills the kernel TX buffer and os.write raises EAGAIN (and may
        # write partially). Spin until the whole line is out.
        data = line.encode("utf-8") + b"\n"
        while data:
            try:
                n = os.write(self.fd, data)
                data = data[n:]
            except BlockingIOError:
                time.sleep(0.005)

    def drain_until_quiet(self, quiet: float = 0.2, max_wait: float = 2.0) -> bytes:
        out = bytearray()
        start = time.monotonic()
        last = start
        while time.monotonic() - start < max_wait:
            chunk = self.read_some()
            if chunk:
                out.extend(chunk)
                last = time.monotonic()
            elif time.monotonic() - last >= quiet:
                break
            else:
                time.sleep(0.01)
        return bytes(out)

    def read_until(self, predicate: Callable[[bytes], Any], timeout: float | None = None) -> tuple[bytes, Any]:
        buf = bytearray()
        deadline = time.monotonic() + (timeout or self.timeout)
        while time.monotonic() < deadline:
            chunk = self.read_some()
            if chunk:
                buf.extend(chunk)
                result = predicate(bytes(buf))
                if result:
                    return bytes(buf), result
            else:
                time.sleep(0.01)
        raise BuddyError(f"timeout waiting for device response on {self.port}", 2)

    def framed_json(self, command: str, tag: str, timeout: float | None = None) -> dict[str, Any]:
        self.write_line(command)
        pattern = re.compile(rb"<<" + tag.encode() + rb"\s+(\{.*?\})>>", re.DOTALL)
        _, match = self.read_until(lambda b: pattern.search(b), timeout)
        return json.loads(match.group(1).decode("utf-8"))


def port_holder(port: str) -> str:
    try:
        cp = subprocess.run(["lsof", "-FnPc", port], text=True, capture_output=True, timeout=2)
    except Exception:
        return ""
    return cp.stdout.strip().replace("\n", " ")


def rgb565le_to_rgb888(buf: bytes, w: int, h: int) -> bytes:
    if len(buf) != w * h * 2:
        raise ValueError(f"expected {w*h*2} RGB565 bytes, got {len(buf)}")
    out = bytearray(w * h * 3)
    o = 0
    for i in range(0, len(buf), 2):
        v = buf[i] | (buf[i + 1] << 8)
        r5 = (v >> 11) & 0x1F
        g6 = (v >> 5) & 0x3F
        b5 = v & 0x1F
        out[o] = (r5 << 3) | (r5 >> 2)
        out[o + 1] = (g6 << 2) | (g6 >> 4)
        out[o + 2] = (b5 << 3) | (b5 >> 2)
        o += 3
    return bytes(out)


def epx2x_rgb(rgb: bytes, w: int, h: int) -> tuple[bytes, int, int]:
    """EPX/Scale2x upscale, matching the firmware's halPresent expand —
    previews what the panel shows (device screenshots dump the pre-upscale
    sprite). Copies neighbor colors, never blends."""
    out = bytearray(w * h * 12)
    ow = w * 2
    def px(x: int, y: int) -> bytes:
        o = (y * w + x) * 3
        return rgb[o : o + 3]
    for y in range(h):
        up, dn = max(y - 1, 0), min(y + 1, h - 1)
        for x in range(w):
            lt, rt = max(x - 1, 0), min(x + 1, w - 1)
            P = px(x, y)
            A, B, C, D = px(x, up), px(rt, y), px(lt, y), px(x, dn)
            e0 = A if (C == A and C != D and A != B) else P
            e1 = B if (A == B and A != C and B != D) else P
            e2 = C if (D == C and D != B and C != A) else P
            e3 = D if (B == D and B != A and D != C) else P
            o0 = (y * 2 * ow + x * 2) * 3
            o1 = ((y * 2 + 1) * ow + x * 2) * 3
            out[o0 : o0 + 3] = e0
            out[o0 + 3 : o0 + 6] = e1
            out[o1 : o1 + 3] = e2
            out[o1 + 3 : o1 + 6] = e3
    return bytes(out), ow, h * 2


def scale_rgb(rgb: bytes, w: int, h: int, scale: int) -> tuple[bytes, int, int]:
    if scale <= 1:
        return rgb, w, h
    row = w * 3
    out = bytearray(w * h * 3 * scale * scale)
    dst_row = w * scale * 3
    for y in range(h):
        expanded = bytearray()
        src = rgb[y * row : (y + 1) * row]
        for x in range(w):
            px = src[x * 3 : x * 3 + 3]
            expanded.extend(px * scale)
        for sy in range(scale):
            start = (y * scale + sy) * dst_row
            out[start : start + dst_row] = expanded
    return bytes(out), w * scale, h * scale


def write_png(path: Path, w: int, h: int, rgb: bytes) -> None:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw.extend(rgb[y * stride : (y + 1) * stride])
    with path.open("wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        f.write(chunk(b"IEND", b""))


def heartbeat_from_args(args: argparse.Namespace) -> dict[str, Any]:
    payload: dict[str, Any] = {"v": 2}
    for key in ("state", "effort", "cheer", "uhoh", "bubble", "gift", "giftLine", "focus", "mute", "posture", "dots", "overlay", "greetLevel", "dotAlert", "t"):
        value = getattr(args, key, None)
        if value is not None:
            payload[key] = value
    if getattr(args, "pet", None) and "state" not in payload:
        payload["state"] = {"sleep": "asleep", "busy": "working", "attention": "needsYou", "celebrate": "done", "error": "uhoh", "thinking": "uhoh", "heart": "idle"}.get(args.pet, args.pet)
    card = {}
    for key in ("id", "tool", "gloss", "stakes", "n", "of", "approval"):
        value = getattr(args, "card_" + key, None)
        if value is not None:
            card[key] = value
    for old, new in (("prompt_id", "id"), ("prompt_tool", "tool"), ("prompt_hint", "gloss")):
        value = getattr(args, old, None)
        if value is not None:
            card.setdefault(new, value)
    if card:
        payload["card"] = {"id": "req_buddyctl", "tool": "", "gloss": "", "stakes": "checkIt", "n": 1, "of": 1, "approval": True, **card}
        payload.setdefault("state", "needsYou")
    snap = {}
    for key in ("name", "level", "xp", "xpNext", "streak", "best", "rest", "days", "tasks", "today", "biggest"):
        value = getattr(args, "snap_" + key, None)
        if value is not None:
            snap[key] = value
    if snap:
        payload["snap"] = {"name": "Boop", "level": 0, "xp": 0, "xpNext": 0, "streak": 0, "best": 0, "rest": 0, "days": 0, "tasks": 0, "today": 0, "biggest": "hop", **snap}
    if getattr(args, "msg", None) is not None:
        payload.setdefault("bubble", args.msg)
    return payload


def command_ping(args: argparse.Namespace) -> int:
    with SerialBuddy(args.port, args.timeout) as buddy:
        data = buddy.framed_json("ping", "PONG")
    emit({"ok": True, "port": args.port or "auto", "pong": data}, args.json)
    return 0


def command_state(args: argparse.Namespace) -> int:
    with SerialBuddy(args.port, args.timeout) as buddy:
        data = buddy.framed_json("state", "STATE")
    emit({"ok": True, "state": data}, args.json)
    return 0


def parse_screenshot(buf: bytes) -> Any:
    begin = re.search(rb"<<SCR_BEGIN\s+W=(\d+)\s+H=(\d+)\s+ROT=(\d+)\s+FMT=RGB565LE>>", buf)
    if not begin:
        return None
    end = re.search(rb"<<SCR_END(?:\s+LEN=(\d+)\s+CRC32=([0-9a-fA-F]{8}))?>>", buf[begin.end() :])
    if not end:
        return None
    return begin, begin.end(), begin.end() + end.start(), end


def capture_screenshot(args: argparse.Namespace) -> dict[str, Any]:
    last_error = ""
    for attempt in range(1, args.retry + 1):
        with SerialBuddy(args.port, args.timeout) as buddy:
            buddy.write_line("screenshot")
            try:
                buf, parsed = buddy.read_until(parse_screenshot, args.timeout)
            except BuddyError as exc:
                last_error = str(exc)
                continue
        begin, body_start, _body_end, end = parsed
        w = int(begin.group(1))
        h = int(begin.group(2))
        rot = int(begin.group(3))
        body = re.sub(rb"\s+", b"", buf[body_start : body_start + end.start()])
        try:
            raw = base64.b64decode(body, validate=True)
        except Exception as exc:
            last_error = f"base64 decode failed: {exc}"
            continue
        if end.group(1):
            want_len = int(end.group(1))
            want_crc = int(end.group(2), 16)
            got_crc = zlib.crc32(raw) & 0xFFFFFFFF
            if len(raw) != want_len or got_crc != want_crc:
                last_error = f"integrity mismatch len={len(raw)}/{want_len} crc={got_crc:08x}/{want_crc:08x}"
                continue
        expected = w * h * 2
        if len(raw) != expected:
            last_error = f"decoded {len(raw)} bytes, expected {expected}"
            continue
        rgb = rgb565le_to_rgb888(raw, w, h)
        scale = args.scale
        if getattr(args, "epx", False):
            rgb, w2, h2 = epx2x_rgb(rgb, w, h)
            scale = max(1, scale // 2)
            out_rgb, out_w, out_h = scale_rgb(rgb, w2, h2, scale)
        else:
            out_rgb, out_w, out_h = scale_rgb(rgb, w, h, scale)
        out = Path(args.out)
        write_png(out, out_w, out_h, out_rgb)
        return {"ok": True, "out": str(out), "w": w, "h": h, "rot": rot, "scale": args.scale, "attempt": attempt}
    raise BuddyError(last_error or "screenshot failed", 2)


def command_screenshot(args: argparse.Namespace) -> int:
    emit(capture_screenshot(args), args.json)
    return 0


def command_press(args: argparse.Namespace) -> int:
    timeout = max(args.timeout, args.ms / 1000 + 1.0)
    with SerialBuddy(args.port, timeout) as buddy:
        buddy.write_line(f"press {args.button.lower()} {args.ms}")
        _, _ = buddy.read_until(lambda b: f"<<PRESS {args.button.lower()} up>>".encode() in b, timeout)
        tail = buddy.drain_until_quiet(max_wait=0.5).decode("utf-8", "replace")
    emit({"ok": True, "button": args.button.lower(), "ms": args.ms, "tail": tail}, args.json)
    return 0


def command_btn(args: argparse.Namespace) -> int:
    with SerialBuddy(args.port, args.timeout) as buddy:
        if args.mock:
            buddy.write_line("mockprompt")
            buddy.read_until(lambda b: b"<<BTN mockprompt armed>>" in b, 2)
        buddy.write_line(f"btn {args.button.lower()}")
        buf, _ = buddy.read_until(lambda b: b"<<BTN" in b, args.timeout)
        text = buf.decode("utf-8", "replace")
        tail = buddy.drain_until_quiet(max_wait=0.5).decode("utf-8", "replace")
    emit({"ok": True, "button": args.button.lower(), "mock": args.mock, "response": text + tail}, args.json)
    return 0


def command_inject(args: argparse.Namespace) -> int:
    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError as exc:
        raise BuddyError(f"invalid JSON: {exc}", 1)
    with SerialBuddy(args.port, args.timeout) as buddy:
        buddy.write_line(json.dumps(payload, separators=(",", ":")))
    emit({"ok": True, "sent": payload}, args.json)
    return 0


def command_frame(args: argparse.Namespace) -> int:
    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError as exc:
        raise BuddyError(f"invalid JSON: {exc}", 1)
    if not isinstance(payload, dict) or type(payload.get("v")) is not int or payload["v"] != 2:
        raise BuddyError("frame must be a v2 JSON object", 1)
    if args.t is not None:
        payload["t"] = args.t
    line = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    if len(line.encode("utf-8")) + 1 > 1536:
        raise BuddyError("frame exceeds 1536 bytes including newline", 1)
    with SerialBuddy(args.port, args.timeout) as buddy:
        if args.t is not None:
            buddy.write_line(f"clock {args.t}")
        buddy.write_line(line)
        state = buddy.framed_json("state", "STATE")
    emit({"ok": True, "state": state}, args.json)
    return 0


def command_set(args: argparse.Namespace) -> int:
    args.payload = json.dumps(heartbeat_from_args(args), ensure_ascii=False)
    return command_frame(args)


def predicate_items(args: argparse.Namespace) -> dict[str, Any]:
    mapping = {
        "creature": args.state,
        "pet": args.pet,
        "species": args.species,
        "desktop": args.desktop,
        "connected": args.connected,
        "total": args.total,
        "running": args.running,
        "waiting": args.waiting,
        "promptId": args.prompt_id,
        "promptTool": args.prompt_tool,
        "screen": args.screen,
        "mode": args.mode,
        "rtcValid": args.rtc_valid,
        "responseSent": args.response_sent,
    }
    return {k: v for k, v in mapping.items() if v is not None}


def command_expect(args: argparse.Namespace) -> int:
    want = predicate_items(args)
    if not want:
        raise BuddyError("no predicates supplied", 1)
    deadline = time.monotonic() + args.timeout
    last: dict[str, Any] = {}
    while time.monotonic() < deadline:
        with SerialBuddy(args.port, 2) as buddy:
            last = buddy.framed_json("state", "STATE", 2)
        if all(last.get(key) == value for key, value in want.items()):
            emit({"ok": True, "matched": want, "state": last}, args.json)
            return 0
        time.sleep(args.interval)
    emit({"ok": False, "matched": want, "state": last}, args.json)
    return 1


def command_monitor(args: argparse.Namespace) -> int:
    pattern = re.compile(args.until) if args.until else None
    deadline = time.monotonic() + args.secs if args.secs else None
    with SerialBuddy(args.port, args.timeout) as buddy:
        while True:
            if deadline and time.monotonic() >= deadline:
                return 0
            chunk = buddy.read_some()
            if chunk:
                text = chunk.decode("utf-8", "replace")
                print(text, end="", flush=True)
                if pattern and pattern.search(text):
                    return 0
            else:
                time.sleep(0.02)


def local_git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        return "unknown"


def command_flash(args: argparse.Namespace) -> int:
    cmd = ["pio", "run", "-e", args.env, "-t", "upload"]
    cp = subprocess.run(cmd, cwd=ROOT, text=True)
    if cp.returncode != 0:
        return 2
    deadline = time.monotonic() + args.timeout
    last: dict[str, Any] = {}
    while time.monotonic() < deadline:
        try:
            with SerialBuddy(args.port, 2) as buddy:
                last = buddy.framed_json("ping", "PONG", 2)
            break
        except BuddyError:
            time.sleep(0.5)
    else:
        raise BuddyError("flash finished but ping did not respond", 2)
    want = local_git_sha()
    ok = want == "unknown" or last.get("git") == want
    emit({"ok": ok, "expectedGit": want, "pong": last}, args.json)
    return 0 if ok else 1


def command_reboot(args: argparse.Namespace) -> int:
    with SerialBuddy(args.port, args.timeout) as buddy:
        buddy.write_line("reboot")
        buddy.read_until(lambda b: b"<<REBOOT ok>>" in b, 2)
    deadline = time.monotonic() + args.timeout
    last: dict[str, Any] = {}
    while time.monotonic() < deadline:
        try:
            with SerialBuddy(args.port, 2) as buddy:
                last = buddy.framed_json("ping", "PONG", 2)
            emit({"ok": True, "pong": last}, args.json)
            return 0
        except BuddyError:
            time.sleep(0.5)
    raise BuddyError("device did not return after reboot", 2)


async def ble_scan(args: argparse.Namespace) -> int:
    from bleak import BleakScanner

    devices = await BleakScanner.discover(timeout=args.timeout, return_adv=True)
    rows = []
    for device, adv in devices.values():
        name = device.name or adv.local_name or ""
        uuids = {u.lower() for u in (adv.service_uuids or [])}
        if args.all or name.startswith("Claude") or NUS_SERVICE_UUID in uuids:
            rows.append({"name": name, "address": device.address, "rssi": adv.rssi})
    emit({"ok": True, "devices": rows}, args.json)
    return 0


async def find_ble_address(args: argparse.Namespace) -> str:
    if args.address:
        return args.address
    from bleak import BleakScanner

    devices = await BleakScanner.discover(timeout=args.timeout, return_adv=True)
    for device, adv in devices.values():
        name = device.name or adv.local_name or ""
        uuids = {u.lower() for u in (adv.service_uuids or [])}
        if name.startswith(args.name) or NUS_SERVICE_UUID in uuids:
            return device.address
    raise BuddyError(f"no BLE buddy found matching {args.name!r}", 2)


async def ble_collect(args: argparse.Namespace, frames: list[dict[str, Any]]) -> list[dict[str, Any]]:
    from bleak import BleakClient

    address = await find_ble_address(args)
    lines: list[dict[str, Any]] = []
    text = bytearray()
    until = re.compile(args.until) if getattr(args, "until", None) else None
    done = asyncio.Event()

    def on_notify(_: int, data: bytearray) -> None:
        nonlocal text
        text.extend(data)
        while b"\n" in text:
            raw, _, rest = text.partition(b"\n")
            text = bytearray(rest)
            line = raw.decode("utf-8", "replace")
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                obj = {"raw": line}
            lines.append(obj)
            if until and until.search(line):
                done.set()

    async with BleakClient(address, timeout=args.timeout) as client:
        await client.start_notify(NUS_TX_UUID, on_notify)
        for frame in frames:
            payload = json.dumps(frame, separators=(",", ":")).encode() + b"\n"
            for i in range(0, len(payload), 180):
                await client.write_gatt_char(NUS_RX_UUID, payload[i : i + 180], response=False)
        secs = getattr(args, "secs", None)
        if until:
            try:
                await asyncio.wait_for(done.wait(), timeout=secs or args.timeout)
            except asyncio.TimeoutError:
                pass
        elif secs:
            await asyncio.sleep(secs)
        else:
            await asyncio.sleep(1)
        await client.stop_notify(NUS_TX_UUID)
    return lines


async def ble_send(args: argparse.Namespace) -> int:
    payload = json.loads(args.payload)
    lines = await ble_collect(args, [payload])
    emit({"ok": True, "sent": payload, "received": lines}, args.json)
    return 0


async def ble_set(args: argparse.Namespace) -> int:
    payload = heartbeat_from_args(args)
    if not payload:
        raise BuddyError("no heartbeat fields supplied", 1)
    args.payload = json.dumps(payload, separators=(",", ":"))
    return await ble_send(args)


async def ble_listen(args: argparse.Namespace) -> int:
    lines = await ble_collect(args, [])
    emit({"ok": True, "received": lines}, args.json)
    return 0


async def ble_status(args: argparse.Namespace) -> int:
    args.until = r'"ack"\s*:\s*"status"'
    args.secs = args.timeout
    lines = await ble_collect(args, [{"cmd": "status"}])
    ok = any(line.get("ack") == "status" and line.get("ok") is True for line in lines)
    emit({"ok": ok, "received": lines}, args.json)
    return 0 if ok else 1


async def ble_timesync(args: argparse.Namespace) -> int:
    now = int(time.time())
    offset = -time.timezone if (time.localtime().tm_isdst == 0) else -time.altzone
    lines = await ble_collect(args, [{"time": [now, offset]}])
    emit({"ok": True, "sent": {"time": [now, offset]}, "received": lines}, args.json)
    return 0


async def ble_prompt(args: argparse.Namespace) -> int:
    payload = {"v": 2, "state": "needsYou", "card": {
        "id": args.id, "tool": args.tool, "gloss": args.hint,
        "stakes": "checkIt", "n": 1, "of": 1, "approval": True}}
    args.until = r'"cmd"\s*:\s*"(?:decision|permission)"'
    args.secs = args.timeout if args.wait_decision else 1
    lines = await ble_collect(args, [payload])
    decision = next((line for line in lines if line.get("cmd") in ("decision", "permission") and line.get("id") == args.id), None)
    ok = decision is not None if args.wait_decision else True
    emit({"ok": ok, "sent": payload, "decision": decision, "received": lines}, args.json)
    return 0 if ok else 1


async def ble_pair(args: argparse.Namespace) -> int:
    from bleak import BleakClient

    passkey = ""
    if args.port:
        with SerialBuddy(args.port, args.timeout) as buddy:
            buddy.drain_until_quiet(max_wait=0.1)
            address = await find_ble_address(args)
            async with BleakClient(address, timeout=args.timeout) as client:
                pair = getattr(client, "pair", None)
                if pair:
                    await pair()
                serial = buddy.drain_until_quiet(max_wait=args.timeout).decode("utf-8", "replace")
                m = re.search(r"\[ble\]\s+passkey\s+(\d{6})", serial)
                passkey = m.group(1) if m else ""
    else:
        address = await find_ble_address(args)
        async with BleakClient(address, timeout=args.timeout) as client:
            pair = getattr(client, "pair", None)
            if pair:
                await pair()
    emit({"ok": True, "passkey": passkey or None}, args.json)
    return 0


def parse_bool(value: str) -> bool:
    if value.lower() in ("1", "true", "yes"):
        return True
    if value.lower() in ("0", "false", "no"):
        return False
    raise argparse.ArgumentTypeError("expected true/false or 1/0")


def add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--port", default=None)
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--json", action="store_true")


def add_heartbeat_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--state", choices=["asleep", "idle", "working", "needsYou", "done", "uhoh"])
    for key, choices in (("effort", ["light", "hard", "grinding"]), ("cheer", ["hop", "cheer", "dance"]), ("uhoh", ["error", "stuck", "hungry"]), ("posture", ["desk", "perch", "travel"]), ("overlay", ["greet", "boop"])):
        p.add_argument("--" + key, choices=choices)
    p.add_argument("--bubble")
    p.add_argument("--gift-line", dest="giftLine")
    for key in ("gift", "focus"):
        p.add_argument("--" + key, type=parse_bool, nargs="?", const=True)
    for key, dest in (("t", "t"), ("mute", "mute"), ("dots", "dots"), ("dot-alert", "dotAlert"), ("greet-level", "greetLevel")):
        p.add_argument("--" + key, dest=dest, type=int)
    for key in ("id", "tool", "gloss"):
        p.add_argument("--card-" + key)
    p.add_argument("--card-stakes", choices=["fine", "checkIt", "careful"])
    for key in ("n", "of"):
        p.add_argument("--card-" + key, type=int)
    p.add_argument("--card-approval", type=parse_bool)
    p.add_argument("--snap-name")
    p.add_argument("--snap-biggest", choices=["hop", "cheer", "dance"])
    for key in ("level", "xp", "xpNext", "streak", "best", "rest", "days", "tasks", "today"):
        p.add_argument("--snap-" + ("xp-next" if key == "xpNext" else key), dest="snap_" + key, type=int)
    p.add_argument("--pet")
    p.add_argument("--species")
    p.add_argument("--desktop")
    p.add_argument("--total", type=int)
    p.add_argument("--running", type=int)
    p.add_argument("--waiting", type=int)
    p.add_argument("--msg")
    p.add_argument("--activity")
    p.add_argument("--entries", action="append")
    p.add_argument("--prompt-id")
    p.add_argument("--prompt-tool")
    p.add_argument("--prompt-hint")
    p.add_argument("--prompt-source")


def add_expect_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--state")
    p.add_argument("--pet")
    p.add_argument("--species")
    p.add_argument("--desktop")
    p.add_argument("--connected", type=lambda v: v.lower() in ("1", "true", "yes"))
    p.add_argument("--total", type=int)
    p.add_argument("--running", type=int)
    p.add_argument("--waiting", type=int)
    p.add_argument("--prompt-id")
    p.add_argument("--prompt-tool")
    p.add_argument("--screen")
    p.add_argument("--mode")
    p.add_argument("--rtc-valid", type=lambda v: v.lower() in ("1", "true", "yes"))
    p.add_argument("--response-sent", type=lambda v: v.lower() in ("1", "true", "yes"))


def add_ble_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--address")
    p.add_argument("--name", default="Claude")
    p.add_argument("--timeout", type=float, default=8.0)
    p.add_argument("--json", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, fn in (("ping", command_ping), ("state", command_state)):
        p = sub.add_parser(name)
        add_common(p)
        p.set_defaults(func=fn)
    p = sub.add_parser("screenshot")
    p.add_argument("--epx", action="store_true")
    add_common(p)
    # ~86 KB base64 dump takes ~8 s at 115200 baud; the shared 5 s default
    # times out mid-transfer.
    p.set_defaults(timeout=15.0)
    p.add_argument("--out", default="screenshot.png")
    p.add_argument("--scale", type=int, default=1)
    p.add_argument("--retry", type=int, default=3)
    p.set_defaults(func=command_screenshot)
    p = sub.add_parser("press")
    add_common(p)
    p.add_argument("button", choices=["a", "b", "m", "A", "B", "M"])
    p.add_argument("--ms", type=int, default=150)
    p.set_defaults(func=command_press)
    p = sub.add_parser("btn")
    add_common(p)
    p.add_argument("button", choices=["a", "b", "A", "B"])
    p.add_argument("--mock", action="store_true")
    p.set_defaults(func=command_btn)
    p = sub.add_parser("inject")
    add_common(p)
    p.add_argument("payload")
    p.set_defaults(func=command_inject)
    p = sub.add_parser("frame")
    p.add_argument("--port", default=None)
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--json", dest="payload", required=True)
    p.add_argument("--t", type=int)
    p.set_defaults(func=command_frame, json=True)
    p = sub.add_parser("set")
    add_common(p)
    add_heartbeat_args(p)
    p.set_defaults(func=command_set)
    p = sub.add_parser("expect")
    add_common(p)
    add_expect_args(p)
    p.add_argument("--interval", type=float, default=0.25)
    p.set_defaults(func=command_expect)
    p = sub.add_parser("monitor")
    add_common(p)
    p.add_argument("--secs", type=float)
    p.add_argument("--until")
    p.set_defaults(func=command_monitor)
    p = sub.add_parser("flash")
    add_common(p)
    p.add_argument("--env", default="m5stickc-plus")
    p.set_defaults(func=command_flash)
    p = sub.add_parser("reboot")
    add_common(p)
    p.set_defaults(func=command_reboot)

    ble = sub.add_parser("ble")
    ble_sub = ble.add_subparsers(dest="ble_cmd", required=True)
    p = ble_sub.add_parser("scan")
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--json", action="store_true")
    p.add_argument("--all", action="store_true")
    p.set_defaults(func=lambda a: asyncio.run(ble_scan(a)))
    p = ble_sub.add_parser("pair")
    add_ble_common(p)
    p.add_argument("--port")
    p.set_defaults(func=lambda a: asyncio.run(ble_pair(a)))
    p = ble_sub.add_parser("send")
    add_ble_common(p)
    p.add_argument("payload")
    p.add_argument("--secs", type=float, default=1.0)
    p.add_argument("--until")
    p.set_defaults(func=lambda a: asyncio.run(ble_send(a)))
    p = ble_sub.add_parser("set")
    add_ble_common(p)
    add_heartbeat_args(p)
    p.add_argument("--secs", type=float, default=1.0)
    p.add_argument("--until")
    p.set_defaults(func=lambda a: asyncio.run(ble_set(a)))
    p = ble_sub.add_parser("listen")
    add_ble_common(p)
    p.add_argument("--secs", type=float, default=5.0)
    p.add_argument("--until")
    p.set_defaults(func=lambda a: asyncio.run(ble_listen(a)))
    p = ble_sub.add_parser("status")
    add_ble_common(p)
    p.set_defaults(func=lambda a: asyncio.run(ble_status(a)))
    p = ble_sub.add_parser("timesync")
    add_ble_common(p)
    p.set_defaults(func=lambda a: asyncio.run(ble_timesync(a)))
    p = ble_sub.add_parser("prompt")
    add_ble_common(p)
    p.add_argument("--id", default="req_buddyctl")
    p.add_argument("--tool", default="Bash")
    p.add_argument("--hint", default="npm test")
    p.add_argument("--wait-decision", action="store_true")
    p.set_defaults(func=lambda a: asyncio.run(ble_prompt(a)))
    return ap


def main() -> int:
    args = build_parser().parse_args()
    try:
        return args.func(args)
    except BuddyError as exc:
        emit({"ok": False, "error": str(exc)}, getattr(args, "json", False))
        return exc.code
    except ImportError as exc:
        emit({"ok": False, "error": f"missing dependency: {exc}"}, getattr(args, "json", False))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
