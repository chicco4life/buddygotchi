# Boop: harness evals

Updated 2026-09-27. Named scenarios for what the harness should do in each
mode, how they run, and what each one checks.

## 1. What they're for

The harness ([HARNESS.md](HARNESS.md)) turns what happens at your desk
into Boop's reactions. The evals pin that down as plain scenarios, like
"a turn fails, so Boop mumbles, annoyed", and show what a harness change
changed. A scenario gives events (agent turns, taps, talk, time passing)
and checks only what each pass through the harness did: which calls ran,
with the words written into them, and what was dropped and why. Prompts
and the transcript aren't checked, so a scenario survives the harness
being restructured. Each one runs once per mode, and its file shows
chatty, normal and calm side by side.

The same scenarios hold for every brain: where the spec leaves a value to
judgment, like a model's word or the feeling for small talk, the scenario
lists every value that fits (§3). By default every mode is deterministic,
with the mode's if-else table and no writer, so the words aren't checked;
with Apple's model they are. Normal's lines are its table's, which Jev is
steered toward, so the same lines check Jev live.

## 2. Running them

```sh
make eval                                     # every scenario in every mode: if-else tables, no writer
make eval REAL=1                              # the real brains, 3 runs each, then a report
app/.build/debug/boopdev eval --mode calm     # one mode
app/.build/debug/boopdev eval --only told     # scenarios whose name or file contains "told"
app/.build/debug/boopdev eval --json FILE     # also write a report, to diff two runs
app/.build/debug/boopdev watch FILE           # every pass of a run, readably
```

