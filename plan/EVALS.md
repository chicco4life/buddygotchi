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
the way, and hands each tick's events to the harness at that tick, so a
heartbeat is answered when it comes. Then it feeds the step to the core,
and hands its events to the harness one at a time, straight through
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

Every event is Claude's, in project `landing`, in session `s1` or the
step's `session`, with the step's `workspace` if it has one.

**The check.** A step with `expect` is checked against the last pass
woken on the way to it and by it, so a `wait` checks the heartbeat its
ticks brought: an idle one, or while a thread works, the working
heartbeat ([harness/EVENTS.md](harness/EVENTS.md) §4). Each expectation is a set of acceptable values (`proud|happy`), so
a scenario holds wherever more than one answer is right:

| Checked | Against |
| --- | --- |
| `react` | Jev's pick for the `react.mood` question: `none` or a mood's face |
| `animation` | The animation the reaction played, Jev's `react.animation` pick (`cheer`), or `none` when it played none or Boop didn't react |
| `word` | The word the mumble used ([DECISIONS.md](harness/DECISIONS.md) §5), or `none` when `react` didn't mumble |
| `loops` | How long the face held, Jev's `react.loops` pick (`once` to `four times`), or `none` when `react` didn't mumble |
| `mood` | Boop's mood after the pass |

A step fails if its pass was dropped (late, or an error), or if any
expectation doesn't hold. A step with `expect` that wakes no pass stops
the whole eval as broken. The evals ask Jev, so they need its key and
fail without it ([HARNESS.md](harness/HARNESS.md) §7).

**The whole-run checks.** A scenario's `checks` are judged over every
pass of a run, checked or not, for how lively Boop stays (the owner's
brief of 2026-09-28: an animated Boop that doesn't sit on one look,
repeat itself or flail). Each is loose, there to catch a clear failure,
and to be tightened once Boop meets it (`Eval.judge`):

| Check | Fails when |
| --- | --- |
| `max_quiet_working` | The turn runs longer than this with no reaction played, counted from its start or the last reaction to the next or its end |
| `max_same_in_a_row` | More reactions than this in a row are the same face, animation and word (however long each held) |
| `mood_changes` | The mood changes a number of times outside this range (`1-3`, `2-` for 2 or more, `-2` for 2 at most) |
| `no_mood_bounce_within` | A mood changes back to the one it just left sooner than this |
| `reactions` | The run plays a number of reactions outside this range |
| `min_variety` | The run plays fewer different reactions (face, animation and word) than this |

**Always and gaps.** An `always` scenario is Boop's character, not a
tuning target: it runs 5 times by default, and every steering change
keeps it passing. A scenario with a `gap` is one Boop can't pass today,
with why and what would fix it: its failures are reported as `GAP` and
don't fail the eval, and when it passes in every run the report says to
take the gap out.

## 2. Running them

```sh
BOOP_JEV_KEY=… make eval                     # every scenario: 5 runs each for always, 3 for the rest
BOOP_JEV_KEY=… .build/debug/boopdev eval --always
.build/debug/boopdev eval --runs 1 --only tests --timeline
.build/debug/boopdev eval --list             # every scenario's case; no key needed
```

| Flag | Does |
| --- | --- |
| `--runs N` | Runs each scenario N times (default 5 for an `always` scenario, 3 for the rest). It passes only if every run does |
| `--only TEXT` | Only the scenarios whose name contains TEXT (any case) or whose file name does |
| `--always` | Only the `always` scenarios |
| `--timeline` | Prints every pass of every run: when, the line, what Boop did and the mood after |
| `--list` | Prints each scenario's file, name, case, and whether it's `always` or a known gap, and runs nothing |
| `--scenarios DIR`, `--steering DIR` | Other scenarios or steering files; by default the repo's, found from the working directory or from `boopdev`'s own place |

The report gives each scenario's verdict (`pass`, `FAIL`, or `GAP` for a
known gap), with how many runs passed (`2/3 runs`) when there's more than
one; for one that failed, its gap and case, then each failing step and
whole-run check once, with what was wanted and what came. Then it gives
how many scenarios passed in every run, and how many known gaps failed, and the median and slowest latency against the pass's
deadline ([HARNESS.md](harness/HARNESS.md) §7). It exits 1 if any
scenario failed that isn't a known gap.
Every entry of every run goes to a file of its own in `/tmp/boop-eval`
(files over a day old are cleared), which `boopdev watch FILE` prints.

