# A5: Mac app look and flow (2026-09-26)

The owner asked for a pass on the Mac app: simple, but nice, elegant and
cute. Setup was a jarring window, the overview showed the board's id
(`b00p-54fe`) and held the volume, focus and away controls, settings was a
separate window, and gen-2's styling and flow were better. The spec is
[UX.md](../../UX.md) §6–7; the decision is in
[ARCHITECTURE.md](../../ARCHITECTURE.md) §11.

## What changed

- Setup and settings open inside the popover. Setup is four steps (hello,
  name and nature, agents, wake up) and opens the popover once on first
  launch; closing it keeps your place.
- The overview only shows. Volume, focus and "I'm away" are in Settings;
  small reminders appear only when a mode is on. The header says whether
  the body is connected, never which board it is.
- Gen-2's "Boop Cream" palette and building blocks, a small copy of the
  device's face (header and setup), and Boop's eyes as the menu-bar icon.
- `Boop --snapshots DIR` renders the panes and icons from fixtures.

## Checks that ran

| Check | Result |
| --- | --- |
| `make build` (`swift build`, all products) | Passed |
| `make test` | 166 passed, 0 skipped |
| `app/.build/debug/Boop --snapshots plan/evidence/2026-09-26-mac-app-ui` | 22 PNGs, all opened and checked against UX.md §7 in light and dark: nothing clipped, no board id, readable text |

Found and fixed on the way, from the snapshots: the header line truncated
next to the connection pill (shortened), the pill was squeezed (fixed
size), and an exact capsule outline drew straight edges offscreen (the
pill uses a rounded rectangle).

## The pictures

| File | Shows |
| --- | --- |
| `overview-asleep-*` | No sessions: sleeping face, "Napping", the empty card |
| `overview-working-*` | Four sessions grouped by agent, three working |
| `overview-needs-you-*` | Two waiting: amber rim, needs-you card with "+1 more", Focus and Quiet reminders |
| `overview-offline-*` | Body not connected, Muted and Away reminders, the restart notice |
| `overview-not-running-*` | Why Boop couldn't start |
| `settings-*` | The whole settings pane, uncapped |
| `setup-1…4-*` | The four setup steps |
| `menubar-*` | The icon asleep, idle, working and needing you, at 4× |

## Not checked here

The app in the real menu bar (opening, the popover's resizing, typing the
name, the switches' accent colour when the popover is key) needs the
owner, because an agent can't launch the app with Bluetooth. That's
morning checklist rows 5 and 7 ([PLAN.md](../../PLAN.md) §6).
