---
name: doctor
description: Self-diagnose whether the current agent harness (Claude Code, Codex, or Cursor) is correctly wired to Boop — config, hook script, hook registration, the running app, auth, a synthetic round trip, and a live check that this harness's own hooks fire. Use when asked "is Boop working", "check my hooks", "/doctor", or before trusting any hook-dependent test.
---

# Boop doctor

Works the same in every harness because the truth is a shell script,
`tools/doctor.sh`, and this file only tells you how to drive it.

## Procedure

1. From the repo root run:

   ```sh
   tools/doctor.sh
   ```

   Pass `--agent claude-code|codex|cursor` if it prints `harness: unknown`.
   Pass `--device` if a buddy is plugged in over USB and the Boop app is quit.

2. Read the report. Exit code meanings:
   - `1`: something is broken. Fix it (below) before running anything that
     depends on hooks. Do not continue to step 3.
   - `2`: everything static passed and the check is **armed** for the live
     step.

3. Run exactly one harmless shell command through your own tool-calling
   path, so your harness fires its hooks:

   ```sh
   echo BOOP_DOCTOR_PING
   ```

4. Then confirm:

   ```sh
   tools/doctor.sh --confirm
   ```

   Exit `0` means this harness's hooks reached Boop. Exit `1` means they did
   not, even though the synthetic path works, which points at the harness's
   hook config or a stale harness process.

## Fixes, by finding

- **App not reachable.** Ask the user to launch Boop from their own terminal
  (`cd app && swift run Boop`). Do not launch it yourself: an agent-launched
  Boop aborts on the Bluetooth permission prompt.
- **Config or hook script missing.** Open Boop, Settings, install hooks.
- **Registration missing or lacking events.** Boop, Settings, reinstall
  hooks for this agent, then restart the harness so it reloads hook config.
- **Synthetic round trip fails but the app is reachable.** Token mismatch
  between `~/.boop/config.json` and the running app; restart Boop.
- **Confirm fails.** The harness did not fire, or fired to a different port.
  Check that only one Boop is running and that the harness was started
  after hooks were installed.

## Report back

State the harness, the pass/fail/warn counts, and any fix applied. If the
live confirm failed, say so plainly and do not run hook-dependent tests as if
they were meaningful.
