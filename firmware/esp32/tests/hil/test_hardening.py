"""Hardening HIL tests: heap headroom, crash telemetry, reboot soak,
serial fuzz, and watchdog recovery.

These exist because of a 2026-07 field-class bug: a 16bpp sprite silently
ate heap until a bonded BLE reconnect OOMed inside Bluedroid and
bootlooped the device. The tests here are the regression gates for that
class of failure:

  - heap gate: fails if boot-time headroom regresses below safe margins
  - reboot soak: fails if any boot panics or wedges
  - serial fuzz: garbage on the command channel must never crash or hang
  - wdt recovery: a deliberately hung loop() must reboot on its own

Run: cd firmware/esp32 && python3 -m pytest tests/hil/test_hardening.py
The wdt test waits out the 30s watchdog — it's marked slow.
"""

from __future__ import annotations

import json
import os
import random
import sys
import time
from pathlib import Path

import pytest


TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))
import buddyctl  # noqa: E402


# Boot-time floors, in bytes. The 2026-07 OOM happened at heap=17K /
# heapBig=12K; a BLE connect burst needs several contiguous KB. Current
# M5 firmware boots around heap=49K / heapBig=35K, so these floors leave
# room for growth while still catching a sprite-sized (32K) regression.
# The env overrides exist for other boards (the S3 AMOLED board has far
# more headroom and gets its own baselines once measured on hardware).
HEAP_FLOOR = int(os.environ.get("BUDDY_HEAP_FLOOR", "40000"))
HEAP_BIG_FLOOR = int(os.environ.get("BUDDY_HEAP_BIG_FLOOR", "28000"))

FUZZ_SEED = int(os.environ.get("BUDDY_FUZZ_SEED", "1337"))
FUZZ_LINES = int(os.environ.get("BUDDY_FUZZ_LINES", "200"))
SOAK_CYCLES = int(os.environ.get("BUDDY_SOAK_CYCLES", "5"))

# Commands the fuzzer must never emit verbatim (they'd legitimately
# reboot or wedge the device and fail the "still alive" oracle).
FORBIDDEN_LINES = {b"reboot", b"hang", b"screenshot", b"guardclear", b"clearbonds"}


# Module scope, not session: SerialBuddy holds a blocking flock on the
# port for the fixture's lifetime, and test_usb.py's own session fixture
# would deadlock behind a session-scoped one here.
@pytest.fixture(scope="module")
def stick():
    try:
        port = buddyctl.find_port()
        serial = buddyctl.SerialBuddy(port, timeout=5)
        serial.__enter__()
        serial.framed_json("ping", "PONG", 3)
    except buddyctl.BuddyError as exc:
        pytest.skip(f"no ESP32 Buddy attached: {exc}")
    try:
        yield serial
    finally:
        serial.__exit__(None, None, None)


def ping(stick) -> dict:
    return stick.framed_json("ping", "PONG", 3)


def ping_retry(stick, deadline_s: float) -> dict:
    """Ping until the device answers (used across reboots)."""
    deadline = time.monotonic() + deadline_s
    last_exc: Exception | None = None
    while time.monotonic() < deadline:
        try:
            return stick.framed_json("ping", "PONG", 2)
        except Exception as exc:  # port hiccup or device mid-boot
            last_exc = exc
            time.sleep(0.5)
    pytest.fail(f"device did not answer ping within {deadline_s}s: {last_exc}")


# --- heap headroom gate --------------------------------------------------


def test_heap_headroom(stick):
    pong = ping(stick)
    assert pong["heap"] >= HEAP_FLOOR, (
        f"free heap {pong['heap']} below {HEAP_FLOOR} — headroom regression; "
        "a BLE connect burst may OOM (see 2026-07 bootloop)"
    )
    assert pong["heapBig"] >= HEAP_BIG_FLOOR, (
        f"largest free block {pong['heapBig']} below {HEAP_BIG_FLOOR} — "
        "fragmentation or a big new allocation"
    )


def test_reset_telemetry_present(stick):
    pong = ping(stick)
    assert pong["reset"] in {
        "poweron", "sw", "panic", "task_wdt", "int_wdt", "wdt",
        "brownout", "deepsleep", "ext", "unknown",
    }
    assert isinstance(pong["panics"], int)
    assert isinstance(pong["early"], int)
    assert pong["safe"] in (0, 1, 2)


# --- reboot soak ---------------------------------------------------------


