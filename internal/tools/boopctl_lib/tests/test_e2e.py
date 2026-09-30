"""boopctl e2e's order check (plan/VERIFICATION.md L4) on a made-up app
log: a brain moment comes after the rules' reaction, and the device's
`ended` says whether a newer moment cut it short: the brain's next one
mustn't, a rule's one-shot may. And e2e and soak --pipeline when the run
can't start. Needs no board or app."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import e2e  # noqa: E402
from boopctl_lib.device import DeviceError  # noqa: E402

LOG = """\
10:00:00.000 hook: claude UserPromptSubmit
10:00:00.001 link rules → {"t":"state","base":"working","mood":"calm"}
10:00:00.002 link brain → {"t":"moment","say":{"take":"new.d03"},"mood":"excited","loops":1,"id":7}
10:00:02.000 hook: claude Stop
10:00:02.001 link rules → {"t":"state","base":"idle","mood":"calm"}
10:00:02.002 link brain → {"t":"moment","anim":"task_complete","outcome":"success","mood":"proud","loops":1,"id":8}
10:00:02.100 device: moment 7 ended done
10:00:03.000 link brain → {"t":"moment","say":{"take":"new.d03"},"mood":"calm","loops":1,"id":9}
10:00:03.100 device: moment 8 ended cut (moment)
10:00:04.000 hook: claude UserPromptSubmit
10:00:04.001 link rules → {"t":"moment","anim":"starting"}
10:00:04.100 device: moment 9 ended cut (moment)
"""


class Recorder(SimpleNamespace):
    def __init__(self, log: str) -> None:
        super().__init__(app=SimpleNamespace(log_text=lambda: log), said=[], failed=[])

    def say(self, line: str) -> None:
        self.said.append(line)

    def fail(self, line: str) -> None:
        self.failed.append(line)


class OrderTests(unittest.TestCase):
    def test_each_brain_moment_after_the_rules_reaction_with_how_it_ended(self):
        moments = e2e.order(LOG)
        self.assertEqual([m["id"] for m in moments], [7, 8, 9])
        self.assertEqual([m["moment"] for m in moments], ["line", "task_complete", "line"])
        self.assertEqual([m["after_reaction_ms"] for m in moments], [1, 1, 999])
        self.assertEqual([m["ended"] for m in moments], ["done", "cut (moment)", "cut (moment)"])
        self.assertEqual([m["next_by"] for m in moments], ["brain", "brain", "rules"])

    def test_the_brain_cutting_its_own_moment_short_fails_and_a_rules_one_shot_doesnt(self):
        run = Recorder(LOG)
        result = e2e.check_order(run)
        self.assertEqual((result["early"], result["unended"]), (0, 0))
        self.assertEqual(result["cut_by_newer"], ["10:00:02.002 task_complete (8) by brain",
                                                  "10:00:03.000 line (9) by rules"])
        self.assertEqual(len(run.failed), 1)
        self.assertIn("cut short by the brain's next one", run.failed[0])

    def test_a_moment_never_ended_fails(self):
        run = Recorder(LOG.split("10:00:04.100")[0])
        self.assertEqual(e2e.check_order(run)["unended"], 1)
        self.assertTrue(any("never got the device's `ended`" in f for f in run.failed))

    def test_a_moment_before_any_rules_reaction_is_early(self):
        run = Recorder('10:00:00.000 link brain → {"t":"moment","say":{"take":"new.d03"},"mood":"calm","id":1}\n'
                       "10:00:01.000 device: moment 1 ended done\n")
        self.assertEqual(e2e.check_order(run)["early"], 1)
        self.assertEqual(len(run.failed), 1)


class SetupFailureTests(unittest.TestCase):
    """No board, no build or an app that exits: the run fails with the
    reason and still writes its result."""

    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        tmp, leak = Path(d.name), []
        self.out, self.leak = tmp / "out", leak
        self.out.mkdir()
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

        class NoBoard(e2e.Run):
            """Its throwaway state in the test's folder, and no board."""

            def __init__(self, root, out, brain, port):
                super().__init__(tmp / root.name, out, brain, port)

            def start(self):
                if leak:  # the log of an app that got partway
                    self.state.mkdir(parents=True)
                    (self.state / "boop.log").write_text(leak[0])
                raise DeviceError("no board on /dev/cu.usbserial-*")

        patch = mock.patch.object(e2e, "Run", NoBoard)
        patch.start()
        self.addCleanup(patch.stop)

    def test_e2e_writes_its_result(self):
        self.assertEqual(e2e.main(self.out, "scripted", None, None), 1)
        result = json.loads((self.out / "e2e-scripted.json").read_text())
        self.assertFalse(result["ok"])
        self.assertIn("no board on /dev/cu.usbserial-*", result["failures"])

    def test_soak_writes_its_result(self):
        self.assertEqual(e2e.soak(self.out, "scripted", None, 0.01), 1)
        result = json.loads((self.out / "soak-scripted.json").read_text())
        self.assertFalse(result["ok"])
        self.assertEqual((result["heap_min_after_2min"], result["series"]), (None, []))
        self.assertIn("no board on /dev/cu.usbserial-*", result["failures"])

    def test_named_fixtures_are_still_checked_for_private_words(self):
        self.leak.append("hook: claude PostToolUse PRIVATE_OUTPUT_9823\n")
        self.assertEqual(e2e.main(self.out, "scripted", None, ["claude/session.jsonl"]), 1)
        failures = json.loads((self.out / "e2e-scripted.json").read_text())["failures"]
        self.assertTrue(any(f.startswith("PRIVATE_ markers") for f in failures), failures)
        self.assertFalse(any("the harness saw an event" in f for f in failures), "the whole run's events aren't expected")


if __name__ == "__main__":
    unittest.main()
