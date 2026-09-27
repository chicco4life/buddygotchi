# Boop: vision

Updated 2026-09-27. Why Boop exists, who it's for, what v1 does, where it's
headed, and the promises it keeps.

## The short version

Boop is a small creature that lives on your desk. It has a personality of
its own, and the plan is for that personality to grow out of living
alongside you, so that after a few months your Boop is different from
anyone else's and recognisably yours.

It also happens to keep an eye on your AI agents. When you run three Claude
sessions and two Codex threads at once, Boop watches them for you. It
mumbles along while they work, perks up when one needs your approval on
the Mac, and cheers when something finishes.

The order matters. **The personality is the product.** Status and nudges
are table stakes; Anthropic already open-sourced a desk buddy that does
those. People will buy Boop for the useful parts, but they keep it, and
get attached to it, because of who it is.

## Who it is for

Super individuals: engineers, founders, creators, PMs and designers who run
Claude Cowork, Claude Code and Codex heavily and in parallel. Most are
33–42, design-literate, and already have too many things beeping at them.
They don't want another dashboard, a gamified toy, or something that makes
them feel watched. They want a bit of company during long stretches of
solo work, and to see at a glance which agent needs them, deal with it and
get back to what they were doing.

## Personality first

Every design decision is weighed against one question: does this make Boop
more of a character, or less? When personality and productivity pull in
different directions, personality wins, as long as nothing the person
relies on breaks. "An agent needs you" still has to be fast and reliable,
but how Boop reacts to it is a question of character.

- **Grown, not chosen.** At setup you name it and answer one question:
  sweet or cheeky? Its voice gets a dialect of its own from a random seed
  ([VOICE.md](VOICE.md) §3). There is no menu of traits; the rest is meant
  to come from living with you. In v1 your answer is a line in Boop's
  memory that the models read when they choose its words; nothing else
  uses it yet.
- **Lasting.** Boop lives on your Mac, and the device is just its body.
  Reflash the device or replace it, and it's still the same Boop.
- **Shown, never told.** Its feelings come out in how it moves, looks and
  sounds. You never see a mood meter, a trait score, or a line saying
  "I've noticed you seem stressed."
- **Sassy about the world, kind to you.** It grumbles at a failed test or a
  stubborn agent, never at you. It never guilt-trips you, never dies of
  neglect, and never pesters you to come back. Its feelings about you pass
  in seconds.

## It does not talk like a human

Boop speaks minion: a stream of gibberish syllables, like the Minions from
the films, that nobody is meant to understand. At most one real English
word slips through, and it fits what's happening right now, such as
*"…tests?"*, *"…done!"* or *"…ugh."* When you talk to it, it mumbles back
the same way; it doesn't answer questions or explain itself.

This is deliberate. Boop is a creature. The moment it speaks in full
sentences, people judge it as a chatbot, and it loses that comparison,
while a pet that half-speaks can be charming. One word lands
better than a sentence: tone carries the feeling and the word the context,
which is all a glance from across the desk can take in. And it keeps Boop
fast, private and cheap, since nothing has to write polished language in
real time.

## How it should feel

You sit down and Boop is asleep, eyes shut, a little "zzZZ" drifting up.
You open Claude Code and it wakes. You kick off a refactor, and a test run
in Codex, and Boop gets to work with you: a focused look, a sweat drop, a
small strain every couple of seconds. Every few minutes it mutters to
itself, *"mi-ne? po… tests?"*, and you only half-notice. Nobody expects
you to follow it. It's like a colleague humming.

Twenty minutes in, Codex wants to run a shell command. Boop's light goes
amber, it turns and leans towards you with one little chirp, and its bubble
says *codex · landing*. It won't chirp again. When you get to it, you
approve in Codex, and Boop sees the agent carry on and goes back to work.

The refactor finishes. Boop hops, beams, a heart pops up, and it mumbles
something proud. Then Claude wraps up a fix with the tests still failing:
no cheer this time, just an annoyed mumble at the agent, *"tu-ka… tests."*

Later you hold the button and snap "shut up". Boop mumbles something small
and sad, and carries on. Say "be quiet for an hour" and it stops mumbling
for the hour, though it still chirps when an agent needs you. Poke it again
and again and it grumbles, *"…nope!"*, and a moment later it has forgotten
all about it.

## Hero moments

Four moments show who Boop is. Each has one clear cause and one clear
feeling, so it reads from across the desk, in a demo or in a ten-second
clip. How each works is in [BEHAVIORS.md](BEHAVIORS.md) §3 and §6, and the
harness evals check the brain's part ([EVALS.md](EVALS.md) §5).

1. **A turn finishes, and it cheers for you.** Three hops, a happy squint
   and a beating heart, and maybe a proud mumble.
2. **A turn fails, and it's annoyed for you.** No cheer, just an annoyed
   mumble that names what broke, *"…tests."*, or *"…ugh."* when there's
   nothing to name.
3. **Yell at it, and it's sad.** Snap at it or tell it off, and it mumbles
   something small and sad.
4. **Poke it too much, and it grumbles.** One poke gets a happy wiggle and a
   heart. Keep poking and it grumbles (*"…nope!"*), and a few seconds
   later it has forgotten all about it.

