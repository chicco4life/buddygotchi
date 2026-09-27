# Boop: harness and brain

Updated 2026-09-27. How something that happened becomes a decision and a
few words, and how they're handed off.

## 1. What this is

Boop's brain works in two stages. A **classifier** decides what Boop does
about something that just happened, by picking from a short menu. When
the decision needs words (the one real word in a mumble, or a line to
remember), a **writer**, a language model, writes just those words. The
**harness** is the small, generic code around both:

```
 input ──► Stage 1: classifier ──► Stage 2: writer ──► actions ──► device, memory
 (from      if-else table or Jev;     Apple's model;       react, quiet,
  the core) picks outputs and         only for words;      remember
            every choice              fills slots
    └──── one append-only transcript: Stage 1 reads a window, Stage 2 this pass ────┘
```

The core's rules have already reacted when an input arrives, so the brain
only adds to what Boop does. The **mode** (chatty, normal or calm) picks
the classifier and writer (§6). The **transcript** (§4) records every
pass, so a later decision knows what Boop just did.

The harness runs the stages, checks their answers and hands each call to
the action that owns it. It doesn't know what an output does or what kind
of model is behind a stage, and it never builds Minion speech, writes a
file or talks to the device: that's the actions' job
([ARCHITECTURE.md](ARCHITECTURE.md) §3.4). The eval scenarios check what
it does for given events ([EVALS.md](EVALS.md)).

## 2. Inputs

Four things reach the brain. The core builds each as a typed input
(`app/BoopKit/Core/Input.swift`): classifiers read its fields, and
language models its one-line form.

| Input | From | Fields | The rules' reaction | Deadline | Menu |
| --- | --- | --- | --- | --- | --- |
| Agent started | `turn_start` | agent, project, time | — | 5 s | `react` |
| Agent finished | `turn_end` or `turn_failed` | outcome (`done` or `failed`), agent, project, topic, the turn's length, the error class if it failed, time, "+N more" | `cheer`, if the mode cheers that finish | 5 s | `react` |
| You said something | push-to-talk, or Send in the popover | your words (at most 500 characters, about 30 s of speech), whether you yelled, time | `listening` | 4 s | `quiet` (only when your words ask for it), `react`, `remember` |
| Poked again and again | a poke streak ([BEHAVIORS.md](BEHAVIORS.md) §3.3) | time | `wiggle` | 4 s | `react` |