`boopdev` with no arguments lists every flag. A run prints `pass` or
`FAIL` for each scenario in each mode, then a summary, and exits 1 if any
failed. For a failed step it prints the expected passes (`-`) and the
actual ones (`+`), with how Stage 1 got to each (the rule that matched,
or Jev's answers) and what the writer answered. Every pass also goes to
the run's own file in `/tmp/boop-eval`, named at the start and the end
([HARNESS.md](HARNESS.md) §8); files over a day old are cleared away.
Here normal's lines run against the chatty table, which mumbles at a
start (`boopdev eval --mode normal --classifier chatty --only 03`):

```
every pass goes to /tmp/boop-eval/20260927-100034-60176.jsonl
FAIL  normal  03-turn-failed.json  A failed turn gets an annoyed mumble in every mode
  step 1 (0s turn started)
    - agent started → nothing
    + agent started → react(feeling: curious)
        because: agent started
0/1 passed: normal chatty@1 + none
every pass: boopdev watch /tmp/boop-eval/20260927-100034-60176.jsonl
```

`make test` runs the same suite (`EvalTests`), and also checks each
mode's character across every scenario: in chatty every agent input and
poke streak gets a mumble, in normal a start never does, and in calm the
brain mumbles only at a failed turn or when you talk to it, and the rules
never chatter.

`make eval REAL=1` (`boopdev eval --real`) runs every mode with the brains
the app would use: Apple's model writes, and normal decides with Jev
alone (no table behind it) when `BOOP_JEV_KEY` is set, or with its table,
saying so, when it isn't. Each scenario runs 3 times (`--runs`) and passes
only if every run does. Then, leaving out steps that script a stage, it
reports refusals, how many passes Stage 1 answered on the menu, the
writer's slots filled and its failures, the calls actions dropped and
why, and for each kind of input the p50 latency of each stage and the p95
of the whole pass against its deadline. It exits 1 unless every scenario
passed and that report holds ([VERIFICATION.md](VERIFICATION.md) L5). Run
it after changing `steering.md`, a definition's questions or a brain's
prompt. `--classifier` runs any mode's lines with another classifier
(`jev` needs `BOOP_JEV_KEY`), and `--writer apple` adds Apple's writer to
a run with the if-else tables.

## 3. A scenario

A scenario is a JSON file in `app/Evals/scenarios/`: a name, a line
saying why (usually the spec it checks), and steps. Each step is an input
event and what it should lead to in each mode. `03-turn-failed.json`:

```json
{
  "name": "A failed turn gets an annoyed mumble in every mode",
  "why": "BEHAVIORS.md §6 and HARNESS.md §6: a failed finish is react(annoyed), in calm too, where it's the one alert besides needs you; with no topic, its word is an annoyed one, or bug for a turn that broke (steering.md, Writing; VOICE.md §6)",
  "steps": [
    {"input": {"at": "0m", "event": "turn started", "agent": "claude", "project": "landing"},
     "expect": {"chatty": ["agent started → react(feeling: curious, word: hmm|what|oh|okay|code|more|wow|hi|none)"],
                "normal": ["agent started → nothing"],
                "calm": ["agent started → nothing"]}},
    {"input": {"at": "2m", "event": "turn failed", "agent": "claude", "project": "landing", "error": "rate_limit"},
     "expect": ["agent finished → react(feeling: annoyed, word: ugh|nope|oops|no|boo|again|what|bug|none)"]}
  ]
}
```

**`expect`** is one list when every mode should do the same, or a list
for each mode the scenario runs in. **`modes`** (optional) narrows which
modes it runs in, each from the start; by default all three. **`rules`**
(optional, `true`) also records the core's own rule reactions, so a
scenario can check a cheer or working chatter: `rules → cheer`,
`rules → mumble(feeling: curious, word: tests)`.

**Events** are what reaches the core, which decides what becomes an
input for the harness ([HARNESS.md](HARNESS.md) §2):

| `event` | Extra fields |
| --- | --- |
| `turn started`, `turn finished`, `turn failed` | `agent` (default `claude`), `project` (default `jetpack`), `session` (default `claude-jetpack`, from the agent and project), `error` for a failure |
| `command` | `topic` (`tests`, `build` or `deploy`), `failed` (default `false`), `agent`, `project`, `session`: a shell command finished, as Claude's `PostToolUse` or `PostToolUseFailure` reports it. It never reaches the brain, but the turn's finish shows its result |
| `needs you` | `agent`, `project`, `session`: an approval request, as Claude's `PermissionRequest` reports it. The session's next event (a `command`, say) is its answer |
| `tap` | — (only noted in the transcript, unless it completes a poke streak) |
| `talk` | `words` (`""` for a wordless yell), `yelled` (default `false`) |
| `mode` | `mode` (`chatty`, `normal` or `calm`): a new mode, applied at once, as in the app |
| `wait` | — (time passes, to check what the core releases on its own) |

`at` is the time since the scenario started (`500ms`, `90s`, `12m`,
`2h`), later for each step. A 12-minute turn is a start at `0m` and a
finish at `12m`.

**Scripted stages** (optional) replace a brain for the passes a step
produces, whatever brains the run uses. Use them for what no brain should
do (an answer off the menu, an error, lateness), not for words: a
scripted word would stand in for the writer the run is meant to check.

| Field | Value | The stage… |
| --- | --- | --- |
| `classifier` | `{"calls": [{"tool": "react", "feeling": "happy"}]}` | decides these calls, with their decided arguments |
| `writer` | `{"react.word": "finally"}` | writes these values, by slot |
| either | `{"error": "…"}` | fails |
| either | `"refused"` | refuses (a guardrail) |
| either | `"late"` | misses its deadline |

**`expect`** lists every pass from the step's event up to the next
step's, in order, and is compared exactly, so a pass nobody expected
always fails some step. After the last step the runner waits 5 more
seconds, so nothing held back goes unchecked. A pass is written
`<input> → <what happened>`, with calls as they reached their actions:

| Written | Means |
| --- | --- |
| `agent finished → react(feeling: proud, word: finally)` | The call ran, with the word the writer wrote |
| `you said → react(feeling: happy, word: okay), remember(text: "demo on Thursday", where: today)` | Both calls ran, in the menu's order |
| `agent started → nothing` | An input reached the harness and Stage 1 chose to do nothing |
| `[]` (an empty list) | No input reached the harness at all |
| `rules → cheer` | The core played a rule moment (only with `"rules": true`) |
| `you said → remember(where: today) dropped (unwritten)` | The writer left its required words empty, so the call was dropped |
| `… dropped (action)` | The call's action refused it (quiet mode, say, or a memory rule) |
| `agent finished → dropped (off menu)` | The whole pass was dropped: `off menu`, `error`, `refused`, `late` or `cancelled` |
| `… · writer failed (error)` | Stage 2 failed (`error`, `refused` or `late`); the calls ran without their words |

`[]` and `→ nothing` differ on purpose: the first means the core held
Boop back (quiet mode, something needing you, a tap), the second that the
classifier did.

**Values that fit.** An argument may list every value that fits, split by
`|`: `word: finally|done|yay`. `none` among them lets the argument be
left out, and `*` stands for any run of characters, matched without
regard to case: `text: "*demo*Thursday*"`. Arguments may come in any
order, and one the line doesn't mention must be absent.

List every value the spec allows, not the ones a model happened to pick:
for a word, every word `steering.md`'s Writing would accept, leaving
`none` out where it says always (a very long turn's word). Keep decided
arguments exact where the spec is (a failed turn is annoyed), and list
alternatives only where it leaves the choice to the classifier, like the
feeling for small talk. With no writer, the writer's arguments aren't
checked, and a call that needs one (a memory line) is expected dropped
(unwritten), as the harness drops it, so one line holds for both.

## 4. How a scenario runs

Each run of a scenario gets a fresh core and harness in its mode, the
real actions, a fixed voice seed, and a copy of the sample memory
(`app/Tests/Fixtures/memory/`) in a temporary directory. The clock starts
at 2026-10-14 14:00 UTC and moves a second at a time between steps,
ticking the core as the app does, so held inputs come out when they
would. Inputs go through the harness
one at a time, asides (a tap) go into its transcript, and the core's
memory lines (Happened, a new day) are written to the memory copy.

Only the harness's passes are recorded, plus the core's rule moments and
chatter when a scenario asks (`"rules": true`), so the evals stay about
the harness. Queue timing (what you say cancelling a running pass, a
newer input replacing a waiting one) is left to `HarnessTests`.

## 5. The scenarios

| File | Checks |
| --- | --- |
| `01-short-turn.json` | Turns of 8 and 12 seconds: chatty mumbles at each start (curious) and finish (happy); normal leaves them to the core's cheer; calm has neither cheer nor mumble. Records the cheer. |
| `02-long-turn.json` | A 20-second turn gets a proud mumble in chatty and normal; a 3-minute one gets an excited (chatty) or proud (normal) mumble, always with a word. Calm: nothing. Hero moment 1. |
| `03-turn-failed.json` | A failed turn gets an annoyed mumble in every mode, with an annoyed word, `bug`, or none. Hero moment 2. |
| `04-be-quiet.json` | "Be quiet for an hour" is quiet(60) in every mode: a turn in that hour is held back, and the next one gets through. A yelled "BE QUIET" is just quiet(30), not a sad mumble, and "you can talk again" ends it at once with a happy mumble, so the next turn reaches the brain. VISION's "goes quiet when asked". |
| `05-bad-answer.json` | A classifier answer off the menu, and a classifier error, each drop their pass, and the next turn gets its mode's reaction. |
| `06-tests-left-failing.json` | A turn whose last test run failed finishes failed: the annoyed mumble in every mode, with `tests` or `ugh`. One whose tests failed and then passed is a normal finish. Hero moment 2. |
| `07-told-off.json` | "Shut up", "you're so annoying", a yell and a wordless yell each get a sad mumble (nothing in calm) and never quiet mode; "this build is annoying" doesn't count; a yelled "GOOD JOB!" is still praise; a classifier that calls `quiet` anyway has its pass dropped, since `quiet` isn't on the menu. Hero moment 3. |
| `08-poke-streak.json` | Quick taps reach nothing until the fourth completes a poke streak: an annoyed mumble in chatty and normal, nothing in calm. A second streak right after doesn't reach the brain, one a minute later does, and slow taps never do. Hero moment 4. |
| `09-remember.json` | "Remember the demo is on Thursday" is kept for today, a lasting fact about you in About you, and how you like things in Preferences; a fact naming someone else stays today's, but one said to Boop by name ("Hey Pip, …") doesn't; "good job today" gets a proud mumble and no note. |
| `10-small-talk.json` | "Hello boop", "time for lunch" and "see you tomorrow" get the word each calls for, in every mode: `hi`, `food`, `bye`. |
| `11-mode-switch.json` | Switching between chatty and calm mid-turn changes the next reaction and the core's cheer at once. |
| `12-chatter.json` | A 10-minute turn: the core chatters 8 times in chatty, twice in normal and never in calm, at the mode's pace ([BEHAVIORS.md](BEHAVIORS.md) §6), and cheers the finish in every mode. |
| `13-no-cheer-for-a-failure.json` | A turn that leaves its tests failing, and one that stops on an API error, get the annoyed mumble and no cheer; a 30-second turn cheers in chatty and normal but not in calm. Records the cheer. Hero moment 2. |
| `14-quiet-fifteen.json` | "Be quiet for fifteen minutes" is quiet(15): talk still reaches the brain but its mumble is dropped, agent inputs don't reach it, and after 15 minutes they do again. A classifier that answers quiet the wrong way (30 for "you can talk again", 0 for "be quiet") has that call dropped, so the 15 minutes hold. |
| `15-needs-you.json` | While one session needs you, another's finish and a poke streak don't reach the brain, and a reply to talk is dropped; once the first carries on (its next command is the answer), its finish gets the mode's reaction. |

The hero moments are [VISION.md](VISION.md)'s. The first is the core's
own cheer, which `01`, `11`, `12` and `13` record; the others are the
brain's mumbles.

Adding a scenario means adding its file and its row here.
