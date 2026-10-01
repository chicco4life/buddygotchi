"""boopctl's command line: every subcommand parses and has help, and the
set stays the one documentation/VERIFICATION.md §2 lists. Needs no board."""
import contextlib
import io
import json
import re
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli, common  # noqa: E402
from facegen import facegen  # noqa: E402
from fake_board import FakeBoard  # noqa: E402

COMMANDS = ["ping", "state", "shot", "send", "play", "takes", "card", "sim", "run", "perf", "soak", "e2e", "bridge",
            "cam", "dash", "day", "workday", "calibrate"]


def firmware_names(path: str, start: str, item: str = r'"(\w+)"', end: str = "};") -> list:
    """What `item` matches in firmware/src/`path`, from `start` to the next
    `end`: by default, the names in a C table."""
    src = (cli.REPO / "firmware" / "src" / path).read_text()
    body = src[src.index(start):]
    return re.findall(item, body[:body.index(end)])


class CLITests(unittest.TestCase):
    def subcommands(self) -> list[str]:
        parser = cli.build_parser()
        action = next(a for a in parser._actions if a.dest == "command")
        return list(action.choices)

    def test_the_commands_are_the_documented_ones(self):
        self.assertEqual(self.subcommands(), COMMANDS)
        table = (cli.REPO / "documentation" / "VERIFICATION.md").read_text()
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
        self.assertEqual(parse(["play", "cheer", "--take", "previous.yay"]).take, "previous.yay")
        self.assertEqual(parse(["play", "needs", "--seconds", "3"]).seconds, 3)
        self.assertEqual(parse(["takes", "--levels", "1", "10"]).levels, [1, 10])
        self.assertTrue(parse(["takes", "--only", "Go", "--board-volume"]).board_volume)
        self.assertTrue(parse(["soak", "--pipeline", "--minutes", "30", "--brain", "jev"]).pipeline)
        self.assertEqual(parse(["cam", "clip", "cheer", "--camera", "X"]).camera, "X")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parse(["takes", "--levels", "1", "--board-volume"])
        # A take the pack lacks is refused before the board is touched,
        # not by argparse, so --help works with no pack.
        with self.assertRaisesRegex(cli.DeviceError, "no take 'banana'"):
            cli.cmd_play(parse(["play", "cheer", "--take", "banana"]))


