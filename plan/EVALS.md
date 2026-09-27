# Boop: harness evals

Updated 2026-09-28. How we check that Jev decides as Boop should: short
scenarios of agent work, run through the real core, harness and actions,
each pass checked against what it should come to. The harness is
[harness/HARNESS.md](harness/HARNESS.md), and the decisions checked are
[harness/DECISIONS.md](harness/DECISIONS.md).

## 1. What an eval is

A scenario is a few hook-level steps on a virtual clock. Each run starts
fresh: a new core, an empty transcript, and a `happy` mood in a
temporary state directory. The runner (`Eval` in
`internal/app/BoopDevKit/Eval/Eval.swift`) wires them as the app does,
with the real `mood` and `react` actions, except that a mumble's queue
goes nowhere and ends the reaction's handle at once, `done` unless the
step says otherwise (`reaction`, §3), so HISTORY shows it as played
([harness/DECISIONS.md](harness/DECISIONS.md) §5).

For each step it moves the clock a second at a time to the step's time,
ticking the core as the app does, so heartbeats and other timers fire on
the way. Then it feeds the step to the core, and hands every event from
the ticks and the step to the harness one at a time, straight through
without the queue (`Harness.respond`). The clock starts at a fixed
Wednesday 14:00 UTC and stands still while Jev answers.

