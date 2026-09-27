# Boop: harness example, end to end

Updated 2026-09-28. One turn of failing tests, from the core's events to
what Boop does: the transcript, the state and questions Jev gets, its
answers, and the actions. How it works is in [HARNESS.md](HARNESS.md),
[EVENTS.md](EVENTS.md) and [DECISIONS.md](DECISIONS.md); this file only
shows it.

Everything here is real: run 1 of the eval scenario
`04-tests-fight-back` ([EVALS.md](../EVALS.md) §4) in a `make eval`
against `jev:jev-latest` on 2026-09-28, with today's code and steering.
Lines are copied from its `debug.jsonl`
([evidence](../evidence/2026-09-28-tonight/loops-pending/eval-debug.jsonl)),
with probabilities rounded to two places and abridged only where marked
`…`. The other two runs made the same picks, each within 0.1.

The eval has no device, so its queue ends each reaction `done` at once
([EVALS.md](../EVALS.md) §1): every `react` action, started
(`"pending":true`), is followed straight away by its `settle`. In the
app the settle comes when the device says how the moment ended
([DECISIONS.md](DECISIONS.md) §5).

## 1. The story

A Wednesday afternoon. Claude works in the `fix-nav` worktree of
`landing`. Boop starts happy.

| Time | What happens | Event | Jev's answers | Boop |
| --- | --- | --- | --- | --- |
| 14:00 | A turn starts | 1 `turn_start` | happy · none | Stays quiet |
| 14:01 | The tests fail | 3 `tool_use` | happy · curious 0.54, once · "tests" 0.83 | A curious face, held once: "…tests!" |
| 14:03 | They fail again | 7 `tool_use` | determined · determined, once · "again" 0.87 | **Turns determined**, a determined face, held once: "…again!" |
| 14:05 | A third time | 12 `tool_use` | grumpy · grumpy, once · "again" 0.97 | **Turns grumpy**, a grumpy face, held once: "…again!" |
| 14:07 | They pass | 17 `tool_use` | proud · proud, three times · "finally" 0.99 | **Turns proud**, a proud face, held three times: "…finally!" |

The pass at 14:05 is shown in full (§2–§6), and the one at 14:07 more
briefly (§7). Each answer came back in 191–387 ms.

## 2. The event (14:05)

In the app, the third failure arrives as Claude's `PostToolUseFailure`
hook, which `boop-hook` and the adapter turn into an `activity` event
with `tool: Bash`, `topic: tests`, `failed: true` and
`tool_error: exit_code` ([ADAPTERS.md](../ADAPTERS.md) §2–3). The eval
hands the core that event directly ([EVALS.md](../EVALS.md) §1).

The core finds the thread, counts two failures of `tests` in a row just
before this one, and writes the line. A failure with a topic is notable,
nothing needs you and there's a brain, so it wakes the brain
([EVENTS.md](EVENTS.md) §4, §6). No rule reacts to a tool use:

```json
{"event":{"facts":{"error":"exit_code","failed_before":2,"result":"failed","thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"kind":"tool_use","line":"claude's tests failed again on \"fix-nav\" (landing), 3 in a row.","reaction":null,"wakes_brain":true},"received_at_ms":1791986700000,"seq":12}
```

(`took` is `short` because the eval sends a command's start and its
result at the same moment.)

## 3. The transcript so far

The harness appended the event as entry 12. Before it (passes' `state`
left out, and the thread abridged after the first):

