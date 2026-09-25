# Boop: vision

Updated 2026-09-25. Why Boop exists, who it's for, and the promises it keeps.

## The short version

Boop is a small creature that lives on your desk. It has a personality of its
own, one that was seeded when it hatched and has been shaped since by living
alongside you. There's no reset button. After three months your Boop is
different from anyone else's, and it is recognisably yours.

It also happens to keep an eye on your AI agents. When you run three Claude
sessions and two Codex threads at once, Boop watches them for you. It mumbles
along while they work, perks up when one needs your approval on the
Mac, and cheers when something finishes.

The order matters. **The personality is the product.** Status and nudges
are table stakes; Anthropic already open-sourced a desk buddy that
does those. People will buy Boop for the useful parts, but they keep it, and
get attached to it, because of who it is.

## Who it is for

Super individuals: engineers, founders, creators, PMs and designers who run
Claude Cowork, Claude Code and Codex heavily and in parallel. Most are 33–42,
design-literate, and already have too many things beeping at them. They don't
want another dashboard, a gamified toy, or something that makes them feel
watched. What they want:

- a bit of warmth and company during long stretches of solo work;
- to know at a glance whether anything needs them, without switching windows;
- to see which agent needs them, deal with it, and get back to what they
  were doing.

## Personality first

Every design decision is weighed against one question: does this make Boop
more of a character, or less? When personality and productivity pull in
different directions, personality wins, as long as nothing the person relies
on breaks. "An agent needs you" still has to be fast and reliable, but how
Boop reacts to one is a question of character.

- **Grown, not chosen.** When you set it up, you name it and answer one
  question: sweet or cheeky? Everything else comes from chance and from
  living with you. There is no menu of traits.
- **Lasting.** Boop lives on your Mac, and the device is just its body.
  Reflash the device or replace it, and it's still the same Boop. There's no
  reset button.
- **Shown, never told.** Boop's mood and personality come out in how it
  moves, looks and sounds. You never see a mood meter, a trait score, or a
  line saying "I've noticed you seem stressed." You notice that it's been
  quieter today, and that's all.
- **Sassy about the world, kind to you.** It can roll its eyes at a flaky test
  or a stubborn agent. It never guilt-trips you, never dies of neglect, and
  never pesters you to come back. It does get hungry if you leave it alone
  for days, but you only see that when you look at it.

## It does not talk like a human

This is a deliberate decision. Boop speaks minion: a stream of gibberish
syllables, like the Minions from the films, that nobody is meant to
understand. At most one real English word slips through, and that word is
always about what's happening right now, such as *"…tests?"*, *"…docs!"* or
*"…bug."* Everything around the word is sound and feeling.

There are three reasons for this:

- **It's a creature, not an assistant.** The moment it speaks in full
  sentences, people start judging it as a chatbot, and it will lose that
  comparison. As a pet that half-speaks, it can be charming.
- **One word lands better than a sentence.** Tone carries the emotion and the
  single word carries the context. That's all a glance from across the desk
  can take in.
- **It keeps Boop fast, private and cheap.** Nothing has to generate polished
  language in real time.

The same applies when you talk to it. Boop replies in mumble with a face and
a real word at most. It doesn't answer questions or explain itself.

## How it should feel

You sit down and Boop is dozing. It opens one eye, then the other, and
stretches. You kick off a refactor in Claude Code and a test run in Codex.
Boop sits up and gets busy with you. Every so often it mutters to itself,
*"mi-ne? po… tests?"*, and you only half-notice. Nobody expects you to
follow it. It's like a colleague humming.

Twenty minutes in, Codex wants to run a shell command. Boop's light goes
amber and it looks straight at you with a little chirp. You're deep in a doc,
so you ignore it. A minute later it chirps again, and after that it buzzes
once on the desk. You glance over. It's Codex on the landing project, so you
switch to it and approve. Boop sees the agent carry on, gives a satisfied
little nod, and gets back to work.

The refactor finishes. Boop throws its hands up and cheers. The Codex tests
fail, and Boop gives the agent a side-eye. It's annoyed at the agent and
never at you.

Later it's been a long afternoon of failed builds. Nothing on screen says
so, but Boop gets calmer. It fidgets less and mumbles less. When you hold the button
and say "shut up," it pouts, zips its mouth, and goes quiet for a while.
It still tells you when an agent needs you.

Months later, it's a slightly different creature. It's cheekier, it trusts
the agents you rely on, and it perks up on Fridays because that's when you
ship. You didn't configure any of that. It grew.

