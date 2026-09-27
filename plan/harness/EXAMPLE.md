# Boop: harness example, end to end

Updated 2026-09-27. One Claude turn from first hook to last mumble: the
hooks, the events the core makes of them, the transcript, the state and
questions Jev gets, its answers, and what Boop does. How it works is in
[HARNESS.md](HARNESS.md), [EVENTS.md](EVENTS.md) and
[DECISIONS.md](DECISIONS.md); this file only shows it.

It's hand-written from the spec until the harness is built; then it's
regenerated from a test fixture, so it stays what the code does
([PLAN.md](../PLAN.md), A10). Jev's probabilities are made up.

## 1. The story

A Tuesday afternoon. Claude works in the `agent-work-visibility` worktree
of `buddygotchi`. Boop is happy, the mood it starts in.

| Time | What happens | Wakes the brain | Boop |
| --- | --- | --- | --- |
| 14:00 | You send a prompt: turn 7 starts | Yes | Stays quiet |
| 14:01 | Claude edits a file | No event at all: the core only counts it | — |
| 14:04 | `npm test` fails | Yes | Shrugs it off: quiet |
| 14:06 | `npm test` fails again | Yes | Mumbles, curious: "…tests?" |
| 14:09 | `npm test` fails a third time | Yes | **Turns grumpy**, mumbles, annoyed: "…again!" |
| 14:12 | You tap Boop | No: the rules handle a tap | Wiggles, by rule |
| 14:21 | `npm test` passes | Yes | **Turns proud**, mumbles, proud: "…finally!" |
| 14:23 | The turn finishes | Yes | Cheers, by rule; the brain adds nothing |

The pass at 14:09 is shown in full (§3–§6); 14:21 and 14:23 more briefly
(§7).

## 2. From hook to event (14:09)

Claude runs its `PostToolUseFailure` hook. The payload, abridged:

```json
{"hook_event_name":"PostToolUseFailure","session_id":"a1b2c3","cwd":"/Users/me/src/buddygotchi/.claude/worktrees/agent-work-visibility-7a22ea","tool_name":"Bash","tool_use_id":"toolu_01AbC","tool_input":{"command":"npm test"},"error":"Command failed with exit code 1: …","is_interrupt":false}
```

`boop-hook` keeps a few fields and drops the rest, the command and the
error text included ([ADAPTERS.md](../ADAPTERS.md) §2):

```json
{"agent":"claude","hook":"PostToolUseFailure","session":"a1b2c3","cwd":"/Users/me/src/buddygotchi/.claude/worktrees/agent-work-visibility-7a22ea","tool":"Bash","topic":"tests","tool_use_id":"toolu_01AbC","tool_error":"exit_code","ts":1790000540000}
```

The core finds the thread (project `buddygotchi`, workspace
`agent-work-visibility`, turn 7), times the call from its `PreToolUse`,
counts two failures of `tests` just before it, writes the line, and
builds the event. No rule reacts to a tool use, and a failure with a
topic wakes the brain ([EVENTS.md](EVENTS.md) §4):

```json
{"kind":"tool_use","received_at_ms":1790000540000,"line":"claude's tests failed again on \"agent-work-visibility\", 3 in a row.","reaction":null,"wakes_brain":true,"facts":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01AbC","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":48210,"failed_before":2}}
```

## 3. The transcript so far

