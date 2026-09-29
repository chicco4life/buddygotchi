"""The dashboard: its feed against debug.jsonl files
recorded from real headless runs, its three columns (the mood, the
automatic reactions and the decided ones) and the stale-log banner, restart
detection, the face's downsampling and
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
from boopctl_lib.dash.face import CROP, SCALE, blocks, render  # noqa: E402
from boopctl_lib.dash import feed  # noqa: E402
from boopctl_lib.dash.feed import STALE_S, Board, Follower, clock, kind  # noqa: E402
from boopctl_lib.scenario import GOLDEN  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "headless-debug.jsonl"
COLUMNS = Path(__file__).parent / "fixtures" / "dash-columns.jsonl"
LANE_TOP = 192  # firmware/src/render/screens.h kLaneTop: the design is above it


def fixture_lines(path: Path = FIXTURE) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def dashboard_action(line: dict) -> dict:
    """A raw action event's data, if the dashboard forced it."""
    data = line.get("event", {}).get("data", {})
    return data if line.get("event", {}).get("type") == "action" and data.get("by") == "dashboard" else {}


def at_by_seq(lines: list[dict]) -> dict[int, int]:
    """Each line's time by its raw event's seq, or its view event's id
    (the converted fixtures keep the old seqs as both)."""
    out = {}
    for line in lines:
        if "event" in line:
            out[line["event"]["seq"]] = line["received_at_ms"]
        elif "view" in line:
            out[line["view"]["id"]] = line["received_at_ms"]
    return out


def board_after(lines: list[dict]) -> tuple[Board, list[tuple[str, str]]]:
    board = Board()
    rows = [row for row in map(board.apply, lines) if row]
    return board, rows


