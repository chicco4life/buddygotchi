# Boop: agent adapters

Updated 2026-09-27. How Boop hears from Claude Code and Codex: the hook
client, the event every hook becomes, how "needs you" is detected and
cleared, and how the hooks are installed.

## 1. The job

An adapter turns one agent's hook calls into Boop's common event.
Everything agent-specific lives here; the rest of Boop never sees a raw
hook payload.

Hooks only report. They never answer, block or change what the agent does,
so Boop can't approve or deny anything. Three rules follow:

1. **Exit fast.** The hook client writes one line and exits with success.
   It prints nothing, so the agent carries on with its own flow, its own
   approval prompt included.
2. **Fail open.** If the app isn't running, or its socket is missing or
   slow, the hook gives up quickly ([ARCHITECTURE.md](ARCHITECTURE.md) §9)
   and still exits with success.
3. **Send little.** Prompt text, tool input, output and file contents never
   leave the hook client. The one thing it takes from a tool's input is a
   topic tag (§3), worked out in memory.

### The common event

Every adapter produces the same shape. This is the Claude adapter's output
for a `PreToolUse` that runs tests:

```json
{"agent":"claude_code","detail":{"tool":"Bash","topic":"tests"},"event":"activity","project":"landing","session":"a1b2","ts":1790000000123}
```

| Field | Meaning |
| --- | --- |
| `agent` | `claude_code` or `codex` |
| `session` | The agent's session or thread ID |
| `subagent` | Only on events from inside a Claude subagent, which shares its parent's `session`: its `agent_id` (§4) |
| `subagent_type` | That subagent's `agent_type`, such as `Explore` |
| `project` | A short project name from the working directory (§3) |
| `workspace` | The worktree or branch the session works in, cleaned to a name (§3); missing on the default branch or outside git |
| `event` | `session_start`, `turn_start`, `activity`, `needs_you`, `turn_end`, `turn_failed`, `turn_stopped` (over without finishing), `session_end` |
| `detail` | Small and event-specific, per hook in §3: `tool`, `tool_use_id`, `topic`, `failed` (true or false), `tool_error` (a failed call's error class, §2) and `error` (a turn's error class, §2). Never prompt text, commands, output or file contents |
| `ts` | When the app received it, in milliseconds |

Turn length isn't sent: the core times each turn itself.

## 2. The hook client

Every hook entry calls one small compiled binary, `boop-hook claude` or
`boop-hook codex`. Being compiled, it costs a few milliseconds even for
agents that fire a hook on every tool call.

1. It reads the hook's JSON from stdin, up to 256 KB, and drains the rest.
   A payload cut off at the cap won't parse, so the fields it needs are
   picked out of its start instead, and it gets no topic.
