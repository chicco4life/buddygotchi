# Boop: agent adapters

Draft 2 · 2026-09-25. Part of the [architecture](ARCHITECTURE.md). This page
covers how Boop hears from Claude Code and Codex: which hooks
we register, what each one becomes, and how "needs you" is detected and
cleared.

## 1. The job

An adapter turns one agent's hook calls into Boop's common event
([ARCHITECTURE.md](ARCHITECTURE.md) §5). Everything agent-specific lives
here. The core, harness and device never see a raw hook payload.

Hooks only report. They never answer, block or change what the agent does.
Three rules follow:

1. **Exit fast.** The hook client writes one line and exits with success.
   It never prints a decision, so the agent always continues with its own
   flow, including its own approval prompt.
2. **Fail open.** If the Boop app isn't running, or the socket is missing or
   slow (connect timeout 50 ms, *proposed*), the hook exits with success and
   does nothing.
3. **Send little.** The hook forwards only the fields listed in §3. Prompt
   text, tool input and file contents are dropped inside the hook client and
   never reach the app.

## 2. The hook client

The hook client is a tiny compiled binary, `boop-hook`, which every hook
registration calls:

```
boop-hook <agent>        # agent = claude | codex
```

1. It reads the hook's JSON from stdin, with a cap of 256 KB. Anything
   beyond that is drained and ignored.
2. It picks out the fields in §3.
3. It writes one JSON line to the app's Unix socket
   (`~/Library/Application Support/Boop/boop.sock`).
4. It exits with 0 and prints nothing.

It's a compiled binary rather than a shell script, so it adds a few
milliseconds at most, even on busy agents that fire a hook on every tool
call.

## 3. Event mapping

### Claude Code

| Claude hook | Becomes | Fields kept |
| --- | --- | --- |
| `SessionStart` | `session_start` | session, cwd |
| `UserPromptSubmit` | `turn_start` | session, cwd |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure` | `activity` | session, tool name |
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
| `PreToolUse`, `PostToolUse` | `activity` | session, tool name |
| `PermissionRequest` | `needs_you` | session, tool name |
| `Stop` | `turn_end` | session |
| `SessionEnd` | `session_end` | session |

Codex has no failure hook, so a failed Codex turn looks like an ordinary
`turn_end`. If we want `turn_failed` for Codex, the adapter can read the
last entry of that session's `~/.codex/sessions` JSONL when `Stop` arrives.
That's optional for v1.

**Project name.** The project is the last folder of the session's `cwd`.
A git worktree maps to its main repository's name, so `landing` and
`landing/.worktrees/fix-nav` both show as `landing`.

## 4. "Needs you"

This is the one signal that has to be right every time. Here is what the
previous generation of Boop learned:

- **Claude's `PermissionRequest` is reliable.** It fires exactly when Claude
  is about to ask you. It doesn't fire for tools you've already allowed. The
  old app used it as a blocking approval hook, and it worked well. Used as a
  notify-only hook, it's simpler still.
- **Codex's `PermissionRequest` needs one extra rule.** Codex has an
  optional automatic reviewer: a model that looks at an approval request
  and can approve it without asking you. The hook fires *before* that
  review, so in the old app Boop sometimes turned amber for requests Codex
  then approved by itself, and you were never asked. With the reviewer off,
  every `PermissionRequest` really is you being asked. To cover both cases,
  Codex "needs you" waits a moment before showing (§4 rules).
- **The current app switched to passive signals.** It shows "needs you" only
  for Claude's `Elicitation` and ignores permission notifications. That was
  a side effect of taking approvals out of Boop entirely. Now that Boop
  notifies without deciding, we go back to `PermissionRequest` for both
  agents.

**Rules:**

- **Start:** `needs_you` puts that session into "needs you". A second
  `needs_you` from the same session while it's already waiting is ignored,
  which dedupes `PermissionRequest` against the matching `Notification`.
- **Codex grace period:** for Codex, Boop waits 2 s before
  showing "needs you". If the session moves on in that time, the automatic
  reviewer handled it and Boop shows nothing. Claude shows immediately.
- **Clear:** any later event from the same session clears it. That covers
  the tool running (you approved), a new tool or `Stop` (you denied and
  Claude moved on), a new prompt (you interrupted), or `SessionEnd`.
- **Safety net:** if nothing arrives for 10 minutes (*proposed*), it clears
  anyway, so a missed event can't leave Boop amber all day.

## 5. Installing and repairing hooks

- **Where:** Claude hooks go in `~/.claude/settings.json`, and Codex hooks
  go in `~/.codex/hooks.json`.
- **Tagging:** every entry Boop adds calls `boop-hook`. That path is how
  Boop recognises its own entries, and it never touches anyone else's.
- **Install:** at setup, one click per detected agent. The app shows
  exactly what it will add.
- **Repair:** on every launch the app checks its entries and quietly
  restores missing or outdated ones, leaving other hooks alone.
- **Remove:** one click in settings, or on uninstall.
- **Restart:** agents read hooks at startup, so the app tells you to
  restart any open sessions after an install or repair.

## 6. Checking it works

The existing `doctor` check carries over:

1. Hooks are registered for each agent, pointing at the current
   `boop-hook`.
2. The app is running and the socket answers.
3. A synthetic event goes from the hook client to the app and back.
4. A live check: run a harmless command in the agent and confirm Boop saw
   it.

## 7. Claude Cowork (not in v1)

Cowork runs Claude Code underneath, but today it doesn't fire the hooks in
`~/.claude/settings.json`. Cowork sessions run in a Linux sandbox that
doesn't see the Mac's settings
([anthropics/claude-code#40495](https://github.com/anthropics/claude-code/issues/40495)).
Cowork is out of v1. When Anthropic makes hooks fire in Cowork, it should
only need the Claude adapter plus a way to tell Cowork sessions apart.

## 8. Adding an agent later

A new agent needs a mapping table like the ones in §3, a way to register
hooks, and an answer to one question: what signal proves a person is being
asked? If there isn't a reliable one, that agent gets activity and
completion, but no "needs you".