class FeedTests(unittest.TestCase):
    """The fixture: boopdev replay of the e2e Claude session into
    `Boop --headless --debug --brain scripted`, then the dashboard's dev
    lines and a few more hooks (plan/evidence/2026-09-27-dashboard),
    rewritten into today's lines by
    plan/evidence/2026-09-28-raw-transcript-view/convert_fixtures.py."""

    def test_the_fixture_has_every_kind_of_line(self):
        kinds = [kind(line) for line in fixture_lines()]
        self.assertEqual(kinds[0], "questions", "written first, once")
        self.assertEqual(kinds.count("questions"), 1)
        self.assertEqual(set(kinds), {"questions", "sent", "status", "view", "event", "pass"})

    def test_the_timeline(self):
        board, rows = board_after(fixture_lines())
        events = [text for style, text in rows if style == "event"]
        self.assertEqual([e.split(":")[0] for e in events][:5],
                         ["▸ 1 turn start", "▸ 4 tool wait (no pass)", "▸ 5 turn end", "▸ 8 turn start", "▸ 11 turn end"])
        self.assertIn(("ok", "  ✓ cheer (by rule): Boop cheered on its own."), rows, "a rule's action, under its view event")
        self.assertIn("failed (rate limit)", events[4])
        self.assertIn(("fail", "  ✗ react (by dashboard): something needs you"), rows)
        self.assertIn(("ok", "  ✓ mood (by dashboard): Boop's mood changed: happy → grumpy."), rows)
        self.assertIn(("pass", "  pass forced by dashboard: react grumpy · word.feeling again"), rows)
        self.assertIn(("sent", "→ moment wiggle"), rows)
        self.assertIn(("sent", "→ state idle grumpy · busy 0 · vol 6"), rows, "a state carries the mood")
        self.assertIn(("sent", "→ state idle happy · busy 0 · needs you: claude jetpack · vol 6"), rows)
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
        newest = board.newest_ms
        facts = dict(board.facts(newest + 10_000))
        self.assertEqual(facts["look"], "idle")
        self.assertEqual(facts["mood"], "happy", "from the state line, never the mood file")
        self.assertEqual(facts["needs you"], "no")
        self.assertEqual(facts["sessions"], "0 working, 1 idle, 0 waiting", "from the status")
        self.assertEqual(facts["brain"], "scripted · 0 ms · dropped 0")
        self.assertEqual(facts["board"], "not connected (the sim shows what it would)")
        needs = next(i for i, line in enumerate(fixture_lines()) if line.get("view", {}).get("phase") == "wait")
        board, _ = board_after(fixture_lines()[: needs + 1])
        facts = dict(board.facts(board.newest_ms))
        self.assertEqual(facts["needs you"], "claude · jetpack")
        self.assertEqual(facts["look"], "idle with the needs-you strip")
        self.assertEqual(facts["sessions"], "1 working, 0 idle, 0 waiting", "the status comes after the event")

    def test_the_counts_come_from_attn_and_the_sessions(self):
        board, _ = board_after([
            {"status": {"sessions": [{"agent": "claude", "project": "a", "status": "waiting"},
                                     {"agent": "codex", "project": "b", "status": "waiting"},
                                     {"agent": "claude", "project": "c", "status": "working"},
                                     {"agent": "claude", "project": "d", "status": "idle"},
                                     {"agent": "codex", "project": "e", "status": "idle"}]}, "received_at_ms": 1},
            {"sent": {"t": "state", "v": 1, "base": "working", "mood": "happy",
                      "attn": {"agent": "claude", "project": "a", "more": 1}, "busy": 1, "vol": 6}, "received_at_ms": 1},
        ])
        self.assertEqual(dict(board.facts(1))["sessions"], "1 working, 2 idle, 2 waiting")
        self.assertEqual(dict(board.facts(1))["needs you"], "claude · a (+1)")

    def test_a_started_action_and_its_end(self):
        """harness/HARNESS.md §5.2: a started action is in progress until
        its end, an action event `for` its seq, says how it ended. The
        lines are the shapes HarnessTests pins."""
        board = Board()
        board.apply(next(line for line in fixture_lines() if kind(line) == "questions"))
        lines = [
            '{"pass":{"answers":{"react":{"choice":"grumpy","p":{"grumpy":1}}},"by":"dashboard","dropped":null,"for":null,'
            '"latency_ms":0,"questions":["react"]},"received_at_ms":1}',
            '{"event":{"seq":2,"ts":2,"source":"boop","type":"action","phase":"start","specific_type":"react","data":'
            '{"by":"dashboard","for":null,"latency_ms":0,"message":"Boop made a grumpy face and mumbled.","ok":true}},'
            '"received_at_ms":2}',
        ]
        rows = [board.apply(json.loads(line)) for line in lines]
        self.assertEqual(rows[1], ("dim", "  … react (by dashboard): Boop made a grumpy face and mumbled."))
        self.assertEqual(board.decided_column()[-1], ("playing", "  ▶ playing"))
        self.assertEqual(dict(board.facts(2))["showing"], "a grumpy reaction face")
        row = board.apply(json.loads('{"event":{"seq":3,"ts":3,"source":"boop","type":"action","phase":"end",'
                                     '"specific_type":"react","data":{"by":"dashboard","outcome":"failed","for":2,'
                                     '"why":"waited too long"}},"received_at_ms":3}'))
        self.assertEqual(row, ("fail", "  ✗ react (2) didn't happen: waited too long"))
        self.assertEqual(board.decided_column()[-1], ("fail", "  ✗ didn't happen: waited too long"))
        self.assertEqual(dict(board.facts(3))["showing"], "its ? look", "no state yet")
        row = board.apply(json.loads('{"event":{"seq":4,"ts":4,"source":"boop","type":"action","phase":"end",'
                                     '"specific_type":"react","data":{"by":"brain","outcome":"done","for":2}},'
                                     '"received_at_ms":4}'))
        self.assertEqual(row, ("ok", "  ✓ react (2) done"))
        self.assertEqual(board.decided_column()[-1], ("ok", "  ✓ played"))


