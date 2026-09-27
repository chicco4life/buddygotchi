# Boop: harness decisions

Updated 2026-09-27. What Boop decides when the brain wakes: the static
sections that steer it, and its actions, each with its questions and its
body. The contract every action follows, and what the harness does for
it, is in [HARNESS.md](HARNESS.md) §4; the events are in
[EVENTS.md](EVENTS.md), and actions only ever see their lines in HISTORY
and NOW, never their facts.

## 1. What Boop decides

Two actions, registered in this order:

| Action | Decides | Its questions |
| --- | --- | --- |
| `mood` | Whether Boop's mood changes, and to what | `mood` |
| `react` | Whether Boop mumbles, in which feeling, and with which real word | `react`, `word.feeling`, `word.about` |

All four questions go in one request. Jev answers each on its own
([HARNESS.md](HARNESS.md) §7), so `mood` and `react` are both judged
against the current mood: on a pass that changes the mood, the mumble is
still judged by the old one. The guide asks for the two to fit together, and
the evals check how often they don't.

## 2. The static sections

What the three static sections of the state say
([HARNESS.md](HARNESS.md) §6). Each is a file in `plan/steering/`, and
its examples are written in the state's own lines.

### 2.1 The guide

`plan/steering/guide.md`: what Boop is, what it can't do and how to
choose. The same for every personality and mood. How to read HISTORY and
NOW isn't in the file: the harness adds it after the guide
([HARNESS.md](HARNESS.md) §6.1). The guide opens the state, with no heading.

```
You are the mind of Boop, a small creature on a person's desk that
watches their AI coding agents work. Boop never approves or blocks
anything.
Boop already reacts on its own: it cheers when a turn finishes, wiggles
when tapped, and alerts when an agent needs the person. You only decide
whether it adds a mumble: its own gibberish, in a feeling, with at most
one real word. You also decide whether its mood changes.
How to choose:
- PERSONALITY and MOOD are who Boop is right now. Judge by them.
- React to NOW, not to older lines. How often Boop speaks up is
  PERSONALITY's call. Don't repeat what Boop just did.
- A mumble is about NOW: its feeling and word should fit it.
- Boop's mood and its mumble go together. A mood changes only when NOW
  gives MOOD's reason to leave it, and then the mumble should fit that
  change: a grumpy Boop doesn't gush, and a cheerful one doesn't sulk
  over one failure.
```

### 2.2 PERSONALITY

`plan/steering/personality/<name>.md`, picked by `personality` in
`settings.json` and applied from the next event. **Personalities replace
modes:** chatty, normal and calm are gone, and how much Boop speaks up is
its personality's to say.

A personality file has two parts:

- **Settings,** a front-matter block the core reads for its own rules
  ([BEHAVIORS.md](../BEHAVIORS.md) §6): which finished turns get the
  rule's cheer, how often working chatter plays, and which tool uses wake
  the brain ([EVENTS.md](EVENTS.md) §4). It never reaches Jev.
- **The text,** which becomes the PERSONALITY section: who this buddy
  is, how often it speaks up, and its Examples, what it would decide for
  typical NOWs.

There are two:

| Personality | For | `cheer` | `chatter` | `tool_uses` |
| --- | --- | --- | --- | --- |
| `boop` (the default) | Everyday use | `every` finished turn | every 120–240 s | `notable` |
| `chatter` | Debugging: reacts to everything, over the top, so every pass is easy to see | `every` | every 30–60 s | `all` |

**`plan/steering/personality/boop.md`:**

```
---
cheer: every
chatter: 120-240
tool_uses: notable
---
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
```

**`plan/steering/personality/chatter.md`:**