## Who Boop is

1. **A character that grows.** Over weeks, its temperament drifts based on
   how you work together, and it keeps a small set of defining moments it can
   come back to.
2. **A creature that mirrors your vibe.** How the work is going and the time
   of day shape its mood. You only see this in how it behaves.
3. **A mumbler.** It keeps up a running commentary in minion gibberish that
   you're not meant to understand, with the odd real word.
4. **Something you feed.** The work you do together is its food, and it
   earns XP and levels up from it. Leave it alone for days and it gets
   hungry, and after a while slowly loses a little XP, but it can never lose
   a level or die. See [Behaviors](BEHAVIORS.md) §4.
5. **Something you can talk to.** Hold the button and speak. Tell it to be
   quiet, tell it good job, or just mumble at it and get mumbled back. The
   mic is on only while you hold the button.

## What Boop does for you

1. **Watches every agent at once.** Claude Code and Codex
   sessions show up in one place, and a glance tells you how many need you.
2. **Nudges when you're needed and backs off otherwise.** A waiting approval
   climbs a gentle ladder: a look, then a chirp, then a buzz. It never goes
   past that, and it never scolds.
3. **Tells you, never decides for you.** Boop shows which agent and project
   need you, and you approve or deny on the Mac in the agent's own prompt.
   Boop can't approve anything, so it can never let an agent do something
   you didn't agree to.
4. **Reacts to finished work.** It cheers when a task is done, gets flustered
   when something fails, then settles down.
5. **Keeps a private record.** The Mac app shows totals across all your
   projects: tasks finished, how many projects, days together, XP and level.
   It never shows a breakdown by project. A shareable buddy card is an idea
   for later ([FUTURE.md](FUTURE.md)).

## Look

"Warm Terminal": an oat matte body, a black glass face and one amber accent.
The face is two expressive eyes in the style of Cozmo, drawn procedurally so
every expression blends into the next. It should look like an object an adult
is happy to have on their desk, not like a toy.

## Promises

These are fixed. If a feature conflicts with one of them, the feature changes.

1. **Personality first, productivity second.** Nothing it needs to do for
   you breaks, but when the two compete, character wins.
2. **It never talks like a human.** Minion mumble with at most one real word,
   and that word always comes from what's happening.
3. **Its inner state stays inner.** Mood and temperament show up only in
   behaviour. Raw values exist only in a debug mode for development.
4. **Fast and rule-driven where it counts.** Anything that tells you an agent
   needs you is decided by plain rules and shows up in well under a second.
   The AI brain adds colour and is never in that path.
5. **Boop never approves anything.** It only notifies. Approving happens on
   the Mac, and urgent nudges come from plain rules.
6. **No reset button.** Boop's personality lives in a file on your Mac, not
   in the device or the model. It changes slowly, by at most one sentence a
   day, and it belongs to you.
7. **Private by construction.** There is no camera, the mic works only while
   you hold the button, and nothing logs your keystrokes. Boop's memory lives
   on your Mac. The default brain runs on the Mac too. If you add your own cloud API key, the cloud model receives
   short summaries and what you say to Boop, and never your code or
   transcripts.
8. **Never nags, never guilts.** Hunger is visible only when you look. It
   never makes a sound, never sends a notification and never interrupts.
9. **No leaderboards.** Stats stay private unless you choose to share them.
10. **It's your pet, not a brand mascot.** Boop is never branded as Claude or
    Codex. You name it.
11. **Changes are announced.** The brain's model, `steering.md` and the voice
    are pinned. When Boop's behaviour changes, it ships as a versioned,
    announced update, so the creature you know doesn't shift under you.

## What it is not

- It is not an assistant or a chatbot. It doesn't answer questions or hold
  conversations.
- It is not a dashboard. The desktop app stays in the background, and the
  creature is the interface.
- It is not an agent. It doesn't run tasks, spend money, approve requests or
  act for you in any way. Information only flows from your agents to Boop.
- It is not tied to one AI. The brain is swappable: Apple's on-device model
  by default, a cloud model with your own API key, or none at all. Boop stays the
  same creature either way.
- It has no always-on wake word and no camera, and that will not change.

## Scope

- **v1:** one Boop; Claude Code and Codex; personality, mood, mumble,
  push-to-talk, XP and hunger, nudges, reactions and the private record.
- **Not now:** life stages, retiring and backup, the buddy card, Claude
  Cowork, other agents, and more than one Boop. These are kept in
  [FUTURE.md](FUTURE.md). None of them should be designed out.