2. It keeps only these fields, each cut to 200 characters: `agent`,
   `hook`, `session`, `cwd`, `tool`, `topic` (§3), `error` (StopFailure's
   `error` or `error_type`), `kind` (Notification's type), `interrupt`
   (PostToolUseFailure's `is_interrupt`), `tool_error` (PostToolUseFailure's
   `error` as a class, below), `tool_use_id`, `agent_id` and `agent_type`
   (the Claude subagent the hook fired in, and its type) and `ts`. A tool
   error's text is read in memory and only its class kept: `timeout` if it
   says it timed out, `denied` if it was refused, `exit_code` if a command
   exited with an error, and `other`. A payload with no hook name or session
   sends nothing.
3. It writes them as one JSON line to the app's Unix socket,
   `~/Library/Application Support/Boop/boop.sock` (tests point it
   elsewhere with `BOOP_SOCKET`). Connecting and writing share one time
   budget ([ARCHITECTURE.md](ARCHITECTURE.md) §9).
4. It exits with 0 and prints nothing. A 1 s alarm makes sure of that even
   if stdin never closes.

The app's adapter turns the line into the common event, and `error` into
a short class for the brain. Claude's own values map as: `rate_limit` and
`overloaded` as they are; `server_error`, `invalid_request` and
`model_not_found` to `api_error`; `max_output_tokens` to `context_limit`;
`billing_error` to `billing`; its sign-in and account errors to `auth`;
and `unknown` to `other`. Any other text becomes the first of
`rate_limit`, `overloaded`, `api_error`, `auth`, `timeout`, `network`,
`context_limit` or `billing` it contains, and `other` otherwise.

## 3. Event mapping

| Claude Code hook | Becomes | `detail` |
| --- | --- | --- |
| `SessionStart` | `session_start` | |
| `UserPromptSubmit` | `turn_start` | |
| `PreToolUse` | `activity` | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `activity` | `tool`, `tool_use_id`, `topic`, `failed: false` |
| `PostToolUseFailure` | `activity` | `tool`, `tool_use_id`, `topic`, `failed: true`, `tool_error` |
| `PostToolUseFailure` with `is_interrupt` (you pressed Esc) | `turn_stopped` | `tool` |
| `PermissionRequest` | `needs_you` | `tool` |
| `Notification`: `permission_prompt`, `elicitation_dialog` | `needs_you` | |
| `Notification`: `idle_prompt` | `turn_stopped` | |
| `Elicitation` | `needs_you` | |
| `ElicitationResult` | `activity` | |
| `Stop` | `turn_end` | |
| `StopFailure` | `turn_failed` | `error` |
| `SessionEnd` | `session_end` | |

Codex's `SessionStart` (startup, resume, clear), `UserPromptSubmit`,
`PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop` and `SessionEnd`
map the same way, and its `Interrupt` (you pressed Esc) becomes
`turn_stopped`. Codex has no failure hook, and what its `PostToolUse`
reports after a failed command hasn't been seen from a real session, so
Codex activity carries no `failed` and a Codex turn never fails
([FUTURE.md](FUTURE.md)).

**Failed commands.** Claude sends `PostToolUse` when a tool call works and
`PostToolUseFailure` when it fails, including a shell command that exits
with an error. The adapter keeps only that yes or no, never the output.
What makes a turn fail is in [BEHAVIORS.md](BEHAVIORS.md) §3.1.

**Interrupted turns.** Claude sends no `Stop` for a turn you interrupt
with Esc. The interrupted tool call becomes `turn_stopped`, and so does
`idle_prompt`, which Claude sends once it has sat at its prompt for about
a minute and which also covers an interrupt between tool calls. A working
session then goes idle with no reaction. Either one can also clear a
waiting request (§4).

**Workspace.** What tells two threads in one project apart: a linked
worktree's folder name, else the branch checked out in the folder's
`.git/HEAD`; none on `main`, `master`, `trunk` or `develop`, on a
detached head, or outside git. An agent picks its branch names, so the
name is cleaned: a leading `word/` and a trailing hash (`-7a22ea`) go,
it's lowercased, only `a-z`, `0-9` and `-` stay, and it's cut to 40
characters (`claude/agent-work-visibility-7a22ea` is
`agent-work-visibility`). It's read with the project name, below, and
cached the same way.

**Project name.** The last folder of the session's `cwd`. A git worktree
maps to its main repository: `landing` and `landing/.worktrees/fix-nav`
both show as `landing`, and so does any folder whose `.git` file points
into `landing/.git/worktrees/`. The app reads each folder's `.git` once
and remembers the name (up to 512 folders, then it starts again), so a
hook never waits on the disk. A line without a `cwd` keeps the session's
project.

**Topic tags.** So that Boop's one real word can be about the work
(*"…tests?"*), `boop-hook` glances at a tool's input to pick a tag, then
drops the input:

| Topic | When |
| --- | --- |
| `deploy` | A shell command that deploys (`vercel`, `fly deploy`, `kubectl apply`, `terraform apply`, …) |
| `tests` | A shell command that runs tests (`pytest`, `npm test`, `jest`, `go test`, `cargo test`, `swift test`, `make test`, …) |
| `build` | A shell command that builds (`make`, `npm run build`, `cargo build`, `swift build`, `xcodebuild`, `tsc`, …) |
| `docs` | An edit to a `.md`, `.mdx`, `.markdown`, `.txt` or `.rst` file |

A shell command's topic comes from what it runs: the program and the
words after it that aren't flags, in each command of the line
(`cd app && make -C firmware test` runs tests). It looks past
`VAR=value`, shell words such as `then` or `!`, and wrappers such as
`sudo -u ci`, `npx`, `uv run`, `bundle exec`, `python -m` or `yarn jest`,
and into `bash -c '…'` and `docker compose run web …`. A check word in an
argument, quoted text or a heredoc doesn't count, so
`grep -n "make test" Makefile` and `command -v pytest` have no topic. When
a line runs several, deploy beats tests, which beats build. The full lists
are in `app/HookWire/Topic.swift`. The core remembers each session's
latest topic for the brain's inputs and working chatter.

## 4. "Needs you"

This is the one signal that has to be right every time. Claude's
`PermissionRequest` is reliable: it fires exactly when Claude is about to
ask you, and not for tools you've already allowed. Codex's fires early:
Codex can hand a request to its optional automatic reviewer, a model that
may approve it without asking you, and the hook fires before that review.

- **Start.** A `needs_you` puts the session into "needs you", and the core
  notes who asked: the main agent, or a Claude subagent by its `agent_id`.
  A request from another subagent of the same session joins the one
  waiting.
- **Duplicates.** A `needs_you` with no tool (a `Notification` or an
  `Elicitation`) while the session waits is the same request, so a
  `PermissionRequest` and its `Notification` count once. One within 5 s
  after the session stopped needing you is the same request arriving late
  after a quick approval, and is ignored too.
- **Codex grace.** For Codex, Boop waits 2 s before showing it. If the
  session moves on in that time, the reviewer handled it and Boop shows
  nothing. Claude's show at once.
- **Clear.** The asker's next event clears its request: the tool ran (you
  approved) or the agent moved on (you denied). A sibling subagent still
  running tools, or the main agent hearing back from another subagent,
  doesn't. Any turn-level event clears every request: a new prompt, the
  turn ending, failing or being interrupted, or the session ending. A
  request with no tool doesn't say who asked, so any event from the
  session clears it. Once no asker is left, the session is working again.
