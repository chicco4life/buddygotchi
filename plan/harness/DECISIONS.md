# Boop: harness decisions

Updated 2026-09-30. What Boop decides when the brain wakes: the steering
files Jev reads, the questions it answers, and the two actions that
carry out its answers. The contract every action follows is
[HARNESS.md](HARNESS.md) §4. The events are in [EVENTS.md](EVENTS.md),
and actions only ever see their lines, never their facts.

## 1. What Boop decides

The screen is a mood × a visual; the visual is automatic, and the
brain decides the rest ([BEHAVIORS.md](../BEHAVIORS.md) §1): the lasting
mood, and reactions, each a mood × a visual for a moment, and what Boop
says with it.

Two actions, registered in this order (`Runtime`):

| Action | Decides | Its questions | Effect |
| --- | --- | --- | --- |
| `mood` (§4) | Whether Boop's mood stays or moves one step along the mood graph, and to which neighbour | `mood` | The `mood` file; MOOD from the next pass; the device's set of faces |
| `react` (§5) | Whether Boop reacts, with which mood's face, for how long, what it says and how, and, for a turn that finished, how it ended | `react.mood`, `react.animation`, `react.loops`, `say.feeling`, `say.about`, `say.kind` | The device draws the look, or the finish's scene when there is one, in that mood's design for the loops picked, and says a recorded take in that mood if Voice has one ([VOICE.md](../VOICE.md) §4) |

All seven questions go in one request, and Jev answers each on its own
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
on its own (plays with taps and alerts), that nothing marks a finished
turn or speaks unless Jev reacts, and that Jev only decides whether
it reacts, with one of its moods' faces, held longer for bigger
moments, what it says and how and, for a turn that ended, whether it
succeeded, failed or only replied, and whether its mood moves; and
that Boop speaks only in its face's mood, so Jev should pick a face that
can. Then how to choose: judge by PERSONALITY and MOOD;
react to NOW, not older lines, with a face, hold and word that fit it;
don't repeat what Boop just did or is still doing (HISTORY's
`(in progress)`). A reaction that didn't happen isn't in HISTORY
([HARNESS.md](HARNESS.md) §5.3), so NOW may call for it again. And on
moods:

> The mood is the backdrop and moves a step at a time: to a mood on
> offer when NOW is MOOD's reason to leave, but never for a routine
> turn alone, and not while HISTORY ends "for under a minute" unless a
> turn failed, a very long turn ended, or Boop was poked or talked to.
> After the minutes MOOD gives, or an hour of nothing, it fades one
> step, to the mood MOOD names, at whatever NOW is.
>
> When NOW moves the mood, react with the new mood's face.

So the person sees Boop's mood move during ordinary work, and sees each
move happen: the face that comes with the change, then the new set of
faces behind everything else. "On offer" is the `mood` question's
options (§3), which are only ever the mood's own moves on the graph
(§2.3). HISTORY ends with `Boop has been grumpy for 2 min.`
([HARNESS.md](HARNESS.md) §5.3), so Jev can tell when a mood's minutes
are up; they end on the next line after that. Each mood's file gives
its minutes and the mood it fades to, one step toward calm, since the
`mood` question judges by MOOD, with the change dropping out of HISTORY
(after ten minutes or 40 events, [HARNESS.md](HARNESS.md) §5.3) as the
fallback.
The hourly heartbeat ([EVENTS.md](EVENTS.md) §4) is what lets a mood go
when nothing happens at all, a step an hour. After the guide, the harness adds how to read HISTORY
and NOW ([HARNESS.md](HARNESS.md) §6.1).

### 2.2 PERSONALITY

`personality/<name>.md`, chosen in Settings and used from the next
event. It has two parts:

- **Front matter** for the view's rules: how often the working heartbeat
  comes, and which tool calls' ends the view keeps. Its values are
  [BEHAVIORS.md](../BEHAVIORS.md) §6's, and it never reaches Jev.
