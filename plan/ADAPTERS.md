# Boop: agent adapters

Updated 2026-09-30. How Boop hears from Claude Code and Codex. The hook
layer is its own package, [agent-hooks](../agent-hooks/README.md), and
its [SPEC.md](../agent-hooks/SPEC.md) is the contract for the hook
client, the event each hook becomes, sessions and "needs you", and
installing the hooks. This file says how Boop uses it: the raw event it
records, its socket, what it adds to the session rules, and when it
installs. Each section matches the SPEC's of the same number. Code:
`app/BoopKit/Adapters/Adapter.swift`, the hook setup in
`app/Boop/MenuBarApp.swift`, and the session table in
`app/BoopKit/Core/Core.swift`.

## 1. The job

agent-hooks turns one agent's hook calls into `AgentEvent`s and keeps the
session table (`SessionTracker`); Boop turns each event into its raw event
and never sees a hook payload. Hooks only report, so Boop can't approve,
deny or block anything (SPEC.md §1).

### The raw event

Every agent event becomes the transcript's shape, which is the brain
kit's event ([harness/EVENTS.md](harness/EVENTS.md) §2), `Event(AgentEvent)`:
`seq`, `at`, the agent as `source`, the kind and phase together as `kind`
(`tool_start`), and in `data` the hook's name as `specific_type`, and
`session`, `subagent` and `cwd`. The event's facts go in `data` under the
same names, except that `asking` is `for` and `subagent_type` is
`agent_type`. This is a `PreToolUse` that runs tests, once the transcript
has given it its `seq` (`AdapterTests.testEventJSONShape`):

```json
{"seq":102,"at":1790000000123,"source":"claude","kind":"tool_start","data":{"cwd":"/Users/me/src/landing","session":"a1b2","specific_type":"PreToolUse","tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}}
```

The generic type and phase, in `kind`, are what the core and the view
read; `data.specific_type` keeps the hook's own name, so the transcript
can be read again if the mapping changes. `at` is when the app received it, on its
steady clock ([ARCHITECTURE.md](ARCHITECTURE.md) §3.2, "Clocks");
`boopdev replay` uses the hook line's own `ts`. The project and workspace
aren't sent: the core and the view work them out from `cwd` (§3). The
core and the view read a recorded event back as agent-hooks has it,
`AgentEvent(Event)`, to fold the sessions (§4).

## 2. The hook client and the socket

Boop's hook entries run agent-hooks' client with `--keep-text`:
`bin/agent-hook claude --keep-text`. Your prompt and the agent's last
message are the only agent words the brain hears
([harness/EVENTS.md](harness/EVENTS.md) §8–9), and the thread's name is what
the needs-you sign, the popover and a finish call it (SPEC.md §2). The
app a hook reports is where a tap opens the thread
([BEHAVIORS.md](BEHAVIORS.md) §3.2).

**Boop's socket** is `boop.sock` in its state directory,
`~/Library/Application Support/Boop/` for the everyday app
([ARCHITECTURE.md](ARCHITECTURE.md) §4.4). At each launch, the everyday
menu-bar app lists it in agent-hooks' socket folder as a link,
`~/.agent-hooks/sockets/boop.sock` (`HookSocket.register`), so
`agent-hook` sends to it along with any other app listening. Nothing else
lists a socket: `Boop --headless` and the tests take hooks sent straight
to theirs with `$AGENT_HOOKS_SOCKET`.

**The app's end** is agent-hooks' `HookServer` on `boop.sock`, which
hands each hook line to the runtime. A line that isn't a hook line is a
dev line (`{"dev":…}`), taken only headless or in debug mode and dropped
otherwise.

## 3. Event mapping

Which hook becomes which kind and phase, with what facts, is SPEC.md §3;
the transcript's `data` for each type is
[harness/EVENTS.md](harness/EVENTS.md) §2. Boop reads a few of the facts
for the look ([BEHAVIORS.md](BEHAVIORS.md) §2): a call's `topic` (tests
running shows `testing`, a command that only looks at files, `inspect`,
shows as analyzing), Claude's plan mode (`mode: plan`) as planning, and a
`subagent` start as a helper at work. What makes a turn fail, and so its
one-shot, is [BEHAVIORS.md](BEHAVIORS.md) §3.1.

**Project and workspace** are agent-hooks' `Place` (SPEC.md §3), which
the core reads through its `Places` cache. The workspace names a thread
when its app gives it no name, and tells two threads in one project
apart.

## 4. Sessions and "needs you"

The core keeps agent-hooks' `SessionTracker` and reads every session from
it: working, idle or needs you, with its turn, running calls and helpers,
and who is asking. Its rules and timers, the Codex grace and the safety
net among them, are SPEC.md §4, and the core's one-second tick runs them
(`advance`). Which session the device shows is
[BEHAVIORS.md](BEHAVIORS.md) §2–3. The view folds the same events with
agent-hooks' `SessionFold` and `Turn`, so the brain's turns and the
core's sessions agree ([harness/EVENTS.md](harness/EVENTS.md) §4).

