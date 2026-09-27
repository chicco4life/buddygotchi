"""boopctl day (plan/VERIFICATION.md §2): a day's summary from debug mode's
logs (plan/harness/HARNESS.md §9), against a simulated day recorded from a
real headless run with a relaunch mid-day (fixtures/day, made by
plan/evidence/2026-09-28-tonight/daylog/drive_day.py), and against small
made-up logs for the rules. Needs no board, app or sim."""
import contextlib
import io
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli, day  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "day"
TZ = os.environ.get("TZ")


def setUpModule():
    # The fixture was recorded in Seoul; its hours are Seoul's.
    os.environ["TZ"] = "Asia/Seoul"
    time.tzset()


def tearDownModule():
    if TZ is None:
        os.environ.pop("TZ", None)
    else:
        os.environ["TZ"] = TZ
    time.tzset()


def at(clock: str, date: str = "2026-09-28") -> int:
    """Local time → ms."""
    return int(time.mktime(time.strptime(f"{date} {clock}", "%Y-%m-%d %H:%M:%S")) * 1000)


def state(t: int, attn: tuple | None = None, mood: str = "happy", more: int = 0) -> dict:
    s = {"t": "state", "v": 1, "base": "idle", "mood": mood, "busy": 0, "vol": 6}
    if attn:
        s["attn"] = {"agent": attn[0], "project": attn[1], "more": more}
    return {"sent": s, "received_at_ms": t}


def launch(*lines: dict) -> day.Launch:
    return day.Launch("debug.jsonl", [{"questions": [], "received_at_ms": lines[0]["received_at_ms"]}, *lines])


