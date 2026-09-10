# UX: The Mac app

The hardware is the companion. The Mac app runs quietly in the background as
its status and configuration surface. Normal use should not require opening it.

## App behavior

- Launch as a menu bar accessory: no Dock icon, startup window, or automatic
  onboarding. A first-run setup link appears when the person opens the menu.
- A static monochrome status icon has a filled variant when an agent needs you.
  No animation, XP counter, or completion celebration in the menu bar.
- Clicking opens a native transient popover anchored to the icon. Clicking again,
  outside, or pressing Escape closes it. Opening normally returns to Overview.
- State changes never open or close it, including pending approvals. Old
  interactive-mode preferences are ignored. Previously opted-in approval
  notifications remain available; selecting one opens the dropdown.
- Activity, Settings, profile, and setup are reached inside the same dropdown,
  with Back navigation. Secondary confirmation and utility sheets remain attached.
- No creature or animated face in ordinary app content or setup. Share cards
  may retain the likeness. The physical device owns Buddy's expression.

## Overview

One column, 360 pt wide, with system typography, semantic colors, native controls,
subtle dividers, and whitespace. No sidebar or top-level tab strip.

1. Buddy name and level.
2. Current state and a short explanation: Working, Idle, Sleeping, Needs you,
   Done, or Needs attention. Device connection is independent of agent state.
3. Pending requests appear only on Overview, below its status. Settings, Activity
   and setup display only their own content, even while an approval is waiting.
   Show the tool,
   supplied reason (or tool name), stakes, queue position, and Approve/Deny for actionable requests. The
   first decision from either surface wins. Passive requests have no fake buttons.
4. Within-level XP progress, total XP, and remaining XP. A compact row shows
   today's XP, lifetime completed tasks, and current streak. The task count is
   explicitly labeled as lifetime until a reliable daily count is exposed.
5. All sessions appear inline with agent, project when known, and status. The
   dropdown grows to accommodate up to ten sessions, within the screen height.
   Additional sessions remain in the same scrollable overview; no expansion
   button or sessions navigation is required. Empty state: No agents awake.
6. Device connection and battery percentage when connected and known. Missing
   battery is omitted; never substitute a made-up percentage.
7. Activity and Settings links, plus a small menu containing Quit.

Overview retains progress and statistics while idle or sleeping. It uses a
450 pt base viewport (590 pt with a pending request), growing by 42 pt per
additional session beyond three, up to ten and bounded by available screen height;
secondary panes use 560 pt.
Long content scrolls inside the dropdown.

## Activity and Settings

Activity contains all sessions, lifetime tasks, days together, current and best
streak, daily/source XP history, and secondary
local share-card export. Missing history is an honest empty/error state.

Settings is one continuous scrollable form. Every group is expanded and visible
in the same view; there is no category picker, sidebar, or extra profile page.
Simple headings separate:

- Buddy & sound: name, language, and Quiet mode.
- Device: connection, pairing, and firmware.
- Agents: installation status, connect and repair actions.
- General: launch at login.
- What your buddy knows: inspect and clear stored profile lines inline; “Edit buddy behavior…” opens the Markdown guide for dialogue, memory and personality.
- Approvals: “Approve through Buddy”, off by default, plus the separate Codex opt-in.
- Support: Report a bug saves a diagnostic file for sharing with support.
- About: version, Check for updates, and Help & support.

Written dialogue is automatic, with a neutral greeting/error fallback and
otherwise silence when the local model is unavailable. There is no Voice picker. Sound uses fixed volume step 1; Quiet
mode is the only sound control. Appearance is fixed to the default skin,
no accessory, and default silhouette. Old saved choices remain stored but are
inactive. Quick command, Reset, and Retire buddy are removed from Settings;
no existing progress is erased. Ordinary action buttons use plain styling to
avoid dark filled rectangles within the form.

## Quiet mode

Quiet mode turns off **all sounds and beeps**, with no high-stakes exceptions.
Animations, expressions, visual approval reminders, nudge timing, state changes,
XP, and agent behavior remain identical. It neither approves nor denies requests.

The setting lives in Buddy & sound, labeled "Quiet mode", with the description
"Turn off Buddy’s sounds. Screen behavior stays the same." Turning it off restores
the fixed default volume (step 1). The physical button's former Focus gesture controls the same
setting. No Focus hours or scheduled behavior remain; old schedule values are
ignored. The existing sounds-enabled preference is retained so existing mute
choices survive upgrades and restarts. Wire names remain compatible; see WIRE-V2.

English and Korean copy are supported. Review both system appearances.

## Approvals and reminders

Native editor/agent approval is the default. Explicit Buddy interception can
replace the native dialog, requiring the decision through Buddy. Codex also
requires its separate opt-in; existing explicit choices remain. Disabling
interception releases held requests to the native flow. Server-side checks
protect this even when an old hook still asks to intercept.

“Snooze reminder” suppresses nudges for that request without deciding it.
The next request starts fresh. Stakes inspect the command; card copy uses the
supplied reason, or the tool name when absent.

Firmware check errors read “Check unavailable”; the sheet shows the underlying
error and offers Try again. This is separate from an installation failure.