| Step | Fed to the core as ([ADAPTERS.md](ADAPTERS.md) §1's common events) |
| --- | --- |
| `turn started` | `turn_start` |
| `command` | An `activity` starting a `Bash` call with the step's `topic`, then its result at the same moment: `failed` as given (default false), with `tool_error: exit_code` when it failed |
| `turn finished` | `turn_end` |
| `turn failed` | `turn_failed`, with the step's `error` (default `api_error`) |
| `pokes` | Four taps at once from the device: a poke streak |
| `wait` | Nothing; only time passes |

Every event is Claude's, in session `s1` of project `landing`, with the
step's `workspace` if it has one.

**The check.** A step with `expect` is checked against the last pass
woken on the way to it and by it, so a `wait` checks the heartbeat its
ticks brought. Each expectation is a set of acceptable values (`proud|happy`), so
a scenario holds wherever more than one answer is right:

| Checked | Against |
| --- | --- |
| `react` | Jev's pick for the `react` question: `none` or a mood's face |
| `word` | The word the mumble used ([DECISIONS.md](harness/DECISIONS.md) §5), or `none` when `react` didn't mumble |
| `loops` | How long the face held, Jev's `react.loops` pick (`once` to `four times`), or `none` when `react` didn't mumble |
| `mood` | Boop's mood after the pass |

A step fails if its pass was dropped (late, or an error), or if any
expectation doesn't hold. A step with `expect` that wakes no pass stops
the whole eval as broken. The evals ask Jev, so they need its key and
fail without it ([HARNESS.md](harness/HARNESS.md) §7).

## 2. Running them

```sh
BOOP_JEV_KEY=… make eval                     # every scenario, 3 runs each
.build/debug/boopdev eval --runs 1 --only tests
```

| Flag | Does |
| --- | --- |
| `--runs N` | Runs each scenario N times (default 3). It passes only if every run does |
| `--only TEXT` | Only the scenarios whose name contains TEXT (any case) or whose file name does |
| `--scenarios DIR`, `--steering DIR` | Other scenarios or steering files; by default the repo's, found from the working directory or from `boopdev`'s own place |

The report gives each scenario's verdict, with how many runs passed
(`2/3 runs`) when there's more than one, and each failing step once, with
what was wanted and what came. Then it gives how many scenarios passed in
every run, and the median and slowest latency against the pass's
deadline ([HARNESS.md](harness/HARNESS.md) §7). It exits 1 if any
scenario failed.
Every entry of every run goes to a file of its own in `/tmp/boop-eval`
(files over a day old are cleared), which `boopdev watch FILE` prints.

`EvalTests` checks the runner without Jev: every scenario file reads, a
scripted brain that answers as `04-tests-fight-back` wants passes it,
one that stays quiet fails `05-poke-streak` with the report saying why,
and a step's `reaction` shows in HISTORY as in progress or not having
happened.

## 3. The scenario file

One JSON file per scenario in `internal/app/Evals/scenarios/`, run in
file-name order:

```json
{
  "name": "Poked again and again, Boop is grumpy",
  "why": "PERSONALITY's Examples and the react question: being poked too much is grumpy, with 'nope'",
  "steps": [
    {"event": "pokes", "at": "0s", "expect": {"react": "grumpy", "word": "nope|ugh|none"}}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `name`, `why` | What it checks, and the spec or steering file that says so |
| `personality` | `boop` (the default) or `chatter` |
| `steps[].event` | One of the steps in §1 |
| `steps[].at` | Virtual time since the start, in `h`, `m` and `s`: `0s`, `2m30s`, `1h5m` |
| `steps[].topic`, `failed` | A command's topic and whether it failed |
| `steps[].error` | A failed turn's error class |
| `steps[].workspace` | The thread's workspace, when it has one |
| `steps[].reaction` | How a reaction this step's passes start ends: `done` (the default), `in progress` (HISTORY keeps saying so), or `failed: <why>` (HISTORY's `(didn't happen: <why>)`) |
| `steps[].expect` | Any of `react`, `word`, `loops` and `mood`, each a `\|`-separated list |

A file with an unknown event, personality or `expect` key, a bad `at` or
`reaction`, or no `expect` at all doesn't load, and the error names the
file and step.

## 4. The scenarios

All with the `boop` personality unless noted. Times are from the start.

| File | Feeds | Expects |
| --- | --- | --- |
| `01-short-turn` | A turn starts, and finishes at 8 s | At the start `react` none or curious; at the finish none or happy; `loops` none or once and `mood` happy at both |
| `02-long-turn` | A turn starts, and finishes at 20 min | At the finish `react` proud, happy or excited; `mood` happy or proud |
| `03-turn-failed` | A turn starts, and fails at 2 min (`rate_limit`) | `react` grumpy, none or curious; `word` none, oops, ugh or again; `mood` happy |
| `04-tests-fight-back` | In `fix-nav`: a turn starts; tests fail at 1, 3 and 5 min, and pass at 7 min | 1st failure: `react` none, curious, determined or grumpy, `mood` happy or determined. 2nd: the same. 3rd: `react` grumpy, `word` again, tests or ugh, `mood` grumpy. The pass: `react` proud, excited or happy, `word` finally, tests or yay, `mood` proud or happy ([harness/EXAMPLE.md](harness/EXAMPLE.md)) |
| `05-poke-streak` | A poke streak | `react` grumpy; `word` nope, ugh or none; `loops` once |
| `06-heartbeat-lets-grumpy-go` | A turn starts; tests fail at 1, 2 and 3 min; the turn fails at 4 min; nothing until 1 h 5 min, bringing the first heartbeat | After the 3rd failure `mood` grumpy. At the heartbeat `react` none, happy or curious, and `mood` happy |
| `07-chatter-reacts-to-everything` | `chatter`: a turn starts, a command with no topic at 4 s, the turn finishes at 8 s | `react` a face at every step: happy, excited, curious or proud at the start and the command; happy, excited or proud at the finish, with `loops` more than once |
| `08-long-turn-fails` | A turn starts, and fails at 25 min (`api_error`) | `react` sad, grumpy or none; `mood` sad |
| `09-failure-worked-through` | A turn starts; tests fail at 1 and 3 min, and pass at 5 min | After the 2nd failure `mood` determined. At the pass `react` proud, happy or excited; `word` finally, tests or yay; `loops` more than once; `mood` proud |
| `10-run-of-wins` | Four turns a minute apart, each with a passing test run at 30 s and a finish at 40 s | After the first turn `mood` happy; after the fourth, excited |
| `11-comeback-still-showing` | A turn starts; tests fail at 1 and 3 min, and pass at 5 min, whose reaction is still in progress when the turn finishes at 5 min 20 s | At the pass `react` proud, happy or excited; `word` finally, tests or yay. At the finish `react` none, happy or excited; `word` none, yay or tests: no second proud "finally" |
| `12-comeback-that-didnt-happen` | As `11`, but the pass's reaction didn't happen (`waited too long`) | At the pass `react` proud, happy or excited. At the finish `react` proud, happy or excited; `word` finally, tests or yay: made after all |

A new decision or a change to the steering files gets a scenario that
shows it, and `make eval` before it's committed.
