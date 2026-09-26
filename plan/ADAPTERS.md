# Boop: agent adapters

Updated 2026-09-26. How Boop hears from Claude Code and Codex: the hook
client, which hooks we register and what each becomes, and how "needs you"
is detected and cleared.

## 1. The job

An adapter turns one agent's hook calls into Boop's common event
([ARCHITECTURE.md](ARCHITECTURE.md) §5). Everything agent-specific lives
here. The rest of Boop never sees a raw hook payload.

Hooks only report. They never answer, block or change what the agent does.
Three rules follow:

1. **Exit fast.** The hook client writes one line and exits with success.
   It never prints a decision, so the agent always continues with its own
   flow, including its own approval prompt.
2. **Fail open.** If the Boop app isn't running, or its socket is missing or
   slow (50 ms in total to connect and write the line), the hook exits with
   success and does nothing.
3. **Send little.** The hook forwards only the fields in §3. Prompt text,
   tool input and file contents never leave the hook client. The one thing
   it takes from tool input is a topic tag (§3), worked out in memory and
   then dropped.

## 2. The hook client

Every hook registration calls one small compiled binary:

```
boop-hook <agent>        # agent = claude | codex
```

1. It reads the hook's JSON from stdin, up to 256 KB. Anything beyond that
   is drained and ignored. A payload cut off at the cap won't parse, so the
   hook name, session, `cwd` and tool name are picked out of its start
   instead (it loses its topic).
2. It picks out the fields in §3.
3. It writes one JSON line to the app's Unix socket,
   `~/Library/Application Support/Boop/boop.sock`. Tests point it elsewhere
   with `BOOP_SOCKET`.
4. It exits with 0 and prints nothing. A 1 s watchdog makes sure of that
   even if stdin never closes.

