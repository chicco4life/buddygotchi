# Harness evals: the first five scenarios

2026-09-26. A deterministic eval suite for the two-stage harness
([EVALS.md](../../EVALS.md)): events in, each harness pass out, step by
step.

## The run

`make eval` (rules classifier, no writer):

```
pass  01-short-turn.json  A short turn: the brain stays quiet
pass  02-long-turn.json  A long turn is celebrated
pass  03-turn-failed.json  A failed turn gets an annoyed mumble
pass  04-shut-up.json  "Shut up" keeps Boop quiet for 30 minutes
pass  05-bad-answer.json  A bad answer or a brain error is contained
5/5 scenarios passed, classifier rules@2, writer none
```

Three runs with `--json` gave byte-identical reports. `make test`: 195
passed, including the four `EvalTests`.

## Does it catch regressions?

Each change below was made on its own, run, and undone.

| Change | Result |
| --- | --- |
| `Menu.check` no longer limits calls to one per output | 05 fails at step 2: both `react` calls run instead of `dropped (off menu)` |
| `04-shut-up.json` says "shh" instead of "shut up" | 04 fails: `react(feeling: curious, voice: mumble)` instead of `quiet`, and the next two turns reach the brain |

The first version of the suite, written against the one-stage harness
before it was rebased, caught a changed Fallbacks row, the call cap raised
from 3 to 4, and a wrong expectation in the same way.

## Notes

- A short turn's celebration is the core's `cheer`, not the brain's: the
  rules classifier does nothing for a finish under 5 minutes, so scenario
  01 expects `agent finished → nothing`.
- The rules classifier doesn't take "shh" as a request for quiet (it knows
  "shut up", "quiet", "hush", "stop talking" and "keep it down").
- Next candidates: talk that asks to remember something, with and without
  the writer; a burst of agent inputs merged into one; a tap only noted in
  the transcript; "needs you" holding agent inputs back; a new day.