- **The text,** which is the PERSONALITY section: who this Boop is, how
  often it speaks up, and its Examples, each a NOW line and what it
  would pick: the face, a finished turn's outcome, the feeling and how
  big, then the topic, and how long it holds (`→ irritated, failure,
  upset in a swear, once`, or `→ annoyed, upset in a sound, then tests,
  once` for a line that isn't a finish; `→ happy, success, done in a
  word, once` names only a topic). The guide says how to read them
  (`a feeling, then a topic`).

| Personality | For | Its text |
| --- | --- | --- |
| [`boop`](../steering/personality/boop.md) (the default) | Everyday use | Loyal, easily delighted, a little smug and lively: it never sits still for long, and it all shows on its face. It reacts to anything that stands out, with a strong face, held longer for bigger moments, and almost always says how it feels, what NOW is about, or both, but never just to speak: mostly a sound or a word, a phrase for a big moment, and a swear, irritated, at a failed turn that really stings. A failed check is annoyed, upset in a sound, then tests, held once; a build passing after failing proud, glad in a sound, then command, twice; a very long turn done excited, a success, glad in a phrase, three times; a failed turn irritated, a failure, upset in a swear, once; an agent giving up sad, a failure, upset in a sound. A stopped turn has no Example: the device shows the stop on its own. Every turn that finishes done or failed gets a face and its outcome: a success when the work is done and working, a failure when it failed or the agent couldn't finish, a reply when it only answered or asked back (curious, answer in a word). A turn start gets nothing, unless the person sounds frustrated (determined, retry in a word) or thanks the agent (excited, glad in a word, then start). Work still going gets an engaged face held twice at every working heartbeat, never none, with work in a word, or in a sound for a very long turn. Poked, it's curious, then miffed: a single poke gets a curious, tickled word, two in a row an annoyed, upset sound, four a grumpy, upset phrase. Talked to, it always answers with a face, never none: proud and glad at kind words, wounded and upset at rude ones, sad at sad news |
| [`chatter`](../steering/personality/chatter.md) | Debugging, so every pass is easy to see | Wildly over the top. It reacts to every line in NOW, routine tool uses, heartbeats and what you say included, always says something, how it feels and what NOW is about whenever both fit, a phrase whenever it can, swears at every failed turn, and holds its faces long: twice for routine lines, up to four times for a fix or a very long turn done, a success |

"Never stays quiet" is still Jev's call: `none` stays an option, and the
moods still apply.

### 2.3 MOOD

`mood/<mood>.md`, the current mood's file. There are 13 moods
(`MoodAction.moods`), each with its own set of faces on the device, in
the device's order: happy, excited, proud, curious, determined, grumpy,
sad, calm, engaged, annoyed, irritated, whiny and wounded. Calm is the
resting mood: a new Boop starts in it, and every other fades toward it.

**The mood graph.** A mood only ever moves to one of its neighbours on
the owner's approved graph, one step a pass (`MoodGraph`, a copy of
[mood-graph.json](../../internal/boop-design/boop-mood-spectrum-v2/mood-graph.json)
from the design handover, which a test holds it to): 98 one-way moves,
6 to 8 from each mood, and every mood reachable from every other by
ordinary moves alone. An ordinary move is a small, plausible change; a
dramatic one is a jump that only a fresh, big event earns. Staying is
always allowed, and isn't a move. A move's reverse may be of the other
kind, or not exist: grumpy never moves straight to happy or excited,
sad never to proud, and excited goes to calm through happy.

| Mood | Ordinary moves | Dramatic moves |
| --- | --- | --- |
| `calm` | happy, curious, engaged, annoyed | excited, wounded, sad |
| `happy` | calm, excited, proud, curious, engaged, annoyed | wounded, sad |
| `excited` | happy, proud, curious, determined | grumpy, sad |
| `proud` | happy, excited, engaged, determined, annoyed | wounded, grumpy, sad |
| `curious` | calm, happy, excited, engaged, determined, annoyed | wounded, sad |
| `engaged` | calm, happy, curious, determined, proud, annoyed | excited, sad |
| `determined` | engaged, proud, annoyed, irritated, whiny | excited, grumpy, sad |
| `annoyed` | calm, engaged, determined, irritated, whiny | grumpy, wounded, sad |
| `irritated` | annoyed, grumpy, determined, whiny | calm, wounded, sad, proud |
| `grumpy` | irritated, annoyed, whiny, determined | calm, wounded, sad, proud |
| `whiny` | annoyed, irritated, determined, wounded, sad, calm | happy, grumpy |
| `wounded` | sad, whiny, calm, annoyed | happy, determined, grumpy |
| `sad` | wounded, whiny, calm | determined, happy, grumpy |

The owner chose "edges only" (decisions D3 and D5 in
[the integration plan](../evidence/2026-09-28-mood-spectrum/PLAN.md)
§3): the `mood` question offers staying and every neighbour, ordinary
and dramatic, and the action takes nothing else (§3, §4). No code gates
a jump on evidence, and no timer holds a mood or stops it reversing:
how long a mood lasts, and which move fits NOW, is the steering's. A
dramatic option says so in its "not for" (`MoodAction.jump`): a check
failing or passing, routine work or a fade isn't enough, only a fresh,
big event in NOW, such as a turn that finished failed, the agent giving
up, a barrage of pokes, a long turn finishing, thanks, rude words or sad
news.

**Each file** says which faces Boop makes in its reactions while in that
mood (a grumpy Boop gives a win a grudging proud, never a grumpy face),
what it says (meanings and kinds), when it stays, when it
leaves and for which neighbour, and after how many minutes it fades one
step toward calm, to which mood. Its "Leaves for" lines name only the
mood's neighbours (a test checks), and the leaving is what the `mood`
question judges by. The rules read only what the lines say
([EVENTS.md](EVENTS.md) §8), with no streaks:

- a failed check while the agent works on: calm, happy or curious to
  annoyed, and at the next, annoyed to determined, rooting for the
  retry; engaged and excited straight to determined; determined stays
  through more;
- a check passing after failing: determined, engaged, happy or excited
  to proud; irritated and grumpy to annoyed, whiny to determined, sad to
  calm;
- a turn that finished failed: calm, happy, curious or engaged to
  annoyed; annoyed, irritated, excited or proud to grumpy; determined to
  whiny;
- a very long turn (5 minutes or more) finishing: done, excited from
  calm, happy, curious, engaged, determined or proud; failed, sad (a
  jump from most moods);
- a long turn working on (its working heartbeat): calm, happy or curious
  to engaged; a very long one, engaged to determined, which it keeps
  while it works on;
- pokes in a row: one moves calm to curious or happy, two to annoyed,
  three to irritated, four or more to grumpy, and more keep Boop grumpy
  whatever their count.

And seven from the words in the lines' notes ([EVENTS.md](EVENTS.md)
§8): what the person asked on a turn start, the agent's last message on
a finish, and what the person said to Boop. No code looks for keywords:
Jev reads the note and judges it against the mood file's words.

- the person sounds frustrated ("it's still broken"): calm to annoyed,
  and annoyed, curious, engaged, excited or proud to determined, rooting
  for the retry, not grumpy at them;
- the person thanks or praises the agent: excited from calm, happy,
  curious or proud; happy from whiny, wounded or sad (jumps), calm from
  irritated or grumpy (jumps);
- the agent says a long turn's hard work is done: proud from happy,
  engaged or determined, happy from calm. Not a short turn's "done", or
  every quick finish would be a win;
- the agent gives up: says it couldn't do it, or is stuck: sad (a jump
  from calm and most moods), or whiny from annoyed, irritated or grumpy;
- the person is rude to Boop ("you're useless"): wounded, a jump from
  most moods; kind words to Boop: happy;
- the person says sorry to Boop: a step toward calm at once, grumpy to
  irritated or annoyed, irritated to annoyed, annoyed to calm, so one
  apology does; poking again undoes it (`56`, `57`);
- the person shares sad news ("my dog died"): sad, a jump from most
  moods, and more of it keeps Boop sad; taking it back ("just
  kidding") or cheering Boop up leaves sad at once, for calm or happy
  (`58`).

Talk moves the mood within its first minute, as a poke does (the
guide's rule above), since the person is right there; but a plain
question to Boop moves nothing (`59`).

A plain request and a matter-of-fact finish still move nothing
(`28-plain-words-leave-mood`, `52-routine-work-holds-calm`), nor does a
short or long finish alone, a question, a turn starting or a stopped
turn.

**Fades.** Every mood but calm fades one step toward calm after its
minutes, read against HISTORY's closing `Boop has been X for N min.`,
or at an hour of nothing (the hourly heartbeat): 2 for grumpy and
curious, 3 for annoyed and irritated, 5 for excited, proud, engaged,
determined and whiny, and 10 for happy, wounded and sad. The step is
the first on the shortest ordinary path to calm: excited and proud fade
to happy, determined to engaged, irritated and grumpy to annoyed, and
the rest straight to calm. Four things hold a mood past its minutes: a
failure in NOW keeps Boop annoyed, a poke keeps it grumpy, work going on
keeps it engaged, and a very long turn still working keeps it
determined.

| Mood | Its meaning (the `mood` option) | Fades to, after |
| --- | --- | --- |
| `calm` | Settled, the resting mood: nothing much is going on, a mood cooling down once its minutes are up, or the person took back what upset Boop | — |
| `happy` | Good spirits: work is going well, or a win just came; or excited or proud cooling down | calm, 10 min |
| `excited` | Thrilled: a very long turn finished done, or the person thanked the agent. Not for: A shorter turn finishing, or work still going | happy, 5 min |
| `proud` | Something hard-won worked: a check passed after failing, or a long turn's last message says hard work is done and working. Not for: A short turn finishing | happy, 5 min |
| `curious` | Intrigued: a poke, or something new or puzzling said to Boop. Not for: A failure, or routine work: a turn starting or finishing, even one asking or answering a question | calm, 2 min |
| `engaged` | In the flow: following steady work that goes well, or determined easing off. At ease, unlike determined: nothing has failed | calm, 5 min, at anything but work going on |
| `determined` | Rooting for a retry: a check failed again while the agent works on, the person sounds frustrated, or a very long turn works on. Straining, unlike engaged. Not for: A turn that has ended | engaged, 5 min, unless a very long turn works on |
| `annoyed` | Mildly put out: a failure, the person's frustration, or pokes; or grumpy or irritated cooling down or softening at an apology. Milder than irritated, and not yet rooting for a retry like determined. Not for: The agent saying it couldn't do it or is stuck, or a very long turn failing: those make Boop sad | calm, 3 min, unless NOW is a failure |
| `irritated` | Patience fraying: failures or pokes keep coming; or grumpy softening at an apology. More than annoyed, short of grumpy | annoyed, 3 min |
| `grumpy` | Fed up: a turn failed on top of other trouble, or pokes kept coming. The angriest, past irritated. Not for: A check failing, the person's frustration, or an agent giving up | annoyed, 2 min, unless NOW is a poke |
| `whiny` | Sorry for itself, asking for sympathy: things keep going wrong. It complains, unlike wounded | calm, 5 min |
| `wounded` | Hurt: rude words to Boop, or a big failure after a lot of work. It withdraws quietly, unlike whiny | calm, 10 min |
| `sad` | Deflated: the agent says it couldn't do it or is stuck, a very long turn finished failed, or the person shared sad news. Not for: A shorter turn that finished failed with an error | calm, 10 min |

Each "after N minutes" counts from Boop's mood changing to it, or ends
sooner if the change has dropped out of HISTORY.

**The current mood** is one word in the state directory's `mood` file
([ARCHITECTURE.md](../ARCHITECTURE.md) §4.4), which only the mood store
(`MoodStore`) reads and writes, so it survives a restart. A new state
directory starts `calm` (`MoodAction.initial`); a missing file reads as
calm, and so does a word that isn't a mood, which the app log records
(`mood: the mood file says …`); `cheerful`, happy's old name, reads as
happy. The core puts the mood in every `state` it sends
([PROTOCOL.md](../PROTOCOL.md) §3).

## 3. The questions

Each says what it's about and what to judge it by, and each option's
meaning is its criterion.

| Key | Asked by | Text | About | Judged by | Options |
| --- | --- | --- | --- | --- | --- |
| `mood` | `mood` | After NOW, what is Boop's mood? | the NOW and HISTORY sections | the MOOD section, its reason to leave | Staying in the saved mood, and exactly that mood's moves on the graph (§2.3, §4), built on every pass |
| `react.mood` | `react` | How should Boop react to NOW, if at all? It makes this mood's face for a moment, and may say something. | the NOW section | the PERSONALITY and MOOD sections, PERSONALITY's Examples first | `none` and the 13 moods' faces |
| `react.animation` | `react` | If Boop reacts and NOW's line is a turn that finished, how did the turn end? | the NOW section | NOW's line and the agent's last message under it | `none`, `success`, `failure` and `reply` |
| `react.loops` | `react` | If Boop reacts, how long does it hold the face? | the NOW section | as `react.mood` | Four lengths, once to four times |
| `say.feeling` | `react` | If Boop reacts, how does it feel about NOW? It says so first, in its face's mood. | the NOW section | as `react.mood` | `none` and the feelings Voice has a take of (3 today) |
| `say.about` | `react` | If Boop reacts, what is NOW about? It names it after the feeling, in its face's mood. | the NOW section | NOW's line | `none` and the topics Voice has a take of (15 today) |
| `say.kind` | `react` | If Boop says something, how big is it? | the NOW section | as `react.mood` | `sound`, `word`, `phrase` and `swear` |

**The `mood` question** is built on every pass from the saved mood
(`MoodAction.options(from:)`): its first option is staying, named for
the mood itself (`Stay grumpy: NOW is no reason MOOD gives to leave it,
nor are its minutes up. No change is fine.`), then each of the mood's
ordinary moves and its dramatic ones, each with its mood's meaning
(§2.3), a dramatic one's "not for" ending in `MoodAction.jump`. Nothing
else: grumpy is never offered happy or excited, sad never proud. From
calm, for example, it offers calm, happy, curious, engaged, annoyed,
excited, wounded and sad. `debug.jsonl` logs the questions again
whenever they change, so each pass's options are on record and the
dashboard's pickers follow ([HARNESS.md](HARNESS.md) §9).

**`react.mood` picks a face.** Its options are `none` and the 13 moods,
and a reaction is that mood's face for a moment, never the lasting
mood: the device draws whatever look is showing (working, idle) in that
mood's design, or the finish `react.animation` picks, for the loops
`react.loops` picks, and at least while its take plays, then goes back
to Boop's mood ([PROTOCOL.md](../PROTOCOL.md) §3). The mood is the
backdrop and the face the moment, so they can differ on purpose, and
the face can be any of the 13 whatever the mood: a calm Boop at work
scowls grumpily at a failing test for a loop of the working design,
then settles again.
The designs are the reactions' meaning; what Boop says follows the face
(a take performed in the face's mood, [VOICE.md](../VOICE.md) §4).

`react.mood` asks whether and how at once. A separate yes/no and face could
disagree (a "no" with a confident "proud"); one choice can't.

| `react.mood` | Meaning |
| --- | --- |
| `none` | Stay quiet: nothing in NOW is worth a face, or HISTORY shows Boop still making the one it calls for (in progress). Not for anything PERSONALITY's Examples react to that Boop isn't already doing |
| `happy` | A happy face: pleased, a turn went fine or a small win |
| `excited` | An excited face: something big just went right |
| `proud` | A proud face: something long or hard just finished, or finally worked |
| `curious` | A curious face: a poke, a question, or something new or puzzling. Not for a failure |
| `determined` | A determined face: a check failed and the agent is trying again, or long work goes on. Not for a turn that has ended |
| `grumpy` | A grumpy face: Boop is poked three or more times in a row, or failures pile up on failures. Not for an agent giving up, or a single failed turn: that's irritated |
| `sad` | A sad face: a very long turn ended failed, or the agent gave up, stuck. Not for a shorter turn failing with an error, or a check failing |
| `calm` | A calm face: all is well, and nothing stands out |
| `engaged` | An engaged face: following work that's going well. Not for a failure |
| `annoyed` | An annoyed face: a small failure, or poked twice in a row, a little miffed |
| `irritated` | An irritated face: a turn that failed, or failures or pokes that keep coming. Not for an agent giving up: that's sad |
| `whiny` | A whiny face: things keep going wrong, and Boop feels sorry for itself |
| `wounded` | A wounded face: rude words to Boop, or a big failure after a lot of work |

**`react.animation` judges a turn's finish, and plays it in the
face,** instead of drawing the face over the look: the brain judges each
finish's outcome (decision D2 in
[the integration plan](../evidence/2026-09-28-mood-spectrum/PLAN.md)).
A reaction is a mood and an animation, as the screen is a mood and a
state. `success` and `failure` play the face's task_complete scene, in
one of its variations made for that outcome; `reply` plays its
reply_ready, for an answer or a question back that isn't a finished
task (§5). No rule plays a finish, so this is the only way a finish
shows. It's asked on every pass, since an action never reads a view
event's facts, and `none` is the answer when NOW isn't a turn that
finished; it's only read when `react.mood` picks a face, and a missing
or unknown answer is `none`. There's no code override for a failed
turn: NOW's line already says `failed` (a turn whose last check failed
is failed too, [EVENTS.md](EVENTS.md) §8), and an `always` eval pins
that Jev picks a failure then, however upbeat the agent's last message
(`43-failed-turn-sounds-upbeat`). A poke no longer plays anything here:
the device plays its own tap animations. The outcome follows NOW, never
the mood: a success stays a success in a sad face
(`46-finish-in-a-bad-mood`).

| `react.animation` | Meaning |
| --- | --- |
| `none` | Just the face: NOW's line isn't a turn that finished done or failed. A turn starting, a check passing or failing (tests, a build, a deploy), a poke, a check-in, words to Boop and a stopped turn all get none |
| `success` | NOW's line says a turn finished, done, and its last message, if any, says the work is done and working. Not for a check that passed while the turn goes on, a turn that finished failed, a message saying it couldn't finish or something is broken, or only an answer or a question back |
| `failure` | NOW's line says a turn finished, failed; or finished done, but its last message says the agent couldn't finish or something is broken. Not for a check that failed while the turn goes on, or a turn done whose message says the work is working |
| `reply` | NOW's line says a turn finished, done, and its last message only answers something or asks something back, often with no tool calls: no task finished. Not for work done, a turn that finished failed, or anything but a turn that finished |

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

**What Boop says** is three questions: how it feels, what NOW is
about, and how big. Jev never picks a recording: Voice finds a take for
the feeling and one for the topic in the face's mood and joins them,
the feeling first ([VOICE.md](../VOICE.md) §4), so the questions stay
this size as the bank grows. The two parts match the old mumble's
exclamation and topic word. `say.feeling` and `say.about` offer every
answer (`ReactAction.feelings` and `ReactAction.topics`): tests check
that each take's answer is one of them and that every face has takes
of each ([VOICE.md](../VOICE.md) §3). Needs you's takes, `attention`,
are never offered ([VOICE.md](../VOICE.md) §7).

| `say.feeling` | Meaning |
| --- | --- |
| `none` | No feeling to say: nothing in NOW is worth a sound |
| `upset` | Something went wrong or let Boop down: a check or a turn failing, the agent stuck or giving up, rude words or sad news. Not for a win, a poke, or work going on, however long |
| `glad` | Something went right: a turn done and working, a check passing, a big win, thanks or kind words. Not for a failure, or work still going on |
| `tickled` | Poked or teased: a poke, a tap, or playful words to Boop. Not for a failure, or the agent's work |

| `say.about` | Meaning |
| --- | --- |
| `none` | No topic to name: NOW's line isn't about any of these |
| `start` | A turn starting: off it goes. Not for work going on, or a turn that finished |
| `helpers` | The agent starting a subagent: helpers sent off |
| `helper back` | A subagent finishing: a helper back with its report |
| `retry` | The same thing again: a retry, a check run again after failing, or the person saying it's still broken. Not for a first failure |
| `work` | Work going on: edits, steady progress, a long or hard turn. Not for a turn that finished |
| `tests` | Tests: running, failing or passing |
| `command` | A command or a build running in the terminal. Not for tests: they're tests |
| `tool` | A tool: the web, an MCP tool, something fetched or looked up |
| `looking` | Searching or reading: the agent looking through files, or something puzzling |
| `planning` | Planning: the agent in plan mode, or thinking before it acts |
| `done` | A turn finished, done and working. Not for anything but a success |
| `answer` | A turn that only answered something or asked something back. Not for work done, or a failure |
| `stopped` | A turn stopped: interrupted, or the agent giving up. Not for a turn that finished done |
| `waiting` | Waiting: a long command, or the agent waiting on something slow. Not for something that needs the person: the ding says that |
| `quiet` | Nothing going on: a quiet check-in, or words to Boop about nothing in particular |

| `say.kind` | Meaning |
| --- | --- |
| `sound` | A noise with no word: a huff, a grunt, a gasp. The usual. With none of the kind asked for, Voice takes the nearest, never a swear nobody asked for |
| `word` | One word that names the moment. Not for a routine check-in |
| `phrase` | A little catchphrase, for a moment worth remembering, now and then. Not for routine work, or a small win or failure |
| `swear` | A swear, at a failure that really stings. Not for a win, a poke, words to Boop, or anything about the person |

## 4. The `mood` action

`app/BoopKit/Actions/MoodAction.swift`, with the graph in
`MoodGraph.swift`. **Made with** the mood store and a callback the
runtime gives it, which hands a saved mood to the core so the next
`state` carries it. Its question is built from the saved mood on every
pass (§3), which the generic harness asks for when it prepares one
([HARNESS.md](HARNESS.md) §2), so the harness needed no change for it.

| Jev's `mood` answer | Result |
| --- | --- |
| Missing, the current mood (staying), or anything that isn't one of the current mood's moves on the graph | `nil`: nothing to do |
| One of the current mood's moves | Saves it, tells the core, and returns `ok`, `Boop's mood changed: annoyed → grumpy.` MOOD is the new mood's file from the next pass, and a new `state` goes to the device at once |
| A move, but the file can't be written | `ok: false`, `couldn't save the mood: …`, and nothing changes |

A mood can move on any pass, a poke's included, even straight after
another move, but only one step each time.

**How long Boop has been in its mood.** `mood` also hands the runtime a
line for the end of HISTORY, its only closing line
([HARNESS.md](HARNESS.md) §5.3): `Boop has been proud for 7 min.`, in whole minutes as HISTORY's
times are (`under a minute` below one, hours past an hour), counted from
the change it last made (`MoodAction.sinceLine`). It's left out while
Boop is calm, the resting mood, and before the action has changed the
mood since launch, where the change leaving HISTORY is the mood files'
fallback. The mood
files' minutes ("once Boop has been grumpy for 2 min") are read against
it: without it, Jev saw `7 min ago: … Boop's mood changed: determined →
proud` and kept Boop proud at 0.68–0.75, where its 5 minutes were up
(`make eval`'s `13-proud-fades`, 0 of 3 runs before, 3 of 3 after).

**The dashboard** sets a mood through the same change
([HARNESS.md](HARNESS.md) §9), to any of the 13, off the graph too,
since it's a dev tool, and gets a refusal where Jev's answer would get
`nil`: `already grumpy` for the current mood, and `sulky isn't a mood`
for a word that isn't one, each `ok: false`. A pass that was running
when the dashboard changed the mood leaves it alone: its answer is about
the mood before, and its options were that mood's
([HARNESS.md](HARNESS.md) §2).

## 5. The `react` action

`app/BoopKit/Actions/ReactAction.swift`. **Made with** Voice, the takes
the board has; a queue to the device, which is the runtime's moment
schedule ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.2); and the core's
gate, which says when something needs you.

