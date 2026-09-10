# Hook review

## Current policy — native approvals only

Owner decision, 2026-09-11: Buddy interception is removed. Hook v9 does not
register PermissionRequest interception and ignores stale registrations after
draining stdin. The server's compatibility `/hook/approve` route always returns
native passthrough, regardless of old settings. No auto-approval or command
classification runs; the engine holds no approval continuations. Repair removes
only Boop entries and preserves unrelated hooks. Config loading drops old
approval enablement keys. Runtime permission events cannot create approval cards.

Claude passive attention notifications and Elicitation can show Needs you when
reliably reported. Tool-use and Cursor execution gates report activity. Native
Codex approval waiting cannot reliably be mirrored through these hooks.

Verify native editor flows against the owner-launched app before release. Old
review notes below describe the removed implementation, not the current policy.

---

## Hook integration review — 2026-09-10

The reported repeated “Bash / runs a command” cards have two distinct causes.
The global approval switch routed every Codex PermissionRequest through Boop's
held approval connection. That hook precedes the normal approval flow; it does
not prove that Codex's automatic reviewer needs the owner. Separately, the
rendered card replaced an available description with a generic gloss.

## Contract review

- Codex: PermissionRequest runs on an approval request, not every command.
  Empty successful output defers to native approval. The payload supplies a
  canonical tool name, command and sometimes a description. SessionEnd is now
  documented and was missing from our registration. Sources:
  [OpenAI hook reference](https://learn.chatgpt.com/docs/hooks).
- Claude Code: PreToolUse is activity regardless of permission status;
  PermissionRequest is the approval boundary. Existing registrations keep these
  separate. Duplicate permission notifications remain ignored. Source:
  [Claude Code hook reference](https://code.claude.com/docs/en/hooks).
- Cursor: beforeShellExecution and beforeMCPExecution are execution gates, not
  proof of a pending human decision. The generated script treats them as
  nonblocking activity. Source: [Cursor hooks](https://prod.cursor.com/docs/hooks).
  No user Cursor hook registration exists on the inspected machine.

The docs establish the hook contracts, but do not establish the precise ordering
of this desktop build's automatic reviewer. The design therefore avoids inferring
human waiting from a Codex request. This preserves native review, including any
later decision that actually requires the owner.

## Changes

1. Hook v8 requires separate `codexApprovalMode` opt-in plus global approval mode
   before intercepting Codex PermissionRequest. The default exits successfully
   without creating a waiting card or granting permission. Activity still flows.
   Advanced settings exposes this preference; disabling it releases held Codex
   approvals with passthrough. Existing Claude approval behavior is unchanged.
2. Approval reasons become transient card glosses when present. Stakes and
   conservative auto-approval inspect the actual command, not the description.
3. Output capping preserves event/input aliases, error classes and tool-call IDs.
   Their previous omission lost events and call/result correlation. Oversized
   fast events retain Cursor conversation IDs as well as session IDs.
4. Codex SessionEnd is registered so explicit session close can clear state.
5. Doctor reports whether Codex uses legacy interception, native handling, or
   explicit opt-in.

## Verification and remaining gates

The running v7 installation passed Codex doctor: 8 checks, zero failures or
warnings; live confirmation passed. The first sandboxed request could not reach
localhost; the unrestricted retry could. Claude registrations were inspected but
this is not a live Claude harness check. Cursor live verification remains open.
The existing fixture matrix is not evidence of a complete real-session corpus.

Regression suite: `make test` passed **452 tests, zero skipped**, including all
four added regressions and the HTTP checks. Log: `/tmp/boop-hook-review-tests.log`.
The advanced-settings snapshot was rendered and visually reviewed at
`/tmp/buddy-snapshots/settings-advanced.png`. The initial sandboxed run failed
before compilation because Swift's user-level module cache was not writable;
the documented unrestricted retry passed after fixing the new tests to use this
repository's throwing assertion shim. `make build` passed for both Boop and
BoopSignal; log: `/tmp/boop-hook-review-build.log`.

The owner must launch the rebuilt GUI app; agents do not launch it because of
Bluetooth/TCC. A normal launch repairs installed hooks to v8. Restart Codex to
load its added SessionEnd registration. Current firmware needs no update: card
shape and byte caps are unchanged. Hardware visual review was not performed.

Native Codex approval waiting cannot be mirrored reliably with these hooks alone.
With Codex opt-in off, Boop shows activity/completion but does not display approval
cards for requests handled by the native reviewer. Cursor approval mirroring also
needs an authoritative waiting signal before it can be claimed.
