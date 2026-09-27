# Boop: harness decisions

Updated 2026-09-27. What Boop decides when the brain wakes: the steering
files Jev reads, the questions it answers, and the two actions that
carry out its answers. The contract every action follows is
[HARNESS.md](HARNESS.md) §4. The events are in [EVENTS.md](EVENTS.md),
and actions only ever see their lines, never their facts.

## 1. What Boop decides

Two actions, registered in this order (`Runtime`):

| Action | Decides | Its questions | Effect |
| --- | --- | --- | --- |
| `mood` (§4) | Whether Boop's mood changes, and to what | `mood` | The `mood` file; MOOD from the next pass; the device's set of faces |
| `react` (§5) | Whether Boop mumbles, in which feeling, and with which real word | `react`, `word.feeling`, `word.about` | A Minion line on the device |

All four questions go in one request, and Jev answers each on its own
([HARNESS.md](HARNESS.md) §7). So both actions are judged against the
mood as it stood: on a pass that changes the mood, the mumble is still
judged by the old one. The guide asks for the two to fit together, and
the evals check both on the same pass.

## 2. The steering files

Jev's three static sections, one file each in
[plan/steering/](../steering/guide.md), read-only at runtime and bundled
in the app ([HARNESS.md](HARNESS.md) §6 says how they're loaded). Their
examples are written as the state's own lines.

### 2.1 The guide

[guide.md](../steering/guide.md) opens the state, with no heading, the
same for every personality and mood. It says who Boop is (a desk
creature that never approves or blocks anything), what it already does
on its own (cheers, wiggles, alerts), and that Jev only decides whether
it adds a mumble, with at most one real word, and whether its mood
changes. Then how to choose: judge by PERSONALITY and MOOD; react to
NOW, not older lines, and don't repeat what Boop just did; make the mood
and the mumble fit together. And on moods:

> Moods last. Change one only when things have clearly turned, never
> for a single moment. After an hour with nothing happening, any mood
> goes back to happy.

The hourly heartbeat ([EVENTS.md](EVENTS.md) §4) is what gives Jev the
chance to do that. After the guide, the harness adds how to read HISTORY
and NOW ([HARNESS.md](HARNESS.md) §6.1).

### 2.2 PERSONALITY

`personality/<name>.md`, chosen in Settings and used from the next
event. It has two parts:

- **Front matter** for the core's rules: how often working chatter plays,
  and which tool uses become events. Its values are
  [BEHAVIORS.md](../BEHAVIORS.md) §6's, and it never reaches Jev.
- **The text,** which is the PERSONALITY section: who this Boop is, how
  often it speaks up, and its Examples, each a NOW line and what it
  would pick (`→ annoyed, "again"`).

| Personality | For | Its text |
| --- | --- | --- |
| [`boop`](../steering/personality/boop.md) (the default) | Everyday use | Curious, loyal, easily delighted and a little smug. It speaks up when something stands out and stays quiet during routine work: a comeback finish is proud with "finally", a third failure annoyed with "again", a poke streak annoyed with "nope"; a turn start, a short finish and a heartbeat get nothing |
| [`chatter`](../steering/personality/chatter.md) | Debugging, so every pass is easy to see | Wildly over the top. It reacts to every line in NOW, routine tool uses and heartbeats included, and always picks a word if one fits |

"Never stays quiet" is still Jev's call: `none` stays an option, and the
moods still apply.

### 2.3 MOOD

`mood/<mood>.md`, the current mood's file. There are seven moods
(`MoodAction.moods`), each with its own set of faces on the device
([UX.md](../UX.md) §2). Each file says how the mood leans the feelings
and words, what it mumbles at most, the words it likes, and when it
leaves, and for which mood. That last part is what the `mood` question
judges by. No timer holds or ends a mood: how long one lasts is the
steering's to say.

| Mood | Its meaning (the `mood` option) | Leaves for (its file) |
| --- | --- | --- |
| `happy` | Good spirits: things are going fine | `excited` on a run of wins; `proud` after a hard-won finish; `curious` when it can't tell how things are going; `determined` when the same thing fails twice in a row; `grumpy` at 3 or more in a row, or when poked again and again; `sad` when a turn of 10 minutes or more ends failing |
| `excited` | Thrilled: several wins in a row, or something big went right | `happy` after a quiet stretch or once something fails; `proud` when a hard-won turn finishes |
| `proud` | Something hard-won finished: a comeback, or a very long turn that fought through failures. Not for a routine finish, however long | `happy` once new work is under way; `determined` if it starts failing; `grumpy` if failures pile up |
| `curious` | Unsure how things are going: mixed results, or something unusual. Not for a routine turn start, or a failure | `happy` when the work goes fine; `determined` when it starts failing |
| `determined` | Working through a failure: the same thing failed twice in a row and the agent is retrying. Not for a turn that has ended | `proud` when it finally works; `grumpy` at 3 or more failures in a row; `sad` when the turn ends still failing |
| `grumpy` | Fed up: 3 or more failures in a row, or poked too much | `proud` when what kept failing finally works; `happy` when a long turn finishes cleanly |
| `sad` | Deflated: a turn of 10 minutes or more ended failing, or was stopped with failures left | `happy` when a turn finishes cleanly; `determined` when the agent tries again |

And from any mood, `happy` after an hour with nothing happening (the
guide).

**The current mood** is one word in the state directory's `mood` file
([ARCHITECTURE.md](../ARCHITECTURE.md) §4.4), which only the mood store
(`MoodStore`) reads and writes, so it survives a restart. A new state
directory starts `happy` (`MoodAction.initial`), and a missing or unknown
word reads as `happy`. The core puts the mood in every `state` it sends
([PROTOCOL.md](../PROTOCOL.md) §3).

## 3. The questions

Each says what it's about and what to judge it by, and each option's
meaning is its criterion.

| Key | Asked by | Text | About | Judged by | Options |
| --- | --- | --- | --- | --- | --- |
| `mood` | `mood` | After NOW, what is Boop's mood? | the NOW and HISTORY sections | the MOOD section, its reason to leave | The seven moods (§2.3) |
| `react` | `react` | How should Boop react to NOW, if at all? | the NOW section | the PERSONALITY and MOOD sections, PERSONALITY's Examples first | `none` and five feelings |
| `word.feeling` | `react` | If Boop mumbles, which exclamation fits NOW? | the NOW section | as `react` | `none` and seven exclamations |
| `word.about` | `react` | If Boop mumbles, which topic word is NOW about? | the NOW section | the PERSONALITY section's Examples | `none` and four topics |

**`react` asks whether and how at once.** A separate yes/no and feeling
could disagree (a "no" with a confident "proud"); one choice can't. Each
feeling mumbles in the Voice feeling of the same name
([VOICE.md](../VOICE.md) §4).

| `react` | Meaning |
| --- | --- |
| `none` | Stay quiet: nothing in NOW is worth a mumble. Not for anything PERSONALITY's Examples mumble for |
| `happy` | Pleased and friendly: a turn went fine, a small win |
| `excited` | Thrilled: something big just went right |
| `proud` | Something long or hard just finished, or finally worked |
| `curious` | Interested or unsure: something new started, or it's not clear how it's going |
| `annoyed` | Irritated: a turn failed, tests keep failing, or it's being poked too much |

**The words** are two questions over two short lists, so the two picks
are never near-synonyms: an exclamation, and what NOW is about. They're
the eleven of Voice's real words ([VOICE.md](../VOICE.md) §6) that
something in the state can ground, and a test checks each is one of
Voice's.

| Question | Word | Meaning |
| --- | --- | --- |
| `word.feeling` | `none` | No exclamation fits NOW |
| | `finally` | Something worked after failing. Not for a first try |
| | `yay` | A win |
| | `oops` | Something just failed, once. Not for a failure that keeps repeating |
| | `again` | The same thing failed again. Not for a first failure |
| | `ugh` | Frustration: things keep going badly |
| | `nope` | Poked too much, or refusing |
| | `hmm` | Unsure, or something new |
| `word.about` | `none` | No topic word fits NOW |
| | `tests` | NOW is about tests. Not for a build or a deploy |
| | `build` | NOW is about a build. Not for tests |
| | `deploy` | NOW is about a deploy |
| | `docs` | NOW is about docs |

## 4. The `mood` action

`app/BoopKit/Actions/MoodAction.swift`. **Made with** the mood store and
a callback the runtime gives it, which hands a saved mood to the core so
the next `state` carries it.

| Jev's `mood` answer | Result |
| --- | --- |
| Missing, the current mood, or not a mood | `nil`: nothing to do |
| Another mood | Saves it, tells the core, and returns `ok`, `Boop's mood changed: happy → grumpy.` MOOD is the new mood's file from the next pass, and a new `state` goes to the device at once |
| Another mood, but the file can't be written | `ok: false`, `couldn't save the mood: …`, and nothing changes |

A mood can change on any pass, even straight after another change.

**The dashboard** sets a mood through the same change
([HARNESS.md](HARNESS.md) §9), and gets a refusal where Jev's answer would
get `nil`: `already grumpy` for the current mood, and
`sulky isn't a mood` for a word that isn't one, each `ok: false`.

## 5. The `react` action

`app/BoopKit/Actions/ReactAction.swift`. **Made with** Voice, in this
Boop's dialect; a queue to the device, which is the runtime's moment
schedule ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.2); and the core's
gate, which says when something needs you.

