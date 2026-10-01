# agent-hooks: the spec

Updated 2026-10-01. What agent-hooks does, exactly: the hook client and
where it sends, the event every hook becomes, how a session moves between
working, idle and "needs you", how the hooks are installed, and the
command line. [README.md](README.md) is the overview. Code: `Sources/`,
tested by `Tests/AgentHooksTests/` (`swift test`).

## 1. The job

agent-hooks turns Claude Code's and Codex's hook calls into one kind of
event, and keeps track of each session from those events. Everything
agent-specific lives here: an app that uses it never sees a hook payload.

Hooks only report. They never answer, block or change what the agent does,
so nothing built on agent-hooks can approve or deny anything. Three rules
follow:

1. **Exit fast.** The hook client writes one line and exits 0. It prints
   nothing, so the agent carries on with its own flow, its own approval
   prompt included.
2. **Fail open.** If no app is listening, or a socket is missing or slow,
   the client gives up within its budget (§2) and still exits 0.
3. **Send little.** Tool input and output, error text, file contents and
   transcripts never leave the hook client. From a tool's input it keeps
   only a topic tag (§3), and from an error only its class (§2). The only
   words it keeps are the thread's name and, with `--keep-text`, your
   prompt and the agent's last message (§2).

| Piece | What it is |
| --- | --- |
| `agent-hook` (`Sources/AgentHookClient/`) | The client every hook entry runs (§2) |
| `AgentHooksWire` | What the client and the library share, in Foundation alone, so both sides agree on the line by construction: the hook line, the socket folder, topic tags, error classes, thread names and the host app. Kept small so the client starts fast |
| `AgentHooks` | The library apps link: the listener (`HookServer`), events (`Mapping`, `AgentEvent`, §3), places (`Place`), sessions (`SessionTracker`, §4), the installer (`HookInstaller`, §5) and thread links (`ThreadLink`). It re-exports `AgentHooksWire` |
| `agent-hooks` (`Sources/AgentHooksCLI/`) | The command line (§6) |

### The event

Every hook becomes an `AgentEvent` (§3): the agent, a `kind` and a
`phase`, the hook's own name, the session and the time, and the few facts
that hook carries. This is a `PreToolUse` that runs tests, as
`agent-hooks tail` prints it (§6):

```json
{"agent":"claude","app":"com.mitchellh.ghostty","at":1790755424947,"cwd":"/tmp/ah.fhVr/src/landing","hook":"PreToolUse","kind":"tool","mode":"default","phase":"start","session":"s1","tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}
```

The kind and phase are what an app reads. `hook` keeps the agent's own
name, so events an app keeps can be read again if the mapping changes. `at`
is when the app received the line (`Mapping.event(from:receivedAt:)`), or
else the line's own `ts`, when the client started.

## 2. The hook client and the socket

