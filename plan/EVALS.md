# Boop: harness evals

Updated 2026-09-27. How we check that Jev decides as Boop should: short
scenarios of agent work, run through the real core, harness and actions,
each pass checked against what it should come to. The harness itself is
[harness/HARNESS.md](harness/HARNESS.md); the decisions checked are
[harness/DECISIONS.md](harness/DECISIONS.md).

## 1. What an eval is

A scenario is a few hook-level steps on a virtual clock: a turn starting
or finishing, a test command failing or passing, pokes, time passing.
Each step goes through a fresh core, which turns it into events
([harness/EVENTS.md](harness/EVENTS.md)); the harness asks Jev about every
event that wakes the brain; the real `mood` and `react` actions carry out
the answers. A step with an `expect` is then checked:

| Checked | Against |
| --- | --- |
| `react` | Jev's pick for the `react` question: `none` or a feeling |
| `word` | The word the mumble actually used ([DECISIONS.md](harness/DECISIONS.md) §5), or `none` |
| `mood` | Boop's mood after the pass, as the `mood` action left it |

Each is a list of acceptable values (`"proud|happy|excited"`), so a
scenario holds wherever more than one answer is right. A step that
expects something must wake the brain, or the scenario is broken. A pass
Jev drops (late, or an error) fails its step.

The evals ask Jev, so they need its key, and fail without it
([HARNESS.md](harness/HARNESS.md) §7).

## 2. Running them

```sh
BOOP_JEV_KEY=… make eval           # every scenario, 3 runs each
app/.build/debug/boopdev eval --runs 1 --only tests
```

A scenario passes only if every run does. The report gives each
scenario's verdict, each failing step with what was wanted and what came,
and the median and slowest latency against the 1.25 s deadline. Every
entry of every run goes to a file of its own in `/tmp/boop-eval`, which
`boopdev watch FILE` prints: each event, Jev's answers with their
probabilities, the first state in full, and what the actions did.

The runner is tested without Jev (`EvalTests`): a scripted brain that
answers as a scenario wants passes it, and one that stays quiet fails it
with the report saying why.

## 3. The scenario file

One JSON file per scenario in `app/Evals/scenarios/`:

```json
{
  "name": "Poked again and again, Boop is annoyed",
  "why": "PERSONALITY's Examples and the react question: being poked too much is annoyed, with 'nope'",
  "steps": [
    {"event": "pokes", "at": "0s", "expect": {"react": "annoyed", "word": "nope|ugh|none"}}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `name`, `why` | What it checks, and the spec that says so |
| `personality` | `boop` (the default) or `chatter` |
| `steps[].event` | `turn started`, `command`, `turn finished`, `turn failed`, `needs you`, `tap`, `pokes` or `wait` |
| `steps[].at` | Virtual time since the start: `0s`, `2m30s`, `1h5m`. Time passes a second at a time, so heartbeats and the core's timers fire on the way |
| `steps[].topic`, `failed` | A command's topic and whether it failed |
| `steps[].error` | A failed turn's error class |
| `steps[].agent`, `session`, `project`, `workspace` | The thread, when it isn't the default Claude one in `landing` |
| `steps[].expect` | `react`, `word` and `mood`, each a `|`-separated list |

## 4. The scenarios

| File | Checks |
| --- | --- |
| `01-short-turn` | A routine start and a short finish get no mumble |
| `02-long-turn` | A very long finish gets a proud or happy mumble |
| `03-turn-failed` | A failed turn is annoyed, or a cheerful shrug |
| `04-tests-fight-back` | The third failure in a row turns Boop grumpy with an annoyed word; the pass after it, past the 10-minute limit, turns it cheerful with "finally" ([harness/EXAMPLE.md](harness/EXAMPLE.md)) |
| `05-poke-streak` | A poke streak is annoyed |
| `06-heartbeat-lets-grumpy-go` | An hour of nothing lets grumpy go, without a mumble |
| `07-chatter-reacts-to-everything` | The `chatter` personality never stays quiet |

A new decision or a change to the steering files gets a scenario that
shows it, and `make eval` before it's committed.
