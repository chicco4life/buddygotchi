# Boop: harness and brain

Updated 2026-09-26. How a trigger becomes a brain call, and how the answer
is handed off.

## 1. What this is

The **brain** is a small LLM. The **harness** is the little bit of generic
code around it:

```
 trigger ──► build prompt ──► call the brain ──► check shape ──► hand each tool call
 (from the   steering.md +     one call,          valid JSON,     to its action
  core)      long-term.md +    ≤ 3 tool calls     allowed tools   (say, face, note…)
             short-term.md +                           │
             the trigger text                          └─► log (debug)
```

The harness knows how to build a prompt, call a model and route tool calls.
It doesn't know what any tool does. It never builds Minion speech, writes a
file or talks to the device. That work belongs to the actions
([ARCHITECTURE.md](ARCHITECTURE.md) §3.4), so the harness would work the
same driving something other than Boop.

Each trigger is one call with no conversation history. The memory files are
the only state carried from one call to the next.

## 2. Modelled on pi

[pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) is the
harness to follow. Its rule is "if I don't need it, it won't be built": a
short system prompt, four tools, one API over many model providers, context
kept in plain files, and every session logged. No MCP, sub-agents or plan
mode.

| pi | Boop |
| --- | --- |
| System prompt under 1,000 tokens, plus AGENTS.md | A few lines of preamble, plus `steering.md` |
| Four tools | A handful of actions, at most four offered per trigger |
| `pi-ai`: one API over many providers | The `Brain` interface (§7) |
| Tool arguments validated against schemas | Same. Beyond that the harness checks only the answer's shape and each tool's limits (§3, §5) |
| Plans and to-dos live in files | Memory lives in three Markdown files |
| Sessions saved as inspectable JSON | Every call logged as one JSON line, in debug mode |
| No MCP, sub-agents or plan mode | Same, and no multi-turn loop either |

pi loops until the model stops calling tools, because a coding agent needs
tool results. Boop's tools return nothing the model needs, so every call is
a single turn.

## 3. What the harness does, step by step

1. **Receive a trigger** from the core: a name, a line or two describing
   what happened, the tools allowed, and a deadline.
2. **Wait its turn.** One call runs at a time. A newer trigger replaces one
   that's waiting, and `talk` cancels whatever is running. Whether to send a
   trigger at all is the core's decision.
3. **Build the prompt** in a fixed order (§4), with the memory text supplied
   by the memory store. A tool past its limit (§5) isn't offered.
4. **Call the brain** with the prompt, the allowed tool definitions and the
   deadline.
5. **Check the shape** of the answer: valid JSON, only allowed tools,
   arguments matching their schemas, and at most three calls. If anything
   fails, the whole answer is dropped. The harness doesn't check meaning;
   each action checks its own rules.
6. **Hand off** each tool call to the action that registered it, in order.
   A call that would pass its tool's limit (a second `say` in one answer) is
   dropped instead.
7. **Log** the call: in full in debug mode, otherwise one short line (§8).

At startup, the app gives the harness its tools as a list of
`(definition, handler)` pairs. That's what keeps the harness generic. A
definition is read again for each call, so it can depend on memory
(`forget` offers only the lines there are).

Every brain answers with the same JSON, which the shape check reads:

```json
{"calls":[{"tool":"say","feeling":"proud","word":"finally"}]}
```

An empty `calls` list means staying quiet. Numbers may come as digits in a
string (`"30"`), and a `null` optional argument counts as left out.

## 4. The prompt

The prompt has the same layout every time, with the stable parts first so a
provider can cache them:

```
system:  preamble (3 lines: you are Boop's brain; answer only with tool calls;
         no tool calls means staying quiet)
         steering.md
user:    long-term.md
         short-term.md
         --- now ---
         turn finished · claude · jetpack · topic: tests · took 18 min · 14:05 Tuesday
```

The trigger line carries only what's needed: what happened, the agent,
project and topic, how long it took, the time, and whether Boop is hungry.
A failed turn adds its error class (`error: rate limit`), and a trigger
merged from a burst ends with `· +N more`
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2). For `talk` it carries your words.

The whole prompt fits in about 3,000 tokens. The memory store's line limits
keep the files within budget, so the harness never has to trim. Apple's
on-device model has an 8K context window here (measured 2026-09-25).

| Part | Budget (tokens) |
| --- | --- |
| Preamble + `steering.md` | ≤ 1,000 |
| `long-term.md` | ≤ 800 |
| `short-term.md` | ≤ 600 |
| Trigger line | ≤ 100 |
| Tool definitions | ≤ 400 |

No code, file contents, prompts or transcripts go in. The one exception is
your words on `talk`, which are dropped after the call.

## 5. Triggers

| Trigger | Sent when | Deadline | Tools offered |
| --- | --- | --- | --- |
| `event` | An agent turn starts, finishes or fails | 5 s | `say`, `face` |
| `tap` | You tap Boop | 3 s | `say`, `face` |
| `talk` | You release the push-to-talk button | 4 s | `say`, `face`, `quiet`, `note` |
| `reflect` | Once a day, at the first activity of a new day | Minutes | `remember`, `temperament`, `moment` (not `forget` in v1, ARCHITECTURE.md §11) |

