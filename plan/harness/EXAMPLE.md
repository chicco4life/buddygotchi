# Boop: harness example, end to end

Updated 2026-09-29. One turn of failing tests, from the raw events to
what Boop does: the view events, the state and questions Jev gets, its
answers, and what the actions did. How it works is in
[HARNESS.md](HARNESS.md), [EVENTS.md](EVENTS.md) and
[DECISIONS.md](DECISIONS.md); this file only shows it.

Everything here is real: run 1 of the eval scenario `04-tests-fight-back`
([EVALS.md](../EVALS.md) §4) in a `boopdev eval --runs 1` against
`jev:jev-latest` on 2026-09-29, with the recorded takes and the steering
of that day. Lines are copied from its log
([the whole run](../evidence/2026-09-29-voice-bank/eval-04-debug.jsonl)),
with probabilities rounded to two places and the state left out of the
`pass` lines (`"state":"…"`).

The eval has no device, so its queue ends each reaction `done` at once
([EVALS.md](../EVALS.md) §1): every `react` action's start is followed
straight away by its end. In the app the end comes when the device says
how the moment ended ([DECISIONS.md](DECISIONS.md) §5).

## 1. The story

A Wednesday afternoon. Claude works in the `fix-nav` worktree of
`landing`. Boop starts calm.

| Time | What happens | View event | Jev's answers | Boop |
| --- | --- | --- | --- | --- |
| 14:00 | A turn starts | 1 | calm · none | Stays quiet |
| 14:01 | The tests fail | 2 | annoyed · annoyed, once · frustration 1.00, a sound | **Turns annoyed**, an annoyed face, held once: "Tsk..." |
| 14:03 | They fail again | 3 | determined · determined, once · frustration 0.63, a sound | **Turns determined**, a determined face, held once, saying nothing |
| 14:05 | A third time | 4 | determined · determined, once · retry 0.52, a sound | A determined face, held once, saying nothing |
| 14:07 | They pass | 5 | proud · proud, twice · pride 0.80, a sound | **Turns proud**, a proud face, held twice, saying nothing |

The pass at 14:01 is shown in full (§2–§6), and the silent ones after it
more briefly (§7). Each answer came back in 213–348 ms.

## 2. The events (14:01)

In the app, the failure arrives as Claude's `PreToolUse` and
`PostToolUseFailure` hooks, which `boop-hook` and the adapter turn into
raw `tool` events ([ADAPTERS.md](../ADAPTERS.md) §2–3); the eval hands
the pipeline the same events ([EVALS.md](../EVALS.md) §1). The end:

```json
{"event":{"seq":3,"ts":1791986460000,"source":"claude","type":"tool","phase":"end","specific_type":"PostToolUseFailure","session":"s1","cwd":"/eval/landing/.worktrees/fix-nav","data":{"error":"exit_code","failed":true,"tool":"Bash","topic":"tests"}},"received_at_ms":1791986460000}
```

The view folds it into view event 2, with its line and facts. A failed
check with a topic is notable and nothing needs you, so it wakes the
brain ([EVENTS.md](EVENTS.md) §4, §8). No rule reacts to a tool's end:

```json
{"view":{"facts":{"error":"exit_code","failed_before":0,"result":"failed","thread":{"agent":"claude","name":"fix-nav","project":"landing","session":"s1","turn":1,"workspace":"fix-nav"},"took":"short","took_ms":0,"tool":"shell","tool_name":"Bash","tool_use_id":null,"topic":"tests"},"from":[3],"id":2,"line":"claude's tests failed on \"fix-nav\" (landing).","notes":[],"phase":"end","type":"tool","wakes_brain":true},"received_at_ms":1791986460000}
```

(`took` is `short` because the eval sends a command's start and its
result at the same moment.)

## 3. The state (14:01)

The harness builds the state for view event 2 ([HARNESS.md](HARNESS.md)
§5.3, §6). The guide and PERSONALITY are the steering files as they are
([steering/guide.md](../steering/guide.md),
[steering/personality/boop.md](../steering/personality/boop.md)), so
they're left out here; MOOD is calm's file, then HISTORY and NOW:

```
MOOD
Calm. Boop is settled and content, at rest: nothing much is going on.
Its faces lean calm and happy; a failure gets an annoyed face.
Says little: a word to begin a turn.
Stays calm through routine turns, plain finishes and questions.
Leaves for curious or happy at a poke; happy at kind words to Boop or
a long turn's hard work done; engaged while a long turn works on;
annoyed at a failed check or turn, frustration, or 2 pokes in a row;
excited when a very long turn finishes done or the person thanks the
agent; sad when a very long turn fails, the agent gives up or the
person shares sad news; wounded at rude words to Boop.

HISTORY (oldest first; indented lines add to the line above)
1 min ago: claude started turn 1 on "fix-nav" (landing).

NOW (14:01, Wednesday)
claude's tests failed on "fix-nav" (landing).
Boop did nothing on its own.
```

The quiet pass at 14:00 left nothing under the turn's start: a reaction
that didn't happen isn't in HISTORY.

## 4. The questions (14:01)

Six questions, in one request ([HARNESS.md](HARNESS.md) §7): `mood`,
offering staying calm and calm's moves on the graph, then `react`'s
five ([DECISIONS.md](DECISIONS.md) §3). `say.meaning` is built from the
takes the board has, each option naming the faces that can say it. As
the app's `debug.jsonl` logs it, abridged to four of its twelve options:

