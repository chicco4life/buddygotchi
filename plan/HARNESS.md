# Boop: harness and brain

Updated 2026-09-26. How something that happened becomes a decision and a
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
      └──────────────── one append-only transcript, read by both stages ────────────────┘
```

Both stages read one **transcript** (§4): the inputs so far, the rules'
reactions, what Stage 1 decided, what Stage 2 wrote and what ran. So the
writer knows exactly what it's writing for, and a later decision knows what
Boop just did.

The harness knows how to run the two stages, check their answers and hand
each call to the action that owns it. It doesn't know what any output
does, or what kind of model is behind either stage. It never builds Minion
speech, writes a file or talks to the device. That work belongs to the
actions ([ARCHITECTURE.md](ARCHITECTURE.md) §3.4), so the harness would
work the same driving something other than Boop.

## 2. Inputs

Four things reach the brain. The core builds each as a typed input
(`app/BoopKit/Core/Input.swift`); classifiers read its fields, and
language models read its one-line form.

| Input | From | Fields | The rules first | Deadline | Menu |
| --- | --- | --- | --- | --- | --- |
| Agent started | `turn_start` | agent, project, time, hunger | Base becomes working | 5 s | `react` |
| Agent finished | `turn_end` or `turn_failed` | outcome (`done` or `failed`), agent, project, topic, how long it took, the error class when it failed, time, hunger, "+N more" | `done`: a cheer, size 1 under 5 minutes, 2 up to 20, 3 beyond. `failed`: `oops`, then `side_eye` | 5 s | `react` |
| You said something | push-to-talk, or Send in the popover | your words (at most 500 characters, about 30 s of speech), time, hunger | `listening`, then `thinking` | 4 s | `quiet`, `react`, `remember` today |
| New day | the first hook or tap on a new day | yesterday's date and short-term memory | — | 10 min | `remember` about you, a preference, temperament or a moment |

Their lines look like this:

```
agent started · claude · landing · 14:00 Wednesday
agent finished · done · claude · landing · took 20 min · 14:20 Wednesday
agent finished · failed · claude · landing · topic: tests · error: rate limit · 14:00 Wednesday
you said · 14:00 Wednesday
new day · yesterday 2026-10-14
```

The topic is `tests`, `build`, `deploy` or `docs`, when the agent's tools
showed one. The error class is one of `rate_limit`, `overloaded`,
`api_error`, `auth`, `timeout`, `network`, `context_limit`, `billing` or
`other` ([ADAPTERS.md](ADAPTERS.md) §2); Codex has no failure hook, so its
turns always finish `done`.

**Bursts.** Agent inputs within 3 s become one, and the most important
wins: failed, then a finish of 5 minutes or more, then a shorter finish,
then a start. It ends `· +N more` for the others
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2).

**Gating.** While something needs you, or in quiet mode, agent inputs don't
reach the brain. What you say and the new day always do. There are no other
limits: whether Boop reacts, and whether it mumbles, is Stage 1's decision
every time.

**Rules only.** A tap (the wiggle) and "needs you" (the ladder) never reach
the brain, so it can't make them slower or different from one time to the
next. They're noted in the transcript as asides, `tapped · 14:07 Tuesday:
Boop wiggled` or `claude needs you · jetpack · 14:07 Tuesday`, so the
brain knows they happened.

Session start and end, and each tool use (`activity`), are the core's
bookkeeping: they keep the session list, the base state and each session's
topic, and never reach the brain.

## 3. What the harness does, step by step

1. **Receive an input** from the core, with its deadline.
2. **Wait its turn.** One pass runs at a time. A newer input replaces one
   that's waiting, and what you say cancels whatever is running.
3. **Open the pass.** The input and the rules' reaction join the
   transcript, moving the window first when it's full (§4). The menu is the
   input's outputs, in the order they run, with the actions' definitions as
   they are now, narrowed to the choices this input allows (`remember`'s
   `where` is only `today` for what you said).
4. **Stage 1.** The classifier gets the input, the memory text and the
   transcript's window, and answers with calls whose decided arguments are
   filled in (§5). The harness checks them: only outputs on the menu,
   decided arguments from their choices and no written ones, at most one
   call to each output (one per section on a new day), and never the same
   call twice. If anything is off, the whole pass is dropped. Staying quiet
   is no calls.
5. **Stage 2, only when something needs words:** a mumble's word, or a
   memory line. Each is a slot (`react.word`, `remember.text`). One writer
   call fills them all, given the window with Stage 1's decision at its end,
   in whatever time the deadline has left (less 100 ms). A slot the writer
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
| `rules` | The rules' reaction to it, e.g. `cheer size 2` |
| `aside` | Something only the rules handled: a tap, something needing you |
| `decided` | Stage 1's calls, and how it got there (the rule that matched, Jev's answers) |
| `dropped` | Why a pass produced nothing: Stage 1 failed, was late or cancelled, or answered off the menu |
| `wrote` / `write_failed` | Stage 2's values by slot, or why it wrote nothing |
| `ran` | Each call as its action received it, and what the action did |

**The window.** Brains see a window onto the transcript: at most **8
inputs**. When a 9th arrives, the window starts again from the **last 2**,
so Boop still knows what you just said. A new day starts a window of its
own. That's the only rule: nothing is summarized, and the window just moves
its start. The window doesn't restart when memory changes, since every
call puts the current memory at the top.

**How each brain reads it.** The if-else classifier reads only the current
input. Jev gets the window as JSON (§6). The writers get it as text, which
looks like this (from `TranscriptTests`):

```
agent finished · done · claude · jetpack · took 18 min · 14:05 Tuesday
  rules: cheer size 2
  decided: react(feeling: proud, voice: mumble)
  wrote: react.word = finally
  ran: react(feeling: proud, voice: mumble, word: finally)