```jsonl
{"event":{"facts":{"gap":null,"thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"}},"kind":"turn_start","line":"claude started turn 1 on \"fix-nav\" (landing).","reaction":null,"wakes_brain":true},"received_at_ms":1791986400000,"seq":1}
{"pass":{"answers":{"mood":{"choice":"happy","p":{"curious":0,"determined":0,"excited":0,"grumpy":0,"happy":1,"proud":0,"sad":0}},"react":{"choice":"none","p":{"curious":0.11,"determined":0,"excited":0,"grumpy":0,"happy":0,"none":0.89,"proud":0,"sad":0}},"react.loops":{"choice":"once","p":{"four times":0.01,"once":0.96,"three times":0,"twice":0.03}},"word.about":{"choice":"none","p":{"build":0,"deploy":0,"docs":0,"none":1,"tests":0}},"word.feeling":{"choice":"none","p":{"again":0,"finally":0,"hmm":0.01,"none":0.99,"nope":0,"oops":0,"ugh":0,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":1,"latency_ms":387,"questions":["mood","react","react.loops","word.feeling","word.about"],"seen":1,"state":"…"},"received_at_ms":1791986400000,"seq":2}
{"event":{"facts":{"error":"exit_code","failed_before":0,"result":"failed","thread":{…},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"kind":"tool_use","line":"claude's tests failed on \"fix-nav\" (landing).","reaction":null,"wakes_brain":true},"received_at_ms":1791986460000,"seq":3}
{"pass":{"answers":{"mood":{"choice":"happy","p":{"curious":0.06,"determined":0.02,"excited":0,"grumpy":0,"happy":0.92,"proud":0,"sad":0}},"react":{"choice":"curious","p":{"curious":0.54,"determined":0.14,"excited":0,"grumpy":0.06,"happy":0,"none":0.26,"proud":0,"sad":0}},"react.loops":{"choice":"once","p":{"four times":0,"once":0.96,"three times":0,"twice":0.04}},"word.about":{"choice":"tests","p":{"build":0,"deploy":0,"docs":0,"none":0.17,"tests":0.83}},"word.feeling":{"choice":"none","p":{"again":0,"finally":0,"hmm":0.06,"none":0.53,"nope":0,"oops":0.41,"ugh":0,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":3,"latency_ms":196,"questions":["mood","react","react.loops","word.feeling","word.about"],"seen":3,"state":"…"},"received_at_ms":1791986460000,"seq":4}
{"action":{"for":3,"latency_ms":1,"message":"Boop made a curious face, held once, and mumbled \"…tests!\"","name":"react","ok":true,"pending":true},"received_at_ms":1791986460000,"seq":5}
{"received_at_ms":1791986460000,"seq":6,"settle":{"end":"done","for":5}}
{"event":{"facts":{"error":"exit_code","failed_before":1,"result":"failed","thread":{…},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"kind":"tool_use","line":"claude's tests failed again on \"fix-nav\" (landing), 2 in a row.","reaction":null,"wakes_brain":true},"received_at_ms":1791986580000,"seq":7}
{"pass":{"answers":{"mood":{"choice":"determined","p":{"curious":0.01,"determined":0.98,"excited":0,"grumpy":0,"happy":0.01,"proud":0,"sad":0}},"react":{"choice":"determined","p":{"curious":0.02,"determined":0.89,"excited":0,"grumpy":0.08,"happy":0,"none":0.01,"proud":0,"sad":0}},"react.loops":{"choice":"once","p":{"four times":0.04,"once":0.71,"three times":0.01,"twice":0.24}},"word.about":{"choice":"tests","p":{"build":0,"deploy":0,"docs":0,"none":0.01,"tests":0.99}},"word.feeling":{"choice":"again","p":{"again":0.87,"finally":0,"hmm":0.01,"none":0.1,"nope":0,"oops":0,"ugh":0.02,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":7,"latency_ms":191,"questions":["mood","react","react.loops","word.feeling","word.about"],"seen":7,"state":"…"},"received_at_ms":1791986580000,"seq":8}
{"action":{"for":7,"latency_ms":1,"message":"Boop's mood changed: happy → determined.","name":"mood","ok":true},"received_at_ms":1791986580000,"seq":9}
{"action":{"for":7,"latency_ms":0,"message":"Boop made a determined face, held once, and mumbled \"…again!\"","name":"react","ok":true,"pending":true},"received_at_ms":1791986580000,"seq":10}
{"received_at_ms":1791986580000,"seq":11,"settle":{"end":"done","for":10}}
```

Four things to notice:

- **A quiet pass leaves only a `pass` entry.** At 14:00 Jev answered the
  current mood and `none`, so both actions returned `nil`, and the
  `react.loops` pick went unused.
- **No exclamation, so the topic.** At 14:01 `word.feeling` was `none`
  at 0.53, so the mumble took `word.about`'s "tests" at 0.83
  ([DECISIONS.md](DECISIONS.md) §5).
