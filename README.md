# Boop

Boop is a small creature that lives on your desk and watches your AI coding
agents (Claude Code and Codex). It mumbles in Minion-like gibberish while
they work, tells you when one needs your approval on the Mac, and cheers
when work finishes. Its personality grows with you and can't be reset. It
never approves, denies or blocks anything: the hooks only report, and they
fail open.

A Mac menu-bar app does the thinking. A cheap ESP32 board with a 2.4" touch
screen (MicroTech MTR024QV01A) is the body: it only draws and reports, over
Bluetooth or USB.

## Using it

1. Flash the board: plug it in over USB and run `make flash`.
2. Build and start the app from your own terminal: `make run`. It finds
   `Boop-XXXX` over Bluetooth and connects.
3. In the popover, connect Claude Code and Codex, one click each.

On the board:

| Do | What happens |
| --- | --- |
| Press BOOT, or touch the screen | Boop it (`wiggle`) |
| Hold BOOT | Push-to-talk while held (the Mac's mic is on only then, 30 s at most). Talk in the popover does the same from the Mac |

The full picture is in [plan/UX.md](plan/UX.md) and
[plan/BEHAVIORS.md](plan/BEHAVIORS.md).

## Entry points

From the repo root (no Xcode needed):

```sh
make run          # the Mac app, with Bluetooth
make debug        # the same, printing everything Boop sees and decides as it happens
make test         # unit tests
make eval         # what the brain decides, scenario by scenario; REAL=1 with the real models
make flash        # the firmware, onto the board over USB
```

Each tool lists its own options: `tools/boopctl --help`,
`app/.build/debug/boopdev --help`, `app/.build/debug/Boop --help`.

## Debugging

- **What is Boop doing, and why?** `make debug`. Its terminal shows every
  hook with what Boop made of it, the core's decisions, every line sent to
  the board, and every brain pass: the input, the memory and transcript
  window the models read, what Stage 1 decided and why, Stage 2's words,
  and what ran. The passes are also in
  `~/Library/Application Support/Boop/debug.jsonl`, fresh each launch;
  `app/.build/debug/boopdev watch` prints that file the same way.
- **Are my agents' hooks reaching Boop?** `skills/doctor/doctor.sh`, from
  inside the agent (it tells you the next step).
- **What do the models say?** `make eval REAL=1`, then
  `app/.build/debug/boopdev watch` on the file it names, for every pass
  behind the results.
- **What is the board doing?** `tools/boopctl ping`, `state` or `shot`, over
  USB.
- **What does Boop remember?** `long-term.md` and `short-term.md` in
  `~/Library/Application Support/Boop`, next to `boop.log`.

Everything else, including the simulator, the pipeline check and the
webcam, is in [plan/VERIFICATION.md](plan/VERIFICATION.md).

## Repo

| Path | What it is |
| --- | --- |
| `plan/` | The spec and the contract the code implements. Start with [the index](plan/README.md) and [the vision](plan/VISION.md); [plan/PLAN.md](plan/PLAN.md) has the build order and status |
| `app/` | Swift package: the `Boop` menu-bar app, the `boop-hook` hook client and the `boopdev` dev CLI |
| `firmware/` | PlatformIO firmware for the board (`cyd24`) and the simulator and unit tests (`native`) |
| `tools/` | `boopctl` (device tool), `voicegen` (voice assets), `fontgen`, `webcam/` (opt-in recorder) |
| `skills/` | `doctor` (hook self-check) and `webcam-verify` |
| `landing/` | The landing page |
| `archived/` | History only; earlier code is at git tag `gen2-final` |