The line it writes carries only `agent`, `hook`, `session`, `cwd`, `tool`,
`topic`, `error` (StopFailure's raw `error`, or its `error_type`), `kind`
(Notification's type) and `ts`, each value cut to 200 characters. The app's
adapter turns that into the common event, and turns `error` into a class:
`rate_limit`, `overloaded`, `api_error`, `auth`, `timeout`, `network`,
`context_limit`, `billing`, or `other` for anything else.

Because it's compiled rather than a script, it costs a few milliseconds at
most, even for agents that fire a hook on every tool call.

## 3. Event mapping

### Claude Code

| Claude hook | Becomes | Fields kept |
| --- | --- | --- |
| `SessionStart` | `session_start` | session, cwd |
| `UserPromptSubmit` | `turn_start` | session, cwd |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure` | `activity` | session, tool name, topic |
| `PermissionRequest` | `needs_you` | session, tool name |
| `Notification` (`permission_prompt`, `elicitation_dialog`) | `needs_you` (deduplicated) | session |
| `Elicitation` | `needs_you` | session |
| `ElicitationResult` | `activity` | session |
| `Stop` | `turn_end` | session |
| `StopFailure` | `turn_failed` | session, error class |
| `SessionEnd` | `session_end` | session |

### Codex

| Codex hook | Becomes | Fields kept |
| --- | --- | --- |
| `SessionStart` (startup, resume, clear) | `session_start` | session, cwd |
| `UserPromptSubmit` | `turn_start` | session, cwd |
| `PreToolUse`, `PostToolUse` | `activity` | session, tool name, topic |
| `PermissionRequest` | `needs_you` | session, tool name |
| `Stop` | `turn_end` | session |
| `SessionEnd` | `session_end` | session |

Codex has no failure hook, so in v1 a failed Codex turn looks like an
ordinary finish.

**Project name.** The last folder of the session's `cwd`. A git worktree
maps to its main repository's name, so `landing` and
`landing/.worktrees/fix-nav` both show as `landing`.

**Topic tags.** So that Boop's one real word can be about what's happening
(*"…tests?"*), `boop-hook` looks at a tool's input just long enough to pick
a tag, then drops the input:

| Topic | When |
| --- | --- |
| `tests` | A shell command that runs tests (`pytest`, `npm test`, `jest`, `vitest`, `go test`, `cargo test`, `swift test`, …) |
| `build` | A shell command that builds (`make`, `npm run build`, `cargo build`, `swift build`, `xcodebuild`, `tsc`, …) |
| `deploy` | A shell command that deploys (`vercel`, `fly deploy`, `kubectl apply`, `terraform apply`, …) |
| `docs` | An edit to a Markdown or plain-text file |

Anything else has no topic. The core remembers each session's latest topic
for triggers and working chatter.

## 4. "Needs you"

This is the one signal that has to be right every time. The previous
generation of Boop taught us two things:

- **Claude's `PermissionRequest` is reliable.** It fires exactly when Claude
  is about to ask you, and not for tools you've already allowed.
- **Codex's `PermissionRequest` fires too early.** Codex can hand a request
  to its optional automatic reviewer, a model that may approve it without
  asking you, and the hook fires *before* that review. Boop used to go amber
  for requests you were never asked about.

**Rules:**

- **Start:** `needs_you` puts the session into "needs you". A second one
  from the same session while it's waiting is ignored. That dedupes
  `PermissionRequest` against the matching `Notification`. A `Notification`
  (a `needs_you` with no tool) that arrives within 5 s after the session
  stopped needing you is the same request arriving late after a quick
  approval, and is ignored too.
- **Codex grace period:** for Codex, Boop waits 2 s before showing it. If
  the session moves on in that time, the reviewer handled it and Boop shows
  nothing. Claude shows immediately.
- **Clear:** any later event from the same session clears it. That means the
  tool ran (you approved), the agent moved on (you denied), you sent a new
  prompt, or the session ended.
- **Safety net:** after 10 minutes with no events (*proposed*), it clears
  anyway, so a missed event can't leave Boop amber all day.
- **Stale sessions:** a working session with no events for an hour counts
  as idle, and a session with no events for a day is forgotten
  (*proposed*), so a missed `SessionEnd` can't keep Boop busy forever.

## 5. Installing and repairing hooks

- **Where:** Claude hooks go in `~/.claude/settings.json`, and Codex hooks
  in `~/.codex/hooks.json`.
- **Ownership:** every entry Boop adds calls `boop-hook`. That's how Boop
  recognises its own entries. The entries call a copy the app keeps at
  `~/Library/Application Support/Boop/bin/boop-hook`, refreshed at launch,
  so rebuilding or moving the app doesn't break them. It never touches anyone else's, but it does
  remove the previous generation's entries, which call
  `~/.boop/boop-hook.sh`.
- **No `boop-hook`, no hooks:** while that copy isn't there (a build that
  skipped `boop-hook`, so the app had nothing to copy), the app installs
  and repairs nothing, and setup and settings say why. Entries that call a
  missing file would drop every event without a sign. `make run` builds
  everything first for this reason.
- **Install:** at setup, a switch per detected agent, on by default
  ([UX.md](UX.md) §6), or one click in settings. The app shows exactly what
  it will add: each hook entry and, for Codex, the `codex_hooks = true` line
  in `config.toml` if it isn't there yet. Each entry carries `timeout: 5`
  (seconds).
- **Repair:** on every launch, for each agent that already has Boop's
  entries, the app restores missing or outdated ones, replacing the previous
  generation's `~/.boop/boop-hook.sh` entries too. It leaves other hooks
  alone, and never installs for an agent that has none.
- **Codex's switch:** Codex runs hooks only with `codex_hooks = true` under
  `[features]` in `~/.codex/config.toml`. Installing adds that line if it's
  missing; removing leaves it, because other hooks may rely on it.
- **Files Boop can't read:** a config that isn't a JSON object is left
  untouched, and settings shows why.
- **Remove:** one click in settings.
- **Restart:** agents read hooks at startup, so after an install or repair
  the app tells you to restart open sessions.

## 6. Checking it works

The `doctor` skill (`skills/doctor/doctor.sh`) checks four things:

1. Hooks are registered for each agent and point at a `boop-hook` that
   exists.
2. The app is running and its socket answers.
3. A synthetic event goes from the hook client to the app and back.
4. A harmless command run in the agent shows up in Boop.

The app logs hook lines only while the doctor has armed it, by writing
`doctor-armed` into the state directory (`--confirm` removes the file), or
when headless mode runs with `--trace` ([VERIFICATION.md](VERIFICATION.md)
L4).

## 7. Claude Cowork (not in v1)

Cowork runs Claude Code underneath, but it doesn't fire the hooks in
`~/.claude/settings.json`: its sessions run in a Linux sandbox that doesn't
see the Mac's settings
([anthropics/claude-code#40495](https://github.com/anthropics/claude-code/issues/40495)).
Once hooks fire there, Cowork should only need the Claude adapter plus a way
to tell its sessions apart.

## 8. Adding an agent later

A new agent needs a mapping table like the ones in §3, a way to register
hooks, and an answer to one question: what signal proves a person is being
asked? Without a reliable one, the agent gets activity and completion, but
no "needs you".
