# agent-hooks: the hook layer as its own package

2026-09-30. The hook client, the hook line, the mapping to events, the
session and "needs you" rules, the installer and thread links moved out
of Boop into `agent-hooks/` ([its README](../../../agent-hooks/README.md),
[SPEC.md](../../../agent-hooks/SPEC.md)), with a command line, a socket
folder any number of apps listen in, `--keep-text` and `topics.json`.
Boop depends on it ([ADAPTERS.md](../../ADAPTERS.md), decision log
2026-09-30).

## What ran

| Check | Result |
| --- | --- |
| `make -C internal test` (the root `make build`, Boop's tests, then agent-hooks' `swift test --scratch-path .build/tests`) | Boop 301 of 301, agent-hooks 76 of 76 in 6 suites, exit 0. `main`'s Boop test files have 359 `func test` methods and this branch's 302: 57 moved with the code (49 in `InstallerTests`, `HookWireTests` and `ThreadLinkTests`, 8 in `AdapterTests`) |
| `make -C internal tools-test` | 93 and 3 tests, OK |
| `HOME=$H internal/skills/doctor/doctor.sh --headless`, after `boopdev hooks install --home $H` in a fresh `/tmp/boop-h.*` | 5 passed, 0 failed: both agents' hooks call `.build/debug/agent-hook`, the socket accepts, the synthetic event arrives |
| `boopdev replay` of the 8 synthetic and recorded hook fixtures, this branch against `main`'s `boopdev` (4bea7b21) on the same files | Every line the same: raw events, the core's decisions and view events (53, 24, 22, 23, 32, 19, 16 and 31 lines) |
| `agent-hooks install --keep-text`, `status`, `doctor`, `tail --sessions` and `remove` in a temporary home, with a made-up Claude session through `agent-hook` | As SPEC.md §6 says; its examples are this run's output |
| The README's library example, compiled against the package in a scratch Swift 6 package, fed a permission request | Printed `Claude Code in landing wants permission` |
| `Examples/needs-you-notify.sh` with a stub `osascript` | One notification for the permission request and one for a later question; a prompt holding `"state":"needs_you"` sent none; its socket went at Ctrl-C |

## Found and changed

- **The command line wrote to the real hooks.** The first run of
  `HOME=$TMP agent-hooks install --keep-text` changed the real
  `~/.claude/settings.json` and `~/.codex/hooks.json`: the command line
  took its home from `NSHomeDirectory()`, which ignores `HOME`, while the
  socket folder and `topics.json` follow `HOME`. It added one
  `agent-hook … --keep-text` entry per hook, beside Boop's `boop-hook`
  ones, and left `~/.codex/config.toml` alone. The command line now takes
  `--home`, else `HOME` (SPEC.md §6), and CLAUDE.md says to give the
  installers `--home` too. The entries it added are the owner's to take
  out: `agent-hooks remove` takes out only `agent-hook` entries, and
  Boop's first launch from this branch replaces both kinds with its own.
- The moved `InstallerTests` had 29 `try #expect(try …)` warnings; the
  outer `try` went.
- **Review, the same day.** Run from `PATH`, the command line looked for
  `agent-hook` in the current folder (`argv[0]` is only its name there), so
  `install`, `status` and `doctor` failed; it now finds it next to its own
  executable, links followed, which a copy on `PATH` and a link to it both
  showed in a temporary home. The README installs the two into
  `~/.local/bin`. `AdapterTests` now pins Boop's first-launch migration
  from `boop-hook` entries and that an agent event reads back whole from
  the transcript (Boop 303 of 303). The TestingMacros flake struck from a
  clean build folder too, so `make -C internal test` retries that failure
  alone, up to twice (checked with a stand-in `swift`: a flake passes on
  the second run, a real failure fails at once).
- Main moved during the work (4bea7b21, a tap on a finished turn opens its
  thread); the branch was rebased onto it, its `ThreadRef(session)` became
  the tracker's `Session.thread`, and two files it added import
  `AgentHooks`.

## Left for the owner

The package's final name, its licence, and whether it moves to a repo of
its own.
