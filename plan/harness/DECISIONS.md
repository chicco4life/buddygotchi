# Boop: harness decisions

Updated 2026-09-28. What Boop decides when the brain wakes: the steering
files Jev reads, the questions it answers, and the two actions that
carry out its answers. The contract every action follows is
[HARNESS.md](HARNESS.md) §4. The events are in [EVENTS.md](EVENTS.md),
and actions only ever see their lines, never their facts.

## 1. What Boop decides

The screen is a mood × a visual; the visual is automatic, and the
brain decides the rest ([BEHAVIORS.md](../BEHAVIORS.md) §1): the lasting
mood, and reactions, each a mood × a visual for a moment with maybe a
word.

Two actions, registered in this order (`Runtime`):

| Action | Decides | Its questions | Effect |
| --- | --- | --- | --- |
| `mood` (§4) | Whether Boop's mood changes, and to what | `mood` | The `mood` file; MOOD from the next pass; the device's set of faces |
| `react` (§5) | Whether Boop reacts, with which mood's face, which animation, for how long, and with which real word | `react.mood`, `react.animation`, `react.loops`, `word.feeling`, `word.about` | The device draws the look, or the animation when there is one, in that mood's design for the loops picked, and at least while a Minion line plays |

All six questions go in one request, and Jev answers each on its own
([HARNESS.md](HARNESS.md) §7). So both actions are judged against the
mood as it stood: on a pass that changes the mood, the reaction is still
judged by the old one. The guide asks for the two to fit together (a
mood change shows, with the new mood's face), and the evals check both
on the same pass.

## 2. The steering files

Jev's three static sections, one file each in
[plan/steering/](../steering/guide.md), read-only at runtime and bundled
in the app ([HARNESS.md](HARNESS.md) §6 says how they're loaded). Their
examples are written as the state's own lines.

### 2.1 The guide

[guide.md](../steering/guide.md) opens the state, with no heading, the
same for every personality and mood. It says who Boop is (a desk
creature that never approves or blocks anything), what it already does
on its own (wiggles and alerts), that nothing celebrates a finished
turn unless Jev reacts to it, and that Jev only decides whether
it reacts, with one of its moods' faces, held once or more (longer for
bigger moments), and a mumble of at most one real word, and whether its
mood changes. Then how to choose: judge by PERSONALITY and MOOD; react
to NOW, not older lines, with a face, hold and word that fit it; don't
repeat what Boop just did or is still doing (HISTORY's
`(in progress)`). A reaction that didn't happen isn't in HISTORY
([HARNESS.md](HARNESS.md) §5.3), so NOW may call for it again. And on
moods:

> The mood is the backdrop, and should visibly shift, step by step:
> change it whenever NOW is MOOD's reason to leave it, but never for a
> routine turn alone, and not while HISTORY ends "for under a minute"
> unless a turn failed, a very long turn ended or Boop was poked. A
> mood goes back to happy after the minutes MOOD gives, or after an
> hour of nothing.
>
> A mood change shows: react with the new mood's face (back to happy:
> a happy face, once).

So the person sees Boop's mood move during ordinary work, and sees each
move happen: the face that comes with the change, then the new set of
faces behind everything else. HISTORY ends with `Boop has been grumpy
for 2 min.` ([HARNESS.md](HARNESS.md) §5.3), so Jev can tell when a
mood's minutes are up; they end on the next line after that. Each mood's file gives its minutes again, since the `mood`
question judges by MOOD, with the change dropping out of HISTORY (after
ten minutes or 40 events, [HARNESS.md](HARNESS.md) §5.3) as the
fallback.
The hourly heartbeat ([EVENTS.md](EVENTS.md) §4) is what lets a mood go
when nothing happens at all. After the guide, the harness adds how to read HISTORY
and NOW ([HARNESS.md](HARNESS.md) §6.1).

### 2.2 PERSONALITY

`personality/<name>.md`, chosen in Settings and used from the next
event. It has two parts:

