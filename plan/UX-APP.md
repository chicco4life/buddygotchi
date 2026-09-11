# UX: Mac app

The Mac app is Boop's status and settings surface. The physical ESP32 owns the
animated face. Shared state, timing, XP and model triggers are in
[How Boop behaves](BEHAVIORS.md).

## Opening and navigation

| Action or event | Behavior |
| --- | --- |
| Launch | Menu bar accessory; no Dock icon, startup window or automatic onboarding |
| Click menu icon | Open a transient popover, normally on Overview |
| Click again/outside or press Escape | Close the popover |
| Agent changes state or needs attention | Update status without opening, closing or navigating the popover |
| Open Settings or setup | Navigate inside the same popover; Back returns to Overview |
| Select a previously enabled passive notification | Open the popover |
| First run | Show a setup link when the person opens the menu |

The menu icon is static and monochrome, with a filled variant for Needs you.
There is no menu-bar XP counter or celebration. Ordinary views and setup do not
show an animated creature. Utility/confirmation sheets stay attached to the popover.

Setup has five steps: welcome, connect agents (skippable), pair the device (or add it later),
name the buddy, and finish with optional launch-at-login and notifications. The
name is locked once chosen. Hook repair preserves unrelated editor hooks.
Opted-in, OS-authorized attention notifications are passive silent banners;
selecting one opens Boop, and clearing its request removes the delivered banner.

## Overview, top to bottom

| Area | Content and behavior |
| --- | --- |
| Buddy | Name, with no level label |
| Status | Current state, optional whole-desk phrase, factual explanation |
| Attention/error | Reported request or error details. Requests show tool/reason, queue position and “Check your editor”; Snooze suppresses reminders only |
| Sessions | Every session: agent, known project and status. Waiting first, then errors, working, idle. Empty state: “No agents awake” |
| Device | Actual connection; battery percentage only when connected and known |
| Progress | Cumulative XP, completed turns and current streak; twelve-week daily turn grid with exact counts on hover |
| Footer | Settings on the left; Quit on the right |

Pending requests appear only on Overview and never cover Settings or setup.
There are no approve/deny controls. Scope wraps below the state title, hides for
a pending request and clears when obsolete or unavailable. Model text is optional;
factual sessions and progress remain available without it.

The 360 pt column grows through ten session rows within the available screen
height, then scrolls. All sessions and progress stay reachable, including on a
small screen. Status and progress remain visible while idle or sleeping.
There is no Activity pane, overflow menu or share export.

## Settings

One scrollable form, with all groups expanded:

| Group | Controls |
| --- | --- |
| Buddy & sound | Saved name (read-only), English/Korean interface language, Quiet mode |
| Device | Connection, pairing and firmware |
| Agents | Hook installation status, connect and repair |
| General | Launch at login |
| What your buddy knows | Inspect/clear profile lines; Edit buddy behavior… opens the local Markdown guide |
| Support | Report a bug saves a diagnostic file for the person to share |
| About | Version, app update check, Help & support |

Quiet mode mutes every authored sound. Visuals, reminders, state, XP and agent
behavior stay the same. The device's one-second secondary hold controls the same
setting, which persists across restart. There are no scheduled hours or volume
slider; normal volume is fixed at step 1. The supported ESP32 board has no speaker.

Companion text stays English when the interface language changes. The model may
stay silent; failed responses do not insert stock greetings or error messages.
There is no Voice picker. Appearance is fixed; saved old cosmetic choices are
inactive. Quick command, Reset and Retire are not exposed; existing progress is preserved.

## Pairing and firmware updates

Use Device settings to pair the board and inspect its connection/version. Device
connection is independent of whether coding agents are active.

| Update outcome | What the app reports |
| --- | --- |
| Manifest check succeeds | Available update or confirmed up-to-date result |
| Manifest check fails | “Check unavailable,” underlying error and Try again |
| Firmware transfer/installation fails | Recoverable installation failure; a known offered update stays retryable |
| Transfer commits and device restarts | Wait for the device to report the expected version |
| Expected version arrives | Installation succeeded |
| Old version or no confirmation within 45 seconds of commit | Recoverable failure; no unverified success claim |

Reconnect triggers another version check after an update failure. Stale check
results cannot overwrite a newer operation. The update sheet follows the current
appearance. Actual public OTA remains an open gate; see [status](PLAN.md).

## Visual and layout rules

Warm paper/ink in both appearances, terracotta for actions, amber for attention,
sage for completion/progress, rose for affection. Semantic text colours meet
4.5:1 against their own background; faint tones are decorative/disabled only.
The device uses the same meanings on a black field.

Section labels and spacing separate cards. Session status uses a leading colour
bar, and the status dot breathes only while work is live. Battery has a small
pip, amber below 25%. Native controls and plain form buttons keep the small view clear.

Layout and screenshot harness share one calculation: Overview base 548 pt,
692 pt with a request, plus 46 pt per additional session through ten; secondary
panes use 560 pt. All are clamped to available screen height and scroll as needed.
Theme constants live in [BuddyTheme.swift](../app/Boop/Theme/BuddyTheme.swift).

Firmware update failures report the HTTP status when the server rejects a
manifest or binary request. Changing a manifest source cannot reuse another
source's cached release. Download errors remain retryable; a successful package
check alone does not indicate an installed update.

Firmware update copy does not promise a fixed duration: the upload screen shows
an estimate based on transfer progress. Keep the device powered and near the Mac
until its automatic restart and version confirmation complete.
