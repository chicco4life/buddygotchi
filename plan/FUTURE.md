# Boop: future ideas

A running list of ideas we like but aren't building in v1. Nothing here is a
promise. To pick one up, write it into the matching spec (UX, BEHAVIORS,
ARCHITECTURE…) first, then add it to [PLAN.md](PLAN.md).

## Character and growth

- **Life stages.** Hatchling → Grown → Veteran, reached by both days
  together and level. When a stage arrives, Boop waits until you're around
  and does a short check-in ritual. Each stage changes its look and movement
  a little, its voice deepens, and its favourite syllables widen.
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
- **Token totals.** Needed for the card. They'd come from the usage numbers
  in each agent's local session files (numbers only, never text), and would
  never earn XP.

## Voice

- **Localised real word** for Korean and Japanese buyers. v1 is English
  only.
- **Echoing you.** When you mumble at Boop, it reuses some of your
  syllables, as if it were copying you. v1 matches your energy.
- **Recorded voice.** A voice actor instead of synthesis, if the synthesised
  voice isn't warm enough.

## Agents and brain

- **Claude Cowork.** Blocked until Cowork's sandbox runs Claude Code hooks
  ([anthropics/claude-code#40495](https://github.com/anthropics/claude-code/issues/40495)).
- **Cursor and other agents.** Each needs an adapter and a reliable "you're
  being asked" signal ([ADAPTERS.md](ADAPTERS.md) §8).
- **Cloud brain switched on.** The interface exists in v1. This is about
  wiring it to the person's own API key (DeepSeek first) and testing it. It
  sends the conversation unchanged and in order so the provider's prompt
  cache applies ([HARNESS.md](HARNESS.md) §7).
- **Mood from prompt tone.** Reading how you write to your agents. v1
  leaves prompt text out entirely.
- **Richer brain triggers,** such as coming back after a long break, or a
  periodic check-in while agents work.
- **Codex failures.** Codex has no failure hook; reading its session file
  when a turn stops would tell failures from finishes.

## The Mac app

- **Open a session from the menu bar.** Click a session in the menu-bar
  list to open that conversation in Claude Code or Codex, and close the
  list. Check first what each app can open: Claude Code's editor extension
  opens a session by ID, but a terminal session can only be resumed (never
  start a second copy of a running one), and Codex needs a link to the
  exact task. Only promise the exact session where the app supports opening
  it; if only the app or project can be opened, say so.

## More than one Boop

- **Several Boops per person**, such as one for Claude and one for Codex.
- **Banter scenes.** Short scripted mumble exchanges between your Boops,
  with a "record last scene" clip to share.
- **Relationships** between your Boops (rivalry, affection) that change
  slowly.
- **Greeting other people's Boops** nearby, over BLE advertising or
  ESP-NOW.
- **A second Boop sold as a bundle.**