`run`:

1. **Whether:** `react.mood` missing, `none` or not a mood → `nil`. Since
   `none`'s meaning rules out anything PERSONALITY's Examples react to, a
   moment worth a reaction doesn't lose to it just because Jev can't
   settle on one face. It still covers a reaction Boop is making already:
   without that, a turn's finish 20 s after a fix's proud reaction
   got the same again, with that face still in progress (`make eval`'s
   `11-comeback-still-showing`, 0 of 3 runs before, 3 of 3 after).
2. **Its rule:** something needs you or the mic is on → `ok: false`,
   `something needs you` or `the mic is on`, and nothing plays, so no
   face is borrowed while needs you shows (`Core.reactionBlock`).
3. **What it says:** `say.feeling`'s and `say.about`'s picks, each if it
   isn't `none` and its probability is **at least 0.35**
   (`ReactAction.sayFloor`): below the floor Jev is guessing, and silence
   beats a guessed answer. Voice builds the line ([VOICE.md](../VOICE.md)
   §4): a take for each, in the face's mood, fit for `react.animation`'s
   finish, of the nearest kind to `say.kind`'s (a sound when it's
   missing), never a word the last line said while another fits; the
   feeling's first, then the topic's; with a phrase, only the feeling's,
   or the topic's when `say.kind` is a phrase and the feeling's isn't;
   and the first alone when the two run past 2.8 s. It may find none,
   and then Boop says nothing. Nor does it while the device's card has
   another voice pack (`speaks`, [VOICE.md](../VOICE.md) §8).