A line reads like `agent finished · done · claude · landing · a very
long turn (20 min) · 14:20 Wednesday` (from the core's tests); your words
travel beside it, never in it.

A finish is `failed` as [BEHAVIORS.md](BEHAVIORS.md) §3.1 defines it. The
topic is the session's latest ([ADAPTERS.md](ADAPTERS.md) §3), and the
error class the hook's ([ADAPTERS.md](ADAPTERS.md) §2).

**A turn's length is named,** so no brain has to compare numbers: short
under 15 seconds, long up to a minute, very long past that
(`Input.Length`). The if-else tables, the core's cheer and the burst
ranking all use these bands.

**Bursts.** An agent input goes out at once if none has in the last 3 s.
Any that follow within those 3 s are held and sent as one when the 3 s
are up, the most important winning: failed, then a finish of 15 seconds
or more, then a shorter finish, then a start. Its line ends `· +N more`.

**Gating.** While something needs you, or in quiet mode, agent inputs
don't reach the brain. What you say always does. A poke streak does too,
except while something needs you (a tap then means "I saw it") or when it
comes too soon after the last ([BEHAVIORS.md](BEHAVIORS.md) §3.3).
Otherwise whether Boop reacts is Stage 1's call every time.

**Asides.** A tap and "needs you" are the rules' alone, so the brain
can't make them slower or different. The transcript notes them
(`tapped · 14:07 Tuesday: Boop wiggled`, `claude needs you · jetpack ·
14:07 Tuesday`) so the brain knows they happened. Everything else the
core hears (sessions, tool use, a new day) is its own bookkeeping.

## 3. What the harness does, step by step

1. **Receive an input** from the core.
2. **Wait its turn.** One pass runs at a time. A newer input replaces one
   that's waiting, and what you say cancels whatever is running.
3. **Open the pass.** The input and the rules' reaction join the
   transcript (§4). The menu is the input's outputs, in the order they
   run, with the actions' definitions as they are now. `quiet` is on it
   only when your words ask for quiet (`Input.asksForQuiet`,
   [BEHAVIORS.md](BEHAVIORS.md) §3.3). The pass keeps the brains it started
   with, so a new mode applies from the next.
4. **Stage 1.** The classifier gets the input, the memory and the window,
   and answers with calls and their decided arguments. The harness checks
   them: only outputs on the menu, decided arguments from their choices,
   no written ones, and at most one call to each output. If anything is
   off, the whole pass is dropped. Staying silent is no calls.
5. **Stage 2, only when something needs words.** Each written argument is
   a slot (`react.word`, `remember.text`). One writer call fills them all,
   in the time the deadline has left, less 100 ms. A slot left out,
   answered `none`, or off its list or over its length is left empty. A
   writer that fails or runs late leaves every slot empty.
6. **Hand off** each call to its action in the menu's order: `quiet`,
   `react`, `remember`. An empty word leaves the mumble without one; an
   empty memory line drops its call ("nothing was written").
7. **Record** it all in the transcript, and log the pass (§8).

A stage that misses the deadline has failed. The app gives the harness
its outputs as `(definition, handler)` pairs at startup, and each
definition is read again for every pass.

## 4. The transcript

One list, owned by the harness (`app/BoopKit/Harness/Transcript.swift`),
that passes only ever append to:

| Entry | What it holds |
| --- | --- |
| `input` | An input that reached the brain |
| `rules` | The rules' reaction to it, e.g. `cheer` |
| `aside` | Something only the rules handled: a tap, something needing you |
| `decided` | Stage 1's calls, and how it got there (the rule that matched, Jev's answers) |
| `dropped` | Why a pass produced nothing: Stage 1 failed, was late or cancelled, or answered off the menu |
| `wrote` / `write_failed` | Stage 2's values by slot, or why it wrote nothing |
| `ran` | Each call as its action received it, and what the action did |

**The window.** Brains see at most **8 inputs**. When a 9th arrives, the
window starts again from the **last 2**, so Boop still knows what you
just said. Nothing is summarized. Asides don't count toward the 8, so
without a cap a burst of taps could crowd out the rest: at most **8
asides** are noted after each input, and later ones are left out. Memory
changes don't restart it, since every call gets the current memory
anyway.

**Who reads what.** The if-else tables read only the current input. Jev
gets the window as JSON (§6). Apple's writer reads only this pass, then a
line per slot (from `BrainTests`):

```
--- now ---
you said · 14:05 Tuesday
They just said: "remember the demo is on Thursday"
Boop decided: react(feeling: happy), remember(where: today)
--- write ---
react.word: the mumble's one real word, from its list, as Writing says; none only when nothing fits.
remember.text: at most 80 characters. Short-term, for today: a fact about a project or this session, like what something is, a date, or what they're doing now. Plain words, no code; leave it empty if nothing is worth keeping.
```

**Sizes.** Apple's model has an 8K-token context for prompt, schema and
answer, so it sets the budget (Jev takes 32K). The memory store keeps
each file within its share, and a full window is about 1–2K tokens, so
nothing needs trimming. A part over budget is logged (`Prompt.Budget`):

| Part | Budget (tokens) |
| --- | --- |
| `steering.md` | 1,000 |
| `long-term.md` | 800 |
| `short-term.md` | 600 |
| An input's line and your words | 200 |

The transcript lives in memory only. Entries before the window are never
read again, and past a thousand of them they're let go. No code, file
contents, prompts or agent transcripts go in; your words are the one
exception, until the window moves past them. With Jev, the window, your
words included, also goes to TypeSafe with each call (§6 lists what Jev
reads).

## 5. Outputs

