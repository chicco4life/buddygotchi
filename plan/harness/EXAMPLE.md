# Boop: harness example, end to end

Updated 2026-09-27. One turn of failing tests, from the core's events to
what Boop does: the transcript, the state and questions Jev gets, its
answers, and the actions. How it works is in [HARNESS.md](HARNESS.md),
[EVENTS.md](EVENTS.md) and [DECISIONS.md](DECISIONS.md); this file only
shows it.

Everything here is real: run 1 of the eval scenario
`04-tests-fight-back` ([EVALS.md](../EVALS.md) §4) in a `make eval`
against `jev:jev-latest` on 2026-09-27, with today's code and steering.
Lines are copied from its `debug.jsonl`
([evidence](../evidence/2026-09-27-example-run/)), abridged only where marked `…`.
The other two runs answered the same, within a few hundredths.

## 1. The story

A Wednesday afternoon. Claude works in the `fix-nav` worktree of
`landing`. Boop starts happy.

| Time | What happens | Event | Jev's answers | Boop |
| --- | --- | --- | --- | --- |
| 14:00 | A turn starts | 1 `turn_start` | happy · none | Stays quiet |
| 14:01 | The tests fail | 3 `tool_use` | happy · none | Shrugs it off |
| 14:03 | They fail again | 5 `tool_use` | determined · annoyed · "again" 0.97 | **Turns determined**, mumbles annoyed: "…again!" |
| 14:05 | A third time | 9 `tool_use` | grumpy · annoyed · "again" 0.88 | **Turns grumpy**, mumbles annoyed: "…again!" |
| 14:07 | They pass | 13 `tool_use` | proud · proud · "finally" 1.00 | **Turns proud**, mumbles proud: "…finally!" |

