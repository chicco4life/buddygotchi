# Boop

Boop is a small creature that lives on your desk and watches your AI coding
agents, Claude Code and Codex. It mumbles in Minion-like gibberish while
they work, tells you when one needs your approval on the Mac, and
celebrates work that earns it. It has a personality of its own, and
there's no reset button. It never approves, denies or blocks anything: its hooks only
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
| Press BOOT, or touch the screen | Poke Boop: it reacts in its mood, and differently from the third poke in a row |
| Hold BOOT and speak (or click Talk in the popover) | Talk to Boop: the Mac's mic listens until you let go, and Boop answers with a face |

What Boop does and shows is in [plan/BEHAVIORS.md](plan/BEHAVIORS.md).

## Everyday commands

From the repo root:

| To | Run |
| --- | --- |
| Put the firmware on the board (over USB) | `make flash` |
| Run Boop, in the menu bar over Bluetooth | `make run` |
| Run Boop and print everything it sees and decides | `make debug` |
| Watch and poke it live in the debug dashboard | `make dash`, in a second terminal while `make debug` runs |
| See what it did in a day of `make debug`, and why | `make day` (`DATE=2026-09-28` for another day) |
| Check the brain against the eval scenarios | `make eval` |

`make run` and `make debug` use Bluetooth, so start them from your own
terminal, not an agent's. The dashboard shows the face, and side by side
Boop's mood, its automatic reactions and the ones Jev decided (with their
probabilities), and can force any mood, or a reaction with the same choices Jev has.
`make day` sums up a day by the hour, relaunches included: finishes, mumbles, faces, mood changes and what
made them, and how long each "needs you" took to clear.

`make eval` reads Jev's key only from the environment. To use the key you
saved in Settings:

```sh
BOOP_JEV_KEY=$(security find-generic-password -s com.boopcomputer.boop -a jev -w) make eval
```

### Without the board or Bluetooth

A headless Boop with a canned brain, and the dashboard on it:

```sh
.build/debug/Boop --headless --state-dir /tmp/boop --brain scripted --debug &
internal/tools/boopctl dash --state-dir /tmp/boop
```

## Where things are

What ships is in `app/` (the Mac app and its hook) and `firmware/`.
Tests, the simulator and the other dev tools are in
[internal/](internal/README.md), run as `make -C internal <target>`
([plan/VERIFICATION.md](plan/VERIFICATION.md) lists them). The specs start
at [plan/README.md](plan/README.md).

The [animation bank](internal/boop-design/README.md) is where the
device's designs and sounds come from: facegen and sfxgen build from it.
It has an offline review, and the mood graph's handover sits beside it.