- **Front matter** for the view's rules: how often the working heartbeat
  comes, and which tool calls' ends the view keeps. Its values are
  [BEHAVIORS.md](../BEHAVIORS.md) §6's, and it never reaches Jev.
- **The text,** which is the PERSONALITY section: who this Boop is, how
  often it speaks up, and its Examples, each a NOW line and what it
  would pick: the face, the word and how long it holds
  (`→ grumpy, "again", once`). `no word` is a mumble with no real word,
  and `no exclamation, "tests"` a topic word alone, so `word.feeling`
  answers `none` and `word.about` gives the word (§5).

| Personality | For | Its text |
| --- | --- | --- |
| [`boop`](../steering/personality/boop.md) (the default) | Everyday use | Loyal, easily delighted, a little smug and lively: it never sits still for long, and it all shows on its face. It reacts to anything that stands out, with a strong face that fits the moment whatever its mood, held longer for bigger moments: a failed check is determined with "oops", held once; a check passing after failing proud with "finally", twice; a very long turn done excited with a cheer and "yay", three times, and failed sad, three times, as is an agent giving up, once; a failed turn grumpy with "ugh", four pokes in a row grumpy with "nope", and a stopped turn and a single poke happy, "hmm" and no word, once. Any turn done gets a small happy face, the same one each time: a long one says "nice", and the rest no word. Only a very long turn done cheers, and the exclamation is kept for what stands out. A turn start gets nothing, unless the person sounds frustrated (determined, "again") or thanks the agent (excited, "yay"). Work still going gets a small face with no word at every working heartbeat, never none: happy in a long turn, determined in a very long one Talked to, it always answers with a face, never none: proud at kind words, and grumpy with "nope" at rude ones. |
| [`chatter`](../steering/personality/chatter.md) | Debugging, so every pass is easy to see | Wildly over the top. It reacts to every line in NOW, routine tool uses, heartbeats and what you say included, always picks a word if one fits, and holds its faces long: twice for routine lines, up to four times for a fix or a very long turn done |

"Never stays quiet" is still Jev's call: `none` stays an option, and the
moods still apply.

### 2.3 MOOD

`mood/<mood>.md`, the current mood's file. There are six moods
(`MoodAction.moods`), each with its own set of faces on the device. Curious, whose faces the device keeps, isn't
one: nothing led to it ([PROTOCOL.md](../PROTOCOL.md) §3). Each file
says which faces Boop makes in its
reactions while in that mood (a happy Boop's wins mostly get an excited
face, and a grumpy Boop gives a win a grudging proud, never a grumpy
face), what it mumbles at most and the words it likes ("yay" only at a
big win, a routine one its topic), and when it leaves, and for which
mood. That last part is what the `mood` question
judges by. No timer holds or ends a mood: how long one lasts is the
steering's to say. The rules read only what the lines say
([EVENTS.md](EVENTS.md) §8), with no streaks:

- a failed check while the agent works on: determined;
- the agent still working on a very long turn (its working heartbeat):
  happy drifts to determined, rooting for it;
- a failed turn, or many pokes in a row: grumpy;
- a check passing after failing: proud;
- a very long turn (5 minutes or more) ending done: excited; ending
  failed: sad.

And four from the words in the lines' notes ([EVENTS.md](EVENTS.md)
§8): what the person asked on a turn start, and the agent's last
message on a finish. No code looks for keywords: Jev reads the note and
judges it against the mood file's words.

- the person sounds frustrated ("it's still broken"): determined,
  rooting for the retry, not grumpy at them;
- the person thanks or praises the agent: excited, or happy from
  grumpy;
- the agent says a long or very long turn's hard work is done: proud.
  Not a short turn's "done", or every quick finish would be a win;
- the agent gives up: says it couldn't do it, or is stuck: sad.