Boop can do three things. Each action writes its own definition, where
each argument is **decided** by Stage 1 from its choices or **written** by
Stage 2. For model brains a definition also carries plain questions for
the output and each decided argument (Jev asks them), and, for a written
argument, the **sources** its value can come from (§7).

| Output | Decided | Written | What it does |
| --- | --- | --- | --- |
| `react` | `feeling`: one of ten (below) | `word`, optional: one of Voice's 40 words ([VOICE.md](VOICE.md) §6), from what they said, the failed topic, how the turn went, or the feeling | A mumble: a Minion line in the feeling's sound, with the word, played over whatever face is showing. Dropped in quiet mode, while something needs you, and while you talk until your words arrive ([BEHAVIORS.md](BEHAVIORS.md) §3.3). Staying silent is not calling it |
| `quiet` | `minutes`: 15, 30, 60 or 120 | — | Quiet mode ([BEHAVIORS.md](BEHAVIORS.md) §4). Runs only when your last words asked for quiet (§3) |
| `remember` | `where`: `today`, `about_you` or `preference` | `text` | A line in that part of memory |

The feelings are `happy`, `excited`, `proud`, `curious`, `hopeful`,
`annoyed`, `sad`, `sleepy`, `smug` and `sulky`. Each mumbles in a Voice
feeling ([VOICE.md](VOICE.md) §4).

Where a line goes is spelled out in each choice's meaning, which Jev is
asked with and the writer is told:

| `where` | Goes to | For |
| --- | --- | --- |
| `today` | short-term Notes, gone tomorrow | A fact about a project or this session: what something is, a date, what they're doing now |
| `about_you` | long-term About you | A durable fact about the person that will still matter in a month: their role, how they work, their routine |
| `preference` | long-term Preferences | How they like things done |

Each section's limits and rules (length, no code or secrets, no
duplicates, no other people's names long-term, a cap on lines) are the
memory store's ([ARCHITECTURE.md](ARCHITECTURE.md) §4). Forgetting a
line is the person's, in Settings; the brain has no way to.

The core's rules use the same `react` action for their animations
(`cheer`, `wiggle`, `listening`) and for working chatter. Every action
checks a call against its own definition, so a call that skips the
harness is held to the same rules, and it logs why it dropped one.

## 6. The brains

A classifier answers `classify(context, menu, deadline)` with calls and
its evidence; a writer answers `write(context, slots, deadline)` with a
value for each slot it filled. The context is the input, the memory and
the window. Each brain is its own type in `app/BoopKit/Brains/`, with a
comment that says exactly how it behaves. The mode picks them:

| Mode | Classifier | Writer |
| --- | --- | --- |
| Chatty | `ChattyRules` (`chatty@1`) | `AppleWriter`, asked again for a word it leaves out |
| Normal (the default) | `JevClassifier` (`jev:jev-latest`) with `NormalRules` behind it; `NormalRules` (`normal@1`) alone without Jev's key | `AppleWriter` |
| Calm | `CalmRules` (`calm@1`) | `AppleWriter` |

**The if-else tables** are plain Swift: no model, always available, and
reading only the input's fields, so the same events always get the same
decisions. Each decides exactly its mode's column in
[BEHAVIORS.md](BEHAVIORS.md) §6 (a curious mumble there is
`react(curious)` here), and all three share the tables below for what you
say.