What Boop adds to what the tracker says:

- **"Needs you" is recorded.** When a Claude request starts showing, and
  when a Codex one does after its grace, the core records a `needs_you`
  action, which the view keeps as the request's `tool` wait, never waking
  the brain ([harness/EVENTS.md](harness/EVENTS.md) §2, §4). When it
  clears, the core records the action's end, with why when nobody
  answered (`clearedWhy`). A Codex request the reviewer handled within
  its grace never showed, so nothing is recorded for it. What you see and
  hear is [BEHAVIORS.md](BEHAVIORS.md) §3.2.
- **One-shots.** A session starting, a prompt, a failed command and a
  stopped turn play the rules' one-shots
  ([BEHAVIORS.md](BEHAVIORS.md) §3.1). A stopped turn plays `stopped`
  only when it ended a turn that was open, so Claude's idle notice after
  a finished turn plays nothing; a call's result that landed late still
  counts for the thread ([harness/EVENTS.md](harness/EVENTS.md) §4) but
  plays nothing.
- **Request numbers** start somewhere random each launch
  (`Core.randomFirstAsk`), so the device's `attn.id` never repeats one it
  still shows from the last launch ([PROTOCOL.md](PROTOCOL.md) §3).
- **A launch** folds the sessions again from the transcript it reads back
  ([ARCHITECTURE.md](ARCHITECTURE.md) §6).

## 5. Installing and repairing hooks

Boop installs with agent-hooks' `HookInstaller` (SPEC.md §5), made by
`HookInstaller.boop`: its entries run `bin/agent-hook` in the state
directory with `--keep-text`, and it counts as its own, and replaces, the
entries Boop wrote before agent-hooks, which ran `boop-hook` (and before
that `~/.boop/boop-hook.sh`). So the first launch after the change finds
the old entries outdated and repairs them. Settings shows each agent's
health as a row with its button, offering only Remove while you have the
agent's hooks turned off, and an agent that isn't detected as not found.

**When they run.** Only the everyday Boop, the menu-bar app on
`~/Library/Application Support/Boop`, changes hooks, since its socket is
the one listed (§2).

| When | What happens |
| --- | --- |
| Launch | The app copies the `agent-hook` built next to it to `bin/agent-hook` if they differ (staged as `bin/agent-hook.new`, then swapped in), so rebuilding or moving the app doesn't break hooks. With none next to it, it keeps the copy in place. It lists `boop.sock` (§2), then repairs, and asks you to restart open agent sessions if anything changed |
| Setup | A switch for each agent, on for each one detected, with a preview of what install adds: each hook's command and, for Codex, the `config.toml` switch until it's on. Finishing setup installs for each switched-on, detected agent, and the Overview shows any that failed ([ARCHITECTURE.md](ARCHITECTURE.md) §8) |
| Settings | One click to connect, repair or remove each agent. A change that works asks you to restart open sessions; one that fails says why |
| Another `--state-dir` | The menu-bar app installs, repairs and removes nothing, at setup or later ("only the everyday Boop changes them"), and logs why. It still reads the real hooks, so Settings shows how they stand. `Boop --headless` never touches hooks |

`boopdev hooks status|install|remove --home DIR` runs Boop's installer
against another home folder, for tests ([VERIFICATION.md](VERIFICATION.md)
§2). agent-hooks' own `agent-hooks` command line works on the same
entries, but without `--keep-text` its install makes Boop's look outdated,
and Boop's next launch installs its own again (SPEC.md §5, "One set of
entries").

## 6. Checking it works

The `doctor` skill (`internal/skills/doctor/doctor.sh`) checks four things:

1. Hooks are registered for each agent and call an `agent-hook` that
   exists (Boop's installer's own health check, through `boopdev hooks`).
2. The app is running, its socket accepts, and it's listed in
   agent-hooks' socket folder (§2).
3. A synthetic event from `agent-hook` reaches the app (seen in its log).
4. With `--confirm`, a harmless command run in the agent
   (`echo BOOP_DOCTOR_PING`) shows up in Boop as a hook from this agent.

`--headless` runs checks 1–3 against a throwaway headless app, which
isn't listed. The app logs hooks only while the doctor has armed it, by
writing `doctor-armed` into the state directory, or in debug mode
(`--debug`, [harness/HARNESS.md](harness/HARNESS.md) §9), which also logs
the event each hook became. `--confirm` removes the arm. An arm lasts 10
minutes: the app removes an older one at the next hook, so a doctor run
that never confirms doesn't leave every hook logged for good.

## 7. Adding an agent

A new agent goes into agent-hooks (SPEC.md §7). Boop needs nothing more
than a `source` for it in the transcript's `Event.Source`.
