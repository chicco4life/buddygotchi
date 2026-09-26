# Boop: harness and brain

Updated 2026-09-26. How a trigger becomes a brain call, and how the answer
is handed off.

## 1. What this is

The **brain** decides how Boop reacts: a small language model, a "system
one" model that only answers questions (Jev), or plain rules. The
**harness** is the little bit of generic code around it:

```
 trigger ──► situation + menu ──► brain.decide ──► check calls ──► hand each tool call
 (from the   what happened,       one call,        allowed tools,   to its action
  core)      memory, recent       ≤ 3 tool calls   arguments fit    (say, face, note…)
             turns; the tools                           │
             and their limits                           └─► log (debug)
```

The input and output are typed. The harness hands every brain the same
situation and menu and gets back tool calls; how a model sees the situation
(a text prompt, JSON state, questions) is that brain's business (§7). The
harness knows how to build the situation, call a brain and route tool
calls. It doesn't know what any tool does, or what kind of model is
deciding. It never builds Minion speech, writes a
file or talks to the device. That work belongs to the actions
([ARCHITECTURE.md](ARCHITECTURE.md) §3.4), so the harness would work the
same driving something other than Boop.

Event, tap and talk calls share a short conversation (§4): each one sends
Boop's last few turns with the brain, so it can follow a back-and-forth
and not repeat itself. Reflection is a call on its own. Beyond the
conversation, the memory files are the only state carried from one call to
the next.

## 2. Modelled on pi

[pi](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) is the
harness to follow. Its rule is "if I don't need it, it won't be built": a
short system prompt, four tools, one API over many model providers, context
kept in plain files, and every session logged. No MCP, sub-agents or plan
mode.

| pi | Boop |
| --- | --- |
| System prompt under 1,000 tokens, plus AGENTS.md | A few lines of preamble, plus `steering.md` |
| Four tools | A handful of actions: the same four offered to every event, tap and talk call, three to reflection |
| `pi-ai`: one API over many providers | The `Brain` interface (§7): one typed call, whatever the model |
| Tool arguments validated against schemas | Same. Beyond that the harness checks only the answer's shape and each tool's limits (§3, §5) |
| Plans and to-dos live in files | Memory lives in three Markdown files |
| The context is the session's messages, compacted when full | A short conversation of recent turns, never compacted: it starts over (§4) |
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
3. **Build the situation and menu** (§4): the trigger, the memory text
   supplied by the memory store and the conversation's earlier turns; the
   tools offered and a line for each one past its limit (§5). Event, tap
   and talk are offered the same tools every time.
4. **Call the brain** with the situation, the menu and the deadline. A
   language model gets them as the text prompt (§4); other brains take them
   as they need (§7).
5. **Check the calls:** only offered tools, arguments matching their
   schemas, and at most three calls. A language model's answer must first
   be valid JSON in the answer format below. If anything fails, the whole
   answer is dropped. The harness doesn't check meaning; each action checks
   its own rules.
6. **Hand off** each tool call to the action that registered it, in order.
   A call to a tool past its limit is dropped instead, whether the prompt
   named the limit or an earlier call in the same answer used it up.
7. **Remember** the turn (§4): for event, tap and talk, the trigger, its
   limit lines and the calls that ran join the conversation. A refused, failed or badly
   shaped answer starts the conversation over instead; a late or cancelled
   one changes nothing.
8. **Log** the call: in full in debug mode, otherwise one short line (§8).

At startup, the app gives the harness its tools as a list of
`(definition, handler)` pairs. That's what keeps the harness generic. A
definition is read again for each call, so it can depend on memory
(`forget` offers only the lines there are).

Language models answer with this JSON, which their shape check reads:

```json
{"calls":[{"tool":"say","feeling":"proud","word":"finally"}]}
```

An empty `calls` list means staying quiet. Numbers may come as digits in a
string (`"30"`), and a `null` optional argument counts as left out.

## 4. The situation and the prompt

The harness keeps the conversation as typed turns: each one is a trigger,
the limit lines it was shown and the calls that ran. The situation for a
call is the trigger, the memory text and those turns, whatever the brain.
A language model gets it as the text prompt below, rendered from the turns
the same way every call; Jev gets it as JSON state (§7).

