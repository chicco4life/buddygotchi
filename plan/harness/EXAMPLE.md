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
of `buddygotchi`. Boop is cheerful.

| Time | What happens | Wakes the brain | Boop |
| --- | --- | --- | --- |
| 14:00 | You send a prompt: turn 7 starts | Yes | Stays quiet |
| 14:01 | Claude edits a file | No: a routine tool use | — |
| 14:04 | `npm test` fails | Yes | Shrugs it off: quiet |
| 14:06 | `npm test` fails again | Yes | Mumbles, curious: "…tests?" |
| 14:09 | `npm test` fails a third time | Yes | **Turns grumpy**, mumbles, annoyed: "…again!" |
| 14:12 | You tap Boop | No: an aside | Wiggles, by rule |
| 14:21 | `npm test` passes | Yes | **Turns cheerful**, mumbles, proud: "…finally!" |
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
counts two failures of `tests` just before it, and builds the event. No
rule reacts to a tool use, and a failure with a topic wakes the brain
([EVENTS.md](EVENTS.md) §4):

```json
{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"tool_use":{"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01AbC","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":48210,"failed_before":2}},"automatic_reaction":"none","woke_brain":true}
```

## 3. The transcript so far

The runtime appends the event (entry 9) before submitting it, so the pass
finds it there. Everything before it, as `debug.jsonl` holds it (thread
fields abridged to `…` after the first):

```jsonl
{"seq":1,"received_at_ms":1790000000000,"event":{"thread":{"name":"agent-work-visibility","agent":"claude","subagent":null,"turn":7,"project":"buddygotchi","workspace":"agent-work-visibility","session":"a1b2c3"},"detail":{"turn_start":{"resumed":false,"gap":"right after"}},"automatic_reaction":"none","woke_brain":true}}
{"seq":2,"received_at_ms":1790000000220,"pass":{"for":1,"answers":{"mood":{"choice":"cheerful","p":{"cheerful":0.94,"grumpy":0.06}},"react":{"choice":"none","p":{"none":0.81,"curious":0.1,"happy":0.06,"excited":0.02,"proud":0.01,"annoyed":0.0}},"word.about":{"choice":"none","p_choice":0.77},"word.feeling":{"choice":"none","p_choice":0.52}},"calls":[],"dropped":null,"latency_ms":220}}
{"seq":3,"received_at_ms":1790000060000,"event":{"thread":{…},"detail":{"tool_use":{"tool":"edit","tool_name":"Edit","tool_use_id":"toolu_01Aa1","topic":null,"result":"ok","error":null,"took":"short","took_ms":120,"failed_before":0}},"automatic_reaction":"none","woke_brain":false}}
{"seq":4,"received_at_ms":1790000240000,"event":{"thread":{…},"detail":{"tool_use":{"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01Bb2","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":47900,"failed_before":0}},"automatic_reaction":"none","woke_brain":true}}
{"seq":5,"received_at_ms":1790000240230,"pass":{"for":4,"answers":{"mood":{"choice":"cheerful","p":{"cheerful":0.9,"grumpy":0.1}},"react":{"choice":"none","p":{"none":0.55,"curious":0.24,"annoyed":0.15,"happy":0.04,"excited":0.01,"proud":0.01}},"word.about":{"choice":"tests","p_choice":0.74},"word.feeling":{"choice":"oops","p_choice":0.61}},"calls":[],"dropped":null,"latency_ms":230}}
{"seq":6,"received_at_ms":1790000360000,"event":{"thread":{…},"detail":{"tool_use":{"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01Cc3","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":49300,"failed_before":1}},"automatic_reaction":"none","woke_brain":true}}
{"seq":7,"received_at_ms":1790000360240,"pass":{"for":6,"answers":{"mood":{"choice":"cheerful","p":{"cheerful":0.78,"grumpy":0.22}},"react":{"choice":"curious","p":{"curious":0.46,"none":0.3,"annoyed":0.2,"happy":0.02,"excited":0.01,"proud":0.01}},"word.about":{"choice":"tests","p_choice":0.79},"word.feeling":{"choice":"again","p_choice":0.31}},"calls":[{"react":{"feeling":"curious","word":"tests"}}],"dropped":null,"latency_ms":240}}
{"seq":8,"received_at_ms":1790000360241,"boop":{"for":6,"by":"brain","action":"react","feeling":"curious","word":"tests"}}
{"seq":9,"received_at_ms":1790000540000,"event":{"thread":{…},"detail":{"tool_use":{"tool":"shell","tool_name":"Bash","tool_use_id":"toolu_01AbC","topic":"tests","result":"failed","error":"exit_code","took":"long","took_ms":48210,"failed_before":2}},"automatic_reaction":"none","woke_brain":true}}
```