These came in because the other rules rarely fire in ordinary work (a
day of short and long turns that finish done left Boop happy all day
but for pokes). A plain request and a matter-of-fact finish still move
nothing (`28-plain-words-leave-mood`), nor does a short or long finish
alone, a turn starting or a stopped turn. Every mood but happy goes
back to happy after its minutes,
read against HISTORY's closing `Boop has been X for N min.`: 2 for
grumpy, which flares up and blows over, 10 for sad, and 5 for the rest
(§2.1). Two things hold a mood past them: pokes coming again and again keep Boop
grumpy while it goes on, and a very long turn still working keeps it
determined. Proud rides out a failed check, with a determined face, so
tests flipping back and forth don't flip the mood (`20-no-flail`, a
known gap still: [EVALS.md](../EVALS.md) §4).

| Mood | Its meaning (the `mood` option) | Leaves for (its file) |
| --- | --- | --- |
| `happy` | Good spirits: things are going fine | `excited` when a very long turn finishes done or the person thanks the agent; `proud` when a check passes after failing or a long turn's last message says hard work is done and working; `determined` when a check fails, a very long turn works on or the person sounds frustrated; `grumpy` when a turn fails or at many pokes in a row; `sad` when a very long turn ends failed or the agent gives up, stuck. Stays happy through plain finishes under 5 minutes and a stopped turn |
| `excited` | Thrilled: a very long turn finished done, or the person thanked the agent. Not for a shorter turn finishing, or work still going | `determined` at a failed check or when the person sounds frustrated; `grumpy` when a turn fails or at many pokes in a row; `sad` when a very long turn ends failed or the agent gives up; `happy` after 5 minutes. Stays through more wins and thanks |
| `proud` | Something hard-won worked: a check passed after failing, or a long turn's last message says hard work is done and working. Not for a short turn finishing | `excited` when a very long turn finishes done or the person thanks the agent; `determined` when the person sounds frustrated; `grumpy` when a turn fails or at many pokes in a row; `sad` when a very long turn ends failed or the agent gives up; `happy` after 5 minutes. Stays through routine turns and a failed check |
| `determined` | Rooting for a retry: a check failed and the agent is working on, or the person sounds frustrated. Not for a turn that has ended | `proud` when a check passes after failing or the agent says a long turn's hard work is done; `excited` when a very long turn finishes done or the person thanks the agent; `grumpy` when a turn fails or at many pokes in a row; `sad` when a very long turn ends failed or the agent gives up; `happy` after 5 minutes, unless the agent is still working on a very long turn. Stays through more failed checks, long work, routine finishes and frustration |
| `grumpy` | Fed up, briefly: a turn failed, or Boop was poked again and again. Not for a check failing while the agent works on, the person's frustration, or an agent giving up | `proud` when a check passes after failing; `sad` when a very long turn ends failed or the agent gives up; `happy` when the person thanks the agent, or after 2 minutes, but never while Boop is being poked |
| `sad` | Deflated: a very long turn finished failed, or the agent gave up, stuck. Not for a shorter turn failing with an error | `proud` when a check passes after failing or the agent says a long turn's hard work is done, staying sad through more failures and frustration before it; `happy` when the person thanks the agent, or after 10 minutes |

Each "after N minutes" counts from Boop's mood changing to it, or ends
sooner if the change has dropped out of HISTORY.

And from any mood, `happy` after an hour with nothing happening (the
guide).

**The current mood** is one word in the state directory's `mood` file
([ARCHITECTURE.md](../ARCHITECTURE.md) §4.4), which only the mood store
(`MoodStore`) reads and writes, so it survives a restart. A new state
directory starts `happy` (`MoodAction.initial`), and a missing or unknown
word reads as `happy`, `curious` included. The core puts the mood in
every `state` it sends
([PROTOCOL.md](../PROTOCOL.md) §3).

## 3. The questions

Each says what it's about and what to judge it by, and each option's
meaning is its criterion.