**Limits.** The brain doesn't decide how often Boop talks; the harness
does, in code. Each trigger kind carries a list of tool limits as plain data
(`Trigger.Kind.limits`): at least so long between two runs of the tool that
went through, and line starts where it's never offered. Time is the
trigger's own clock (`ts`), so tests and the pipeline check can move it. A
tool past its limit isn't offered at all, because a small model can't pick a
tool it isn't shown, and nearly always speaks when it can. Only the brain's
calls count; the core's rule mumbles don't.

| Trigger | Tool | Limit |
| --- | --- | --- |
| `event` | `say` | Once every 10 minutes, and never on a turn start |
| `tap` | `say` | Once every 5 minutes |
| `talk`, `reflect` | — | None: talk is the person asking, and reflection doesn't speak |

"Needs you" is not a trigger. That moment belongs to plain rules, so the
brain can't make it slower or different from one time to the next.

## 6. Designing for small models

The brain is assumed to be small. Small models are good at picking from a
short menu and bad at following long, open-ended instructions, so the design
leans on the menu:

- **Few tools:** at most four per trigger.
- **Flat, multiple-choice arguments.** `say` takes a `feeling` from a list
  of eight and an optional `word` from a list of about forty. The only free
  text is a short note or memory line, with a length limit.
- **One step:** one call, up to three tool calls, no follow-up.
- **Easy silence:** an empty answer is valid, and the limits (§5) make
  silence the default for `say` whatever the model would pick.
- **Examples over rules:** `steering.md` shows short examples for each
  trigger, which helps a small model more than extra rules do.

Each action writes its own tool definition. For example, `say` publishes:

```json
{"name":"say","description":"Mumble. Pick a feeling; add one word only if it helps.",
 "parameters":{"feeling":{"enum":["happy","excited","proud","curious","hopeful","annoyed","sad","sleepy"]},
               "word":{"enum":["tests","build","docs","deploy","bug","fix","ship","code","merge","review","yay","…"],"optional":true}}}
```

The word list is Voice's vocabulary ([VOICE.md](VOICE.md) §6). Whatever the
brain picks, `say` and Voice do the rest.

All eight tools, as their actions define them (`app/BoopKit/Actions/`):

| Tool | Arguments | The action's own checks |
| --- | --- | --- |
| `say` | `feeling` (one of 8), `word?` (one of 40) | Dropped in quiet or focus mode or while something needs you. Plays the feeling's face (`happy`, `happy` at size 2 for excited, `proud`, `curious`, `love` for hopeful, `side_eye` for annoyed, `worried` for sad, `sleepy`) under the mumble |
| `face` | `name`: `happy`, `proud`, `smug`, `curious`, `sleepy`, `worried`, `sulky`, `love` or `side_eye` | The core's rules may play any animation through the same action |
| `quiet` | `minutes`: 15, 30, 60 or 120 | — |
| `note` | `text`, at most 80 characters | Memory's rules: one line, no code, paths or secrets, no duplicates |
| `remember` | `text`, at most 100 characters; `kind`: `about_you` or `preference` | Memory's rules, plus no other people's names; refused when the section or file is full |
| `forget` | `text`: one of the lines now under About you or Preferences (the definition is rebuilt for each call; not callable when there are none) | Removes that line. Registered but offered by no trigger in v1 |
| `temperament` | `text`, one sentence of at most 120 characters | Once a day |
| `moment` | `text`, at most 80 characters | One per day reflected on; refused when half or more of its longer words are in an earlier moment |

Every action checks its arguments against its own definition too, so a
call that skips the harness (a rule's) is held to the same rules. A
dropped call is logged with the reason.

## 7. The `Brain` interface

```
Brain
  id                                      e.g. "apple:<os>", "cloud:<model>", "rules@1"
  complete(system, user, tools, deadline) -> [tool call]
```

| Brain | Notes |
| --- | --- |
| Apple on-device | **The default.** Small, private and free. Guided generation with a schema built at runtime: a leading `react` choice (`stay quiet` or `react`, since a small model rarely leaves a list empty on its own), then up to three calls whose choices are constrained. Every list of words to choose from starts with `none`, which leaves an optional argument out or drops the call, because the model otherwise drifts to a list's first entry; lists of numbers (like `quiet`'s minutes) don't. Guardrails are set to `permissiveContentTransformations`; a guardrail refusal is dropped like any brain error (Boop keeps the rule reaction), but marked as a refusal so L5 counts it apart. Text lengths are only asked for, so the shape check still applies. Everything must work well on this |
| Cloud API | Interface only in v1: `cloud:<model>` refuses every call, so Boop keeps its rule reactions. Wiring it to the person's own API key comes later ([FUTURE.md](FUTURE.md)); it should be wittier, with the same tools and limits |
| Rules only | No model. Reads the fallback table from `steering.md` in the system prompt and the trigger from the now section, like any brain. The most specific matching row wins (`Tap, hungry` over `Tap`); "long" means 5 minutes or more. Always available, and used when Apple's model can't run |

The brain in use is pinned, and switching is a setting the person changes.
Every brain gets the same prompt and tools, and every tool call goes through
the same actions. A weaker brain makes Boop less witty, but it can't make it
break the rules.

## 8. Logging

In debug mode, each call is logged as one JSON line: the trigger, the brain,
the full prompt, the raw answer, what the shape check dropped, which actions
ran and what they dropped, and the latency. Otherwise the app log gets one
line per call: the trigger kind, the latency and the names of the tools
that ran, never their arguments. Outside debug mode, the words you said
and what the brain answered never reach the log.