class PlayTests(unittest.TestCase):
    def play(self, what: str, *more: str, playing: str | None = None) -> tuple[int, list]:
        """Plays `what` on a board whose dbg.state says `playing` (by
        default the name play sends); returns play's exit code and the
        names of the `do`s it sent."""
        name = cli.OLD_ANIMS.get(what, what)
        board = FakeBoard.by_type({"dbg.ping": {"ble": "adv"}, "dbg.clock": {},
                                   "dbg.state": {"moment": {"anim": playing or name, "left_ms": 900, "variant": 1}}})
        self.board = board
        with mock.patch.object(cli, "Device", lambda port: board), contextlib.redirect_stdout(io.StringIO()):
            code = cli.cmd_play(cli.build_parser().parse_args(["play", what, *more]))
        return code, [m["name"] for m in self.dos()]

    def dos(self) -> list[dict]:
        return [m for m in self.board.sent if m["t"] == "do"]

    def args(self) -> list[dict]:
        return [m.get("args", {}) for m in self.dos()]

    def test_play_sets_the_mood(self):
        self.play("cheer", "--mood", "determined")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["determined"])
        self.play("cheer", "--mood", "wounded")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["wounded"])
        self.play("wiggle")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["happy"])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "cheer", "--mood", "cheerful"])

    def test_the_moods_are_the_devices(self):
        """PROTOCOL.md §3: the moods boopctl sends are facegen's, which it
        writes into firmware/assets/faces.h, in the device's order."""
        self.assertEqual(cli.MOODS, facegen.MOODS)
        self.assertEqual(cli.MOODS, firmware_names("../assets/faces.h", "kMoodNames["))

    def test_play_sends_just_the_animation_now(self):
        """A `do` with the animation's name, played `now` so it replaces
        whatever plays, with no id: play reads dbg.state, not `ended`
        (linkkit/SPEC.md §3)."""
        for anim in cli.ANIMS:
            self.assertEqual(self.play(anim), (0, [anim]))
            self.assertEqual(self.dos(), [{"t": "do", "name": anim, "play": "now"}])
        self.assertEqual(self.play("task_complete", playing="poked")[0], 1, "something else playing")

    def test_the_older_names_are_sent_by_todays(self):
        """The device no longer knows `cheer` or `wiggle`: play sends
        task_complete's success and poked."""
        self.assertEqual(self.play("cheer"), (0, ["task_complete"]))
        self.assertEqual(self.args(), [{"outcome": "success"}])
        self.assertEqual(self.play("wiggle"), (0, ["poked"]))
        self.assertEqual(self.args(), [{}])
        with self.assertRaisesRegex(cli.DeviceError, "task_complete --outcome failure"):
            self.play("cheer", "--outcome", "failure")

    def test_play_sends_a_take(self):  # PROTOCOL.md `do`: `say` is {"take": id}
        self.assertEqual(self.play("cheer", "--take", "new.d15")[0], 0)
        self.assertEqual(self.args()[0]["say"], {"take": "new.d15"})

    def test_play_sends_the_facts(self):  # PROTOCOL.md `do`: outcome, ctx, variant
        self.play("task_complete", "--outcome", "failure", "--variant", "2")
        self.assertEqual(self.args(), [{"outcome": "failure", "variant": 2}])
        self.play("starting", "--ctx", "session")
        self.assertEqual([a.get("ctx") for a in self.args()], ["session"])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "task_complete", "--outcome", "win"])

    def test_the_animations_are_the_devices(self):
        """BEHAVIORS.md §5: the names boopctl plays are the device's own, the
        names of the states whose designs they play (firmware/src/render/
        scene.cpp animState; faces.h names them), and all of them are in
        Boop's `hello.does` (PROTOCOL.md `hello`). The older two are play's
        own, sent by today's names."""
        names = firmware_names("../assets/faces.h", "kStateNames[")
        self.assertEqual(names, facegen.STATES)
        states = dict(zip(firmware_names("render/scene.h", "enum class SceneState", r"\bk\w+"), names))
        plays = firmware_names("render/scene.cpp", "SceneState animState(Anim a) {",
                               r"case Anim::k\w+: return SceneState::(k\w+);", end="\n}\n")
        self.assertEqual(cli.ANIMS + ["listening"], [states[s] for s in plays])
        self.assertTrue(set(cli.ANIMS + ["listening"]) <= set(common.DOES))
        self.assertEqual(set(common.DOES) - set(cli.ANIMS), {"react", "listening", "stop_listening"})
        self.assertTrue(set(cli.OLD_ANIMS.values()) <= set(cli.ANIMS))

    def test_the_do_names_are_the_devices(self):
        """PROTOCOL.md §3 (The names): the names the tools send are the ones
        the firmware puts in `hello.does`, in its order, and the ones it plays
        with no animation are the tools' NO_ANIM."""
        names = firmware_names("app/device.cpp", "kDoNames[kDoCount] =")
        self.assertEqual(common.DOES, names)
        anims = firmware_names("app/device.cpp", "kDoAnims[kDoCount] =", r"render::Anim::k(\w+)")
        self.assertEqual(len(anims), len(names))
        self.assertEqual(common.NO_ANIM, {n for n, a in zip(names, anims) if a == "None"})

    def test_play_sends_its_loops(self):  # PROTOCOL.md `do`: 1-6, none reads as 1
        self.play("cheer", "--loops", "3")
        self.assertEqual([a.get("loops") for a in self.args()], [3])
        self.play("cheer")
        self.assertEqual([a.get("loops") for a in self.args()], [None])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "cheer", "--loops", "7"])


