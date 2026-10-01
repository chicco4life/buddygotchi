# Mac app look, before and after (2026-09-27)

The overnight polish of the popover and the menu-bar icon
([UX.md](../../../UX.md) §7). Every picture comes from
`app/.build/debug/Boop --snapshots DIR`: "before" is the code at `dc9eb69`
(the old look with the new edge-state fixtures), "after" is the end of the
`ovn/mac` branch. Snapshots are 2x; the overview, settings and setup sheets
are scaled to 1x to keep them small.

| File | What it shows |
| --- | --- |
| `icons.png` | The five menu-bar icons (asleep, idle, working, needs you, listening), top row at 1x and bottom at 2x with each pixel magnified, on a light and a dark bar. Before: fractional panes smear at 1x and go soft at 2x, and needs-you amber is 1.7:1 on the light bar. After: whole points, and a deeper amber (3.5:1) on light |
| `faces.png` | The header's 46 pt face tile at 2x, blown up 3x: working, needs you (dark), idle. Before: a grey two-pixel cross and a three-row smeared mouth. After: one-pixel blocks on the device's grid, its looks and bar mouths |
| `overview.png` | Needs you (light) and every mode chip at once (dark). Warm Terminal colours, a fixed Claude Code then Codex order, chips on their own row, plain device status, equal Talk and Send |
| `settings.png` | Normal without a key and the body away, and the usual Settings (dark). Black-glass filled buttons (oat on dark paper, as in `setup.png`), no dead Connect, one "no key" line, the key only in Normal, the theme's mode picker, versions in the footer |
| `setup.png` | The name step (light) and the last step (dark). The 88 pt face on whole-point blocks, the filled button in black glass (oat on dark), Back lined up with the column |

Checks that ran: `make build`, and `make test` (210 passed) after every
commit, and the snapshot run's contrast check ("contrast: 62 pairs pass").
Not checked here: the real popover in the menu bar (NSPopover's own arrow
and rim, the switches' active colours), which needs the owner's `make run`
([PLAN.md](../../../PLAN.md) §7).
