"""The dashboard's one source, the state dir's debug.jsonl (plan/DASHBOARD.md
§3): following it as the app writes it, noticing when the app starts again,
and keeping what the panes show. It never reads boop.log or the mood file,
and never parses an action's message."""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

Line = dict[str, Any]


class Follower:
    """The complete lines added to a file since the last read. The app
    empties the file in place at each launch and writes its `questions`
    line first, so when the file no longer starts with the first line read,
    the app has started again, and the file is read from the top."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset = 0
        self.partial = b""
        self.first = b""  # the file's first line, once read whole

    def read(self) -> tuple[bool, list[Line]]:
        """(started again, new lines). The first read is not a restart."""
        try:
            f = self.path.open("rb")
        except FileNotFoundError:
            return False, []
        with f:
            restarted = bool(self.first) and f.read(len(self.first)) != self.first
            if restarted:
                self.offset, self.partial, self.first = 0, b"", b""
            f.seek(self.offset)
            data = f.read()
        self.offset += len(data)
        *whole, self.partial = (self.partial + data).split(b"\n")
        if whole and not self.first:
            self.first = whole[0] + b"\n"
        lines = []
        for raw in whole:
            try:
                lines.append(json.loads(raw))
            except ValueError:
                continue
        return restarted, lines


def kind(line: Line) -> str:
    """`event`, `pass`, `action`, `sent`, `status` or `questions`."""
    return next((k for k in line if k not in ("seq", "received_at_ms")), "?")


def clock(ms: int) -> str:
    return time.strftime("%H:%M:%S", time.localtime(ms / 1000))


def without_time(state: Line | None) -> Line | None:
    return {k: v for k, v in state.items() if k != "time"} if state else None


class Board:
    """What the panes show, built from debug.jsonl's lines in order."""

    def __init__(self) -> None:
        self.questions: list[Line] = []
        self.status: Line = {}
        self.state: Line | None = None  # the latest `state` sent to the device
        self.say: Line | None = None  # the latest mumble sent
        self.events: dict[int, Line] = {}
        self.last_pass: Line | None = None  # the latest pass line, whole
        self.ran: list[Line] = []  # what its actions reported
        self.latency_ms: int | None = None  # Jev's last
        self.dropped = 0

    def apply(self, line: Line) -> tuple[str, str] | None:
        """Takes one line, and returns its timeline row as (style, text), or
        None for a `state` resent unchanged (the 10 s keepalive)."""
        k = kind(line)
        body, seq = line.get(k), line.get("seq")
        if k == "questions":
            self.questions = body
            return "status", "questions: " + ", ".join(q["key"] for q in body)
        if k == "status":
            before, self.status = self.status, body
            return "status", "status: " + status_text(body, before)
        if k == "sent":
            return self._sent(body)
        if k == "event":
            self.events[seq] = body
            text = f"▸ {seq} {body['kind']}{'' if body.get('wakes_brain') else ' (no pass)'}: {body['line']}"
            return "event", text + (f"  [{body['reaction']}]" if body.get("reaction") else "")
        if k == "pass":
            self.last_pass, self.ran = line, []
            if body.get("brain"):
                self.latency_ms = body.get("latency_ms")
            who = body.get("brain") or f"forced by {body.get('by')}"
            if body.get("dropped"):
                self.dropped += 1
                return "fail", f"  pass {who} for {body.get('for')}: dropped: {body['dropped']}"
            picks = " · ".join(f"{key} {a['choice']}" for key, a in answers(body))
            return "pass", f"  pass {who}" + (f" for {body['for']}" if body.get("for") else "") + f": {picks}"
        if k == "action":
            if self._answers_latest_pass(body):
                self.ran.append(body)
            by = f" (by {body['by']})" if body.get("by") else ""
            return ("ok" if body["ok"] else "fail"), f"  {'✓' if body['ok'] else '✗'} {body['name']}{by}: {body['message']}"
        return None

    def _sent(self, msg: Line) -> tuple[str, str] | None:
        if msg.get("t") == "state":
            unchanged = without_time(msg) == without_time(self.state)
            self.state = msg
            return None if unchanged else ("sent", "→ state " + state_text(msg))
        if msg.get("t") == "moment":
            if msg.get("say"):
                self.say = msg["say"]
            parts = ([msg["anim"]] if msg.get("anim") else []) + (["say " + say_text(msg["say"])] if msg.get("say") else [])
            return "sent", "→ moment " + " + ".join(parts)
        return "sent", "→ " + json.dumps(msg)

    def _answers_latest_pass(self, action: Line) -> bool:
        """Whether an action is the latest pass's: for the same event (or,
        forced, for none), and asking one of its questions. A mood the
        dashboard set is for none too, but answers no forced pass."""
        p = (self.last_pass or {}).get("pass")
        owners = {q["key"]: q["action"] for q in self.questions}
        return bool(p) and action.get("for") == p.get("for") and action["name"] in {owners.get(k) for k in p["questions"]}

    # The panes, as text.

    def facts(self) -> list[tuple[str, str]]:
        s, st = self.state or {}, self.status
        attn = s.get("attn")
        return [
            ("base", f"{s.get('base', '?')} · busy {s.get('busy', 0)} · idle {s.get('idle', 0)} · waiting {s.get('wait', 0)}"),
            ("needs you", f"{attn['agent']} · {attn['project']}" + (f" (+{attn['more']})" if attn.get("more") else "")
             if attn else "no"),
            ("saying", say_text(self.say) if self.say else "nothing yet"),
            ("mood", f"{s.get('mood', '?')} · personality {st.get('personality', '?')}"),
            ("sessions", sessions_text(st.get("sessions", []))),
            ("brain", f"{st.get('brain', '?')} · "
             + (f"{self.latency_ms} ms" if self.latency_ms is not None else "no pass yet") + f" · dropped {self.dropped}"),
            ("volume", str(s.get("vol", "?"))),
            ("device", "connected" if st.get("connected") else "not connected (the sim shows what it would)"),
        ]

    def harness(self) -> list[tuple[str, str]]:
        """The latest pass as (style, text) lines: IN, OUT and RAN."""
        if not self.last_pass:
            return [("dim", "no pass yet")]
        p = self.last_pass["pass"]
        out = [("head", "IN")]
        event = self.events.get(p.get("for"))
        if event:
            out.append(("event", f"▸ {p['for']} {event['kind']}: {event['line']}"))
            out.append(("dim", "  reflex: " + (event.get("reaction") or "nothing")))
        elif p.get("by"):
            out.append(("event", f"forced by {p['by']}, for no event"))
        if p.get("state"):
            out.append(("dim", "  state: " + " · ".join(f"{head.split(' (')[0]} {n}" for head, n in sections(p["state"]))
                        + " lines (s shows it)"))
        out.append(("dim", "  asked: " + ", ".join(p.get("questions", []))))
        out.append(("head", f"OUT  {p.get('brain') or 'forced'} · {p.get('latency_ms', 0)} ms"))
        if p.get("dropped"):
            out.append(("fail", "  dropped: " + p["dropped"]))
        for key, a in answers(p):
            spread = sorted(a.get("p", {}).items(), key=lambda kv: -kv[1])
            out.append(("pass", f"  {key} → {a['choice']}   " + " · ".join(f"{o} {v:.2f}" for o, v in spread)))
        out.append(("head", "RAN"))
        out += [("ok" if r["ok"] else "fail", f"  {'✓' if r['ok'] else '✗'} {r['name']}: {r['message']}") for r in self.ran]
        if not self.ran:
            out.append(("dim", "  nothing"))
        return out


