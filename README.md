# Boop

`app/` and `firmware/` contain the active product. `plan/` holds its current
behavior, UX, architecture and verification specs. `archived/` holds the previous generation, which still
builds and runs: the Swift macOS menu bar app, the ESP32 firmware, the
hardware files and earlier research. The landing page lives at `landing/`
for Vercel deployment. Start with the [spec index](plan/README.md) and
[component behaviors](plan/BEHAVIORS.md) for current rules and tuning;
[plan/PLAN.md](plan/PLAN.md) tracks implementation and verification status.

The active Mac app is a quiet menu bar companion: click its icon for status,
XP, activity and settings. It opens no window at launch. Quiet mode mutes Buddy's
sounds without changing its screen behavior. From the repository root:

```sh
make build
make test
make run
```

The GUI should be launched by the user. See [plan/UX-APP.md](plan/UX-APP.md)
for the current desktop experience.

The v2 Waveshare firmware builds from the active tree:

```sh
cd firmware/esp32
tools/pio_ws.sh run -e ws-amoled164
python3 -m py_compile tests/hil/test_usb.py
```

For independent USB UI tests while the Mac app stays open, build
`-e ws-amoled164-usb-debug` and use the `--usb-only` device runner described
in [tools/dev/README.md](tools/dev/README.md). Restore normal firmware afterward;
Bluetooth integration uses normal firmware and one known Mac app instance.

The wrapper keeps toolchains and cache in the git-ignored
`firmware/esp32/.platformio-core/` of each worktree; build output is in `.pio/`.
The first build downloads dependencies; subsequent builds reuse them.

See [firmware/esp32/README.md](firmware/esp32/README.md) for device controls and HIL.

Webcam verification requires explicit permission and setup for that session.
For an authorized session, run `make webcam
ARGS='list'` from the repository root and follow the
[webcam workflow](tools/webcam/README.md). `make webcam-test` checks the tooling
without opening a camera.

## Previous generation

Historical code and build instructions remain in [archived](archived/README.md).
Run archived commands from `archived/`; new work belongs in the active tree.
