"""The dashboard's live check (README.md here): a headless Boop with the
scripted brain, the e2e Claude session replayed into it, and the real
dashboard, with its real sim, driven key by key through Textual's pilot.
Saves an SVG of the dashboard and a PNG of the sim's screen at each step.

    internal/tools/.venv/bin/python plan/evidence/2026-09-27-dashboard/drive.py SCRATCH
"""
import asyncio
import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "internal" / "tools"))

from boopctl_lib.cli import SIM_PROGRAM  # noqa: E402
from boopctl_lib.dash.app import Dash, StateView  # noqa: E402
from boopctl_lib.dash.face import SimFace  # noqa: E402
from boopctl_lib.e2e import BIN, FIXTURES  # noqa: E402
from boopctl_lib.image import save_shot  # noqa: E402

OUT = Path(__file__).parent
SOCKET = "/tmp/bdash.sock"


async def main(scratch: Path) -> None:
    state = scratch / "bd"
    boop = subprocess.Popen([BIN / "Boop", "--headless", "--state-dir", state, "--socket", SOCKET, "--debug",
                             "--brain", "scripted", "--name", "Pip"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        while not Path(SOCKET).exists():
            time.sleep(0.1)
        app = Dash(state / "debug.jsonl", SOCKET, make_face=lambda on_frame, on_error: SimFace(str(SIM_PROGRAM), on_frame, on_error))
        async with app.run_test(size=(170, 62)) as pilot:
            async def until(what: str, check, timeout: float = 15) -> None:
                deadline = time.monotonic() + timeout
                while not check():
                    if time.monotonic() > deadline:
                        raise SystemExit(f"timed out waiting for {what}")
                    await pilot.pause(0.1)
                print("ok:", what)

            async def shot(name: str) -> None:
                await pilot.pause(0.3)
                app.save_screenshot(f"{name}.svg", str(OUT))
                if app.face.last:
                    save_shot(app.face.last, OUT / f"{name}-sim.png")

            async def pick(key: str, *downs: int) -> None:
                await pilot.press(key)
                for down in downs:
                    await pilot.pause(0.2)
                    await pilot.press(*["down"] * down, "enter")

            def rows() -> list[str]:
                return [strip.text for strip in app.timeline.lines]

            def landed() -> bool:
                return not app.pending.waiting

            await until("the sim's first frame", lambda: app.face.last is not None)
            replay = subprocess.run([BIN / "boopdev", "replay", FIXTURES / "claude" / "session.jsonl",
                                     "--socket", SOCKET, "--gap-ms", "400"], capture_output=True, text=True)
            assert replay.returncode == 0, replay.stderr
            await until("the session's five events", lambda: sum("▸ " in r for r in rows()) >= 5)
            events = [r.split(" ", 1)[1] for r in rows() if "▸ " in r]
            print("\n".join(events))
            await shot("01-session")
            await pilot.press("s")
            await until("the state view", lambda: isinstance(app.screen, StateView))
            await shot("02-state")
            await pilot.press("escape")

            await pick("m", 5)  # grumpy
            await until("the forced mood landed", landed)
            await shot("03-mood")
            await pick("r", 5, 4, 0)  # annoyed, again, no topic word
            await until("the forced pass landed", landed)
            await pilot.pause(0.4)
            await shot("04-react")
            await pick("a", 0)  # cheer
            await until("the cheer landed", landed)
            await pilot.pause(0.4)
            await shot("05-cheer")
            await pilot.press("z")
            await pilot.pause(1.0)
            await shot("06-whole-screen")
            await pilot.press("z")
            await pick("p", 3)  # needs you
            await pilot.pause(1.0)
            await shot("07-preview-needs-you")
            await pick("p", 4)  # leave Preview
            await pilot.press("q")
    finally:
        boop.terminate()
        boop.wait()
    lines = [json.loads(line) for line in (state / "debug.jsonl").read_text().splitlines()]
    for line in lines:
        body = line.get("action") or line.get("pass") or {}
        if body.get("by"):
            print("dashboard:", json.dumps(line, ensure_ascii=False)[:200])


if __name__ == "__main__":
    asyncio.run(main(Path(sys.argv[1])))
