"""Command line for boopctl. Subcommands are listed in plan/VERIFICATION.md §2."""
from __future__ import annotations

import argparse
import json
import random
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


SOAK_ANIMS = ["nod", "cheer", "oops", "side_eye", "wiggle", "stretch", "yawn", "shrug", "zip", "gobble",
              "rumble", "levelup", "happy", "proud", "smug", "curious", "sleepy", "worried", "sulky", "love"]
SOAK_PROJECTS = ["landing", "jetpack", "buddygotchi", "a-very-long-project-name", "notes"]


def soak_state(rng: random.Random) -> dict:
    """A realistic snapshot: sessions, sometimes something that needs you."""
    threads = [[rng.choice(["claude", "codex"]), rng.choice(SOAK_PROJECTS), rng.choice(["work", "idle", "wait"])]
               for _ in range(rng.randint(0, 8))]
    busy = sum(t[2] == "work" for t in threads)
    wait = sum(t[2] == "wait" for t in threads)
    msg = {"t": "state", "v": 1, "time": int(time.time()), "name": "Pip",
           "base": "working" if busy else rng.choice(["idle", "idle", "asleep"]),
           "busy": busy, "idle": len(threads) - busy - wait, "wait": wait,
           "mood": {"energy": rng.randint(30, 170), "pace": rng.randint(60, 150), "pitch": 100},
           "quiet": rng.choice([0, 0, 0, 5]), "focus": rng.random() < 0.1, "vol": 6,
           "night": rng.random() < 0.15, "level": rng.randint(1, 30), "prog": rng.randint(0, 99),
           "days": rng.randint(0, 400), "hungry": rng.choice([0, 0, 0, 1, 2]), "threads": threads}
    if wait:
        waiting = next(t for t in threads if t[2] == "wait")
        msg["attn"] = {"agent": waiting[0], "project": waiting[1], "more": wait - 1}
    return msg


def soak_moment(rng: random.Random) -> dict:
    msg = {"t": "moment", "anim": rng.choice(SOAK_ANIMS), "size": rng.randint(1, 3), "ttl": 5}
    if rng.random() < 0.4:
        n = rng.randint(1, 8)
        msg["say"] = {"syl": " ".join(rng.choice(["ba", "na", "po", "ti", "ka", "mi"]) for _ in range(n)),
                      "word": rng.choice(["", "done", "tests", "finally", "hmm"]), "at": rng.randint(0, n),
                      "tune": "up", "ms": rng.randint(80, 200)}
    return msg


def soak_input(rng: random.Random) -> dict:
    kind = rng.choice(["tap", "hold", "face", "face_hold", "strip", "strip_hold"])
    if kind == "tap":
        return {"t": "dbg.press", "ms": 100}
    if kind == "hold":
        return {"t": "dbg.press", "ms": rng.randint(500, 3000)}
    y = rng.randint(290, 315) if kind.startswith("strip") else rng.randint(20, 260)
    return {"t": "dbg.touch", "x": rng.randint(10, 230), "y": y, "ms": 800 if kind.endswith("hold") else 100}


def cmd_soak(args: argparse.Namespace) -> int:
    """Random, realistic traffic and inputs with the clock running, then
    checks for resets, a drifting heap minimum and stuck states."""
    rng = random.Random(args.seed)
    samples, log_lines = [], []
    with Device(args.port) as dev:
        dev.request({"t": "dbg.reset"})
        dev.request({"t": "dbg.clock", "run": True})
        start = time.monotonic()
        next_ping = 0.0
        silent_until = 0.0
        state = soak_state(rng)
        last_state = -100.0
        silence_done = False
        while (elapsed := time.monotonic() - start) < args.minutes * 60:
            r = rng.random()
            if not silence_done and elapsed > args.minutes * 30:
                silent_until, silence_done = elapsed + 35, True  # once: the Mac goes away, "no app"
            if elapsed >= silent_until:
                if r < 0.25:
                    state = soak_state(rng)
                    dev.send(state)
                    last_state = elapsed
                elif r < 0.5:
                    dev.send(soak_moment(rng))
                elif r < 0.7:
                    dev.request(soak_input(rng))
                if elapsed - last_state >= 10:
                    dev.send(state)  # the Mac's 10 s snapshot
                    last_state = elapsed
            if elapsed >= next_ping:
                ping = dev.request({"t": "dbg.ping"})
                samples.append({"t": round(elapsed, 1), "up": ping["up"], "heap": ping["heap"],
                                "heap_min": ping["heap_min"], "fps": ping["fps"]})
                next_ping = elapsed + 5
            time.sleep(rng.uniform(0.2, 1.5))
        # Stuck? Calm snapshots must bring back the plain face once the last
        # press and push-to-talk (thinking, then a shrug, ≤ 13 s) are over.
        for _ in range(3):
            dev.send({"t": "state", "v": 1, "base": "idle", "busy": 0, "idle": 1, "wait": 0})
            time.sleep(5)
        final = dev.request({"t": "dbg.state"})
        ping = dev.request({"t": "dbg.ping"})
        samples.append({"t": round(time.monotonic() - start, 1), "up": ping["up"], "heap": ping["heap"],
                        "heap_min": ping["heap_min"], "fps": ping["fps"]})
    ups = [s["up"] for s in samples]
    early = [s["heap_min"] for s in samples if s["t"] >= 60] or [samples[0]["heap_min"]]
    result = {
        "minutes": args.minutes,
        "samples": len(samples),
        "reset": any(b <= a for a, b in zip(ups, ups[1:])),
        "heap_min_start": early[0],
        "heap_min_end": samples[-1]["heap_min"],
        "heap_min_drift": early[0] - samples[-1]["heap_min"],
        "final_screen": final.get("screen"),
        "final_moment": final.get("moment"),
        "answering": final.get("t") == "dbg.state",
    }
    result["ok"] = (not result["reset"] and result["heap_min_drift"] <= 2048 and result["answering"]
                    and result["final_screen"] == "face" and result["final_moment"] is None)
    if args.out:
        Path(args.out).write_text(json.dumps({**result, "series": samples}, indent=1))
    emit(result)
    return 0 if result["ok"] else 1


def cmd_cam(args: argparse.Namespace) -> int:
    from boopctl_lib import cam

    with Device(args.port) as dev:
        if args.action == "frame":
            result = cam.frame(dev, args.usb)
        elif args.action == "clip":
            if not args.name:
                raise DeviceError(f"cam clip needs a name: {', '.join(cam.CLIPS)}")
            result = cam.clip(dev, args.name, args.seconds)
        else:
            result = cam.pattern(dev)
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
    p = sub.add_parser("soak", help="random realistic traffic and inputs; checks resets, leaks, stuck states")
    p.add_argument("--minutes", type=float, default=20)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--out", help="write the result and the samples as JSON")
    p.set_defaults(func=cmd_soak)
    p = sub.add_parser("cam", help="webcam helpers (opt-in; plan/VERIFICATION.md §6)")
    p.add_argument("action", choices=["frame", "pattern", "clip"])
    p.add_argument("name", nargs="?", help="clip: idle, needs_you, cheer, ladder, cheers or tap")
    p.add_argument("--seconds", type=int, default=8, help="clip length, at most 10")
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