class WireTests(unittest.TestCase):
    """The requests the tools send and read (linkkit/SPEC.md §3, PROTOCOL.md
    `do`), and the older logs' moments read the same way."""

    def test_a_do_as_the_tools_send_it(self):
        self.assertEqual(json.dumps(common.do("react", id=44, play="next", ttl=5000, mood="calm")),
                         '{"t": "do", "id": 44, "name": "react", "play": "next", "ttl": 5000, "args": {"mood": "calm"}}',
                         "in the vocabulary's order")
        self.assertEqual(common.do("poked"), {"t": "do", "name": "poked", "play": "now"}, "now, no id, no args")

    def test_what_a_request_asks(self):
        call = common.call
        finish = call({"t": "do", "id": 7, "name": "task_complete", "play": "next", "ttl": 5000,
                       "args": {"outcome": "success", "say": {"take": "a"}}})
        self.assertEqual((finish["anim"], finish["id"], finish["play"], finish["outcome"], finish["say"]),
                         ("task_complete", 7, "next", "success", {"take": "a"}))
        self.assertEqual({k: call({"t": "do", "name": k})["anim"] for k in ("react", "stop_listening", "listening")},
                         {"react": None, "stop_listening": None, "listening": "listening"})
        self.assertEqual(call({"t": "do", "name": "starting"})["play"], "next", "the kit's default")
        # Older logs: a moment played at once; the empty one ended push-to-talk.
        cheer = call({"t": "moment", "anim": "cheer", "loops": 1})
        self.assertEqual((cheer["name"], cheer["anim"], cheer["play"], cheer["loops"]), ("cheer", "cheer", "now", 1))
        self.assertEqual(call({"t": "moment", "say": {}, "mood": "calm", "id": 3})["name"], "react")
        self.assertEqual(call({"t": "moment"})["name"], "stop_listening")
        self.assertIsNone(call({"t": "state", "base": "idle"}))

    def test_what_says_a_request_ended(self):
        self.assertEqual(common.ended({"t": "ev", "kind": "ended", "data": {"id": 44, "how": "cut", "why": "tap"}}),
                         {"id": 44, "how": "cut", "why": "tap"})
        self.assertIsNone(common.ended({"t": "ev", "kind": "tap", "did": "dip", "data": {"on": 44}}))
        self.assertIsNone(common.ended({"t": "ended", "id": 44, "how": "done"}), "the old wire is gone")


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


class TakesTests(unittest.TestCase):
    """The takes boopctl plays are the board's, from the voice pack on its
    card (.build/voice/voice.bin)."""

    def test_the_takes_are_the_boards(self):
        takes = cli.takes()
        self.assertEqual(len(takes), 2722)
        self.assertEqual([t.id for t in takes], sorted((t.id for t in takes), key=str.encode), "the pack's order: by id")
        go = cli.take("previous.go")
        self.assertEqual((go.id, go.text, go.ms), ("previous.go", "Go", 638))
        self.assertEqual(cli.take("new.d15").text, "Bada bing bada boom")
        self.assertIsNone(cli.take("banana"))

    def test_only_picks_by_id_or_text(self):
        gos = cli.chosen_takes("Go")
        self.assertTrue({"previous.go", "new.d01", "new.d02"} <= {t.id for t in gos})
        self.assertTrue(all(t.text == "Go" or "go" in t.text.lower().split() for t in gos), [t.text for t in gos])
        self.assertEqual([t.id for t in cli.chosen_takes("new.d15")], ["new.d15"])
        self.assertTrue(all("again" in t.text.lower() for t in cli.chosen_takes("again")))
        self.assertEqual([t.id for t in cli.chosen_takes("mamma mia")], ["new.d14"])
        self.assertEqual({t.text for t in cli.chosen_takes("boom")}, {"Bada bing bada boom", "Boom shakalaka"})
        self.assertEqual(len(cli.chosen_takes(None)), 2722)
        with self.assertRaises(cli.DeviceError):
            cli.chosen_takes("banana")

    def test_a_take_is_checked_against_audio_out(self):
        t = cli.take("previous.go")
        states = iter([{"audio": {"out": {"lines": 3}}, "amp": False},
                       {"amp": True, "vol": 6, "audio": {"out": {"lines": 4, "take": "previous.go", "plan_ms": 638,
                                                                  "out_ms": 638, "wall_ms": 648, "cut": False}}}])
        board = FakeBoard(lambda msg: json.dumps({"t": msg["t"], **next(states)}).encode() + b"\n"
                          if msg["t"] == "dbg.state" else b"")
        r = cli.check_take(board, t)
        self.assertTrue(r["ok"], r)
        self.assertIn({"t": "do", "name": "react", "play": "now", "args": {"say": {"take": "previous.go"}}}, board.sent,
                      "a line on its own: a reaction with no face, played at once")