- **Each reaction is started, then settled** (entries 5–6 and 10–11), as
  above.
- **Two in a row is determined,** as happy's file says it leaves for
  ([steering/mood/happy.md](../steering/mood/happy.md)).

## 4. The state (14:05)

The harness builds the state for entry 12 ([HARNESS.md](HARNESS.md)
§5.3, §6). The first three parts are the steering files as they are, so
they're cut to a few lines here: the whole text is in
[steering/guide.md](../steering/guide.md),
[steering/personality/boop.md](../steering/personality/boop.md) and
[steering/mood/determined.md](../steering/mood/determined.md).

```
You are the mind of Boop, a small creature on a person's desk that
watches their AI coding agents work. Boop never approves or blocks
anything.
…
How to read HISTORY and NOW:
…
- Turns are short (under 15 s), long (under a minute) or very long.

PERSONALITY
Boop is curious, loyal and easily delighted, and a little smug. …
Examples:
…
- NOW: claude's tests failed again on "api", 3 in a row.
  → grumpy, "again", once
…

MOOD
Determined. Boop is working through a failure with the agent while it
retries: something fights back, but it isn't fed up.
…
Leaves this mood for proud when what kept failing finally works, for
grumpy when failures keep piling up (3 or more in a row), and for sad
when the turn ends still failing.

HISTORY (oldest first; indented lines are what Boop did)
5 min ago: claude started turn 1 on "fix-nav" (landing).
4 min ago: claude's tests failed on "fix-nav" (landing).
  Boop made a curious face, held once, and mumbled "…tests!"
2 min ago: claude's tests failed again on "fix-nav" (landing), 2 in a row.
  Boop's mood changed: happy → determined.
  Boop made a determined face, held once, and mumbled "…again!"
Working now: nothing else.

NOW (14:05, Wednesday)
claude's tests failed again on "fix-nav" (landing), 3 in a row.
Boop did nothing on its own.
```

NOW matches one of PERSONALITY's Examples almost word for word, and
MOOD's reason to leave for grumpy. The quiet pass at 14:00 doesn't show,
the reactions have settled so their lines carry no brackets, and
"Working now" leaves out NOW's own thread.

## 5. The request (14:05)

The request isn't logged, but it's built from the logged state and the
five questions ([HARNESS.md](HARNESS.md) §7). Sent compact; here with the
state cut and one question of five in full:

```json
{
  "model": "jev-latest",
  "questions": {
    "mood": {…},
    "react": {…},
    "react.loops": {
      "criteria": {
        "four times": {"not_for": "A single win or failure.", "what": "The biggest moments: a hard-won finish, or a failure that keeps coming back."},
        "once": "A small moment: the usual.",
        "three times": "A big moment, such as a comeback.",
        "twice": {"not_for": "Routine work.", "what": "A moment that stands out."}
      },
      "instructions": {"about": "the NOW section", "judge_by": "the PERSONALITY and MOOD sections, PERSONALITY's Examples first", "question": "If Boop reacts, how long does it hold the face?"},
      "type": "choice"
    },
    "word.about": {…},
    "word.feeling": {…}
  },
  "state": "You are the mind of Boop, …\n\nNOW (14:05, Wednesday)\nclaude's tests failed again on \"fix-nav\" (landing), 3 in a row.\nBoop did nothing on its own."
}
```

## 6. From answers to Boop (14:05)

Jev answered in 325 ms. The harness recorded the pass, then gave each
action its own answers, in order ([DECISIONS.md](DECISIONS.md) §4–5):