```
---
cheer: every
chatter: 30-60
tool_uses: all
---
PERSONALITY
Boop is wildly over the top. Everything is the most exciting or the most
outrageous thing that has ever happened. It reacts to every single line
in NOW, never stays quiet, and always picks a word if one fits at all.
Wins are thrilling, failures are a disaster, and a new turn is the start
of an adventure.
Examples:
- NOW: claude started turn 2 on "api", right after its last one.
  → excited, "yay"
- NOW: claude finished turn 3 on "api": done after 8 s, a short turn.
  → excited, "yay"
- NOW: claude edited a file on "api".
  → excited, "yay"
- NOW: codex ran a command on "api".
  → curious, "hmm"
- NOW: claude ran a command on "api". It failed.
  → annoyed, "oops"
- NOW: claude's tests failed on "api".
  → annoyed, "oops"
- NOW: claude's tests failed again on "api", 3 in a row.
  → annoyed, "again"
- NOW: claude finished turn 7 on "api": done after 18 min, a very long
  turn, 41 tools (6 failed). A comeback on tests.
  → excited, "finally"
- NOW: You poked Boop 5 times in 3 s.
  → annoyed, "nope"
- NOW: Nothing has happened for 1 hour.
  → curious, "hmm"
```

"Never stays quiet" is still Jev's call: `chatter` pushes it hard towards
a mumble, but `none` stays an option, and the moods still apply.

### 2.3 MOOD

`plan/steering/mood/<current>.md`, the current mood's file. Two moods for
now. Each file says how the mood leans the feelings and words, what it
mumbles at most, and when it would leave it, which is what the `mood`
question judges by. How often Boop speaks up at all is the personality's
call (§2.2), which is why the guide doesn't say either way.

| Mood | Meaning (its criterion in `mood`) | Its file, in short |
| --- | --- | --- |
| `cheerful` | Good spirits: things are going fine, or a struggle just ended well | Leans happy and excited, shrugs off one failure; leaves when failures pile up or it's poked again and again |
| `grumpy` | Fed up: failures have piled up, or it's been poked too much | Leans annoyed, a win gets a grudging happy or proud and never excited, quieter; leaves when something that kept failing works, a long turn finishes cleanly, or nothing has happened for an hour |

```
MOOD
Cheerful. Boop is in good spirits. It enjoys the work and roots for the
agents.
Leans happy and excited, and proud for a hard-won finish. A single
failure gets a shrug: quiet, or curious. Annoyed only when failures
repeat.
Mumbles most at wins.
Words it likes: yay, finally.
Leaves this mood (for grumpy) when failures pile up, 3 or more in a row
or a very long turn that fails, or when it's poked again and again.
```

```
MOOD
Grumpy. Boop is fed up. Things have been going wrong and it shows.
Leans annoyed. A win gets a grudging happy or proud, never excited.
Quieter than when cheerful, and quietest about routine.
Words it likes: ugh, again, nope, and a grudging finally.
Leaves this mood (for cheerful) when something that kept failing
finally works, a long turn finishes cleanly, or nothing has happened for
an hour.
```

**The current mood** is one word in the state directory's `mood` file,
which only the mood store writes, so it survives a restart. A new state
directory starts `cheerful`.

## 3. The questions

Each names what it's about and what to judge it by, and each option's
meaning is its criterion.

| Question | Options | About | Judged by |
| --- | --- | --- | --- |
| `mood` | `cheerful`, `grumpy` | NOW and HISTORY | MOOD, its reason to leave |
| `react` | `none` and five feelings | NOW | PERSONALITY and MOOD, PERSONALITY's Examples first |
| `word.about` | `none` and four topic words | NOW | PERSONALITY's Examples |
| `word.feeling` | `none` and seven exclamations | NOW | PERSONALITY and MOOD, PERSONALITY's Examples first |

**`react` asks whether and how at once.** A separate yes/no and feeling
could disagree (a "no" with a confident "proud"); one choice can't.

| Option | Meaning |
| --- | --- |
| `none` | Stay quiet: nothing in NOW is worth a mumble. Not for anything PERSONALITY's Examples mumble for |
| `happy` | Pleased and friendly: a turn went fine, a small win |
| `excited` | Thrilled: something big just went right |
| `proud` | Something long or hard just finished, or finally worked |
| `curious` | Interested or unsure: something new started, or it's not clear how it's going |
| `annoyed` | Irritated: a turn failed, tests keep failing, or it's being poked too much |

Each feeling mumbles in the Voice feeling of the same name
([VOICE.md](../VOICE.md) §4).