- **Approved long commands.** Claude has no hook for the moment you
  approve, so "the tool ran" arrives only when the tool finishes: a long
  command you approved keeps "needs you" up until it ends, or until the
  safety net. Boop doesn't guess sooner, since a wrong guess would hide a
  prompt that's still open.
- **Denied with Esc.** Pressing Esc on Claude's prompt sends no hook at
  all. Claude never sends `idle_prompt` while the main agent's prompt is
  up, so when it arrives about a minute later it clears the main agent's
  request, or one with no tool, and the session goes idle. A subagent's
  request stays, since its prompt may still be up. Denying with
  typed feedback carries the turn on, and its next event clears the
  request as usual.
- **Safety net.** After 10 minutes with no events from the session, the
  request clears anyway and the session goes idle: by then the agent is
  still waiting at its prompt or is gone. This covers a Codex request still
  in its grace, as when the Mac sleeps right after Codex asks. The
  session's next event makes it working again.
- **Stale sessions.** A working session with no events for an hour counts
  as idle, and one with no events for a day is forgotten, so a missed
  `SessionEnd` can't keep Boop busy.

What you see and hear is in [BEHAVIORS.md](BEHAVIORS.md) §3.2.

## 5. Installing and repairing hooks

Claude's hooks go in `~/.claude/settings.json` and Codex's in
`~/.codex/hooks.json`. Every entry Boop adds calls `boop-hook`, which is
how Boop recognises its own. It never touches anyone else's entries, but
it does remove an older Boop's, which call `~/.boop/boop-hook.sh`.

- **Which copy.** The entries call a copy of `boop-hook` the app keeps at
  `~/Library/Application Support/Boop/bin/boop-hook` and refreshes at
  launch, so rebuilding or moving the app doesn't break them. While that
  copy is missing, the app installs and repairs nothing, and setup and
  settings say why: entries calling a missing file would drop every event
  without a sign. `make run` builds everything first for this reason.
- **Install.** At setup, a switch for each agent found on this Mac (its
  `~/.claude` or `~/.codex` folder exists), on by default
  ([UX.md](UX.md) §5), or one click in settings. The app shows exactly
  what it will add. Each entry has `timeout: 5` (seconds). Claude runs a
  `Notification` hook only for the types its matcher lists, so Boop's
  lists every type §3 maps, `permission_prompt|elicitation_dialog|idle_prompt`;
  Codex's `SessionStart` matches `startup|resume|clear`.
- **Repair.** On every launch, for each agent that already has Boop's
  entries, the app restores missing or outdated ones. It never installs
  for an agent that has none.
- **Remove.** One click in settings removes Boop's entries, current and
  old, and nothing else.
- **Only the everyday Boop.** A menu-bar app started with another
  `--state-dir` installs, repairs and removes nothing, at setup or later
  (a click in settings says "Couldn't change its hooks: only the everyday
  Boop changes them"), and its log says why. Hooks always report to the
  everyday app's socket, so pointing them at another folder would only
  break them once it's deleted.
- **Codex's switch.** Codex runs hooks only with `codex_hooks = true`
  under `[features]` in `~/.codex/config.toml`. Installing adds the line
  (the preview shows it); removing leaves it for other hooks. However the
  table is written (`[ features ] # note`, or top-level `features.x = …`
  keys), it's never declared twice, which Codex refuses to load. An inline
  `features = {…}` without the key is left for you to edit, and then
  neither file is written.
- **Careful writes.** A config file that's a symlink (a dotfiles setup) is
  written through, not replaced. One that isn't a JSON object is left
  alone, and settings shows why. Nothing is written when nothing would
  change.
- **Restart.** Agents read hooks at startup, so after an install, removal
  or repair the app asks you to restart open sessions.

## 6. Checking it works

The `doctor` skill (`internal/skills/doctor/doctor.sh`) checks four things:

1. Hooks are registered for each agent and call a `boop-hook` that
   exists.
2. The app is running and its socket accepts.
3. A synthetic event from `boop-hook` reaches the app (seen in its log).
4. With `--confirm`, a harmless command run in the agent shows up in Boop
   as a hook from this agent's own session.

`--headless` runs checks 1–3 against a throwaway headless app. The app
logs hook lines only while the doctor has armed it, by writing
`doctor-armed` into the state directory, or in debug mode (`--debug`, [HARNESS.md](harness/HARNESS.md) §9), which also logs the
event each hook became. `--confirm` removes the arm. An arm lasts 10
minutes: the app removes an older one at the next hook, so a doctor run
that never confirms doesn't leave every hook logged for good.

## 7. Claude Cowork

Not in v1 ([FUTURE.md](FUTURE.md)). Cowork runs Claude Code in a Linux
sandbox that doesn't see the Mac's `~/.claude/settings.json`, so Boop's
hooks don't fire there
([anthropics/claude-code#40495](https://github.com/anthropics/claude-code/issues/40495)).
Once they do, it should need only the Claude adapter and a way to tell its
sessions apart.

## 8. Adding an agent

A new agent needs an adapter with a mapping like §3's, a way to register
hooks, and an answer to one question: what signal proves a person is being
asked? Without a reliable one, the agent gets activity and completion, but
no "needs you".
