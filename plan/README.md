# Boop spec

Updated 2026-09-30. The index of Boop v1's specs. They're the contract the
code implements, so a change to one goes in the same commit as the code
([CLAUDE.md](../CLAUDE.md) says which spec goes with which code). Start
with the vision.

| Read | For |
| --- | --- |
| [VISION.md](VISION.md) | Why Boop exists, its personality, the promises, and what's in v1 |
| [BEHAVIORS.md](BEHAVIORS.md) | What Boop does when things happen, with its sound and light, and how each personality changes it |
| [VOICE.md](VOICE.md) | What Boop says: the recorded takes, how one is picked and played |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The parts and their boundaries, the data flow, queues and timers, what Boop keeps on disk, budgets, and the decisions in force |
| [ADAPTERS.md](ADAPTERS.md) | How Boop uses agent-hooks: the raw event each hook becomes, Boop's socket, what it adds to the session rules, and when it installs the hooks |
| [../agent-hooks/SPEC.md](../agent-hooks/SPEC.md) | agent-hooks, the hook layer as a package of its own: the hook client, the event each hook becomes, session states and "needs you", installing the hooks, and its command line |
| [kit/BRAIN-KIT.md](kit/BRAIN-KIT.md) | The brain kit Boop's harness runs on, generic and open-sourceable: events and the log, inputs and their lines, rules, outputs, the prompt, the loop, and how Boop sits on top |
| [harness/HARNESS.md](harness/HARNESS.md) | The harness: how a view event becomes a question for Jev and an answer becomes an action; the transcript and the state |
| [harness/EVENTS.md](harness/EVENTS.md) | What goes in the transcript: raw events, their seven types and their data; and the view over it: view events, their facts and lines, what's kept, and which wake the brain |
| [harness/DECISIONS.md](harness/DECISIONS.md) | What Boop decides: the steering files, the questions, how answers are read, and the actions |
| [harness/EXAMPLE.md](harness/EXAMPLE.md) | One turn of failing tests end to end, from a real eval run: events, transcript, state, Jev's answers and what Boop does |
| [steering/](steering/guide.md) | The guide, personalities and moods Jev reads, read-only and bundled in the app ([harness/DECISIONS.md](harness/DECISIONS.md) §2) |
| [PROTOCOL.md](PROTOCOL.md) | The messages between the Mac and the device, over Bluetooth or USB, and the debug messages over USB |
| [DEVICE.md](DEVICE.md) | The board, pins, firmware stack, what the device keeps, and building and flashing |
| [VERIFICATION.md](VERIFICATION.md) | How everything is checked (L0–L6), and every tool |
| [EVALS.md](EVALS.md) | The harness eval scenarios: how they run and what each checks |

What each check found is in [evidence/](evidence/), one folder per piece
of work. History is in git: the finished v1 build plan and its full
decision log (`archived/plan-v1-build/`) and the previous generation's
specs (`archived/plan-gen2/`) are at tag `archived-final`.

The device's designs and sounds come from the
[animation bank](../internal/boop-design/README.md) ([DEVICE.md](DEVICE.md)
§6, [VOICE.md](VOICE.md) §10); its mood-graph handover is design material
for the Mac's Mood action.
