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
        shot = dev.shot()
    print(save_shot(shot, Path(args.out)))
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


def cmd_calibrate(args: argparse.Namespace) -> int:
    from boopctl_lib import calibrate

    if args.show:
        with Device(args.port) as dev:
            emit(dev.request({"t": "dbg.touchcal", **({"clear": True} if args.clear else {})}))
        return 0
    emit(calibrate.run(args.port))
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


# F5's L2 check: one moment per feeling, with and without a real word.
VOICE_LINES = [("happy", "happy", "yay"), ("excited", "cheer", "done"), ("proud", "proud", "ship"),
               ("curious", "curious", "tests"), ("hopeful", "love", "food"), ("annoyed", "side_eye", "build"),
               ("sad", "sulky", "oops"), ("sleepy", "sleepy", "nap")]


def boopdev_voice(feeling: str, word: str | None, count: int, seed: int | None = None) -> list[dict]:
    """Lines as the Mac's Voice builds them, through `boopdev voice --json`."""
    boopdev = REPO / "app" / ".build" / "debug" / "boopdev"
    if not boopdev.exists():
        raise DeviceError(f"{boopdev} is missing; run `make build` first")
    cmd = [str(boopdev), "voice", feeling] + ([word] if word else []) + ["--count", str(count), "--json"]
    if seed is not None:
        cmd += ["--seed", str(seed)]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    return [json.loads(row) for row in out.splitlines() if row.startswith("{")]


def voice_lines(count: int) -> list[tuple[str, dict]]:
    return [(anim, line) for feeling, anim, word in VOICE_LINES for w in (None, word)
            for line in boopdev_voice(feeling, w, count)]