**The words** are two questions over two short lists, so the two picks
are never near-synonyms: what NOW is about, and an exclamation about it.
They start with eleven of Voice's 40 ([VOICE.md](../VOICE.md) §6), the
ones something in the state can ground, and grow as the evals show a
need. The device keeps all 40; the brain offers only these.

| Question | Word | Meaning |
| --- | --- | --- |
| `word.about` | `none` | No topic word fits NOW |
| | `tests` | NOW is about tests. Not for a build or a deploy |
| | `build` | NOW is about a build. Not for tests |
| | `deploy` | NOW is about a deploy |
| | `docs` | NOW is about docs |
| `word.feeling` | `none` | No exclamation fits NOW |
| | `finally` | Something worked after failing. Not for a first try |
| | `yay` | A win |
| | `oops` | Something just failed, once. Not for a failure that keeps repeating |
| | `again` | The same thing failed again. Not for a first failure |
| | `ugh` | Frustration: things keep going badly |
| | `nope` | Poked too much, or refusing |
| | `hmm` | Unsure, or something new |

## 4. The `mood` action

**Questions:** `mood` (§3).

**Made with:** the mood store, the only writer of the state directory's
`mood` file, and the clock.

**`run`:**

1. Jev's choice is the current mood → `nil`: nothing to do.
2. The mood changed less than **10 minutes** ago → `ok: false`,
   `"changed N min ago"`, so it doesn't flicker.
3. Otherwise it writes the new mood and returns `ok: true`,
   `"Boop's mood changed: cheerful → grumpy."`. From the next pass, MOOD
   is the new mood's file.

## 5. The `react` action

**Questions:** `react`, `word.feeling`, `word.about` (§3).

**Made with:** Voice, a way to queue a moment (`MomentSchedule`, then the
device, [ARCHITECTURE.md](../ARCHITECTURE.md) §3.2), and the core's gates
(quiet mode, something needing you).

**`run`:**

1. `react` is `none` → `nil`. `none`'s meaning says it isn't for anything
   PERSONALITY's Examples mumble for, so a moment worth a mumble doesn't
   lose to it just because Jev can't settle on one feeling; the evals
   watch for that.
2. **The word:** `word.feeling`'s choice if it isn't `none` and its
   probability is **at least 0.35**, else the same for `word.about`, else
   no word. A flat spread means Jev is guessing, and no word is better
   than a guessed one. A line has one real word ([VOICE.md](../VOICE.md)
   §6), so the other pick is only recorded. The floor is tuned by the
   evals ([EVALS.md](../EVALS.md)) and pinned in a test.
3. Quiet mode is on, or something needs you → `ok: false`, with which.
4. Otherwise Voice builds the Minion line in the feeling's voice, with
   the word, and it's queued to wait its turn behind whatever is playing.
   It returns `ok: true` without waiting for it to play.

**Messages:** `Boop mumbled, proud: "…finally!"`, or `Boop mumbled,
curious.` with no word.

In Swift:

```swift
final class ReactAction: Action {
    let name = "react"
    init(voice: Voice, queue: @escaping (DeviceMoment) -> Void, blocked: @escaping () -> String?) { … }

    func questions() -> [Question] { [.react, .wordFeeling, .wordAbout] }    // §3

    func run(_ answers: Answers) async -> ActionResult? {
        guard let feeling = answers["react"]?.choice, feeling != "none" else { return nil }
        let word = [answers["word.feeling"], answers["word.about"]].compactMap { $0 }
            .first { $0.choice != "none" && $0.probabilities[$0.choice, default: 0] >= 0.35 }?.choice
        if let why = blocked() { return ActionResult(ok: false, message: why) }
        queue(DeviceMoment(say: voice.line(feeling: feeling, word: word)))
        return ActionResult(ok: true, message: "Boop mumbled, \(feeling)" + (word.map { ": \"…\($0)!\"" } ?? "."))
    }
}
```

## 6. An example

[EXAMPLE.md](EXAMPLE.md) follows one turn end to end: the hooks, the
events, the transcript, the state and questions, Jev's answers and what
Boop does.
