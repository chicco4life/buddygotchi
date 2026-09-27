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
from boopctl_lib.device import Link  # noqa: E402

COMMANDS = ["ping", "state", "shot", "send", "play", "mumble", "sim", "run", "perf", "soak", "e2e", "bridge",
            "cam", "calibrate"]


class CLITests(unittest.TestCase):
    def subcommands(self) -> list[str]:
        parser = cli.build_parser()
        action = next(a for a in parser._actions if a.dest == "command")
        return list(action.choices)

    def test_the_commands_are_the_documented_ones(self):
        self.assertEqual(self.subcommands(), COMMANDS)
        table = (Path(__file__).resolve().parents[3] / "plan" / "VERIFICATION.md").read_text()
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
        self.assertTrue(parse(["soak", "--pipeline", "--minutes", "30", "--writer", "apple"]).pipeline)
        self.assertEqual(parse(["cam", "clip", "cheer", "--camera", "X"]).camera, "X")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parse(["mumble", "--levels", "1", "--board-volume"])


class FakeBoard(Link):
    """Answers each debug message with the scripted reply for its type."""

    timeout = 0.05

    def __init__(self, replies: dict[str, dict]) -> None:
        super().__init__()
        self.replies = replies
        self.sent: list[dict] = []
        self.pending = b""

    def _write(self, data: bytes) -> None:
        msg = json.loads(data)
        self.sent.append(msg)
        if msg["t"] in self.replies:
            self.pending += json.dumps({"t": msg["t"], **self.replies[msg["t"]]}).encode() + b"\n"

    def _read(self) -> bytes:
        out, self.pending = self.pending, b""
        return out


class PlayTests(unittest.TestCase):
    def play(self, what: str) -> tuple[int, list]:
        board = FakeBoard({"dbg.ping": {"ble": "adv"}, "dbg.clock": {}, "dbg.state": {"moment": {"anim": what, "left_ms": 900}}})
        with mock.patch.object(cli, "Device", lambda port: board), contextlib.redirect_stdout(io.StringIO()):
            code = cli.cmd_play(cli.build_parser().parse_args(["play", what]))
        return code, [m.get("anim") for m in board.sent if m["t"] == "moment"]

    def test_play_ends_a_listening_left_playing_first(self):
        # No other animation replaces listening (BEHAVIORS.md §3.3), so the
        # empty moment goes first.
        self.assertEqual(self.play("cheer"), (0, [None, "cheer"]))
        self.assertEqual(self.play("listening"), (0, ["listening"]))


if __name__ == "__main__":
    unittest.main()
