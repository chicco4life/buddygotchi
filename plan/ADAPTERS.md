# Boop: agent adapters

Updated 2026-09-29. How Boop hears from Claude Code and Codex: the hook
client, the raw event every hook becomes, how a session moves between
working, idle and "needs you", and how the hooks are installed. Code:
`app/HookWire/`, `app/BoopHook/`, `app/BoopKit/Adapters/`,
`app/BoopKit/Install/`, and the session rules in `app/BoopKit/Core/Core.swift`.

## 1. The job

An adapter turns one agent's hook calls into Boop's raw events.
Everything agent-specific lives here; the rest of Boop never sees a hook
payload.

Hooks only report. They never answer, block or change what the agent does,
so Boop can't approve or deny anything. Three rules follow:

1. **Exit fast.** The hook client writes one line and exits 0. It prints
   nothing, so the agent carries on with its own flow, its own approval
   prompt included.
2. **Fail open.** If the app isn't running, or its socket is missing or
   slow, the hook gives up within its budget (§2) and still exits 0.
3. **Send little.** Tool input and output, error text, file contents and
   transcripts never leave the hook client. From a tool's input it keeps
   only a topic tag (§3), and from an error only its class (§2). The only
   words it keeps are your prompt, the agent's last message and the
   thread's name (§2).

### The raw event

Every adapter produces the same shape, the transcript's
([harness/EVENTS.md](harness/EVENTS.md) §2): the same metadata for every
event, and `data` for what only its type has. This is the Claude
adapter's output for a `PreToolUse` that runs tests, once the transcript
has given it its `seq` (`AdapterTests.testEventJSONShape`):

```json
{"seq":102,"ts":1790000000123,"source":"claude","type":"tool","phase":"start","specific_type":"PreToolUse","session":"a1b2","cwd":"/Users/me/src/landing","data":{"tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}}
```