```json
{"action":"react","key":"say.meaning","options":[{"name":"none","not_for":null,"what":"Say nothing: nothing in NOW is worth a word or a sound."},…,{"name":"frustration","not_for":"A win.","what":"Something failed or keeps failing: a check, a turn, or the agent giving up. Only these faces can say it: grumpy, annoyed, whiny."},{"name":"retry","not_for":"A first failure.","what":"The same thing again: a retry, or the person saying it's still broken. Only these faces can say it: determined, annoyed, irritated, whiny."}],"text":"If Boop reacts, what does it say about NOW? It says it in its face's mood."}
```

## 5. The answers (14:01)

Jev answered in 229 ms:

```json
{"pass":{"answers":{"mood":{"choice":"annoyed","p":{"annoyed":0.98,"calm":0.02,"curious":0,"engaged":0,"excited":0,"happy":0,"sad":0,"wounded":0}},"react.animation":{"choice":"none","p":{"failure":0.1,"none":0.9,"reply":0,"success":0}},"react.loops":{"choice":"once","p":{"four times":0,"once":0.94,"three times":0.02,"twice":0.04}},"react.mood":{"choice":"annoyed","p":{"annoyed":1,"calm":0,"curious":0,"determined":0,"engaged":0,"excited":0,"grumpy":0,"happy":0,"irritated":0,"none":0,"proud":0,"sad":0,"whiny":0,"wounded":0}},"say.kind":{"choice":"sound","p":{"phrase":0,"sound":0.94,"swear":0.03,"word":0.03}},"say.meaning":{"choice":"frustration","p":{"begin":0,"celebrate":0,"delight":0,"effort":0,"frustration":1,"none":0,"ponder":0,"pride":0,"relief":0,"retry":0,"success":0,"work":0}}},"brain":"jev:jev-latest","dropped":null,"for":3,"latency_ms":229,"now":{"id":2,"line":"claude's tests failed on \"fix-nav\" (landing).","phase":"end","type":"tool"},"questions":["mood","react.mood","react.animation","react.loops","say.meaning","say.kind"],"seen":3,"state":"…"},"received_at_ms":1791986460000}
```

## 6. From answers to Boop (14:01)

The harness gave each action its own answers, in order
([DECISIONS.md](DECISIONS.md) §4–5), and recorded what each did as an
`action` event:

```jsonl
{"event":{"seq":4,"ts":1791986460000,"source":"boop","type":"action","specific_type":"mood","data":{"by":"brain","for":3,"latency_ms":0,"message":"Boop's mood changed: calm → annoyed.","ok":true}},"received_at_ms":1791986460000}
{"event":{"seq":5,"ts":1791986460000,"source":"boop","type":"action","phase":"start","specific_type":"react","data":{"by":"brain","for":3,"latency_ms":0,"message":"Boop made an annoyed face, held once, and said \"Tsk...\".","ok":true}},"received_at_ms":1791986460000}
{"event":{"seq":6,"ts":1791986460000,"source":"boop","type":"action","phase":"end","specific_type":"react","data":{"by":"brain","for":5,"outcome":"done"}},"received_at_ms":1791986460000}
```

1. **`mood` got** `annoyed`, one of calm's moves, so it saved it. From
   the next pass MOOD is annoyed's file, and in the app the device gets
   a `state` with `"mood":"annoyed"` at once.
2. **`react` got** an annoyed face, no finish, held `once`, meaning
   `frustration` at 1.00 (over the 0.35 floor) as a `sound`. Voice looked
   for a take of frustration performed in annoyed, of no finish, as a
   sound: "Tsk..." and "Pfft" fit, and it picked "Tsk..."
   ([VOICE.md](../VOICE.md) §4). Nothing needs you, so it queued the face,
   one loop and the take, `say: {"take":"previous.tsk"}`, with a handle,
   and returned started; the eval's queue ended it `done` at once.

The eval checked this step against `react: annoyed|determined` and
`mood: annoyed`, and it passed.

## 7. The silent passes (14:03–14:07)

The next three passes picked faces with nothing to say for what they
meant, so Boop made its face in silence
([VOICE.md](../VOICE.md) §4):

- **14:03**, the second failure: a determined face meaning
  `frustration` (0.63). Only grumpy, annoyed and whiny can say that, so
  `Boop made a determined face, held once.`
- **14:05**, the third: a determined face meaning `retry` (0.52), as a
  `sound` (0.87). Determined's only retry take is the word "Again", and
  Voice never steps up to a fancier kind than asked, so again nothing.
- **14:07**, the tests passing: a proud face meaning `pride` (0.80).
  Proud's pride take, "Tiny genius", needs a turn that finished a
  success, and a check passing mid-turn isn't one.

HISTORY at 14:05, as Jev read it:

```
HISTORY (oldest first; indented lines add to the line above)
5 min ago: claude started turn 1 on "fix-nav" (landing).
4 min ago: claude's tests failed on "fix-nav" (landing).
  Boop's mood changed: calm → annoyed.
  Boop made an annoyed face, held once, and said "Tsk...".
2 min ago: claude's tests failed on "fix-nav" (landing).
  Boop's mood changed: annoyed → determined.
  Boop made a determined face, held once.
Boop has been determined for 2 min.

NOW (14:05, Wednesday)
claude's tests failed on "fix-nav" (landing).
Boop did nothing on its own.
```

The scenario ends at 14:07 with Boop proud. Twenty raw events went in,
nine of Claude's (the turn's start, and four starts and four ends of a
command) and eleven of Boop's actions, with five view events and five
passes.
