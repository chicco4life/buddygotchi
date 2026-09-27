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

What Boop does and shows is in [plan/BEHAVIORS.md](plan/BEHAVIORS.md) and
[plan/UX.md](plan/UX.md).

## Commands

Everything you need, from the repo root:

```sh
make flash   # build the firmware and upload it to the board over USB
make run     # build and start the Mac app in the menu bar (Bluetooth)
make debug   # the same, with a live view of everything Boop sees and decides
internal/tools/boopctl dash   # with make debug running: the debug dashboard (face, brain passes, timeline, force a mood)
make eval    # the brain's eval scenarios against Jev (needs BOOP_JEV_KEY)
```

`make eval` reads Jev's key only from the environment. To use the key you
saved in Settings, run it from your own terminal:

```sh
BOOP_JEV_KEY=$(security find-generic-password -s com.boopcomputer.boop -a jev -w) make eval
```

The dashboard is in [plan/DASHBOARD.md](plan/DASHBOARD.md). Tests, the simulator and the other device tools are for development; they're in
[internal/](internal/README.md) and
[plan/VERIFICATION.md](plan/VERIFICATION.md).

The specs start at [plan/README.md](plan/README.md), and the repo layout
is in [CLAUDE.md](CLAUDE.md). What ships is in `app/` and `firmware/`;
tests, dev tools and everything else that doesn't is in
[internal/](internal/README.md).