`EvalTests` checks the runner without Jev: every scenario file reads and
has a case, a scripted brain that answers as `04-tests-fight-back` wants
passes it, one that stays quiet fails `05-poke-streak` with the report
saying why, a step's `reaction` shows in HISTORY as in progress, or not
at all when it didn't happen, and each whole-run check catches what it
should.

## 3. The scenario file

One JSON file per scenario in `internal/app/Evals/scenarios/`, run in
file-name order:

`05-poke-streak.json`:

```json
{
  "name": "A poke streak makes Boop grumpy, briefly",
  "case": "The person pokes Boop again and again. Boop gets angry right away: a grumpy face, held briefly, with 'nope', 'ugh' or no word, and its mood turns grumpy. Three minutes later, when the agent starts a new turn, it has calmed down to happy and doesn't react to the start with anything but a happy face.",
  "always": true,
  "why": "PERSONALITY's Examples and the react question: being poked too much is grumpy, with 'nope', held once. plan/steering/mood/happy.md: a poke streak makes Boop grumpy, and plan/steering/mood/grumpy.md: grumpy goes back to happy 2 minutes after the change",
  "steps": [
    {"event": "pokes", "at": "0s", "expect": {"react": "grumpy", "word": "nope|ugh|none", "loops": "once", "mood": "grumpy"}},
    {"event": "turn started", "at": "3m", "expect": {"react": "none|happy", "mood": "happy"}}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `name` | What it checks, in a line |
| `case` | The situation and what Boop should do in it, in plain words and no harness terms, so the steps can be rewritten to fit it when the harness changes. Required |
| `why` | The spec or steering file that says so |
| `always` | `true` for Boop's character (§1): 5 runs by default, and `--always` runs these |
| `gap` | A known gap (§1): why Boop can't pass it today, and what would fix it. Never on an `always` scenario |
| `checks` | Whole-run checks (§1), any of `max_quiet_working` and `no_mood_bounce_within` (times, like `6m`), `max_same_in_a_row` and `min_variety` (counts), `mood_changes` and `reactions` (ranges, like `1-3`) |
| `personality` | `boop` (the default) or `chatter` |
| `steps[].event` | One of the steps in §1 |
| `steps[].at` | Virtual time since the start, in `h`, `m` and `s`: `0s`, `2m30s`, `1h5m` |
| `steps[].topic`, `failed` | A command's topic and whether it failed |
| `steps[].error` | A failed turn's error class |
| `steps[].workspace` | The thread's workspace, when it has one |
| `steps[].session` | Claude's session, `s1` unless it says: another session is another thread, working at the same time |
| `steps[].reaction` | How a reaction this step's passes start ends: `done` (the default), `in progress` (HISTORY keeps saying so), or `failed: <why>` (HISTORY leaves it out) |
| `steps[].expect` | Any of `react`, `animation`, `word`, `loops` and `mood`, each a `\|`-separated list |

A file with no `case`, an unknown key, event, personality, `expect` key
or check, a bad `at`, `reaction` or check value, or nothing to check (no
`expect` and no `checks`) doesn't load, and the error names the file and
step.

## 4. The scenarios

Each scenario's file says what it checks, in its `case`, so the list
lives there: `boopdev eval --list` prints them all. They come in three
kinds, all with the `boop` personality unless the file says otherwise:

- **Always** (`02`–`06`, `08`, `09`, `13`, `16`, `17`): Boop's
  character. A failed check makes it determined and the fix proud; a
  failed turn grumpy, a very long one failed sad; a very long turn done
  cheers; poking it again and again keeps it grumpy while it goes on,
  and it calms down after; moods fade back to happy; and no face ever
  contradicts what happened.
- **Tuning** (`01`, `07`, `10`–`12`, `14`, `15`, `18`, `19`, `21`,
  `22`): single decisions, and the liveliness brief: Boop reacts often
  (every quick win, `19`; most of a busy half hour, `21`), never goes
  over 6 minutes of work with no reaction, even while another thread's
  quick turns keep waking the brain (`18`, `21`, `22`), and its mood
  drifts (happy → determined → excited) without bouncing. Repeats are
  fine.
- **Known gaps** (`20`): flipping tests don't flip the mood. Its `gap`
  says why the steering can't get there alone.

A new decision or a change to the steering files gets a scenario that
shows it, and `make eval` before it's committed.

## 5. The working day

The scenarios check single decisions; the working day checks how they
add up over a day: how often Boop's mood changes, whether a routine
line changes it, and how often, and with which faces, Boop reacts.
`internal/tools/workday/workday.py` replays a scripted 8-hour day
through the whole headless app and Jev on a compressed clock, in about
five minutes:

```sh
make build
BOOP_JEV_KEY=… python3 internal/tools/workday/workday.py run --state /tmp/tn-1 --out /tmp/tn-out/1
python3 internal/tools/workday/workday.py report /tmp/tn-out/1/debug.jsonl /tmp/tn-out/2/debug.jsonl
python3 internal/tools/workday/workday.py check /tmp/tn-out/1/debug.jsonl
python3 internal/tools/workday/workday.py plan    # the day's story
```

**The day** (`--seed 1` by default; the seed only moves lengths and
gaps) runs from 09:00 to about 17:40: about 190 turns on four threads
(Claude on `api`, and on `fix-nav` and `docs` in `landing`; Codex on
`boop`), mostly routine turns of seconds to a few minutes, with two
approvals; tests failing three times, then passing, in a 9-minute turn;
a turn failing on a rate limit; a 22-minute turn whose build fails once
and comes back; a stopped turn; lunch, over an hour with nothing, for
the heartbeat; a build failing twice, then passing; a poke streak, and
later two a minute and a half apart; a 14-minute turn ending with its
tests still failing, and the next turn fixing them; a coffee break; an
hour of quick wins with an API error and a passing deploy; and a
16-minute docs turn. An hour of nothing after it brings the evening's
heartbeat.

**The run** starts `Boop --headless --brain jev --debug` with a fresh
state directory and a fake device on a Unix socket (`--link usb:`) that
says each of the brain's moments played to the end, so HISTORY reads as
it would with a board, and whose taps make the poke streaks. It moves
the app's clock to 09:00 the next morning, sends each hook line straight
to the app's socket in `boop-hook`'s wire form, moves the clock between
them with `{"dev":"advance"}` (a minute at a time over a long gap, so the
heartbeat comes when it would), and waits for every pass and reaction to
end before the next line, so no event waits behind Jev. `--brain
scripted` runs it without a key, and `--personality chatter` with the
other text.

**The report** gives, for each hour of the app's clock: turns ended,
passes (and how many dropped), mood changes, with those on a routine
line (a turn start, or a finish done under 5 minutes) split into back
to happy (a mood fading, as the guide says) and any other (which a
routine line shouldn't cause); and reactions, as reacted/all for each
kind of line that woke the brain: notable (a failure, a fix, a failed or
stopped turn, a turn of 5 minutes or more, a poke streak), a finish
done in 1 to 5 minutes, one under a minute, a turn start, and a
heartbeat; and the faces used. Then the words the reactions mumbled over
the day (`none` for a mumble with no real word), how long each mood
lasted, and every mood change with the line that brought it. `--json`
gives all that and every reaction.

**Liveliness.** The report also gives, for the day: the longest stretch
of work (any agent in a turn) with no reaction, and how many went over
6 minutes; reactions per turn ended; how many reactions were the same
as the one before, and the longest run of the same (reported, with no
limit: repeats are fine); mood bounces (a mood changing back to the one
it left within a minute); and the longest stretch of work with Boop
happy all through. `workday.py check FILE…` holds each run to loose
limits (`LIMITS` in `workday.py`) and exits 1 if one fails:

| Limit | Holds |
| --- | --- |
| `longest_quiet_min` | 8 at most |
| `quiet_over_6_min` | 3 at most |
| `min_reactions_per_turn` | 0.8 at least (reactions over turns ended) |
| `mood_bounces` | 1 at most |
| `min_mood_changes` | 10 at least |
| `longest_happy_working_min` | 45 at most |

```sh
python3 internal/tools/workday/workday.py check /tmp/tn-out/1/debug.jsonl
```

Jev is stochastic, so run each side of a change at least twice. Warm it
up on new steering first (a `boopdev eval --runs 1`): its first passes
on text it hasn't seen could go over the deadline, then 1.25 s, and drop, 13 and
19 of the first 30 in the runs of
[2026-09-28](evidence/2026-09-28-tonight/tune/README.md), which has the
numbers the mood is tuned to today; the reactions' are in
[the second pass](evidence/2026-09-28-tonight/tune2/README.md) and
[its check](evidence/2026-09-28-tonight/tune2-check/README.md). A few can drop in a run that is
warm too (2 and 8 in [the check's reruns](evidence/2026-09-28-tonight/tune-check/README.md)),
so compare runs by their dropped passes as well.

`internal/tools/workday/tests/` checks the day and the report without
the app (`make -C internal tools-test`).