Every hook entry runs one small compiled binary, `agent-hook claude` or
`agent-hook codex` (with no agent it's `claude`; any other sends nothing),
followed by `--keep-text` if the install asked for it (§5).

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
   | `prompt` | `prompt`, up to 2,000 characters (`HookLine.maxMessage`), with `--keep-text` | `UserPromptSubmit` |
   | `message` | `last_assistant_message`, up to 2,000 characters, with `--keep-text` | `Stop` |
   | `name` | the thread's name, as the agent's app shows it (below) | every hook |
   | `app`, `app_session` | the hook's environment: the app the agent runs in, and the Claude app's ID for the session (below) | every hook that has them |
   | `ts` | when `agent-hook` started, in ms | every hook |

   A payload cut off at 256 KB won't parse, so the hook name, session,
   `cwd`, `agent_id`, `permission_mode` and, for tool hooks, `tool_name`
   and `tool_use_id` are picked out of its start instead. It gets no topic.

   **The thread's name** (`ThreadName`) is read on every hook, so an app
   can name the thread as you do, and a rename shows at the thread's next
   hook. Claude's is the last title record in the session's transcript
   (`transcript_path`): a `custom-title` (yours, or the desktop app's) over
   an `ai-title` (the one Claude made up). Claude appends them every so
   often (in 55 real transcripts the last was always within 30 KB of the
   end), so the last 256 KB are read first, then the last 4 MB; a tool
   call's hooks (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`) read
   only the 256 KB, so a thread with no title costs no wide read per call.
   A thread has no name until Claude titles it, after its first prompt.
   Codex's is the last `thread_name` for the thread in
   `session_index.jsonl` under `$CODEX_HOME` (else `~/.codex`). Only the
   name leaves: the rest of either file is read in memory and dropped.
   With no name found the line has none.

   **The app** is where the thread opens (`ThreadLink`), read from three
   environment variables the hook inherits from its agent (`HostApp`), and
   nothing else of the environment. `app` is `__CFBundleIdentifier`, which
   macOS gives a process an app launched and its children keep: the Claude
   app's (`com.anthropic.claudefordesktop`), or the terminal's
   (`com.mitchellh.ghostty`). The Codex app's agent server has none, so a
   Codex hook with `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` set is the Codex
   app's (`com.openai.codex`). `app_session` is Claude's
   `CLAUDE_CODE_HOST_SESSION_ID`, the Claude app's own `local_…` ID for
   the session, which its links take; Claude Code's `session_id` is
   another. `ThreadLink.target` turns them into `claude://code/continue?session=…`,
   `codex://threads/…`, or the app to bring forward. These are the apps'
   own internals, so each can change with an update; then the thread
   doesn't open, or its app just comes forward.
3. **Send.** One JSON line to every app listening: each `*.sock` in the
   socket folder (below), in name order. `$AGENT_HOOKS_SOCKET`, when it's
   set, is the only place the line goes, for tests and checks. Connecting
   and writing are non-blocking and share one 50 ms budget per socket;
   past it the line is dropped for that socket. A socket nobody listens on
   fails at once.
4. **Exit** 0, having printed nothing.

**The socket folder** is `~/.agent-hooks/sockets/`, or
`$AGENT_HOOKS_DIR/sockets/` when that's set (`HookSocket.directory`). An
app lists its socket there as `<name>.sock`, the socket itself or a link
to it (`HookSocket.register(path, as: name)`). Once is enough: a link left
behind while the app is closed costs a hook nothing, since connecting
fails at once. So any number of apps hear one set of hook entries, with
nothing else running. The folder's path is short on purpose: a socket's
path has room for 103 bytes.

**Keeping text.** Without `--keep-text`, none of your words or the agent's
leave the client but the thread's name. With it, your prompt and the
agent's last message do, for an app that shows or summarises them. It's
one choice per install, since every entry runs the same command (§5).

**Error classes.** A failed tool call's `error` text becomes `timeout`
("timed out", "timeout"), `exit_code` ("exit code", "exited", "non-zero",
"status code"), `denied` ("denied", "not allowed", "rejected",
"permission"), or `other`, checked in that order (`ToolError`). A failed
command's text is Claude's `Exit code N`, then the command's stderr and
stdout, so a rejected `git push` or a test named for permissions is still
`exit_code`. A failed turn's `error` becomes, in the library, one of
`rate_limit`, `overloaded`, `api_error`, `auth`, `timeout`, `network`,
`context_limit`, `billing` or `other`: Claude's `server_error`,
`invalid_request` and `model_not_found` are `api_error`,
`max_output_tokens` is `context_limit`, `account_on_hold`,
`verification_required` and `cloud_credential_error` are `auth`, and any
other text is the first class it contains, else `other`
(`Mapping.errorClass`).

**The listening end.** `HookServer` listens on an app's socket (mode 0600,
replaced at `start`, removed at `stop`) on its own thread. It reads each
connection until it closes, goes quiet for 200 ms or reaches 64 KB, splits
it into lines and hands each hook line (`HookLine.decode`) to `onLine`,
on that thread. A line that isn't a hook line goes to `onOther`, for an
app's own commands, or is dropped. It never writes back.

## 3. Events

Each hook becomes a `kind` and `phase`, with its name as `hook`
(`Mapping`). Only a `tool` waits: on you.

| Kind | `start` | `wait` | `end` |
| --- | --- | --- | --- |
| `session` | It started, resumed, cleared or compacted | | It ended |
| `turn` | You sent a prompt | | It's over: `outcome` `done`, `failed` or `stopped` |
| `tool` | A call starts | A call waits on you, for permission or an answer (`asking`) | A call's result |
| `subagent` | A Claude subagent starts | | It ends |

Every event has `agent` (`claude` or `codex`), `kind`, `phase`, `hook`,
`session` and `at`, and, when its hook has them, `cwd`, `name`, `app`,
`app_session` and `mode`. A Claude event from inside a subagent also has
`subagent` (its `agent_id`) and `subagent_type` (its `agent_type`:
`Explore`, `Plan`). The rest depends on the hook. On the wire (`agent-hooks
tail`) the fields are snake_case, and an empty one is left out.

**Claude Code:**

| Hook | Kind and phase | Fields |
| --- | --- | --- |
| `SessionStart` | `session` start | `source` |
| `UserPromptSubmit` | `turn` start | `prompt`, with `--keep-text` |
| `PreToolUse` | `tool` start | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `tool` end, the call's result | `tool`, `tool_use_id`, `topic`, `failed: false` |
| `PostToolUseFailure` | `tool` end, the call's result | `tool`, `tool_use_id`, `topic`, `failed: true`, `error` (its class) |
| `PostToolUseFailure` with `is_interrupt` (you pressed Esc) | `turn` end | `outcome: stopped`, `tool` |
| `PermissionRequest` | `tool` wait | `tool`, `asking: permission` (the hook has no `tool_use_id`) |
| `Notification`: `permission_prompt`, `elicitation_dialog` | `tool` wait | `notice`: the type; `asking`: `permission` or `input` |
| `Notification`: `idle_prompt` | `turn` end | `outcome: stopped`, `notice: idle_prompt` |
| `Elicitation` | `tool` wait | `asking: input` |
| `ElicitationResult` | `tool` end, with no tool | |
| `Stop` | `turn` end | `outcome: done`, `message`, with `--keep-text` |
| `StopFailure` | `turn` end | `outcome: failed`, `error` |
| `SubagentStart` | `subagent` start, with the subagent's `agent_id`; dropped without one | |
| `SubagentStop` | `subagent` end, with the subagent's `agent_id`; dropped without one, since it would pass for the main agent | |
| `SessionEnd` | `session` end | |

A subagent's start, like its end, is Claude's alone: Codex has no hook
for helpers.

**Codex:**

| Hook | Kind and phase | Fields |
| --- | --- | --- |
| `SessionStart` (startup, resume, clear) | `session` start | `source` |
| `UserPromptSubmit` | `turn` start | `prompt`, with `--keep-text` |
| `PreToolUse` | `tool` start | `tool`, `tool_use_id`, `topic` |
| `PostToolUse` | `tool` end, the call's result | `tool`, `tool_use_id`, `topic` |
| `PermissionRequest` | `tool` wait | `tool`, `asking: permission` (the hook has no `tool_use_id`) |
| `Stop` | `turn` end | `outcome: done`, `message`, with `--keep-text` |
| `Interrupt` (you pressed Esc) | `turn` end | `outcome: stopped` |
| `SessionEnd` | `session` end | |

Any other hook, or any other `Notification` type, becomes no event; the
installer doesn't register them (§5). A call's result finds its start
time, and its topic if it has none, from its `PreToolUse`, by
`tool_use_id` or else the session's last call (`Turn.callEnded`).

**Failed commands.** Claude sends `PostToolUse` when a tool call works and
`PostToolUseFailure` when it fails, including a shell command that exits
with an error. The event keeps only that yes or no and the error's class.
Codex has no failure hook, and what its `PostToolUse` reports after a
failed command hasn't been seen, so a Codex tool end has no `failed` and a
Codex turn never fails.

**Interrupted turns.** Claude sends no `Stop` for a turn you interrupt
with Esc. The interrupted tool call becomes a stopped `turn` end, and so
does `idle_prompt`, which Claude sends once it has sat at its prompt for
about a minute and which also covers an interrupt between tool calls.

**Project and workspace** (`Place.at(cwd:)`), from an event's `cwd`.
`Places` reads each folder once and remembers it for 30 s (up to 512
folders, then it starts again), so an app rarely waits on the disk and a
branch you check out shows within 30 s.

- **Repository:** the folder, or, when it has no `.git`, the nearest
  folder above it that has one, looking up to 8 folders (`Place.lookUp`)
  and never at the home folder or past it. So an agent that runs
  `cd firmware` stays in its repository. A folder with no repository above
  it is its own. The project and workspace are the repository's.
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

**Tool kinds.** So an app never keeps a list of the agents' tool names,
`ToolKind.of(tool)` says what kind of work a call is, and an event's
`toolKind` and a running call's `kind` say it too. It's worked out from
the name, so it isn't on the wire:

| Kind | Tools |
| --- | --- |
| `shell` | `Bash`, `shell`, `exec_command`, `local_shell` |
| `edit` | `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `apply_patch`, `edit`, `write`, `write_file`, `edit_file` |
| `read` | `Read` |
| `search` | `Grep`, `Glob`, `LS` |
| `web` | `WebFetch`, `WebSearch` |
| `subagent` | `Task`, `Agent` |
| `planning` | `TodoWrite`, `ExitPlanMode`, `update_plan` |
| `mcp` | any `mcp__…` |
| `other` | anything else |

A new or renamed agent tool is one line in `ToolKind.tools`.

**Topic tags.** So an app can say what the work is without the command,
`agent-hook` glances at a tool's input to pick a tag, then drops the
input:

| Topic | When |
| --- | --- |
| `deploy` | A command that deploys (`vercel`, `fly deploy`, `kubectl apply`, `terraform apply`, `wrangler deploy`, `git push heroku`, …) |
| `tests` | A command that runs tests (`pytest`, `jest`, `npm test`, `go test`, `cargo test`, `swift test`, `make test`, `pio test`, …) |
| `build` | A command that builds (`make`, `tsc`, `npm run build`, `cargo build`, `swift build`, `xcodebuild`, `docker build`, …) |
| `docs` | An edit tool (`Edit`, `Write`, `MultiEdit`, `apply_patch`, …) touching a `.md`, `.mdx`, `.markdown`, `.txt` or `.rst` file |
| `inspect` | A command that only looks at files, with no check in it: every command in the line reads (`rg`, `grep`, `cat`, `sed -n`, `find`, `ls`, `head`, `tail`, `wc`, `nl`, `sort`, `uniq`, `cut`) or neither reads nor changes anything (`cd`, `echo`, `pwd`), and none writes a file with `>`. `sed -i` and `find -delete` or `-exec` don't count. So an app can tell reading from running, Codex's shell reads included |

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
lists are in `Sources/AgentHooksWire/Topic.swift`.

**Your own commands.** `topics.json` in the agent-hooks folder
(`~/.agent-hooks/`, or `$AGENT_HOOKS_DIR`) adds command shapes to
`deploy`, `tests` and `build` (`Topic.extraPatterns`):

```json
{"tests": [["just", "check"]], "build": [["./build.sh"]]}
```

A shape is a program and the words that must follow it, in order, as the
built-in ones are. Its program is matched by name, so `["./build.sh"]`
matches `build.sh` run from any folder. A shape for another topic, with no
words or with a blank word is left out, and the topics keep their order.
The client reads the file on every hook; one that's missing or doesn't
read adds nothing.

## 4. Sessions and "needs you"

`SessionTracker` keeps one entry per agent and session, keyed
`claude/<session>` (`SessionFold.key`). Each is **working**, **idle** or
**needs you**; a Codex request in its grace period (below) still counts as
working. It has no queue or clock of its own: `handle` applies each event
at its time, the timers due by then first, and returns what the event did
(`Change`), or nil when it didn't count; `advance(to:)` runs the timers,
about once a second; `grouped(at:)` lists the sessions, those that need
you first (oldest first), then working, then idle. Touch it from one
queue.

| Event | The session |
| --- | --- |
| Any, from a session it hasn't seen | Is created idle, then the event applies |
| Any but a `session` start or `turn` start, from a session that ended (a `session` end) in the last 24 hours and hasn't started again | Ignored: it landed late, from before the end. A permission `Notification` as you quit at the prompt, a background subagent's result or end, the command Codex's `Interrupt` aborted, or a `Stop` would otherwise bring the session back as needing you, working or idle. A resumed session (a `session` start) or a new prompt brings it back |
| `session` start | Stays as it is |
| `turn` start, `tool` start or end | Works. The main agent's call with no turn open opens one (Claude carrying on after another hook blocked its `Stop`); a subagent's doesn't, so a background helper that works on after the main agent's `Stop` makes the session work with no turn |
| A `tool` end that's a call's result, once its turn has ended or stopped, for a call that started before then | Stays as it is (`callEnded(late: true)`). The result landed late: you pressed Esc as a parallel call finished, a subagent's call raced the interrupt, or Codex reported the command its `Interrupt` aborted. It doesn't start the turn again, so a stopped turn doesn't end twice |
| `turn` end, done or failed | Goes idle |
| `turn` end, stopped | Goes idle. If its turn is still open, even after the safety net (below) made the session idle, that turn ends as stopped (`turnEnded(.stopped, endedTurn: true)`), so a call's result after it is a late one (above). Claude's `idle_prompt` less than 30 s after the session's last `turn` start (`SessionFold.idleNoticeMinMs`) is ignored: it comes after a minute at the prompt, so it's from before that prompt, one typed just as the minute ran out. A turn that the main agent's call started, with no prompt, has nothing for the notice to race. With no turn open, the notice ends none (`endedTurn: false`) |
| `subagent` start | Stays as it is: the helper is at work (`Session.helpers`) until its end |
| `subagent` end | Stays as it is: a subagent finishing isn't activity, and it doesn't count as an event for the timers below, so it can't make an idle or stale session look busy. It can answer a request (below). One that leaves no turn open and no call running makes a working session idle: a background helper that worked on after the main agent's `Stop` is done. A helper seen starting that ends while its turn goes on has returned (`subagentEnded(returned: true)`) |
| A `session` start or end, `turn` start, or `turn` end done or failed, from inside a subagent (with its `agent_id`) | That subagent's alone, not the session's turn: like a `subagent` end, it isn't activity and it can answer that subagent's request (below). Only the `subagent` end itself ends the helper, so only it makes a working session idle |
| `tool` wait | Needs you (below) |
| `session` end | Is forgotten, and marked as ended (above) |
| No event for 1 hour (`SessionFold.staleWorkMs`) | Counts as idle if it was working |
| No event for 24 hours (`SessionFold.forgetMs`) | Is forgotten, so a missed `SessionEnd` can't keep it around |

"Needs you" is the one signal that has to be right every time. Claude's
`PermissionRequest` fires exactly when Claude is about to ask you, and not
for tools you've already allowed. Codex's fires early: Codex can hand a
request to its optional automatic reviewer, a model that may approve it
without asking you, and the hook fires before that review.

**Who asked.** A request remembers its askers (`Session.askers`): the main
agent, or a Claude subagent by its `agent_id`, as its own hook names them
(`PermissionRequest` with its tool, `Elicitation` without one). Claude's
`Notification` (`notice`) repeats a request that its own hook makes too,
landing just before or after it, and doesn't say who asked: one that
starts a request starts it from "anyone" (`SessionTracker.anyone`).

| While nothing waits | |
| --- | --- |
| `tool` wait from a hook | Starts a request from its asker. Claude's shows at once; Codex's waits 2 s first |
| `tool` wait from a `Notification` | The same, from "anyone", unless it's the late copy of the session's last request: of the type that request sends (a `PermissionRequest`'s `permission_prompt`, an `Elicitation`'s `elicitation_dialog`), and within 5 s of that request clearing (`noticeLagMs`) or before any tool call has started since (a new request always follows a new call). Then it's ignored |

| While a request waits | |
| --- | --- |
| `tool` wait from a hook | Its asker joins the request (a sibling subagent asking too). If the request is a `Notification`'s from "anyone" under 5 s old, the hook is that request's own and takes it over |
| `tool` wait from a `Notification` | Ignored: it's the same request (a `PermissionRequest` and its `Notification` count once) |
| `tool` start or end from an asker | Answers that asker: the tool ran (you approved) or the agent moved on (you denied). Not the result of a call for another tool, which the agent made alongside the one that asks (Claude runs read-only calls in parallel, and the main agent's `Agent` call runs on while it asks). A request has no `tool_use_id`, so only the tool's name tells them apart: a parallel call of the same tool still answers it. An `Elicitation` asks for no tool, so no call's result answers it: its `ElicitationResult` does, or the agent's next call |
| `tool` start or end from anyone else | Nothing, unless "anyone" is asking: then it clears the request, once the request is 1 s old (`noticeFirstMs`). Sooner, it's a sibling's call landing between a `Notification` and its request's own hook, and nobody answers a prompt that fast |
| A stopped `turn` end without a tool (Claude's `idle_prompt`, Codex's `Interrupt`) | Clears the request, as any turn-level event does. `idle_prompt` means Claude has sat at its own prompt for about a minute with the turn over, which it never does while a prompt is up, a subagent's included: it arrives about a minute after you press Esc on a prompt, which sends no hook |
| `subagent` end | Answers that subagent only: one that has finished can't be waiting on a prompt. That's how a subagent you denied, which carries on and ends without another tool call, is answered. The main agent, other subagents and "anyone" stay asking |
| Any other event: a new prompt, the turn ending, failing or interrupted mid-tool, the session starting or ending | Clears the request too |

Once no asker is left, the request clears and the session works again,
before the event itself applies (so a `turn` end then makes it idle). After
a `subagent` end it works again only if its turn is still going, and
otherwise goes idle. When one of several askers is answered, the next
one's prompt shows in its place: a new request.

**Timers**, run by `advance(to:)` and before each event (the grace in
`SessionTracker`, the rest in `SessionFold`):

| Timer | Value | What happens |
| --- | --- | --- |
| Codex grace (`codexGraceMs`) | 2 s | A Codex request nothing has answered shows at the first `advance`, or another session's event, past its grace, dated 2 s after it arrived (`needsSince`). One the reviewer handled is answered by the session's next event within the grace, and never shows, as long as that event comes within the grace: see "What it can't see" below. So is one that event answers after the grace but before anything showed it |
| Safety net (`safetyNetMs`) | 10 min with no events from the session | The request clears, shown or still in its grace, and the session goes idle: by then the agent is still waiting at its prompt or gone. This covers a grace no `advance` saw through, as when the Mac sleeps right after Codex asks. The turn stays open, since you may have approved (which sends no hook) and the command run on: the session's next event makes it working again, and an interrupt still stops the turn |

**What it can't see.**

- **Approved long commands.** Claude has no hook for the moment you
  approve, so "the tool ran" arrives only when the tool finishes: a long
  command you approved keeps "needs you" up until it ends, or until the
  safety net. The tracker doesn't guess sooner, since a wrong guess would
  hide a prompt that's still open.
- **Denied with typed feedback** carries the turn on, and its next event
  clears the request as usual.
- **A denied subagent** keeps needing you while it takes in your answer,
  until its next tool call or its end answers it.
- **Codex's reviewer approving** sends no hook either, as far as the
  hand-written fixtures know: the next hook is the command's own result.
  So a command the reviewer approves that runs past the 2 s grace shows
  "needs you" from 2 s until it ends, as an approved long command of
  Claude's does; so does any command whose review takes over 2 s. Nobody
  was asked. A recorded Codex session would show whether Codex sends
  something the grace could wait for.

**Requests** are numbered as they start showing (`Session.request`), from
the `firstRequest` the tracker was made with, wrapping to 1 past
2³¹ − 1 and never 0, so an app can tell one request from the next;
`randomFirstRequest()` keeps numbers from repeating across launches.
`requestRef` is the caller's own reference for the event that made it
show (`handle(_:ref:)`), and `asking` what it asks for. When one clears
with nobody answering, `clearedWhy` says why (`nothing for 10 minutes`,
`forgotten`) until the app takes it.

**An app's own view.** An app that folds its own view of the sessions
from the same events (what each turn did, say) can keep a `SessionFold`
and a `Turn` per session, as the tracker does, so the two agree on which
events count and when a turn starts and ends.

## 5. Installing and repairing hooks

**What gets written.** Every entry is one group per hook, with one
command entry. This is Claude's `Notification` and Codex's `SessionStart`,
installed with `--hook /tmp/ah.dsmm/bin/agent-hook`:

```json
{"hooks":[{"command":"\"/tmp/ah.dsmm/bin/agent-hook\" claude","timeout":5,"type":"command"}],"matcher":"permission_prompt|elicitation_dialog|idle_prompt"}
{"hooks":[{"command":"\"/tmp/ah.dsmm/bin/agent-hook\" codex","timeout":5,"type":"command"}],"matcher":"startup|resume|clear"}
```

The command is the client's full path, the agent, and the installer's
`arguments` (`--keep-text`, §2). The installer recognises its own entries
by that command: any command that runs a program called `agent-hook`, or
one of the older clients the app names (`formerClients`, a program's name
or a path's ending), which installing replaces (`isOurs`). It never
touches anyone else's.

**One set of entries.** Every app shares the same entries, and installing
replaces any `agent-hook` entry, whatever its path and arguments. So apps
that install hooks must agree on the client's path and on `--keep-text`:
otherwise each one's repair sees the other's entries as outdated and
installs its own again.

| File | What's added |
| --- | --- |
| `~/.claude/settings.json` | Under `hooks`, a group for each Claude hook in §3's table (14 hooks). `Notification`'s has the matcher `permission_prompt\|elicitation_dialog\|idle_prompt` (`Mapping.notificationTypes`), since Claude runs it only for the types its matcher lists |
| `~/.codex/hooks.json` | Under `hooks`, a group for each Codex hook in §3's table (8 hooks). `SessionStart`'s has the matcher `startup\|resume\|clear`, so a Codex session never starts as `compact` |
| `~/.codex/config.toml` | `codex_hooks = true` under `[features]`, which Codex needs to run hooks at all. Added by install, never removed, since other hooks may rely on it |

The installer takes the hooks from `Mapping`'s tables (`Mapping.claude`,
`Mapping.codex`), in their order, which installs already have. A hook
added there makes older installs outdated, so a repair adds it.

**The installer's operations** (`HookInstaller(home:hookPath:arguments:formerClients:)`):

- **Install** removes its entries, current and old, then adds a fresh
  group for each hook. For Codex it also turns hooks on in `config.toml`,
  and writes neither file if it won't edit that one. Refused while the
  client at `hookPath` is missing, while health is *unreadable*, or for
  Codex while its hooks are off in `config.toml`.
- **Remove** takes out its entries, current and old, and nothing else.
  A group left empty goes, then a hook, then `hooks`.
- **Repair** installs again for each agent whose entries are outdated, as
  an app does at launch. It never installs for an agent that has none.
- **Health**, per agent, checked in this order: *unreadable* (the file is
  there but can't be read or isn't a JSON object, or Codex's `config.toml`
  is there but can't be read; it's left alone, since only a file that
  isn't there counts as empty), *client missing* (no executable at
  `hookPath`, so the entries would drop every event without a sign), *not
  installed* (none of its entries), *hooks off* (its entries are there,
  but you turned the agent's hooks off: Claude's `"disableAllHooks":
  true`, or `hooks` or `codex_hooks` set to `false` in Codex's `features`;
  the case names the file, and repair leaves it), *installed* (its entries
  are the ones a fresh install writes: exactly one per hook, current,
  under its matcher; where a group sits and what else shares it don't
  count, since the agent runs every hook, so another tool's hook added
  after it never needs a repair) or *outdated*.
- **Detected** means the agent's folder, `~/.claude` or `~/.codex`,
  exists.
- **Preview** says what install adds, one line per hook with its matcher
  and command, and for Codex the `config.toml` switch until it's on, or
  why nothing is added.

**Where the client lives.** The entries run the `agent-hook` at
`hookPath`. The command line's default is the one built next to it (§6).
An app that ships its own copy can keep it at a stable path and copy the
new one there when it changes, so rebuilding or moving the app doesn't
break the hooks.

**Careful writes.** A config file that's a symlink (a dotfiles setup) is
written through, not replaced. JSON is written sorted and pretty-printed,
atomically. Nothing is written when nothing would change, so installing
twice is the same as once. In `config.toml`, `[features]` is found however
it's written (`[ features ] # note`, or top-level `features.x = …` keys)
and never declared twice, which Codex refuses to load. An inline
`features = {…}` without `codex_hooks = true`, or a file with both a
`[features]` table and `features.` keys, is left for you to edit, and the
preview says what to add. A `config.toml` that's there but can't be read,
or that turns the hooks off, gets nothing, and the preview says why
instead.

**Restart.** Agents read hooks at startup, so after an install, removal
or repair, open sessions need restarting.

## 6. The command line

`agent-hooks` (`Sources/AgentHooksCLI/`); `agent-hooks --help` prints its
usage. `install`, `remove`, `status` and `doctor` take `--home DIR`, the
home folder whose `~/.claude` and `~/.codex` they read and change. The
default is `$HOME`, as for the socket folder, and never
`NSHomeDirectory()` alone, which ignores `$HOME`: a run with a throwaway
`HOME` must not change the real hooks. The socket folder follows `$HOME`
or `$AGENT_HOOKS_DIR`, not `--home`.

| Command | What it does |
| --- | --- |
| `install [claude\|codex] [--keep-text] [--hook PATH]` | Installs for the agent named, or every one detected (§5). `--hook` is the client the entries run; the default is the `agent-hook` next to the `agent-hooks` executable, links followed, however it was run. Then prints each agent's health and asks you to restart open sessions |
| `remove [claude\|codex]` | Takes the entries out (§5) |
| `status [--hook PATH]` | Each agent's health (`installed`, `installed, keeping text`, `not installed`, `outdated`…, or `not found` when it isn't detected), then the sockets listening in the socket folder |
| `tail [--sessions] [--name NAME]` | Listens in the socket folder as `NAME.sock` (default `tail-<pid>`) and prints every event as a JSON line (§1). With `--sessions` it also keeps a `SessionTracker` and prints each session's state as it changes. Ctrl-C stops it and removes its socket |
| `doctor [--hook PATH]` | `status`, then a made-up `Stop` through the client to a socket of its own (`$AGENT_HOOKS_SOCKET`): the client must exit 0 and the line arrive within 2 s |

A session's line from `tail --sessions` has `session` (its key),
`state` (`working`, `idle`, `needs_you`, or `gone` once it's forgotten),
`project`, `workspace` and `name` when known, `asking` while it needs you,
and `at`. These are a permission request's, from a real run:

```json
{"agent":"claude","app":"com.mitchellh.ghostty","asking":"permission","at":1790755425280,"cwd":"/tmp/ah.fhVr/src/landing","hook":"PermissionRequest","kind":"tool","mode":"default","phase":"wait","session":"s1","tool":"Bash"}
{"asking":"permission","at":1790755425280,"project":"landing","session":"claude/s1","state":"needs_you","workspace":"fix-nav"}
```

## 7. Adding an agent

A new agent needs a mapping like §3's in `Mapping`, a way to register
hooks in `HookInstaller`, and an answer to one question: what signal
proves a person is being asked? Without a reliable one, the agent gets
activity and turns, but no "needs you". Record a session of the new
agent's hooks into the fixtures ([VERSIONS.md](Tests/AgentHooksTests/Fixtures/VERSIONS.md))
before claiming support. Claude Cowork should need only the Claude mapping
once its sandbox runs the Mac's hooks.