**`JevClassifier`** is TypeSafe's `jev-latest`
([docs](https://docs.typesafe.ai/api)) with the person's API key. It
doesn't write: it answers yes/no and multiple-choice questions with
probabilities, in one request of about 0.2 s.

- **Reads:** `steering.md` without its Writing section, both memory files,
  the window's earlier inputs and asides (minutes ago, what happened, what
  you said, what the rules and Boop did) and `now`.
- **Asked:** one yes/no per output ("Does what just happened call for Boop
  to react?") and one choice per decided argument with more than one
  option, with its options' meanings, all up front. As TypeSafe advises,
  each question names what it's about (`now`) and what to judge it by
  (`boop`, its Examples first).
- **Answer:** a yes is above 0.5, and a choice is the likeliest option.
  Only a chosen output's arguments are used.
- **Failures:** a 429, a 5xx or a dropped connection is tried once more
  after 0.3 s. Only a failed request's HTTP status is logged.

In normal mode Jev gets half the input's deadline (2.5 s for an agent
input, 2 s otherwise), leaving the rest for the writer. When it fails,
refuses or hasn't answered by then, `NormalRules` decides that pass
(`FallbackClassifier`), so a failed turn or "be quiet" is never lost to
an outage or a bad key. The evidence then reads `jev:jev-latest failed
(…) · normal@1: …`.

**`AppleWriter`** is Apple's on-device model: private and free. Each call
is a fresh session.

- **Reads:** a three-line preamble, `steering.md`, long-term memory, and
  short-term memory with only its last 5 Happened lines (every character
  costs time on every write). Its prompt is the pass (§4).
- **Asked:** guided generation gives it one property per slot: a word
  from `none` and its list, or text with its length asked for. A slot
  with sources gets a property just before it where the model picks the
  source. In chatty mode a word left empty is asked for once more, with
  `none` off its list, if the first answer left time. It can't decline,
  so it can't choose silence: that was Stage 1's job.
- **Sampling** is greedy, so the same moment always gets the same words.
  Guardrails are `permissiveContentTransformations`, and a refusal fails
  the write like any error, marked as a refusal.
- **When it can't run** (downloading, updating, Apple Intelligence off),
  every write fails at once, so mumbles go without a word and nothing is
  remembered. It checks before every write, so it recovers by itself.

**`NoWriter`** writes nothing: `--writer none`, and the evals' default.

**What you said**, for every if-else table (`Phrases`): the first row
that matches wins, on whole words, with curly apostrophes read as
straight ones.

| You said | Decides |
| --- | --- |
| "remember" or "note", unless you told Boop off | `react(happy)` and `remember(where)`, with where from the next table. This wins over "quiet": "remember I like it quiet" isn't asking for quiet |
| "quiet" | `quiet(minutes)` and nothing else, yelled or not |
| You told Boop off: "shut up", "go away", "hate you", "you suck", "hush", "stop talking", "keep it down", or "you" with "annoying", "stupid", "dumb", "useless" or "idiot" | `react(sad)` in chatty and normal; nothing in calm |
| Starting with "hello", "hi", "hey", "morning" or "good morning" ("the tests broke this morning" isn't a greeting) | `react(happy)` |
| "bye", "goodbye", "see you" or "good night" | `react(happy)` |
| "lunch", "dinner", "breakfast", "food", "snack" or "hungry" | `react(hopeful)` |
| "good job", "well done", "nice", "great", "thanks", "thank you" or "the best" | `react(proud)` |
| You yelled, and nothing above matched (or there were no words): loudness comes last, so a yelled "good job!" is still praise | `react(sad)` in chatty and normal; nothing in calm |
| Anything else | `react(curious)` |

Quiet lasts the time you said, as the nearest of 15, 30, 60 and 120
minutes, the shorter on a tie ("ten minutes" is 15, "an hour and a half"
60). A unit alone is one ("the next hour", 60), except "for hours" (120);
a number alone is minutes ("for fifteen", 15). "A quarter of an hour" and
"a little while" are 15, "a long while" 120, and no time at all is 30.

**Where to remember**, first match wins. Going only by the words, the
tables lean towards today:

| The words have | `where` |
| --- | --- |
| Someone else's name: a capitalised word that isn't the first, "I", a day, a month or an acronym ("Bob", not "PRs"), found as the memory store finds one | `today`, since long-term keeps no one else's name |
| "I like", "I love", "I prefer", "I hate", "I don't like" or "I'd rather" | `preference` |
| "I", "I'm", "I've" or "my", with a sign it lasts: "always", "usually", "never", "every", "mostly", "generally", a weekday in the plural ("Fridays"), "weekends", "mornings", "evenings", "my name", "I'm a", "I work" or "I live" | `about_you` |
| Anything else | `today` |

**The setting** is `mode` in `settings.json` (Mode in the app,
[UX.md](UX.md) §7), and applies at once. Jev's key comes from
`BOOP_JEV_KEY`, else, in the menu-bar app only, the Keychain:
`Boop --headless` and `boopdev` read only the variable, so a run from an
agent shell never uses the owner's key. It's read off the app's event queue
and the main thread the first time normal needs it, since a Keychain
prompt would stall both, and normal decides with its table until then;
saving a key in Settings brings Jev in at once. For one run, `--mode`,
`--classifier chatty|normal|calm|jev` and `--writer apple|none` override
the setting and its brains (`Boop --headless`, `boopdev eval`);
`--classifier jev` is Jev alone, with no table behind it.

A weaker brain makes Boop less witty, but it can't make it break the
rules: every call goes through the same check and the same actions.

## 7. Designing for small models

Both stages are assumed to be small: good at picking from a short menu
and filling one blank, bad at long, open-ended instructions. The evidence
behind most of these rules is in [ARCHITECTURE.md](ARCHITECTURE.md) §11.

- **Deciding and writing are separate jobs,** each one call with no
  follow-up.
- **A short menu:** one to three outputs, with flat, multiple-choice
  arguments. The only free text is a memory line with a length limit, and
  no calls is always a valid answer.
- **Examples over rules:** `steering.md` shows a short example for each
  input, with its mumble's word.
- **The source before the word.** The writer names where a word comes
  from before it picks one, and the sources' names matter.
- **Only what the stage needs.** The writer reads just its pass and the
  latest Happened lines; Jev doesn't get the writer's guidance.
- **No arithmetic:** numbers arrive already named (a long turn, not
  20 s), and what the rules decide isn't asked (`quiet` is offered only
  when your words ask for it).
- **Choices that say what they're not:** each feeling's meaning rules out
  its neighbours ("sad" is only hurt; a failed turn is "annoyed"), since
  Jev is literal
  ([TypeSafe](https://docs.typesafe.ai/model-jaggedness/jev-1.13)).

The spirit is [pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/)'s
"if I don't need it, it won't be built".

## 8. Logging

**Debug mode** is `Boop --debug`, in the menu-bar app (`make debug`) or
headless. It prints to the terminal that started the app, as it happens:
each hook with the event the adapter made of it, the core's decisions,
every line sent to the device (marked rules or brain), and each pass.

Each pass is also one JSON line in the state directory's `debug.jsonl`,
which starts afresh at every launch: the input (with what you said), both
brains, the memory they read (not steering, which never changes), the
window, Stage 1's calls and evidence, the slots and what was written
(with the writer's raw answer), why anything was dropped or failed, what
each action did, and each stage's latency. Asides get a line too, so the
file holds the whole transcript. `boopdev watch [FILE]` prints it
readably (the everyday app's by default), following it as it grows and
starting again when a launch empties it. One pass from the
`09-remember` eval (evals run without a writer, so nothing is written):

```
▸ you said · 14:01 Wednesday   [normal@1 → none, 0 ms]
    said     "remember I always review PRs before lunch"
    memory   the same as the pass before
    window   2 inputs, oldest first
      you said · 14:00 Wednesday "remember the demo is on Thursday" · rules: listening · did: react(feeling: happy)
      you said · 14:01 Wednesday "remember I always review PRs before lunch" · rules: listening
    decided  react(feeling: happy), remember(where: about_you) (0 ms)
    because  asked to remember, about_you
    wrote    react.word = (empty), remember.text = (empty) (0 ms)
    ran      react(feeling: happy) → done: happy: la-la la… (seed 2)
    ran      remember(where: about_you) → dropped: nothing was written
```

**The app log** (`boop.log`) gets one line per pass, debug mode or not:
the input kind, the latency and the outputs that ran, never their
arguments, as in `brain you said 812 ms → quiet, react, remember`. What
you said and what the brain wrote never reach it; only the terminal and
`debug.jsonl` get them. (In debug mode the log does get the lines sent to
the device, and a mumble's word is in them.)
