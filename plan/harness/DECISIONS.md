# Boop: harness decisions

Updated 2026-09-28. What Boop decides when the brain wakes: the steering
files Jev reads, the questions it answers, and the two actions that
carry out its answers. The contract every action follows is
[HARNESS.md](HARNESS.md) §4. The events are in [EVENTS.md](EVENTS.md),
and actions only ever see their lines, never their facts.

## 1. What Boop decides

Two actions, registered in this order (`Runtime`):

| Action | Decides | Its questions | Effect |
| --- | --- | --- | --- |
| `mood` (§4) | Whether Boop's mood changes, and to what | `mood` | The `mood` file; MOOD from the next pass; the device's set of faces |
| `react` (§5) | Whether Boop reacts, with which mood's face, for how long, and with which real word | `react`, `react.loops`, `word.feeling`, `word.about` | The device draws the look in that mood's design for the loops picked, and at least while a Minion line plays |

All five questions go in one request, and Jev answers each on its own
([HARNESS.md](HARNESS.md) §7). So both actions are judged against the
mood as it stood: on a pass that changes the mood, the reaction is still
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
it reacts, with one of its moods' faces, held once or more (longer for
bigger moments), and a mumble of at most one real word, and whether its
mood changes. Then how to choose: judge by PERSONALITY and MOOD; react
to NOW, not older lines, with a face, hold and word that fit it; don't
repeat what Boop just did or is still doing (HISTORY's
`(in progress)`), though a reaction that didn't happen may be made again
if NOW still calls for it (§5); the mood is the backdrop and the
reaction the moment, so they may differ, but should fit together. And on
moods:

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
  would pick: the face, the word and how long it holds
  (`→ grumpy, "again", once`).

| Personality | For | Its text |
| --- | --- | --- |
| [`boop`](../steering/personality/boop.md) (the default) | Everyday use | Curious, loyal, easily delighted and a little smug. It speaks up when something stands out and stays quiet during routine work: a comeback finish is proud with "finally", held three times; a third failure grumpy with "again" and a poke streak grumpy with "nope", each held once; a turn start, a short finish and a heartbeat get nothing |
| [`chatter`](../steering/personality/chatter.md) | Debugging, so every pass is easy to see | Wildly over the top. It reacts to every line in NOW, routine tool uses and heartbeats included, always picks a word if one fits, and holds its faces long: twice for routine lines, up to four times for a comeback or a third failure |

"Never stays quiet" is still Jev's call: `none` stays an option, and the
moods still apply.

### 2.3 MOOD

`mood/<mood>.md`, the current mood's file. There are seven moods
(`MoodAction.moods`), each with its own set of faces on the device
([UX.md](../UX.md) §2). Each file says which faces Boop makes in its
reactions while in that mood (a grumpy Boop rarely looks happy), what it
mumbles at most, the words it likes, and when it leaves, and for which
mood. That last part is what the `mood` question
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
| `react` | `react` | How should Boop react to NOW, if at all? It makes this face for a moment, with a mumble. | the NOW section | the PERSONALITY and MOOD sections, PERSONALITY's Examples first | `none` and the seven moods' faces |
| `react.loops` | `react` | If Boop reacts, how long does it hold the face? | the NOW section | as `react` | Four lengths, once to four times |
| `word.feeling` | `react` | If Boop mumbles, which exclamation fits NOW? | the NOW section | as `react` | `none` and seven exclamations |
| `word.about` | `react` | If Boop mumbles, which topic word is NOW about? | the NOW section | the PERSONALITY section's Examples | `none` and four topics |

**`react` picks a face.** Its options are `none` and the seven moods,
and a reaction is that mood's face for a moment: the device draws
whatever look is showing (working, idle, the cheer) in that mood's
design for the loops `react.loops` picks, and at least while the mumble
plays, then goes back to Boop's mood ([PROTOCOL.md](../PROTOCOL.md) §3).
The mood is the backdrop and the face the moment, so they can differ on
purpose: a happy Boop at work scowls grumpily at a failing test for a
loop of the working design, then smiles again.
The designs are the reactions' meaning; the sound follows the face
(Voice picks a feeling for each mood, [VOICE.md](../VOICE.md) §4).

`react` asks whether and how at once. A separate yes/no and face could
disagree (a "no" with a confident "proud"); one choice can't.

| `react` | Meaning |
| --- | --- |
| `none` | Stay quiet: nothing in NOW is worth a face and a mumble. Not for anything PERSONALITY's Examples react to |
| `happy` | A happy face: pleased, a turn went fine or a small win |
| `excited` | An excited face: something big just went right |
| `proud` | A proud face: something long or hard just finished, or finally worked |
| `curious` | A curious face: something new started, or it's not clear how it's going |
| `determined` | A determined face: something failed and the agent is trying again. Not for a turn that has ended, or the same failure 3 or more times in a row |
| `grumpy` | A grumpy face: a turn failed, the same thing keeps failing, or Boop is poked too much |
| `sad` | A sad face: a turn of 10 minutes or more ended failing, or was stopped with failures left. Not for a short turn failing, or a single failure |