The generic `type` and `phase` are what the core and the view read;
`specific_type` keeps the hook's own name, so the transcript can be read
again if the mapping changes. `ts` is when the app received it, on its
steady clock ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2, "Clocks");
`boopdev replay` uses the hook line's own `ts`. The project and workspace
aren't sent: the core and the view work them out from `cwd` (§3).

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
   | `mode` | `permission_mode` (Claude's `default`, `plan`, `acceptEdits`…) | every hook that has it |
   | `source` | `source`: `startup`, `resume`, `clear` or `compact` | `SessionStart` |
   | `tool`, `tool_use_id` | `tool_name`, `tool_use_id` | `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` |
   | `topic` | the tool's input, read in memory (§3) | the same, except `PermissionRequest` |
   | `interrupt` | `is_interrupt` | `PostToolUseFailure` |
   | `tool_error` | `error`, as a class (below) | `PostToolUseFailure` that isn't an interrupt |
   | `error` | `error`, else `error_type` | `StopFailure` |
   | `kind` | `notification_type` | `Notification` |
   | `prompt` | `prompt`, up to 2,000 characters (`HookLine.maxMessage`) | `UserPromptSubmit` |
   | `message` | `last_assistant_message`, up to 2,000 characters | `Stop` |
   | `name` | the thread's name, as the agent's app shows it (below) | every hook |
   | `app`, `app_session` | the hook's environment: the app the agent runs in, and the Claude app's ID for the session (below) | every hook that has them |
   | `ts` | when `boop-hook` started, in ms | every hook |

   A payload cut off at 256 KB won't parse, so the hook name, session,
   `cwd`, `agent_id`, `permission_mode` and, for tool hooks, `tool_name`
   and `tool_use_id` are picked out of its start instead. It gets no topic.

   **The thread's name** (`ThreadName`) is read on every hook, so the
   needs-you strip, the popover and a finish name the thread as you do,
   and a rename shows at the thread's next hook. Claude's is the last
   title record in the session's transcript (`transcript_path`): a
   `custom-title` (yours, or the desktop app's) over an `ai-title` (the
   one Claude made up). Claude appends them every so often (in 55 real
   transcripts the last was always within 30 KB of the end), so the
   last 256 KB are read first, then the last 4 MB; a tool call's hooks
   (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`) read only the
   256 KB, so a thread with no title costs no wide read per call. A
   thread has no name until Claude titles it, after its first prompt.
   Codex's is the last `thread_name` for the thread in
   `session_index.jsonl` under `$CODEX_HOME` (else `~/.codex`). Only the
   name leaves: the rest of either file is read in memory and dropped.
   With no name found the line has none.

   **The app** is where a tap opens the thread
   ([BEHAVIORS.md](BEHAVIORS.md) §3.2), read from three environment
   variables the hook inherits from its agent (`HostApp`), and nothing
   else of the environment. `app` is `__CFBundleIdentifier`, which macOS
   gives a process an app launched and its children keep: the Claude
   app's (`com.anthropic.claudefordesktop`), or the terminal's
   (`com.mitchellh.ghostty`). The Codex app's agent server has none, so a
   Codex hook with `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` set is the Codex
   app's (`com.openai.codex`). `app_session` is Claude's
   `CLAUDE_CODE_HOST_SESSION_ID`, the Claude app's own `local_…` ID for
   the session, which its links take; Claude Code's `session_id` is
   another. These are the apps' own internals, so each can change with an
   update; then the thread doesn't open, or its app just comes forward.
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
hook line is a dev line (`{"dev":…}`),
taken only headless or in debug mode and dropped otherwise.

## 3. Event mapping

Each hook becomes a `type` and `phase`, with its name as
`specific_type` (`Adapter.mapping`).

**Claude Code** (`source` `claude`):

| Hook | `type` and `phase` | `data` |
| --- | --- | --- |
| `SessionStart` | `session` start | `source` |
| `UserPromptSubmit` | `turn` start | `prompt` |
| `PreToolUse` | `tool` start | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `tool` end, the call's result | `tool`, `tool_use_id`, `topic`, `failed: false` |
| `PostToolUseFailure` | `tool` end, the call's result | `tool`, `tool_use_id`, `topic`, `failed: true`, `error` (its class) |
| `PostToolUseFailure` with `is_interrupt` (you pressed Esc) | `turn` end | `outcome: stopped`, `tool` |
| `PermissionRequest` | `tool` wait | `tool`, `for: permission` (the hook has no `tool_use_id`) |
| `Notification`: `permission_prompt`, `elicitation_dialog` | `tool` wait | `notice`: the type; `for`: `permission` or `input` |
| `Notification`: `idle_prompt` | `turn` end | `outcome: stopped`, `notice: idle_prompt` |
| `Elicitation` | `tool` wait | `for: input` |
| `ElicitationResult` | `tool` end, with no tool | |
| `Stop` | `turn` end | `outcome: done`, `message` |
| `StopFailure` | `turn` end | `outcome: failed`, `error` |
| `SubagentStart` | `subagent` start, with the subagent's `agent_id`: a helper Boop saw start ([BEHAVIORS.md](BEHAVIORS.md) §2); ignored without one | |
| `SubagentStop` | `subagent` end, with the subagent's `agent_id`; ignored without one, since it would pass for the main agent | |
| `SessionEnd` | `session` end | |

Any Claude event from inside a subagent carries its `agent_id` as
`subagent` and its `agent_type` in `data`. Any Claude event whose hook
reports the permission mode carries it as `mode`, so the look can show
plan mode as planning ([BEHAVIORS.md](BEHAVIORS.md) §2). A subagent's
start, like its end, is Claude's alone: Codex has no hook for helpers.

**Codex** (`source` `codex`):

| Hook | `type` and `phase` | `data` |
| --- | --- | --- |
| `SessionStart` (startup, resume, clear) | `session` start | `source` |
| `UserPromptSubmit` | `turn` start | `prompt` |
| `PreToolUse` | `tool` start | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `tool` end, the call's result | `tool`, `tool_use_id`, `topic` |
| `PermissionRequest` | `tool` wait | `tool`, `for: permission` (the hook has no `tool_use_id`) |
| `Stop` | `turn` end | `outcome: done`, `message` |
| `Interrupt` (you pressed Esc) | `turn` end | `outcome: stopped` |
| `SessionEnd` | `session` end | |

Any other hook, or any other `Notification` type, is ignored; the
installer doesn't register them (§5). A call's result finds its topic and
start time from its `PreToolUse`, by `tool_use_id` or else the session's
last call.

**Failed commands.** Claude sends `PostToolUse` when a tool call works and
`PostToolUseFailure` when it fails, including a shell command that exits
with an error. The adapter keeps only that yes or no and the error's
class. Codex has no failure hook, and what its `PostToolUse` reports after
a failed command hasn't been seen, so a Codex tool end carries no
`failed` and a Codex turn never fails. What makes a turn
fail is in [BEHAVIORS.md](BEHAVIORS.md) §3.1.

**Interrupted turns.** Claude sends no `Stop` for a turn you interrupt
with Esc. The interrupted tool call becomes a stopped `turn` end, and so
does `idle_prompt`, which Claude sends once it has sat at its prompt for about
a minute and which also covers an interrupt between tool calls.

**Project and workspace.** From the hook's `cwd`, read once per folder
and remembered (up to 512 folders, then the cache starts again), so a hook
never waits on the disk. A line without a `cwd` keeps the session's, and
so does every line while a request waits (§4): the strip names where the
request was made, whatever folder a sibling subagent works in meanwhile.

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
| `inspect` | A command that only looks at files, with no check in it: every command in the line reads (`rg`, `grep`, `cat`, `sed -n`, `find`, `ls`, `head`, `tail`, `wc`, `nl`, `sort`, `uniq`, `cut`) or neither reads nor changes anything (`cd`, `echo`, `pwd`), and none writes a file with `>`. `sed -i` and `find -delete` or `-exec` don't count. The look shows it as analyzing, not a terminal ([BEHAVIORS.md](BEHAVIORS.md) §2), Codex's shell reads included |

A command's topic comes from what it runs: the program and the words
after it that aren't flags, in each command of the line
(`cd app && make -C firmware test` runs tests). It looks past
`VAR=value`, shell words such as `then` or `!`, and wrappers such as
`sudo -u ci`, `timeout 60`, `npx`, `uv run`, `bundle exec` or
`python -m`, and into `bash -c '…'` and `docker compose run web …`. A
check word in an argument, quoted text or a heredoc doesn't count, so
`grep -n "make test" Makefile` and `command -v pytest` have no topic. When
a line runs several, deploy beats tests, which beats build, and any of
them beats `inspect`: `swift test 2>&1 | tail -20` is tests. The full
lists are in `app/HookWire/Topic.swift`.

## 4. Sessions and "needs you"

The core keeps one entry per agent and session. Each is **working**,
**idle** or **needs you**; a Codex request in its grace period (below)
still counts as working. Which of them the device shows is
[BEHAVIORS.md](BEHAVIORS.md) §2–3.

| Raw event | The session |
| --- | --- |
| Any, from a session Boop hasn't seen | Is created idle, then the event applies |
| Any but a `session` start or `turn` start, from a session that ended (a `session` end) in the last 24 hours and hasn't started again | Ignored: it landed late, from before the end. A permission `Notification` as you quit at the prompt, a background subagent's result or end, the command Codex's `Interrupt` aborted, or a `Stop` would otherwise bring the session back as needing you, working or idle, keeping Boop awake. A resumed session (a `session` start) or a new prompt brings it back |
| `session` start | Stays as it is |
| `turn` start, `tool` start or end | Works |
| A `tool` end that's a call's result, once its turn has ended or stopped, for a call that started before then | Stays as it is. The result landed late: you pressed Esc as a parallel call finished, a subagent's call raced the interrupt, or Codex reported the command its `Interrupt` aborted. It still counts for the thread ([harness/EVENTS.md](harness/EVENTS.md) §4), but it doesn't start the turn again, so a stopped turn isn't recorded twice |
| `turn` end, done or failed | Goes idle |
| `turn` end, stopped | Goes idle, with no rule reaction. If its turn is still open, even after the safety net (below) made the session idle, that turn ends as stopped and the brain hears of it ([harness/EVENTS.md](harness/EVENTS.md) §4), so a call's result after it is a late one (above). Claude's `idle_prompt` less than 30 s after the session's last `turn` start (`SessionFold.idleNoticeMinMs`) is ignored: it comes after a minute at the prompt, so it's from before that prompt, one typed just as the minute ran out. A turn that a call started, with no prompt (a background subagent's after the main agent stopped), has nothing for the notice to race |
| `subagent` start | Stays as it is, as for its end: it only tells the look a helper is at work ([BEHAVIORS.md](BEHAVIORS.md) §2) |
| `subagent` end | Stays as it is: a subagent finishing isn't activity, and it doesn't count as an event for the timers below, so it can't make an idle or stale session look busy. It can answer a request (below) |
| A `session` start or end, `turn` start, or `turn` end done or failed, from inside a subagent (with its `agent_id`) | The same as a `subagent` end: that subagent's alone, not the session's turn |
| `tool` wait | Needs you (below) |
| `session` end | Is forgotten, and marked as ended (above) |
| No event for 1 hour (`staleWorkMs`) | Counts as idle if it was working |
| No event for 24 hours (`forgetMs`) | Is forgotten, so a missed `SessionEnd` can't keep Boop busy |

"Needs you" is the one signal that has to be right every time. Claude's
`PermissionRequest` fires exactly when Claude is about to ask you, and not
for tools you've already allowed. Codex's fires early: Codex can hand a
request to its optional automatic reviewer, a model that may approve it
without asking you, and the hook fires before that review.

**Who asked.** A request remembers its askers: the main agent, or a
Claude subagent by its `agent_id`, as its own hook names them
(`PermissionRequest` with its tool, `Elicitation` without one). Claude's
`Notification` (`notice`) repeats a request that its own hook makes too,
landing just before or after it, and doesn't say who asked: one that
starts a request starts it from "anyone".

| While nothing waits | |
| --- | --- |
| `tool` wait from a hook | Starts a request from its asker. Claude's shows at once; Codex's waits 2 s first |
| `tool` wait from a `Notification` | The same, from "anyone", unless it's the late copy of the session's last request: of the type that request sends (a `PermissionRequest`'s `permission_prompt`, an `Elicitation`'s `elicitation_dialog`), and within 5 s of that request clearing or before any tool call has started since (a new request always follows a new call). Then it's ignored |

| While a request waits | |
| --- | --- |
| `tool` wait from a hook | Its asker joins the request (a sibling subagent asking too). If the request is a `Notification`'s from "anyone" under 5 s old, the hook is that request's own and takes it over |
| `tool` wait from a `Notification` | Ignored: it's the same request (a `PermissionRequest` and its `Notification` count once) |
| `tool` start or end from an asker | Answers that asker: the tool ran (you approved) or the agent moved on (you denied). Not the result of a call for another tool, which the agent made alongside the one that asks (Claude runs read-only calls in parallel, and the main agent's `Agent` call runs on while it asks). A request has no `tool_use_id`, so only the tool's name tells them apart: a parallel call of the same tool still answers it. An `Elicitation` asks for no tool, so no call's result answers it: its `ElicitationResult` does, or the agent's next call |
| `tool` start or end from anyone else | Nothing, unless "anyone" is asking: then it clears the request |
| A stopped `turn` end without a tool (Claude's `idle_prompt`, Codex's `Interrupt`) | Clears the request, as any turn-level event does. `idle_prompt` means Claude has sat at its own prompt for about a minute with the turn over, which it never does while a prompt is up, a subagent's included: it arrives about a minute after you press Esc on a prompt, which sends no hook |
| `subagent` end | Answers that subagent only: one that has finished can't be waiting on a prompt. That's how a subagent you denied, which carries on and ends without another tool call, is answered. The main agent, other subagents and "anyone" stay asking |
| Any other event: a new prompt, the turn ending, failing or interrupted mid-tool, the session starting or ending | Clears the request too |

Once no asker is left, the request clears and the session works again,
before the event itself applies (so a `turn` end then makes it idle). After
a `subagent` end it works again only if its turn is still going, and
otherwise goes idle.

**Timers**, checked on the core's one-second tick (the grace in `Core.Config`, the rest in `SessionFold`):

| Timer | Value | What happens |
| --- | --- | --- |
| Codex grace (`codexGraceMs`) | 2 s | A Codex request nothing has answered shows at the first tick past its grace (2–3 s after it arrived), dated 2 s after it arrived. One the reviewer handled is answered by the session's next event within the grace, and never shows, as long as that event comes within the grace: see "What it can't see" below. So is one that event answers after the grace but before a tick showed it: the core records no `needs_you` action for it, since the screen never showed it |
| Safety net (`safetyNetMs`) | 10 min with no events from the session | The request clears, shown or still in its grace, and the session goes idle: by then the agent is still waiting at its prompt or gone. This covers a grace no tick saw through, as when the Mac sleeps right after Codex asks. The turn stays open, since you may have approved (which sends no hook) and the command run on: the session's next event makes it working again, and an interrupt still stops the turn |

**What it can't see.**

- **Approved long commands.** Claude has no hook for the moment you
  approve, so "the tool ran" arrives only when the tool finishes: a long
  command you approved keeps "needs you" up until it ends, or until the
  safety net. Boop doesn't guess sooner, since a wrong guess would hide a
  prompt that's still open.
- **Denied with typed feedback** carries the turn on, and its next event
  clears the request as usual.
- **A denied subagent** stays amber while it takes in your answer, until
  its next tool call or its end answers it.
- **Codex's reviewer approving** sends no hook either, as far as the
  hand-written fixtures know: the next hook is the command's own result.
  So a command the reviewer approves that runs past the 2 s grace shows
  "needs you", with its alert, from 2 s until it ends, as an approved long
  command of Claude's does; so does any command whose review takes over
  2 s. Nobody was asked. A recorded Codex session would
  show whether Codex sends something the grace could wait for.

When a Claude request starts showing, and when a Codex one does after its
grace, the core records a `needs_you` action, which the view keeps as
the request's `tool` wait, never waking the brain
([harness/EVENTS.md](harness/EVENTS.md) §2, §4). When it clears, the core
records the action's end. What you see and
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
| `~/.claude/settings.json` | Under `hooks`, a group for each Claude hook in §3's table (14 hooks). `Notification`'s has the matcher `permission_prompt\|elicitation_dialog\|idle_prompt`, since Claude runs it only for the types its matcher lists. An install from before `SubagentStart` is outdated, so the launch repair adds it |
| `~/.codex/hooks.json` | Under `hooks`, a group for each Codex hook in §3's table (8 hooks). `SessionStart`'s has the matcher `startup\|resume\|clear`, so a Codex session never starts as `compact` |
| `~/.codex/config.toml` | `codex_hooks = true` under `[features]`, which Codex needs to run hooks at all. Added by install (or flipped from `false`), never removed, since other hooks may rely on it |

The installer takes the hooks from the adapter's tables (`Adapter.claude`,
`Adapter.codex`), in their order, which installs already have.

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
  its button.
- **Detected** means the agent's folder, `~/.claude` or `~/.codex`,
  exists.

**When they run.** Only the everyday Boop, the menu-bar app on
`~/Library/Application Support/Boop`, changes hooks, since hooks always
report to its socket.

| When | What happens |
| --- | --- |
| Launch | The app copies the `boop-hook` built next to it to `bin/boop-hook` if they differ (staged as `bin/boop-hook.new`, then swapped in), so rebuilding or moving the app doesn't break hooks. With none next to it, it keeps the copy in place. Then it repairs, and asks you to restart open agent sessions if anything changed |
| Setup | A switch for each agent, on for each one detected. Finishing setup installs for each switched-on, detected agent |
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
sandbox runs the Mac's hooks.