Two things to notice. Entry 3, the edit, didn't wake the brain, so it
will never have a line. And at 14:06 (entry 7) `word.feeling` picked
"again" at only 0.31, under the 0.35 floor, so the word fell back to
`word.about`'s "tests".

## 4. The state (14:09)

The harness puts the six sections together (READING, then the three
static files, then HISTORY and NOW, built from the transcript as
[HARNESS.md](HARNESS.md) §4.3 describes). Entry 9 is NOW, so HISTORY
stops before it:

```
READING
HISTORY and NOW describe what's happening around Boop, one line each.
- HISTORY is what already happened, oldest first. Each line starts with
  how long ago it was. Lines indented under it are what Boop did about it.
- The last line of HISTORY lists the other threads still working.
- NOW is the one thing to react to, headed with the time. Its second line
  is what Boop already did on its own.
- "On its own" means one of Boop's fixed reflexes, not a choice.
Words the lines use:
- claude and codex are the person's coding agents. "claude's tests"
  means tests that claude ran.
- A thread is one conversation with an agent. It's written as its name
  in quotes, then its project in brackets: "fix-nav" (landing) is the
  thread fix-nav in the project landing. The name is the workspace the
  agent works in, so two threads in one project have different names.
  The project is left out when it's the same as the name.
- A turn is one request to a thread, from the person's prompt to the
  agent's answer, numbered within its thread. It ends done, failed, or
  stopped (the person interrupted it).
- Tests, build, deploy and docs are what an agent's command or edit was
  about. Failed means the command ended with an error.
- "N in a row" counts failures of the same thing in that thread. A
  comeback is something that passed after failing.
- A short turn is under 15 s, a long one up to a minute, a very long one
  more.

GUIDE
You decide how Boop reacts to what's happening. Boop is a small creature
on a person's desk that watches their AI coding agents work. Boop never
approves or blocks anything.
Boop already reacts on its own: it cheers when a turn finishes, wiggles
when tapped, and alerts when an agent needs the person. You only decide
whether it adds a mumble: its own gibberish, in a feeling, with at most
one real word. You also decide whether its mood changes.
How to choose:
- PERSONALITY and MOOD are who Boop is right now. Judge by them.
- React to NOW, not to older lines. Staying quiet is always fine. Don't
  repeat what Boop just did.
- A mumble is about NOW: its feeling and word should fit it.
- Boop's mood and its mumble go together. A mood changes only when NOW
  gives MOOD's reason to leave it, and then the mumble should fit that
  change: a grumpy Boop doesn't gush, and a cheerful one doesn't sulk
  over one failure.

PERSONALITY
Boop is curious, loyal and easily delighted, and a little smug. It
watches the agents' work like a sport: thrilled by wins, openly grumpy
about failures, always on the person's side, never mean about them.
It speaks up when something stands out, and stays quiet during routine
work.
Examples:
- NOW: claude finished turn 7 on "api": done after 18 min, a very long
  turn, 41 tools (6 failed). A comeback on tests.
  → proud, "finally"
- NOW: claude's tests failed again on "api", 3 in a row.
  → annoyed, "again"
- NOW: claude started turn 2 on "api", right after its last one.
  → none
- NOW: claude finished turn 3 on "api": done after 8 s, a short turn.
  → none
- NOW: You poked Boop 5 times in 3 s.
  → annoyed, "nope"
- NOW: Nothing has happened for 1 hour.
  → none

MOOD
Cheerful. Boop is in good spirits. It enjoys the work and roots for the
agents.
Leans happy and excited, and proud for a hard-won finish. A single
failure gets a shrug: quiet, or curious. Annoyed only when failures
repeat.
Mumbles at wins and at anything that stands out.
Words it likes: yay, finally.
Leaves this mood (for grumpy) when failures pile up, 3 or more in a row
or a very long turn that fails, or when it's poked again and again.

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
  "state": "GUIDE\nYou decide how Boop reacts to what's happening. …\n\nNOW (14:09, Tuesday)\nclaude's tests failed again on \"agent-work-visibility\", 3 in a row.\nBoop did nothing on its own.",
  "questions": {
    "mood": {
      "type": "choice",
      "criteria": {
        "cheerful": "Good spirits: things are going fine, or a struggle just ended well.",
        "grumpy": "Fed up: failures have piled up, or it's been poked too much."
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
    "mood":         {"choice": "grumpy",  "probabilities": {"grumpy": 0.69, "cheerful": 0.31}},
    "react":        {"choice": "annoyed", "probabilities": {"annoyed": 0.63, "none": 0.18, "curious": 0.15, "happy": 0.02, "excited": 0.01, "proud": 0.01}},
    "word.about":   {"choice": "tests",   "probabilities": {"tests": 0.81, "none": 0.12, "build": 0.05, "deploy": 0.01, "docs": 0.01}},
    "word.feeling": {"choice": "again",   "probabilities": {"again": 0.57, "ugh": 0.24, "oops": 0.08, "none": 0.07, "hmm": 0.02, "nope": 0.01, "finally": 0.0, "yay": 0.0}}
  },
  "usage": {"input_tokens": 1874, "output_tokens": 0}
}
```

