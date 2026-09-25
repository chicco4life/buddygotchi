"""The pipeline check (plan/VERIFICATION.md L4): hook → app → USB → device.

Starts `boopctl bridge` and a headless app with throwaway state, sends each
fixture's payloads through the real `boop-hook`, and checks the device's
`dbg.state` at every checkpoint. Latency is hook launch to the device having
received the new `state` (its `rx.state` count going up), on the host clock.

Fixture lines, besides hook payloads:
  {"wait_ms": N}                         sleep
  {"advance_ms": N}                      jump the app's clock (a long turn without the wait)
  {"expect": {...}, "within_ms": N}      poll dbg.state until it matches (default 2000 ms)
  {"expect_not": {...}, "for_ms": N}     dbg.state must not match for that long
  {"expect_not": {...}, "until_ms": N}   … until N ms after the last hook was launched
  "shot": "name" on an expect line       also save a screenshot
"""
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import socket
import subprocess
import time
from pathlib import Path
from typing import Any

from boopctl_lib.device import Device, DeviceError
from boopctl_lib.image import save_shot
from boopctl_lib.scenario import matches

REPO = Path(__file__).resolve().parents[2]
BIN = REPO / "app" / ".build" / "debug"
FIXTURES = REPO / "app" / "Tests" / "Fixtures" / "hooks" / "e2e"
RUN_ORDER = ["claude/session.jsonl", "codex/quick.jsonl", "codex/slow.jsonl"]
# How long a hook's `state` may take before it counts as "no new state". A
# later one still fails the checkpoint that expects the change.
STATE_WAIT = 0.5