| Key | Asked by | Text | About | Judged by | Options |
| --- | --- | --- | --- | --- | --- |
| `mood` | `mood` | After NOW, what is Boop's mood? | the NOW and HISTORY sections | the MOOD section, its reason to leave | The six moods (§2.3) |
| `react.mood` | `react` | How should Boop react to NOW, if at all? It makes this mood's face for a moment, with a mumble. | the NOW section | the PERSONALITY and MOOD sections, PERSONALITY's Examples first | `none` and the six moods' faces |
| `react.animation` | `react` | If Boop reacts, does it play an animation? | the NOW section | as `react.mood` | `none` and each reaction animation: today only `cheer` |
| `react.loops` | `react` | If Boop reacts, how long does it hold the face? | the NOW section | as `react.mood` | Four lengths, once to four times |
| `word.feeling` | `react` | If Boop mumbles, which exclamation fits NOW? | the NOW section | as `react.mood` | `none` and eight exclamations |
| `word.about` | `react` | If Boop mumbles, which topic word is NOW about? | the NOW section | the PERSONALITY section's Examples | `none` and seven topics |

**`react.mood` picks a face.** Its options are `none` and the six moods,
and a reaction is that mood's face for a moment: the device draws
whatever look is showing (working, idle) in that mood's design, or the
animation `react.animation` picks, for the loops `react.loops` picks, and at least while the mumble
plays, then goes back to Boop's mood ([PROTOCOL.md](../PROTOCOL.md) §3).
The mood is the backdrop and the face the moment, so they can differ on
purpose: a happy Boop at work scowls grumpily at a failing test for a
loop of the working design, then smiles again.
The designs are the reactions' meaning; the sound follows the face
(Voice picks a feeling for each mood, [VOICE.md](../VOICE.md) §4).

`react.mood` asks whether and how at once. A separate yes/no and face could
disagree (a "no" with a confident "proud"); one choice can't.

| `react.mood` | Meaning |
| --- | --- |
| `none` | Stay quiet: nothing in NOW is worth a face and a mumble, or HISTORY shows Boop still making the one it calls for (in progress). Not for anything PERSONALITY's Examples react to that Boop isn't already doing |
| `happy` | A happy face: pleased, a turn went fine or a small win |
| `excited` | An excited face: something big just went right |
| `proud` | A proud face: something long or hard just finished, or finally worked |
| `determined` | A determined face: a check failed and the agent is trying again. Not for a turn that has ended |
| `grumpy` | A grumpy face: a turn failed, or Boop is poked again and again. Not for an agent giving up |
| `sad` | A sad face: a very long turn ended failed, or the agent gave up, stuck. Not for a shorter turn failing with an error, or a check failing |

**`react.animation` picks an animation to play in the face,** instead
of drawing the face over the look. A reaction is a mood and an
animation, as the screen is a mood and a state. Today the only one is
the cheer, the mood's task-complete scene (a trophy, a curtain call or
a podium; the device picks). No rule cheers, so this is the only way a
finish is celebrated. It's asked on every pass and only read when
`react.mood` picks a face; a missing or unknown answer is `none`. A new
reaction animation is a new option here with its own meaning, once its
art exists; candidates are an `oops` for a first failure, a `slump`
when things keep failing, a `huff` at a pile of pokes and a `ponder` at a
stopped turn.

| `react.animation` | Meaning |
| --- | --- |
| `none` | Just the face, over whatever look is showing: the usual |
| `cheer` | Something just finished or finally worked, and it stands out. Not for a routine finish, a failure, or anything still going |

**`react.loops` picks how long the face holds,** in loops of the design
it's drawn in. It's asked on every pass and only
read when `react.mood` picks a face; a missing answer holds it once. The
personality's Examples set the scale: boop mostly holds once, chatter
long.

| `react.loops` | Loops | Meaning |
| --- | --- | --- |
| `once` | 1 | A small moment: the usual |
| `twice` | 2 | A moment that stands out. Not for routine work |
| `three times` | 3 | A big moment, such as a check passing after failing |
| `four times` | 4 | The biggest moments: a hard-won finish, or a failure that keeps coming back. Not for a single win or failure |