class SoakTests(unittest.TestCase):
    """The soak's requests, and how it holds the board to one `ended` for
    each reaction (linkkit/SPEC.md §3–4)."""

    def test_reactions_are_waited_requests_with_loops(self):
        import random
        rng = random.Random(1)
        for i in range(1, 50):
            m = cli.soak_reaction(rng, i)
            self.assertEqual((m["t"], m["id"], m["name"], m["play"], m["ttl"]), ("do", i, "react", "next", 5000),
                             "as the Mac sends the brain's")
            self.assertIn(m["args"]["mood"], cli.MOODS)
            self.assertTrue(1 <= m["args"]["loops"] <= 6)
            self.assertTrue(m["args"]["say"] == {} or cli.take(m["args"]["say"]["take"]))
        dos = [cli.soak_do(rng) for _ in range(300)]
        self.assertTrue({m["name"] for m in dos} == set(cli.ANIMS) | {"react"}, "every animation, and lines")
        finishes = [m["args"] for m in dos if m["name"] == "task_complete"]
        self.assertTrue(finishes)
        self.assertTrue(all(1 <= a["loops"] <= 3 and a["outcome"] in cli.OUTCOMES for a in finishes))
        self.assertTrue(all(m["args"]["ctx"] in cli.CTXS for m in dos if m["name"] == "starting"))
        self.assertTrue(all(m["args"]["say"] is not None for m in dos if m["name"] == "react"), "a line says something")
        self.assertFalse(any("id" in m or "mood" in m.get("args", {}) for m in dos), "the rest aren't waited on")
        # Each asks for its turn as the Mac or a tool would (PROTOCOL.md `do`).
        plays = {m["name"]: (m["play"], m.get("ttl")) for m in dos}
        self.assertEqual(plays, {"starting": ("if_free", None), "stopped": ("if_free", None), "error": ("if_free", None),
                                 "helper_return": ("if_free", None), "poked": ("now", None), "tap_spam": ("now", None),
                                 "task_complete": ("next", 5000), "reply_ready": ("next", 5000), "react": ("next", 5000)})

    def test_each_reaction_ends_once(self):
        ended = [{"id": 1, "how": "done"}, {"id": 2, "how": "cut", "why": "tap"}, {"id": 3, "how": "skipped"}]
        r = cli.ended_report([1, 2, 3], ended, 0)
        self.assertTrue(r["ended_ok"])
        self.assertEqual(r["ended_how"], {"done": 1, "cut (tap)": 1, "skipped": 1})
        self.assertFalse(cli.ended_report([1, 2, 3], ended + [ended[0]], 0)["ended_ok"])  # twice
        self.assertFalse(cli.ended_report([1, 2], ended, 0)["ended_ok"])  # an id never sent
        # A missing one only when a line was lost on the way.
        self.assertFalse(cli.ended_report([1, 2, 3, 4], ended, 0)["ended_ok"])
        self.assertTrue(cli.ended_report([1, 2, 3, 4], ended, 1)["ended_ok"])
        self.assertEqual(cli.ended_report([1, 2, 3, 4], ended, 1)["ended_missing"], [4])

    def test_waiting_behind_another_is_an_answer_and_an_unknown_name_fails(self):
        """The device queues the reactions: one that waited past its ttl, or
        was refused, ended as surely as one that played. A name the device
        doesn't play means the soak and the firmware disagree."""
        ended = [{"id": 1, "how": "skipped", "why": "late"}, {"id": 2, "how": "cut", "why": "now"},
                 {"id": 3, "how": "skipped", "why": "needs_you"}, {"id": 4, "how": "skipped", "why": "full"}]
        r = cli.ended_report([1, 2, 3, 4], ended, 0)
        self.assertTrue(r["ended_ok"], r)
        self.assertEqual(r["ended_how"], {"skipped (late)": 1, "cut (now)": 1, "skipped (needs_you)": 1,
                                          "skipped (full)": 1})
        r = cli.ended_report([1, 2, 3, 4, 5], ended + [{"id": 5, "how": "skipped", "why": "unknown"}], 0)
        self.assertEqual((r["ended_ok"], r["names_unknown"]), (False, 1))

    def test_the_link_hears_what_comes_unasked(self):
        board = FakeBoard.in_turn([b'{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.0.0","does":[]}\n'
                                   b'{"t":"ev","kind":"ended","data":{"id":7,"how":"done"}}\n'
                                   b'{"t":"ev","kind":"ended","data":{"id":8\n'
                                   b'{"t":"ev","kind":"tap","did":"poked"}\n{"t":"dbg.ping","up":1}\n'])
        heard: list[dict] = []
        board.heard = heard.append
        board.request({"t": "dbg.ping"})
        self.assertEqual([m["t"] for m in heard], ["hello", "ev", "torn", "ev"])
        self.assertEqual([cli.ended(m) for m in heard], [None, {"id": 7, "how": "done"}, None, None],
                         "only an `ev` of kind `ended` is one")


if __name__ == "__main__":
    unittest.main()