tapped · 14:07 Tuesday: Boop wiggled
you said · 14:05 Tuesday
  they said: "remember 'the' demo"
  decided: react(feeling: happy, voice: mumble), remember(where: today)
  wrote: nothing
  ran: react(feeling: happy, voice: mumble)
  ran: remember(where: today) (dropped)
```

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
**written** by Stage 2.

| Output | Decided | Written | What it does |
| --- | --- | --- | --- |
| `react` | `feeling`, one of ten; `voice`: `silent` or `mumble` | `word`, only for a mumble: `none` or one of Voice's 40 words ([VOICE.md](VOICE.md) §6) | The feeling's face on the device, and for a mumble a Minion line from Voice with the word. The mumble is dropped in quiet mode or while something needs you; the face still plays |
| `quiet` | `minutes`: 15, 30, 60 or 120 | — | The core's quiet mode: no mumbles, and agent inputs skip the brain |
| `remember` | `where`: `today`, `about_you`, `preference`, `temperament` or `moment` | `text` | A line in that part of memory, under its own rules |

| Feeling | Face | Its mumble sounds |
| --- | --- | --- |
| `happy` | `happy` | happy |
| `excited` | `happy`, size 2 | excited |
| `proud` | `proud` | proud |
| `curious` | `curious` | curious |
| `hopeful` | `love` | hopeful |
| `annoyed` | `side_eye` | annoyed |
| `sad` | `worried` | sad |
| `sleepy` | `sleepy` | sleepy |
| `smug` | `smug` | proud |
| `sulky` | `sulky` | sad |

| `where` | Goes to | Text | Its own rules |
| --- | --- | --- | --- |
| `today` | short-term Notes | ≤ 80 characters | One line, no code, paths or secrets, no duplicates |
| `about_you`, `preference` | long-term About you, Preferences | ≤ 100 | Also no other people's names; refused when the section or file is full |
| `temperament` | long-term Temperament | one sentence, ≤ 120 | Once a day |
| `moment` | long-term Moments | ≤ 80 | One per day reflected on; refused when half or more of its longer words are in an earlier moment |

The core's rules use the same `react` action: any animation for their
instant reactions (a cheer, an oops), and a mumble for working chatter.
Every action checks its arguments against its own definition, so a call
that skips the harness (a rule's) is held to the same rules. A dropped call
is logged with the reason. Forgetting a remembered line is the person's, in
Settings; the brain has no way to.

## 6. The brains

```
Classifier                                   Stage 1
  id                                         e.g. "rules@2", "jev:jev-latest"
  classify(context, menu, deadline) -> calls with their decided arguments, and evidence

