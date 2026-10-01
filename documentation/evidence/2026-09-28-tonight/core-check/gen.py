import json, sys, subprocess, os
# Run from the repo root after `make build`; the sessions are written to /tmp/occk.
BOOPDEV = os.path.abspath(".build/debug/boopdev")
os.makedirs("/tmp/occk", exist_ok=True)
def h(hook, sid="s1", cwd="/tmp/landing", **kw):
    d = {"hook_event_name": hook, "session_id": sid, "cwd": cwd}
    d.update(kw); return d
def pre(tool, tid, agent=None, sid="s1", **kw):
    d = h("PreToolUse", sid, tool_name=tool, tool_use_id=tid, tool_input={"command":"ls"} if tool=="Bash" else {"file_path":"/tmp/x.ts"}, **kw)
    if agent: d["agent_id"]=agent; d["agent_type"]="general-purpose"
    return d
def post(tool, tid, agent=None, sid="s1", fail=False, **kw):
    d = h("PostToolUseFailure" if fail else "PostToolUse", sid, tool_name=tool, tool_use_id=tid, tool_input={"command":"ls"} if tool=="Bash" else {"file_path":"/tmp/x.ts"}, **kw)
    if fail: d["error"]="exit code 1"
    if agent: d["agent_id"]=agent; d["agent_type"]="general-purpose"
    return d
def perm(tool, agent=None, sid="s1"):
    d = h("PermissionRequest", sid, tool_name=tool, tool_input={"command":"ls"})
    if agent: d["agent_id"]=agent; d["agent_type"]="general-purpose"
    return d
def note(kind, sid="s1"): return h("Notification", sid, notification_type=kind, message="m")
def sstop(agent, sid="s1"): return h("SubagentStop", sid, agent_id=agent, agent_type="general-purpose", stop_hook_active=False, last_assistant_message="x")
def wait(ms): return {"wait_ms": ms}
def run(name, lines, states=True):
    p = f"/tmp/occk/{name}.jsonl"
    open(p,"w").write("\n".join(json.dumps(l) for l in lines)+"\n")
    args = [BOOPDEV, "replay", p] + (["--states"] if states else [])
    out = subprocess.run(args, capture_output=True, text=True)
    print(f"=== {name}"); print(out.stdout + out.stderr)