class ColumnsTests(unittest.TestCase):
    """The three columns, newest first, from
    `tests/fixtures/dash-columns.jsonl`. It was recorded from a real run
    (plan/evidence/2026-09-28-tonight/dash: a headless app whose USB link is
    a boop-sim, a forced mood, the e2e Claude session, a forced reaction
    that played, a forced pass that chose none, a cheer from the dashboard,
    and four taps on the sim's screen, then a poke streak), then edited, since
    the scripted brain answers everything at probability 1: the first
    pass's mood and the turn end's reaction, word and hold were given
    other probabilities, and the pass for the failed deploy was made a
    dropped one, its reaction's action, moment and settle taken out
    (make_fixture.py there). It was recorded before the raw transcript,
    and rewritten into today's lines by
    plan/evidence/2026-09-28-raw-transcript-view/convert_fixtures.py, so
    its lines keep that run's words."""

    def setUp(self):
        self.board, _ = board_after(fixture_lines(COLUMNS))
        self.at = at_by_seq(fixture_lines(COLUMNS))

    def texts(self, rows):
        return [text for _, text in rows]

    def test_the_mood(self):
        """The mood now and since when, then each change with what made it:
        the event and the brain's probability for the new mood, or the
        dashboard, or the launch; and the pokes' pass sitting out, as that run's did."""
        mood = self.texts(self.board.mood_column())
        changes = [line for line in fixture_lines(COLUMNS) if line.get("sent", {}).get("t") == "state"]
        self.assertEqual(mood[0], f"happy since {clock(self.at[4])}", "the state sent with the mood action")
        poked = next(line for line in fixture_lines(COLUMNS) if line.get("pass", {}).get("for") == 31)
        self.assertEqual(mood[2], f"{clock(poked['received_at_ms'])} · mood sat out: You poked Boop 4 times in 3 s.")
        self.assertEqual(mood[3:6], [f"{clock(self.at[4])} grumpy → happy", '  ▸ claude started turn 1 on "jetpack".',
                                     "  scripted: happy 0.87"])
        self.assertEqual(mood[6:8], [f"{clock(self.at[1])} happy → grumpy", "  forced by dashboard"])
        self.assertEqual(mood[8:], [f"{clock(changes[0]['received_at_ms'])} happy", "  at launch"])

    def test_the_automatic_reactions(self):
        """Each reflex with what set it off: the cheer and its turn end, the
        alert and the request, the taps' wiggles the board plays itself, the
        working chatter, and a cheer the dashboard played, with no event."""
        rows = self.board.reflex_column()
        reflex = self.texts(rows)
        self.assertEqual(reflex[:2], [f"{clock(self.at[31])} Boop wiggled on its own.", "  ▸ You poked Boop 4 times in 3 s."])
        self.assertEqual(reflex.count("  ▸ You tapped Boop."), 3)
        cheers = [i for i, text in enumerate(reflex) if text.endswith(" cheer, loops 1")]
        self.assertEqual([reflex[i + 1] for i in cheers],
                         ["  no event: played from the dashboard",
                          '  ▸ claude finished turn 1 on "jetpack": done after 6 min, a very long turn, 3 tools. '
                          "Tests passing."])
        chatter = next(line["sent"]["say"] for line in fixture_lines(COLUMNS)
                       if line.get("sent", {}).get("say") and not line["sent"].get("mood"))
        at = reflex.index(next(t for t in reflex if t.endswith(f"working chatter {feed.say_text(chatter)}")))
        self.assertEqual(reflex[at + 1], "  an agent is working")
        self.assertTrue(reflex[-3].endswith(" needs you cleared"))
        self.assertTrue(reflex[-2].endswith(" needs you: claude · jetpack · alert"))
        self.assertEqual(reflex[-1], '  ▸ claude needs you on "jetpack".')
        self.assertEqual(rows[-2][0], "attn")

    def test_a_rules_one_shot_and_the_activity(self):
        """A rule's one-shot (PROTOCOL.md §3 `moment`) is named by the view
        event recorded right after it, never "played from the dashboard",
        and the working look shows its activity (`act`)."""
        t = 1_790_550_800_000
        state = {"t": "state", "v": 1, "base": "working", "act": "terminal", "mood": "calm", "busy": 1, "vol": 6}
        view = {"id": 9, "type": "turn", "from": [9], "line": 'claude started turn 2 on "jetpack".', "notes": [],
                "wakes_brain": True, "facts": {}, "phase": "start"}
        board, rows = board_after([
            {"sent": state, "received_at_ms": t},
            {"sent": {"t": "moment", "anim": "starting", "ctx": "new_task"}, "received_at_ms": t + 10},
            {"view": view, "received_at_ms": t + 20},
        ])
        reflex = self.texts(board.reflex_column())
        self.assertEqual(reflex, [f"{clock(t + 10)} starting (new_task)", '  ▸ claude started turn 2 on "jetpack".'])
        self.assertIn(("sent", "→ state working (terminal) calm · busy 1 · vol 6"), rows)
        self.assertEqual(dict(board.facts(t + 60_000))["showing"], "its terminal look")

    def test_the_decided_reactions(self):
        """Each pass that could react: its event, the face, word and hold
        with their probabilities, and what became of it."""
        decided = self.texts(self.board.decided_column())
        blocks, block = [], []
        for text in decided:
            if not text.startswith("  ") and block:
                blocks.append(block)
                block = []
            block.append(text)
        blocks.append(block)
        blocks = [[text if text.startswith("  ") else text[9:] for text in b] for b in blocks]  # without the times
        self.assertEqual(blocks, [
            ["▸ You poked Boop 4 times in 3 s.", "  excited 1.00 · “yay” 1.00 · once 1.00", "  ✓ played",
             "  the mood sat this pass out"],
            ["forced by dashboard", "  stayed quiet · none 1.00"],
            ["forced by dashboard", "  proud 1.00 · “finally” 1.00 · three times 1.00", "  ✓ played"],
            ['▸ claude finished turn 2 on "jetpack": failed (rate limit) after 41 s, a long turn, 1 tool (1 failed). '
             "Deploy failing.", "  excited 1.00 · “yay” 1.00 · once 1.00", "  ✓ played"],
            ['▸ claude\'s deploy failed on "jetpack".', "  ✗ pass dropped: late: no answer within 1500 ms"],
            ['▸ claude started turn 2 on "jetpack", right after its last one.', "  excited 1.00 · “yay” 1.00 · once 1.00",
             "  ✗ didn't happen: the device never said it ended"],
            ['▸ claude finished turn 1 on "jetpack": done after 6 min, a very long turn, 3 tools. Tests passing.',
             "  excited 0.82 · “yay” 0.71 · once 0.64", "  ✓ played"],
            ['▸ claude started turn 1 on "jetpack".', "  excited 1.00 · “yay” 1.00 · once 1.00", "  ✓ played"],
        ])
        self.assertEqual(self.board.dropped, 1)
        # A forced reaction refused while something needs you (the old fixture's).
        refused = [line for line in fixture_lines() if line.get("pass", {}).get("by") or dashboard_action(line)]
        board, _ = board_after(fixture_lines(COLUMNS) + refused[-2:])
        self.assertEqual(self.texts(board.decided_column())[1:3], ["  happy 1.00 · no word",
                                                                   "  ✗ didn't happen: something needs you"])

    def test_what_is_showing(self):
        """Boop now's `showing`: a reaction until its settle, a reflex for
        SHOWING_MS after it, else the look."""
        lines = fixture_lines(COLUMNS)
        forced = next(i for i, line in enumerate(lines) if dashboard_action(line).get("message", "").startswith(
            "Boop made a proud face"))
        board, _ = board_after(lines[: forced + 1])
        self.assertEqual(dict(board.facts(board.newest_ms))["showing"], "a proud reaction face, three times, “…finally!”")
        board = self.board
        self.assertEqual(dict(board.facts(self.at[31] + 1000))["showing"], "Boop wiggled on its own.")
        self.assertEqual(dict(board.facts(self.at[31] + 60_000))["showing"], "its idle look")

    def test_the_stale_log_banner(self):
        """A debug-mode app writes a `sent` line at least
        every 10 s, so a newest line older than 15 s means no live log, and
        the board's connection isn't shown as a fact."""
        self.assertEqual(STALE_S, 15)
        newest = self.board.newest_ms
        self.assertFalse(self.board.stale(newest + 15_000))
        self.assertTrue(self.board.stale(newest + 15_001))
        self.assertEqual(dict(self.board.facts(newest + 1000))["board"], "connected")
        self.assertEqual(dict(self.board.facts(newest + 16_000))["board"], "unknown: no live log")
        self.assertTrue(Board().stale(newest), "no lines at all")


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
        """The app empties the file at each launch and writes
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
        self.assertEqual((len(crop[0]), len(crop)), (107, 32), "107×64 blocks, two per cell")

    def test_each_block_is_its_most_common_colour(self):
        # A 6×3 image: a block of five 1s and four 2s, then one of three
        # each of 0, 1 and 2 (the first counted wins a tie).
        pixels = bytes([1, 2, 1, 0, 1, 2,
                        2, 1, 2, 1, 2, 0,
                        1, 2, 1, 2, 0, 1])
        self.assertEqual(blocks(pixels, 6, (0, 0, 6, 3)), [[1, 0]])
        self.assertEqual(blocks(bytes(4), 2, (0, 0, 2, 2)), [[0]], "an edge block may be smaller")

    def test_the_face_stays_in_the_crop(self):
        """Every golden frame's face (everything drawn above the bottom
        lane) is inside the crop, in pixels and in the downsampled blocks,
        so the crop loses none of it."""
        x0, y0, x1, y1 = CROP
        self.assertEqual(y1, LANE_TOP)
        frames = [p for p in sorted(GOLDEN.rglob("*.png")) if p.parent.name != "pattern"]
        self.assertTrue(frames, f"no golden frames in {GOLDEN}")
        for path in frames:
            with self.subTest(path.relative_to(GOLDEN)):
                palette, indexes, (w, h) = shot = golden_shot(path)
                background = indexes[0]
                outside = [(x, y) for y in range(LANE_TOP) for x in range(w)
                           if indexes[y * w + x] != background and not (x0 <= x < x1 and y0 <= y)]
                self.assertEqual(outside, [])
                grid = blocks(indexes, w, (0, 0, w, h))
                for by, row in enumerate(grid[: LANE_TOP // SCALE]):
                    for bx, index in enumerate(row):
                        inside = x0 <= bx * SCALE < x1 and y0 <= by * SCALE
                        self.assertTrue(inside or index == background, (bx, by))
                render(shot)


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
                  "busy": 1, "vol": 3}
        self.assertEqual(controls.preview_state(latest, "asleep"),
                         {"t": "state", "v": 1, "base": "asleep", "busy": 1, "vol": 3})
        self.assertEqual(controls.preview_state(latest, "idle", "sad")["mood"], "sad")
        needs = controls.preview_state(None, "needs you")
        self.assertEqual((needs["base"], needs["attn"]["agent"]), ("idle", "claude"))
        self.assertEqual(latest["base"], "working", "the app's state is left alone")

    def test_a_preview_reaction_says_its_take(self):
        line = controls.preview_reaction("grumpy", "new.d14", 3)
        self.assertEqual((line["t"], line["mood"], line["loops"]), ("moment", "grumpy", 3))
        self.assertEqual(line["say"], {"take": "new.d14"})
        self.assertNotIn("anim", line)
        face = controls.preview_reaction("proud", None, 1, "cheer")
        self.assertEqual(face["anim"], "cheer", "an animation as react.animation picks it")
        self.assertEqual(face["say"], {}, "saying nothing still sends a say, as react does")

    def test_confirmations(self):
        pending = controls.Pending()
        pending.add({"dev": "mood", "mood": "grumpy"}, now=0)
        pending.add({"dev": "answer", "answers": {"react": "happy"}}, now=0)
        lines = fixture_lines()
        first = next(i for i, line in enumerate(lines) if dashboard_action(line))
        seen = [pending.seen(line) for line in lines[first:]]
        self.assertEqual([s for s in seen if s], ["mood", "answer"], "in the order they landed")
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
                self.assertRegex(plain(app.query_one("#facts")), r"mood +happy")
                # The fixture is days old: no live log, so the board's link isn't a fact.
                self.assertTrue(app.query_one("#stale").has_class("shown"))
                self.assertRegex(plain(app.query_one("#stale")), r"No live log: the newest line is from .*make debug")
                self.assertRegex(plain(app.query_one("#facts")), r"board +unknown: no live log")
                app.now = lambda: app.board.newest_ms / 1000 + 5
                app.poll()
                self.assertFalse(app.query_one("#stale").has_class("shown"))
                self.assertRegex(plain(app.query_one("#facts")), r"board +not connected")
                self.assertIn("happy since", plain(app.query_one("#mood")))
                self.assertIn("cheer", plain(app.query_one("#reflexes")))
                self.assertIn("excited 1.00 · “yay” 1.00", plain(app.query_one("#decided")))
                self.assertEqual(app.query_one("#timeline").size.height, 0, "the timeline waits for t")
                await pilot.press("t")
                await pilot.pause()
                self.assertGreater(app.query_one("#timeline").size.height, 5)
                self.assertGreater(len(app.query_one("#timeline").lines), 40)
                await pilot.press("t")
                await pilot.pause()
                self.assertEqual(app.query_one("#timeline").size.height, 0)

                async def pick(key: str, *downs: int) -> None:
                    await pilot.press(key)
                    for down in downs:
                        await pilot.pause()
                        await pilot.press(*["down"] * down, "enter")
                    await pilot.pause()

                await pick("m", 5)  # grumpy
                await pick("r", 6, 4, 0)  # grumpy, again, none
                got = server.wait(2)
                self.assertEqual(got, [{"dev": "mood", "mood": "grumpy"},
                                       {"dev": "answer", "answers": {"react": "grumpy", "word.feeling": "again",
                                                                     "word.about": "none"}}])
                self.assertEqual(len(app.pending.waiting), 2)
                with log.open("a") as f:
                    f.write('{"event":{"seq":28,"ts":1790498700000,"source":"boop","type":"action","specific_type":"mood",'
                            '"data":{"by":"dashboard","for":null,"latency_ms":0,"message":"already grumpy","ok":false}},'
                            '"received_at_ms":1790498700000}\n')
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
                self.assertEqual(len(server.wait(3, timeout=0.3)), 2, "nothing went to the app")
                with log.open("a") as f:
                    f.write('{"sent":{"t":"moment","anim":"cheer"},"received_at_ms":1790498700002}\n')
                app.poll()
                self.assertEqual(face.sent[-1]["mood"], "sad", "the app's lines wait")
                await pick("r", 5, 0)  # grumpy's face, saying nothing: a moment with its `mood`
                for _ in range(100):
                    if face.sent[-1]["t"] == "moment":
                        break
                    await pilot.pause(0.05)
                self.assertEqual((face.sent[-1]["t"], face.sent[-1]["mood"]), ("moment", "grumpy"))
                self.assertEqual(face.sent[-1]["say"], {}, "saying nothing, as react sends it")
                # Resent well inside the device's 30 s no-app timeout.
                self.assertEqual(PREVIEW_RESEND_S, 10)
                app.keep_preview()
                self.assertEqual(face.sent[-1]["base"], "working")
                await pick("p", len(controls.LOOKS))
                self.assertEqual(face.restarts[-1], latest, "leaving Preview replays the latest state")
                self.assertIn("live", app.query_one("#face").border_title)

                await pilot.press("s")
                await pilot.pause()
                self.assertIsInstance(app.screen, StateView)
                await pilot.press("escape")
                await pilot.pause()
                self.assertNotIsInstance(app.screen, StateView)

                # The app starts again: the file is emptied in place.
                log.write_text('{"questions":[],"received_at_ms":2}\n'
                               '{"sent":{"t":"state","v":1,"base":"idle","busy":0,"vol":6},'
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


class ReactionKeysTests(unittest.TestCase):
    """harness/DECISIONS.md §3: a reaction is `react.mood` and
    `react.animation`; older logs name the face `react`."""

    def test_the_face_and_its_finish(self) -> None:
        from boopctl_lib.dash.feed import choice, picks_text, reaction_text
        a = lambda c, p=1.0: {"choice": c, "p": {c: p}}  # noqa: E731
        now = {"answers": {"react.mood": a("proud", 0.82), "react.animation": a("success", 0.9),
                           "react.loops": a("twice"), "word.feeling": a("finally", 0.71)},
               "questions": ["react.mood", "react.animation", "react.loops", "word.feeling"]}
        self.assertEqual(picks_text(now), "proud 0.82 · success 0.90 · “finally” 0.71 · twice 1.00")
        self.assertEqual(reaction_text({"pass": now}), "a success in a proud face, twice, “…finally!”")
        old = {"answers": {"react": a("grumpy"), "react.loops": a("once")}, "questions": ["react", "react.loops"]}
        self.assertEqual(choice(old, "react.mood"), "grumpy", "an older log's `react`")
        self.assertEqual(reaction_text({"pass": old}), "a grumpy reaction face, once")
