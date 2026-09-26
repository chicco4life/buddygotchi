# Boop: harness and brain

Updated 2026-09-27. How something that happened becomes a decision and a
few words, and how they're handed off.

## 1. What this is

Boop's brain works in two stages. A **classifier** decides what Boop does
about something that just happened, by picking from a short menu. When a
decision needs words (the one real word in a mumble, or a line to
remember), a **writer**, a language model, writes just those words. The
**harness** is the little bit of generic code around both:

```
 input ──► rules react ──► Stage 1: classifier ──► Stage 2: writer ──► actions ──► device, memory
 (from      at once          Jev or if-else;          Apple's model;       react, quiet,
  the core)  (the core)      picks outputs and        only for words;      remember
                             every choice             fills slots
      └──────── one append-only transcript: Stage 1 reads its window, Stage 2 this pass ────────┘
```

Which classifier and writer run is the **mode**'s choice: chatty, normal or
calm ([BEHAVIORS.md](BEHAVIORS.md) §6, and §6 below).

One **transcript** (§4) records every pass: the inputs so far, the rules'
reactions, what Stage 1 decided, what Stage 2 wrote and what ran. Stage 1
reads a window onto it, so a later decision knows what Boop just did. The
writer reads only the pass it writes for, what just happened and what
Stage 1 decided, since a small model copies the words it sees.

The harness knows how to run the two stages, check their answers and hand
each call to the action that owns it. It doesn't know what any output
does, or what kind of model is behind either stage. It never builds Minion
speech, writes a file or talks to the device. That work belongs to the
actions ([ARCHITECTURE.md](ARCHITECTURE.md) §3.4), so the harness would
work the same driving something other than Boop.

The harness eval scenarios check what it does for given events
([EVALS.md](EVALS.md)).

## 2. Inputs

Four things reach the brain. The core builds each as a typed input
(`app/BoopKit/Core/Input.swift`); classifiers read its fields, and
language models read its one-line form.

| Input | From | Fields | The rules first | Deadline | Menu |
| --- | --- | --- | --- | --- | --- |
| Agent started | `turn_start` | agent, project, time | Base becomes working | 5 s | `react` |
| Agent finished | `turn_end` or `turn_failed`; a `turn_end` whose last test, build or deploy command failed is `failed` ([BEHAVIORS.md](BEHAVIORS.md) §3.1) | outcome (`done` or `failed`), agent, project, topic, how long it took, named (below), the error class when it failed, time, "+N more" | `done`: a cheer (in calm, only for a very long turn). `failed`: nothing; the session goes idle | 5 s | `react` |
| You said something | push-to-talk, or Send in the popover | your words (at most 500 characters, about 30 s of speech), whether you yelled, time | `listening`, until the reply | 4 s | `quiet` only when your words ask for it, `react`, `remember` |
| Poked again and again | a poke streak ([BEHAVIORS.md](BEHAVIORS.md) §3.3) | time | `wiggle`, as for every tap | 4 s | `react` |

Their lines look like this:

```
agent started · claude · landing · 14:00 Wednesday
agent finished · done · claude · landing · a very long turn (20 min) · 14:20 Wednesday
agent finished · failed · claude · landing · topic: tests · error: rate limit · 14:00 Wednesday
you said · 14:00 Wednesday
you said · yelled · 14:00 Wednesday
poked again and again · 14:00 Wednesday
```

The topic is `tests`, `build`, `deploy` or `docs`, when the agent's tools
showed one; for a turn that failed on its last test, build or deploy
command, it's that command's, and there's no error class. The error class is one of `rate_limit`, `overloaded`,
`api_error`, `auth`, `timeout`, `network`, `context_limit`, `billing` or
`other` ([ADAPTERS.md](ADAPTERS.md) §2); Codex has no failure hook, so its
turns always finish `done`.

**A turn's length is named**, so no brain has to compare numbers: a short
turn is under 15 seconds, a long one up to a minute, and a very long one
past it (`Input.Length`). The if-else classifiers, calm's cheer and the
core's burst ranking use the same bands.