**The words** are two questions over two short lists, so the two picks
are never near-synonyms: an exclamation, and what NOW is about. They're
the fifteen of Voice's real words ([VOICE.md](../VOICE.md) §6) that
something in the state can ground, and a test checks each is one of
Voice's.

| Question | Word | Meaning |
| --- | --- | --- |
| `word.feeling` | `none` | No exclamation fits NOW |
| | `finally` | Something worked after failing. Not for a first try |
| | `yay` | A big win: a very long turn done. Not for a shorter turn done |
| | `nice` | A solid win: a long turn done. Not for a short or very long turn, or a turn ending just after its fix |
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
| | `bug` | NOW is about a bug: your prompt or the agent's last message says one was hunted or fixed. Not for a failed check or turn with no word of a bug |
| | `merge` | NOW is git work: a commit, merge, push or pull request, as your prompt or the agent's last message says |
| | `review` | NOW is a review of code or a pull request, as your prompt or the agent's last message says |

## 4. The `mood` action

`app/BoopKit/Actions/MoodAction.swift`. **Made with** the mood store and
a callback the runtime gives it, which hands a saved mood to the core so
the next `state` carries it.

| Jev's `mood` answer | Result |
| --- | --- |
| Missing, the current mood, or not a mood | `nil`: nothing to do |
| Another mood | Saves it, tells the core, and returns `ok`, `Boop's mood changed: happy → grumpy.` MOOD is the new mood's file from the next pass, and a new `state` goes to the device at once |
| Another mood, but the file can't be written | `ok: false`, `couldn't save the mood: …`, and nothing changes |

A mood can change on any pass, a poke's included, even straight
after another change.

**How long Boop has been in its mood.** `mood` also hands the runtime a
line for the end of HISTORY, its only closing line
([HARNESS.md](HARNESS.md) §5.3): `Boop has been proud for 7 min.`, in whole minutes as HISTORY's
times are (`under a minute` below one, hours past an hour), counted from
the change it last made (`MoodAction.sinceLine`). It's left out while
Boop is happy, and before the action has changed the mood since launch,
where the change leaving HISTORY is the mood files' fallback. The mood
files' minutes ("once Boop has been grumpy for 2 min") are read against
it: without it, Jev saw `7 min ago: … Boop's mood changed: determined →
proud` and kept Boop proud at 0.68–0.75, where its 5 minutes were up
(`make eval`'s `13-proud-fades`, 0 of 3 runs before, 3 of 3 after).

**The dashboard** sets a mood through the same change
([HARNESS.md](HARNESS.md) §9), and gets a refusal where Jev's answer would
get `nil`: `already grumpy` for the current mood, and
`sulky isn't a mood` for a word that isn't one, each `ok: false`. A pass
that was running when the dashboard changed the mood leaves it alone:
its answer is about the mood before ([HARNESS.md](HARNESS.md) §2).

## 5. The `react` action

`app/BoopKit/Actions/ReactAction.swift`. **Made with** Voice, in this
Boop's dialect; a queue to the device, which is the runtime's moment
schedule ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.2); and the core's
gate, which says when something needs you.

`run`:

1. **Whether:** `react.mood` missing, `none` or not a mood → `nil`. Since
   `none`'s meaning rules out anything PERSONALITY's Examples react to, a
   moment worth a reaction doesn't lose to it just because Jev can't
   settle on one face. It still covers a reaction Boop is making already:
   without that, a turn's finish 20 s after a fix's proud "…finally!"
   got the same again, with that face still in progress (`make eval`'s
   `11-comeback-still-showing`, 0 of 3 runs before, 3 of 3 after).
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
   and `react.loops`' pick as `loops` (1–4, `ReactAction.loops`), with
   `react.animation`'s pick as `anim` when it isn't `none`, with one of
   the cheer's variations as `variant`, at random and never the last one,
   and `who`, the agent and thread NOW is about (the name its agent's
   app shows, once a request brought one, else the view's `who(about:)`;
   none for a poke or an idle heartbeat), so the device
   names them ([PROTOCOL.md](../PROTOCOL.md) §3), and otherwise no animation,
   so it plays over whatever is showing (a wiggle included). Either way
   it waits until any line or face playing has finished. A face the last reaction
   holds on for its loops after its mumble is the exception: this one
   replaces it once that mumble has played, so a long hold doesn't
   make the next reaction wait past its 5 s and be dropped
   ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.2). The last reaction is
   still `done`. A new `Pending` goes with
   it, and the action returns without waiting for the moment.