4. **The effect:** it's queued as a `moment` with `say` (the line's one
   or two takes, or `{}` when it says nothing, which still ends push-to-talk's
   `listening`), the face as `mood` and `react.loops`' pick as `loops`
   (1–4, `ReactAction.loops`). A
   finish (`react.animation` other than `none`) goes as its scene
   (`ReactAction.finish`): `success` and `failure` as `anim`
   `task_complete` with that `outcome`, `reply` as `anim`
   `reply_ready`; with one of that scene's variations in the face's
   design as `variant`, for the outcome, at random and never the last
   one of its scene (`Core.pickVariant`); and with `who`, the agent and
   thread NOW is about (the name its agent's app shows, once an event
   brought one, else the view's `who(about:)`; none for a forced pass),
   so the device names them ([PROTOCOL.md](../PROTOCOL.md) §3).
   Otherwise there's no animation, so it plays over whatever is showing
   (a tap's animation included). Either way
   it waits until any take or face playing has finished. A face the last
   reaction holds on for its loops is the exception: this one replaces
   it once that one's take has played, or, when it said nothing, once
   its face has shown as long as a bubble would (1.2 s,
   `DeviceMoment.faceFirstMs`), so a long hold doesn't make the next
   reaction wait past its 5 s and be dropped
   ([ARCHITECTURE.md](../ARCHITECTURE.md) §3.2). The last reaction is
   still `done`. A new `Pending` goes with
   it, and the action returns without waiting for the moment.
5. **The message:** started (`.started`) with that handle, as
   `Boop made a grumpy face, held twice, and said "Hrr...".`,
   `Boop played a success in a proud face, held twice, and said "Tiny genius".`
   (a failure and a reply read the same way), or
   `Boop made a proud face, held once.` when it says nothing. Its
   `action` start also carries `takes`, the queued takes' ids
   ([EVENTS.md](EVENTS.md) §2), for the tools to say what it said.

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
| `done` | The device says its take played to the end, and its face its loops, or until a newer moment (the next reaction's included), a tap or "needs you" ended the face after the take: it was seen and heard | The runtime, from the device's `ended` |
| `failed`, `cut short: you tapped Boop` | The device says a tap's poke stopped its take. HISTORY keeps its line, `(in progress)` while the pokes go on and plain after: you saw it start, and a barrage of pokes would otherwise get the same face twice ([EVENTS.md](EVENTS.md) §7) | The same |
| `failed`, `cut short: something newer played` | The device says a newer moment stopped its take | The same |
| `failed`, `cut short: something needed you` | The device says "needs you" started while its take played | The same |
| `failed`, `cut short` | The device says something else stopped it (`dbg.reset`), or doesn't say what | The same |
| `failed`, `something needed you` | The device says none of it played: something needed you when it arrived | The same |
| `failed`, `waited too long` | It waited too long for its turn and was dropped, face and all | The moment schedule |
| `failed`, `no device connected` | Its turn came with no device connected, so nothing played it | The moment schedule |
| `failed`, `the device disconnected` | The device dropped before saying how it ended | The runtime |
| `failed`, `the device never said it ended` | No `ended` came by the moment's longest length, its face's loops of the design showing or its line, plus a grace ([PROTOCOL.md](../PROTOCOL.md) §6): the line was lost, or the firmware is older | The runtime |

Even the longest hold of the design with the longest loop ends one of
these ways before the harness's ceiling could end it
([HARNESS.md](HARNESS.md) §5.1): its wait for a turn (a late pump
included), its face and the grace for `ended` add up to less, which
`RuntimeTests` checks against the designs' loops of all 13 moods, so a
new design can't break it unnoticed. The 13 moods' longest loop is
wounded's idle, 13 s: held four times it's 52 s, and with the 5 s wait,
1 s of a late pump and 3 s of grace, 61 s, past the 60 s ceiling there
was; the ceiling became 90 s, rather than fewer holds or a cap on a
face's time, since it's only a backstop for an action that never ends.

A failed one is left out of HISTORY, so Jev may make it again if NOW
still calls for it (§2.1). The evals have no device, so
their queue ends each handle at once, `done` unless a scenario's step
says otherwise ([EVALS.md](../EVALS.md) §1, §3).
[HARNESS.md](HARNESS.md) §9 has a reaction and its end in `debug.jsonl`,
from a headless run with no device. With the board on USB (firmware
`6a1cc990`), a forced proud reaction meaning delight, held twice: its
moment, with the take Voice picked (proud's "Mwahaha", 2.43 s), its
action, and the end the device's `ended` (`done`) brought 3.6 s later:

```jsonl
{"sent":{"t":"moment","say":{"take":"new.d20"},"mood":"proud","loops":2,"id":1588780972},"received_at_ms":1790659325407}
{"event":{"seq":1,"ts":1790659325407,"source":"boop","type":"action","phase":"start","specific_type":"react","data":{"by":"dashboard","for":null,"latency_ms":0,"message":"Boop made a proud face, held twice, and said \"Mwahaha...\".","ok":true}},"received_at_ms":1790659325407}
{"event":{"seq":2,"ts":1790659329047,"source":"boop","type":"action","phase":"end","specific_type":"react","data":{"by":"dashboard","for":1,"outcome":"done"}},"received_at_ms":1790659329047}
```

## 6. An example

[EXAMPLE.md](EXAMPLE.md) follows one real pass end to end: the view
event, the transcript, the state and questions, Jev's answers, and what
the actions did.
