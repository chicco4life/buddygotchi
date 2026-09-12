# Three-story device demo

A presenter-controlled mock of **success**, **failure/retry**, and **needs you**.
All events and words are scripted. This is a device presentation demo, not an
agent-hook, Mac UI, Bluetooth or model integration test. It sends transient v2
frames through USB to the existing production renderer. No production code is
changed, and nothing is sent to the everyday app.

## Run

Keep the normal `dev-visible-20260912` or newer compatible firmware installed.
Plug the Waveshare ESP32-S3-Touch-AMOLED-1.64 into USB, leave it face up on the
desk, and quit Boop yourself. The runner refuses to compete with the normal app
or another hardware tool. No firmware flashing, pairing or dependencies to
install: it uses Python 3 and the repository's standard-library serial client.

From the repository root:

```sh
python3 tools/demo/demo.py success
python3 tools/demo/demo.py failure
python3 tools/demo/demo.py attention
```

Or run all three in order:

```sh
python3 tools/demo/demo.py
```

Press Enter at the narration pauses. Timed animations advance themselves.
Ctrl-C or closing input ends the demo and attempts cleanup. The attention
scene's Enter key **simulates** an answer; it does not contact an editor. Device
taps can dismiss the reminder, but do not answer the mock question.

With several USB devices, select this board explicitly with
`--port /dev/cu.usbmodem...`.

Rehearse the script without accessing hardware:

```sh
python3 tools/demo/demo.py --preview
```

Use `--auto` to advance narration pauses after two seconds for a bounded run.
Each sweating pause lasts three seconds. The success flow still shows the
full celebration; retry and attention show the smaller one. These are mocked
outcomes with compressed timing, not changes to the app's duration thresholds.

## Presenter notes

| Flow | Say | Device sequence |
| --- | --- | --- |
| Success | “I can look away while the agent works, then glance over when it finishes.” | Start nod → sweat for three seconds → full caption-pulling celebration → idle |
| Failure/retry | “When something goes wrong, the buddy shows it. A retry gives it another go.” | Start → work → red/slumped error; Enter → retry → teal caption → idle |
| Needs you | “This is when I need to come back and answer a question.” | Start → work → amber question; Enter simulates answer → work → teal caption → idle |

The terminal clearly labels mock answers and failures. “All done!” means the
scripted turn ended, not that Boop independently checked a result. Words are
fixed for a reliable presentation; no local model is called.

## Isolation and cleanup

- Uses the existing machine-wide hardware lease and GUI singleton lock for the
  entire run, including cleanup. It never stops or launches the Mac app.
- No HTTP calls, agent sessions, hooks, app preferences, XP, history or memories.
- Frames have a strict transient-field allowlist. Saved `snap`, cosmetics,
  timestamps and commands cannot be added accidentally. Every frame preserves
  the device's current `mute` value; omitting it would change saved volume.
- Refuses first-wake devices, a frozen debug clock, USB-only images and firmware
  without moment telemetry. No clock or IMU overrides are installed.
- Before/after each story and in a `finally` block, clears cards, moments, error
  state, thread rows and counts. Waits for local overlays to expire and verifies
  a sleeping face, no demo content and unchanged exposed saved-state telemetry.
- The pre-demo transient work screen is not replayed: after cleanup, reopen your
  normal Boop app yourself to receive the current real state. Without a host,
  ordinary firmware connection timeout/fallback behavior still applies.

If USB is unplugged or the process is forcibly killed, software cannot promise
cleanup. After reconnecting, with Boop closed, run:

```sh
python3 tools/demo/demo.py --reset-only
```

The runner reports cleanup failure as an error rather than claiming restoration.
It does not erase, reboot, unpair or flash the device to recover. If the GUI lock
is busy, close the app or finish the other device session; do not delete its lock.

Afterward, resume the normal app from your terminal:

```sh
make run
```

## Verification

```sh
python3 -m unittest discover -s tools/demo/tests -v
python3 tools/demo/demo.py --preview
```

Eight automated tests cover persistent-field exclusion, saved-volume carry,
wire budgets, moment deadline countdown, scenario timing, device preflight,
cleanup after interruption/EOF/failure, and detection of failed restoration.
A real `all --auto` run verifies frame acceptance and final device state. This
must hold the hardware and GUI locks; mock tests are not physical verification.

2026-09-12: all eight tests and preview passed. After the user closed Boop,
all three flows completed on the normal USB device with exit code 0. Every
frame was accepted, and final cleanup verified a sleeping face without demo
requests, text or task rows and unchanged exposed saved-state telemetry.
This verifies the state transitions and cleanup, not a visual review or live
Bluetooth/agent integration. [Physical run log](evidence/device-run.txt).
Production app and firmware sources were unchanged.

Timing follow-up: set all working pauses to three seconds; eight automated
tests and preview passed. The physical run log above records the earlier pacing;
rendered frames and cleanup are unchanged.
