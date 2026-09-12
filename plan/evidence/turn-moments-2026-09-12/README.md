# Turn moments — 2026-09-12

Development implementation uses the existing trigger / Markdown / shared Voice /
pure Core / output pipeline. This evidence supersedes device-scope pop-ups in
the earlier phrase experiment; that evidence is retained as history.

## Verification

- Final app suite: **396 passed, 0 skipped**. Exact 3/20-second boundaries,
  duplicate ends, coalescing, failure/retry duration, late replies, unavailable-model
  fallback, 24/48-byte generation budgets, no second idle remark, guide reload,
  bounded long-work milestones, person-return merging and wire limits.
- Both Mac products (`Boop`, `BoopSignal`) build.
- Both firmware variants (`ws-amoled164`, `ws-amoled164-usb-debug`) build.
- **48 USB hardware checks passed**: turn moments, work-scope compatibility and
  dashboard navigation. Includes deadline/replay, request/details/sleep interruption,
  malformed frame rejection, long-word silence and fixed hint pixels during fade.
- **27 lifecycle screenshots** inspected, covering starts, tiny/caption/full
  completions, long-work and return. Full tier includes arrival, pull, release,
  settled and expiry. No text/face/footer collision observed at sampled poses.
- **14 goldens** independently reproduced twice with identical decoded pixels:
  eight existing scope/count scenes and six new moment scenes. Baselines recorded
  only after the two captures matched; [contact sheet](contact-sheet.png) reviewed.

[Lifecycle sheet](lifecycle-sheet.png), [device result](device-result.json),
[hardware output](device-checks.txt), [firmware build](firmware-build.txt),
[app tests](app-tests.txt), [Mac build](mac-build.txt), [artifact hashes](sha256.json).

## Local model sample and limits

The bounded Swift replay used the bundled guide, six synthetic English contexts,
Foundation Models temperature 0.4, and 24/48-byte instructions. No owner prompt
or transcript was sampled. [Inputs](model-inputs.json), [runner](model-replay.swift),
[final raw results](model-results-shipped.txt), [preceding sample](model-results-final.txt).

Final sample: five valid short phrases and one Markdown-fenced response, which
the runtime text filter rejects. Valid phrases were generic (“On it!”, “Turn
finished.”, “Still working away.”, “Welcome back!”). Latencies were 1.55–2.59 s;
start generation exceeded the 1.5-second display window. Immediate guide fallbacks
cover this case, and ID/count/deadline validation discards late replies. The new
unavailable-runtime test ensures failure does not erase the immediate fallback.
Timely model SILENT can still clear words. This is a fit/latency sample, **not**
a broad semantic-quality pass or evidence of task-aware/time-aware wording.

## Device restoration and installed status

The wrapper held the shared reservation through setup, verification and restore.
USB-only candidate: `dev-moments-20260912`; setup/scenario/restore all exited 0.
The saved normal image was restored: **0.0.1-readiness.1**, git `0c7f1d0e9b1a`,
`usbOnly: false`; panic counter remained **103 before and after**.
[Before](before.json), [restoration log](device-restore.txt).

The running owner-launched Mac GUI was not restarted and the new normal candidate
was not left installed. Owner Markdown overrides were preserved. No public release,
production Bluetooth integration, native-editor/hook gate or webcam review was
performed for this change. The current app/device must be updated together to
exercise the new moments in everyday use.

The [capture script](capture.py) requires a reserved USB-only device. Use the
standard setup/restoration wrapper from `tools/dev/README.md`; do not run raw
flashing or captures alongside another hardware writer. Frozen-clock screenshots
verify sampled geometry, not continuous camera motion.

## User-requested normal installation

After the user quit the Mac GUI and requested installation, the verified normal
`dev-moments-20260912` image was installed and left on the device. An initial
backup read failed from serial noise without flashing. A subsequent factory-image
attempt reset NVS; its verification rejected the changed counter and restored the
saved image/settings. The final installation verified matching partition tables
and application bytes, then wrote only boot selection at 0xe000 and app0 at
0x10000, preserving restored NVS and the existing app1. Normal mode (`usbOnly:false`),
version, increasing uptime and unchanged panic counter 103 were verified in three
samples through 10.5 seconds. No safe mode or new reset appeared.

[Install result](install-result.json), [samples](installed.json),
[retained as requested](install-retained.txt). The new firmware is now installed;
this supersedes the restoration status above. The matching Mac build's bundled
guide hash matches the source. The agent did not launch the GUI; the user receives
`make -C /Users/michaeljxzhu/.codex/worktrees/2441/buddygotchi run` to start it.
Live Bluetooth behavior after that launch remains a separate check.

## Main integration (2026-09-12)

Integrated with main `1b6bacb07befc904898470f29e4e928077d4b327`, retaining
its display privacy safeguards, no-intent scope silence, native hook fixes and
OTA fixes. Regenerated the combined test runner and reconciled the dated
installation records; the latest installed firmware remains `dev-visible-20260912`.

- **405 app tests passed, zero skipped**, including both sets of behavior tests.
- **Boop and BoopSignal built successfully.**
- **Six development workflow tests and one release-artifact test passed.**
  The first restricted workflow run could not start its temporary local server;
  rerunning outside the sandbox passed.
- `git diff --check` passed. Firmware sources were unchanged by integration;
  earlier build and physical-device evidence above and in the visibility record
  still applies. No firmware reflash or GUI launch was performed for this merge.

[App tests](main-app-tests.txt), [Mac builds](main-mac-build.txt),
[Workflow and artifact checks](main-workflows.txt).
