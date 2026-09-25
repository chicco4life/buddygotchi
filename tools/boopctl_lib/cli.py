"""Command line for boopctl. Subcommands are listed in plan/VERIFICATION.md §2."""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

from boopctl_lib import scenario
from boopctl_lib.device import Device, DeviceError, Sim, list_ports
from boopctl_lib.image import diff, save_shot

REPO = Path(__file__).resolve().parents[2]
PIO = REPO / "firmware" / "tools" / "pio.sh"
SIM_PROGRAM = REPO / "firmware" / ".pio" / "build" / "native" / "program"
SIM_OUT = Path("/tmp/boop-sim")
RUN_OUT = Path("/tmp/boop-run")


def emit(obj: object) -> None:
    print(json.dumps(obj, indent=2, sort_keys=True))


def cmd_ports(args: argparse.Namespace) -> int:
    ports = list_ports()
    for port in ports:
        print(port)
    return 0 if ports else 1


def cmd_flash(args: argparse.Namespace) -> int:
    cmd = [str(PIO), "run", "-e", args.env, "-t", "upload"]
    if args.port:
        cmd += ["--upload-port", args.port]
    return subprocess.run(cmd).returncode


def cmd_ping(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        emit(dev.request({"t": "dbg.ping"}))
    return 0


def cmd_state(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        emit(dev.request({"t": "dbg.state"}))
    return 0


def cmd_send(args: argparse.Namespace) -> int:
    json.loads(args.message)  # refuse to send malformed JSON
    with Device(args.port) as dev:
        dev.send(args.message)
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        palette, pixels = dev.shot()
    print(save_shot(palette, pixels, Path(args.out)))
    return 0


def cmd_diff(args: argparse.Namespace) -> int:
    out = Path(args.out) if args.out else Path(args.b).with_suffix(".diff.png")
    n = diff(Path(args.a), Path(args.b), out)
    print(f"{n} pixels differ" + (f"; see {out}" if n else ""))
    return 0 if n <= args.threshold else 1


def cmd_pattern(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        dev.request({"t": "dbg.pattern"})
    return 0


def cmd_press(args: argparse.Namespace) -> int:
    ms = args.ms or scenario.PRESS_MS[args.kind]
    with Device(args.port) as dev:
        dev.request({"t": "dbg.press", "ms": ms})
    return 0


def cmd_touch(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        dev.request({"t": "dbg.touch", "x": args.x, "y": args.y, "ms": args.ms})
    return 0


def cmd_clock(args: argparse.Namespace) -> int:
    message = {"freeze": {"freeze": args.value}, "step": {"step": args.value}, "run": {"run": True}}[args.action]
    if args.action != "run" and args.value is None:
        raise SystemExit(f"boopctl clock {args.action} needs a value in ms")
    with Device(args.port) as dev:
        emit(dev.request({"t": "dbg.clock", **message}))
    return 0


def build_sim() -> None:
    result = subprocess.run([str(PIO), "run", "-e", "native"], capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-4000:] + result.stderr[-2000:])
        raise DeviceError("building boop-sim failed")


def pick(names: list[str]) -> list[Path]:
    return [scenario.resolve(n) for n in names] if names else scenario.all_scenarios()


def sim_all(paths: list[Path]) -> tuple[int, dict[str, Path]]:
    """Plays scenarios in boop-sim. Returns (failures, scenario → shot dir)."""
    build_sim()
    failures, dirs = 0, {}
    for path in paths:
        out = SIM_OUT / path.stem
        shutil.rmtree(out, ignore_errors=True)
        with Sim(str(SIM_PROGRAM)) as sim:
            failures += len(scenario.play(sim, path, out))
        dirs[path.stem] = out
    return failures, dirs


def cmd_sim(args: argparse.Namespace) -> int:
    failures, dirs = sim_all(pick(args.scenario))
    changed = 0
    for name, out in dirs.items():
        for png in sorted(out.glob("*.png")):
            if png.name.endswith(".diff.png"):
                continue
            golden = scenario.GOLDEN / name / png.name
            if args.accept:
                golden.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(png, golden)
                print(f"accepted {golden.relative_to(REPO)}")
            elif not golden.exists():
                changed += 1
                print(f"NEW   {png} (no golden yet)")
            elif (n := diff(golden, png, png.with_suffix(".diff.png"))):
                changed += 1
                print(f"DIFF  {png}: {n} pixels differ from {golden.relative_to(REPO)}")
            else:
                print(f"same  {png}")
    print(f"{len(dirs)} scenarios, {failures} expect failures, {changed} new or changed pictures")
    return 1 if failures or changed else 0


def cmd_run(args: argparse.Namespace) -> int:
    paths = pick(args.scenario)
    _, sim_dirs = sim_all(paths)
    failures = differ = 0
    with Device(args.port) as dev:
        for path in paths:
            out = RUN_OUT / path.stem
            shutil.rmtree(out, ignore_errors=True)
            failures += len(scenario.play(dev, path, out))
            for png in sorted(out.glob("*.png")):
                ref = sim_dirs[path.stem] / png.name
                n = diff(ref, png, png.with_suffix(".diff.png"))
                differ += bool(n)
                print(("same  " if not n else f"DIFF  ({n} px) ") + f"{png} vs {ref}")
        dev.request({"t": "dbg.clock", "run": True})
    print(f"{len(paths)} scenarios, {failures} expect failures, {differ} pictures differ from the simulator")
    return 1 if failures or differ else 0


# Moments that keep the face moving for perf, one after another.
MOTION = ["cheer", "wiggle", "levelup", "gobble", "rumble", "nod", "yawn", "stretch"]


def cmd_perf(args: argparse.Namespace) -> int:
    """Samples fps and heap once a second with the clock running. With
    --motion, it plays moments back to back, so every sample is mid-motion."""
    samples = []
    with Device(args.port) as dev:
        dev.request({"t": "dbg.clock", "run": True})
        dev.send({"t": "state", "v": 1, "base": "working", "busy": 1})
        start = time.monotonic()
        last_moment = -10.0
        i = 0
        while (elapsed := time.monotonic() - start) < args.seconds:
            if args.motion and elapsed - last_moment >= 1.0:
                dev.send({"t": "moment", "anim": MOTION[i % len(MOTION)], "size": 3, "ttl": 5})
                dev.send({"t": "state", "v": 1, "base": "working", "busy": 1})
                last_moment, i = elapsed, i + 1
            time.sleep(1.0)
            ping = dev.request({"t": "dbg.ping"})
            samples.append({"fps": ping["fps"], "heap": ping["heap"], "heap_min": ping["heap_min"], "up": ping["up"]})
    fps = [s["fps"] for s in samples[1:]] or [0]  # the first second includes the start
    ups = [s["up"] for s in samples]
    result = {
        "samples": len(samples),
        "fps_min": min(fps),
        "fps_mean": round(sum(fps) / len(fps), 1),
        "heap_min": min(s["heap_min"] for s in samples),
        "reset": any(b <= a for a, b in zip(ups, ups[1:])),
        "motion": args.motion,
    }
    result["ok"] = (not args.motion or result["fps_min"] >= 25) and result["heap_min"] >= 60000 and not result["reset"]
    emit(result)
    return 0 if result["ok"] else 1


def cmd_cam(args: argparse.Namespace) -> int:
    from boopctl_lib import cam

    with Device(args.port) as dev:
        result = cam.frame(dev, args.usb) if args.action == "frame" else cam.pattern(dev)
    emit(result)
    return 0 if result["ok"] else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="boopctl", description="Talk to the Boop board over USB.")
    parser.add_argument("--port", help="serial port (default: $BOOP_PORT or the first /dev/cu.usbserial-*)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("ports", help="list USB serial ports").set_defaults(func=cmd_ports)
    p = sub.add_parser("flash", help="build and upload the firmware")
    p.add_argument("--env", default="cyd24")
    p.set_defaults(func=cmd_flash)
    sub.add_parser("ping", help="firmware version, uptime, heap, fps, link").set_defaults(func=cmd_ping)
    sub.add_parser("state", help="the device's own view of itself").set_defaults(func=cmd_state)
    p = sub.add_parser("send", help="send one protocol message")
    p.add_argument("message")
    p.set_defaults(func=cmd_send)
    p = sub.add_parser("shot", help="screenshot the device's canvas")
    p.add_argument("--out", default="/tmp/boop-shot.png")
    p.set_defaults(func=cmd_shot)
    p = sub.add_parser("diff", help="pixel diff of two PNGs; non-zero exit past the threshold")
    p.add_argument("a")
    p.add_argument("b")
    p.add_argument("--threshold", type=int, default=0)
    p.add_argument("--out", help="highlighted diff image (default: <b>.diff.png)")
    p.set_defaults(func=cmd_diff)
    sub.add_parser("pattern", help="show the bring-up test pattern").set_defaults(func=cmd_pattern)
    p = sub.add_parser("press", help="inject a BOOT press")
    p.add_argument("kind", choices=["tap", "hold"])
    p.add_argument("--ms", type=int)
    p.set_defaults(func=cmd_press)
    p = sub.add_parser("touch", help="inject a touch at screen coordinates")
    p.add_argument("x", type=int)
    p.add_argument("y", type=int)
    p.add_argument("--ms", type=int, default=100)
    p.set_defaults(func=cmd_touch)
    p = sub.add_parser("clock", help="freeze T | step MS | run")
    p.add_argument("action", choices=["freeze", "step", "run"])
    p.add_argument("value", type=int, nargs="?")
    p.set_defaults(func=cmd_clock)
    p = sub.add_parser("sim", help="play scenarios in the simulator and compare with the goldens")
    p.add_argument("scenario", nargs="*", help="names or paths (default: all)")
    p.add_argument("--accept", action="store_true", help="copy the pictures into the goldens (after looking!)")
    p.set_defaults(func=cmd_sim)
    p = sub.add_parser("run", help="play scenarios on the device and compare with the simulator")
    p.add_argument("scenario", nargs="*", help="names or paths (default: all)")
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("perf", help="sample fps and heap; --motion keeps the face moving")
    p.add_argument("--seconds", type=int, default=30)
    p.add_argument("--motion", action="store_true")
    p.set_defaults(func=cmd_perf)
    p = sub.add_parser("cam", help="webcam helpers (opt-in; plan/VERIFICATION.md §6)")
    p.add_argument("action", choices=["frame", "pattern"])
    p.add_argument("--usb", default="right", choices=["bottom", "right", "top", "left"],
                   help="where USB-C is in the camera's view (frame only)")
    p.set_defaults(func=cmd_cam)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (DeviceError, FileNotFoundError) as exc:
        print(f"boopctl: {exc}", file=sys.stderr)
        return 2
