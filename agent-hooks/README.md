# agent-hooks

What your coding agents are doing, from their hooks. agent-hooks installs
hooks into Claude Code and Codex on macOS, turns every hook into one kind
of event, and keeps track of each session: working, idle, or waiting on
you ("needs you"). Apps get a Swift library and a small socket protocol,
and people get a command line.

It only watches. Hooks report and exit; nothing here can approve, deny or
block anything an agent does, and if nothing is listening the hook gives
up in milliseconds.

It's for anything that wants to show agents' work without reading their
transcripts: a menu-bar app, a desk gadget, a status line, a notification
when an agent needs you. It was pulled out of Boop, a desk creature
that watches your agents, and Boop uses it.

[SPEC.md](SPEC.md) says exactly what it does; this page is the overview.

## Install

It builds from source with Swift 6 (Xcode or the Command Line Tools) on
macOS 13 or later:

```sh
cd agent-hooks
swift build -c release
mkdir -p ~/.local/bin && cp .build/release/agent-hooks .build/release/agent-hook ~/.local/bin/
~/.local/bin/agent-hooks install            # or: install claude, install --keep-text
```

`install` adds an entry that runs the `agent-hook` next to `agent-hooks`
(here `~/.local/bin/agent-hook`) to every hook agent-hooks uses, in
`~/.claude/settings.json` and `~/.codex/hooks.json` (and turns Codex's
hooks on in `~/.codex/config.toml`), and never touches anyone else's
hooks. Copy the two somewhere stable first, as above: the entries keep
the client's path, and cleaning the build folder would take its copy
away. `--hook PATH` names another client. Restart open agent sessions:
they read their hooks when they start. `agent-hooks remove` takes the
entries out again.

Then, with `~/.local/bin` on your `PATH`, watch with
`agent-hooks tail --sessions`. It prints each event as a
JSON line, and with `--sessions` each session's state as it changes. This
is Claude asking to run the tests, from a real run:

```json
{"agent":"claude","app":"com.mitchellh.ghostty","at":1790755424947,"cwd":"/tmp/ah.fhVr/src/landing","hook":"PreToolUse","kind":"tool","mode":"default","phase":"start","session":"s1","tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}
{"agent":"claude","app":"com.mitchellh.ghostty","asking":"permission","at":1790755425280,"cwd":"/tmp/ah.fhVr/src/landing","hook":"PermissionRequest","kind":"tool","mode":"default","phase":"wait","session":"s1","tool":"Bash"}
{"asking":"permission","at":1790755425280,"project":"landing","session":"claude/s1","state":"needs_you","workspace":"fix-nav"}
```

## Events

Every hook becomes an event with a **kind** and a **phase**, the hook's own
name, the session, the time and the few facts that hook carries:

| Kind | `start` | `wait` | `end` |
| --- | --- | --- | --- |
| `session` | `SessionStart`: `source` (`startup`, `resume`, `clear`, `compact`) | | `SessionEnd` |
| `turn` | `UserPromptSubmit`: `prompt`, with `--keep-text` | | Claude: `Stop` (`outcome: done`, `message` with `--keep-text`), `StopFailure` (`failed`, `error`), an interrupted call or `idle_prompt` (`stopped`). Codex: `Stop`, `Interrupt` (`stopped`) |
| `tool` | `PreToolUse`: `tool`, `tool_use_id`, `topic` | `PermissionRequest`, Claude's `Elicitation` and its `Notification`s: `tool`, `asking` (`permission` or `input`) | `PostToolUse`, Claude's `PostToolUseFailure` (`failed`, `error`) and `ElicitationResult` |
| `subagent` | Claude's `SubagentStart` | | Claude's `SubagentStop` |

Every event can also have `cwd`, the thread's `name` as the agent's app
shows it, the `app` the agent runs in, and Claude's permission `mode` and
`subagent`. `topic` says what a command is about without the command:
`tests`, `build`, `deploy`, `docs` or `inspect` (it only reads).
[SPEC.md](SPEC.md) §3 has every hook and field.

## Sessions and "needs you"

`SessionTracker` folds the events into sessions. Each is working, idle or
needs you, with its project and workspace (from the folder's git
repository, branch or worktree), its running tool calls and its
subagents. "Needs you" is the part that has to be right every time, and
the fiddly one: a `Notification` repeats a request its own hook makes;
subagents ask alongside their parent; Codex asks before its automatic
reviewer may approve, so its requests wait 2 s before they show; hooks
land after their session ended; and nothing at all reports that you
approved or pressed Esc, so the next event has to say. A session silent
for 10 minutes stops needing you. [SPEC.md](SPEC.md) §4 has every rule.

## How apps listen

