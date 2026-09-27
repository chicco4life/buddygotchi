# Boop: future ideas

Updated 2026-09-27. Ideas we like but aren't building in v1. Nothing here is
a promise. To pick one up, write it into the matching spec first, then add
it to [PLAN.md](PLAN.md).

## Parked

On 2026-09-26 v1 was cut to a minimal core in two steps, and the modes then
replaced the new day's reflection; everything below was built and working,
and its code, tests and specs are at git tag `v1-full` (the first step),
commit `fd1c083` (the second) and commit `9bb8004` (the reflection), for
example `git show v1-full:plan/BEHAVIORS.md`. Bring one back at a time.

| Feature | What it was | Where |
| --- | --- | --- |
| Cheer sizes | Three sizes by turn length (under 5 min, 5–20, over 20), a jingle and a warm light for the bigger two, and a burst of finishes upgrading one cheer | `v1-full` BEHAVIORS §3.1 |
| Failed-turn face | `oops`, then `side_eye` at the agent | `v1-full` BEHAVIORS §3.1 |
| Nudge ladder | A second chirp and a bigger lean at 45 s, then three amber pulses (or a buzz, with a motor) at 2 min; a tap stopped the nudges for that session | `v1-full` BEHAVIORS §3.2 |
| Morning ritual | `stretch` and `yawn` at the day's first activity | `v1-full` BEHAVIORS §3.3 |
| XP, levels and hunger | +1 XP a finished turn, +5 a day, a level every 50; hungry after 2 days and starving after 5 (tummy rumble, hopeful peeks, an empty bowl, −1 XP a day, never a level); `levelup` and `gobble`; "I'm away" pausing hunger | `v1-full` BEHAVIORS §4 |
| Mood | Energy, pace and pitch set by wins, failures and night, shaping how moments and the voice play | `v1-full` BEHAVIORS §5, VOICE §5 |
| Night | 23:00–07:00: dimmer, drowsier, fewer mumbles, and asleep when nothing works | `v1-full` BEHAVIORS §2 |
| Idle life | Glances, peeks and bobs while idle, and glancing down at the work while working | `v1-full` BEHAVIORS §2 |
| Brain faces | The brain's `face` tool (`happy`, `proud`, `smug`, `curious`, `sleepy`, `worried`, `sulky`, `love`, `side_eye`), and `say` showing its feeling's face | `v1-full` HARNESS §6, BEHAVIORS §7 |
| Touch-and-hold | Holding the face showed how Boop felt, from its mood | `v1-full` BEHAVIORS §3.3, UX §4 |
| Threads screen | Every session by agent, with its status | `v1-full` UX §3 |
| Stats and the record | Level ring, name and days together on the device; level, tasks finished, projects and days in the popover | `v1-full` UX §3, §7 |
| Focus mode | Holding the status strip: no sound or buzz, "needs you" visual only | `v1-full` BEHAVIORS §6, UX §4 |
| `zip` | Drawn but never played | `v1-full` BEHAVIORS §7 |
| `nod` | A nod when "needs you" cleared, and on a tap while it showed | `fd1c083` BEHAVIORS §5 |
| `thinking` and `shrug` | A thinking face while waiting for the brain's reply, and a shrug when it was too slow or the mic couldn't start; `listening` now covers the wait | `fd1c083` BEHAVIORS §3.3 |
| The no-app look | Eyes open, glancing about while waiting for the Mac; now the asleep face with the unplugged icon | `fd1c083` BEHAVIORS §2 |
| The new day's reflection | At a day's first activity the brain looked back on yesterday and could keep a line about you, a preference, a temperament sentence or a moment in `long-term.md` (only Jev ever did). Without it Temperament and Moments don't change; About you and Preferences still grow when you tell Boop something lasting | `9bb8004` HARNESS §2, §5; ARCHITECTURE §4 |

## Character and growth

- **Life stages.** Hatchling → Grown → Veteran, reached by both days
  together and level. When a stage arrives, Boop waits until you're around
  and does a short check-in ritual. Each stage changes its look and
  movement a little, its voice deepens, and its favourite syllables widen.
- **Hatching animation.** An egg on the device at setup that hatches once
  Boop is named. v1 just names Boop in the app.
- **Weekly report card.** A plain-language summary of the week in the app,
  about what happened rather than what Boop is like inside.

## Keeping Boop

- **Retire and memorial card.** A deliberate way to end a Boop that
  archives it and renders a keepsake card. The next Boop starts fresh.
- **Backup and moving Macs.** Opt-in, end-to-end encrypted backup of the
  memory files, and restoring Boop onto a new Mac.

## Record and sharing

- **Buddy card.** A shareable image with aggregate numbers only: totals
  across all projects, how many projects, the overall token count, days
  used, and XP and level. It never shows details of individual projects.
- **Token totals.** Needed for the card, from the usage numbers in each
  agent's local session files (numbers only, never text). They would never
  earn XP.

## Voice

- **Localised real word** for Korean and Japanese buyers. v1 is English
  only.
- **Echoing you.** When you mumble at Boop, it reuses some of your
  syllables, as if it were copying you.
- **Recorded voice.** A voice actor instead of synthesis, if the
  synthesised voice isn't warm enough.

## Agents and brain

- **Claude Cowork.** Blocked until Cowork's sandbox runs Claude Code hooks
  ([anthropics/claude-code#40495](https://github.com/anthropics/claude-code/issues/40495)).
- **Cursor and other agents.** Each needs an adapter and a reliable "you're
  being asked" signal ([ADAPTERS.md](ADAPTERS.md) §8).
- **A DeepSeek writer.** A cloud language model writing Boop's words in
  place of Apple's model, with the person's own API key: a new `Writer`
  ([HARNESS.md](HARNESS.md) §6) that, like Apple's, reads only its pass.
- **Mood from prompt tone.** Reading how you write to your agents. v1
  leaves prompt text out entirely.
- **More brain inputs,** such as coming back after a long break, or a
  periodic check-in while agents work.
- **Codex failures.** Codex has no failure hook; reading its session file
  when a turn stops would tell failures from finishes.

## The Mac app

- **Open a session from the menu bar.** Click a session in the list to open
  that conversation in Claude Code or Codex. Check first what each app can
  open: Claude Code's editor extension opens a session by ID, but a
  terminal session can only be resumed (never start a second copy of a
  running one), and Codex needs a link to the exact task. Promise the exact
  session only where the app can open it; otherwise say that only the app
  or project opens.

## More than one Boop

- **Several Boops per person**, such as one for Claude and one for Codex.
- **Banter scenes.** Short scripted mumble exchanges between your Boops,
  with a "record last scene" clip to share.
- **Relationships** between your Boops (rivalry, affection) that change
  slowly.
- **Greeting other people's Boops** nearby, over BLE advertising or
  ESP-NOW.
- **A second Boop sold as a bundle.**