def cmd_voice(args: argparse.Namespace) -> int:
    """Plays real `say` lines on the board and checks the audio timeline in
    dbg.state against each: syllable count, the word, and the duration the
    DAC took within 10% of beats × ms. Then checks mute keeps it silent."""
    lines = voice_lines(args.count)
    results = []
    with Device(args.port) as dev:
        dev.request({"t": "dbg.reset"})
        dev.request({"t": "dbg.clock", "run": True})
        dev.send({"t": "state", "v": 1, "base": "idle", "vol": 6})
        for anim, say in lines:
            before = dev.request({"t": "dbg.state"})["audio"]["out"]["lines"]
            dev.send({"t": "moment", "anim": anim, "size": 1, "say": say, "ttl": 5})
            deadline = time.monotonic() + 6
            amp_seen = playing_seen = False
            while True:
                st = dev.request({"t": "dbg.state"})
                out = st["audio"]["out"]
                amp_seen |= st["amp"]
                playing_seen |= out["playing"]
                if out["lines"] > before or time.monotonic() > deadline:
                    break
                time.sleep(0.05)
            syl = len([s for s in say["syl"].replace("-", " ").split() if s])
            beats = syl + (2 if say.get("word") else 0)
            plan = beats * say["ms"]
            r = {"syl": say["syl"], "word": say.get("word"), "ms": say["ms"], "plan_ms": plan,
                 "got": {k: out[k] for k in ("syl", "word", "plan_ms", "out_ms", "wall_ms", "cut")},
                 "amp_on": amp_seen, "amp_off_after": not st["amp"]}
            r["ok"] = (out["lines"] == before + 1 and out["syl"] == syl and out["word"] == bool(say.get("word"))
                       and abs(out["plan_ms"] - plan) <= 1 and abs(out["out_ms"] - plan) <= 1
                       and abs(out["wall_ms"] - plan) <= plan // 10 and not out["cut"] and amp_seen)
            results.append(r)
            if not args.json:
                g = r["got"]
                print(f"{'ok ' if r['ok'] else 'BAD'} {say['syl']!r:28} {str(say.get('word') or ''):6} "
                      f"plan {plan:5} ms  out {g['out_ms']:5} ms  dac {g['wall_ms']:5} ms  "
                      f"({(g['wall_ms'] - plan) * 100 / plan:+.1f}%)  amp {'on' if amp_seen else 'OFF'}")
        # Muted: the mouth still moves, the DAC stays off.
        dev.send({"t": "state", "v": 1, "base": "idle", "vol": 0})
        before = dev.request({"t": "dbg.state"})["audio"]["out"]["lines"]
        dev.send({"t": "moment", "anim": "happy", "size": 1, "say": lines[0][1], "ttl": 5})
        mouth = dev.request({"t": "dbg.state"})["audio"]["playing"]
        time.sleep(2.5)
        st = dev.request({"t": "dbg.state"})
        muted = {"mouth_moved": mouth, "lines_played": st["audio"]["out"]["lines"] - before, "amp": st["amp"]}
        dev.send({"t": "state", "v": 1, "base": "idle", "vol": 6})
    walls = [abs(r["got"]["wall_ms"] - r["plan_ms"]) * 100 / r["plan_ms"] for r in results]
    summary = {"lines": len(results), "passed": sum(r["ok"] for r in results),
               "worst_wall_error_pct": round(max(walls), 1), "muted": muted,
               "ok": all(r["ok"] for r in results) and muted["mouth_moved"] and not muted["lines_played"]}
    if args.json:
        emit({"results": results, **summary})
    else:
        emit(summary)
    return 0 if summary["ok"] else 1


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
    # The 320×240 screen: the strip is the bottom 36 px (render/screens.h kStripTop 204).
    y = rng.randint(210, 235) if kind.startswith("strip") else rng.randint(20, 190)
    return {"t": "dbg.touch", "x": rng.randint(10, 310), "y": y, "ms": 800 if kind.endswith("hold") else 100}


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


def cmd_e2e(args: argparse.Namespace) -> int:
    from boopctl_lib import e2e

    if args.soak:
        return e2e.soak(Path(args.out), args.brain, args.port, args.soak)
    return e2e.main(Path(args.out), args.brain, args.port, args.fixture or None, args.clip)


def cmd_bridge(args: argparse.Namespace) -> int:
    from boopctl_lib.bridge import bridge_path, serve

    return serve(args.port, args.socket or bridge_path(), quiet=args.quiet)


# Hearing and watching Boop by hand: mumble, sound, moment and needs drive
# the board over USB the way the Mac would, and read dbg.state to say
# whether it happened. The Mac app, if it's connected over Bluetooth, keeps
# sending its own `state` and can override these.

FEELINGS = [f for f, _, _ in VOICE_LINES]
MOMENT_ANIMS = sorted(set(SOAK_ANIMS) | {"listening", "thinking"})


def show_begin(dev: Device) -> None:
    """Lets the clock run (a scenario may have frozen it) and warns when the
    Mac app is connected, since its next `state` wins. These commands poll
    dbg.state often, and the CH340 now and then drops a reply, so a debug
    request is retried once, as in e2e's soak."""
    request = dev.request

    def retried(message: dict) -> dict:
        try:
            return request(message)
        except (DeviceError, ValueError):
            dev._buf.clear()
            return request(message)

    dev.request = retried
    if dev.request({"t": "dbg.ping"}).get("ble") == "conn":
        print("boopctl: the Mac app is connected over Bluetooth and may override this; "
              "quit it for a clean run", file=sys.stderr)
    dev.request({"t": "dbg.clock", "run": True})


def show_state(dev: Device, vol: int, base: str = "idle", attn: dict | None = None) -> None:
    """A minimal `state`. Resent at least every 10 s, since the board shows
    "no app" after 30 s without one (PROTOCOL.md §3)."""
    msg = {"t": "state", "v": 1, "base": base, "vol": vol}
    if attn:
        msg["attn"] = attn
    dev.send(msg)


def sfx_name(st: dict) -> str | None:
    sfx = st.get("sfx")
    if isinstance(sfx, dict):
        sfx = sfx.get("k") or sfx.get("name")
    elif isinstance(sfx, list):
        sfx = sfx[0] if sfx else None
    return sfx


def play_line(dev: Device, anim: str, say: dict) -> dict | None:
    """Plays one mumble and waits for the board to finish it: `audio.out`
    for the line, or None if it didn't play within 6 s."""
    before = dev.request({"t": "dbg.state"})["audio"]["out"]["lines"]
    dev.send({"t": "moment", "anim": anim, "size": 1, "say": say, "ttl": 5})
    deadline = time.monotonic() + 6
    while (out := dev.request({"t": "dbg.state"})["audio"]["out"])["lines"] <= before:
        if time.monotonic() > deadline:
            return None
        time.sleep(0.05)
    return out


def cmd_mumble(args: argparse.Namespace) -> int:
    """One mumble per feeling (or the ones named), without and then with its
    usual word, waiting for the board to finish each line."""
    words = {f: w for f, _, w in VOICE_LINES}
    anims = {f: a for f, a, _ in VOICE_LINES}
    seed = args.seed if args.seed is not None else random.randrange(10_000)
    print(f"seed {seed} (--seed {seed} plays these lines again)")
    missed = 0
    with Device(args.port) as dev:
        show_begin(dev)
        for i, feeling in enumerate(args.feeling or FEELINGS):
            variants = [args.word] if args.word else [None] if args.no_word else [None, words[feeling]]
            for word in variants:
                say = boopdev_voice(feeling, word, 1, seed + i)[0]
                show_state(dev, args.vol)
                out = play_line(dev, anims[feeling], say)
                missed += out is None
                print(f"{'ok  ' if out else 'MISS'} {feeling:8} {say['syl']!r:30} {say.get('word') or '':7} "
                      + (f"{out['wall_ms']} ms" if out else "didn't play"))
                time.sleep(args.gap)
    return 1 if missed else 0


# One fixed line for comparing volumes, so only the level changes between
# plays: a proud mumble with a long real word.
VOLUME_LINE = {"syl": "mo-la-gom la-pa pa go-gom", "word": "finally", "at": 8, "tune": "lift", "ms": 135}


def cmd_volume(args: argparse.Namespace) -> int:
    """The same line at each level in turn, round after round, for comparing
    by ear, and whether the board played each one in full."""
    missed = 0
    with Device(args.port) as dev:
        show_begin(dev)
        for i in range(args.rounds):
            for vol in args.levels:
                show_state(dev, vol)
                out = play_line(dev, "happy", VOLUME_LINE)
                missed += out is None or out["cut"]
                print(f"round {i + 1} vol {vol:2}: "
                      + (f"played {out['out_ms']} ms" + (", cut short" if out["cut"] else "") if out else "didn't play"),
                      flush=True)
                time.sleep(args.gap)
    return 1 if missed else 0


def cmd_sound(args: argparse.Namespace) -> int:
    """The chirp comes with a new "needs you", so it's played by sending one
    and clearing it (Boop nods). The jingle comes with a cheer of size 2."""
    with Device(args.port) as dev:
        show_begin(dev)
        if args.cue == "chirp":
            show_state(dev, args.vol, attn={"agent": "claude", "project": "boopctl", "more": 0})
        else:
            show_state(dev, args.vol)
            dev.send({"t": "moment", "anim": "cheer", "size": 2, "ttl": 5})
        deadline = time.monotonic() + 3
        while (heard := sfx_name(dev.request({"t": "dbg.state"}))) != args.cue and time.monotonic() < deadline:
            time.sleep(0.05)
        if args.cue == "chirp":
            time.sleep(1.5)
            show_state(dev, args.vol)
    print(f"{args.cue}: " + ("played" if heard == args.cue else f"not played (last cue {heard})"))
    return 0 if heard == args.cue else 1


def cmd_moment(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        show_begin(dev)
        show_state(dev, args.vol, base=args.base)
        msg = {"t": "moment", "anim": args.anim, "size": args.size, "ttl": 5}
        if args.say:
            msg["say"] = boopdev_voice(args.say, args.word, 1, args.seed)[0]
        dev.send(msg)
        moment = dev.request({"t": "dbg.state"}).get("moment")
    playing = bool(moment) and moment.get("anim") == args.anim
    print(f"{args.anim}: " + (f"playing, {moment['left_ms']} ms" if playing else f"not playing ({moment})")
          + (f", saying {msg['say']['syl']!r} {msg['say'].get('word') or ''}" if args.say else ""))
    return 0 if playing else 1


def cmd_needs(args: argparse.Namespace) -> int:
    """Holds a "needs you" and prints each rung of the nudge ladder as the
    board reaches it (BEHAVIORS.md §3.2), then clears it. Ctrl-C clears it
    early."""
    attn = {"agent": args.agent, "project": args.project, "more": args.more}
    with Device(args.port) as dev:
        show_begin(dev)
        start = time.monotonic()
        resend = rung = None
        try:
            while (now := time.monotonic()) - start < args.seconds:
                if resend is None or now >= resend:
                    show_state(dev, args.vol, attn=attn)
                    resend = now + 10
                st = dev.request({"t": "dbg.state"})
                if st["rung"] != rung:
                    rung = st["rung"]
                    print(f"{now - start:6.1f} s  rung {rung}  screen {st['screen']}  led {st['led']}  "
                          f"last cue {sfx_name(st)}", flush=True)
                time.sleep(0.25)
        except KeyboardInterrupt:
            pass
        finally:
            show_state(dev, args.vol)
    print("cleared: Boop nods and goes back to idle")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="boopctl", description="Talk to the Boop board over USB.")
    parser.add_argument("--port", help="serial port (default: $BOOP_PORT or the first /dev/cu.usbserial-*)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("ports", help="list USB serial ports").set_defaults(func=cmd_ports)
    p = sub.add_parser("flash", help="build and upload the firmware")
    p.add_argument("--env", default="cyd24")
    p.set_defaults(func=cmd_flash)
    sub.add_parser("ping", help="firmware version, uptime, heap, fps, link").set_defaults(func=cmd_ping)
    p = sub.add_parser("bridge", help="own the serial port and share it on a Unix socket")
    p.add_argument("--socket", help="socket path (default: $BOOP_BRIDGE or /tmp/boop-bridge.sock)")
    p.add_argument("--quiet", action="store_true")
    p.set_defaults(func=cmd_bridge)
    p = sub.add_parser("e2e", help="the pipeline check: hooks → headless app → bridge → board (L4)")
    p.add_argument("--brain", default="rules", choices=["rules", "apple"])
    p.add_argument("--out", default="/tmp/boop-e2e-out", help="results, logs and screenshots")
    p.add_argument("fixture", nargs="*", help="paths under app/Tests/Fixtures/hooks/e2e (default: all three)")
    p.add_argument("--clip", action="store_true",
                   help="first film a 10 s Claude session on the webcam (authorised runs only; §6)")
    p.add_argument("--soak", type=float, metavar="MIN",
                   help="loop the fixtures for MIN minutes and check for resets, leaks and stuck states (J2)")
    p.set_defaults(func=cmd_e2e)
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
    p = sub.add_parser("calibrate", help="touch calibration: tap 4 crosses (needs a person); kept in NVS")
    p.add_argument("--show", action="store_true", help="print the stored calibration instead")
    p.add_argument("--clear", action="store_true", help="with --show: forget it (back to the default raw range)")
    p.set_defaults(func=cmd_calibrate)
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
    p = sub.add_parser("voice", help="play say lines and check the audio timeline in dbg.state (F5, L2)")
    p.add_argument("--count", type=int, default=2, help="lines per feeling, with and without a word")
    p.add_argument("--json", action="store_true", help="every line's result as JSON")
    p.set_defaults(func=cmd_voice)
    vol = {"type": int, "choices": range(1, 11), "default": 6, "metavar": "1-10", "help": "volume (default 6)"}
    p = sub.add_parser("mumble", help="hear mumbles: every feeling, or the ones named, without and with a word")
    p.add_argument("feeling", nargs="*", choices=FEELINGS, metavar="feeling",
                   help=f"any of {', '.join(FEELINGS)} (default: all)")
    words = p.add_mutually_exclusive_group()
    words.add_argument("--word", help="say this word in every line (one from the vocabulary, VOICE.md §6)")
    words.add_argument("--no-word", action="store_true", help="only lines without a word")
    p.add_argument("--vol", **vol)
    p.add_argument("--seed", type=int, help="replay the lines of an earlier run (default: new lines)")
    p.add_argument("--gap", type=float, default=0.8, help="seconds between lines (default 0.8)")
    p.set_defaults(func=cmd_mumble)
    p = sub.add_parser("volume", help="compare volumes by ear: the same line at each level in turn")
    p.add_argument("levels", nargs="*", type=int, choices=range(1, 11), default=[1, 10], metavar="level",
                   help="volumes 1-10, played in this order each round (default: 1 10)")
    p.add_argument("--rounds", type=int, default=6, help="default 6")
    p.add_argument("--gap", type=float, default=0.6, help="seconds between lines (default 0.6)")
    p.set_defaults(func=cmd_volume)
    p = sub.add_parser("sound", help="hear the needs-you chirp or the cheer's jingle")
    p.add_argument("cue", choices=["chirp", "jingle"])
    p.add_argument("--vol", **vol)
    p.set_defaults(func=cmd_sound)
    p = sub.add_parser("moment", help="play an animation or face, optionally with a mumble")
    p.add_argument("anim", choices=MOMENT_ANIMS, metavar="anim", help=", ".join(MOMENT_ANIMS))
    p.add_argument("--size", type=int, choices=[1, 2, 3], default=1)
    p.add_argument("--say", choices=FEELINGS, metavar="FEELING", help="add a mumble with this feeling")
    p.add_argument("--word", help="the mumble's word")
    p.add_argument("--seed", type=int)
    p.add_argument("--base", choices=["idle", "working", "asleep"], default="idle")
    p.add_argument("--vol", **vol)
    p.set_defaults(func=cmd_moment)
    p = sub.add_parser("needs", help="hold a fake \"needs you\" through the nudge ladder, then clear it")
    p.add_argument("--seconds", type=float, default=130, help="how long to hold it (default 130: past rung 3)")
    p.add_argument("--agent", choices=["claude", "codex"], default="claude")
    p.add_argument("--project", default="boopctl")
    p.add_argument("--more", type=int, default=0, help="how many more are waiting")
    p.add_argument("--vol", **vol)
    p.set_defaults(func=cmd_needs)
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
                   help="where USB-C is in the camera's view (frame only); right means upright")
    p.set_defaults(func=cmd_cam)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (DeviceError, FileNotFoundError) as exc:
        print(f"boopctl: {exc}", file=sys.stderr)
        return 2
