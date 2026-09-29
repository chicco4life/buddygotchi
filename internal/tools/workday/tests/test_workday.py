"""The scripted working day's own tests: the day is the same for a seed,
well formed, and tells the story it says; the report counts what it says
(plan/EVALS.md §5). No app, no brain."""
from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import workday  # noqa: E402


class DayTests(unittest.TestCase):
    def test_same_seed_same_day(self) -> None:
        a = [(s.at, s.kind, s.line, s.taps) for s in workday.build_day(1).steps()]
        b = [(s.at, s.kind, s.line, s.taps) for s in workday.build_day(1).steps()]
        c = [(s.at, s.kind, s.line, s.taps) for s in workday.build_day(2).steps()]
        self.assertEqual(a, b)
        self.assertNotEqual(a, c)

    def test_turns_never_overlap_on_one_thread(self) -> None:
        open_turn: dict[str, float] = {}
        for s in workday.build_day(1).steps():
            session, hook = s.line.get("session"), s.line.get("hook")
            if hook == "UserPromptSubmit":
                self.assertNotIn(session, open_turn, f"{session} starts a turn at {workday.clock(s.at)} inside another")
                open_turn[session] = s.at
            elif hook in ("Stop", "StopFailure") or s.line.get("interrupt"):
                self.assertIn(session, open_turn, f"{session} ends a turn it never started at {workday.clock(s.at)}")
                del open_turn[session]
        self.assertEqual(open_turn, {})

    def test_the_story(self) -> None:
        steps = workday.build_day(1).steps()
        hooks = Counter(s.line.get("hook") for s in steps)
        failures = [s for s in steps if s.line.get("hook") == "PostToolUseFailure" and not s.line.get("interrupt")]
        self.assertEqual({s.line["topic"] for s in failures}, {"tests", "build"})
        self.assertEqual(len([s for s in failures if s.line["topic"] == "tests"]), 7)
        self.assertEqual(len([s for s in failures if s.line["topic"] == "build"]), 3)
        self.assertEqual(hooks["StopFailure"], 2)
        self.assertEqual(hooks["PermissionRequest"], 2)
        self.assertEqual(sum(s.taps for s in steps if s.kind == "taps"), 12)
        self.assertGreater(hooks["UserPromptSubmit"], 150)
        # Lunch: over an hour with nothing, for the heartbeat.
        gaps = [b.at - a.at for a, b in zip(steps, steps[1:])]
        self.assertGreater(max(gaps), 3600)
        # 09:00 to about 17:40.
        self.assertLess(steps[-1].at, 9 * 3600)

    def test_the_plan_names_the_story(self) -> None:
        text = workday.plan(1)
        self.assertIn("tests fail three times, then pass", text)
        self.assertIn("lunch", text)


def entry(seq: int, at_min: int, view: dict | None = None, action: dict | None = None, settle: dict | None = None,
          **body) -> str:
    """A debug.jsonl line: a view event made by the raw event `seq`, an
    action (a raw `action` event, its start if pending) or a started one's
    end, or a pass as given."""
    base = 1_791_990_000_000  # any time; the report reads local hours
    at = base + at_min * 60_000
    if view is not None:
        body = {"view": {"id": seq, "from": [seq], "notes": [], **view}}
    elif action is not None:
        data = {"for": action["for"], "ok": action["ok"], "message": action["message"], "by": "brain"}
        body = {"event": {"seq": seq, "ts": at, "source": "boop", "type": "action",
                          **({"phase": "start"} if action.get("pending") else {}), "specific_type": action["name"],
                          "data": data}}
    elif settle is not None:
        body = {"event": {"seq": seq, "ts": at, "source": "boop", "type": "action", "phase": "end", "specific_type": "react",
                          "data": {"for": settle["for"], "outcome": settle["end"], "by": "brain"}}}
    return json.dumps({"received_at_ms": at, **body})


