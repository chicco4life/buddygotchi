# Boop

Boop is a small creature that lives on your desk and watches your AI coding
agents, Claude Code and Codex. It mumbles in Minion-like gibberish while
they work, tells you when one needs your approval on the Mac, and cheers
when work finishes. It has a personality of its own, and there's no
reset button. It never approves, denies or blocks anything: its hooks only
report, and they fail open.

A Mac menu-bar app does the thinking. A cheap ESP32 board with a 2.4" touch
screen (MicroTech MTR024QV01A) is the body: it only draws and reports, over
Bluetooth or USB. Why it exists and what's in v1 are in
[plan/VISION.md](plan/VISION.md).

## Using it

You need macOS 26 or later with Command Line Tools (Xcode isn't needed)
and PlatformIO's `pio`.

1. Plug the board in over USB and run `make flash`.
2. From your own terminal, run `make run`. It builds everything and starts
   the app in the menu bar.
3. The first time, the popover walks you through setup: a name, sweet or
   cheeky, and which agents to watch. Boop adds its hooks to
   `~/.claude/settings.json` and `~/.codex/hooks.json`; restart open agent
   sessions so they load them. The app then finds `Boop-XXXX` over
   Bluetooth and connects.

Settings → Agents connects, repairs or removes the hooks later.

On the board:

| Do | What happens |
| --- | --- |
| Press BOOT, or touch the screen | Boop it: a happy wiggle |
| Hold BOOT | Push-to-talk. The Mac's mic is on only while you hold it. Talk in the popover does the same from the Mac |

What Boop does and shows is in [plan/BEHAVIORS.md](plan/BEHAVIORS.md) and
[plan/UX.md](plan/UX.md).

## Entry points

From the repo root:

```sh
make run          # the Mac app, with Bluetooth
make debug        # the same, printing everything live in this terminal
make test         # Swift unit tests
make eval         # the brain's eval scenarios against Jev, 3 runs each (needs BOOP_JEV_KEY)
make flash        # build the firmware and upload it over USB
tools/boopctl     # the board over USB, and the simulator: ping, state, shot, play, sim, run, e2e, …
```

To run the evals with the key you saved in Settings, run this from your
own terminal (agents never read the Keychain):

```sh
BOOP_JEV_KEY=$(security find-generic-password -s com.boopcomputer.boop -a jev -w) make eval
```

Each tool lists its options with `--help`: `tools/boopctl`,
`app/.build/debug/boopdev`, `app/.build/debug/Boop`. Every make target and
tool is described in [plan/VERIFICATION.md](plan/VERIFICATION.md) §2.

## Debugging

- **What is Boop doing, and why?** `make debug` shows everything in one
  terminal as it happens: every hook and what Boop made of it, the core's
  decisions, every line sent to the board, and every brain pass with what
  the brain read (the input, the memory, the recent transcript), what it
  decided and why, the words it wrote, and what ran. The passes are also
  saved to `~/Library/Application Support/Boop/debug.jsonl`, fresh each
  launch (the format is in [plan/harness/HARNESS.md](plan/harness/HARNESS.md) §8).
- **What happened in a saved run?** `app/.build/debug/boopdev watch FILE`
  prints a `debug.jsonl` the way `make debug` does. With no file it
  follows the everyday app's. `make eval` names the file it writes.
- **Does the whole path work?** `make e2e` sends recorded hooks through the
  real `boop-hook` and a headless app to the board over USB, and checks
  what the board shows.
- **Are my agents' hooks reaching Boop?** Run `skills/doctor/doctor.sh`
  from inside the agent. It says what to do next.
- **What is the board doing?** `tools/boopctl ping`, `state` or `shot`.
- **What does Boop remember?** Its name and voice in `long-term.md`, in
  `~/Library/Application Support/Boop`, next to `boop.log`.

The specs start at [plan/README.md](plan/README.md), and the repo layout
is in [CLAUDE.md](CLAUDE.md).
