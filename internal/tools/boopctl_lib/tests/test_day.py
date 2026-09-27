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
    s = {"t": "state", "v": 1, "base": "idle", "mood": mood, "busy": 0, "idle": 1, "wait": 1 if attn else 0, "vol": 6}
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
                         (3, 17, 20, 4, 6, 15, 0, 7, 5))
        self.assertEqual(sorted(self.day.hours), [1, 2, 3, 4, 5, 6])
        self.assertEqual(dict(t.faces), {"excited": 14, "curious": 2, "determined": 1, "happy": 1, "proud": 1, "sad": 1})
        self.assertEqual(self.day.forced, 9)

    def test_chatter_and_reactions_are_the_sent_mumbles_without_and_with_a_face(self):
        sent = [json.loads(line)["sent"] for f in ("debug.1.jsonl", "debug.jsonl")
                for line in (FIXTURE / f).read_text().splitlines() if line.startswith('{"sent":{"t":"moment"')]
        t = self.day.total()
        self.assertEqual(t.reactions, sum(1 for s in sent if s.get("say") and s.get("mood")))
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
        self.assertEqual(sorted(m.why for m in self.day.misses), [
            "cut short: you tapped Boop", "no device connected", "no word it finished", "something needs you",
            "the device disconnected", "the device never said it ended", "waited too long"])

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
        self.assertIn("  1× cut short: you tapped Boop: 01:53", lines)


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
        self.assertIn("Brain: 2 passes (median 4450 ms, slowest 8000 ms), 1 dropped, 1 chose no reaction", text)
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
