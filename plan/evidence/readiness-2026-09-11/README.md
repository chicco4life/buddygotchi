# Readiness follow-up — 11 September 2026

Worktree: `codex/readiness`, based on main `0c7f1d0`. This is partial
readiness evidence, not release approval. The initial checks wrote no firmware. The later local OTA test below installed a
normal BLE candidate; nothing was published.

| Area | Result | Still needed |
| --- | --- | --- |
| Display model | Privacy masking/rejection, normalized repeat rejection and no-intent silence added; expanded live trial rejected guided candidate | Whole-desk relevance, replacement intent, factuality and appropriate silence |
| OTA client and real transfer | HTTP/cache fixes tested; actual Mac download, BLE transfer, verification, reboot and version confirmation passed | Public delivery and broader release environments |
| Native Claude Code 2.1.268 | Native Yes created a temporary marker; native No left a second marker absent. Boop had zero waiting approvals while native approval was pending; actual hook events arrived | Other supported versions and stale-hook/repair scenarios |
| Native Codex 0.153.4 | Doctor and native allow/deny passed; Boop waiting count stayed zero; SessionEnd arrived after native trust review | Fresh SessionStart after trust, stale-hook and repair coverage |
| Cursor | Neither app nor CLI available | Actual supported-editor run |
| Device startup | USB recovered; asleep at brightness 28; three confirmed software restarts left panic count at 103 | Explain original panic; BLE startup and extended stability |
| Public firmware delivery | Manifest endpoint still HTTP 404 | Publish a validated release after actual OTA gate |

The diagnostic receiver was a temporary headless instance using the installed
hook endpoint, with no Bluetooth or owner database access. Native checks used
only a dedicated temporary directory and touch markers. They do not establish
Mac GUI or BLE integration. The Codex lifecycle timeout is now registered at
its 3-second limit. Its deprecated `codex_hooks` flag remains compatible but
needs a separately tested migration that preserves ownership and uninstall.

## Model replay

The [16 synthetic cases](model-cases.json) cover multiple projects and purposes,
changed intent, thin/missing evidence, six-project load, private values,
instruction injection, routine completion, error and repeated/return greetings.
The candidate uses Apple guided generation with per-task purpose fields, a
silence Boolean and final text. It runs through the actual Voice deadline and
output checks. [Raw candidate output](guided-replay.jsonl) is synthetic; timings
are observational, not a performance guarantee.

| Representative case | Observed failure |
| --- | --- |
| Single project with Mac and device work | “Boop app improvements” omitted device purpose |
| Current request canceled earlier work | Included both canceled brushes and current login fix |
| Injection within task data | Claimed deployment success without evidence |
| Routine completion | Produced generic congratulations and advice |
| Six projects | Returned generic “updates and improvements” |

All 16 candidate requests finished within the five-second deadline in this run,
but that does not close the semantic gate. Six standalone prompt/schema variants
were also explored; none justified replacing production generation. Candidate
code is test-only. The production runtime keeps its full owner guide and fresh
session. Structural, privacy and exact-repeat safeguards do not prove semantic
correctness or comprehensive private-data detection.

Reproduce from the repository root on a Mac with Foundation Models available:

```sh
python3 app/tools/test.py
app/.build/debug/BoopTests --model-replay \
  plan/evidence/readiness-2026-09-11/model-cases.json /tmp/boop-production.jsonl
app/.build/debug/BoopTests --model-replay \
  plan/evidence/readiness-2026-09-11/model-cases.json /tmp/boop-guided.jsonl --guided
```

Output must be a new path. Ordinary tests never call the live model. The replay
entry point requires the shim runner (`BOOP_USE_XCTEST_SHIM=1` when using Xcode).
Replays use the bundled guide. The app can additionally use its owner override;
these replay results do not validate a custom owner guide.

## Verification before the OTA run

