"""Command line for boopctl (plan/VERIFICATION.md §2); `boopctl --help` lists
the subcommands and `boopctl <command> --help` their options."""
from __future__ import annotations

import argparse
import json
import random
import shutil
import subprocess
import sys
import time
from pathlib import Path

from boopctl_lib import scenario, workday
from boopctl_lib.common import ANIMS, CTXS, MOODS, OLD_ANIMS, OUTCOMES, PACK, REPO, Take, restarted, take, takes
from boopctl_lib.device import Device, DeviceError, Sim
from boopctl_lib.image import diff, save_shot

PIO = REPO / "firmware" / "tools" / "pio.sh"
SIM_PROGRAM = REPO / "firmware" / ".pio" / "build" / "native" / "program"
SIM_OUT = Path("/tmp/boop-sim")
RUN_OUT = Path("/tmp/boop-run")
# The everyday app's state directory (AppSettings.defaultStateDir).
EVERYDAY_STATE = Path.home() / "Library" / "Application Support" / "Boop"


def emit(obj: object) -> None:
    print(json.dumps(obj, indent=2, sort_keys=True))


def cmd_ping(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        emit(dev.request({"t": "dbg.ping"}))
    return 0


def cmd_card(args: argparse.Namespace) -> int:
    """Copies the voice pack onto the board's card over USB (VOICE.md §8)."""
    from boopctl_lib import card
    with Device(args.port) as dev:
        return card.copy(dev, Path(args.pack), force=args.force, fresh=args.fresh)


def cmd_state(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        emit(dev.request({"t": "dbg.state"}))
    return 0


def cmd_send(args: argparse.Namespace) -> int:
    """One message as the Mac would send it; a `dbg.` request (§3: press,
    touch, clock, pattern, light…) prints the board's reply."""
    message = json.loads(args.message)  # refuse to send malformed JSON
    with Device(args.port) as dev:
        if str(message.get("t", "")).startswith("dbg."):
            emit(dev.request(message))
        else:
            dev.send(args.message)
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    with Device(args.port) as dev:
        shot = dev.shot()
    print(save_shot(shot, Path(args.out)))
    return 0


def cmd_dash(args: argparse.Namespace) -> int:
    """The live dashboard, on the app's debug.jsonl and
    hook socket; its face is boop-sim, built from this checkout."""
    from boopctl_lib.dash.app import run

    state = Path(args.state_dir).expanduser() if args.state_dir else EVERYDAY_STATE
    build_sim()
    run(state, args.socket or str(state / "boop.sock"), str(SIM_PROGRAM))
    return 0


def cmd_day(args: argparse.Namespace) -> int:
    """What Boop did in a day, and why, from debug mode's logs
    (plan/harness/HARNESS.md §9)."""
    from boopctl_lib import day

    if args.file:
        paths = [Path(f).expanduser() for f in args.file]
    else:
        state = Path(args.state_dir).expanduser() if args.state_dir else EVERYDAY_STATE
        paths = day.launch_files(state)
        if not paths:
            print(f"boopctl day: no debug.jsonl in {state}. Boop writes it with --debug (make debug).", file=sys.stderr)
            return 1
    status, text = day.run(paths, args.date)
    print(text)
    return status


def a_date(text: str) -> str:
    try:
        return time.strftime("%Y-%m-%d", time.strptime(text, "%Y-%m-%d"))
    except ValueError:
        raise argparse.ArgumentTypeError(f"{text!r} isn't a date like 2026-09-28")


def cmd_calibrate(args: argparse.Namespace) -> int:
    from boopctl_lib import calibrate

    if args.show:
        with Device(args.port) as dev:
            emit(dev.request({"t": "dbg.touchcal", **({"clear": True} if args.clear else {})}))
        return 0
    emit(calibrate.run(args.port))
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
        try:
            for path in paths:
                out = RUN_OUT / path.stem
                shutil.rmtree(out, ignore_errors=True)
                failures += len(scenario.play(dev, path, out))
                for png in sorted(out.glob("*.png")):
                    ref = sim_dirs[path.stem] / png.name
                    n = diff(ref, png, png.with_suffix(".diff.png"))
                    differ += bool(n)
                    print(("same  " if not n else f"DIFF  ({n} px) ") + f"{png} vs {ref}")
        finally:
            # Scenarios freeze the clock; the face moves again even after a
            # failure or Ctrl-C.
            dev.request({"t": "dbg.clock", "run": True})
    print(f"{len(paths)} scenarios, {failures} expect failures, {differ} pictures differ from the simulator")
    return 1 if failures or differ else 0


def cmd_perf(args: argparse.Namespace) -> int:
    """Samples fps, frame time and heap once a second with the clock
    running. With --motion, it plays every animation in turn, one a second
    and each replacing the last, over the working face, so every sample is
    mid-motion. The board draws only when the picture changes, and the
    designs step a few times a second, so fps follows the design, and a
    second of a slow one draws only a few frames. So in motion it asks that
    the board drew in every second, and draw_us + push_us says how fast it
    draws (DEVICE.md §6)."""
    samples = []
    working = {"t": "state", "base": "working", "busy": 1}
    with Device(args.port) as dev:
        dev.request({"t": "dbg.clock", "run": True})
        dev.send(working)
        start = time.monotonic()
        last_moment = -10.0
        i = 0
        while (elapsed := time.monotonic() - start) < args.seconds:
            if args.motion and elapsed - last_moment >= 1.0:
                dev.send({"t": "moment", "anim": ANIMS[i % len(ANIMS)]})
                dev.send(working)
                last_moment, i = elapsed, i + 1
            time.sleep(1.0)
            samples.append(dev.vitals())
    fps = [s["fps"] for s in samples[1:]] or [0]  # the first second includes the start
    result = {
        "samples": len(samples),
        "fps_min": min(fps),
        "fps_mean": round(sum(fps) / len(fps), 1),
        "frame_ms_max": round(max((s["draw_us"] + s["push_us"]) / 1000 for s in samples), 1),
        "heap_min": min(s["heap_min"] for s in samples),
        "reset": restarted([s["up"] for s in samples]),
        "motion": args.motion,
    }
    moving = result["fps_min"] >= 1 and result["frame_ms_max"] <= 40  # VERIFICATION.md L2
    result["ok"] = (not args.motion or moving) and result["heap_min"] >= 60000 and not result["reset"]
    emit(result)
    return 0 if result["ok"] else 1


SOAK_PROJECTS = ["landing", "jetpack", "buddygotchi", "a-very-long-project-name", "notes"]


def soak_state(rng: random.Random, vol: int = 6) -> dict:
    """A realistic snapshot: sessions, sometimes something that needs you
    (a session waits one time in seven, so reactions mostly get to play)."""
    status = ["work"] * 3 + ["idle"] * 3 + ["wait"]
    sessions = [[rng.choice(["claude", "codex"]), rng.choice(SOAK_PROJECTS), rng.choice(status)]
                for _ in range(rng.randint(0, 8))]
    busy = sum(t[2] == "work" for t in sessions)
    wait = sum(t[2] == "wait" for t in sessions)
    msg = {"t": "state",
           "base": "working" if busy else rng.choice(["idle", "idle", "asleep"]),
           "mood": rng.choice(MOODS),
           "busy": busy, "vol": vol}
    if wait:
        waiting = next(t for t in sessions if t[2] == "wait")
        msg["attn"] = {"agent": waiting[0], "project": waiting[1], "more": wait - 1}
    return msg


def soak_say(rng: random.Random) -> dict:
    """A take by its id, now and then none (`{}`, which plays nothing)."""
    return {} if rng.random() < 0.1 else {"take": rng.choice(takes()).id}


def soak_moment(rng: random.Random) -> dict:
    """An animation, a line, or both, as the rules and the dashboard send
    them: a finish with its outcome and loops (1–3), a one-shot, a poke,
    chatter."""
    msg: dict = {"t": "moment"}
    if rng.random() < 0.7:
        msg["anim"] = rng.choice(ANIMS)
        if msg["anim"] == "task_complete":
            msg["outcome"] = rng.choice(OUTCOMES)
            msg["loops"] = rng.randint(1, 3)
        if msg["anim"] == "starting":
            msg["ctx"] = rng.choice(CTXS)
    if "anim" not in msg or rng.random() < 0.4:
        msg["say"] = soak_say(rng)
    return msg


def soak_reaction(rng: random.Random, moment_id: int) -> dict:
    """A brain reaction, which the Mac waits on: a line in a mood's face,
    held for its loops (1–6, as the device takes them), with an `id` the
    board answers with one `ended` (PROTOCOL.md §3–4)."""
    return {"t": "moment", "say": soak_say(rng), "mood": rng.choice(MOODS), "loops": rng.randint(1, 6),
            "id": moment_id}


def soak_input(rng: random.Random) -> dict:
    """BOOT presses and touches anywhere, short and long, the status strip
    included: each a tap on release, except a BOOT press held 400 ms or
    more, which is push-to-talk (DEVICE.md §4)."""
    kind = rng.choice(["tap", "long_press", "touch", "long_touch"])
    if kind == "tap":
        return {"t": "dbg.press", "ms": 100}
    if kind == "long_press":
        return {"t": "dbg.press", "ms": rng.randint(500, 3000)}
    return {"t": "dbg.touch", "x": rng.randint(10, 310), "y": rng.randint(10, 235),
            "ms": 800 if kind == "long_touch" else 100}


def ended_report(ids: list[int], heard: list[dict], excused: int) -> dict:
    """How the board said the reactions it was sent ended: each id exactly
    once (PROTOCOL.md §4). A moment line the board never got has none, and
    an `ended` that lost bytes on the way back can't be read, so up to
    `excused` (lines lost either way) may be missing."""
    counts: dict[int, int] = {}
    hows: dict[str, int] = {}
    for m in heard:
        counts[m.get("id")] = counts.get(m.get("id"), 0) + 1
        how = str(m.get("how")) + (f" ({m['why']})" if m.get("why") else "")
        hows[how] = hows.get(how, 0) + 1
    sent = set(ids)
    missing = [i for i in ids if i not in counts]
    report = {"reactions": len(ids), "ended": len(heard), "ended_how": hows, "ended_missing": missing,
              "ended_twice": sorted(i for i, n in counts.items() if n > 1),
              "ended_unknown": sorted(i for i in counts if i not in sent)}
    report["ended_ok"] = not report["ended_twice"] and not report["ended_unknown"] and len(missing) <= excused
    return report


def cmd_soak(args: argparse.Namespace) -> int:
    """Random, realistic traffic and inputs with the clock running, brain
    reactions with ids and loops among them, then checks for resets, a
    drifting heap minimum, stuck states, lost lines, audio errors and an
    `ended` for every reaction. With --pipeline, the e2e fixtures on a loop
    through the headless app instead (J2's soak)."""
    if args.pipeline:
        from boopctl_lib import e2e

        return e2e.soak(Path(args.out or "/tmp/boop-e2e-out"), args.brain, args.port, args.minutes)
    rng = random.Random(args.seed)
    samples, glitches, heard, ids = [], [], [], []
    sent = {"state": 0, "moment": 0}
    with Device(args.port) as dev:
        start = time.monotonic()

        # The CH340 now and then drops bytes over a long run: a debug
        # request whose reply is lost is asked again once, and counted.
        def glitch(exc: Exception) -> None:
            glitches.append(f"{time.monotonic() - start:.0f} s: {exc}"[:160])

        dev.retries, dev.on_retry = 1, glitch
        dev.heard = lambda m: heard.append(m) if m.get("t") in ("ended", "torn") else None

        def send(msg: dict) -> None:
            dev.send(msg)
            sent[msg["t"]] += 1

        dev.request({"t": "dbg.reset"})
        rx0 = dev.request({"t": "dbg.state"})["rx"]
        dev.request({"t": "dbg.clock", "run": True})
        next_ping = 0.0
        silent_until = 0.0
        state = soak_state(rng, args.vol)
        last_state = -100.0
        silence_done = False
        while (elapsed := time.monotonic() - start) < args.minutes * 60:
            r = rng.random()
            if not silence_done and elapsed > args.minutes * 30:
                silent_until, silence_done = elapsed + 35, True  # once: the Mac goes away, "no app"
            if elapsed >= silent_until:
                if r < 0.25:
                    state = soak_state(rng, args.vol)
                    send(state)
                    last_state = elapsed
                elif r < 0.4:
                    send(soak_moment(rng))
                elif r < 0.5:
                    ids.append(len(ids) + 1)
                    send(soak_reaction(rng, ids[-1]))
                elif r < 0.7:
                    dev.request(soak_input(rng))
                if elapsed - last_state >= 10:
                    send(state)  # the Mac's 10 s snapshot
                    last_state = elapsed
            if elapsed >= next_ping:
                samples.append({"t": round(elapsed, 1), **dev.vitals()})
                next_ping = elapsed + 5
            time.sleep(rng.uniform(0.2, 1.5))
        # Stuck? Calm snapshots must bring back the plain face once the
        # last press (held ≤ 3 s, then listening waits ≤ 8 s for a reply)
        # and moment are over: a reaction's face can hold 6 loops of a 9 s
        # design.
        calm = {"t": "state", "base": "idle", "busy": 0, "vol": args.vol}
        settle_by = time.monotonic() + 75
        while True:
            send(calm)
            time.sleep(5)
            final = dev.request({"t": "dbg.state"})
            plain = final.get("screen") == "face" and final.get("moment") is None and final.get("expr") is None
            if plain or time.monotonic() > settle_by:
                break
        samples.append({"t": round(time.monotonic() - start, 1), **dev.vitals()})
        # Whatever reaction still plays is cut by the reset; its `ended`
        # comes with the reply.
        dev.request({"t": "dbg.reset"})
        dev.request({"t": "dbg.ping"})
    rx1 = final.get("rx", {})
    lost = {k: sent[k] - (rx1.get(k, 0) - rx0.get(k, 0)) for k in sent}
    early = [s["heap_min"] for s in samples if s["t"] >= 60] or [samples[0]["heap_min"]]
    result = {
        "minutes": args.minutes,
        "samples": len(samples),
        "reset": restarted([s["up"] for s in samples]),
        "heap_min_start": early[0],
        "heap_min_end": samples[-1]["heap_min"],
        "heap_min_drift": early[0] - samples[-1]["heap_min"],
        "final_screen": final.get("screen"),
        "final_moment": final.get("moment"),
        "final_expr": final.get("expr"),
        "answering": final.get("t") == "dbg.state",
        "sent": sent,
        "lost": lost,
        "audio_errors": final.get("audio", {}).get("out", {}).get("errors"),
        "link_glitches": glitches,
        "torn_lines": sum(m["t"] == "torn" for m in heard),
    }
    excused = lost["moment"] + result["torn_lines"] + len(glitches)
    result.update(ended_report(ids, [m for m in heard if m["t"] == "ended"], excused))
    result["ok"] = (not result["reset"] and result["heap_min_drift"] <= 2048 and result["answering"]
                    and result["final_screen"] == "face" and result["final_moment"] is None
                    and result["final_expr"] is None and not result["audio_errors"] and result["ended_ok"])
    if args.out:
        Path(args.out).write_text(json.dumps({**result, "series": samples}, indent=1))
    emit(result)
    return 0 if result["ok"] else 1


def cmd_cam(args: argparse.Namespace) -> int:
    from boopctl_lib import cam

    camera = args.camera or cam.CAMERA
    with Device(args.port) as dev:
        if args.action == "frame":
            result = cam.frame(dev, args.usb, camera)
        elif args.action == "clip":
            if not args.name:
                raise DeviceError(f"cam clip needs a name: {', '.join(cam.CLIPS)}")
            result = cam.clip(dev, args.name, camera, args.seconds)
        else:
            result = cam.pattern(dev, camera)
    emit(result)
    return 0 if result["ok"] else 1


def cmd_e2e(args: argparse.Namespace) -> int:
    from boopctl_lib import e2e

    return e2e.main(Path(args.out), args.brain, args.port, args.fixture or None, args.clip, args.camera)


def cmd_bridge(args: argparse.Namespace) -> int:
    from boopctl_lib.bridge import bridge_path, serve

    return serve(args.port, args.socket or bridge_path(), quiet=args.quiet)


# Hearing and watching Boop by hand: takes and play drive the board over
# USB the way the Mac would, and read dbg.state to say whether it happened.
# The Mac app, if it's connected over Bluetooth, keeps sending its own
# `state` and can override these.


def show_begin(dev: Device, warn: bool = True) -> dict:
    """Lets the clock run (a scenario may have frozen it) and, with `warn`,
    warns when the Mac app is connected, since its next `state` wins. These
    commands poll dbg.state often, and the CH340 now and then drops a reply,
    so a debug request is retried once (Link.retries). Returns dbg.ping."""
    dev.retries = 1
    ping = dev.request({"t": "dbg.ping"})
    if warn and ping.get("ble") == "conn":
        print("boopctl: the Mac app is connected over Bluetooth and may override this; "
              "quit it for a clean run", file=sys.stderr)
    dev.request({"t": "dbg.clock", "run": True})
    return ping


def show_state(dev: Device, vol: int, base: str = "idle", attn: dict | None = None, mood: str = "happy") -> None:
    """A minimal `state`. Resent at least every 10 s, since the board shows
    "no app" after 30 s without one (PROTOCOL.md §3)."""
    msg = {"t": "state", "base": base, "mood": mood, "vol": vol}
    if attn:
        msg["attn"] = attn
    dev.send(msg)


def play_line(dev: Device, say: dict) -> tuple[int, dict, bool]:
    """Plays one line on its own and waits up to 6 s for the board to
    finish it. Returns how many lines finished meanwhile (1 when it played),
    the last dbg.state, and whether the amp was on at any point."""
    before = dev.request({"t": "dbg.state"})["audio"]["out"]["lines"]
    dev.send({"t": "moment", "say": say})
    deadline = time.monotonic() + 6
    amp = False
    while True:
        st = dev.request({"t": "dbg.state"})
        amp |= st["amp"]
        if st["audio"]["out"]["lines"] > before or time.monotonic() > deadline:
            return st["audio"]["out"]["lines"] - before, st, amp
        time.sleep(0.05)


def check_take(dev: Device, t: Take) -> dict:
    """Plays one take and checks `audio.out` in dbg.state against it: the
    take, and the time the DAC took within 10% of the take's length (L2).
    Waits up to 6 s for it to finish."""
    finished, st, amp_seen = play_line(dev, {"take": t.id})
    out = st["audio"]["out"]
    played = finished > 0
    r = {"take": t.id, "text": t.text, "plan_ms": t.ms, "played": played,
         "got": {k: out[k] for k in ("take", "plan_ms", "out_ms", "wall_ms", "cut")} if played else None,
         "amp_on": amp_seen, "vol": st.get("vol")}
    r["ok"] = (finished == 1 and out["take"] == t.id
               and abs(out["plan_ms"] - t.ms) <= 1 and abs(out["out_ms"] - t.ms) <= 1
               and abs(out["wall_ms"] - t.ms) <= t.ms // 10 and not out["cut"] and amp_seen)
    return r


def line_row(r: dict) -> str:
    head = f"{'ok ' if r['ok'] else 'BAD'} {r['take']:16} {r['text']!r:22}"
    if not r["played"]:
        return f"{head} didn't play"
    wall = r["got"]["wall_ms"]
    return (f"{head} plan {r['plan_ms']:5} ms  dac {wall:5} ms  ({(wall - r['plan_ms']) * 100 / r['plan_ms']:+.1f}%)"
            f"  amp {'on' if r['amp_on'] else 'OFF'}" + (", cut short" if r["got"]["cut"] else ""))


def chosen_takes(only: str | None) -> list[Take]:
    """Every take, or with `only` those whose id starts with it, or whose
    text is it or has it as a word, in any case and without its dots and
    marks ("again", "mamma mia", "previous.", "new.d15")."""
    if not only:
        return list(takes())
    want = only.lower().strip(".?! ")
    picked = [t for t in takes() if t.id.startswith(only) or want == t.text.lower().strip(".?! ")
              or want in t.text.lower().replace(".", " ").replace("?", " ").split()]
    if not picked:
        raise DeviceError(f"no take's id or text matches {only!r}")
    return picked


def cmd_takes(args: argparse.Namespace) -> int:
    """For hearing Boop by hand, and L2's voice check: every take (or those
    --only picks) in turn on its own, each checked with check_take. Then
    checks that a muted line moves the mouth and plays nothing.
    --board-volume and --levels play one take instead (take_at_board_volume,
    take_levels)."""
    chosen = chosen_takes(args.only)
    if args.levels:
        return take_levels(args, chosen[0])
    if args.board_volume:
        return take_at_board_volume(args, chosen[0])
    results = []
    with Device(args.port) as dev:
        show_begin(dev)
        for t in chosen:
            show_state(dev, args.vol)
            r = check_take(dev, t)
            results.append(r)
            if not args.json:
                print(line_row(r), flush=True)
            time.sleep(args.gap)
        # Muted: the mouth still moves, the DAC stays off.
        show_state(dev, 0)
        before = dev.request({"t": "dbg.state"})["audio"]["out"]["lines"]
        dev.send({"t": "moment", "say": {"take": chosen[0].id}})
        mouth = dev.request({"t": "dbg.state"})["audio"]["playing"]
        time.sleep(chosen[0].ms / 1000 + 1.5)
        st = dev.request({"t": "dbg.state"})
        muted = {"mouth_moved": mouth, "lines_played": st["audio"]["out"]["lines"] - before, "amp": st["amp"]}
        show_state(dev, args.vol)
    walls = [abs(r["got"]["wall_ms"] - r["plan_ms"]) * 100 / r["plan_ms"] for r in results if r["played"]]
    summary = {"takes": len(results), "passed": sum(r["ok"] for r in results),
               "worst_wall_error_pct": round(max(walls), 1) if walls else None, "muted": muted,
               "ok": all(r["ok"] for r in results) and muted["mouth_moved"] and not muted["lines_played"]}
    emit({"results": results, **summary} if args.json else summary)
    return 0 if summary["ok"] else 1


def take_at_board_volume(args: argparse.Namespace, t: Take) -> int:
    """One take. It sends no `state`, so it plays at whatever volume the
    board already has: the Mac app's, when it's connected, for trying the
    app's volume setting."""
    with Device(args.port) as dev:
        mac = show_begin(dev, warn=False).get("ble") == "conn"
        st = dev.request({"t": "dbg.state"})
        vol = st.get("vol")
        print(f"volume {vol} ({'the Mac app' if mac else 'the last `state` the board got; the Mac app is not connected'})")
        why = "muted (volume 0)" if vol == 0 else "something needs you" if st["attn"] else None
        if why:
            print(f"not playing: the board is {why}, so it won't speak")
            return 1
        r = check_take(dev, t)
    print(line_row(r))
    return 0 if r["ok"] else 1


def take_levels(args: argparse.Namespace, t: Take) -> int:
    """The same take at each level in turn, round after round, for
    comparing by ear, and whether the board played each one in full."""
    missed = 0
    with Device(args.port) as dev:
        show_begin(dev)
        for i in range(args.rounds):
            for vol in args.levels:
                show_state(dev, vol)
                finished, st, _ = play_line(dev, {"take": t.id})
                out = st["audio"]["out"] if finished else None
                missed += out is None or out["cut"]
                print(f"round {i + 1} vol {vol:2} {t.text!r}: "
                      + (f"played {out['out_ms']} ms" + (", cut short" if out["cut"] else "") if out else "didn't play"),
                      flush=True)
                time.sleep(args.gap)
    return 1 if missed else 0


def cmd_play(args: argparse.Namespace) -> int:
    """One thing the Mac can make the board do, checked through dbg.state:
    an animation from the set (BEHAVIORS.md §5), --loops times, with --take
    a take over it (from the design's voice window); `needs`, a fake
    "needs you" (play_needs); or the bring-up `pattern`. `cheer` and
    `wiggle` are the older names of task_complete's success and poked."""
    if (args.take or args.loops or args.outcome or args.ctx or args.variant) and args.what in ("needs", "pattern"):
        raise DeviceError(f"play {args.what} takes no --take, --loops, --outcome, --ctx or --variant")
    if args.what == "pattern":
        with Device(args.port) as dev:
            dev.request({"t": "dbg.pattern"})
        print("pattern: showing until the next state")
        return 0
    if args.what == "needs":
        return play_needs(args)
    with Device(args.port) as dev:
        show_begin(dev)
        show_state(dev, args.vol, base=args.base, mood=args.mood)
        msg = {"t": "moment", "anim": args.what}
        for key in ("loops", "variant", "outcome", "ctx"):
            if getattr(args, key):
                msg[key] = getattr(args, key)
        if args.take:
            msg["say"] = {"take": args.take}
        dev.send(msg)
        moment = dev.request({"t": "dbg.state"}).get("moment")
    ok = bool(moment) and moment.get("anim") == OLD_ANIMS.get(args.what, args.what)
    print(f"{args.what}: " + (f"playing variation {moment.get('variant')}, {moment['left_ms']} ms" if ok
                              else f"not playing ({moment})")
          + (f", saying {take(args.take).text!r}" if args.take else ""))
    return 0 if ok else 1


def play_needs(args: argparse.Namespace) -> int:
    """Holds a "needs you" for a while (BEHAVIORS.md §3.2): its performance
    with knocks and the ding, amber at half, the face turned to you. Prints
    what the board shows and whether the ding was sent (VOICE.md §10), then
    clears it, and the face blends back. Ctrl-C clears it early."""
    attn = {"agent": args.agent, "project": args.project, "more": args.more}
    alert = ding = None
    with Device(args.port) as dev:
        show_begin(dev)
        start = time.monotonic()
        resend = None
        shown = False
        try:
            while (now := time.monotonic()) - start < args.seconds:
                if resend is None or now >= resend:
                    show_state(dev, args.vol, attn=attn, mood=args.mood)
                    resend = now + 10
                if ding is None and now - start < 8:
                    st = dev.request({"t": "dbg.state"})
                    alert = st.get("alert")
                    if ((st.get("audio") or {}).get("fx") or {}).get("last") == "alertDing":
                        ding = now - start
                    if not shown and now - start >= 0.3:
                        print(f"{now - start:6.1f} s  screen {st['screen']}  led {st['led']}  bl {st['bl']}", flush=True)
                        shown = True
                time.sleep(0.25)
        except KeyboardInterrupt:
            pass
        finally:
            show_state(dev, args.vol, mood=args.mood)
    print("alert: " + ("started" if alert is not None else "not started"))
    print("ding: " + (f"sent at {ding:.1f} s" if ding is not None else "not sent"))
    print("cleared: Boop goes back to idle")
    return 0 if alert is not None and ding is not None else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="boopctl", description="Talk to the Boop board over USB (plan/VERIFICATION.md §2).")
    parser.add_argument("--port", help="serial port (default: $BOOP_PORT or the first /dev/cu.usbserial-*)")
    sub = parser.add_subparsers(dest="command", required=True, metavar="command")
    sub.add_parser("ping", help="firmware version, uptime, heap, fps, link").set_defaults(func=cmd_ping)
    sub.add_parser("state", help="the device's own view of itself").set_defaults(func=cmd_state)
    p = sub.add_parser("shot", help="screenshot the device's canvas")
    p.add_argument("--out", default="/tmp/boop-shot.png")
    p.set_defaults(func=cmd_shot)
    p = sub.add_parser("send", help="send one protocol message; a dbg.* request prints the reply")
    p.add_argument("message", help="""JSON, e.g. '{"t":"dbg.press","ms":100}' or '{"t":"dbg.clock","run":true}'""")
    p.set_defaults(func=cmd_send)
    vol = {"type": int, "choices": range(1, 11), "default": 6, "metavar": "1-10", "help": "volume (default 6)"}
    p = sub.add_parser("play", help="play an animation (with --take, a take over it), a fake needs-you "
                                    "with its ding, or the bring-up pattern")
    p.add_argument("what", choices=ANIMS + list(OLD_ANIMS) + ["needs", "pattern"],
                   help=", ".join(ANIMS + list(OLD_ANIMS)) + "; needs; pattern")
    p.add_argument("--take", choices=[t.id for t in takes()], metavar="ID",
                   help="a take over it, by id (`boopctl takes` lists them)")
    p.add_argument("--loops", type=int, choices=range(1, 7), metavar="1-6",
                   help="how many times the animation's design plays (PROTOCOL.md §3; the device reads none as 1)")
    p.add_argument("--variant", type=int, choices=range(1, 10), metavar="1-9",
                   help="which variation; the device picks one that fits when it's none or doesn't fit")
    p.add_argument("--outcome", choices=OUTCOMES, help="task_complete: the turn's result")
    p.add_argument("--ctx", choices=CTXS, help="starting: what started")
    p.add_argument("--base", choices=["idle", "working", "asleep"], default="idle")
    p.add_argument("--mood", choices=MOODS, default="happy", help="the mood the state carries (default happy)")
    p.add_argument("--vol", **vol)
    p.add_argument("--seconds", type=float, default=10, help="needs: how long to hold it (default 10)")
    p.add_argument("--agent", choices=["claude", "codex"], default="claude", help="needs: who asks")
    p.add_argument("--project", default="boopctl", help="needs: the project shown")
    p.add_argument("--more", type=int, default=0, help="needs: how many more are waiting")
    p.set_defaults(func=cmd_play)
    p = sub.add_parser("takes", help="play and check every take, or those --only picks, one after another; "
                                     "then check mute (L2)")
    p.add_argument("--only", metavar="TEXT", help="takes whose id starts with this, or whose text has it (any case)")
    p.add_argument("--vol", **vol)
    p.add_argument("--gap", type=float, default=0.8, help="seconds between takes (default 0.8)")
    p.add_argument("--json", action="store_true", help="every take's result as JSON")
    how = p.add_mutually_exclusive_group()
    how.add_argument("--board-volume", action="store_true",
                     help="the first take at the volume the board has (the Mac app's), sending no state")
    how.add_argument("--levels", nargs="+", type=int, choices=range(1, 11), metavar="LEVEL",
                     help="compare volumes by ear: the first take at each level in turn, --rounds times")
    p.add_argument("--rounds", type=int, default=6, help="with --levels (default 6)")
    p.set_defaults(func=cmd_takes)
    p = sub.add_parser("card", help="copy the voice pack onto the board's microSD card over USB, unless it has it; "
                                    "goes on where a cut-off copy stopped (about 15-30 min for the whole pack)")
    p.add_argument("--pack", default=str(PACK), help="the pack (default: .build/voice/voice.bin)")
    p.add_argument("--force", action="store_true", help="copy even when the card has this version")
    p.add_argument("--fresh", action="store_true", help="start again rather than go on from an earlier copy")
    p.set_defaults(func=cmd_card)
    p = sub.add_parser("sim", help="play scenarios in the simulator and compare with the goldens (L1)")
    p.add_argument("scenario", nargs="*", help="names or paths (default: all)")
    p.add_argument("--accept", action="store_true", help="copy the pictures into the goldens (after looking!)")
    p.set_defaults(func=cmd_sim)
    p = sub.add_parser("run", help="play scenarios on the device and compare with the simulator (L2)")
    p.add_argument("scenario", nargs="*", help="names or paths (default: all)")
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("perf", help="sample fps, frame time and heap; --motion keeps the face moving")
    p.add_argument("--seconds", type=int, default=30)
    p.add_argument("--motion", action="store_true")
    p.set_defaults(func=cmd_perf)
    p = sub.add_parser("soak", help="random realistic traffic and inputs; checks resets, leaks, stuck states "
                                    "(--pipeline: the e2e fixtures on a loop)")
    p.add_argument("--minutes", type=float, default=20)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--out", help="write the result as JSON here (--pipeline: a directory, default /tmp/boop-e2e-out)")
    p.add_argument("--pipeline", action="store_true",
                   help="through the headless app: hooks, a tap between rounds, then a quiet minute (J2)")
    p.add_argument("--brain", default="scripted", choices=["scripted", "jev"],
                   help="with --pipeline: the headless app's brain; jev needs BOOP_JEV_KEY (default: scripted)")
    p.add_argument("--vol", type=int, default=6, choices=range(0, 11), metavar="0-10",
                   help="the volume every state carries (default 6); 1 keeps a night run quiet")
    p.set_defaults(func=cmd_soak)
    p = sub.add_parser("e2e", help="the pipeline check: hooks → headless app → bridge → board (L4)")
    p.add_argument("--brain", default="scripted", choices=["scripted", "jev"],
                   help="the headless app's brain: scripted answers every pass the same way; jev needs BOOP_JEV_KEY "
                        "(default: scripted)")
    p.add_argument("--out", default="/tmp/boop-e2e-out", help="results, logs and screenshots")
    p.add_argument("fixture", nargs="*", help="paths under internal/app/Tests/Fixtures/hooks/e2e (default: all three)")
    p.add_argument("--clip", action="store_true",
                   help="first film a 10 s Claude session on the webcam (authorised runs only; §6)")
    p.add_argument("--camera", help="with --clip: the camera id (default: $BOOP_CAMERA or the built-in one)")
    p.set_defaults(func=cmd_e2e)
    p = sub.add_parser("bridge", help="own the serial port and share it on a Unix socket")
    p.add_argument("--socket", help="socket path (default: $BOOP_BRIDGE or /tmp/boop-bridge.sock)")
    p.add_argument("--quiet", action="store_true")
    p.set_defaults(func=cmd_bridge)
    p = sub.add_parser("cam", help="webcam helpers (opt-in; plan/VERIFICATION.md §6)")
    p.add_argument("action", choices=["frame", "pattern", "clip"])
    p.add_argument("name", nargs="?", help="clip: idle, needs_you, cheer or tap")
    p.add_argument("--seconds", type=int, default=8, help="clip length, at most 10")
    p.add_argument("--usb", default="left", choices=["bottom", "right", "top", "left"],
                   help="where USB-C is in the camera's view (frame only); left means upright")
    p.add_argument("--camera", help="the camera id, from internal/tools/webcam/webcam.sh list "
                                    "(default: $BOOP_CAMERA or the built-in one)")
    p.set_defaults(func=cmd_cam)
    p = sub.add_parser("dash", help="the live dashboard: Boop now with its face, and its mood, automatic reactions "
                                    "and decided reactions side by side, from debug.jsonl; keys force a mood, a "
                                    "reaction or an animation")
    p.add_argument("--state-dir", help="the app's state directory, where Boop --debug writes debug.jsonl "
                                       "(default: the everyday app's, ~/Library/Application Support/Boop)")
    p.add_argument("--socket", help="the app's hook socket (default: STATE-DIR/boop.sock)")
    p.set_defaults(func=cmd_dash)
    p = sub.add_parser("day", help="what Boop did in a day, and why, by the hour: from debug.jsonl and the "
                                   "earlier launches' debug.<n>.jsonl")
    p.add_argument("--state-dir", help="the app's state directory (default: the everyday app's, "
                                       "~/Library/Application Support/Boop)")
    p.add_argument("--date", type=a_date, help="the local day, YYYY-MM-DD (default: the newest line's)")
    p.add_argument("file", nargs="*", help="read these debug logs instead, oldest launch first")
    p.set_defaults(func=cmd_day)
    workday.add_parser(sub)
    p = sub.add_parser("calibrate", help="touch calibration: tap 4 crosses (needs a person); kept in NVS")
    p.add_argument("--show", action="store_true", help="print the stored calibration instead")
    p.add_argument("--clear", action="store_true", help="with --show: forget it (back to the default raw range)")
    p.set_defaults(func=cmd_calibrate)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (DeviceError, FileNotFoundError) as exc:
        print(f"boopctl: {exc}", file=sys.stderr)
        return 2
