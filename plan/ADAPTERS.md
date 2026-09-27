# Boop: agent adapters

Updated 2026-09-27. How Boop hears from Claude Code and Codex: the hook
client, the event every hook becomes, how a session moves between
working, idle and "needs you", and how the hooks are installed. Code:
`app/HookWire/`, `app/BoopHook/`, `app/BoopKit/Adapters/`,
`app/BoopKit/Install/`, and the session rules in `app/BoopKit/Core/Core.swift`.

## 1. The job

An adapter turns one agent's hook calls into Boop's common event.
Everything agent-specific lives here; the rest of Boop never sees a raw
hook payload.

Hooks only report. They never answer, block or change what the agent does,
so Boop can't approve or deny anything. Three rules follow:

1. **Exit fast.** The hook client writes one line and exits 0. It prints
   nothing, so the agent carries on with its own flow, its own approval
   prompt included.
2. **Fail open.** If the app isn't running, or its socket is missing or
   slow, the hook gives up within its budget (§2) and still exits 0.
3. **Send little.** Prompt text, tool input and output, error text and
   file contents never leave the hook client. From a tool's input it keeps
   only a topic tag (§3), and from an error only its class (§2).

### The common event

Every adapter produces the same shape. This is the Claude adapter's output
for a `PreToolUse` that runs tests (`AdapterTests.testEventJSONShape`):

```json
{"agent":"claude_code","detail":{"tool":"Bash","topic":"tests"},"event":"activity","project":"landing","session":"a1b2","ts":1790000000123}
```

