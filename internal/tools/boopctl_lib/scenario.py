"""Scenarios (plan/VERIFICATION.md §4): one JSON object per line, played the
same way on the board and in boop-sim."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from boopctl_lib.common import REPO
from boopctl_lib.device import Link
from boopctl_lib.image import save_shot

SCENARIOS = REPO / "internal" / "firmware" / "test" / "scenarios"
GOLDEN = REPO / "internal" / "firmware" / "test" / "golden"

TAP_MS = 100  # a tap's press or touch, unless the line gives "ms"


def resolve(name: str) -> Path:
    path = Path(name)
    if path.exists():
        return path
    path = SCENARIOS / f"{name}.jsonl"
    if not path.exists():
        raise FileNotFoundError(f"no scenario {name!r} in {SCENARIOS}")
    return path


def all_scenarios() -> list[Path]:
    return sorted(SCENARIOS.glob("*.jsonl"))


def matches(expected: Any, actual: Any) -> bool:
    """Every key in `expected` must match; extra keys in `actual` are fine."""
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(k in actual and matches(v, actual[k]) for k, v in expected.items())
    return expected == actual


def input_message(spec: dict[str, Any]) -> dict[str, Any]:
    if "press" in spec:
        return {"t": "dbg.press", "ms": spec.get("ms", TAP_MS)}
    if "touch" in spec:
        x, y = spec["touch"]
        return {"t": "dbg.touch", "x": x, "y": y, "ms": spec.get("ms", TAP_MS)}
    raise ValueError(f"unknown input {spec}")


def play(link: Link, path: Path, out_dir: Path, log=print) -> list[str]:
    """Plays one scenario. Returns the failures; saves shots as PNGs."""
    failures: list[str] = []
    out_dir.mkdir(parents=True, exist_ok=True)
    link.request({"t": "dbg.reset"})  # same start on the board and in the simulator
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("//"):
            continue
        step = json.loads(raw)
        where = f"{path.name}:{number}"
        if "t" in step:
            if step["t"].startswith("dbg."):
                link.request(step)
            else:
                link.send(step)
        elif "clock" in step:
            link.request({"t": "dbg.clock", "freeze": step["clock"]})
        elif "input" in step:
            link.request(input_message(step["input"]))
        elif "shot" in step:
            save_shot(link.shot(), out_dir / f"{step['shot']}.png")
        elif "expect" in step:
            state = link.request({"t": "dbg.state"})
            if not matches(step["expect"], state):
                failures.append(f"{where}: expected {json.dumps(step['expect'])}, got {json.dumps(state)}")
                log(f"FAIL {failures[-1]}")
        else:
            raise ValueError(f"{where}: unknown step {raw}")
    return failures
