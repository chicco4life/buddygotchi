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
3. From the menu bar, install the hooks for Claude Code and Codex, one click
   each.

On the board:

| Do | What happens |
| --- | --- |
| Press BOOT, or tap the face | Boop it; acknowledges a cheer; quiets the nudges if something needs you |
| Hold BOOT | Push-to-talk while held (the Mac's mic is on only then, 30 s at most). Talk in the popover does the same from the Mac |
| Tap the status strip | Face → threads → stats → face |

The full picture is in [plan/UX.md](plan/UX.md) and
[plan/BEHAVIORS.md](plan/BEHAVIORS.md).

## Repo

| Path | What it is |
| --- | --- |
| `plan/` | The spec and the contract the code implements. Start with [the index](plan/README.md) and [the vision](plan/VISION.md); [plan/PLAN.md](plan/PLAN.md) has the build order and status |
| `app/` | Swift package: the `Boop` menu-bar app, the `boop-hook` hook client and the `boopdev` dev CLI |
| `firmware/` | PlatformIO firmware for the board (`cyd24`) and the simulator and unit tests (`native`) |
| `tools/` | `boopctl` (device tool), `voicegen` (voice assets), `fontgen`, `webcam/` (opt-in recorder), `build-loop.sh` |
| `skills/` | `doctor` (hook self-check) and `webcam-verify` |
| `landing/` | The landing page |
| `archived/` | History only; earlier code is at git tag `gen2-final` |

## Build and test

From the repo root. There's no Xcode needed: `make test` runs the XCTest
shim.

```sh
make build        # Boop, boop-hook, boopdev
make test         # Swift unit tests
make run          # the Mac app, with Bluetooth (from your own terminal)
make tools        # tools/.venv with pyserial and Pillow, for boopctl
make fw           # build the firmware
make flash        # build and upload over USB
make fw-test      # firmware unit tests on the Mac
make sim          # build the renderer simulator
make e2e          # hook → app → USB → board pipeline check
make webcam-test  # the webcam recorder's tests, on synthetic video (no camera)
```

`tools/boopctl` talks to the board over USB:

```sh
tools/boopctl ports | ping | state | shot | pattern
tools/boopctl sim [scenario…] [--accept]   # simulator vs goldens
tools/boopctl run [scenario…]              # board vs simulator, pixel for pixel
tools/boopctl bridge                       # share the serial port on a Unix socket
tools/boopctl e2e [--brain rules|apple]    # the pipeline check (needs the bridge's port free)
tools/boopctl e2e --soak 30 --brain apple  # the pipeline on a loop: resets, leaks, stuck states
tools/boopctl soak | perf                  # device-only soak, frame rate
tools/boopctl mumble | say | volume | sound | moment | needs  # hear and watch Boop by hand
tools/boopctl calibrate                    # touch calibration: tap 4 crosses (needs a person)
```

`app/.build/debug/boopdev` exercises the app without a board:

```sh
boopdev replay <hooks.jsonl>               # hooks through the adapter and core, on a virtual clock
boopdev memory --state-dir DIR             # the memory files as the store reads them
boopdev voice <feeling> [word]             # Minion lines as `say` builds them
boopdev brain --brain apple|rules|jev [--gap-min N] [--history N]  # the harness and brain on recorded triggers (L5); jev needs BOOP_API_KEY
boopdev hooks status|install|remove --home DIR
boopdev talk "<words>" --socket PATH       # a push-to-talk transcript to a headless app
```

For live checks without Bluetooth, run `tools/boopctl bridge` and
`Boop --headless --state-dir DIR --link usb:/tmp/boop-bridge.sock`.
`tools/.venv/bin/python tools/voicegen/voicegen.py` rebuilds the voice
assets in `firmware/assets/voice.h`.

How everything is checked, including what's on the screen, is in
[plan/VERIFICATION.md](plan/VERIFICATION.md).