The prompt has the same layout every time, with the stable parts first so a
provider can cache them:

```
system:  preamble (3 lines: you are Boop's brain; answer only with tool calls;
         no tool calls means staying quiet)
         steering.md
earlier: the conversation's exchanges, oldest first (none for reflection)
user:    long-term.md      only in a conversation's first message,
         short-term.md     and in every reflection
         --- now ---
         turn finished · claude · a · took 12 s · 09:01 Tuesday
         say limit: once every 10 min on event, next in 9 min
         quiet limit: only on talk
         note limit: only on talk
```

**The conversation.** Event, tap and talk calls share one. Its first
message carries the memory files; later messages are only the now section.
Each earlier turn is shown as the message it was sent as and the calls that
ran, in the answer format (§3): calls dropped by a limit or an action are left
out, and an answer where nothing ran is `{"calls":[]}`. So each request
starts with the one before it, which a provider can cache.

There is no compaction. The conversation starts over, empty, when:

- its opening changes: `steering.md`, either memory file or a tool
  definition. The core writes a Happened line to `short-term.md` just
  before the trigger for a turn that took 30 seconds or more and for every
  failed turn, so most such events start over;
- it already holds 4 turns;
- the request as text would pass 5,000 tokens, estimated at four bytes a
  token (the same for every brain, which keeps Jev's state small too);
- an answer is refused, fails or has a bad shape.

It lives in memory only and is gone when the app quits. Reflection is a call
on its own; it neither sees nor joins the conversation.

The trigger line carries only what's needed: what happened, the agent,
project and topic, how long it took, the time, and whether Boop is hungry.
A failed turn adds its error class (`error: rate limit`), and a trigger
merged from a burst ends with `· +N more`
([ARCHITECTURE.md](ARCHITECTURE.md) §3.2). For `talk` it carries your words.

A conversation's first prompt fits in about 3,000 tokens. The memory store's
line limits keep the files within budget, and the conversation's own limits
keep later requests under 5,000, so the harness never has to trim. Apple's
on-device model has an 8K context window here (measured 2026-09-25).

| Part | Budget (tokens) |
| --- | --- |
| Preamble + `steering.md` | ≤ 1,000 |
| `long-term.md` | ≤ 800 |
| `short-term.md` | ≤ 600 |
| Trigger line | ≤ 100 |
| Tool definitions | ≤ 400 |

No code, file contents, prompts or transcripts go in. The one exception is
your words on `talk`, which stay in the conversation until it starts over. With
Jev (§7) the situation leaves the Mac: it goes to TypeSafe with each call,
your words included.

## 5. Triggers

| Trigger | Sent when | Deadline | Tools allowed |
| --- | --- | --- | --- |
| `event` | An agent turn starts, finishes or fails | 5 s | `say`, `face` |
| `tap` | You tap Boop | 3 s | `say`, `face` |
| `talk` | You release the push-to-talk button | 4 s | `say`, `face`, `quiet`, `note` |
| `reflect` | Once a day, at the first activity of a new day | Minutes | `remember`, `temperament`, `moment` (not `forget` in v1, ARCHITECTURE.md §11) |

Event, tap and talk calls are all offered `say`, `face`, `quiet` and `note`,
so the tools never change within a conversation. A tool outside a trigger's
allowed list is shown as a limit (`quiet limit: only on talk`). Reflection
is offered its own list.

**Limits.** The brain doesn't decide how often Boop talks; the harness
does, in code. Each trigger kind carries a list of tool limits as plain data
(`Trigger.Kind.limits`): at least so long between two runs of the tool that
went through, and line starts where it never runs. Time is the trigger's
own clock (`ts`), so tests and the pipeline check can move it. A tool past
its limit is still offered, so the tool list stays the same, but the now
section names the limit (`say limit: once every 10 min on event, next in 9
min`, `say limit: not on turn started`) and the harness drops any call to
it. Only the brain's calls count; the core's rule mumbles don't.

| Trigger | Tool | Limit |
| --- | --- | --- |
| `event` | `say` | Once every 10 minutes, and never on a turn start |
| `tap` | `say` | Once every 5 minutes |
| `event`, `tap` | `quiet`, `note` | Only on `talk` |
| `talk`, `reflect` | — | None: talk is the person asking, and reflection doesn't speak |

"Needs you" is not a trigger. That moment belongs to plain rules, so the
brain can't make it slower or different from one time to the next.

## 6. Designing for small models

The brain is assumed to be small. Small models are good at picking from a
short menu and bad at following long, open-ended instructions, so the design
leans on the menu:

- **Few tools:** four for event, tap and talk, three for reflection.
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
  id                                      e.g. "apple:<os>", "jev:jev-latest", "rules@1"
  decide(situation, menu, deadline) -> decision (tool calls, and the raw answer for the log)

TextBrain: Brain                          a language model
  complete(system, history, user, tools, deadline) -> answer JSON

Writer                                    fills in words for a call another brain chose
  write(tool, situation, deadline) -> tool call or nothing
```

A text brain gets the situation as the prompt (§4) and answers with the
answer JSON (§3); the shared text adapter builds one and checks the other.
It sends `system`, each earlier exchange in `history` and then `user`, in
that order and unchanged, so every request starts with the one before.

| Brain | Notes |
| --- | --- |
| Apple on-device | **The default.** Small, private and free. Guided generation with a schema built at runtime: a leading `react` choice (`stay quiet` or `react`, since a small model rarely leaves a list empty on its own), then up to three calls whose choices are constrained. Every list of words to choose from starts with `none`, which leaves an optional argument out or drops the call, because the model otherwise drifts to a list's first entry; lists of numbers (like `quiet`'s minutes) don't. Guardrails are set to `permissiveContentTransformations`; a guardrail refusal is dropped like any brain error (Boop keeps the rule reaction), but marked as a refusal so L5 counts it apart. Text lengths are only asked for, so the shape check still applies. Each call builds a fresh session from the conversation, showing earlier answers in its own `react`/`calls` shape. Everything must work well on this |
| System one (Jev) | TypeSafe's `jev-latest` ([docs](https://docs.typesafe.ai/api)), with the person's own API key; setting `jev`. It doesn't write: it answers typed questions about a state with probabilities, in one request of about 0.2 s. The state is the situation as JSON: `steering.md`, both memory files, the recent turns (minutes ago, what happened, what Boop did) and now. The menu becomes questions: an `act` choice (`stay_quiet` or each open tool it can fill), a choice for each argument of those tools (`none` first for an optional one), and a yes/no for each open tool that needs words (`note`). Jev answers each question on its own, so every argument is asked up front and only the chosen tool's are used. The most likely `act` wins. A yes above 0.5 has the writer (Apple's model, as a `Writer`: that tool only, and it must call it) write the call, after Jev's own; the rules can't write, so with them there's no note. Reflection offers nothing Jev can fill, so the writer's brain decides it alone. A limited tool isn't an option at all. Only the HTTP status of a failed request is logged. With no key, Boop uses what `apple` gives |
| Cloud API | Interface only in v1: `cloud:<model>` refuses every call, so Boop keeps its rule reactions. Wiring it to the person's own API key comes later ([FUTURE.md](FUTURE.md)); it should be wittier, with the same tools and limits, and send the conversation in order so the provider's prompt cache applies |
| Rules only | No model. Matches the fallback table in `steering.md` against the trigger itself and ignores the history. It leaves out calls to tools past a limit. The most specific matching row wins (`Tap, hungry` over `Tap`); "long" means 5 minutes or more. Always available, and used when Apple's model can't run |

The brain in use is pinned, and switching is a setting the person changes.
Every brain gets the same situation and menu, and every tool call goes through
the same actions. A weaker brain makes Boop less witty, but it can't make it
break the rules.

## 8. Logging

In debug mode, each call is logged as one JSON line: the trigger, the brain,
the situation as the text prompt (system prompt and new message), how many
earlier turns were sent, the raw answer (a model's JSON; Jev's answers with
their probabilities, then what the writer wrote; the rules' calls), what the shape check dropped, which actions
ran and what they dropped, and the latency. Otherwise the app log gets one
line per call: the trigger kind, the latency and the names of the tools
that ran, never their arguments. Outside debug mode, the words you said
and what the brain answered never reach the log.
