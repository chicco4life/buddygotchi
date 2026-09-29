"""boopctl e2e's order check (plan/VERIFICATION.md L4) on a made-up app
log: a brain moment comes after the rules' reaction, and the device's
`ended` says whether a newer moment cut it short: the brain's next one
mustn't, a rule's one-shot may. Needs no board or app."""
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import e2e  # noqa: E402

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


if __name__ == "__main__":
    unittest.main()