**`react.loops` picks how long the face holds,** in loops of the design
it's drawn in ([UX.md](../UX.md) §2). It's asked on every pass and only
read when `react` picks a face; a missing answer holds it once. The
personality's Examples set the scale: boop mostly holds once, chatter
long.

| `react.loops` | Loops | Meaning |
| --- | --- | --- |
| `once` | 1 | A small moment: the usual |
| `twice` | 2 | A moment that stands out. Not for routine work |
| `three times` | 3 | A big moment, such as a comeback |
| `four times` | 4 | The biggest moments: a hard-won finish, or a failure that keeps coming back. Not for a single win or failure |

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

1. **Whether:** `react` missing, `none` or not a mood → `nil`. Since
   `none`'s meaning rules out anything PERSONALITY's Examples react to, a
   moment worth a reaction doesn't lose to it just because Jev can't
   settle on one face.
2. **The word:** `word.feeling`'s pick if it isn't `none` and its
   probability is **at least 0.35** (`ReactAction.wordFloor`), else the
   same for `word.about`, else no word. Below the floor Jev is guessing,
   and no word beats a guessed one. A line has one real word
   ([VOICE.md](../VOICE.md) §6), so the other pick is only recorded.
3. **Its rule:** something needs you → `ok: false`, `something needs
   you`, and nothing plays, so no face is borrowed while needs you shows.
4. **The effect:** Voice builds a Minion line in the voice it gives that
   mood (`Voice.feeling(forMood:)`), with the word, each line with the
   next seed. It's queued as a `moment` with `say`, the face as `mood`
   and `react.loops`' pick as `loops` (1–4, `ReactAction.loops`), and no
   animation, so it plays over whatever is showing (the cheer included)
   once any line or face playing has finished. A new `Pending` goes with
   it, and the action returns without waiting for the moment.
5. **The message:** started (`.started`) with that handle, as
   `Boop made a proud face, held three times, and mumbled "…finally!"`,
   or `Boop made a curious face, held once, and mumbled.` with no word.

**How a reaction ends.** HISTORY shows its line `(in progress)` until
whoever holds the moment ends the handle ([HARNESS.md](HARNESS.md) §4,
§5.3). The moment goes to the device with an `id`, and the device says
how it ended ([PROTOCOL.md](../PROTOCOL.md) §4):

| End | When | By |
| --- | --- | --- |
| `done` | The device says its mumble played to the end, and its face its loops, or until a newer moment, a tap or "needs you" ended the face after the mumble: it was seen and heard | The runtime, from the device's `ended` |
| `failed`, `cut short: you tapped Boop` | The device says a tap's wiggle stopped its mumble | The same |
| `failed`, `cut short: something newer played` | The device says a newer moment stopped its mumble: the rules' cheer, or a line | The same |
| `failed`, `cut short: something needed you` | The device says "needs you" started while its mumble played | The same |
| `failed`, `cut short` | The device says something else stopped it (`dbg.reset`), or doesn't say what | The same |
| `failed`, `something needed you` | The device says none of it played: something needed you when it arrived | The same |
| `failed`, `waited too long` | It waited too long for its turn and was dropped, face and all | The moment schedule |
| `failed`, `no device connected` | Its turn came with no device connected, so nothing played it | The runtime |
| `failed`, `the device disconnected` | The device dropped before saying how it ended | The runtime |
| `failed`, `the device never said it ended` | No `ended` came by the moment's longest length, its face's loops of the design showing or its line, plus a grace ([PROTOCOL.md](../PROTOCOL.md) §6): the line was lost, or the firmware is older | The runtime |

Even the longest hold of the design with the longest loop ends one of
these ways before the harness's ceiling could end it
([HARNESS.md](HARNESS.md) §5.1): its wait for a turn (a late pump
included), its face and the grace for `ended` add up to less, which
`RuntimeTests` checks against the designs' loops, so a new design can't
break it unnoticed.

A failed one reads `(didn't happen: <why>)` in HISTORY, so Jev may make
it again if NOW still calls for it (§2.1). The evals have no device, so
their queue ends each handle `done` at once ([EVALS.md](../EVALS.md) §1).
[HARNESS.md](HARNESS.md) §9 has a reaction and its end in `debug.jsonl`,
from a headless run with no device. With the board on USB and Boop
asleep, a forced proud reaction held twice: its moment, its action and
the settle the device's `ended` (`done`) brought 14.0 s later, at the
second loop boundary of the asleep design's 8 s clock, long after its
1.9 s mumble:

```jsonl
{"sent":{"t":"moment","say":{"syl":"da-to-lon","word":"finally","at":3,"tune":"lift","ms":135},"mood":"proud","loops":2,"id":1710758195},"received_at_ms":1790531820132}
{"action":{"by":"dashboard","for":null,"latency_ms":1,"message":"Boop made a proud face, held twice, and mumbled \"…finally!\"","name":"react","ok":true,"pending":true},"received_at_ms":1790531820132,"seq":2}
{"received_at_ms":1790531834106,"seq":3,"settle":{"by":"dashboard","end":"done","for":2}}
```

## 6. An example

[EXAMPLE.md](EXAMPLE.md) follows one real pass end to end: the events,
the transcript, the state and questions, Jev's answers, and what the
actions did.
