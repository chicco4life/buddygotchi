# Boop support

What to do when Boop misbehaves, in the order a person should try things.
Everything here is local; nothing leaves the Mac unless the leaderboard is
opted in.

## 1. Is it wired up?

Run the doctor from the harness you are using (Claude Code, Codex, or
Cursor):

```sh
skills/doctor/doctor.sh
echo BOOP_DOCTOR_PING      # as a tool call inside the agent
skills/doctor/doctor.sh --confirm
```

Exit 0 is healthy. Exit 1 prints the broken step and its fix. The usual
ones:

- **Hook script older than v7.** Launch Boop from your terminal (not from an
  agent); it repairs its own hook script and registrations on launch and
  logs the repair under Settings → Diagnostics.
- **App not reachable.** Boop is not running, or a second copy holds the
  port. Quit both and launch once.
- **Token mismatch (401).** Relaunch Boop so it rewrites the hook script; the
  token lives in `~/.boop/config.json` and the script reads it at call time.

## 2. Forgetting things

Boop keeps extracted facts (projects, goals, habits, tools), never
transcripts, code, or prompt text. Settings → Profile lists every fact with
its date; delete a line, or clear all. Clearing explains what goes: name,
facts, traits, voice memory. Growth (XP, level, streak) stays.

## 3. Reset and retire

- **Reset the app.** Quit Boop, delete `~/.boop/boop.sqlite`, launch again.
  Config and hooks are kept; facts, growth, and memory are gone.
- **Re-pair the device.** Settings → Device → "Forget this buddy" drops the
  Bluetooth bond on the Mac; pair again from the same screen. Nothing on
  the device changes.
- **Retire** when handing the device to someone else. Settings → Retire
  (with a confirmation). The device fades out, wipes its cosmetics and its
  unit key, and the app forgets the unit identity and drops the leaderboard
  opt-in. A retired unit can never sign growth again, so the signed ledger
  ends there; a new unit starts a new one. There is no device-side gesture
  for this on purpose.

## 4. A harness shipped a hook regression

Symptoms: the doctor's static checks pass but the live check never fires, or
`/diag/recent` shows payloads rejected at the input boundary.

1. Record the new payload shape:
   `app/tools/record-hooks.sh <agent>` as the hook target for one session.
   It redacts your home path and caps strings; the files land under
   `app/Tests/Fixtures/hooks/<agent>/<date>/`.
2. Run `swift run BoopTests` (after `python3 tools/gen-test-runner.py`).
   `HookFixtureTests` fails at the exact field that moved.
3. Fix the parser in `RawHookPayload` (app side) or the transport in
   `HookInstaller` (script side). Never in outputs or the reducer.
4. Bump the hook script version if the script changed; the doctor and the
   launch-time repair use it.
5. Add the agent release to `app/Tests/Fixtures/hooks/VERSIONS.md`.

Hooks fail open: while Boop is broken, the agent keeps working without it.

## 5. Device will not answer on USB

The Waveshare board's native USB serial sometimes does not re-enumerate
after a reset. Unplug, wait five seconds, plug back in, press the reset
button once. If `tools/buddyctl.py ping --json` still times out, hold BOOT
while pressing RESET and flash with `tools/pio_ws.sh run -e ws-amoled164 -t upload`.

## 6. Reporting a bug

Settings → "Export bug report" writes a redacted JSON report
(`boop-bug-report-<date>.json`) with recent diagnostic events and versions.
It contains no facts, transcripts, or tokens.
