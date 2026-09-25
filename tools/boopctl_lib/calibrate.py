"""Touch calibration (plan/DEVICE.md §4): a person taps 4 crosses, and the
board keeps the fitted raw → screen map in NVS. Needs a person; `fit` is
the only part that runs without one."""
from __future__ import annotations

import statistics
import time
from typing import Any

from boopctl_lib.device import Device, DeviceError

TARGETS = [(20, 20), (220, 20), (20, 300), (220, 300)]
CHECK = (120, 160)
POLL_S = 0.03
TAP_TIMEOUT_S = 60.0


def solve3(m: list[list[float]], v: list[float]) -> list[float]:
    """Solves a 3×3 linear system by Cramer's rule."""

    def det(a: list[list[float]]) -> float:
        return (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]))

    d = det(m)
    if abs(d) < 1e-9:
        raise DeviceError("the taps don't span the screen; try again")
    out = []
    for col in range(3):
        a = [row[:] for row in m]
        for r in range(3):
            a[r][col] = v[r]
        out.append(det(a) / d)
    return out


def fit(raw: list[tuple[float, float]], screen: list[tuple[int, int]]) -> list[int]:
    """Least-squares affine map raw → screen, as the 6 integers dbg.touchcal
    takes: [ax, bx, cx, ay, by, cy] in 1/65536."""
    rows = [(rx, ry, 1.0) for rx, ry in raw]
    ata = [[sum(r[i] * r[j] for r in rows) for j in range(3)] for i in range(3)]
    result = []
    for axis in range(2):
        atb = [sum(r[i] * s[axis] for r, s in zip(rows, screen)) for i in range(3)]
        result += [round(c * 65536) for c in solve3(ata, atb)]
    return result


def apply(cal: list[int], rx: float, ry: float) -> tuple[float, float]:
    ax, bx, cx, ay, by, cy = cal
    return (ax * rx + bx * ry + cx) / 65536, (ay * rx + by * ry + cy) / 65536


def touch_now(dev: Device) -> tuple[int, int] | None:
    t = dev.request({"t": "dbg.state"})["touch"]
    x, y, z = t["raw"]
    return (x, y) if t["irq"] and z > 0 else None


def read_tap(dev: Device) -> tuple[float, float]:
    """Waits for a finger, averages the readings while it's down, then waits
    for it to lift."""
    deadline = time.monotonic() + TAP_TIMEOUT_S
    while (p := touch_now(dev)) is None:
        if time.monotonic() > deadline:
            raise DeviceError("no tap within a minute")
        time.sleep(POLL_S)
    xs, ys = [p[0]], [p[1]]
    while (p := touch_now(dev)) is not None:
        xs.append(p[0]), ys.append(p[1])
        time.sleep(POLL_S)
    time.sleep(0.3)  # let the panel settle before the next cross
    return statistics.median(xs), statistics.median(ys)


def run(port: str | None) -> dict[str, Any]:
    raw: list[tuple[float, float]] = []
    with Device(port) as dev:
        try:
            for i, (x, y) in enumerate(TARGETS, 1):
                dev.request({"t": "dbg.pattern", "target": [x, y]})
                print(f"Tap the amber cross ({i} of {len(TARGETS)}) with a fingertip or stylus, then lift.", flush=True)
                raw.append(read_tap(dev))
                print(f"  raw {raw[-1][0]:.0f}, {raw[-1][1]:.0f}", flush=True)
            cal = fit(raw, TARGETS)
            worst = max(abs(a - b) for (rx, ry), t in zip(raw, TARGETS) for a, b in zip(apply(cal, rx, ry), t))
            dev.request({"t": "dbg.pattern", "target": list(CHECK)})
            print("Now tap the cross in the middle, to check.", flush=True)
            cx, cy = apply(cal, *read_tap(dev))
            miss = ((cx - CHECK[0]) ** 2 + (cy - CHECK[1]) ** 2) ** 0.5
            reply = dev.request({"t": "dbg.touchcal", "set": cal})
        finally:
            dev.request({"t": "dbg.reset"})  # back to the face, with the clock running
            dev.request({"t": "dbg.clock", "run": True})
    return {"raw": raw, "cal": reply["cal"], "fit_worst_px": round(worst, 1), "check_miss_px": round(miss, 1)}