Writer                                       Stage 2
  id                                         e.g. "apple:26.4", "none"
  write(context, slots, deadline) -> a value for each slot it filled
```

The context is the input, the memory text and the transcript's window.
Each brain is its own class in `app/BoopKit/Brains/`, with a comment that
says exactly how it behaves.

| Brain | Stage | What it does |
| --- | --- | --- |
| `RulesClassifier` | 1 | **The default.** Plain Swift, no model, always available; reads only the input's fields. Agent started: nothing. Finished `done` in 5 minutes or more: `react(proud, mumble)`; shorter: nothing. Finished `failed`: `react(annoyed, mumble)`, one mumble per failure. You said "shut up", "quiet", "hush", "stop talking" or "keep it down": `quiet` (two hours 120, fifteen 15, half an hour 30, an hour 60, else 30) then `react(sulky, silent)`; "remember" or "note": `react(happy, mumble)` and `remember(today)`; "hello", "hi", "hey" or "morning": `react(happy, mumble)`; "good job", "well done", "nice", "great", "thanks" or "the best": `react(proud, mumble)`; anything else: `react(curious, mumble)`. Whole words only, and the first row that matches wins. New day: nothing, since deciding what lasts needs a model |
| `JevClassifier` | 1 | TypeSafe's `jev-latest` ([docs](https://docs.typesafe.ai/api)), with the person's API key. It doesn't write: it answers typed questions about a state with probabilities, in one request of about 0.2 s. The state is `steering.md`, both memory files, the window's recent inputs (minutes ago, what happened, what you said, what the rules did and what Boop did) and now. The menu becomes questions built from the definitions: a yes/no for each output ("Should Boop react about what just happened?"), a choice for each decided argument with more than one option (`react.feeling`, `react.voice`, `quiet.minutes`), and, when the menu allows several calls told apart by a choice, a yes/no per choice instead (a new day's `remember.about_you`, `remember.moment`, …). Each question is answered on its own, so every argument is asked up front and only a chosen output's are used. A yes is above 0.5; each choice is the most likely one. Only the HTTP status of a failed request is logged |
| `AppleWriter` | 2 | **The default.** Apple's on-device model: private and free. A fresh session each call: its instructions are a short preamble, `steering.md` and both memory files; its prompt is the window as text, then what just happened and what Boop decided, then a line per slot. Guided generation with one property per slot: a word from `none` and its list, or text with its length asked for. There's no option to decline, so it can't answer "stay quiet"; that was Stage 1's job. Guardrails are `permissiveContentTransformations`; a refusal fails the write like any error, marked as a refusal |
| `NoWriter` | 2 | Writes nothing: mumbles have no word, and nothing is remembered. The setting `none`, and what `apple` falls back to when Apple's model can't run at launch |
| `DeepSeekWriter` | 2 | Not built yet: it refuses every write ([FUTURE.md](FUTURE.md)) |

**Settings** (`settings.json`, and "Decides with" and "Writes with" in the
app, [UX.md](UX.md) §7): `classifier` is `rules` or `jev`, `writer` is
`apple`, `none` or `deepseek`, and they take effect on restart. Jev needs
its key, from the Keychain or `BOOP_JEV_KEY`; without one Boop classifies
with the rules. An older `brain` setting becomes the two: `apple` is rules
and Apple's model, `rules` is rules and no writer, `jev` is Jev and Apple's
model.

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
  input, which helps a small model more than extra rules do.

It's modelled on [pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/),
whose rule is "if I don't need it, it won't be built": a short system
prompt, few tools, context kept in plain files, every session logged, and
no MCP, sub-agents or plan mode. pi loops until its model stops calling
tools; Boop's outputs return nothing a model needs, so each stage is a
single call.

## 8. Logging

In debug mode, each pass is logged as one JSON line: the input and its
line, both brains, how many inputs the window held, Stage 1's calls and
evidence, the slots and what was written (and the writer's raw answer),
why anything was dropped or failed, what each action did, and each stage's
latency. Otherwise the app log gets one line per pass: the input kind, the
latency and the outputs that ran, never their arguments:

```
brain you said 812 ms → quiet, react, remember
```

Outside debug mode, the words you said and what the brain wrote never reach
the log.
