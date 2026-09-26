# Boop: harness evals

Updated 2026-09-26. Named scenarios for what the harness should do, how
they run, and what each one checks.

## 1. What they're for

The harness ([HARNESS.md](HARNESS.md)) turns what happens at your desk into
Boop's reactions: Stage 1 decides, Stage 2 writes any words, and the
actions carry it out. The evals pin that down as plain scenarios: "a turn
finishes after 12 minutes, so Boop mumbles proudly". Run them before and
after a harness change to see what it changed, and as a standing suite.

They stay at the highest level they can. A scenario gives events (agent
turns, taps, talk, time passing) and checks only what each pass through the
harness did: which calls ran, with the words written into them, and what
was dropped and why. Prompts, the transcript and other internals aren't
checked, so a scenario stays valid when the harness is restructured.

They're deterministic: a virtual clock, the rules classifier, no writer, a
fixed voice seed and a fresh copy of the sample memory for every scenario.
Where a scenario needs words, it scripts the writer. The same code gives
the same result every time.

## 2. Running them

```sh
make eval                                   # every scenario: rules classifier, no writer
app/.build/debug/boopdev eval --only shut   # scenarios whose name or file matches
app/.build/debug/boopdev eval --json FILE   # also write a report, to diff two runs
```

`boopdev eval` prints `pass` or `FAIL` for each scenario, then a diff of
each failed step, and exits 1 if any failed:

```
FAIL  05-bad-answer.json  A bad answer or a brain error is contained
  step 2 (720s turn finished)
    - agent finished → dropped (off menu)
    + agent finished → react(feeling: happy, voice: mumble), react(feeling: proud, voice: mumble)
```

`make test` runs the whole suite too (`EvalTests`), so a change that breaks
a scenario fails the unit tests. `--classifier jev` and `--writer apple`
run the same scenarios with real models, but they only pass reliably with
the deterministic defaults.

## 3. A scenario

A scenario is a JSON file in `app/Evals/scenarios/`: a name, a line saying
why (usually the spec it checks), and steps. Each step is an input event
and what it should lead to.

```json
{
  "name": "A long turn is celebrated, and an ultra-long one with a word",
  "why": "HARNESS.md §6: a finish of 15 seconds or more is react(proud, mumble); over a minute the writer is steered to always write its word",
  "steps": [
    {"input": {"at": "0s", "event": "turn started", "agent": "claude", "project": "jetpack"},
     "expect": ["agent started → nothing"]},
    {"input": {"at": "20s", "event": "turn finished", "agent": "claude", "project": "jetpack"},
     "expect": ["agent finished → react(feeling: proud, voice: mumble)"]},
    {"input": {"at": "1m", "event": "turn started", "agent": "claude", "project": "jetpack"},
     "expect": ["agent started → nothing"]},
    {"input": {"at": "4m", "event": "turn finished", "agent": "claude", "project": "jetpack"},
     "writer": {"react.word": "finally"},
     "expect": ["agent finished → react(feeling: proud, voice: mumble, word: finally)"]}
  ]
}
```

**Events** are what reaches the core, which decides what becomes an input
for the harness ([HARNESS.md](HARNESS.md) §2):

