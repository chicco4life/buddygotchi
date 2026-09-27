"""boopctl's command line: every subcommand parses and has help, and the
set stays the one plan/VERIFICATION.md §2 lists. Needs no board."""
import contextlib
import io
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli  # noqa: E402
from fake_board import FakeBoard  # noqa: E402

COMMANDS = ["ping", "state", "shot", "send", "play", "mumble", "sim", "run", "perf", "soak", "e2e", "bridge",
            "cam", "dash", "day", "calibrate"]


class CLITests(unittest.TestCase):
    def subcommands(self) -> list[str]:
        parser = cli.build_parser()
        action = next(a for a in parser._actions if a.dest == "command")
        return list(action.choices)

    def test_the_commands_are_the_documented_ones(self):
        self.assertEqual(self.subcommands(), COMMANDS)
        table = (Path(__file__).resolve().parents[4] / "plan" / "VERIFICATION.md").read_text()
        for command in COMMANDS:
            self.assertTrue(f"| `{command}" in table, f"VERIFICATION.md §2 doesn't list boopctl {command}")

    def test_every_command_has_help(self):
        for command in COMMANDS:
            with self.subTest(command), contextlib.redirect_stdout(io.StringIO()) as out:
                with self.assertRaises(SystemExit) as done:
                    cli.build_parser().parse_args([command, "--help"])
                self.assertEqual(done.exception.code, 0)
                self.assertIn("usage: boopctl", out.getvalue())

    def test_the_hand_driven_commands_parse(self):
        parse = cli.build_parser().parse_args
        self.assertEqual(parse(["play", "cheer", "--say", "proud"]).func, cli.cmd_play)
        self.assertEqual(parse(["play", "needs", "--seconds", "3"]).seconds, 3)
        self.assertEqual(parse(["mumble", "--levels", "1", "10"]).levels, [1, 10])
        self.assertTrue(parse(["mumble", "happy", "--board-volume"]).board_volume)
        self.assertTrue(parse(["soak", "--pipeline", "--minutes", "30", "--brain", "jev"]).pipeline)
        self.assertEqual(parse(["cam", "clip", "cheer", "--camera", "X"]).camera, "X")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parse(["mumble", "--levels", "1", "--board-volume"])


class PlayTests(unittest.TestCase):
    def play(self, what: str, *more: str) -> tuple[int, list]:
        board = FakeBoard.by_type({"dbg.ping": {"ble": "adv"}, "dbg.clock": {},
                                   "dbg.state": {"moment": {"anim": what, "left_ms": 900}}})
        self.board = board
        with mock.patch.object(cli, "Device", lambda port: board), contextlib.redirect_stdout(io.StringIO()):
            code = cli.cmd_play(cli.build_parser().parse_args(["play", what, *more]))
        return code, [m.get("anim") for m in board.sent if m["t"] == "moment"]

    def test_play_sets_the_mood(self):
        self.play("cheer", "--mood", "determined")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["determined"])
        self.play("wiggle")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["happy"])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "cheer", "--mood", "cheerful"])

    def test_play_sends_just_the_animation(self):
        self.assertEqual(self.play("cheer"), (0, ["cheer"]))
        self.assertEqual(self.play("wiggle"), (0, ["wiggle"]))

    def test_play_sends_its_loops(self):  # PROTOCOL.md §3: 1-6, none reads as 1
        self.play("cheer", "--loops", "3")
        self.assertEqual([m.get("loops") for m in self.board.sent if m["t"] == "moment"], [3])
        self.play("cheer")
        self.assertEqual([m.get("loops") for m in self.board.sent if m["t"] == "moment"], [None])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "cheer", "--loops", "7"])


