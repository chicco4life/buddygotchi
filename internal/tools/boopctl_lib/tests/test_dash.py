"""The dashboard (plan/DASHBOARD.md): its feed against a debug.jsonl recorded
from a real headless run, restart detection, the face's downsampling and
crop against every golden frame, the dev lines its keys build, and the app
itself through Textual's pilot. Needs no board, app or sim."""
import asyncio
import io
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from PIL import Image  # noqa: E402
from rich.console import Console  # noqa: E402

from boopctl_lib.common import REPO, send_line  # noqa: E402
from boopctl_lib.dash import controls  # noqa: E402
from boopctl_lib.dash.app import PREVIEW_RESEND_S, Dash, StateView  # noqa: E402
from boopctl_lib.dash.face import CROP, SCALE, WHOLE, blocks, render  # noqa: E402
from boopctl_lib.dash.feed import Board, Follower, kind, sections  # noqa: E402
from boopctl_lib.scenario import GOLDEN  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "headless-debug.jsonl"
BUBBLE_TOP = 144  # firmware/src/render/screens.h kBubbleTop: the face is above it


def fixture_lines() -> list[dict]:
    return [json.loads(line) for line in FIXTURE.read_text().splitlines()]


def board_after(lines: list[dict]) -> tuple[Board, list[tuple[str, str]]]:
    board = Board()
    rows = [row for row in map(board.apply, lines) if row]
    return board, rows


class FeedTests(unittest.TestCase):
    """The fixture: boopdev replay of the e2e Claude session into
    `Boop --headless --debug --brain scripted`, then the dashboard's dev
    lines and a few more hooks (plan/evidence/2026-09-27-dashboard)."""

    def test_the_fixture_has_every_kind_of_line(self):
        kinds = [kind(line) for line in fixture_lines()]
        self.assertEqual(kinds[0], "questions", "written first, once")
        self.assertEqual(kinds.count("questions"), 1)
        self.assertEqual(set(kinds), {"questions", "sent", "status", "event", "pass", "action"})

    def test_the_timeline(self):
        board, rows = board_after(fixture_lines())
        events = [text for style, text in rows if style == "event"]
        self.assertEqual([e.split(":")[0] for e in events][:5],
                         ["▸ 1 turn_start", "▸ 4 needs_you (no pass)", "▸ 5 turn_end", "▸ 8 turn_start", "▸ 11 turn_end"])
        self.assertIn("[Boop cheered on its own.]", events[2])
        self.assertIn("failed (rate limit)", events[4])
        self.assertIn(("fail", "  ✗ react (by dashboard): something needs you"), rows)
        self.assertIn(("ok", "  ✓ mood (by dashboard): Boop's mood changed: happy → grumpy."), rows)
        self.assertIn(("pass", "  pass forced by dashboard: react annoyed · word.feeling again"), rows)
        self.assertIn(("sent", "→ moment wiggle"), rows)
        self.assertIn(("sent", "→ state idle grumpy · busy 0 idle 1 wait 0 · vol 6"), rows, "a state carries the mood")
        self.assertIn(("status", "status: sessions claude jetpack waiting"), rows, "a status row shows what changed")

    def test_keepalives_are_hidden(self):
        lines = fixture_lines()
        states = [line for line in lines if kind(line) == "sent" and line["sent"]["t"] == "state"]
        _, rows = board_after(lines)
        shown = [text for _, text in rows if text.startswith("→ state")]
        self.assertLess(len(shown), len(states), "the fixture has a state resent unchanged")
        for a, b in zip(shown, shown[1:]):
            self.assertNotEqual(a, b, "each shown state changed something")

    def test_the_facts(self):
        board, _ = board_after(fixture_lines())
        facts = dict(board.facts())
        self.assertEqual(facts["base"], "idle · busy 0 · idle 1 · waiting 0")
        self.assertEqual(facts["needs you"], "no")
        self.assertEqual(facts["mood"], "happy · personality boop", "from the state line, never the mood file")
        self.assertEqual(facts["sessions"], "claude jetpack idle")
        self.assertEqual(facts["brain"], "scripted · 0 ms · dropped 0")
        self.assertEqual(facts["volume"], "6")
        self.assertEqual(facts["saying"], "“la-gi ni-gi bi-bi” + yay (at 0) · bounce · 115 ms/syl")
        needs = next(i for i, line in enumerate(fixture_lines()) if line.get("event", {}).get("kind") == "needs_you")
        board, _ = board_after(fixture_lines()[: needs + 1])
        self.assertEqual(dict(board.facts())["needs you"], "claude · jetpack")

    def test_the_harness_pane(self):
        lines = fixture_lines()
        board, _ = board_after(lines)
        text = [t for _, t in board.harness()]
        self.assertEqual(text[0], "IN")
        self.assertTrue(text[1].startswith("▸ 24 turn_end: claude finished turn 3"))
        self.assertEqual(text[2], "  reflex: Boop cheered on its own.")
        self.assertEqual(text[3], "  state: guide 32 · PERSONALITY 20 · MOOD 13 · HISTORY 18 · NOW 3 lines (s shows it)")
        self.assertEqual(text[4], "  asked: mood, react, word.feeling, word.about")
        self.assertIn("  react → excited   excited 1.00", text)
        self.assertEqual(text[-2:], ["RAN", "  ✓ react: Boop mumbled, excited: \"…yay!\""])
        # A mood the dashboard set right after a pass isn't that pass's.
        mood = next(i for i, line in enumerate(lines) if line.get("action", {}).get("by"))
        board, _ = board_after(lines[: mood + 1])
        self.assertEqual([r["name"] for r in board.ran], ["react"])
        # Jev's next pass changes it back, and that's its own.
        back = next(i for i, line in enumerate(lines) if line.get("action", {}).get("message", "").endswith("grumpy → happy."))
        board, _ = board_after(lines[: back + 2])
        self.assertEqual([r["name"] for r in board.ran], ["mood", "react"])
        forced = next(i for i, line in enumerate(lines) if line.get("pass", {}).get("by"))
        board, _ = board_after(lines[: forced + 3])
        text = [t for _, t in board.harness()]
        self.assertEqual(text[1], "forced by dashboard, for no event")
        self.assertFalse(any("state:" in t for t in text), "a forced pass has no state")
        self.assertEqual(text[-1], "  ✓ react: Boop mumbled, annoyed: \"…again!\"")

    def test_sections(self):
        state = next(line["pass"]["state"] for line in fixture_lines() if line.get("pass", {}).get("state"))
        heads = [head for head, _ in sections(state)]
        self.assertEqual(heads[:3], ["guide", "PERSONALITY", "MOOD"])
        self.assertTrue(heads[3].startswith("HISTORY (") and heads[4].startswith("NOW ("))


class RestartTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.path = self.dir / "debug.jsonl"

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, text: str, mode: str = "a") -> None:
        with self.path.open(mode) as f:
            f.write(text)

    def test_following(self):
        follower = Follower(self.path)
        self.assertEqual(follower.read(), (False, []), "no file yet")
        self.write('{"questions":[]}\n{"seq":1,"event":{}}\n{"seq":2,"pa')
        self.assertEqual(follower.read(), (False, [{"questions": []}, {"seq": 1, "event": {}}]), "a partial line waits")
        self.write('ss":{}}\n')
        self.assertEqual(follower.read(), (False, [{"seq": 2, "pass": {}}]))
        self.assertEqual(follower.read(), (False, []))
        self.write('{"sent":{"t":"state"}}\n')
        self.assertEqual(follower.read(), (False, [{"sent": {"t": "state"}}]), "growing")

    def test_the_app_starting_again(self):
        """DASHBOARD.md §3: the app empties the file at each launch and writes
        its questions line, with that launch's time, first."""
        follower = Follower(self.path)
        self.write('{"questions":[],"received_at_ms":1}\n{"seq":1,"event":{}}\n{"seq":2,"pass":{}}\n')
        follower.read()
        for why, text in [
            ("shorter", '{"questions":[],"received_at_ms":2}\n'),
            ("longer, past where it had read", '{"questions":[],"received_at_ms":3}\n' + '{"sent":{"t":"state"}}\n' * 9),
            ("the same length", '{"questions":[],"received_at_ms":4}\n' + '{"sent":{"t":"state"}}\n' * 9),
        ]:
            with self.subTest(why):
                self.write(text, "w")
                self.assertEqual(follower.read(), (True, [json.loads(line) for line in text.splitlines()]))
        os.remove(self.path)
        self.assertEqual(follower.read(), (False, []), "gone: nothing to read yet")
        self.write('{"questions":[],"received_at_ms":5}\n', "w")
        self.assertEqual(follower.read(), (True, [{"questions": [], "received_at_ms": 5}]), "a new file")