**Bursts.** Agent inputs within 3 s become one, and the most important
wins: failed, then a finish of 15 seconds or more, then a shorter finish,
then a start. It ends `· +N more` for the others
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).

**Gating.** While something needs you, or in quiet mode, agent inputs don't
reach the brain. What you say always does, and so does a poke streak, except while something needs you, when a tap means "I saw it". A
poke streak too soon after the last ([BEHAVIORS.md](BEHAVIORS.md) §3.3)
gets the rules' wiggle alone. There are no other limits: whether Boop reacts, and whether it
mumbles, is Stage 1's decision every time.

**Rules only.** A tap (the wiggle) and "needs you" (the ladder) never reach
the brain, so it can't make them slower or different from one time to the
next. They're noted in the transcript as asides, `tapped · 14:07 Tuesday:
Boop wiggled` or `claude needs you · jetpack · 14:07 Tuesday`, so the
brain knows they happened. The one tap that does reach it is the one that
completes a poke streak, as its own input.

Session start and end, and each tool use (`activity`), are the core's
bookkeeping: they keep the session list, the base state and each session's
topic, and never reach the brain. So does the first activity of a day,
which starts short-term memory fresh; nothing reflects on the day before
([ARCHITECTURE.md](ARCHITECTURE.md) §11).

## 3. What the harness does, step by step

1. **Receive an input** from the core, with its deadline.
2. **Wait its turn.** One pass runs at a time. A newer input replaces one
   that's waiting, and what you say cancels whatever is running.
3. **Open the pass.** The input and the rules' reaction join the
   transcript, moving the window first when it's full (§4). The menu is the
   input's outputs, in the order they run, with the actions' definitions as
   they are now. `quiet` is on it only when your words ask for quiet
   ("quiet" as a whole word, and not asking Boop to remember something,
   `Input.asksForQuiet`): its action would refuse it otherwise, and a brain
   isn't asked what the rules decide.
   The pass keeps the classifier and writer it starts with: a new mode
   (§6) takes the next pass, and one already running finishes with its
   own.
4. **Stage 1.** The classifier gets the input, the memory text and the
   transcript's window, and answers with calls whose decided arguments are
   filled in (§5). The harness checks them: only outputs on the menu,
   decided arguments from their choices and no written ones, and at most
   one call to each output. If anything is off, the whole pass is dropped.
   Staying quiet is no calls.
5. **Stage 2, only when something needs words:** a mumble's word, or a
   memory line. Each is a slot (`react.word`, `remember.text`). One writer
   call fills them all, given the window with Stage 1's decision at its end
   (Apple's model reads only this pass, §4), in whatever time the deadline
   has left (less 100 ms). A slot the writer
   leaves out, answers `none`, or fills with something that doesn't fit its
   list or its length is left empty. A writer that fails or runs late
   leaves every slot empty.
6. **Hand off** each call to its action, in the menu's order: `quiet`, then
   `react`, then `remember`. An empty word leaves the mumble without one; an
   empty memory line drops that call ("nothing was written"). Each action
   checks its own rules.
7. **Record** everything in the transcript, and log the pass (§8).

At startup, the app gives the harness its outputs as `(definition,
handler)` pairs. That's what keeps it generic. A definition is read again
for each pass.

## 4. The transcript

One list, owned by the harness (`app/BoopKit/Harness/Transcript.swift`).
Each pass appends to it; nothing in it is ever changed:

| Entry | What it holds |
| --- | --- |
| `input` | An input that reached the brain |
| `rules` | The rules' reaction to it, e.g. `cheer` |
| `aside` | Something only the rules handled: a tap, something needing you |
| `decided` | Stage 1's calls, and how it got there (the rule that matched, Jev's answers) |
| `dropped` | Why a pass produced nothing: Stage 1 failed, was late or cancelled, or answered off the menu |
| `wrote` / `write_failed` | Stage 2's values by slot, or why it wrote nothing |
| `ran` | Each call as its action received it, and what the action did |

**The window.** Brains see a window onto the transcript: at most **8
inputs**. When a 9th arrives, the window starts again from the **last 2**,
so Boop still knows what you just said. That's the only rule: nothing is summarized, and the window just moves
its start. The window doesn't restart when memory changes, since every
call puts the current memory at the top. Asides don't move it, so at most
**8 asides** follow an input and later ones aren't noted: a burst of taps
can't crowd out the prompt.

**How each brain reads it.** The if-else classifiers read only the current
input. Jev gets the window as JSON (§6). Apple's writer reads only the
pass it writes for: what just happened, what you said and what Stage 1
decided, then a line per slot (from `BrainTests`):

```
--- now ---
you said · 14:05 Tuesday
They just said: "remember the demo is on Thursday"
Boop decided: react(feeling: happy), remember(where: today)
--- write ---
react.word: the mumble's one real word, from its list, as Writing says; none only when nothing fits.
remember.text: at most 80 characters. Short-term, for today: a fact about a project or this session, like what something is, a date, or what they're doing now. Plain words, no code; leave it empty if nothing is worth keeping.
```

In chatty mode the prompt is the same (§6 has its second try for a word).

Given the rest of the window too, it copied the words it had written
before: over 58 inputs it said "yay" to every finished turn and ignored a
failed turn's topic ([ARCHITECTURE.md](ARCHITECTURE.md) §11).

**Sizes.** Apple's on-device model has an 8K context window here (measured
2026-09-25), for the prompt, the schema and the answer; Jev takes 32K tokens
of state. So Apple's model sets the budget. The memory store's line limits
keep the files within theirs, and 8 inputs of the window come to about
1–2K tokens, so nothing ever needs trimming:

| Part | Budget (tokens) |
| --- | --- |
| `steering.md` | ≤ 1,000 |
| `long-term.md` | ≤ 800 |
| `short-term.md` | ≤ 600 |
| An input's line and your words | ≤ 200 |

The transcript lives in memory only and is gone when the app quits. Entries
before the window are never read again, and past a thousand of them they're
let go.

No code, file contents, prompts or agent transcripts go in. The one
exception is your words, which stay in the window until it moves past
them. With Jev (§6) the pass leaves the Mac: `steering.md`, both memory
files and the window, your words included, go to TypeSafe with each call.

## 5. Outputs

Boop can do three things. Each output's action writes its definition, and
each argument has a **role**: **decided** by Stage 1 from its choices, or
**written** by Stage 2. For model brains, a definition also says in plain
words what to ask: a question for the output and for each decided argument
(Jev asks them), and, for a written argument, the **sources** its value
can come from, in order (the writer picks one before the value, §7).

| Output | Decided | Written | What it does |
| --- | --- | --- | --- |
| `react` | `feeling`, one of ten | `word`: `none` or one of Voice's 40 words ([VOICE.md](VOICE.md) §6), from what they said, the failed topic, how the turn went or the feeling (`steering.md`, Writing) | A mumble: a Minion line from Voice in the feeling's sound, with the word, played over whatever face is showing. The brain's faces are parked ([FUTURE.md](FUTURE.md)), so staying silent is not calling `react`. A mumble is dropped in quiet mode or while something needs you |
| `quiet` | `minutes`: 15, 30, 60 or 120 | — | The core's quiet mode: no mumbles, and agent inputs skip the brain. The action runs only when the last thing you said asked for quiet ("quiet" in your words, and not asking Boop to remember something), whichever classifier decided ([BEHAVIORS.md](BEHAVIORS.md) §3.3) |
| `remember` | `where`: `today`, `about_you` or `preference` | `text` | A line in that part of memory, under its own rules |

| Feeling | Its mumble sounds |
| --- | --- |
| `happy` | happy |
| `excited` | excited |
| `proud` | proud |
| `curious` | curious |
| `hopeful` | hopeful |
| `annoyed` | annoyed |
| `sad` | sad |
| `sleepy` | sleepy |
| `smug` | proud |
| `sulky` | sad |

Where a line goes is spelled out for both stages: in each choice's meaning,
which Jev is asked with, and in `steering.md`, which both read. The writer
is told the chosen place's meaning and its length.

| `where` | Goes to | For | Text | Its own rules |
| --- | --- | --- | --- | --- |
| `today` | short-term Notes, gone tomorrow | A fact about a project or this session: what something is, a date, what they're doing now | ≤ 80 characters | One line, no code, paths or secrets, no duplicates |
| `about_you` | long-term About you | A durable fact about the person that will still matter in a month: their role, how they work, their routine | ≤ 100 | Also no other people's names, and nothing already remembered; refused when the section or the file is full |
| `preference` | long-term Preferences | How they like things done | ≤ 100 | As `about_you` |

The core's rules use the same `react` action: its animations for their
instant reactions (`cheer`, `wiggle`, `listening`), and a mumble for
working chatter.
Every action checks its arguments against its own definition, so a call
that skips the harness (a rule's) is held to the same rules. A dropped call
is logged with the reason. Forgetting a remembered line is the person's, in
Settings; the brain has no way to.

## 6. The brains

```
Classifier                                   Stage 1
  id                                         e.g. "chatty@1", "jev:jev-latest"
  classify(context, menu, deadline) -> calls with their decided arguments, and evidence

