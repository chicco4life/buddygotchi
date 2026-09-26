# Boop: harness evals

Updated 2026-09-27. Named scenarios for what the harness should do in each
mode, how they run, and what each one checks.

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

Each scenario runs once per mode ([BEHAVIORS.md](BEHAVIORS.md) §6), and
says what should happen in each: one file shows chatty, normal and calm
side by side for the same events.

The same scenarios hold for every brain. Where the spec leaves a value to
judgment, a scenario lists every value that fits (§3): a word a model may
write, or a feeling for small talk. Every mode is deterministic by
default: a virtual clock, the mode's if-else table, no writer, a fixed
voice seed and a fresh copy of the sample memory for every scenario, so the
same code gives the same result every time. With no writer, the words
aren't checked; with Apple's model they are, which is the point of running
it. Normal's expectations are its if-else table's, which Jev is steered
toward, so the same lines check Jev live with its key.

## 2. Running them

```sh
make eval                                                  # every scenario in every mode, no writer
app/.build/debug/boopdev eval --mode calm                  # one mode
app/.build/debug/boopdev eval --only told                  # scenarios whose name or file matches
app/.build/debug/boopdev eval --json FILE                  # also write a report, to diff two runs
app/.build/debug/boopdev eval --writer apple --runs 5      # Apple's model writes; every run must pass
BOOP_JEV_KEY=… app/.build/debug/boopdev eval --mode normal --classifier jev --writer apple --runs 3   # Jev decides
```