def golden_shot(path: Path) -> tuple[list[int], bytes, tuple[int, int]]:
    """A golden PNG as a device screenshot: an RGB565 palette and indexes."""
    image = Image.open(path).convert("RGB")
    raw = image.tobytes()
    colours: dict[bytes, int] = {}
    indexes = bytes(colours.setdefault(raw[i : i + 3], len(colours)) for i in range(0, len(raw), 3))
    palette = [((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3) for r, g, b in colours] + [0] * (256 - len(colours))
    return palette, indexes, image.size


class FaceTests(unittest.TestCase):
    def test_the_sizes(self):
        self.assertEqual(SCALE, 3)
        shot = golden_shot(GOLDEN / "base" / "idle.png")
        crop = render(shot).plain.split("\n")
        self.assertEqual((len(crop[0]), len(crop)), (83, 22), "83×44 blocks, two per cell")
        whole = render(shot, whole=True).plain.split("\n")
        self.assertEqual((len(whole[0]), len(whole)), (107, 40))

    def test_each_block_is_its_most_common_colour(self):
        # A 6×3 image: a block of five 1s and four 2s, then one of three
        # each of 0, 1 and 2 (the first counted wins a tie).
        pixels = bytes([1, 2, 1, 0, 1, 2,
                        2, 1, 2, 1, 2, 0,
                        1, 2, 1, 2, 0, 1])
        self.assertEqual(blocks(pixels, 6, (0, 0, 6, 3)), [[1, 0]])
        self.assertEqual(blocks(bytes(4), 2, (0, 0, 2, 2)), [[0]], "an edge block may be smaller")

    def test_the_face_stays_in_the_crop(self):
        """Every golden frame's face (everything drawn above the bubble) is
        inside the crop, in pixels and in the downsampled blocks, so the
        crop loses none of it."""
        x0, y0, x1, y1 = CROP
        self.assertEqual(y1, BUBBLE_TOP)
        frames = [p for p in sorted(GOLDEN.rglob("*.png")) if p.parent.name != "pattern"]
        self.assertTrue(frames, f"no golden frames in {GOLDEN}")
        for path in frames:
            with self.subTest(path.relative_to(GOLDEN)):
                palette, indexes, (w, h) = shot = golden_shot(path)
                background = indexes[0]
                outside = [(x, y) for y in range(BUBBLE_TOP) for x in range(w)
                           if indexes[y * w + x] != background and not (x0 <= x < x1 and y0 <= y)]
                self.assertEqual(outside, [])
                grid = blocks(indexes, w, WHOLE)
                for by, row in enumerate(grid[: BUBBLE_TOP // SCALE]):
                    for bx, index in enumerate(row):
                        inside = x0 <= bx * SCALE < x1 and y0 <= by * SCALE
                        self.assertTrue(inside or index == background, (bx, by))
                render(shot)
                render(shot, whole=True)


QUESTIONS = next(line["questions"] for line in fixture_lines() if "questions" in line)


class ControlsTests(unittest.TestCase):
    def test_the_pickers_come_from_the_questions_line(self):
        self.assertEqual(controls.options(controls.asked_by(QUESTIONS, "mood")[0]),
                         ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad"])
        react = controls.asked_by(QUESTIONS, "react")
        self.assertEqual([q["key"] for q in react], ["react", "word.feeling", "word.about"])
        self.assertEqual(controls.options(react[0])[0], "none")

    def test_preview_lines(self):
        latest = {"t": "state", "v": 1, "base": "working", "attn": {"agent": "codex", "project": "x", "more": 0},
                  "busy": 1, "idle": 0, "wait": 1, "vol": 3}
        self.assertEqual(controls.preview_state(latest, "asleep"),
                         {"t": "state", "v": 1, "base": "asleep", "busy": 1, "idle": 0, "wait": 0, "vol": 3})
        self.assertEqual(controls.preview_state(latest, "idle", "sad")["mood"], "sad")
        needs = controls.preview_state(None, "needs you")
        self.assertEqual((needs["base"], needs["wait"], needs["attn"]["agent"]), ("idle", 1, "claude"))
        self.assertEqual(latest["base"], "working", "the app's state is left alone")

    @unittest.skipUnless((REPO / ".build" / "debug" / "boopdev").exists(), "needs make build")
    def test_a_preview_mumble_is_the_apps_voice(self):
        line = controls.preview_mumble("annoyed", "again")
        self.assertEqual((line["t"], line["say"]["word"]), ("moment", "again"))
        self.assertIn("syl", line["say"])

    def test_confirmations(self):
        pending = controls.Pending()
        pending.add({"dev": "mood", "mood": "grumpy"}, now=0)
        pending.add({"dev": "answer", "answers": {"react": "happy"}}, now=0)
        pending.add({"dev": "moment", "anim": "cheer"}, now=0)
        lines = fixture_lines()
        first = next(i for i, line in enumerate(lines) if line.get("action", {}).get("by"))
        seen = [pending.seen(line) for line in lines[first:]]
        self.assertEqual([s for s in seen if s], ["mood", "answer", "moment"], "in the order they landed")
        pending.add({"dev": "moment", "anim": "wiggle"}, now=0)
        self.assertIsNone(pending.seen({"sent": {"t": "moment", "anim": "cheer"}}), "a rule's cheer isn't it")
        self.assertIsNone(pending.seen({"sent": {"t": "moment", "say": {"syl": "pi"}}}), "nor a mumble")
        self.assertEqual(pending.seen({"sent": {"t": "moment", "anim": "wiggle"}}), "moment")
        pending.add({"dev": "mood", "mood": "grumpy"}, now=0)
        self.assertEqual(pending.late(now=1.9), [])
        self.assertEqual(pending.late(now=2.0), ["mood"], "nothing within 2 s")
        self.assertEqual(pending.waiting, [])

    def test_send(self):
        with Socket() as server:
            self.assertIsNone(send_line(server.path, {"dev": "mood", "mood": "grumpy"}))
            self.assertEqual(server.wait(1), [{"dev": "mood", "mood": "grumpy"}])
        self.assertIn("can't reach Boop's socket", send_line(server.path, {"dev": "mood", "mood": "grumpy"}))


class Socket:
    """A Unix socket that collects the JSON lines written to it, as the
    app's hook socket would."""

    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(dir="/tmp")
        self.path = os.path.join(self.dir, "s.sock")
        self.got: list[dict] = []
        self.lock = threading.Lock()

    def __enter__(self) -> "Socket":
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen()
        threading.Thread(target=self._serve, daemon=True).start()
        return self

    def _serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                data = b""
                while chunk := conn.recv(4096):
                    data += chunk
            with self.lock:
                self.got += [json.loads(line) for line in data.splitlines() if line]

    def wait(self, n: int, timeout: float = 2) -> list[dict]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self.lock:
                if len(self.got) >= n:
                    return list(self.got)
            time.sleep(0.01)
        with self.lock:
            return list(self.got)

    def __exit__(self, *_: object) -> None:
        self.server.close()
        shutil.rmtree(self.dir)


class FakeFace:
    def __init__(self) -> None:
        self.whole = False
        self.sent: list[dict] = []
        self.restarts: list[dict | None] = []
        self.running = False

    def start(self) -> None:
        self.running = True

    def stop(self) -> None:
        self.running = False

    def send(self, message: dict) -> None:
        self.sent.append(message)

    def restart(self, state: dict | None) -> None:
        self.restarts.append(state)


def plain(widget) -> str:
    """A Static's content as the terminal shows it, without colour."""
    console = Console(width=200, record=True, file=io.StringIO())
    console.print(widget.content)
    return console.export_text()


class AppTests(unittest.TestCase):
    """The app through Textual's pilot: its panes from the fixture, and every
    key."""

    def test_the_panes_and_keys(self):
        with mock.patch.object(controls, "CONFIRM_S", 60):  # the pilot's pauses add up
            asyncio.run(self.drive())

    async def drive(self) -> None:
        state_dir = Path(tempfile.mkdtemp())
        log = state_dir / "debug.jsonl"
        shutil.copy(FIXTURE, log)
        face = FakeFace()
        with Socket() as server:
            app = Dash(log, server.path, make_face=lambda on_frame, on_error: face)
            async with app.run_test(size=(170, 60)) as pilot:
                await pilot.pause()
                self.assertTrue(face.running)
                latest = next(line["sent"] for line in reversed(fixture_lines()) if line.get("sent", {}).get("t") == "state")
                self.assertEqual(face.restarts, [latest], "the sim starts on the latest state, and no old moments")
                self.assertEqual(face.sent, [])
                self.assertRegex(plain(app.query_one("#facts")), r"mood +happy · personality boop")
                harness = plain(app.query_one("#harness-text"))
                self.assertIn("RAN", harness)
                self.assertIn("✓ react: Boop mumbled, excited", harness)
                self.assertGreater(len(app.query_one("#timeline").lines), 40)

                async def pick(key: str, *downs: int) -> None:
                    await pilot.press(key)
                    for down in downs:
                        await pilot.pause()
                        await pilot.press(*["down"] * down, "enter")
                    await pilot.pause()

                await pick("m", 5)  # grumpy
                await pick("r", 5, 4, 0)
                await pick("a", 0)
                got = server.wait(3)
                self.assertEqual(got, [{"dev": "mood", "mood": "grumpy"},
                                       {"dev": "answer", "answers": {"react": "annoyed", "word.feeling": "again",
                                                                     "word.about": "none"}},
                                       {"dev": "moment", "anim": "cheer"}])
                self.assertEqual(len(app.pending.waiting), 3)
                with log.open("a") as f:
                    f.write('{"action":{"by":"dashboard","for":null,"latency_ms":0,"message":"already grumpy",'
                            '"name":"mood","ok":false},"received_at_ms":1790498700000,"seq":28}\n')
                    f.write('{"sent":{"t":"moment","anim":"cheer"},"received_at_ms":1790498700001}\n')
                app.poll()
                self.assertEqual([name for _, name, _ in app.pending.waiting], ["answer"])
                self.assertEqual(face.sent, [{"t": "moment", "anim": "cheer"}], "live lines reach the sim")

                # Preview: the dashboard's own lines, to its sim only.
                await pick("p", 1)
                self.assertEqual(face.sent[-1]["base"], "working")
                self.assertIn("PREVIEW: working", app.query_one("#face").border_title)
                await pick("m", 6)  # sad: the mood's faces, on the sim only
                self.assertEqual((face.sent[-1]["base"], face.sent[-1]["mood"]), ("working", "sad"))
                await pick("a", 1)
                self.assertEqual(face.sent[-1], {"t": "moment", "anim": "wiggle"})
                self.assertEqual(len(server.wait(4, timeout=0.3)), 3, "nothing went to the app")
                with log.open("a") as f:
                    f.write('{"sent":{"t":"moment","anim":"cheer"},"received_at_ms":1790498700002}\n')
                app.poll()
                self.assertEqual(face.sent[-1], {"t": "moment", "anim": "wiggle"}, "the app's lines wait")
                # DASHBOARD.md §4: resent well inside the device's 30 s no-app timeout.
                self.assertEqual(PREVIEW_RESEND_S, 10)
                app.keep_preview()
                self.assertEqual(face.sent[-1]["base"], "working")
                await pick("p", len(controls.LOOKS))
                self.assertEqual(face.restarts[-1], latest, "leaving Preview replays the latest state")
                self.assertIn("live", app.query_one("#face").border_title)

                await pilot.press("z")
                self.assertTrue(face.whole)
                self.assertIn("whole screen", app.query_one("#face").border_title)
                await pilot.press("s")
                await pilot.pause()
                self.assertIsInstance(app.screen, StateView)
                await pilot.press("escape")
                await pilot.pause()
                self.assertNotIsInstance(app.screen, StateView)

                # The app starts again: the file is emptied in place.
                log.write_text('{"questions":[],"received_at_ms":2}\n'
                               '{"sent":{"t":"state","v":1,"base":"idle","busy":0,"idle":0,"wait":0,"vol":6},'
                               '"received_at_ms":2}\n'
                               '{"sent":{"t":"moment","anim":"cheer"},"received_at_ms":3}\n')
                sent_before = len(face.sent)
                app.poll()
                self.assertEqual(face.restarts[-1]["base"], "idle", "the new app's latest state")
                self.assertEqual(len(face.sent), sent_before, "and none of its moments")
                self.assertIn("Boop restarted", " ".join(strip.text for strip in app.query_one("#timeline").lines))
                await pilot.press("q")
            self.assertFalse(face.running)
        shutil.rmtree(state_dir)


if __name__ == "__main__":
    unittest.main()