Writer                                       Stage 2
  id                                         e.g. "apple:26.4", "none"
  write(context, slots, deadline) -> a value for each slot it filled
```

The context is the input, the memory text and the transcript's window.
Each brain is its own class in `app/BoopKit/Brains/`, with a comment that
says exactly how it behaves. The mode picks them
([BEHAVIORS.md](BEHAVIORS.md) §6):

| Mode | Classifier | Writer |
| --- | --- | --- |
| Chatty | `ChattyRules` | `AppleWriter`, asked again for a word it leaves out |
| Normal (the default) | `JevClassifier`, with `NormalRules` behind it; `NormalRules` alone without Jev's key | `AppleWriter` |
| Calm | `CalmRules` | `AppleWriter` |

| Brain | Stage | What it does |
| --- | --- | --- |
| `ChattyRules` | 1 | Plain Swift, no model, always available; reads only the input's fields, so the same events always get the same decisions. Every agent input gets a mumble. Agent started: `react(curious)`. Finished `done`, a short turn: `react(happy)`; a long turn: `react(proud)`; a very long turn: `react(excited)`. Finished `failed`: `react(annoyed)`, one mumble per failure. Poked again and again: `react(annoyed)`. You said something: the phrase table below, with a sad mumble when you told Boop off, or yelled and said nothing else |
| `NormalRules` | 1 | Plain Swift, no model, always available; reads only the input's fields. Normal decides with it without Jev's key, and for any pass Jev fails, refuses or doesn't answer in half the input's deadline (2.5 s for an agent input, 2 s otherwise), which leaves the rest for the writer; the evidence says `jev:jev-latest failed (…) · normal@1: …` and the log gives Jev's error. Normal's column ([BEHAVIORS.md](BEHAVIORS.md) §6), which Jev is steered toward. Agent started, and finished `done` in a short turn: nothing (the rules cheer). Finished `done`, a long or very long turn: `react(proud)`. Finished `failed`: `react(annoyed)`. Poked again and again: `react(annoyed)`. You said something: the phrase table below, with a sad mumble when you told Boop off, or yelled and said nothing else |
| `CalmRules` | 1 | Plain Swift, no model, always available; reads only the input's fields. Agent started, finished `done`, and poked again and again: nothing. Finished `failed`: `react(annoyed)`, the one alert besides "needs you". You said something: the phrase table below, and nothing when you told Boop off, or yelled and said nothing else |
| `JevClassifier` | 1 | TypeSafe's `jev-latest` ([docs](https://docs.typesafe.ai/api)), with the person's API key. It doesn't write: it answers typed questions about a state with probabilities, in one request of about 0.2 s. The state is `steering.md` without its Writing section (Jev never writes), both memory files, the window's recent inputs (minutes ago, what happened, what you said, what the rules did and what Boop did) and now. The menu becomes questions built from the definitions' own questions: a yes/no for each output ("Does what just happened call for Boop to react?"), a choice for each decided argument with more than one option (`react.feeling`, `quiet.minutes`); `remember.where` is asked with each place's meaning. As TypeSafe advises, each question names what it's about (`now`) and what to judge it by (`boop`, its Examples first), and a yes means `boop` says to do it for something like `now`. Each question is answered on its own, so every argument is asked up front and only a chosen output's are used. A yes is above 0.5; each choice is the most likely one. A 429, a 5xx (TypeSafe's 529 is "overloaded") or a dropped connection is tried once more, 0.3 s later, as TypeSafe advises; the input's deadline still bounds the pass. Only the HTTP status of a failed request is logged |
| `AppleWriter` | 2 | Apple's on-device model: private and free. A fresh session each call: its instructions are a short preamble, `steering.md` and both memory files; its prompt is what just happened and what Boop decided, then a line per slot (§4). Guided generation with one property per slot: a word from `none` and its list, or text with its length asked for; a slot with sources gets a property before it, where the model picks the source first. Temperature 0.2, so the same moment gets the same word. In chatty mode a word left empty is asked for once more, with `none` off its list, when that can finish in the time left; taking `none` off from the start made the words worse (a failed test run got "ugh", not "tests"). There's no option to decline, so it can't answer "stay quiet"; that was Stage 1's job. Guardrails are `permissiveContentTransformations`; a refusal fails the write like any error, marked as a refusal |
| `NoWriter` | 2 | Writes nothing: mumbles have no word, and nothing is remembered. What Apple's model falls back to when it can't run, and `--writer none` |

**What you said**, for every if-else classifier (`Phrases`), first match
wins and whole words only; a curly apostrophe counts as a straight one
("I’d rather" is "I'd rather"):

| You said | Decides |
| --- | --- |
| "remember" or "note", unless you told Boop off | `react(happy)` and `remember(where)`, where from the words below. It wins over "quiet", for the menu and the quiet action too: "remember I like it quiet" isn't asking for quiet |
| "quiet" | `quiet`: the time you said ("ten minutes", "1.5 hours", "an hour and a half", "a quarter of an hour", "a couple of hours"), as the nearest of 15, 30, 60 and 120, the shorter on a tie (90 minutes is 60). A unit with no number is one ("the next hour" 60), but "for hours" is 120; a number with no unit is minutes ("for fifteen" 15); "a little while" 15, "a long while" 120; else 30. Nothing else, yelled or not: Boop is quiet now |
| You told Boop off: "shut up", "go away", "hate you", "you suck", "hush", "stop talking", "keep it down", or "you" with "annoying", "stupid", "dumb", "useless" or "idiot" | `react(sad)` in chatty and normal; nothing in calm |
| Starting with "hello", "hi", "hey", "morning" or "good morning" ("the tests broke this morning" isn't a greeting) | `react(happy)` |
| "bye", "goodbye", "see you" or "good night" | `react(happy)` |
| "lunch", "dinner", "breakfast", "food", "snack" or "hungry" | `react(hopeful)` |
| "good job", "well done", "nice", "great", "thanks" or "the best" | `react(proud)` |
| You yelled, and the words say none of the above, or nothing: loudness comes last, so a yelled "good job!" is still praise | `react(sad)` in chatty and normal; nothing in calm |
| Anything else | `react(curious)` |

Where to remember, for every if-else classifier, first match wins. They can
only go by the words, so they err towards today:

| The words have | `where` |
| --- | --- |
| Someone else's name: a capitalised word that isn't the first, "I", a day, a month or an acronym ("Bob", not "PRs"), as the memory store finds one | `today`, since long-term keeps no one else's name |
| "I like", "I love", "I prefer", "I hate", "I don't like", "I'd rather" | `preference` |
| "I", "I'm", "I've" or "my", with a sign it lasts: "always", "usually", "never", "every", "mostly", "generally", a weekday in the plural ("Fridays"), "weekends", "mornings", "evenings", "my name", "I'm a", "I work", "I live" | `about_you` |
| Anything else | `today` |

**The setting** (`mode` in `settings.json`, and Mode in the app,
[UX.md](UX.md) §7) is `chatty`, `normal` or `calm`, and takes effect at
once (§3 step 3). Jev needs its key, from the Keychain or `BOOP_JEV_KEY`;
without one, normal decides with `NormalRules`, and saving a key in
Settings brings Jev in at once. A settings file from before the modes
(`classifier`, `writer` or `brain`) starts in normal. For one run,
`--mode`, `--classifier chatty|normal|calm|jev` and `--writer apple|none`
override the setting and the mode's brains (`Boop --headless`, `boopdev`);
`--classifier jev` is Jev alone, without the table behind it, to check its
own decisions.

A weaker brain makes Boop less witty, but it can't make it break the rules:
every call goes through the same check and the same actions.

## 7. Designing for small models

Both stages are assumed to be small. Small models are good at picking from
a short menu and at filling one blank, and bad at following long,
open-ended instructions, so the design leans on that:

- **Deciding and writing are separate jobs.** Asked to do both, Apple's
  model answered most inputs with silence, and Jev never chose a note over
  staying quiet ([ARCHITECTURE.md](ARCHITECTURE.md) §11).
- **A short menu:** one to three outputs per input, with flat,
  multiple-choice arguments. The only free text is a memory line with a
  length limit.
- **Easy silence:** no calls is always a valid answer.
- **One step:** one call per stage, no follow-up.
- **Examples over rules:** `steering.md` shows a short example for each
  input, with the word a mumble should carry, which helps a small model
  more than extra rules do.
- **The kind before the word:** asked for a word straight away, Apple's
  model answered every annoyed mumble "ugh" and every proud one "yay",
  whatever `steering.md` said. Asked first where the word comes from (what
  they said, the failed topic, how the turn went, the feeling), it names a
  failed turn's topic every time. The sources' names matter: "what the
  agent failed at" led to "bug" ([ARCHITECTURE.md](ARCHITECTURE.md) §11).
- **Only what the stage needs:** the writer reads just the pass it writes
  for, and Jev doesn't get the writer's guidance. Text a stage doesn't
  need pulls a small model off course.
- **No arithmetic:** numbers a decision depends on arrive already named
  (a long turn, not 20 s), and what the rules can decide isn't asked
  (`quiet` is offered only when your words ask for quiet).
- **Choices that say what they're not:** each feeling's description rules
  out its neighbours ("sad" is only hurt, a failed turn is "annoyed", a
  finished one "proud" whatever it ran), as TypeSafe advises for choices. Jev is literal and
  poor at comparing numbers ([TypeSafe](https://docs.typesafe.ai/model-jaggedness/jev-1.13)).

It's modelled on [pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/),
whose rule is "if I don't need it, it won't be built": a short system
prompt, few tools, context kept in plain files, every session logged, and
no MCP, sub-agents or plan mode. pi loops until its model stops calling
tools; Boop's outputs return nothing a model needs, so each stage is a
single call.

## 8. Logging

In debug mode, each pass is logged as one JSON line: the input and its
line (with what you said), both brains, how many inputs the window held,
Stage 1's calls and evidence, the slots and what was written (and the
writer's raw answer), why anything was dropped or failed, what each action
did, and each stage's latency. Each aside gets a line too, so the log
carries the whole transcript. Debug mode is `--debug-log FILE`, in the
menu-bar app (`make run DEBUG_LOG=FILE`) or headless, and `boopdev watch
FILE` follows it live, printing each pass readably. Otherwise the app log gets one line per pass: the input kind, the
latency and the outputs that ran, never their arguments:

```
brain you said 812 ms → quiet, react, remember
```

Outside debug mode, the words you said and what the brain wrote never reach
the log.