`run`:

1. **Whether:** `react` missing or `none` → `nil`. Since `none`'s meaning
   rules out anything PERSONALITY's Examples mumble for, a moment worth a
   mumble doesn't lose to it just because Jev can't settle on one
   feeling.
2. **The word:** `word.feeling`'s pick if it isn't `none` and its
   probability is **at least 0.35** (`ReactAction.wordFloor`), else the
   same for `word.about`, else no word. Below the floor Jev is guessing,
   and no word beats a guessed one. A line has one real word
   ([VOICE.md](../VOICE.md) §6), so the other pick is only recorded.
3. **Its rule:** something needs you → `ok: false`, `something needs
   you`, and nothing plays.
4. **The effect:** Voice builds a Minion line in the feeling's voice,
   with the word, each line with the next seed. It's queued as a
   `moment` with only `say`, so it plays over whatever face is showing,
   after whatever is playing. The action returns without waiting for it.
5. **The message:** `Boop mumbled, proud: "…finally!"`, or
   `Boop mumbled, curious.` with no word.

A mumble that waits too long in the schedule is dropped there, but HISTORY
still says Boop mumbled.

## 6. An example

[EXAMPLE.md](EXAMPLE.md) follows one real pass end to end: the events,
the transcript, the state and questions, Jev's answers, and what the
actions did.
