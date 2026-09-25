# Boop: harness and brain

Draft 4 · 2026-09-25. Part of the [architecture](ARCHITECTURE.md). This page
covers how a trigger becomes a brain call and how the answer is handed off.
Context layout and compaction get their own pass later.

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
([ARCHITECTURE.md](ARCHITECTURE.md) §3.4). So the harness would work the
same if it drove something other than Boop.

Each trigger is one call with no conversation history. The memory files are
the only state carried from one call to the next.

## 2. Modelled on pi

[pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) is the
model to follow. Its rule is "if I don't need it, it won't be built". It has
a short system prompt, four tools, one API over many model providers,
context kept in plain files, and every session logged. It has no MCP,
sub-agents or plan mode.

| pi | Boop |
| --- | --- |
| System prompt under 1,000 tokens, plus AGENTS.md | A few lines of preamble, plus `steering.md` |
| Four tools | A handful of actions, at most four offered per trigger |
| `pi-ai`: one API over many providers | The `Brain` interface (§7) |
| Tool arguments validated against schemas | Same, and that's the only check the harness makes |
| Plans and to-dos live in files | Memory lives in three Markdown files |
| Sessions saved as inspectable JSON | Every call logged as one JSON line in debug mode |
| No MCP, no sub-agents, no plan mode | Same, and no multi-turn loop either |

pi loops until the model stops calling tools, because a coding agent needs
tool results. Boop's tools return nothing the model needs, so every call is
a single turn.

## 3. What the harness does, step by step

1. **Receive a trigger** from the core: a name, a line or two describing
   what happened, the tools allowed, and a deadline.
2. **Wait its turn.** One call runs at a time. A newer trigger replaces one
   that's waiting, and `talk` cancels whatever is running. That is the
   harness's only scheduling rule. Deciding *whether* to send a trigger at
   all (quiet mode, something needs you, merging bursts) is the core's job.
3. **Build the prompt** in a fixed order (§4).
4. **Call the brain** with the prompt, the allowed tool definitions and the
   deadline.
5. **Check the shape** of the answer: valid JSON, only allowed tool names,
   arguments matching their schemas, and at most three calls. If anything
   fails, the whole answer is dropped. The harness doesn't check meaning,
   because each action checks its own rules.
6. **Hand off** each tool call to the action that registered it, in order.
7. **Log** the call in debug mode.

At startup, the app gives the harness its tools as a list of
`(definition, handler)` pairs. That's what keeps the harness generic.

## 4. The prompt

The prompt has the same layout every time. The stable parts come first, so
a provider can cache them.

```
system:  preamble (3 lines: you are Boop's brain; answer only with tool calls;
         no tool calls means staying quiet)
         steering.md
user:    long-term.md
         short-term.md
         --- now ---
         turn finished · claude · jetpack · took 18 min · 14:05 Tuesday
```

**Budget:** the whole prompt fits in about 3,000 tokens. Apple's on-device
model has an 8K context window on this Mac (measured 2026-09-25), which
leaves plenty of room.

| Part | Budget (tokens) |
| --- | --- |
| Preamble + `steering.md` | ≤ 1,000 |
| `long-term.md` | ≤ 800 |
| `short-term.md` | ≤ 600 |
| Trigger text | ≤ 100 |
| Tool definitions | ≤ 400 |

The memory store keeps the files inside their budgets through its line
limits, so the harness never has to trim anything.

No code, file contents, prompts or transcripts go in. The one exception is
your words on `talk`, which are dropped after the call.

## 5. Triggers

The core sends four triggers. More can come later.

| Trigger | Sent when | Deadline | Tools offered |
| --- | --- | --- | --- |
| `event` | An agent turn starts, finishes or fails | 5 s | `say`, `face`, `note` |
| `tap` | You tap Boop | 3 s | `say`, `face` |
| `talk` | You release the push-to-talk button | 4 s | `say`, `face`, `quiet`, `note` |
| `reflect` | Nightly, on power | Minutes | `remember`, `forget`, `temperament`, `moment` |

"Needs you" is not a trigger. That moment belongs to plain rules, so the
brain can't make it slower or different from one time to the next.

## 6. Designing for small models

The brain is assumed to be small, such as Apple's on-device model. Small
models are good at picking from a short menu and bad at following long,
open-ended instructions, so the design leans on the menu:

- **Few tools:** at most four per trigger.
- **Flat, multiple-choice arguments.** `say` takes a `feeling` from a list
  of eight and an optional `word` from a list of about forty. The only free
  text is a short `note` or memory line, with a length limit.
- **One step:** one call, up to three tool calls, no follow-up.
- **Easy silence:** an empty answer is valid, and common.
- **Examples over rules:** `steering.md` shows one or two short examples per
  trigger, which helps a small model more than extra rules do.

Each action writes and owns its tool definition, which is what the brain
sees. For example, the `say` action publishes:

```json
{"name":"say","description":"Mumble. Pick a feeling; add one word only if it helps.",
 "parameters":{"feeling":{"enum":["happy","proud","curious","annoyed","sad","sleepy","hopeful","excited"]},
               "word":{"enum":["tests","build","docs","bug","deploy","done","finally","yay","oops","hmm","food","…"],"optional":true}}}
```

The word list is Voice's vocabulary. Whatever the brain picks, the `say`
action and Voice do the rest.

## 7. The `Brain` interface

```
Brain
  id                                      e.g. "apple:<os>", "cloud:<model>@<version>", "rules@1"
  complete(system, user, tools, deadline) -> [tool call]
```

| Brain | Notes |
| --- | --- |
| Apple on-device | **The default.** Small, private and free. Guided generation means answers always match the schema. Everything must work well on this |
| Cloud API | Optional: the person's own API key. Wittier, with the same tools and limits |
| Rules only | No model. Answers each trigger from the fallback table in `steering.md`. Always available |

The brain in use is pinned, and switching is a setting the person changes.
Every brain gets the same prompt and the same tools, and every tool call
goes through the same actions. A weaker brain makes Boop less witty, but it
can't make it break the rules.

## 8. Logging

In debug mode, each call is logged as one JSON line: the trigger, the
brain, the full prompt, the raw answer, what the shape check dropped, which
actions ran and what they dropped, and the latency. Otherwise nothing is
written to disk, because `talk` entries contain what you said.

## 9. Later

- The exact prompt layout and caching.
- Compaction: the files are already bounded and `short-term.md` resets
  nightly. What's still open is how reflection condenses a day.
- Richer triggers, such as returning after a long break or a periodic
  check-in.
- A replay set of recorded triggers to compare brains before pinning one.