class FilesTests(unittest.TestCase):
    def test_the_state_dirs_logs_oldest_launch_first(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ["debug.jsonl", "debug.1.jsonl", "debug.2.jsonl", "debug.10.jsonl", "debug.x.jsonl", "boop.log"]:
                (Path(d) / name).write_text("")
            self.assertEqual([p.name for p in day.launch_files(Path(d))],
                             ["debug.10.jsonl", "debug.2.jsonl", "debug.1.jsonl", "debug.jsonl"])

    def test_each_file_is_a_launch_and_a_questions_line_starts_another(self):
        launches = day.read_launches(day.launch_files(FIXTURE))
        self.assertEqual([x.name for x in launches], ["debug.1.jsonl", "debug.jsonl"])
        self.assertTrue(all("questions" in x.lines[0] for x in launches))
        with tempfile.TemporaryDirectory() as d:
            both = Path(d) / "both.jsonl"
            both.write_text((FIXTURE / "debug.1.jsonl").read_text() + "{not json\n" + (FIXTURE / "debug.jsonl").read_text())
            self.assertEqual([len(x.lines) for x in day.read_launches([both])], [len(x.lines) for x in launches],
                             "a line cut short is skipped")


class FixtureTests(unittest.TestCase):
    """The simulated day: a Claude turn in the first launch; then Codex and
    Claude working, both needing you, a tap, three failed tests and a
    rate limit; a quiet midday with the board unplugged a while; pokes and
    reactions forced from the dashboard; and a long Claude turn."""

    @classmethod
    def setUpClass(cls):
        cls.day = day.summarise(day.read_launches(day.launch_files(FIXTURE)), "2026-09-28")

    def test_what_boop_did_by_the_hour(self):
        t = self.day.total()
        self.assertEqual((t.cheers, t.chatter, t.reactions, t.chirps, t.moods, t.passes, t.dropped, t.missed, t.taps),
                         (3, 17, 15, 4, 6, 15, 0, 2, 5))
        self.assertEqual(sorted(self.day.hours), [1, 2, 3, 4, 5, 6])
        self.assertEqual([self.day.hours[h].reactions for h in range(1, 7)], [5, 5, 1, 3, 1, 0])
        self.assertEqual(dict(t.faces), {"excited": 15}, "the scripted brain always answers excited")
        self.assertEqual((self.day.forced, self.day.forced_reacts), (9, 8))

    def test_the_brains_reactions_are_its_react_actions_and_forced_ones_are_apart(self):
        """20 moments with a face were sent (counted by hand): 14 of the
        brain's 15 reactions (02:11's never reached the device) and 6 of the
        8 forced (01:48's was refused and 04:48's excited one waited too
        long). Chatter and cheers are the sent moments."""
        sent = [json.loads(line)["sent"] for f in ("debug.1.jsonl", "debug.jsonl")
                for line in (FIXTURE / f).read_text().splitlines() if line.startswith('{"sent":{"t":"moment"')]
        t = self.day.total()
        faces = [s["mood"] for s in sent if s.get("say") and s.get("mood")]
        self.assertEqual(len(faces), (t.reactions - 1) + (self.day.forced_reacts - 2))
        self.assertEqual(sorted(f for f in faces if f != "excited"), ["curious", "curious", "determined", "happy",
                                                                      "proud", "sad"], "the forced ones")
        self.assertEqual(t.chatter, sum(1 for s in sent if s.get("say") and not s.get("mood")))
        self.assertEqual(t.cheers, sum(1 for s in sent if s.get("anim") == "cheer"))

    def test_needs_you_from_attn_appearing_to_clearing(self):
        needs = [(day.clock(n.start), n.end - n.start, n.who, n.chirps, n.open) for n in self.day.needs]
        self.assertEqual(needs, [
            ("01:34", 12028, ["claude · jetpack"], 1, False),
            ("01:47", 363666, ["codex · landing", "claude · jetpack"], 2, False),
            ("05:13", 421612, ["claude · jetpack"], 1, False),
        ])
        self.assertEqual(self.day.hours[1].needs_ms, 12028 + 363666)
        self.assertEqual(self.day.total().needs_ms, 12028 + 363666 + 421612)

    def test_each_mood_change_with_what_made_it(self):
        moods = [(m.before, m.after, m.why.split(":")[0]) for m in self.day.moods]
        self.assertEqual(moods, [
            ("happy", "proud", "forced from the dashboard"),
            ("proud", "happy", "turn_start"),
            ("happy", "determined", "forced from the dashboard"),
            ("determined", "happy", "turn_end"),
            ("happy", "grumpy", "forced from the dashboard"),
            ("grumpy", "happy", "turn_start"),
        ])

    def test_reactions_that_didnt_happen_and_why(self):
        # Every end harness/DECISIONS.md §5 lists that the run could bring
        # about, and the action's own refusal.
        self.assertEqual(sorted((m.forced, m.why) for m in self.day.misses), [
            (False, "no device connected"), (False, "no word it finished"),
            (True, "cut short: you tapped Boop"), (True, "something needs you"), (True, "the device disconnected"),
            (True, "the device never said it ended"), (True, "waited too long")])

    def test_the_relaunch_keeps_the_morning(self):
        """Without debug.1.jsonl (before HARNESS.md §9 kept it), the first
        launch's needs-you, cheer and proud mood are gone."""
        alone = day.summarise(day.read_launches([FIXTURE / "debug.jsonl"]), "2026-09-28")
        self.assertEqual(len(alone.needs), 2)
        self.assertEqual(alone.total().cheers, 2)
        self.assertEqual(self.day.launches[0][0], "debug.1.jsonl")
        self.assertEqual(self.day.running_ms, sum(b - a for _, a, b, _ in self.day.launches))

    def test_the_table(self):
        text = day.render(self.day)
        lines = text.splitlines()
        self.assertEqual(lines[0], "Boop's day: Monday 2026-09-28, 01:34–06:01, 2 launches")
        head = next(i for i, x in enumerate(lines) if x.startswith("hour"))
        self.assertEqual(lines[head].split(), ["hour", "cheers", "chatter", "reacts", "chirps", "moods", "passes",
                                               "dropped", "missed", "taps", "needs", "you", "faces"])
        self.assertEqual([x.split()[0] for x in lines[head + 1:head + 8]], ["01", "02", "03", "04", "05", "06", "all"])
        self.assertIn("  01:47  codex · landing → claude · jetpack  6 min 4 s, 2 chirps", lines)
        self.assertIn("  1× cut short: you tapped Boop (forced): 01:53", lines)
        self.assertIn("Reactions that didn't happen: 2 of the brain's 15, and 5 of the 8 forced from the dashboard",
                      lines)


def event(t: int, seq: int, kind: str, wakes: bool = True) -> dict:
    return {"event": {"kind": kind, "line": f"a {kind}.", "wakes_brain": wakes}, "seq": seq, "received_at_ms": t}


def a_pass(t: int, seq: int, for_: int | None, **choices: str) -> dict:
    body = {"for": for_, "dropped": None, "latency_ms": 0 if for_ is None else 700,
            "answers": {k: {"choice": v, "p": {v: 1}} for k, v in choices.items()}}
    body.update({"by": "dashboard"} if for_ is None else {"brain": "jev:jev-latest"})
    return {"pass": body, "seq": seq, "received_at_ms": t}


def action(t: int, seq: int, for_: int | None, name: str, ok: bool = True, message: str = "", pending: bool = False):
    body = {"for": for_, "name": name, "ok": ok, "message": message, "latency_ms": 0,
            **({"pending": True} if pending else {}), **({"by": "dashboard"} if for_ is None else {})}
    return {"action": body, "seq": seq, "received_at_ms": t}


def status(t: int, connected: bool) -> dict:
    return {"status": {"brain": "jev:jev-latest", "connected": connected, "personality": "boop", "sessions": []},
            "received_at_ms": t}


class SmallDayTests(unittest.TestCase):
    """Three launches counted by hand. The first ends while something
    needs you; the second starts disconnected and connects later; the
    third starts in a mood set while no debug log ran."""

    @classmethod
    def setUpClass(cls):
        first = [
            {"questions": [], "received_at_ms": at("09:00:00")}, status(at("09:00:00"), True), state(at("09:00:00")),
            event(at("09:05:00"), 1, "turn_start"),
            a_pass(at("09:05:01"), 2, 1, mood="grumpy", react="grumpy"),
            state(at("09:05:01"), mood="grumpy"),  # the mood action's state goes out before its entry
            action(at("09:05:01"), 3, 1, "mood", message="Boop's mood changed: happy → grumpy."),
            action(at("09:05:01"), 4, 1, "react", pending=True),
            {"settle": {"for": 4, "end": "done"}, "seq": 5, "received_at_ms": at("09:05:03")},
            state(at("09:10:00"), ("claude", "a"), mood="grumpy"),  # needs you: a chirp
            state(at("09:20:00"), ("claude", "a"), mood="excited"),  # the dashboard's mood line
            action(at("09:20:00"), 6, None, "mood", message="Boop's mood changed: grumpy → excited."),
            a_pass(at("09:30:00"), 7, None, react="happy"),
            action(at("09:30:00"), 8, None, "react", ok=False, message="something needs you"),
            state(at("09:40:00"), ("claude", "a"), mood="excited"),  # the launch ends: still up
        ]
        second = [
            {"questions": [], "received_at_ms": at("10:00:00")}, status(at("10:00:00"), False),
            state(at("10:00:00"), mood="excited"),  # carried over: no change
            status(at("10:10:00"), True),
            state(at("10:15:00"), ("claude", "a"), mood="excited"),  # a chirp again: 10:00's state had no attn
            state(at("10:20:00"), mood="excited"),
            event(at("10:30:00"), 1, "tool_use"),
            a_pass(at("10:30:01"), 2, 1, react="curious"),
            action(at("10:30:01"), 3, 1, "react", pending=True),
            {"settle": {"for": 3, "end": "failed", "why": "waited too long"}, "seq": 4, "received_at_ms": at("10:30:07")},
            state(at("10:45:00"), mood="excited"),
        ]
        third = [{"questions": [], "received_at_ms": at("11:00:00")}, state(at("11:00:00"), mood="sad"),
                 state(at("11:05:00"), mood="sad")]
        cls.tmp = tempfile.TemporaryDirectory()
        for name, lines in (("debug.2.jsonl", first), ("debug.1.jsonl", second), ("debug.jsonl", third)):
            (Path(cls.tmp.name) / name).write_text("".join(json.dumps(x) + "\n" for x in lines))
        cls.day = day.summarise(day.read_launches(day.launch_files(Path(cls.tmp.name))), "2026-09-28")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_the_hours(self):
        row = lambda h: (h.reactions, dict(h.faces), h.chirps, h.moods, h.passes, h.missed, h.needs_ms // 60_000)
        self.assertEqual({hr: row(h) for hr, h in self.day.hours.items()}, {
            9: (1, {"grumpy": 1}, 1, 2, 1, 0, 30),
            10: (1, {"curious": 1}, 1, 0, 1, 1, 5),
            11: (0, {}, 0, 1, 0, 0, 0),
        })
        self.assertEqual((self.day.forced, self.day.forced_reacts), (1, 1))

    def test_moods_by_the_brain_the_dashboard_and_between_launches(self):
        self.assertEqual([(day.clock(m.at), m.before, m.after, m.why) for m in self.day.moods], [
            ("09:05", "happy", "grumpy", "turn_start: a turn_start."),
            ("09:20", "grumpy", "excited", "forced from the dashboard"),
            ("11:00", "excited", "sad", "between launches"),
        ])

    def test_needs_you_across_the_relaunch(self):
        self.assertEqual([(day.clock(n.start), n.end - n.start, n.chirps, n.open) for n in self.day.needs], [
            ("09:10", 30 * 60_000, 1, True), ("10:15", 5 * 60_000, 1, False)])

    def test_running_and_connected(self):
        self.assertEqual([(name, day.clock(a), day.clock(b)) for name, a, b, _ in self.day.launches], [
            ("debug.2.jsonl", "09:00", "09:40"), ("debug.1.jsonl", "10:00", "10:45"), ("debug.jsonl", "11:00", "11:05")])
        self.assertEqual((self.day.running_ms, self.day.connected_ms), (90 * 60_000, 75 * 60_000))

    def test_what_didnt_happen(self):
        text = day.render(self.day).splitlines()
        self.assertIn("Reactions that didn't happen: 1 of the brain's 2, and 1 of the 1 forced from the dashboard", text)
        self.assertIn("  1× waited too long: 10:30", text)
        self.assertIn("  1× something needs you (forced): 09:30", text)
        self.assertIn("  09:10  claude · a  30 min (still up when the log ends)", text)
        self.assertIn("Needs you: 2 times, 35 min in all; cleared in 5 min", text)
        self.assertIn("Brain: 2 passes (median 700 ms, slowest 700 ms), 0 dropped, 0 chose no reaction; "
                      "and 1 forced from the dashboard, asking for 1 reaction", text)


class RuleTests(unittest.TestCase):
    def test_a_chirp_is_a_new_needs_you_or_a_different_one(self):
        """PROTOCOL.md §3: a new attn, or a different agent or project,
        chirps once; the keepalive's repeats and a changed `more` don't."""
        d = day.summarise([launch(
            state(at("09:00:00")),
            state(at("09:01:00"), ("claude", "a")),
            state(at("09:01:10"), ("claude", "a")),
            state(at("09:02:00"), ("claude", "a"), more=1),
            state(at("09:03:00"), ("codex", "b")),
            state(at("09:04:00")),
            state(at("09:10:00"), ("claude", "a")),
            state(at("09:12:00"), ("claude", "a")),
        )], "2026-09-28")
        self.assertEqual(d.total().chirps, 3)
        self.assertEqual([(n.end - n.start, n.chirps, n.open) for n in d.needs], [(180_000, 2, False), (120_000, 1, True)],
                         "one still up when its launch's log ends")
        self.assertIn("(still up when the log ends)", day.render(d))

    def test_needs_you_across_midnight_counts_on_each_day(self):
        lines = launch(state(at("23:50:00", "2026-09-27"), ("claude", "a")), state(at("00:10:00")))
        before, after = (day.summarise([lines], d) for d in ("2026-09-27", "2026-09-28"))
        self.assertEqual((before.hours[23].needs_ms, after.hours[0].needs_ms), (600_000, 600_000))
        self.assertEqual((before.total().chirps, after.total().chirps), (1, 0))

    def test_dropped_passes_and_skipped_events(self):
        t = at("10:00:00")
        d = day.summarise([launch(
            state(t),
            {"event": {"kind": "turn_start", "line": "claude started turn 1.", "wakes_brain": True}, "seq": 1,
             "received_at_ms": t},
            {"event": {"kind": "tool_use", "line": "claude's tests failed.", "wakes_brain": True}, "seq": 2,
             "received_at_ms": t + 10},
            {"event": {"kind": "turn_end", "line": "claude finished.", "wakes_brain": True}, "seq": 3,
             "received_at_ms": t + 20},
            {"pass": {"brain": "jev:jev-latest", "for": 1, "dropped": "timed out after 8000 ms", "answers": {},
                      "latency_ms": 8000}, "seq": 4, "received_at_ms": t + 8000},
            {"pass": {"brain": "jev:jev-latest", "for": 3, "dropped": None, "latency_ms": 900,
                      "answers": {"react": {"choice": "none", "p": {"none": 0.9}}}}, "seq": 5, "received_at_ms": t + 9000},
        )], "2026-09-28")
        self.assertEqual((d.total().passes, d.total().dropped, d.quiet, d.skipped), (2, 1, 1, 1))
        text = day.render(d)
        self.assertIn("Brain: 2 passes (median 4450 ms, slowest 8000 ms), 1 dropped, 1 chose no reaction; "
                      "none forced from the dashboard", text.splitlines())
        self.assertIn("  dropped 1×: timed out after 8000 ms", text)
        self.assertIn("  1 events woke it but got no pass", text)

    def test_an_hour_with_no_lines_is_one_boop_wasnt_logging(self):
        d = day.summarise([launch(state(at("09:00:00"))), launch(state(at("11:30:00")))], "2026-09-28")
        row = next(x for x in day.render(d).splitlines() if x.startswith("10"))
        self.assertIn("no log", row)


class CLITests(unittest.TestCase):
    def test_day_on_a_state_dir(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cli.main(["day", "--state-dir", str(FIXTURE)]), 0)
        self.assertTrue(out.getvalue().startswith("Boop's day: Monday 2026-09-28"))

    def test_a_day_with_nothing_logged(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cli.main(["day", "--date", "2026-9-27", str(FIXTURE / "debug.jsonl")]), 1)
        self.assertIn("Nothing in the debug logs on 2026-09-27: they run from 2026-09-28 01:35", out.getvalue())


if __name__ == "__main__":
    unittest.main()