class ReportTests(unittest.TestCase):
    def test_counts_by_kind_of_line(self) -> None:
        start = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True, "facts": {}}
        short = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a short turn.",
                 "wakes_brain": True, "facts": {"outcome": "done", "length_ms": 8000, "tools_failed": 0}}
        fail = {"type": "tool", "phase": "end", "line": "claude's tests failed on \"api\".", "wakes_brain": True, "facts": {}}
        lines = [
            entry(1, 0, view=start),
            entry(2, 0, **{"pass": {"for": 1, "dropped": None}}),
            entry(3, 0, action={"for": 1, "name": "mood", "ok": True, "message": "Boop's mood changed: calm → excited."}),
            entry(4, 1, view=short),
            entry(5, 1, **{"pass": {"for": 4, "dropped": None}}),
            entry(6, 2, view=fail),
            entry(7, 2, **{"pass": {"for": 6, "dropped": None}}),
            entry(8, 2, action={"for": 6, "name": "react", "ok": True, "pending": True,
                                "message": "Boop made a grumpy face, held twice, and said \"Tsk...\"."}),
            entry(9, 2, settle={"for": 8, "end": "done"}),
            entry(10, 2, action={"for": 6, "name": "mood", "ok": True, "message": "Boop's mood changed: excited → grumpy."}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            r = workday.summarize(path)
        t = workday.total(r)
        self.assertEqual(t["passes"], 3)
        self.assertEqual(t["mood_changes"], 2)
        self.assertEqual(t["mood_after_routine"], 1, "the change on a turn start counts, the one on a failure doesn't")
        self.assertEqual(t["back_to_rest"], 0)
        self.assertEqual(t["reactions"], 1)
        self.assertEqual(t["reacted"], Counter({"notable": 1}))
        self.assertEqual(t["lines"], Counter({"start": 1, "short": 1, "notable": 1}))
        self.assertEqual(t["faces"], Counter({"grumpy": 1}))
        self.assertEqual(t["loops"], Counter({"twice": 1}))
        self.assertEqual(t["words"], Counter({"Tsk...": 1}))
        self.assertEqual(r["reactions"][0]["word"], "Tsk...")
        # Excited from the first event to the failure 2 minutes later, then
        # grumpy to the last event, the same failure.
        self.assertEqual(r["mood_minutes"], {"excited": 2, "calm": 0, "grumpy": 0})

    def test_a_finish_is_read_from_the_reactions_message(self) -> None:
        """ReactAction's line for a finish names it: success, failure or reply
        (harness/DECISIONS.md §5); a face alone has none."""
        self.assertEqual(workday.finish("Boop played a success in a calm face, held once."), "success")
        self.assertEqual(workday.finish("Boop played a failure in an annoyed face, held twice."), "failure")
        self.assertEqual(workday.finish("Boop played a reply in a curious face, held once."), "reply")
        self.assertIsNone(workday.finish("Boop made a happy face, held once."))

    def test_the_takes_count_a_reaction_that_said_nothing_as_none(self) -> None:
        end = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a short turn.",
               "wakes_brain": True, "facts": {"outcome": "done", "length_ms": 50_000, "tools_failed": 0}}
        lines = [
            entry(1, 0, view=end),
            entry(2, 0, action={"for": 1, "name": "react", "ok": True, "pending": True,
                                "message": "Boop made a happy face, held once."}),
            entry(3, 1, view=end),
            entry(4, 1, action={"for": 3, "name": "react", "ok": True, "pending": True,
                                "message": "Boop made an excited face, held once, and said \"Go\"."}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            self.assertEqual(workday.total(workday.summarize(path))["words"], Counter({"none": 1, "Go": 1}))
            self.assertIn("Takes said (none: a reaction that said nothing): none 1, Go 1", workday.report([path]))

    def test_a_mood_fading_on_a_routine_line_is_counted_apart(self) -> None:
        start = {"type": "turn", "phase": "start", "line": "claude started turn 2 on \"api\".", "wakes_brain": True, "facts": {}}
        lines = [
            entry(1, 0, view=start),
            entry(2, 0, action={"for": 1, "name": "mood", "ok": True, "message": "Boop's mood changed: proud → calm."}),
            entry(3, 5, view=start),
            entry(4, 5, action={"for": 3, "name": "mood", "ok": True, "message": "Boop's mood changed: calm → proud."}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            t = workday.total(workday.summarize(path))
        self.assertEqual((t["mood_changes"], t["back_to_rest"], t["mood_after_routine"]), (2, 1, 1))

    def test_liveliness_and_its_check(self) -> None:
        """A 20-minute turn with the same happy face at 1 and 3 minutes and
        nothing after: quiet for 17 minutes at the end, two the same in a
        row; calm → grumpy → calm inside a minute is a bounce
        (EVALS.md §5)."""
        thread = {"session": "s-api"}
        start = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True,
                 "facts": {"thread": thread}}
        beat = {"type": "heartbeat", "line": "claude is still working on \"api\", a long turn.", "wakes_brain": True,
                "facts": {"thread": thread}}
        end = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a very long turn.",
               "wakes_brain": True, "facts": {"thread": thread, "outcome": "done", "length_ms": 1_200_000}}
        happy = "Boop made a happy face, held once."
        lines = [
            entry(1, 0, view=start),
            entry(2, 1, view=beat),
            entry(3, 1, action={"for": 2, "name": "react", "ok": True, "pending": True, "message": happy}),
            entry(4, 3, view=beat),
            entry(5, 3, action={"for": 4, "name": "react", "ok": True, "pending": True, "message": happy}),
            entry(6, 3, action={"for": 4, "name": "mood", "ok": True, "message": "Boop's mood changed: calm → grumpy."}),
            entry(7, 3, action={"for": 4, "name": "mood", "ok": True, "message": "Boop's mood changed: grumpy → calm."}),
            entry(8, 20, view=end),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            lv = workday.summarize(path)["lively"]
            text, ok = workday.check([path])
        self.assertEqual(lv["longest_quiet_min"], 17.0)
        self.assertEqual(lv["quiet_over_6_min"], 1)
        self.assertEqual((lv["longest_same_run"], lv["longest_same_what"], lv["repeat_pct"]), (2, "happy", 100),
                         "reported, not held to a limit")
        self.assertEqual(lv["mood_bounces"], 1)
        self.assertEqual(lv["min_mood_changes"], 2)
        self.assertEqual(lv["longest_rest_working_min"], 17.0)
        self.assertFalse(ok)
        self.assertIn("FAIL  longest_quiet_min ≤ 8: 17.0", text)
        self.assertIn("ok    quiet_over_6_min ≤ 3: 1", text)
        self.assertEqual(lv["min_reactions_per_turn"], 2.0, "two reactions, one turn ended")
        self.assertIn("ok    min_reactions_per_turn ≥ 0.8: 2.0", text)
        self.assertIn("(repeats, not held to a limit: 100% the same as the one before, at most 2 in a row)", text)

    def test_classes(self) -> None:
        def end(**facts) -> dict:
            return {"type": "turn", "phase": "end", "facts": {"outcome": "done", "tools_failed": 0, **facts}}
        self.assertEqual(workday.classify(end(length_ms=59_000)), "short")
        self.assertEqual(workday.classify(end(length_ms=60_000)), "minutes")
        # plan/harness/DECISIONS.md §2.3: a turn of 5 minutes or more is a big moment.
        self.assertEqual(workday.classify(end(length_ms=5 * 60_000 - 1)), "minutes")
        self.assertEqual(workday.classify(end(length_ms=5 * 60_000)), "notable")
        # The line says only the outcome and length, so failures along the way don't count.
        self.assertEqual(workday.classify(end(length_ms=5_000, tools_failed=1)), "short")
        self.assertEqual(workday.classify(end(length_ms=5_000, comeback="tests")), "short")
        self.assertEqual(workday.classify(end(length_ms=5_000, outcome="failed")), "notable")
        self.assertEqual(workday.classify({"type": "heartbeat"}), "quiet")
        self.assertEqual(workday.classify({"type": "poke"}), "notable")
        self.assertIsNone(workday.classify({"type": "tool", "phase": "wait"}))


class SettleTests(unittest.TestCase):
    def test_a_pass_is_looked_at_again_behind_a_barrier(self) -> None:
        """The app writes a pass before its actions: settling on the pass
        alone would let the next clock move end a reaction as never
        played. So `settle` moves the clock 1 ms as a barrier, and waits
        for the reaction it then finds."""
        wakes = {"type": "tool", "phase": "end", "line": "claude's tests failed on \"api\".", "wakes_brain": True, "facts": {}}
        with tempfile.TemporaryDirectory() as d:
            run = workday.Run(Path(d), "scripted", None, False)
            run.debug.write_text(entry(1, 0, view=wakes) + "\n" + entry(2, 0, **{"pass": {"for": 1, "dropped": None}}) + "\n")
            barriers: list[int] = []
            ended = threading.Event()

            def advance(ms: int) -> None:
                barriers.append(ms)
                with open(run.debug, "a") as f:
                    f.write(entry(3, 0, action={"for": 1, "name": "react", "ok": True, "pending": True,
                                                "message": "Boop made a determined face, held once."}) + "\n")

                def device_says_ended() -> None:
                    with open(run.debug, "a") as f:
                        f.write(entry(4, 0, settle={"for": 3, "end": "done"}) + "\n")
                    ended.set()
                threading.Timer(0.1, device_says_ended).start()

            run.advance = advance  # type: ignore[method-assign]
            run.settle()
            self.assertEqual(barriers, [1])
            self.assertTrue(ended.is_set(), "settle returned before the reaction ended")
            self.assertEqual((run.waiting_passes, run.waiting_settles), (set(), set()))
            # Nothing new since: no second barrier.
            run.settle()
            self.assertEqual(barriers, [1])

    def test_a_dropped_pass_needs_no_barrier(self) -> None:
        wakes = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True, "facts": {}}
        with tempfile.TemporaryDirectory() as d:
            run = workday.Run(Path(d), "scripted", None, False)
            run.debug.write_text(entry(1, 0, view=wakes) + "\n"
                                 + entry(2, 0, **{"pass": {"for": 1, "dropped": "late"}}) + "\n")
            barriers: list[int] = []
            run.advance = barriers.append  # type: ignore[method-assign]
            run.settle()
            self.assertEqual(barriers, [])
            self.assertEqual(run.dropped, 1)


if __name__ == "__main__":
    unittest.main()
