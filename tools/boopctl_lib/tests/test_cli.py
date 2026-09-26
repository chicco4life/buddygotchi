"""boopctl's command line: every subcommand parses and has help, and the
set stays the one plan/VERIFICATION.md §2 lists. Needs no board."""
import contextlib
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli  # noqa: E402

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


if __name__ == "__main__":
    unittest.main()
