# Boop: vision

Updated 2026-09-30. Why Boop exists, who it's for, what v1 does, and the
promises it keeps. How it all works is in the other specs
([README.md](README.md)).

## The short version

Boop is a small creature that lives on your desk. It has a personality of
its own, and the plan is for that personality to grow out of living
alongside you, so that after a few months your Boop is different from
anyone else's and recognisably yours.

It also happens to keep an eye on your AI agents. When you run three Claude
sessions and two Codex threads at once, Boop watches them for you. It
naps while no agent is open, works along at a little keyboard while they
do, mutters now and then, lights up amber and knocks once when one needs
your approval on the Mac, and celebrates a finish that earns it.

The order matters. **The personality is the product.** Status and nudges
are table stakes; Anthropic already open-sourced a desk buddy that does
those. People will buy Boop for the useful parts, but they keep it, and
get attached to it, because of who it is.

## Who it's for

People who run Claude Code and Codex heavily and in parallel: engineers,
founders, creators, PMs and designers. They already have too many things
beeping at them, and don't want another dashboard, a gamified toy, or
something that makes them feel watched. They want a bit of company during
long stretches of solo work, and to see at a glance which agent needs
them, deal with it and get back to what they were doing.

## Personality first

Every design decision is weighed against one question: does this make Boop
more of a character, or less? When personality and productivity pull in
different directions, personality wins, as long as nothing the person
relies on breaks. "An agent needs you" still has to be fast and reliable,
but how Boop reacts to it is a question of character.

- **Grown, not chosen.** At setup you name it and answer one question:
  sweet or cheeky? There is no menu of traits. In v1 your answer is kept,
  and nothing uses it yet.
- **Lasting.** Boop lives on your Mac, and the device is just its body.
  Reflash the device or replace it, and it's still the same Boop.
- **Shown, never told.** Its feelings come out in how it moves, looks and
  sounds: 13 moods, each with its own face. You never see a mood meter,
  a trait score, or a line saying "I've noticed you seem stressed."
- **Sassy about the world, kind to you.** It grumbles at a failed test or a
  stubborn agent, never at you. It never guilt-trips you, never dies of
  neglect, and never pesters you to come back.

## It doesn't talk like a human

Boop half-speaks: a huff, a grunt or a gasp, one word that lands
(*"Done"*, *"Again"*, *"Yatta"*), now and then a little catchphrase
(*"Mamma mia"*), and a swear when a failure really stings. Each is a real
recording, performed in one of its moods, and it plays only with that
mood's face.

This is deliberate. The moment a creature speaks in full sentences,
people judge it as a chatbot, and it loses that comparison, while a pet
that half-speaks can be charming. The tone carries the feeling and the
word the moment, which is all a glance from across the desk can take in.
And it keeps Boop fast, private and cheap, since nothing has to write
language in real time: the brain picks what Boop means, never the words
([VOICE.md](VOICE.md)).

## Hero moments

Four moments show who Boop is. Each has one clear cause and one clear
feeling, so it reads from across the desk, in a demo or in a ten-second
clip. How each works is in [BEHAVIORS.md](BEHAVIORS.md) §3, and the
harness evals check the brain's part ([EVALS.md](EVALS.md)).

1. **A turn finishes, and it's happy for you,** as much as the finish
   earns: a small face for a quick one, the finish played as a success
   in its excited face with *"Bada bing bada boom"* for a big one. It judges each
   finish from what the agent said: a success, a failure, or only a
   reply.
2. **A turn fails, and it's grumpy for you.** Maybe a grumpy
   face and a *"Mamma mia"*, or a swear when it really stings.
3. **Yell at it, and it's sad.** This one waits for Boop to hear how
   you say things: v1's push-to-talk hears only the words.
4. **Poke it too much, and it grumbles.** One poke gets a curious look and
   its tap animation. Keep poking and it gets annoyed, then irritated and
   grumpy (*"Mamma mia"*), then calms down a step at a time.

## Scope

**What v1 does:**

- **Watches every agent at once.** Claude Code and Codex sessions show up
  in one place: the device's strip counts those working and those that
  need you, and the Mac app lists them all.
- **Tells you when you're needed.** An amber light, an amber sign, one
  knock-and-ding, and the agent and thread in the strip. You answer on the Mac,
  in the agent's own prompt ([BEHAVIORS.md](BEHAVIORS.md) §3.2).