The pass at 14:05 is shown in full (§2–§6), and the one at 14:07 more
briefly (§7). Each answer came back in 187–232 ms.

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
{"event":{"facts":{"error":"exit_code","failed_before":2,"result":"failed","thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"kind":"tool_use","line":"claude's tests failed again on \"fix-nav\" (landing), 3 in a row.","reaction":null,"wakes_brain":true},"received_at_ms":1791986700000,"seq":9}
```

(`took` is `short` because the eval sends a command's start and its
result at the same moment.)

## 3. The transcript so far

The harness appended the event as entry 9. Before it (passes' `state`
left out, and the thread abridged after the first):

```jsonl
{"event":{"facts":{"gap":null,"thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"}},"kind":"turn_start","line":"claude started turn 1 on \"fix-nav\" (landing).","reaction":null,"wakes_brain":true},"received_at_ms":1791986400000,"seq":1}
{"pass":{"answers":{"mood":{"choice":"happy","p":{"curious":0,"determined":0,"excited":0,"grumpy":0,"happy":1,"proud":0,"sad":0}},"react":{"choice":"none","p":{"annoyed":0,"curious":0.04,"excited":0,"happy":0,"none":0.96,"proud":0}},"word.about":{"choice":"none","p":{"build":0,"deploy":0,"docs":0,"none":1,"tests":0}},"word.feeling":{"choice":"none","p":{"again":0,"finally":0,"hmm":0.01,"none":0.99,"nope":0,"oops":0,"ugh":0,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":1,"latency_ms":214,"questions":["mood","react","word.feeling","word.about"],"state":"…"},"received_at_ms":1791986400000,"seq":2}
{"event":{"facts":{"error":"exit_code","failed_before":0,"result":"failed","thread":{…},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"kind":"tool_use","line":"claude's tests failed on \"fix-nav\" (landing).","reaction":null,"wakes_brain":true},"received_at_ms":1791986460000,"seq":3}
{"pass":{"answers":{"mood":{"choice":"happy","p":{"curious":0.04,"determined":0.06,"excited":0,"grumpy":0,"happy":0.9,"proud":0,"sad":0}},"react":{"choice":"none","p":{"annoyed":0.11,"curious":0.13,"excited":0,"happy":0,"none":0.76,"proud":0}},"word.about":{"choice":"tests","p":{"build":0,"deploy":0,"docs":0,"none":0.01,"tests":0.99}},"word.feeling":{"choice":"oops","p":{"again":0,"finally":0,"hmm":0.02,"none":0.3,"nope":0,"oops":0.68,"ugh":0,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":3,"latency_ms":213,"questions":["mood","react","word.feeling","word.about"],"state":"…"},"received_at_ms":1791986460000,"seq":4}
{"event":{"facts":{"error":"exit_code","failed_before":1,"result":"failed","thread":{…},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"kind":"tool_use","line":"claude's tests failed again on \"fix-nav\" (landing), 2 in a row.","reaction":null,"wakes_brain":true},"received_at_ms":1791986580000,"seq":5}
{"pass":{"answers":{"mood":{"choice":"determined","p":{"curious":0,"determined":0.99,"excited":0,"grumpy":0,"happy":0.01,"proud":0,"sad":0}},"react":{"choice":"annoyed","p":{"annoyed":0.93,"curious":0.01,"excited":0,"happy":0,"none":0.06,"proud":0}},"word.about":{"choice":"tests","p":{"build":0,"deploy":0,"docs":0,"none":0,"tests":1}},"word.feeling":{"choice":"again","p":{"again":0.97,"finally":0,"hmm":0,"none":0.02,"nope":0,"oops":0,"ugh":0.01,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":5,"latency_ms":197,"questions":["mood","react","word.feeling","word.about"],"state":"…"},"received_at_ms":1791986580000,"seq":6}
{"action":{"for":5,"latency_ms":1,"message":"Boop's mood changed: happy → determined.","name":"mood","ok":true},"received_at_ms":1791986580000,"seq":7}
{"action":{"for":5,"latency_ms":1,"message":"Boop mumbled, annoyed: \"…again!\"","name":"react","ok":true},"received_at_ms":1791986580000,"seq":8}
```

Three things to notice:

- **Quiet passes leave only a `pass` entry.** At 14:00 and 14:01 Jev
  answered the current mood and `none`, so both actions returned `nil`.
- **The words don't matter without a mumble.** At 14:01 Jev picked
  "oops" at 0.68, but `react` was `none`, so nothing played.
- **Two in a row is determined,** as happy's file says it leaves for
  ([steering/mood/happy.md](../steering/mood/happy.md)).

## 4. The state (14:05)

The harness builds the state for entry 9 ([HARNESS.md](HARNESS.md)
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
  → annoyed, "again"
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
2 min ago: claude's tests failed again on "fix-nav" (landing), 2 in a row.
  Boop's mood changed: happy → determined.
  Boop mumbled, annoyed: "…again!"
Working now: nothing else.

NOW (14:05, Wednesday)
claude's tests failed again on "fix-nav" (landing), 3 in a row.
Boop did nothing on its own.
```

NOW matches one of PERSONALITY's Examples almost word for word, and
MOOD's reason to leave for grumpy. The passes at 14:00 and 14:01 don't
show, and "Working now" leaves out NOW's own thread.

## 5. The request (14:05)

The request isn't logged, but it's built from the logged state and the
four questions ([HARNESS.md](HARNESS.md) §7). Sent compact; here with the
state cut and one question of four in full:

```json
{
  "model": "jev-latest",
  "questions": {
    "mood": {…},
    "react": {…},
    "word.about": {…},
    "word.feeling": {
      "criteria": {
        "again": {"not_for": "A first failure.", "what": "The same thing failed again."},
        "finally": {"not_for": "A first try.", "what": "Something worked after failing."},
        "hmm": "Unsure, or something new.",
        "none": "No exclamation fits NOW.",
        "nope": "Poked too much, or refusing.",
        "oops": {"not_for": "A failure that keeps repeating.", "what": "Something just failed, once."},
        "ugh": "Frustration: things keep going badly.",
        "yay": "A win."
      },
      "instructions": {"about": "the NOW section", "judge_by": "the PERSONALITY and MOOD sections, PERSONALITY's Examples first", "question": "If Boop mumbles, which exclamation fits NOW?"},
      "type": "choice"
    }
  },
  "state": "You are the mind of Boop, …\n\nNOW (14:05, Wednesday)\nclaude's tests failed again on \"fix-nav\" (landing), 3 in a row.\nBoop did nothing on its own."
}
```

## 6. From answers to Boop (14:05)

Jev answered in 187 ms. The harness recorded the pass, then gave each
action its own answers, in order ([DECISIONS.md](DECISIONS.md) §4–5):

```jsonl
{"pass":{"answers":{"mood":{"choice":"grumpy","p":{"curious":0,"determined":0.01,"excited":0,"grumpy":0.99,"happy":0,"proud":0,"sad":0}},"react":{"choice":"annoyed","p":{"annoyed":0.99,"curious":0,"excited":0,"happy":0,"none":0.01,"proud":0}},"word.about":{"choice":"tests","p":{"build":0,"deploy":0,"docs":0,"none":0,"tests":1}},"word.feeling":{"choice":"again","p":{"again":0.88,"finally":0,"hmm":0,"none":0.02,"nope":0,"oops":0,"ugh":0.1,"yay":0}}},"brain":"jev:jev-latest","dropped":null,"for":9,"latency_ms":187,"questions":["mood","react","word.feeling","word.about"],"state":"…"},"received_at_ms":1791986700000,"seq":10}
{"action":{"for":9,"latency_ms":0,"message":"Boop's mood changed: determined → grumpy.","name":"mood","ok":true},"received_at_ms":1791986700000,"seq":11}
{"action":{"for":9,"latency_ms":0,"message":"Boop mumbled, annoyed: \"…again!\"","name":"react","ok":true},"received_at_ms":1791986700000,"seq":12}
```

1. **`mood` got** `grumpy`, which isn't the current mood, so it saved
   it. From the next pass MOOD is the grumpy file, and in the app the
   device gets a `state` with `"mood":"grumpy"` at once.
2. **`react` got** `annoyed`, "again" at 0.88 and "tests" at 1.00. The
   exclamation clears the 0.35 floor, so it's the word and "tests" goes
   unused. Nothing needs you, so Voice builds an annoyed line with
   "again" and queues it. In the app it plays on the device; the eval's
   queue goes nowhere.

In the app, `boop.log` would get `brain tool_use 187 ms → mood, react`.
The eval checked this step against `react: annoyed`,
`word: again|tests|ugh` and `mood: grumpy`, and it passed.

## 7. The pass (14:07)

The tests pass, entry 13 (`failed_before: 3`). MOOD is now the grumpy
file ([steering/mood/grumpy.md](../steering/mood/grumpy.md)), and HISTORY
shows what the last two passes did:

```
MOOD
Grumpy. Boop is fed up. Things have been going wrong and it shows.
…
Leaves this mood for proud when something that kept failing finally
works, and for happy when a long turn finishes cleanly.

HISTORY (oldest first; indented lines are what Boop did)
7 min ago: claude started turn 1 on "fix-nav" (landing).
6 min ago: claude's tests failed on "fix-nav" (landing).
4 min ago: claude's tests failed again on "fix-nav" (landing), 2 in a row.
  Boop's mood changed: happy → determined.
  Boop mumbled, annoyed: "…again!"
2 min ago: claude's tests failed again on "fix-nav" (landing), 3 in a row.
  Boop's mood changed: determined → grumpy.
  Boop mumbled, annoyed: "…again!"
Working now: nothing else.

NOW (14:07, Wednesday)
claude's tests passed on "fix-nav" (landing) after 3 failures in a row.
Boop did nothing on its own.
```

Jev answered in 232 ms, sure of every pick: `mood: proud`,
`react: proud`, `word.feeling: finally`, `word.about: tests`, each 1.00.
Grumpy leaves straight for proud; no rule holds a mood.

```jsonl
{"action":{"for":13,"latency_ms":0,"message":"Boop's mood changed: grumpy → proud.","name":"mood","ok":true},"received_at_ms":1791986820000,"seq":15}
{"action":{"for":13,"latency_ms":0,"message":"Boop mumbled, proud: \"…finally!\"","name":"react","ok":true},"received_at_ms":1791986820000,"seq":16}
```

The scenario ends here. Sixteen entries went in: five events, five
passes and six actions. In the app, the turn's end would come next as a
`turn_end` with a comeback on tests, carrying the rule's cheer.