```jsonl
{"pass":{"answers":{"mood":{"choice":"grumpy","p":{"curious":0,"determined":0.01,"excited":0,"grumpy":0.99,"happy":0,"proud":0,"sad":0}},"react":{"choice":"grumpy","p":{"curious":0,"determined":0.01,"excited":0,"grumpy":0.99,"happy":0,"none":0,"proud":0,"sad":0}},"react.loops":{"choice":"once","p":{"four times":0.23,"once":0.64,"three times":0.01,"twice":0.12}},"word.about":{"choice":"tests","p":{"build":0,"deploy":0,"docs":0,"none":0,"tests":1}},"word.feeling":{"choice":"again","p":{"again":0.97,"finally":0,"hmm":0,"none":0.01,"nope":0,"oops":0,"ugh":0.02,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":12,"latency_ms":325,"questions":["mood","react","react.loops","word.feeling","word.about"],"seen":12,"state":"…"},"received_at_ms":1791986700000,"seq":13}
{"action":{"for":12,"latency_ms":1,"message":"Boop's mood changed: determined → grumpy.","name":"mood","ok":true},"received_at_ms":1791986700000,"seq":14}
{"action":{"for":12,"latency_ms":0,"message":"Boop made a grumpy face, held once, and mumbled \"…again!\"","name":"react","ok":true,"pending":true},"received_at_ms":1791986700000,"seq":15}
{"received_at_ms":1791986700000,"seq":16,"settle":{"end":"done","for":15}}
```

1. **`mood` got** `grumpy`, which isn't the current mood, so it saved
   it. From the next pass MOOD is the grumpy file, and in the app the
   device gets a `state` with `"mood":"grumpy"` at once.
2. **`react` got** `grumpy`, held `once` (at 0.64, with `four times` at
   0.23), "again" at 0.97 and "tests" at 1.00. The exclamation clears the
   0.35 floor, so it's the word and "tests" goes unused. Nothing needs
   you, so Voice builds a line in annoyed's voice, grumpy's, with
   "again", and queues it with the face and one loop, and a handle. It
   returns started. In the app the moment plays on the device, which
   says when it has ended; the eval's queue ends the handle at once, so
   the settle follows.

In the app, `boop.log` would get `brain tool_use 325 ms → mood, react`.
The eval checked this step against `react: grumpy`,
`word: again|tests|ugh` and `mood: grumpy`, and it passed.

## 7. The pass (14:07)

The tests pass, entry 17 (`failed_before: 3`). MOOD is now the grumpy
file ([steering/mood/grumpy.md](../steering/mood/grumpy.md)), and HISTORY
shows what the last three passes did:

```
MOOD
Grumpy. Boop is fed up. Things have been going wrong and it shows.
…
Leaves this mood for proud when something that kept failing finally
works, and for happy when a long turn finishes cleanly.

HISTORY (oldest first; indented lines are what Boop did)
7 min ago: claude started turn 1 on "fix-nav" (landing).
6 min ago: claude's tests failed on "fix-nav" (landing).
  Boop made a curious face, held once, and mumbled "…tests!"
4 min ago: claude's tests failed again on "fix-nav" (landing), 2 in a row.
  Boop's mood changed: happy → determined.
  Boop made a determined face, held once, and mumbled "…again!"
2 min ago: claude's tests failed again on "fix-nav" (landing), 3 in a row.
  Boop's mood changed: determined → grumpy.
  Boop made a grumpy face, held once, and mumbled "…again!"
Working now: nothing else.

NOW (14:07, Wednesday)
claude's tests passed on "fix-nav" (landing) after 3 failures in a row.
Boop did nothing on its own.
```

Jev answered in 230 ms, sure of every pick: `mood: proud` at 1.00,
`react: proud` at 0.97, `react.loops: three times` at 0.89,
`word.feeling: finally` and `word.about: tests` at 0.99. A comeback is a
big moment, as boop's Example says, so the face holds three loops.
Grumpy leaves straight for proud; no rule holds a mood.

```jsonl
{"action":{"for":17,"latency_ms":1,"message":"Boop's mood changed: grumpy → proud.","name":"mood","ok":true},"received_at_ms":1791986820000,"seq":19}
{"action":{"for":17,"latency_ms":1,"message":"Boop made a proud face, held three times, and mumbled \"…finally!\"","name":"react","ok":true,"pending":true},"received_at_ms":1791986820000,"seq":20}
{"received_at_ms":1791986820000,"seq":21,"settle":{"end":"done","for":20}}
```

The scenario ends here. Twenty-one entries went in: five events, five
passes, seven actions and four settles. In the app, the turn's end would
come next as a `turn_end` with a comeback on tests, carrying the rule's
cheer.
