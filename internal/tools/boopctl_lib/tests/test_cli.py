"""boopctl's command line: every subcommand parses and has help, and the
set stays the one plan/VERIFICATION.md §2 lists. Needs no board."""
import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli  # noqa: E402
from fake_board import FakeBoard  # noqa: E402

COMMANDS = ["ping", "state", "shot", "send", "play", "mumble", "sim", "run", "perf", "soak", "e2e", "bridge",
            "cam", "dash", "calibrate"]


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


if __name__ == "__main__":
    unittest.main()