- **Reacts like a creature.** Its look follows what its agents do:
  asleep, idle, working and at what (running tests or a command,
  reading, searching, sending off helpers, waiting, planning), needs
  you, and a short scene when a task starts, stops, fails a command or
  a helper comes back; its own animation for every tap, a bigger one
  for a barrage; with Jev, grunts and chatters while agents work
  ([BEHAVIORS.md](BEHAVIORS.md)).
- **Has a personality and moods.** Two personalities: `boop`, its
  everyday self, and `chatter`, an over-the-top one for debugging. 13
  moods, from calm, where it rests, to happy, grumpy, whiny or sad, each
  with its own face, and moving a step at a time along the owner's mood
  graph. With your own TypeSafe Jev key, Jev picks the mood and adds
  reactions with character: another mood's face for a moment, and a
  word or a sound in that mood, a finished turn's included, which Jev judges a success, a
  failure or only a reply; without one, Boop shows what its agents do
  and when you're needed, but doesn't react
  ([harness/HARNESS.md](harness/HARNESS.md)).
- **Hears you.** Hold its button, or click Talk, and speak: the Mac's
  mic turns it into words on the Mac, and with Jev, Boop answers with a
  face, and maybe a word or a sound. It can't talk back ([BEHAVIORS.md](BEHAVIORS.md)
  §3.3).

Its name and its sweet or cheeky nature are set when it hatches. Nothing else about its character grows in v1. A character that
grows with you, hearing how you say things, gentler nudges, a private
record and more are parked, to come back one at a time.

## Look

"Warm Terminal": an oat matte body, a black glass face and one amber
accent. The face is pixel art, two window eyes with pink cheeks and a
small mouth, in a design for each mood and state, and it blinks from one
to the next. It should look like an object an adult is
happy to have on their desk, not like a toy. v1 has the face and the
colours, on the board's screen and in the Mac app; the body comes later.

## Promises

These are fixed. If a feature conflicts with one of them, the feature
changes.

1. **Personality first, productivity second.** Nothing it needs to do for
   you breaks, but when the two compete, character wins.
2. **It never talks like a human.** A sound, a word or a little phrase
   at most, recorded in the mood it shows, and it fits what's happening.
3. **Its inner state stays inner.** Feelings show only in behaviour, never
   as meters or scores.
4. **Fast and rule-driven where it counts.** Anything that tells you an
   agent needs you is decided by plain rules and shows up within a second
   of Claude asking, and 2 s after Codex asks, since Codex's own reviewer
   may approve first ([ADAPTERS.md](ADAPTERS.md) §4). The brain adds
   colour and is never in that path.
5. **Boop never approves anything.** Its hooks only report, so it can
   never let an agent do something you didn't agree to. Approving happens
   on the Mac.
6. **No reset button.** Boop lives in files on your Mac, not in the device
   or the model, and it belongs to you. In v1 it keeps its name, nature,
   seed and mood ([ARCHITECTURE.md](ARCHITECTURE.md) §4).
7. **Private by construction.** There is no camera and no wake word, and
   the Mac's mic listens only while you hold Boop's button or after you
   click Talk, never longer than 30 s; the audio never leaves the Mac. Boop's memory lives on your Mac, and without a Jev key everything
   runs there. With one, each decision goes to TypeSafe with Boop's
   steering (its guide, personality and mood) and short lines about what
   just happened: which agent, which project or worktree, how a turn or a
   test run went, with what you asked, the agent's last message and
   what you said to Boop, cut short. Your code, commands, tool output and agents' transcripts never
   leave the Mac ([harness/EVENTS.md](harness/EVENTS.md) §9).
8. **Never nags, never guilts.** One alert per request, and the Mac app
   never sends notifications.
9. **No leaderboards.** Nothing about you is ranked or shared.
10. **It's your pet, not a brand mascot.** Boop is never branded as Claude
    or Codex. You name it.
11. **It changes only in a release, as far as we control it.** The
    steering files and the voice ship with the app. The model isn't
    pinned yet (Jev is TypeSafe's latest), so Boop's choices can shift a
    little when it changes. Pinning it is the goal.

## What it is not

- **Not an assistant or a chatbot.** It doesn't answer questions or hold
  conversations.
- **Not a dashboard.** The Mac app stays in the background, and the
  creature is the interface.
- **Not an agent.** It doesn't run tasks, spend money or act for you.
  Information only flows from your agents to Boop.
- **Not tied to one AI.** Plain rules keep the screen true (looks,
  "needs you", the tap's poke); Jev adds every reaction. Without it, Boop
  still watches your agents, just without reacting.