| Field | Meaning |
| --- | --- |
| `agent` | `claude_code` or `codex` |
| `session` | The agent's session or thread ID |
| `subagent` | Claude only, on events from inside a subagent (which shares its parent's `session`): its `agent_id` |
| `subagent_type` | That subagent's `agent_type`, such as `Explore` |
| `project` | A short project name from the working directory (§3); `unknown` when the hook had no `cwd` |
| `workspace` | The worktree or branch the session works in, cleaned to a name (§3); missing on the default branch or outside git |
| `event` | `session_start`, `turn_start`, `activity`, `needs_you`, `turn_end`, `turn_failed`, `turn_stopped` (over without finishing), `session_end` |
| `detail` | Per hook in §3: `tool`, `tool_use_id`, `topic`, `failed` (true or false, Claude only), `tool_error` (a failed call's class) and `error` (a failed turn's class) |
| `ts` | When the app received it, in milliseconds on the app's steady clock ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2, "Clocks"); `boopdev replay` uses the hook line's own `ts` |

Turn length isn't sent: the core times each turn itself.

## 2. The hook client and the socket

Every hook entry calls one small compiled binary, `boop-hook claude` or
`boop-hook codex` (any other argument sends nothing). It shares only
`HookWire` with the app: the hook line, the topic tags, the error classes
and the socket, in Foundation alone, so both sides agree on the line by
construction.

1. **Read.** The hook's JSON from stdin, up to 256 KB; the rest is
   drained and ignored. A 1 s alarm exits 0 whatever happens, even if
   stdin never closes.
2. **Keep.** The hook name (`hook_event_name`) and session (`session_id`,
   else `thread_id` or `conversation_id`). Without both, nothing is sent.
   Then, each cut to 200 characters:

   | Field | From | On |
   | --- | --- | --- |
   | `cwd`, `agent_id`, `agent_type` | the same keys | every hook |
   | `tool`, `tool_use_id` | `tool_name`, `tool_use_id` | `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` |
   | `topic` | the tool's input, read in memory (§3) | the same, except `PermissionRequest` |
   | `interrupt` | `is_interrupt` | `PostToolUseFailure` |
   | `tool_error` | `error`, as a class (below) | `PostToolUseFailure` that isn't an interrupt |
   | `error` | `error`, else `error_type` | `StopFailure` |
   | `kind` | `notification_type` | `Notification` |
   | `ts` | when `boop-hook` started, in ms | every hook |

   A payload cut off at 256 KB won't parse, so the hook name, session,
   `cwd`, `agent_id` and, for tool hooks, `tool_name` and `tool_use_id`
   are picked out of its start instead. It gets no topic.
3. **Send.** One JSON line to the app's Unix socket,
   `~/Library/Application Support/Boop/boop.sock`, or `$BOOP_SOCKET` in
   tests. Connecting and writing are non-blocking and share one 50 ms
   budget; past it the line is dropped.
4. **Exit** 0, having printed nothing.

**Error classes.** A failed tool call's `error` text becomes `timeout`
("timed out", "timeout"), `denied` ("denied", "not allowed", "rejected",
"permission"), `exit_code` ("exit code", "exited", "non-zero", "status
code"), or `other`, checked in that order (`ToolError`). A failed turn's
`error` becomes, in the app, one of `rate_limit`, `overloaded`,
`api_error`, `auth`, `timeout`, `network`, `context_limit`, `billing` or
`other`: Claude's `server_error`, `invalid_request` and `model_not_found`
are `api_error`, `max_output_tokens` is `context_limit`,
`account_on_hold`, `verification_required` and `cloud_credential_error`
are `auth`, and any other text is the first class it contains, else
`other` (`Adapter.errorClass`).

**The app's end.** The hook server listens on `boop.sock` (mode 0600,
replaced at launch, removed at quit) on its own thread. It reads each
connection until it closes, goes quiet for 200 ms or reaches 64 KB, splits
it into lines and hands each hook line to the runtime. It never writes back. A line that isn't a
hook line is a dev line (`{"dev":…}`, [DASHBOARD.md](DASHBOARD.md) §4),
taken only headless or in debug mode and dropped otherwise.

## 3. Event mapping

**Claude Code** (`claude_code`):

| Hook | Becomes | `detail` |
| --- | --- | --- |
| `SessionStart` | `session_start` | |
| `UserPromptSubmit` | `turn_start` | |
| `PreToolUse` | `activity` | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `activity`, the call's result | `tool`, `tool_use_id`, `topic`, `failed: false` |
| `PostToolUseFailure` | `activity`, the call's result | `tool`, `tool_use_id`, `topic`, `failed: true`, `tool_error` |
| `PostToolUseFailure` with `is_interrupt` (you pressed Esc) | `turn_stopped` | `tool` |
| `PermissionRequest` | `needs_you` | `tool`, `tool_use_id` |
| `Notification`: `permission_prompt`, `elicitation_dialog` | `needs_you` | |
| `Notification`: `idle_prompt` | `turn_stopped` | |
| `Elicitation` | `needs_you` | |
| `ElicitationResult` | `activity` | |
| `Stop` | `turn_end` | |
| `StopFailure` | `turn_failed` | `error` |
| `SessionEnd` | `session_end` | |

**Codex** (`codex`):

| Hook | Becomes | `detail` |
| --- | --- | --- |
| `SessionStart` (startup, resume, clear) | `session_start` | |
| `UserPromptSubmit` | `turn_start` | |
| `PreToolUse` | `activity` | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `activity`, the call's result | `tool`, `tool_use_id`, `topic` |
| `PermissionRequest` | `needs_you` | `tool`, `tool_use_id` |
| `Stop` | `turn_end` | |
| `Interrupt` (you pressed Esc) | `turn_stopped` | |
| `SessionEnd` | `session_end` | |

Any other hook, or any other `Notification` type, is ignored; the
installer doesn't register them (§5). A call's result finds its topic and
start time from its `PreToolUse`, by `tool_use_id` or else the session's
last call.

**Failed commands.** Claude sends `PostToolUse` when a tool call works and
`PostToolUseFailure` when it fails, including a shell command that exits
with an error. The adapter keeps only that yes or no and the error's
class. Codex has no failure hook, and what its `PostToolUse` reports after
a failed command hasn't been seen, so Codex activity carries no `failed`
and a Codex turn never fails ([PLAN.md](PLAN.md) §3). What makes a turn
fail is in [BEHAVIORS.md](BEHAVIORS.md) §3.1.

**Interrupted turns.** Claude sends no `Stop` for a turn you interrupt
with Esc. The interrupted tool call becomes `turn_stopped`, and so does
`idle_prompt`, which Claude sends once it has sat at its prompt for about
a minute and which also covers an interrupt between tool calls.

**Project and workspace.** From the hook's `cwd`, read once per folder
and remembered (up to 512 folders, then the cache starts again), so a hook
never waits on the disk. A line without a `cwd` keeps the session's.

- **Project:** the folder's name, except that a git worktree maps to its
  main repository. `landing/.worktrees/fix-nav` and
  `landing/.claude/worktrees/fix-nav` are `landing` even unread, and so is
  any folder whose `.git` file points into `landing/.git/worktrees/`.
- **Workspace:** what tells two threads in one project apart: a linked
  worktree's name, else the branch in the folder's `.git/HEAD`; none on
  `main`, `master`, `trunk` or `develop`, on a detached head, or outside
  git. An agent picks its branch names, so the name is cleaned: a leading
  `word/` and a trailing hash (`-7a22ea`) go, it's lowercased, anything
  but `a-z` and `0-9` becomes `-`, and it's cut to 40 characters
  (`claude/agent-work-visibility-7a22ea` is `agent-work-visibility`).

**Topic tags.** So that Boop's one real word can be about the work
(*"…tests?"*), `boop-hook` glances at a tool's input to pick a tag, then
drops the input:

| Topic | When |
| --- | --- |
| `deploy` | A command that deploys (`vercel`, `fly deploy`, `kubectl apply`, `terraform apply`, `wrangler deploy`, `git push heroku`, …) |
| `tests` | A command that runs tests (`pytest`, `jest`, `npm test`, `go test`, `cargo test`, `swift test`, `make test`, `pio test`, …) |
| `build` | A command that builds (`make`, `tsc`, `npm run build`, `cargo build`, `swift build`, `xcodebuild`, `docker build`, …) |
| `docs` | An edit tool (`Edit`, `Write`, `MultiEdit`, `apply_patch`, …) touching a `.md`, `.mdx`, `.markdown`, `.txt` or `.rst` file |

A command's topic comes from what it runs: the program and the words
after it that aren't flags, in each command of the line
(`cd app && make -C firmware test` runs tests). It looks past
`VAR=value`, shell words such as `then` or `!`, and wrappers such as
`sudo -u ci`, `timeout 60`, `npx`, `uv run`, `bundle exec` or
`python -m`, and into `bash -c '…'` and `docker compose run web …`. A
check word in an argument, quoted text or a heredoc doesn't count, so
`grep -n "make test" Makefile` and `command -v pytest` have no topic. When
a line runs several, deploy beats tests, which beats build. The full lists
are in `app/HookWire/Topic.swift`.

## 4. Sessions and "needs you"

The core keeps one entry per agent and session. Each is **working**,
**idle** or **needs you**; a Codex request in its grace period (below)
still counts as working. Which of them the device shows is
[BEHAVIORS.md](BEHAVIORS.md) §2–3.

| Event | The session |
| --- | --- |
| Any, from a session Boop hasn't seen | Is created idle, then the event applies |
| `session_start` | Stays as it is |
| `turn_start`, `activity` | Works |
| `turn_end`, `turn_failed` | Goes idle |
| `turn_stopped` | Goes idle if it was working, with no rule reaction (the brain hears of a stopped turn, [harness/EVENTS.md](harness/EVENTS.md) §4) |
| `needs_you` | Needs you (below) |
| `session_end` | Is forgotten |
| No event for 1 hour (`staleWorkMs`) | Counts as idle if it was working |
| No event for 24 hours (`forgetMs`) | Is forgotten, so a missed `SessionEnd` can't keep Boop busy |

"Needs you" is the one signal that has to be right every time. Claude's
`PermissionRequest` fires exactly when Claude is about to ask you, and not
for tools you've already allowed. Codex's fires early: Codex can hand a
request to its optional automatic reviewer, a model that may approve it
without asking you, and the hook fires before that review.

**Who asked.** A request remembers its askers: the main agent, a Claude
subagent by its `agent_id`, or "anyone" for a request with no tool (a
`Notification` or `Elicitation`), which doesn't say who asked.

| While nothing waits | |
| --- | --- |
| `needs_you` with a tool | Starts a request from that asker. Claude's shows at once; Codex's waits 2 s first |
| `needs_you` without a tool | The same, from "anyone", unless it comes within 5 s of the session's last request clearing: then it's that request's `Notification` arriving late, and is ignored |

| While a request waits | |
| --- | --- |
| `needs_you` with a tool | Its asker joins the request (a sibling subagent asking too) |
| `needs_you` without a tool | Ignored: it's the same request (a `PermissionRequest` and its `Notification` count once) |
| `activity` from an asker | Answers that asker: the tool ran (you approved) or the agent moved on (you denied) |
| `activity` from anyone else | Nothing, unless "anyone" is asking: then it clears the request |
| `turn_stopped` without a tool (Claude's `idle_prompt`, Codex's `Interrupt`) | Answers the main agent, and "anyone" if no subagent is also asking. Claude never sends `idle_prompt` while the main agent's prompt is up, so it arrives about a minute after you press Esc on that prompt, which sends no hook. A subagent's request stays, since its prompt may still be up |
| Any other event: a new prompt, the turn ending, failing or interrupted mid-tool, the session starting or ending | Clears the request |

Once no asker is left, the request clears and the session works again,
before the event itself applies (so `turn_end` then makes it idle).

**Timers**, checked on the core's one-second tick (`Core.Config`):

| Timer | Value | What happens |
| --- | --- | --- |
| Codex grace (`codexGraceMs`) | 2 s | A Codex request nothing has answered shows, dated 2 s after it arrived. One the reviewer handled is answered by the session's next event within the grace, and never shows |
| Safety net (`safetyNetMs`) | 10 min with no events from the session | The request clears, shown or still in its grace, and the session goes idle: by then the agent is still waiting at its prompt or gone. This covers a grace no tick saw through, as when the Mac sleeps right after Codex asks. The session's next event makes it working again |

**What it can't see.**

- **Approved long commands.** Claude has no hook for the moment you
  approve, so "the tool ran" arrives only when the tool finishes: a long
  command you approved keeps "needs you" up until it ends, or until the
  safety net. Boop doesn't guess sooner, since a wrong guess would hide a
  prompt that's still open.
- **Denied with typed feedback** carries the turn on, and its next event
  clears the request as usual.
- **A denied subagent** that then ends without another tool call sends
  only `SubagentStop`, which Boop doesn't hook, so its request stays until
  the turn ends or the safety net ([PLAN.md](PLAN.md) §3).

When a Claude request starts showing, and when a Codex one does after its
grace, the core hands the harness a `needs_you` event, which never wakes
the brain ([harness/EVENTS.md](harness/EVENTS.md) §4). What you see and
hear is in [BEHAVIORS.md](BEHAVIORS.md) §3.2.

## 5. Installing and repairing hooks

**What gets written.** Every entry Boop adds is one group per hook, with
one command entry:

```json
{"hooks":[{"command":"\"~/Library/Application Support/Boop/bin/boop-hook\" claude","timeout":5,"type":"command"}]}
```

(the path is written out in full). Boop recognises its own entries by that
command: any command running `boop-hook`, or an older Boop's
`~/.boop/boop-hook.sh`. It never touches anyone else's.

| File | What Boop adds |
| --- | --- |
| `~/.claude/settings.json` | Under `hooks`, a group for each Claude hook in §3's table (12 hooks). `Notification`'s has the matcher `permission_prompt\|elicitation_dialog\|idle_prompt`, since Claude runs it only for the types its matcher lists |
| `~/.codex/hooks.json` | Under `hooks`, a group for each Codex hook in §3's table (8 hooks). `SessionStart`'s has the matcher `startup\|resume\|clear` |
| `~/.codex/config.toml` | `codex_hooks = true` under `[features]`, which Codex needs to run hooks at all. Added by install (or flipped from `false`), never removed, since other hooks may rely on it |

**The installer's operations** (`HookInstaller`):

- **Install** removes Boop's entries, current and old, then adds a fresh
  group for each hook. For Codex it also turns hooks on in `config.toml`,
  and writes neither file if it won't edit that one. Refused while
  `bin/boop-hook` is missing.
- **Remove** takes out Boop's entries, current and old, and nothing else.
  A group left empty goes, then an event, then `hooks`.
- **Repair** installs again for each agent whose entries are outdated. It
  never installs for an agent that has none.
- **Health**, per agent, checked in this order: *unreadable* (the file
  isn't a JSON object; it's left alone), *client missing* (no executable
  `bin/boop-hook`, so entries would drop every event without a sign),
  *not installed* (no Boop entries), *installed* (the file is what a fresh
  install would write) or *outdated*. Settings shows each as a row with
  its button ([UX.md](UX.md) §6).
- **Detected** means the agent's folder, `~/.claude` or `~/.codex`,
  exists.

**When they run.** Only the everyday Boop, the menu-bar app on
`~/Library/Application Support/Boop`, changes hooks, since hooks always
report to its socket.

| When | What happens |
| --- | --- |
| Launch | The app copies the `boop-hook` built next to it to `bin/boop-hook` if they differ (staged as `bin/boop-hook.new`, then swapped in), so rebuilding or moving the app doesn't break hooks. With none next to it, it keeps the copy in place. Then it repairs, and asks you to restart open agent sessions if anything changed |
| Setup | A switch for each agent, on for each one detected ([UX.md](UX.md) §5). Finishing setup installs for each switched-on, detected agent |
| Settings | One click to connect, repair or remove each agent. A change that works asks you to restart open sessions; one that fails says why |
| Another `--state-dir` | The menu-bar app installs, repairs and removes nothing, at setup or later ("only the everyday Boop changes them"), and logs why. It still reads the real hooks, so Settings shows how they stand. `Boop --headless` never touches hooks |

`boopdev hooks status|install|remove --home DIR` runs the same installer
against another home folder, for tests ([VERIFICATION.md](VERIFICATION.md)
§2).

**Careful writes.** A config file that's a symlink (a dotfiles setup) is
written through, not replaced. JSON is written sorted and pretty-printed,
atomically. Nothing is written when nothing would change, so installing
twice is the same as once. In `config.toml`, `[features]` is found however
it's written (`[ features ] # note`, or top-level `features.x = …` keys)
and never declared twice, which Codex refuses to load. An inline
`features = {…}` without `codex_hooks = true`, or a file with both a
`[features]` table and `features.` keys, is left for you to edit, and the
preview says what to add.

**Restart.** Agents read hooks at startup, so after an install, removal
or repair the app asks you to restart open sessions.

## 6. Checking it works

The `doctor` skill (`internal/skills/doctor/doctor.sh`) checks four things:

1. Hooks are registered for each agent and call a `boop-hook` that
   exists (the installer's own health check, through `boopdev hooks`).
2. The app is running and its socket accepts.
3. A synthetic event from `boop-hook` reaches the app (seen in its log).
4. With `--confirm`, a harmless command run in the agent
   (`echo BOOP_DOCTOR_PING`) shows up in Boop as a hook from this agent.

`--headless` runs checks 1–3 against a throwaway headless app. The app
logs hooks only while the doctor has armed it, by writing `doctor-armed`
into the state directory, or in debug mode (`--debug`,
[harness/HARNESS.md](harness/HARNESS.md) §9), which also logs the event
each hook became. `--confirm` removes the arm. An arm lasts 10 minutes:
the app removes an older one at the next hook, so a doctor run that never
confirms doesn't leave every hook logged for good.

## 7. Adding an agent

A new agent needs an adapter with a mapping like §3's, a way to register
hooks, and an answer to one question: what signal proves a person is being
asked? Without a reliable one, the agent gets activity and completion, but
no "needs you". Claude Cowork should need only the Claude adapter once its
sandbox runs the Mac's hooks ([FUTURE.md](FUTURE.md)).