| `event` | Extra fields |
| --- | --- |
| `turn started`, `turn finished`, `turn failed` | `agent` (default `claude`), `project` (default `jetpack`), `error` for a failure |
| `command` | `topic` (`tests`, `build` or `deploy`), `failed` (default `false`), `agent`, `project`: an agent's shell command finished, as Claude's `PostToolUse` or `PostToolUseFailure` reports it. Never reaches the brain; the turn's finish shows what it did |
| `tap` | — (only noted in the transcript, unless it's the fourth of a poke streak) |
| `talk` | `words` (`""` for a yell with no words), `yelled` (default `false`) |
| `wait` | — (time passes; checks what the core releases on its own) |

`at` is the time since the scenario started (`500ms`, `90s`, `12m`, `2h`),
later for each step. A turn's length is the time from its start to its finish, so a
12-minute turn is a start at `0m` and a finish at `12m`.

**Scripted stages** (optional) replace a brain for the passes that step
produces. Use them for what the defaults would never do:

| Field | Value | The stage… |
| --- | --- | --- |
| `classifier` | `{"calls": [{"tool": "react", "feeling": "happy", "voice": "mumble"}]}` | decides these calls, with their decided arguments |
| `writer` | `{"react.word": "finally"}` | writes these values, by slot |
| either | `{"error": "…"}` | fails |
| either | `"refused"` | refuses (a guardrail) |
| either | `"late"` | misses its deadline |

**`expect`** lists every pass from the step's event up to the next step's
event, in order, and is compared exactly. After the last step the runner
waits 5 more seconds, so nothing is left unchecked. Because each step's
window runs to the next, a pass nobody expected always fails some step.

A pass is written `<input> → <what happened>`, with calls as they reached
their actions (arguments in alphabetical order):

| Written | Means |
| --- | --- |
| `agent finished → react(feeling: proud, voice: mumble, word: finally)` | The call ran, with the word the writer wrote |
| `you said → quiet(minutes: 30), react(feeling: sad, voice: silent)` | Both calls ran, in the menu's order |
| `agent started → nothing` | An input reached the harness and Stage 1 chose to do nothing |
| `you said → remember(where: today) dropped (unwritten)` | The writer left its required words empty, so the call was dropped |
| `… dropped (action)` | The call's action refused it (a memory rule, say) |
| `agent finished → dropped (off menu)` | The whole pass was dropped: `off menu`, `error`, `refused`, `late` or `cancelled` |
| `… · writer failed (error)` | Stage 2 failed (`error`, `refused` or `late`); the calls ran without their words |
| `[]` (an empty list) | No input reached the harness at all |

`[]` and `→ nothing` are different on purpose. The first means the core
held Boop back (quiet mode, something needing you, a tap); the second
means the classifier did.

## 4. How a scenario runs

Each scenario gets a fresh core, the real harness and the real actions,
with a copy of the sample memory (`app/Tests/Fixtures/memory/`) in a
temporary directory. The clock starts at 2026-10-14 14:00 UTC and moves a
second at a time between steps, ticking the core as the app does, so held
inputs come out when they would. Inputs go through the harness one at a
time, asides (a tap) go into its transcript, and the core's memory lines
(Happened, growth, a new day) are written to the memory copy, as the app
does.

Only the harness's passes are recorded. The core's own rule reactions (a
cheer, an oops, working chatter) aren't, so the evals stay about the
harness. Queue timing (what you say cancelling a running pass, a newer
input replacing a waiting one) is left to the unit tests in
`HarnessTests`.

## 5. The scenarios

| File | Checks |
| --- | --- |
| `01-short-turn.json` | Turns that finish in 8 and 12 seconds get nothing from the brain (under 15 s), since the core's cheer already celebrates them. |
| `02-long-turn.json` | A 20-second turn gets a proud mumble; a 3-minute one gets it with the word the writer writes (the writer is steered to always write one past a minute, which only `--writer apple` can show). Hero moment 1. |
| `03-turn-failed.json` | A failed turn gets an annoyed mumble. Hero moment 2. |
| `04-be-quiet.json` | "Be quiet for an hour" sets quiet mode for 60 minutes, holds back a turn in that time, and lets the next one through after; a yelled "be quiet" also gets a silent sad face. Hero moment 3. |
| `05-bad-answer.json` | A classifier answer off the menu and a classifier error each run nothing, and the next turn gets its normal reaction. |
| `06-tests-left-failing.json` | A turn whose last test run failed finishes failed and gets the annoyed mumble; one whose tests failed, then passed, is a normal finish. Hero moment 2. |
| `07-told-off.json` | "Shut up", "you're so annoying", a yell and a wordless yell each get a sad mumble and leave quiet mode off; "this build is annoying" doesn't count; a classifier that calls `quiet` anyway has it dropped. Hero moment 3. |
| `08-poke-streak.json` | Quick taps reach nothing until one completes a poke streak, which gets an annoyed mumble; a second streak soon after gets nothing from the brain, and one later does; slow taps never do. Hero moment 4. |

The hero moments are VISION.md's. Hero moment 1's cheer, 2's oops and 4's
side-eye are the core's own reactions, which the evals don't record; the
core's unit tests check those.

Adding a scenario means adding its file and its row here.