class PerfTests(unittest.TestCase):
    """perf --motion's rule (VERIFICATION.md L2): a frame drawn in every
    second and none over 40 ms. fps follows the design, so 6 a second, a
    second of the cheer, passes."""

    def perf(self, fps: int, frame_us: int) -> dict:
        up = [0]

        def answer(msg: dict) -> bytes:
            if msg["t"] == "dbg.ping":
                up[0] += 1000
                reply = {"t": "dbg.ping", "up": up[0], "heap": 74000, "heap_min": 73800, "fps": fps,
                         "draw_us": 1000, "push_us": frame_us - 1000}
            elif msg["t"].startswith("dbg."):
                reply = {"t": msg["t"]}
            else:
                return b""
            return json.dumps(reply).encode() + b"\n"

        class Clock:  # perf's seconds pass at once
            now = 0.0

            def monotonic(self) -> float:
                return self.now

            def sleep(self, s: float) -> None:
                self.now += s

        board = FakeBoard(answer)
        out = io.StringIO()
        with mock.patch.object(cli, "Device", lambda port: board), mock.patch.object(cli, "time", Clock()), \
                contextlib.redirect_stdout(out):
            cli.cmd_perf(cli.build_parser().parse_args(["perf", "--motion", "--seconds", "5"]))
        return json.loads(out.getvalue())

    def test_a_slow_design_passes_and_a_stalled_or_slow_board_fails(self):
        self.assertTrue(self.perf(6, 14200)["ok"])
        self.assertFalse(self.perf(0, 14200)["ok"])  # nothing drawn in a second of motion
        self.assertFalse(self.perf(20, 41000)["ok"])  # a frame over 40 ms


class SoakTests(unittest.TestCase):
    """The soak's brain reactions and how it holds the board to one
    `ended` each (PROTOCOL.md §3–4)."""

    def test_reactions_are_waited_moments_with_loops(self):
        import random
        rng = random.Random(1)
        for i in range(1, 50):
            m = cli.soak_reaction(rng, i)
            self.assertEqual(m["id"], i)
            self.assertIn(m["mood"], cli.MOODS)
            self.assertTrue(1 <= m["loops"] <= 6)
            self.assertTrue(m["say"]["syl"])
        cheers = [cli.soak_moment(rng) for _ in range(200)]
        self.assertTrue(all(1 <= m["loops"] <= 3 for m in cheers if m.get("anim") == "cheer"))
        self.assertFalse(any("id" in m or "mood" in m for m in cheers))  # the rules' moments aren't waited on

    def test_each_reaction_ends_once(self):
        ended = [{"t": "ended", "id": 1, "how": "done"}, {"t": "ended", "id": 2, "how": "cut", "why": "tap"},
                 {"t": "ended", "id": 3, "how": "skipped"}]
        r = cli.ended_report([1, 2, 3], ended, 0)
        self.assertTrue(r["ended_ok"])
        self.assertEqual(r["ended_how"], {"done": 1, "cut (tap)": 1, "skipped": 1})
        self.assertFalse(cli.ended_report([1, 2, 3], ended + [ended[0]], 0)["ended_ok"])  # twice
        self.assertFalse(cli.ended_report([1, 2], ended, 0)["ended_ok"])  # an id never sent
        # A missing one only when a line was lost on the way.
        self.assertFalse(cli.ended_report([1, 2, 3, 4], ended, 0)["ended_ok"])
        self.assertTrue(cli.ended_report([1, 2, 3, 4], ended, 1)["ended_ok"])
        self.assertEqual(cli.ended_report([1, 2, 3, 4], ended, 1)["ended_missing"], [4])

    def test_the_link_hears_what_comes_unasked(self):
        board = FakeBoard.in_turn([b'{"t":"ended","id":7,"how":"done"}\n{"t":"ended","id":8\n{"t":"dbg.ping","up":1}\n'])
        heard: list[dict] = []
        board.heard = heard.append
        board.request({"t": "dbg.ping"})
        self.assertEqual([m["t"] for m in heard], ["ended", "torn"])
        self.assertEqual(heard[0]["id"], 7)


if __name__ == "__main__":
    unittest.main()