## 6. From answers to Boop (14:09)

The harness reads each answer as its action declared
([DECISIONS.md](DECISIONS.md) §4):

| Question | Answer | Read as |
| --- | --- | --- |
| `mood` | `grumpy` | Not the current mood: `mood(grumpy)` |
| `react` | `annoyed` | A feeling: Boop mumbles |
| `word.feeling` | `again`, 0.57 | Over 0.35: the word is "again" |
| `word.about` | `tests`, 0.81 | Recorded; a line has one real word |

It hands the calls over, `mood` first:

1. **`mood(grumpy)`.** The mood hasn't changed in the last 10 minutes, so
   the action writes `grumpy` to the state directory's `mood` file. From
   the next pass, MOOD is `grumpy.md`.
2. **`react(annoyed, "again")`.** Voice builds a Minion line in the
   annoyed voice with "again" in it, and `MomentSchedule` plays it at
   once, since nothing else is playing.

What's appended:

```jsonl
{"seq":10,"received_at_ms":1790000540240,"pass":{"for":9,"answers":{"mood":{"choice":"grumpy","p":{"grumpy":0.69,"cheerful":0.31}},"react":{"choice":"annoyed","p":{"annoyed":0.63,"none":0.18,"curious":0.15,"happy":0.02,"excited":0.01,"proud":0.01}},"word.about":{"choice":"tests","p_choice":0.81},"word.feeling":{"choice":"again","p_choice":0.57}},"calls":[{"mood":{"to":"grumpy"}},{"react":{"feeling":"annoyed","word":"again"}}],"dropped":null,"latency_ms":240}}
{"seq":11,"received_at_ms":1790000540241,"boop":{"for":9,"by":"brain","action":"mood","from":"cheerful","to":"grumpy"}}
{"seq":12,"received_at_ms":1790000540242,"boop":{"for":9,"by":"brain","action":"react","feeling":"annoyed","word":"again"}}
```