def sections(state: str) -> list[tuple[str, int]]:
    """The state's parts as (heading, lines): the guide first, which has no
    heading, then each blank-line-separated section by its first line."""
    out = []
    for i, block in enumerate(state.split("\n\n")):
        lines = block.split("\n")
        out.append(("guide" if i == 0 else lines[0], len(lines)))
    return out


def state_text(s: Line) -> str:
    attn = s.get("attn")
    return (f"{s.get('base')} {s.get('mood')} · busy {s.get('busy', 0)} idle {s.get('idle', 0)} wait {s.get('wait', 0)}"
            + (f" · needs you: {attn['agent']} {attn['project']}" if attn else "") + f" · vol {s.get('vol')}")


def say_text(say: Line) -> str:
    word = f" + {say['word']} (at {say.get('at')})" if say.get("word") else ""
    return f"“{say.get('syl', '')}”{word} · {say.get('tune')} · {say.get('ms')} ms/syl"


def answers(p: Line) -> list[tuple[str, Line]]:
    """A pass's answers in the order it asked its questions."""
    return [(key, p["answers"][key]) for key in p["questions"] if key in p["answers"]]


def sessions_text(sessions: list[Line]) -> str:
    return ", ".join(f"{x['agent']} {x['project']} {x['status']}" for x in sessions) or "none"


def status_text(st: Line, before: Line | None = None) -> str:
    """What changed since `before`; everything the first time."""
    shown = {
        "personality": lambda v: f"personality {v}",
        "brain": lambda v: f"brain {v}",
        "sessions": lambda v: "sessions " + sessions_text(v),
        "connected": lambda v: "device " + ("connected" if v else "not connected"),
    }
    return " · ".join(show(st.get(key)) for key, show in shown.items() if not before or st.get(key) != before.get(key))
