"""Makes internal/tools/boopctl_lib/tests/fixtures/dash-columns.jsonl from
this run's debug.jsonl. The scripted brain answers everything at
probability 1, so the fixture gives the first pass's mood and the first
turn end's reaction, word and hold other probabilities, and makes the pass
for the failed deploy a dropped one, taking out its reaction's action,
moment and settle.

    python3 plan/evidence/2026-09-28-tonight/dash/make_fixture.py
"""
import json
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE.parents[3] / "internal" / "tools" / "boopctl_lib" / "tests" / "fixtures" / "dash-columns.jsonl"

lines = [json.loads(raw) for raw in (HERE / "debug.jsonl").read_text().splitlines()]
events = {line["seq"]: line["event"] for line in lines if "event" in line}
first_start = min(seq for seq, e in events.items() if e["kind"] == "turn_start")
first_end = min(seq for seq, e in events.items() if e["kind"] == "turn_end")
deploy = next(seq for seq, e in events.items() if "deploy failed" in e["line"])
dropped_action = next(line["seq"] for line in lines if line.get("action", {}).get("for") == deploy
                      and line["action"]["name"] == "react")
out = []
for i, line in enumerate(lines):
    p = line.get("pass")
    if p and p.get("for") == first_start:
        p["answers"]["mood"]["p"] = {"happy": 0.87, "grumpy": 0.08, "determined": 0.05}
    if p and p.get("for") == first_end:
        p["answers"]["react"]["p"] = {"excited": 0.82, "proud": 0.15, "none": 0.03}
        p["answers"]["word.feeling"]["p"] = {"yay": 0.71, "finally": 0.2, "none": 0.09}
        p["answers"]["react.loops"]["p"] = {"once": 0.64, "twice": 0.36}
    if p and p.get("for") == deploy:
        p["answers"], p["dropped"], p["latency_ms"] = {}, "late: no answer within 1500 ms", 1500
    if line.get("seq") == dropped_action or line.get("settle", {}).get("for") == dropped_action:
        continue
    # The reaction's moment: sent next to its action, the one with a `mood` for the deploy pass.
    sent = line.get("sent", {})
    if sent.get("mood") and any(o.get("seq") == dropped_action for o in lines[i - 1 : i + 2]):
        continue
    out.append(json.dumps(line, ensure_ascii=False, separators=(",", ":")))
OUT.write_text("\n".join(out) + "\n")
print(f"{OUT}: {len(out)} lines")