The client, `agent-hook`, sends each hook as one JSON line to every
`*.sock` in `~/.agent-hooks/sockets/` (`$AGENT_HOOKS_DIR/sockets/` when
that's set), then exits 0. An app listens on a Unix socket of its own and
lists it there once, as a link. Any number of apps hear the same hooks,
with nothing else running. Set `$AGENT_HOOKS_SOCKET` to send to one socket
only, for tests.

**Keeping text.** By default no words of yours or the agent's leave the
client, but the thread's name. Install with `--keep-text` and your prompt
and the agent's last message come too, up to 2,000 characters each. Tool
input and output, error text, file contents and transcripts never do.

**Your own commands.** `~/.agent-hooks/topics.json` adds command shapes
to the `tests`, `build` and `deploy` topics:

```json
{"tests": [["just", "check"]], "build": [["./build.sh"]]}
```

## The command line

| Command | What it does |
| --- | --- |
| `agent-hooks install [claude\|codex] [--keep-text] [--hook PATH]` | Adds the hooks for the agent named, or every one found |
| `agent-hooks remove [claude\|codex]` | Takes them out, and nothing else |
| `agent-hooks status` | Each agent's hooks, and the apps listening |
| `agent-hooks tail [--sessions] [--name NAME]` | Prints every event, and with `--sessions` each session's state as it changes |
| `agent-hooks doctor` | `status`, then a made-up hook through the client, to check it works |

`--home DIR` points `install`, `remove`, `status` and `doctor` at another
home folder (the default is `$HOME`). [Examples/needs-you-notify.sh](Examples/needs-you-notify.sh)
turns `tail --sessions` into a macOS notification each time an agent
needs you.

## The library

```swift
// Package.swift
.package(path: "../agent-hooks"),
// and in a target's dependencies:
.product(name: "AgentHooks", package: "agent-hooks"),
```

`HookServer` listens on a socket, `Mapping.event(from:)` turns each line
into an `AgentEvent`, and a `SessionTracker` keeps the sessions. This
prints each time an agent starts waiting on you:

```swift
import AgentHooks
import Foundation

/// Prints each time an agent session starts waiting on you.
final class Watcher: @unchecked Sendable {
    let queue = DispatchQueue(label: "watcher")  // the tracker's one queue
    let tracker = SessionTracker()
    var waiting: Set<String> = []
    var keep: [Any] = []

    func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func start(socket: String) throws {
        let server = HookServer(path: socket) { [self] line in
            queue.async { [self] in
                guard let event = Mapping.event(from: line, receivedAt: now()) else { return }
                tracker.handle(event)
                report()
            }
        }
        try server.start()
        try HookSocket.register(socket, as: "needs-you")  // agent-hook now sends here too
        // The timers: Codex's 2 s grace, the 10-minute safety net.
        let tick = DispatchSource.makeTimerSource(queue: queue)
        tick.schedule(deadline: .now() + 1, repeating: 1)
        tick.setEventHandler { [self] in
            tracker.advance(to: now())
            report()
        }
        tick.resume()
        keep = [server, tick]
    }

    func report() {
        let asking = tracker.grouped(at: now()).waiting
        for s in asking where !waiting.contains(s.key) {
            let what = s.asking == .input ? "has a question" : "wants permission"
            print("\(s.agent.displayName) in \(s.name ?? s.project) \(what)")
        }
        waiting = Set(asking.map(\.key))
    }
}

let watcher = Watcher()
try watcher.start(socket: NSTemporaryDirectory() + "needs-you.sock")
dispatchMain()
```

The library also installs hooks (`HookInstaller`, for an app's own setup
screen), names a folder's project and workspace (`Place`, `Places`), and
opens a thread in its app (`ThreadLink`).

## Caveats

- **Undocumented internals.** Some of what agent-hooks reports comes from
  the agents' and apps' internals, not their hook contracts, so an update
  can break it: the thread's name (Claude's title records in its
  transcript, Codex's `session_index.jsonl`), which app the agent runs in
  and the Claude app's session ID (environment variables the apps set),
  and what Claude's `idle_prompt` notification means. When one breaks,
  the name is missing or the thread doesn't open; the events still come.
- **What hooks can't see.** No hook says you approved, so a long command
  you approved keeps "needs you" up until it finishes. Codex's automatic
  reviewer sends no hook either, so a command it approves that runs past
  the 2 s grace shows "needs you" when nobody was asked. SPEC.md §4 lists
  these.
- **One set of entries.** Every app shares the same hook entries, so apps
  that install hooks must agree on the client's path and on
  `--keep-text`, or each undoes the other's at its next repair.
- **Tested agents.** Recorded against Claude Code 2.1.263 and Codex CLI
  0.153.4 ([the fixtures](Tests/AgentHooksTests/Fixtures/VERSIONS.md)).
  macOS only.

## Development

```sh
swift test --scratch-path .build/tests
```

The tests use Swift Testing, and the hook fixtures are in
`Tests/AgentHooksTests/Fixtures/`. The package depends on nothing but
Foundation, and on nothing outside this folder.