- App regression suite: **392 passed, zero skipped**.
- Debug `Boop` and `BoopSignal` products built successfully.
- [Final production replay](production-replay.jsonl): missing intent and empty
  partial context skipped generation; repeated greeting was suppressed; the
  private-text case did not echo supplied private values. Coverage still failed:
  one output invented a budget app, several were generic, and a routine finish
  produced Markdown. One request resolved to silence around the deadline
  (5.13 seconds observed wall time). This remains a failed semantic gate.
- [Native approval assertions](native-approvals.json) and
  [sanitized recent hook events](hook-events.json). Recent Codex events also
  include the controlling task, so only the dedicated marker assertions and
  observed native exit establish the specific approval/SessionEnd checks.
- Temporary receiver and test CLIs were stopped before handoff. The app has
  been built, not launched; the normal firmware was left untouched.

## Startup and OTA limits before device recovery

The earlier unexplained panic remains unexplained. No stack trace was captured
in this follow-up and no speculative firmware change was made. A serial timeout
is not a clean reboot or a panic reproduction. Earlier installed-version claims
in the plan describe the last successful session, not a fresh observation.

`https://adoptaboop.com/firmware/manifest.json` returned HTTP 404 again. Client
unit tests establish error/cache behavior only. A loopback manifest override
can exercise actual OTA once the device responds and the user launches the Mac
GUI; publishing untested assets is not a substitute for that check.

## Device recovery — 12 September 2026 (Korea)

After the user reported a dim face, USB ping succeeded. The device explicitly
reported asleep, brightness 28/255, no host connection, and normal firmware
`dev+6182f51882a7`. The dim face matches the documented disconnected sleep
behavior. [Recovery data](device-recovery.json) and [boot traces](startup-serial.log)
record three confirmed software restarts with unchanged panic count 103, no
safe-mode entry, and continued uptime afterward. This does not explain the
earlier panic. A repeatable I²C warning precedes successful IMU detection;
probing the absent first candidate address is a possible explanation, not a
confirmed root cause. No firmware fix was inferred from the warning.

A read-only full-flash backup failed with a serial-stream error; the incomplete
image is not a recovery backup. USB ping recovered afterward, with panic count
still 103. The existing normal images remain available locally. No flash writes
have occurred.

Normal BLE firmware `0.0.1-readiness.1` built successfully from this worktree
for a loopback-only OTA test. Its manifest hash was verified and release-manifest
tests passed. The local launcher selects `http://127.0.0.1:18766/manifest.json`
for this process only. The user must launch the Mac GUI before actual OTA; this
is still prepared, not transferred or installed. Nothing was published.

## Actual Mac OTA — 12 September 2026

**Passed.** The user launched the readiness Mac build against the loopback
manifest. Its real Settings → Firmware → Update now flow downloaded the
1,243,264-byte normal BLE image, transferred it, received a successful final
verification acknowledgment, and reconnected securely. The Mac displayed
“Update complete — 0.0.1-readiness.1”; independent USB telemetry confirmed that
version, software reset, over 100 seconds of uptime, safe mode off, and panic
count unchanged at 103. The test candidate remains installed.

Hiding the update panel left the transfer running; reopening it displayed
current progress. Transfer took approximately **17.85 minutes**, measured
between nearby USB uptime samples. No rejected acknowledgments were observed.
The measured time is why the app copy now refers to the live estimate instead
of promising “a few minutes.” The copy change passed the 392-test app suite
and Boop build; the running app predates only that wording change.

[Result and artifact hash](ota-result.json), [reboot/telemetry](ota-reboot-serial.log),
[Mac success](ota-success.png), [hidden panel](ota-hidden.png), and
[reopened panel](ota-reopened.png). This closes the **local actual Mac OTA** gate;
public hosting, signing/release checks, broader environments and the earlier
unexplained panic remain open. I²C warnings also occurred after startup without
a panic, so an absent-address probe alone does not explain every warning.

The temporary HTTP server and USB observer were stopped. The user’s Mac GUI
was left running. Its manifest override applies only to this test process; a
normal launch returns to the public endpoint. No public release was created.
