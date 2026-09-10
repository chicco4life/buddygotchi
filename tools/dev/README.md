# Parallel development

Create one Git worktree per feature (`codex/<feature>` branches). Run these
commands from each worktree root:

```sh
make headless
make e2e
python3 tools/dev/instance.py status
python3 tools/dev/instance.py run -- app/tools/e2e/codex.sh
app/tools/headless.sh --stop
```

Each worktree uses a private directory under `/tmp/boop-dev-<uid>-<path-hash>`:
its own port, generated token, config, database, log, PID metadata, and defaults
suite. State persists between starts. The app disables Bluetooth and hook
installation in headless mode. Tests use explicit instance configuration;
normal agent hooks continue targeting the everyday app. `run` serializes
scenarios within that instance. Other worktrees run independently. Do not
remove a live instance's files. Stop it before deleting its worktree.

`BOOP_BIN=/absolute/path/to/Boop make headless` selects a packaged binary.
Headless smoke leaves the instance running for inspection; stop it explicitly.
The doctor uses the separate legacy `headless-shared-hooks.sh` launcher because
its live hook check must use the globally registered endpoint. That diagnostic
is exclusive and cannot run alongside the everyday GUI. It is not the parallel
feature testing path.

## Shared ESP32

Choose one of two verification paths:

- **Independent USB device/UI work (default for visual changes):** build
  `ws-amoled164-usb-debug` through `firmware/esp32/tools/pio_ws.sh`. This
  compile-time-only build has no active Bluetooth bridge and leaves saved
  bonds untouched. The Mac GUI can stay open and be developed independently.
  Run the device wrapper with `--usb-only`; it checks `ping.usbOnly == true`
  after setup and before running the scenario. A normal image is rejected.
- **Bluetooth integration:** use normal `ws-amoled164` firmware and exactly
  one identified Mac app build. Reserve the device and coordinate that app
  explicitly. The existing default runner still requires the GUI closed;
  an agent BLE client can then be the single host. Testing the actual Mac
  GUI requires a separately coordinated integration session, not `--usb-only`.

The USB path changes no production app behavior. Never ship the debug image
or use it as evidence of Bluetooth integration. Flash normal firmware back
when finished. Keep the device plugged in over USB throughout testing.
The shared device reservation still serializes flashing and hardware tests.

For USB-only testing with the GUI open:

```sh
cd firmware/esp32
tools/pio_ws.sh run -e ws-amoled164-usb-debug
# From the repo root, using immutable setup/restore images:
python3 tools/dev/device.py --usb-only \
  --setup /absolute/path/flash-usb-debug.sh \
  --restore /absolute/path/restore-normal.sh \
  --evidence /tmp/usb-device-check -- \
  python3 -m pytest firmware/esp32/tests/hil/test_usb.py
```

Without `--usb-only`, quit the Boop GUI and leave it closed until the run
ends. The runner holds the GUI singleton lock during this default path.
Headless instances can remain running. Relaunch the GUI yourself afterward;
agents must not launch the Bluetooth app.

For a scenario using the firmware already on the device:

```sh
make hil
# or a custom bounded scenario:
python3 tools/dev/device.py --evidence /tmp/feature-device-check -- \
  python3 firmware/esp32/tools/buddyctl.py ping --json
```

For firmware changes, supply executable setup and restoration scripts:

```sh
python3 tools/dev/device.py \
  --setup /absolute/path/flash-candidate.sh \
  --restore /absolute/path/restore-known-good.sh \
  --evidence /tmp/feature-device-check -- \
  python3 -m pytest firmware/esp32/tests/hil -m 'not ble'
```

Build both images before reserving. Setup must flash the correct board image
and query its identity; restore must flash and verify a previously saved
known-good image. Use immutable image paths, not a build directory another
job can overwrite. The runner requires restoration whenever setup is supplied.
It attempts restoration after failed setup, failed tests, or interruption.
SIGKILL, machine shutdown, and failed flashing can still require manual recovery.
No setup means the runner does not flash or restore firmware automatically.

One machine-wide advisory lock covers the whole run, including restoration.
Other runners queue. `buddyctl` CLI and direct pytest HIL sessions participate;
child commands inherit the reservation. Raw PlatformIO/esptool commands and
other BLE clients must run inside the wrapper. Do not open the GUI or a serial
monitor during a reservation. The lock cannot control unrelated programs.

Evidence contains separate setup/scenario/restore logs plus commit, dirty-tree
status, command, times and exit codes. Use a fresh evidence directory per run.
A failed restore is reported as a failed run; inspect it before using the device.
No hardware reservation, flashing, or webcam access occurs during tooling tests:

```sh
python3 -m unittest discover -s tools/dev/tests -v
```

To repeat the concurrency test with the actual built app instead of the HTTP
fixture (requires localhost access):

```sh
BOOP_WORKFLOW_TEST_BINARY="$PWD/app/.build/debug/Boop" \
  python3 -m unittest discover -s tools/dev/tests -v
```

### Firmware build isolation

`firmware/esp32/tools/pio_ws.sh` defaults to the worktree-local, git-ignored
`firmware/esp32/.platformio-core/` for PlatformIO platforms, packages, cache,
and bookkeeping. Compiled output stays in `firmware/esp32/.pio/`. This keeps
parallel worktrees from changing each other's toolchains and allows builds
with workspace-only write access. First builds require network access to
install dependencies; warm builds reuse local packages. Each worktree needs
several GB of toolchains. Explicit `PLATFORMIO_CORE_DIR` and
`PLATFORMIO_PACKAGES_DIR` overrides are supported for managed environments.
The physical-device reservation remains separate and is needed only for
flashing and hardware tests.
