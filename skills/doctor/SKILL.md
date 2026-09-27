---
name: doctor
description: Self-diagnose whether the current agent harness (Claude Code or Codex) is correctly wired to Boop — hook registration, the boop-hook binary, the running app's socket, a synthetic round trip, and a live check that this harness's own hooks fire. Use when asked "is Boop working", "check my hooks", "/doctor", or before trusting any hook-dependent test.
---

# Boop doctor

The truth is a shell script, `skills/doctor/doctor.sh`; this file says how
to drive it. It checks the four things in `plan/ADAPTERS.md` §6. It only
reads `~/.claude` and `~/.codex`.

## Procedure

1. From the repo root run:

   ```sh
   skills/doctor/doctor.sh
   ```

   Pass `--agent claude|codex` if it prints `agent: unknown`, and
   `--state-dir DIR` for a headless app (the default is the everyday app's
   `~/Library/Application Support/Boop`).

2. Read the report. Exit codes:
   - `1`: something is broken. Fix it (below) before running anything that
     depends on hooks.
   - `2`: everything passed and the check is **armed** for the live step.
     Arming writes `doctor-armed` in the state directory; while it's there
     the app logs every hook to `boop.log`.

3. Run exactly one harmless shell command through your own tool-calling
   path, so your harness fires its hooks:

   ```sh
   echo BOOP_DOCTOR_PING
   ```

4. Then confirm (this also disarms):

   ```sh
   skills/doctor/doctor.sh --confirm
   ```

   Exit `0` means this harness's hooks reached Boop.

`--headless` runs checks 1–3 against a throwaway headless app instead of
the everyday one. Combine it with a temporary `HOME` after
`app/.build/debug/boopdev hooks install --home DIR` to check the installer
without touching the owner's setup.

## Fixes, by finding

- **No socket / socket doesn't accept.** The app isn't running. Ask the
  owner to start Boop (`make run`). Don't launch it yourself: an
  agent-launched Boop is killed on its first Bluetooth use.
- **Missing hooks, or previous-generation entries.** Boop → Settings →
  Agents → Connect (or Repair) for this agent, then restart the agent's sessions so
  they reload hook config.
- **boop-hook is missing.** The app places it in
  `~/Library/Application Support/Boop/bin/` at launch; restart the app.
- **Round trip fails but the socket accepts.** Another Boop owns the socket,
  or `boop.log` belongs to a different state directory.
- **Confirm fails.** The harness didn't fire its hooks: it was started
  before the hooks were installed, or it reads a different config.

## Report back

State the agent, the pass/fail counts, and any fix applied. If the live
confirm failed, say so plainly and don't run hook-dependent tests as if they
were meaningful.
