#!/usr/bin/env python3
"""Universal PreToolUse hook for Cursor and Claude Code.

Reads the hook invocation JSON on stdin, forwards it to the local
buddy-daemon (``POST /hook/request``), and writes back the host-specific
permission decision JSON on stdout.

Supported formats (set via --format):

  cursor       Cursor's preToolUse / beforeShellExecution shape:
                 {"permission": "allow"|"deny"|"ask", ...}

  claude-code  Claude Code's PreToolUse shape:
                 {"hookSpecificOutput": {
                    "permissionDecision": "allow"|"deny"|"ask"}}

Fail-open policy
  On daemon-unreachable / timeout / network error / invalid JSON from
  the daemon we emit ``ask`` so the host falls back to its native
  permission UI rather than blocking or silently allowing.

Environment
  BUDDY_HOOK_URL      daemon endpoint
                      (default http://127.0.0.1:8080/hook/request)
  BUDDY_HOOK_TIMEOUT  seconds to block waiting for the browser/phone
                      decision before falling back to "ask" (default 55)
  BUDDY_HOOK_DEBUG    if set (any non-empty value), write the last stdin
                      payload to ``$BUDDY_HOOK_DEBUG_PATH`` or
                      ``$TMPDIR/buddy-hook-last.json`` for troubleshooting
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request


def _post(url: str, body: dict, timeout: float) -> dict:
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout + 2.0) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _decide_cursor(decision: str) -> dict:
    if decision == "allow":
        return {"permission": "allow"}
    if decision == "deny":
        return {
            "permission": "deny",
            "user_message": "Denied from your buddy client.",
            "agent_message": "User denied this tool call via the buddy mobile/web app.",
        }
    return {"permission": "ask"}


def _decide_claude_code(decision: str) -> dict:
    if decision == "allow":
        return {
            "hookSpecificOutput": {"permissionDecision": "allow"},
        }
    if decision == "deny":
        return {
            "hookSpecificOutput": {"permissionDecision": "deny"},
            "systemMessage": "Denied from the buddy client.",
        }
    return {"hookSpecificOutput": {"permissionDecision": "ask"}}


_FORMAT_WRITERS = {
    "cursor": _decide_cursor,
    "claude-code": _decide_claude_code,
}


def _extract_tool_and_hint(hook_input: dict) -> tuple[str, str]:
    """Normalize the varying Cursor / Claude-Code payload shapes.

    Observed shapes:
      Cursor beforeShellExecution: {"command": "...", "cwd": "...", ...}
      Cursor preToolUse:           {"tool_name": "Shell", "tool_input": {"command": "..."}, ...}
      Claude-Code PreToolUse:      {"hook_event_name":"PreToolUse","tool_name":..., "tool_input":...}
    """
    tool = (
        hook_input.get("tool_name")
        or hook_input.get("hook_event_name")
        or "Shell"
    )

    cand: list[str] = []
    for key in ("command", "user_prompt", "prompt"):
        v = hook_input.get(key)
        if isinstance(v, str) and v:
            cand.append(v)

    ti = hook_input.get("tool_input")
    if isinstance(ti, dict):
        for key in ("command", "file_path", "path", "url", "query"):
            v = ti.get(key)
            if isinstance(v, str) and v:
                cand.append(v)
        if not cand:
            cand.append(json.dumps(ti, separators=(",", ":"))[:200])

    hint = cand[0] if cand else ""
    return str(tool), str(hint)


def _write(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj))
    sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--format",
        choices=sorted(_FORMAT_WRITERS),
        default="cursor",
        help="output shape (default: cursor)",
    )
    args = ap.parse_args(argv)
    writer = _FORMAT_WRITERS[args.format]

    try:
        raw = sys.stdin.read()
    except Exception:
        _write(writer("ask"))
        return 0

    if os.environ.get("BUDDY_HOOK_DEBUG"):
        debug_path = os.environ.get(
            "BUDDY_HOOK_DEBUG_PATH",
            os.path.join(tempfile.gettempdir(), "buddy-hook-last.json"),
        )
        try:
            with open(debug_path, "w", encoding="utf-8") as fp:
                fp.write(raw or "{}")
        except OSError:
            pass

    try:
        hook_input = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        hook_input = {}

    tool_name, hint = _extract_tool_and_hint(hook_input)

    url = os.environ.get("BUDDY_HOOK_URL", "http://127.0.0.1:8080/hook/request")
    # Keep ~5s below the Cursor hooks.json timeout so we return a valid
    # stdout before Cursor reaps us. If you raise the Cursor timeout
    # further, raise this correspondingly via BUDDY_HOOK_TIMEOUT.
    timeout = float(os.environ.get("BUDDY_HOOK_TIMEOUT", "55"))
    # The source tag is carried end-to-end to the browser so the UI can
    # filter by host. "cursor" and "claude-code" are the known values;
    # anything else is rendered as "other".
    source = "claude-code" if args.format == "claude-code" else "cursor"

    try:
        resp = _post(
            url,
            {
                "tool": str(tool_name),
                "hint": str(hint),
                "source": source,
                "timeout_s": timeout,
            },
            timeout,
        )
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
        _write(writer("ask"))
        return 0

    decision = resp.get("decision", "ask") if isinstance(resp, dict) else "ask"
    _write(writer(decision))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