The app log gets one line: `brain tool_use 240 ms → mood, react`.

## 7. The rest of the turn

**14:12, a tap.** An aside, never a pass. The rule wiggles:

```jsonl
{"seq":13,"received_at_ms":1790000720000,"aside":{"tap":{}}}
{"seq":14,"received_at_ms":1790000720001,"boop":{"for":13,"by":"automatic","action":"wiggle"}}
```

**14:21, the tests pass** (entry 15, `failed_before: 3`). MOOD is now the
grumpy file:

```
MOOD
Grumpy. Boop is fed up. Things have been going wrong and it shows.
Leans annoyed. A win gets a grudging happy or proud, never excited.
Quieter than when cheerful: mumbles at failures and at clear wins, and
ignores routine.
Words it likes: ugh, again, nope, and a grudging finally.
Leaves this mood (for cheerful) when something that kept failing
finally works, a long turn finishes cleanly, or nothing has happened for
an hour.

HISTORY (oldest first; indented lines are what Boop did)
21 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
17 min ago: claude's tests failed on "agent-work-visibility".
15 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, curious: "…tests?"
12 min ago: claude's tests failed again on "agent-work-visibility", 3 in a row.
  Boop's mood changed: cheerful → grumpy.
  Boop mumbled, annoyed: "…again!"
9 min ago: You tapped Boop.
  Boop wiggled on its own.
Working now: nothing else.

NOW (14:21, Tuesday)
claude's tests passed on "agent-work-visibility" after 3 failures in a row.
Boop did nothing on its own.
```

(READING, GUIDE and PERSONALITY are as in §4.) Jev answers `mood: cheerful`,
`react: proud`, `word.feeling: finally 0.66`. The last mood change was 12
minutes ago, over the 10-minute limit, so both run: Boop turns cheerful
and mumbles, proud, "…finally!". Entries 16–18: the `pass`, then two
`boop` entries.

**14:23, the turn ends** (entry 19). The rule cheers first (entry 20).
NOW reads:

```
NOW (14:23, Tuesday)
claude finished turn 7 on "agent-work-visibility": done after 23 min, a very long turn, 41 tools (3 failed). Tests passing. A comeback on tests.
Boop already cheered on its own.
```

HISTORY ends with the "…finally!" of two minutes ago, and GUIDE says not
to repeat what Boop just did. Jev answers `mood: cheerful` (already
cheerful: no call) and `react: none`. The pass appends only its `pass`
entry (21).

## 8. How it all reads afterwards

The next event's HISTORY holds the whole turn:

```
HISTORY (oldest first; indented lines are what Boop did)
24 min ago: claude started turn 7 on "agent-work-visibility" (buddygotchi), right after its last one.
20 min ago: claude's tests failed on "agent-work-visibility".
18 min ago: claude's tests failed again on "agent-work-visibility", 2 in a row.
  Boop mumbled, curious: "…tests?"
15 min ago: claude's tests failed again on "agent-work-visibility", 3 in a row.
  Boop's mood changed: cheerful → grumpy.
  Boop mumbled, annoyed: "…again!"
12 min ago: You tapped Boop.
  Boop wiggled on its own.
3 min ago: claude's tests passed on "agent-work-visibility" after 3 failures in a row.
  Boop's mood changed: grumpy → cheerful.
  Boop mumbled, proud: "…finally!"
1 min ago: claude finished turn 7 on "agent-work-visibility": done after 23 min, a very long turn, 41 tools (3 failed). Tests passing. A comeback on tests.
  Boop cheered on its own.
Working now: nothing else.
```

Twenty-one entries went in; seven lines of events and asides and seven
of what Boop did came out. The routine edit and the six passes never
show.
