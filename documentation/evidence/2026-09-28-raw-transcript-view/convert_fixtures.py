"""Rewrites debug.jsonl files recorded before the raw transcript and its view
(2026-09-28) into the lines the app writes now, so the dashboard's and
`boopctl day`'s test fixtures keep their real runs:

- an `event` (kind, line, reaction, wakes_brain, facts) becomes a `view`
  line, its type and phase from its kind, `from` and `id` its old seq, and
  a rule reaction under it becomes a raw `action` event by the rule;
- an `action` becomes a raw `action` event (a `start` if it was pending),
  and a `settle` that action's `end`;
- a `pass` loses its seq.

The lines' words are the run's own: they're data for the tools, which never
parse them. Usage: python3 convert_fixtures.py FILE... (in place)."""
import json
import sys

KINDS = {"turn_start": ("turn", "start"), "turn_end": ("turn", "end"), "tool_use": ("tool", "end"),
         "pokes": ("poke", None), "tap": ("poke", None), "needs_you": ("tool", "wait"), "heartbeat": ("heartbeat", None)}
RULE = {"Boop wiggled on its own.": "wiggle", "Boop cheered on its own.": "cheer"}


def kind(line):
    return next((k for k in line if k not in ("seq", "received_at_ms")), "?")


def raw(seq, at, specific, phase, data, session=None):
    e = {"seq": seq, "ts": at, "source": "boop", "type": "action"}
    if phase:
        e["phase"] = phase
    e["specific_type"] = specific
    if session:
        e["session"] = session
    e["data"] = data
    return {"event": e, "received_at_ms": at}


def convert(lines):
    out, names, extra = [], {}, 10_000_000
    for line in lines:
        k, at, seq = kind(line), line.get("received_at_ms", 0), line.get("seq")
        body = line.get(k)
        if k == "event":
            type_, phase = KINDS[body["kind"]]
            view = {"id": seq, "type": type_, "from": [seq], "line": body["line"], "notes": [],
                    "wakes_brain": body.get("wakes_brain", False), "facts": body.get("facts", {})}
            if phase:
                view["phase"] = phase
            out.append({"view": view, "received_at_ms": at})
            if body.get("reaction"):
                extra += 1
                out.append(raw(extra, at, RULE.get(body["reaction"], "rule"), None,
                               {"by": "rule", "for": seq, "message": body["reaction"], "ok": True}))
        elif k == "action":
            names[seq] = body["name"]
            data = {"by": body.get("by") or "brain", "for": body.get("for"), "message": body["message"], "ok": body["ok"],
                    "latency_ms": body.get("latency_ms", 0)}
            out.append(raw(seq, at, body["name"], "start" if body.get("pending") else None, data))
        elif k == "settle":
            data = {"by": body.get("by") or "brain", "for": body["for"], "outcome": body["end"]}
            if body.get("why"):
                data["why"] = body["why"]
            out.append(raw(seq, at, names.get(body["for"], "react"), "end", data))
        elif k == "pass":
            out.append({"pass": body, "received_at_ms": at})
        else:
            out.append(line)
    return out


for path in sys.argv[1:]:
    text = open(path).read().splitlines()
    parsed = []
    for raw_line in text:
        try:
            parsed.append(json.loads(raw_line))
        except ValueError:
            continue
    with open(path, "w") as f:
        for line in convert(parsed):
            f.write(json.dumps(line, ensure_ascii=False, separators=(",", ":")) + "\n")