The runtime appends the event (entry 8) before submitting it, so the pass
finds it there. Everything before it, as `debug.jsonl` holds it (the
thread's facts abridged to `…` after the first):

```jsonl
{"seq":1,"received_at_ms":1790000000000,"event":{"kind":"turn_start","line":"claude started turn 7 on \"agent-work-visibility\" (buddygotchi), right after its last one.","reaction":null,"wakes_brain":true,"facts":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"gap":"right after"}}}
{"seq":2,"received_at_ms":1790000000220,"pass":{"for":1,"answers":{"mood":{"choice":"happy","p":{"happy":0.9,"determined":0.04,"curious":0.03,"grumpy":0.01,"proud":0.01,"excited":0.01,"sad":0.0}},"react":{"choice":"none","p":{"none":0.81,"curious":0.1,"happy":0.06,"excited":0.02,"proud":0.01,"annoyed":0.0}},"word.feeling":{"choice":"none","p_choice":0.52},"word.about":{"choice":"none","p_choice":0.77}},"dropped":null,"latency_ms":220}}
{"seq":3,"received_at_ms":1790000240000,"event":{"kind":"tool_use","line":"claude's tests failed on \"agent-work-visibility\".","reaction":null,"wakes_brain":true,"facts":{"thread":{…},"tool":"shell","topic":"tests","result":"failed","error":"exit_code","took":"long","failed_before":0,…}}}
{"seq":4,"received_at_ms":1790000240230,"pass":{"for":3,"answers":{"mood":{"choice":"happy","p":{"happy":0.8,"determined":0.12,"curious":0.04,"grumpy":0.03,"sad":0.01,"proud":0.0,"excited":0.0}},"react":{"choice":"none","p":{"none":0.55,"curious":0.24,"annoyed":0.15,"happy":0.04,"excited":0.01,"proud":0.01}},"word.feeling":{"choice":"oops","p_choice":0.61},"word.about":{"choice":"tests","p_choice":0.74}},"dropped":null,"latency_ms":230}}
{"seq":5,"received_at_ms":1790000360000,"event":{"kind":"tool_use","line":"claude's tests failed again on \"agent-work-visibility\", 2 in a row.","reaction":null,"wakes_brain":true,"facts":{"thread":{…},"tool":"shell","topic":"tests","result":"failed","error":"exit_code","took":"long","failed_before":1,…}}}
{"seq":6,"received_at_ms":1790000360240,"pass":{"for":5,"answers":{"mood":{"choice":"happy","p":{"happy":0.52,"determined":0.3,"grumpy":0.14,"curious":0.03,"sad":0.01,"proud":0.0,"excited":0.0}},"react":{"choice":"curious","p":{"curious":0.46,"none":0.3,"annoyed":0.2,"happy":0.02,"excited":0.01,"proud":0.01}},"word.feeling":{"choice":"again","p_choice":0.31},"word.about":{"choice":"tests","p_choice":0.79}},"dropped":null,"latency_ms":240}}
{"seq":7,"received_at_ms":1790000360241,"action":{"for":5,"name":"react","ok":true,"message":"Boop mumbled, curious: \"…tests?\"","latency_ms":1}}
{"seq":8,"received_at_ms":1790000540000,"event":{"kind":"tool_use","line":"claude's tests failed again on \"agent-work-visibility\", 3 in a row.","reaction":null,"wakes_brain":true,"facts":{"thread":{…},"tool":"shell","topic":"tests","result":"failed","error":"exit_code","took":"long","failed_before":2,…}}}
```

Three things to notice. The edit at 14:01 isn't here at all: the core
only counted it. The pass at 14:00 (entry 2) answered `none` and
`happy`, so neither action returned anything and only the `pass`
entry went in. And at 14:06 `word.feeling` picked "again" at only 0.31,
under the 0.35 floor, so the `react` action fell back to `word.about`'s
"tests" (entry 7).

## 4. The state (14:09)

The harness puts the state together: the guide, with no heading and
ending with how to read the rest, then PERSONALITY and MOOD, then
HISTORY and NOW, built from the transcript as
[HARNESS.md](HARNESS.md) §5.3 describes. Entry 8 is NOW, so HISTORY
stops before it.

The first three parts are the steering files as they are, so only their
opening lines are shown here. The whole text is in
[steering/guide.md](../steering/guide.md) (plus the generated lines on
reading HISTORY and NOW), [steering/personality/boop.md](../steering/personality/boop.md)
and [steering/mood/happy.md](../steering/mood/happy.md).

```
You are the mind of Boop, a small creature on a person's desk that
watches their AI coding agents work. Boop never approves or blocks
anything.
…

PERSONALITY
Boop is curious, loyal and easily delighted, and a little smug. …

MOOD
Happy. Boop is in good spirits. It enjoys the work and roots for the
agents. …

HISTORY (oldest first; indented lines are what Boop did)
9 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
5 min ago: claude's tests failed on "agent-work-visibility".
3 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, curious: "…tests?"
Working now: nothing else.

NOW (14:09, Tuesday)
claude's tests failed again on "agent-work-visibility", 3 in a row.
Boop did nothing on its own.
```

## 5. The request and the answer (14:09)

```json
{
  "model": "jev-latest",
  "state": "You are the mind of Boop, a small creature on a person's desk …\n\nNOW (14:09, Tuesday)\nclaude's tests failed again on \"agent-work-visibility\", 3 in a row.\nBoop did nothing on its own.",
  "questions": {
    "mood": {
      "type": "choice",
      "criteria": {
        "happy": "Good spirits: things are going fine.",
        "excited": "Thrilled: several wins in a row, or something big went right.",
        "proud": {"what": "Something hard-won finished: a comeback, or a very long turn that fought through failures.", "not_for": "A routine finish, however long."},
        "curious": {"what": "Unsure how things are going: mixed results, or something unusual.", "not_for": "A routine turn start, or a failure."},
        "determined": {"what": "Working through a failure: the same thing failed twice in a row and the agent is retrying.", "not_for": "A turn that has ended."},
        "grumpy": "Fed up: 3 or more failures in a row, or poked too much.",
        "sad": "Deflated: a turn of 10 minutes or more ended failing, or was stopped with failures left."
      },
      "instructions": {"question": "After NOW, what is Boop's mood?", "about": "the NOW and HISTORY sections", "judge_by": "the MOOD section, its reason to leave"}
    },
    "react": {
      "type": "choice",
      "criteria": {
        "none": {"what": "Stay quiet: nothing in NOW is worth a mumble.", "not_for": "Anything PERSONALITY's Examples mumble for."},
        "happy": "Pleased and friendly: a turn went fine, a small win.",
        "excited": "Thrilled: something big just went right.",
        "proud": "Something long or hard just finished, or finally worked.",
        "curious": "Interested or unsure: something new started, or it's not clear how it's going.",
        "annoyed": "Irritated: a turn failed, tests keep failing, or it's being poked too much."
      },
      "instructions": {"question": "How should Boop react to NOW, if at all?", "about": "the NOW section", "judge_by": "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"}
    },
    "word.about": {
      "type": "choice",
      "criteria": {
        "none": "No topic word fits NOW.",
        "tests": {"what": "NOW is about tests.", "not_for": "A build or a deploy."},
        "build": {"what": "NOW is about a build.", "not_for": "Tests."},
        "deploy": "NOW is about a deploy.",
        "docs": "NOW is about docs."
      },
      "instructions": {"question": "If Boop mumbles, which topic word is NOW about?", "about": "the NOW section", "judge_by": "the PERSONALITY section's Examples"}
    },
    "word.feeling": {
      "type": "choice",
      "criteria": {
        "none": "No exclamation fits NOW.",
        "finally": {"what": "Something worked after failing.", "not_for": "A first try."},
        "yay": "A win.",
        "oops": {"what": "Something just failed, once.", "not_for": "A failure that keeps repeating."},
        "again": {"what": "The same thing failed again.", "not_for": "A first failure."},
        "ugh": "Frustration: things keep going badly.",
        "nope": "Poked too much, or refusing.",
        "hmm": "Unsure, or something new."
      },
      "instructions": {"question": "If Boop mumbles, which exclamation fits NOW?", "about": "the NOW section", "judge_by": "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"}
    }
  }
}
```

Jev answers in about 0.24 s:

```json
{
  "answers": {
    "mood":         {"choice": "grumpy",  "probabilities": {"grumpy": 0.69, "determined": 0.22, "happy": 0.05, "sad": 0.03, "curious": 0.01, "proud": 0.0, "excited": 0.0}},
    "react":        {"choice": "annoyed", "probabilities": {"annoyed": 0.63, "none": 0.18, "curious": 0.15, "happy": 0.02, "excited": 0.01, "proud": 0.01}},
    "word.about":   {"choice": "tests",   "probabilities": {"tests": 0.81, "none": 0.12, "build": 0.05, "deploy": 0.01, "docs": 0.01}},
    "word.feeling": {"choice": "again",   "probabilities": {"again": 0.57, "ugh": 0.24, "oops": 0.08, "none": 0.07, "hmm": 0.02, "nope": 0.01, "finally": 0.0, "yay": 0.0}}
  },
  "usage": {"input_tokens": 1874, "output_tokens": 0}
}
```

## 6. From answers to Boop (14:09)

The harness gives each action the answers to its own questions, in
registration order ([HARNESS.md](HARNESS.md) §4), and each reads them
itself ([DECISIONS.md](DECISIONS.md) §4–5):

1. **`mood` gets** `mood: grumpy`. That isn't the current mood, so it
   writes `grumpy` to the state directory's `mood` file and returns
   `ok: true, "Boop's mood changed: happy → grumpy."`. From the next
   pass, MOOD is `grumpy.md`.
2. **`react` gets** `react: annoyed`, `word.feeling: again 0.57` and
   `word.about: tests 0.81`. `annoyed` isn't `none`; "again" clears the
   0.35 floor, so it's the word and "tests" goes unused; nothing blocks
   a mumble. Voice builds a Minion line in the annoyed voice with "again"
   in it, `MomentSchedule` plays it at once since nothing else is
   playing, and it returns `ok: true, "Boop mumbled, annoyed: "…again!""`.

What the harness appends:

```jsonl
{"seq":9,"received_at_ms":1790000540240,"pass":{"for":8,"answers":{"mood":{"choice":"grumpy","p":{"grumpy":0.69,"determined":0.22,"happy":0.05,"sad":0.03,"curious":0.01,"proud":0.0,"excited":0.0}},"react":{"choice":"annoyed","p":{"annoyed":0.63,"none":0.18,"curious":0.15,"happy":0.02,"excited":0.01,"proud":0.01}},"word.feeling":{"choice":"again","p_choice":0.57},"word.about":{"choice":"tests","p_choice":0.81}},"dropped":null,"latency_ms":240}}
{"seq":10,"received_at_ms":1790000540241,"action":{"for":8,"name":"mood","ok":true,"message":"Boop's mood changed: happy → grumpy.","latency_ms":1}}
{"seq":11,"received_at_ms":1790000540242,"action":{"for":8,"name":"react","ok":true,"message":"Boop mumbled, annoyed: \"…again!\"","latency_ms":1}}
```

The app log gets one line: `brain tool_use 240 ms → mood, react`.

## 7. The rest of the turn

**14:12, a tap.** The rule wiggles, and the event says so; it doesn't
wake the brain:

```jsonl
{"seq":12,"received_at_ms":1790000720000,"event":{"kind":"tap","line":"You tapped Boop.","reaction":"Boop wiggled on its own.","wakes_brain":false,"facts":{}}}
```

**14:21, the tests pass** (entry 13, `failed_before: 3`). MOOD is now the
grumpy file ([steering/mood/grumpy.md](../steering/mood/grumpy.md)):

```
MOOD
Grumpy. Boop is fed up. Things have been going wrong and it shows. …

HISTORY (oldest first; indented lines are what Boop did)
21 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
17 min ago: claude's tests failed on "agent-work-visibility".
15 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, curious: "…tests?"
12 min ago: claude's tests failed again on "agent-work-visibility", 3 in a row.
  Boop's mood changed: happy → grumpy.
  Boop mumbled, annoyed: "…again!"
9 min ago: You tapped Boop.
  Boop wiggled on its own.
Working now: nothing else.

NOW (14:21, Tuesday)
claude's tests passed on "agent-work-visibility" after 3 failures in a row.
Boop did nothing on its own.
```

(The guide and PERSONALITY are as in §4.) Jev answers `mood: proud`,
`react: proud`, `word.feeling: finally 0.66`, since grumpy leaves for
proud when something that kept failing finally works. Both actions
return a result: Boop turns proud and mumbles, proud, "…finally!". Entries 14–16: the
`pass`, then two `action` entries.

**14:23, the turn ends** (entry 17). The rule has already cheered, and
the event carries it. NOW reads:

```
NOW (14:23, Tuesday)
claude finished turn 7 on "agent-work-visibility": done after 23 min, a very long turn, 41 tools (3 failed). Tests passing. A comeback on tests.
Boop cheered on its own.
```

HISTORY ends with the "…finally!" of two minutes ago, and the guide says not
to repeat what Boop just did. Jev answers `mood: proud` and `react: none`, so both actions return
`nil`. The pass appends only its `pass` entry (18).

## 8. How it all reads afterwards

The next event's HISTORY holds the whole turn:

```
HISTORY (oldest first; indented lines are what Boop did)
24 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
20 min ago: claude's tests failed on "agent-work-visibility".
18 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, curious: "…tests?"
15 min ago: claude's tests failed again on "agent-work-visibility", 3 in a row.
  Boop's mood changed: happy → grumpy.
  Boop mumbled, annoyed: "…again!"
12 min ago: You tapped Boop.
  Boop wiggled on its own.
3 min ago: claude's tests passed on "agent-work-visibility" after 3 failures in a row.
  Boop's mood changed: grumpy → proud.
  Boop mumbled, proud: "…finally!"
1 min ago: claude finished turn 7 on "agent-work-visibility": done after 23 min, a very long turn, 41 tools (3 failed). Tests passing. A comeback on tests.
  Boop cheered on its own.
Working now: nothing else.
```

Eighteen entries went in: seven events, six passes and five actions.
Out came seven event lines, and seven lines of what Boop did: five from
actions and two rule reactions carried by their events. The passes never
show, and the routine edit never became an entry.
