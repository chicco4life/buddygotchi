# Boop

Boop is a small creature that lives on your desk and watches your AI coding
agents. It mumbles in Minion-like gibberish while they work, tells you when
one needs your approval on the Mac, and cheers when work finishes. Its
personality grows with you and can't be reset.

- `plan/` is the spec. Start with [the index](plan/README.md), then
  [the vision](plan/VISION.md). [plan/PLAN.md](plan/PLAN.md) has the build
  order and status.
- `app/` is the Mac menu-bar app and the `boop-hook` hook client (Swift).
- `firmware/` is the firmware for the MicroTech MTR024QV01A board (ESP32 with
  a 2.4" screen).
- `tools/` has the device tool (`boopctl`) and the webcam recorder.
- `archived/` holds earlier generations. `landing/` is the landing page.

v1 is being rebuilt. The commands below are the targets from
[plan/PLAN.md](plan/PLAN.md) milestone M0:

```sh
make build        # build the Mac app
make test         # Swift unit tests
make run          # run the Mac app (from your own terminal, for Bluetooth)
make tools        # set up tools/.venv
make flash        # build and flash the firmware over USB
make sim          # render every screen in the simulator
tools/boopctl ping
```

How everything is checked, including what's on the screen, is in
[plan/VERIFICATION.md](plan/VERIFICATION.md).