5. **The message:** started (`.started`) with that handle, as
   `Boop made a proud face, held three times, and mumbled "…finally!"`,
   `Boop played a cheer in a proud face, held twice, and mumbled "…finally!"`,
   or `Boop made a happy face, held once, and mumbled.` with no word.

**No last-reaction line.** HISTORY no longer closes with Boop's last
reaction: what Boop did is only under the lines it answered. The line
was added because Jev repeated a reaction once it had played out (an
excited "…tests!" over quick passing turns); it went with the other
modifiers to keep the state small and testable, and the evals will say
whether the repeats come back ([ARCHITECTURE.md](../ARCHITECTURE.md)'s
decision log).

**How a reaction ends.** HISTORY shows its line `(in progress)` until
whoever holds the moment ends the handle ([HARNESS.md](HARNESS.md) §4,
§5.3). The moment goes to the device with an `id`, and the device says
how it ended ([PROTOCOL.md](../PROTOCOL.md) §4):

| End | When | By |
| --- | --- | --- |
| `done` | The device says its mumble played to the end, and its face its loops, or until a newer moment (the next reaction's included), a tap or "needs you" ended the face after the mumble: it was seen and heard | The runtime, from the device's `ended` |
| `failed`, `cut short: you tapped Boop` | The device says a tap's wiggle stopped its mumble. HISTORY keeps its line, `(in progress)` while the pokes go on and plain after: you saw it start, and a barrage of pokes would otherwise get the same face twice ([EVENTS.md](EVENTS.md) §7) | The same |
| `failed`, `cut short: something newer played` | The device says a newer moment stopped its mumble: a line | The same |
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

A failed one is left out of HISTORY, so Jev may make it again if NOW
still calls for it (§2.1). The evals have no device, so
their queue ends each handle at once, `done` unless a scenario's step
says otherwise ([EVALS.md](../EVALS.md) §1, §3).
[HARNESS.md](HARNESS.md) §9 has a reaction and its end in `debug.jsonl`,
from a headless run with no device. With the board on USB and Boop
asleep, a forced proud reaction held twice: its moment, its action and
the end the device's `ended` (`done`) brought 14.0 s later, at the
second loop boundary of the asleep design's 8 s clock, long after its
1.9 s mumble (recorded before the raw transcript, and rewritten into
today's lines by
`plan/evidence/2026-09-28-raw-transcript-view/convert_fixtures.py`):

```jsonl
{"sent":{"t":"moment","say":{"syl":"da-to-lon","word":"finally","at":3,"tune":"lift","ms":135},"mood":"proud","loops":2,"id":1710758195},"received_at_ms":1790531820132}
{"event":{"seq":2,"ts":1790531820132,"source":"boop","type":"action","phase":"start","specific_type":"react","data":{"by":"dashboard","for":null,"latency_ms":1,"message":"Boop made a proud face, held twice, and mumbled \"…finally!\"","ok":true}},"received_at_ms":1790531820132}
{"event":{"seq":3,"ts":1790531834106,"source":"boop","type":"action","phase":"end","specific_type":"react","data":{"by":"dashboard","for":2,"outcome":"done"}},"received_at_ms":1790531834106}
```

## 6. An example

[EXAMPLE.md](EXAMPLE.md) follows one real pass end to end: the view
event, the transcript, the state and questions, Jev's answers, and what
the actions did.