Calm mode keeps hurt and grumbles to itself ([BEHAVIORS.md](BEHAVIORS.md)
§6).

## Scope

### What v1 does

- **Watches every agent at once.** Claude Code and Codex sessions show up
  in one place: the device's strip counts those working and those that
  need you, and the Mac app lists them all.
- **Tells you when you're needed.** An amber light, one chirp, and the
  agent and project in the bubble. You answer on the Mac, in the agent's
  own prompt.
- **Reacts like a creature.** A face that sleeps, idles, works and looks
  at you, mumbles while agents work, and the hero moments above.
- **Listens.** Hold its button, or click Talk in the Mac app, and speak.
  Boop mumbles back, goes quiet when asked, and keeps the facts you tell
  it: today's for today, lasting ones about you for good (you can see and
  remove those in Settings).
- **Reacts as much as you like:** chatty, normal or calm
  ([BEHAVIORS.md](BEHAVIORS.md) §6).

Its name, its sweet or cheeky nature and its voice are set when it
hatches. Nothing else about its character changes in v1.

### Where Boop is headed

Most of this is parked and comes back one feature at a time
([FUTURE.md](FUTURE.md)).

- **A character that grows.** Over weeks its temperament drifts with how
  you work together, and it keeps a few defining moments to come back to.
  Months in, it's cheekier, trusts the agents you rely on, and perks up on
  Fridays because that's when you ship. You didn't configure any of that.
- **A mood that mirrors yours.** How the work is going and the time of day
  shape it. After a long afternoon of failed builds Boop gets calmer,
  fidgets less and mumbles less. Nothing on screen says so.
- **Something you feed.** The work you do together earns XP and levels.
  Leave it alone for days and it gets hungry, which you see only when you
  look, and slowly loses a little XP, but it never loses a level or dies.
- **Gentler nudges.** A waiting approval climbs a ladder: a second chirp
  and a bigger lean, then a few amber pulses (a buzz, once there's a
  motor), and never more.
- **A private record.** Totals across all your projects: tasks finished,
  projects, days together, XP and level, never a breakdown by project.
- **Not started:** life stages, retiring and backup, a shareable buddy
  card, Claude Cowork, other agents, and more than one Boop. None of them
  should be designed out.

## Look

"Warm Terminal": an oat matte body, a black glass face and one amber
accent. The face is pixel art, two window eyes with pink cheeks and a bar
mouth ([UX.md](UX.md) §2), drawn from code so every expression blends into
the next. It should look like an object an adult is happy to have on their
desk, not like a toy. v1 has the face and the colours, on the board's
screen and in the Mac app; the body comes later.

## Promises

These are fixed. If a feature conflicts with one of them, the feature
changes.

1. **Personality first, productivity second.** Nothing it needs to do for
   you breaks, but when the two compete, character wins.
2. **It never talks like a human.** Minion mumble with at most one real
   word, and that word fits what's happening.
3. **Its inner state stays inner.** Feelings show only in behaviour, never
   as meters or scores.
4. **Fast and rule-driven where it counts.** Anything that tells you an
   agent needs you is decided by plain rules and shows up within a second
   of Claude asking, and 2 s after Codex asks, since Codex's own reviewer
   may approve first ([ADAPTERS.md](ADAPTERS.md) §4). The brain adds
   colour and is never in that path.
5. **Boop never approves anything.** It only tells you, so it can never let
   an agent do something you didn't agree to. Approving happens on the
   Mac.
6. **No reset button.** Boop lives in files on your Mac, not in the device
   or the model, and it belongs to you. What it keeps about you changes
   only when you tell it something lasting, and you can remove any line.
7. **Private by construction.** There is no camera and no wake word. The
   mic is on only while you hold the button or until you click Send.
   Nothing logs your keystrokes. Boop's memory lives on your Mac, and
   without an API key everything runs there. With a Jev key (normal mode),
   each decision goes to TypeSafe with Boop's memory, `steering.md`, short
   lines about what just happened and what you said to Boop. Your code,
   prompts and agents' transcripts never leave the Mac
   ([HARNESS.md](HARNESS.md) §6).
8. **Never nags, never guilts.** One chirp per request, and the Mac app
   never sends notifications. When hunger comes back, it will show only
   when you look: no sound, no notification, no interruption.
9. **No leaderboards.** Stats stay private unless you choose to share them.
10. **It's your pet, not a brand mascot.** Boop is never branded as Claude
    or Codex. You name it.
11. **It changes only in a release, as far as we control it.**
    `steering.md` and the voice ship with the app. The models aren't pinned
    yet (Jev is TypeSafe's latest, and Apple's model updates with macOS),
    so Boop's choices and words can shift a little when they change.
    Pinning them is the goal.

## What it is not

- **Not an assistant or a chatbot.** It doesn't answer questions or hold
  conversations.
- **Not a dashboard.** The Mac app stays in the background, and the
  creature is the interface.
- **Not an agent.** It doesn't run tasks, spend money or act for you.
  Information only flows from your agents to Boop.
- **Not tied to one AI.** Plain rules or a cloud model with your own key
  decide what Boop does, and Apple's on-device model writes its words
  ([HARNESS.md](HARNESS.md) §6). It's the same creature either way.