`boopdev eval` prints `pass` or `FAIL` for each scenario in each mode, then
a diff of each failed step, with how Stage 1 got to each pass (the rule
that matched, or Jev's answers), and exits 1 if any failed. Normal's
expectations run against the chatty table
(`boopdev eval --mode normal --classifier chatty --only 03`):

```
FAIL  normal  03-turn-failed.json  A failed turn gets an annoyed mumble in every mode
  step 1 (0s turn started)
    - agent started → nothing
    + agent started → react(feeling: curious, voice: mumble)
        because: agent started
0/1 passed: normal chatty@1 + none
```

`make test` runs the same suite too (`EvalTests`), so a change that breaks
a scenario fails the unit tests. It also checks each mode's character
across every scenario: in chatty, every agent input and poke streak gets a
mumble; in normal, a start never does; in calm, the brain mumbles only at
a failed turn or when you talk to it, and the rules never chatter.

With a model, `--runs N` runs each scenario N times and passes it only if
every run does, since a model can answer differently from one run to the
next. Run the suite this way after changing `steering.md`, a definition's
questions or a brain's prompt: every mode with Apple's model
(`--writer apple`), and normal with Jev too (`--classifier jev`, its key
in `BOOP_JEV_KEY`). `--classifier` runs any mode's scenarios with another
classifier, for comparison.

## 3. A scenario

A scenario is a JSON file in `app/Evals/scenarios/`: a name, a line saying
why (usually the spec it checks), and steps. Each step is an input event
and what it should lead to, in each mode. From `03-turn-failed.json`:

```json
{

  "name": "A failed turn gets an annoyed mumble in every mode",
  "why": "HARNESS.md §6: a failed finish is react(annoyed, mumble), in calm too, where it's the one alert besides needs you; with no topic, its word is an annoyed one, or bug for a turn that broke (steering.md, Writing; VOICE.md §6)",
  "steps": [
    {"input": {"at": "0m", "event": "turn started", "agent": "claude", "project": "landing"},
     "expect": {"chatty": ["agent started → react(feeling: curious, voice: mumble, word: hmm|what|oh|okay|code|more|wow|hi|none)"],
                "normal": ["agent started → nothing"],
                "calm": ["agent started → nothing"]}},
    {"input": {"at": "2m", "event": "turn failed", "agent": "claude", "project": "landing", "error": "rate_limit"},
     "expect": ["agent finished → react(feeling: annoyed, voice: mumble, word: ugh|nope|oops|no|boo|again|what|bug|none)"]}
  ]
}
```

**`expect`** is a list when every mode should do the same, or one list for
each mode the scenario runs in. **`modes`** (optional) narrows which modes
it runs in, each from the start; by default all three. **`rules`**
(optional, `true`) also records the core's own rule reactions, so a
scenario can check a cheer or working chatter: `rules → cheer`,
`rules → mumble(feeling: curious, word: tests)`.

**Events** are what reaches the core, which decides what becomes an input
for the harness ([HARNESS.md](HARNESS.md) §2):

| `event` | Extra fields |
| --- | --- |
| `turn started`, `turn finished`, `turn failed` | `agent` (default `claude`), `project` (default `jetpack`), `error` for a failure |
| `command` | `topic` (`tests`, `build` or `deploy`), `failed` (default `false`), `agent`, `project`: an agent's shell command finished, as Claude's `PostToolUse` or `PostToolUseFailure` reports it. Never reaches the brain; the turn's finish shows what it did |
| `tap` | — (only noted in the transcript, unless it's the fourth of a poke streak) |
| `talk` | `words` (`""` for a yell with no words), `yelled` (default `false`) |
| `mode` | `mode` (`chatty`, `normal` or `calm`): the person picks a new mode, which applies at once, as in the app |
| `wait` | — (time passes; checks what the core releases on its own) |

`at` is the time since the scenario started (`500ms`, `90s`, `12m`, `2h`),
later for each step. A turn's length is the time from its start to its finish, so a
12-minute turn is a start at `0m` and a finish at `12m`.

**Scripted stages** (optional) replace a brain for the passes that step
produces, whatever brains the run uses. Use them for what no brain should
do (an answer off the menu, an error, lateness), not for words: a scripted
word would stand in for the writer the run is meant to check.

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
their actions:

| Written | Means |
| --- | --- |
| `agent finished → react(feeling: proud, voice: mumble, word: finally)` | The call ran, with the word the writer wrote |
| `rules → cheer` | The core played a rule moment (only with `"rules": true`) |
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

**Values that fit.** An argument's value may list every value that fits,
split by `|`: `word: finally|done|yay`. `none` among them lets the
argument be left out, and `*` stands for any run of characters, matched
without regard to case: `text: "*demo*Thursday*"`. Arguments may come in
any order, and one the line doesn't mention must be absent.

- List every value the spec allows, not the ones a model happened to pick:
  for a word, every word `steering.md`'s Writing would accept for the case
  (a failed test run's word is `tests`; a sad mumble's is any sad word, or
  none). Leave `none` out where the spec says always (a very long turn's
  word).
- Decided arguments stay exact where the spec is (a hero moment's
  feeling); list alternatives only where it leaves the choice to the
  classifier, like the feeling for small talk.
- **With no writer** (the default run), the writer's arguments aren't
  checked, and a call that needs one (a memory line) is expected dropped
  (unwritten), as the harness drops it. So one line holds for both.

## 4. How a scenario runs

Each run of a scenario gets a fresh core and harness in its mode, the real
actions, and a copy of the sample memory (`app/Tests/Fixtures/memory/`) in a
temporary directory. The clock starts at 2026-10-14 14:00 UTC and moves a
second at a time between steps, ticking the core as the app does, so held
inputs come out when they would. Inputs go through the harness one at a
time, asides (a tap) go into its transcript, and the core's memory lines
(Happened, growth, a new day) are written to the memory copy, as the app
does.

Only the harness's passes are recorded, unless the scenario asks for the
core's rule moments and chatter too (`"rules": true`), so the evals stay
about the harness. Queue timing (what you say cancelling a running pass, a newer
input replacing a waiting one) is left to the unit tests in
`HarnessTests`.

## 5. The scenarios

| File | Checks |
| --- | --- |
| `01-short-turn.json` | Turns of 8 and 12 seconds (short turns): chatty mumbles at each start (curious) and finish (happy); normal leaves them to the core's cheer; calm has no cheer and no mumble. Records the cheer. |
| `02-long-turn.json` | A 20-second turn (long) gets a proud mumble in chatty and normal; a 3-minute one (very long) gets an excited (chatty) or proud (normal) mumble with a word that fits, always (`steering.md`, Writing). Calm: nothing. Hero moment 1. |
| `03-turn-failed.json` | A failed turn gets an annoyed mumble in every mode, with an annoyed word, bug, or none. Hero moment 2. |
| `04-be-quiet.json` | "Be quiet for an hour" sets quiet mode for 60 minutes in every mode, holds back a turn in that time, and lets the next one through after; a yelled "be quiet" also gets a silent sad `react`, which shows nothing in v1. Hero moment 3. |
| `05-bad-answer.json` | A classifier answer off the menu and a classifier error each run nothing, and the next turn gets its mode's reaction. |
| `06-tests-left-failing.json` | A turn whose last test run failed finishes failed and gets the annoyed mumble in every mode, whose word is `tests`; one whose tests failed, then passed, is a normal finish. Hero moment 2. |
| `07-told-off.json` | "Shut up", "you're so annoying", a yell and a wordless yell each get a sad mumble (nothing in calm) and leave quiet mode off; "this build is annoying" doesn't count (curious, or annoyed at the build); a classifier that calls `quiet` anyway has its pass dropped, since `quiet` isn't on the menu. Hero moment 3. |
| `08-poke-streak.json` | Quick taps reach nothing until one completes a poke streak, which gets an annoyed mumble in chatty and normal and nothing in calm; a second streak soon after doesn't reach the brain, and one later does; slow taps never do. Hero moment 4. |
| `09-remember.json` | "Remember the demo is on Thursday" is kept for today, a lasting fact about you in About you and how you like things in Preferences; long-term refuses someone else's name, and "good job today" gets a proud mumble and no note. |
| `10-small-talk.json` | "Hello boop", "time for lunch" and "see you tomorrow" get the word each calls for, in every mode: hi, food, bye. |
| `11-mode-switch.json` | Switching mode mid-turn changes the next reaction and the core's cheer at once, between chatty and calm. |
| `12-chatter.json` | A 10-minute turn: the core chatters 8 times in chatty (45–90 s apart), twice in normal (2–4 minutes apart) and never in calm, and cheers the finish in every mode. |

The hero moments are VISION.md's. Hero moment 1's cheer is the core's own
reaction: `01` and `10` record it, and the core's unit tests check it too. In
v1 the others are the brain's mumbles, which the evals do record: C1 parked
the `oops` and side-eye they had ([BEHAVIORS.md](BEHAVIORS.md)).

Adding a scenario means adding its file and its row here.