def percentile(values: list[float], p: float) -> float:
    s = sorted(values)
    if not s:
        return 0.0
    k = max(0, min(len(s) - 1, int(-(-len(s) * p // 1)) - 1))
    return s[k]


class Run:
    def __init__(self, root: Path, out: Path, brain: str, port: str | None) -> None:
        self.root = root
        self.out = out
        self.brain = brain
        self.port = port
        self.state = root / "state"
        self.bridge_sock = str(root / "usb.sock")
        self.hook_sock = str(root / "boop.sock")
        self.log: list[str] = []
        self.failures: list[str] = []
        self.hooks: list[dict[str, Any]] = []
        self.procs: list[subprocess.Popen] = []
        self.last_hook = time.monotonic()

    def say(self, line: str) -> None:
        print(line, flush=True)
        self.log.append(line)

    def fail(self, line: str) -> None:
        self.failures.append(line)
        self.say("FAIL " + line)

    # Processes

    def start(self) -> None:
        if self.root.exists():
            shutil.rmtree(self.root)
        self.root.mkdir(parents=True)
        self.out.mkdir(parents=True, exist_ok=True)
        for name in ("Boop", "boop-hook", "boopdev"):
            if not (BIN / name).exists():
                raise DeviceError(f"no {BIN / name}; run make build")
        bridge = [str(REPO / "tools" / "boopctl")] + (["--port", self.port] if self.port else [])
        bridge += ["bridge", "--socket", self.bridge_sock, "--quiet"]
        self.procs.append(subprocess.Popen(bridge, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        self._wait_for(lambda: os.path.exists(self.bridge_sock), 10, "the bridge's socket")
        app = [str(BIN / "Boop"), "--headless", "--state-dir", str(self.state), "--link", f"usb:{self.bridge_sock}",
               "--socket", self.hook_sock, "--brain", self.brain, "--name", "Pip", "--trace",
               "--debug-log", str(self.root / "brain.jsonl")]
        self.procs.append(subprocess.Popen(app, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        self._wait_for(lambda: "device link: connected" in self.app_log(), 10, "the app to reach the bridge")
        # The first launch of a freshly built boop-hook is slow (~270 ms) while
        # macOS checks the new binary; agents run it hundreds of times a day.
        # Warm it once, against a socket nobody listens on.
        subprocess.run([str(BIN / "boop-hook"), "claude"], input=b"{}",
                       env=dict(os.environ, BOOP_SOCKET=str(self.root / "none.sock")))
        self.say(f"bridge and headless app up (brain {self.brain}, state {self.state})")

    def stop(self) -> None:
        for proc in reversed(self.procs):
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                try:
                    code = proc.wait(10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    code = "killed"
                self.say(f"{Path(proc.args[0]).name} exit {code}")
        self.procs = []

    def _wait_for(self, ok, seconds: float, what: str) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if ok():
                return
            time.sleep(0.05)
        raise DeviceError(f"timed out waiting for {what}")

    def app_log(self) -> str:
        path = self.state / "boop.log"
        return path.read_text() if path.exists() else ""

    # Steps

    def hook(self, dev: Device, agent: str, payload: str) -> None:
        before = dev.request({"t": "dbg.state"})["rx"]["state"]
        env = dict(os.environ, BOOP_SOCKET=self.hook_sock)
        t0 = self.last_hook = time.monotonic()
        proc = subprocess.run([str(BIN / "boop-hook"), agent], input=payload.encode(), env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        hook_ms = (time.monotonic() - t0) * 1000
        name = json.loads(payload).get("hook_event_name", "?")
        if proc.returncode != 0 or proc.stdout or proc.stderr:
            self.fail(f"boop-hook {name}: exit {proc.returncode}, printed {len(proc.stdout) + len(proc.stderr)} bytes")
        latency = None
        while time.monotonic() - t0 < STATE_WAIT:
            if dev.request({"t": "dbg.state"})["rx"]["state"] > before:
                latency = (time.monotonic() - t0) * 1000
                break
        self.hooks.append({"agent": agent, "hook": name, "hook_ms": round(hook_ms, 1),
                           "state_ms": None if latency is None else round(latency, 1)})
        self.say(f"  {agent} {name}: boop-hook {hook_ms:.0f} ms, " +
                 (f"state on the device after {latency:.0f} ms" if latency is not None else "no new state"))

    def advance(self, ms: int) -> None:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(self.hook_sock)
            s.sendall(json.dumps({"dev": "advance", "ms": ms}).encode() + b"\n")
        time.sleep(0.3)
        self.say(f"  app clock +{ms / 1000:.0f} s")

    def expect(self, dev: Device, step: dict[str, Any], where: str) -> None:
        want = step["expect"]
        end = time.monotonic() + step.get("within_ms", 2000) / 1000
        state: dict[str, Any] = {}
        t0 = time.monotonic()
        while True:
            state = dev.request({"t": "dbg.state"})
            if matches(want, state):
                self.say(f"  ok {json.dumps(want)} after {(time.monotonic() - t0) * 1000:.0f} ms")
                break
            if time.monotonic() > end:
                keys = {k: state.get(k) for k in ("screen", "base", "attn", "rung", "moment")}
                self.fail(f"{where}: expected {json.dumps(want)}, got {json.dumps(keys)}")
                break
        if step.get("shot"):
            palette, pixels = dev.shot()
            path = save_shot(palette, pixels, self.out / f"{step['shot']}.png")
            self.say(f"  shot {path}")

    def expect_not(self, dev: Device, step: dict[str, Any], where: str) -> None:
        want = step["expect_not"]
        if "until_ms" in step:
            end = self.last_hook + step["until_ms"] / 1000
        else:
            end = time.monotonic() + step.get("for_ms", 1000) / 1000
        while time.monotonic() < end:
            state = dev.request({"t": "dbg.state"})
            if matches(want, state):
                self.fail(f"{where}: {json.dumps(want)} showed up too early")
                return
        self.say(f"  ok not {json.dumps(want)} until {(end - self.last_hook) * 1000:.0f} ms after the last hook")

    def fixture(self, dev: Device, path: Path) -> None:
        agent = "codex" if "/codex/" in str(path) else "claude"
        self.say(f"## {path.relative_to(REPO)}")
        for n, raw in enumerate(path.read_text().splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            step = json.loads(line)
            where = f"{path.name}:{n}"
            if "hook_event_name" in step:
                self.hook(dev, agent, line)
            elif "wait_ms" in step:
                time.sleep(step["wait_ms"] / 1000)
            elif "advance_ms" in step:
                self.advance(step["advance_ms"])
            elif "expect" in step:
                self.expect(dev, step, where)
            elif "expect_not" in step:
                self.expect_not(dev, step, where)
            else:
                self.fail(f"{where}: unknown step {line}")


def check_after(run: Run, expected: dict[str, Any]) -> None:
    """The memory files, settings and logs once the app has stopped."""
    long_term = (run.state / "long-term.md").read_text()
    short_term = (run.state / "short-term.md").read_text()
    m = re.search(r"xp: (\d+) · level: (\d+) · last fed: (\S+)", long_term)
    if not m:
        run.fail("long-term.md has no Growth line")
    else:
        xp, level = int(m.group(1)), int(m.group(2))
        ok = xp == expected["xp"] and level == expected["level"]
        (run.say if ok else run.fail)(f"growth: xp {xp} level {level} last fed {m.group(3)} "
                                      f"(expected xp {expected['xp']} level {expected['level']})")
    happened = short_term.split("## Happened", 1)[-1]
    for want in expected["happened"]:
        count = happened.count(want)
        need = expected["happened"].count(want)
        (run.say if count >= need else run.fail)(f"short-term Happened has {want!r} ×{count}")
    settings = json.loads((run.state / "settings.json").read_text())
    ok = settings.get("finished") == expected["finished"] and sorted(settings.get("projects", [])) == expected["projects"]
    (run.say if ok else run.fail)(f"settings: finished {settings.get('finished')}, projects {settings.get('projects')}")
    brain_log = (run.root / "brain.jsonl").read_text() if (run.root / "brain.jsonl").exists() else ""
    for want in expected["triggers"]:
        (run.say if want in brain_log else run.fail)(f"brain saw a trigger with {want!r}: {want in brain_log}")
    # Nothing private may reach the app's files or the brain.
    leaks = []
    for f in list(run.state.rglob("*")) + [run.root / "brain.jsonl"]:
        if f.is_file() and "PRIVATE_" in f.read_text(errors="replace"):
            leaks.append(str(f))
    (run.fail if leaks else run.say)(f"PRIVATE_ markers in app files or the brain log: {leaks or 'none'}")


def play_ms(moment: dict[str, Any]) -> int:
    """How long the device plays a moment: firmware/src/render/anim.cpp's
    animDuration, or the mumble if longer (as DeviceMoment.playMs)."""
    size = max(1, min(3, moment.get("size", 1)))
    anim = moment.get("anim")
    table = {"listening": 0, "thinking": 0, "nod": 600, "cheer": (size + 1) * 380 + 500, "oops": 1400,
             "stretch": 1400, "side_eye": 1600, "yawn": 1600, "wiggle": 700, "shrug": 1200, "zip": 1500,
             "gobble": 1500, "rumble": 1500, "levelup": 2400}
    say = moment.get("say") or {}
    syllables = sum(len(g.split("-")) for g in say.get("syl", "").split()) if say else 0
    return max(table.get(anim, 2500), syllables * say.get("ms", 0))


def check_order(run: Run) -> dict[str, Any]:
    """The brain's moments come after the rules' reaction and never cut a
    rule moment short.

    With --trace the app logs `hook: …` for each hook and `link rules → …` or
    `link brain → …` for each line sent to the device. For every brain
    moment: the rules' reaction to the last hook came first, and the last
    rule moment had finished playing."""
    stamp = re.compile(r"^(\d\d):(\d\d):(\d\d)\.(\d\d\d) (.*)$")
    answers = []
    last_hook: str | None = None
    reaction: int | None = None
    rule_moment: tuple[int, str, int] | None = None  # sent, anim, ends
    brain_ends = 0
    cut: list[str] = []  # brain moments a later rule moment replaced (a new hook may; for the record)
    for raw in run.app_log().splitlines():
        m = stamp.match(raw)
        if not m:
            continue
        h, mi, s, ms, text = m.groups()
        t = (int(h) * 3600 + int(mi) * 60 + int(s)) * 1000 + int(ms)
        if text.startswith("hook: "):
            last_hook = text[6:]
        elif text.startswith("link rules → "):
            if last_hook and (reaction is None or reaction[1] != last_hook):
                reaction = (t, last_hook)
            line = json.loads(text[len("link rules → "):])
            if line.get("t") == "moment":
                rule_moment = (t, line["anim"], t + play_ms(line))
                if t < brain_ends:
                    cut.append(f"{raw[:12]} {line['anim']} after {last_hook}")
        elif text.startswith("link brain → "):
            brain_line = json.loads(text[len("link brain → "):])
            anim = brain_line.get("anim", "?")
            brain_ends = t + play_ms(brain_line)
            answers.append({
                "moment": anim, "at": raw[:12],
                "after_reaction_ms": None if reaction is None else t - reaction[0],
                "reaction_to": None if reaction is None else reaction[1],
                "last_rule_moment": None if rule_moment is None else rule_moment[1],
                "after_rule_moment_ended_ms": None if rule_moment is None else t - rule_moment[2],
            })
    bad = [a for a in answers if a["after_reaction_ms"] is None or a["after_reaction_ms"] <= 0
           or (a["after_rule_moment_ended_ms"] is not None and a["after_rule_moment_ended_ms"] < 0)]
    for a in answers:
        run.say(f"  {a['at']} brain {a['moment']}: {a['after_reaction_ms']} ms after the rules' reaction to "
                f"{a['reaction_to']}; last rule moment {a['last_rule_moment']} ended "
                f"{a['after_rule_moment_ended_ms']} ms before")
    run.say(f"brain moments: {len(answers)}, early: {len(bad)}, later replaced by a rule moment: {cut or 'none'}")
    if bad:
        run.fail(f"{len(bad)} brain moments came before the rules' reaction or cut a rule moment short")
    return {"brain_moments": len(answers), "early": len(bad), "replaced_by_rules": cut, "answers": answers}


def main(out: Path, brain: str, port: str | None, fixtures: list[str] | None, clip: bool = False) -> int:
    root = Path("/tmp/boop-e2e")
    run = Run(root, out, brain, port)
    expected = json.loads((FIXTURES / "expect.json").read_text())
    paths = [FIXTURES / f for f in (fixtures or RUN_ORDER)]
    started = time.time()
    try:
        run.start()
        os.environ["BOOP_BRIDGE"] = run.bridge_sock
        with Device(timeout=3.0) as dev:
            if clip:
                # L3: a short Claude session through the whole pipeline, on
                # camera (VERIFICATION.md §6: authorised runs only).
                from boopctl_lib import cam

                session = FIXTURES / "claude" / "clip.jsonl"
                result = cam.clip(dev, "e2e-session", seconds=10, frames=24, play=lambda: run.fixture(dev, session))
                shutil.copy(result["sheet"], out / "clip-e2e-session.png")
                run.say(f"clip {out / 'clip-e2e-session.png'}")
            for path in paths:
                run.fixture(dev, path)
    except DeviceError as exc:
        run.fail(str(exc))
    finally:
        run.stop()
    for gone in (run.hook_sock, run.bridge_sock):
        (run.fail if os.path.exists(gone) else run.say)(f"{gone} removed: {not os.path.exists(gone)}")

    lat = [h["state_ms"] for h in run.hooks if h["state_ms"] is not None]
    p50, p95 = percentile(lat, 0.5), percentile(lat, 0.95)
    run.say(f"latency, hook launch to state on the device: n {len(lat)}/{len(run.hooks)} hooks, "
            f"p50 {p50:.0f} ms, p95 {p95:.0f} ms, max {max(lat, default=0):.0f} ms")
    if not lat or p95 >= 200:
        run.fail(f"p95 latency {p95:.0f} ms is not under 200 ms")
    if fixtures is None and not clip:
        check_after(run, expected)
    order = check_order(run)

    shutil.copy(run.state / "boop.log", out / f"app-{brain}.log")
    for name in ("long-term.md", "short-term.md", "settings.json"):
        if (run.state / name).exists():
            shutil.copy(run.state / name, out / f"{brain}-{name}")
    result = {"brain": brain, "started": started, "seconds": round(time.time() - started), "hooks": run.hooks,
              "latency": {"p50": p50, "p95": p95, "n": len(lat)}, "order": order,
              "failures": run.failures, "ok": not run.failures}
    (out / f"e2e-{brain}.json").write_text(json.dumps(result, indent=2))
    (out / f"e2e-{brain}.txt").write_text("\n".join(run.log) + "\n")
    print("PASS" if not run.failures else f"FAIL ({len(run.failures)})")
    return 0 if not run.failures else 1


def soak(out: Path, brain: str, port: str | None, minutes: float) -> int:
    """J2's soak: the e2e fixtures on a loop through the whole pipeline, with
    a tap on the board between rounds, for `minutes`. Samples the board
    (resets, heap, audio errors) and the app (alive, memory), counts
    checkpoint misses, and at the end checks that calm brings back the plain
    face with nothing stuck."""
    root = Path("/tmp/boop-soak")
    run = Run(root, out, brain, port)
    samples: list[dict[str, Any]] = []
    rounds, misses = 0, 0
    started = time.time()
    t0 = time.monotonic()
    final: dict[str, Any] = {}

    def sample(dev: Device) -> None:
        ping = dev.request({"t": "dbg.ping"})
        st = dev.request({"t": "dbg.state"})
        app = run.procs[1]
        rss = subprocess.run(["ps", "-o", "rss=", "-p", str(app.pid)], capture_output=True, text=True).stdout.strip()
        samples.append({"t": round(time.monotonic() - t0, 1), "up": ping["up"], "heap": ping["heap"],
                        "heap_min": ping["heap_min"], "fps": ping["fps"],
                        "audio_errors": st.get("audio", {}).get("out", {}).get("errors"),
                        "app_alive": app.poll() is None, "app_rss_kb": int(rss) if rss else None})

    try:
        run.start()
        os.environ["BOOP_BRIDGE"] = run.bridge_sock
        with Device(timeout=3.0) as dev:
            sample(dev)
            while time.monotonic() - t0 < minutes * 60:
                rounds += 1
                run.say(f"# round {rounds} at {(time.monotonic() - t0) / 60:.1f} min")
                for f in RUN_ORDER:
                    before = len(run.failures)
                    run.fixture(dev, FIXTURES / f)
                    misses += len(run.failures) - before
                    sample(dev)
                    if not samples[-1]["app_alive"]:
                        raise DeviceError("the headless app exited")
                dev.request({"t": "dbg.press", "ms": 100})  # a tap: the brain's `tap` trigger
                time.sleep(3)
            # Nothing stuck: once every session has stopped and a quiet minute
            # has passed, the board is back on the plain face.
            time.sleep(60)
            final = dev.request({"t": "dbg.state"})
            sample(dev)
    except DeviceError as exc:
        run.fail(str(exc))
    finally:
        run.stop()

    ups = [s["up"] for s in samples]
    later = [s for s in samples if s["t"] >= 120] or samples[-1:]
    errors = [s["audio_errors"] or 0 for s in samples]
    rss = [s["app_rss_kb"] for s in samples if s["app_rss_kb"]]
    lat = [h["state_ms"] for h in run.hooks if h["state_ms"] is not None]
    result = {
        "brain": brain, "minutes": round((time.monotonic() - t0) / 60, 1), "rounds": rounds,
        "hooks": len(run.hooks), "checkpoint_misses": misses,
        "latency": {"p50": percentile(lat, 0.5), "p95": percentile(lat, 0.95), "n": len(lat)},
        "reset": any(b <= a for a, b in zip(ups, ups[1:])),
        "heap_min_after_2min": later[0]["heap_min"], "heap_min_end": samples[-1]["heap_min"] if samples else None,
        "heap_min_drift": later[0]["heap_min"] - samples[-1]["heap_min"] if samples else None,
        "audio_errors": max(errors, default=0) - min(errors, default=0),
        "app_rss_kb": {"after_2min": later[0]["app_rss_kb"], "end": rss[-1] if rss else None,
                       "max": max(rss, default=None)},
        "app_exited_early": any(not s["app_alive"] for s in samples),
        "final": {k: final.get(k) for k in ("screen", "base", "attn", "moment", "rung")},
    }
    stuck = final.get("screen") != "face" or final.get("attn") is not None or final.get("moment") is not None
    result["stuck"] = stuck
    result["failures"] = run.failures
    result["ok"] = (not result["reset"] and not stuck and not result["app_exited_early"]
                    and (result["heap_min_drift"] or 0) <= 2048 and result["audio_errors"] == 0)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"soak-{brain}.json").write_text(json.dumps({**result, "series": samples}, indent=1))
    (out / f"soak-{brain}.txt").write_text("\n".join(run.log) + "\n")
    if (run.state / "boop.log").exists():
        shutil.copy(run.state / "boop.log", out / f"soak-app-{brain}.log")
    if (run.root / "brain.jsonl").exists():
        shutil.copy(run.root / "brain.jsonl", out / f"soak-brain-{brain}.jsonl")
    print(json.dumps({k: v for k, v in result.items() if k != "failures"}, indent=1))
    print("PASS" if result["ok"] else "FAIL")
    return 0 if result["ok"] else 1