def test_reboot_soak_no_panics(stick):
    """Commanded reboots must come back clean: sw reset reason, no new
    panics, device answering within a bounded window. Crank
    BUDDY_SOAK_CYCLES=200 for a pre-ship soak."""
    baseline = ping(stick)["panics"]
    for cycle in range(SOAK_CYCLES):
        stick.write_line("reboot")
        time.sleep(2.0)  # boot + splash before the port is useful again
        pong = ping_retry(stick, 20)
        assert pong["up"] < 60_000, f"cycle {cycle}: device did not actually reboot"
        assert pong["reset"] == "sw", (
            f"cycle {cycle}: expected clean sw reset, got {pong['reset']!r}"
        )
        assert pong["panics"] == baseline, (
            f"cycle {cycle}: panic count rose {baseline} -> {pong['panics']}"
        )
        assert pong["safe"] == 0, f"cycle {cycle}: device entered safe mode"


# --- serial fuzz ---------------------------------------------------------


def _fuzz_lines(rng: random.Random, n: int):
    """Adversarial lines for the USB command channel: binary garbage,
    oversized lines (the parser buffers 2048), malformed JSON, and
    truncated real-command prefixes."""
    real_prefixes = [b"press ", b"btn ", b"ping", b"state", b"{", b"screenshot "]
    for _ in range(n):
        kind = rng.randrange(5)
        if kind == 0:  # raw binary, newline-free
            line = bytes(rng.choice([b for b in range(256) if b not in (10, 13)])
                         for _ in range(rng.randrange(1, 120)))
        elif kind == 1:  # oversized printable line (overflows the 2048 buffer)
            line = bytes(rng.randrange(32, 127) for _ in range(rng.randrange(2000, 5000)))
        elif kind == 2:  # malformed JSON
            base = b'{"total":1,"pet":"idle"'
            line = base + bytes(rng.randrange(32, 127) for _ in range(rng.randrange(0, 40)))
        elif kind == 3:  # deeply nested JSON
            depth = rng.randrange(8, 64)
            line = b"{" * depth + b'"a":1' + b"}" * rng.randrange(0, depth)
        else:  # real-command prefix + junk
            line = rng.choice(real_prefixes) + bytes(
                rng.randrange(32, 127) for _ in range(rng.randrange(0, 60)))
        if line.strip() in FORBIDDEN_LINES:
            continue
        yield line


def test_serial_fuzz_survives(stick):
    """Garbage on the command channel must never panic, reboot, or wedge
    the device. Oracle: panic counter unchanged, uptime monotonic, ping
    still answered. Reproduce a failure with BUDDY_FUZZ_SEED=<seed>."""
    rng = random.Random(FUZZ_SEED)
    before = ping(stick)
    for line in _fuzz_lines(rng, FUZZ_LINES):
        stick.write_line(line.decode("latin-1"))
        stick.read_some()  # keep the RX side drained while we flood TX
        time.sleep(0.01)
    stick.drain_until_quiet()
    after = ping_retry(stick, 10)
    assert after["panics"] == before["panics"], (
        f"fuzz crashed the device (seed {FUZZ_SEED}): "
        f"panics {before['panics']} -> {after['panics']}, reset={after['reset']!r}"
    )
    assert after["up"] > before["up"], (
        f"fuzz rebooted the device (seed {FUZZ_SEED}): "
        f"uptime {before['up']} -> {after['up']}, reset={after['reset']!r}"
    )


# --- watchdog recovery ---------------------------------------------------


@pytest.mark.slow
def test_wdt_reboots_hung_loop(stick):
    """'hang' wedges loop() on purpose; the task watchdog must reboot the
    device on its own and the crash must land in telemetry. This is the
    guarantee that a field freeze is a ~30s blip, not a dead unit."""
    before = ping(stick)
    stick.write_line("hang")
    # WDT timeout is 30s; allow boot time on top.
    time.sleep(35)
    pong = ping_retry(stick, 30)
    assert pong["reset"] == "task_wdt", (
        f"expected task_wdt reset after hang, got {pong['reset']!r} — "
        "watchdog did not fire"
    )
    assert pong["panics"] == before["panics"] + 1
    assert pong["early"] >= 1
    # Clean up so repeated runs don't accumulate toward safe mode.
    reply = stick.framed_json("guardclear", "GUARDCLEAR", 3)
    assert reply is not None
    assert ping(stick)["early"] == 0
