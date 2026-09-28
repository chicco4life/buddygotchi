"""The dashboard's one source, the state dir's debug.jsonl: following it as
the app writes it, noticing when the app starts again,
and keeping what the panes show: Boop now, and its three columns, the mood,
the automatic reactions and the decided ones. It never reads boop.log or the
mood file, and never parses an action's message for a fact."""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

Line = dict[str, Any]

# A debug-mode app writes a `sent` line at least every 10 s, the state
# keepalive (PROTOCOL.md §3), so a newest line older than this means no app
# is writing the file.
STALE_S = 15
# A view event written this soon after a reflex's `sent` line is what set it
# off: the app sends to the device first, then records the view event.
TRIGGER_MS = 1000
# A cheer, a wiggle or a mumble counts as what's showing for this long.
SHOWING_MS = 4000


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
    """`event` (a raw event the transcript recorded), `view` (what the brain
    may hear of), `pass`, `sent`, `status` or `questions`."""
    return next((k for k in line if k not in ("seq", "received_at_ms")), "?")


def view_name(view: Line) -> str:
    """A view event's type and phase: `turn end`, `tool wait`, `poke`."""
    return view.get("type", "?") + (f" {view['phase']}" if view.get("phase") else "")


def action(event: Line) -> Line | None:
    """A raw `action` event's start, or its only line, as the dashboard reads
    it: its name, whether it worked, its message, whether it's still going,
    who it's by (`dashboard`, `rule` or none for the brain) and what it's
    for. None for any other event, and for an action's end."""
    if event.get("type") != "action" or event.get("phase") == "end":
        return None
    data = event.get("data", {})
    by = data.get("by")
    return {"name": event.get("specific_type"), "ok": bool(data.get("ok")), "message": data.get("message", ""),
            "pending": event.get("phase") == "start", "by": None if by == "brain" else by, "for": data.get("for"),
            "session": event.get("session")}


def action_end(event: Line) -> Line | None:
    """A raw `action` event's end: how the action it's `for` went."""
    if event.get("type") != "action" or event.get("phase") != "end":
        return None
    data = event.get("data", {})
    by = data.get("by")
    return {"name": event.get("specific_type"), "for": data.get("for"), "end": data.get("outcome"), "why": data.get("why"),
            "by": None if by == "brain" else by}


def clock(ms: int) -> str:
    return time.strftime("%H:%M:%S", time.localtime(ms / 1000))


class Board:
    """What the panes show, built from debug.jsonl's lines in order."""

    def __init__(self) -> None:
        self.questions: list[Line] = []
        self.status: Line = {}
        self.state: Line | None = None  # the latest `state` sent to the device
        self.events: dict[int, Line] = {}  # view events by the raw event that made them
        self.names: dict[int, str] = {}  # each action's name by its seq, for its end
        self.latency_ms: int | None = None  # Jev's last
        self.dropped = 0
        self.jev_state: str | None = None  # the latest state a brain read, for `s`
        self.newest_ms: int | None = None  # the newest line's received_at_ms
        # The three columns, oldest first; each row a dict.
        self.moods: list[Line] = []
        self.reflexes: list[Line] = []
        self.decided: list[Line] = []
        self._pass_for: dict[int | None, Line] = {}  # the latest decided row by its event (None: forced)
        self._decided_by_action: dict[int, Line] = {}  # a decided row by its react action's seq
        self._reflex: tuple[int, str] | None = None  # the latest cheer, wiggle or chatter: (time, what)

    def apply(self, line: Line) -> tuple[str, str] | None:
        """Takes one line, and returns its timeline row as (style, text), or
        None for a `state` resent unchanged (the 10 s keepalive)."""
        k = kind(line)
        body, seq, at = line.get(k), line.get("seq"), line.get("received_at_ms", 0)
        if at:
            self.newest_ms = max(self.newest_ms or 0, at)
        if k == "questions":
            self.questions = body
            return "status", "questions: " + ", ".join(q["key"] for q in body)
        if k == "status":
            before, self.status = self.status, body
            return "status", "status: " + status_text(body, before)
        if k == "sent":
            return self._sent(body, at)
        if k == "view":
            self.events[(body.get("from") or [0])[-1]] = body
            self._event(body, at)
            text = f"▸ {body.get('id')} {view_name(body)}{'' if body.get('wakes_brain') else ' (no pass)'}: {body['line']}"
            return "event", text + "".join(f"  [{note}]" for note in body.get("notes") or [])
        if k == "event":
            return self._raw(body, at)
        if k == "pass":
            if body.get("brain") and body.get("state"):
                self.jev_state = body["state"]
            self._pass(body, seq, at)
            if body.get("brain"):
                self.latency_ms = body.get("latency_ms")
            who = body.get("brain") or f"forced by {body.get('by')}"
            if body.get("dropped"):
                self.dropped += 1
                return "fail", f"  pass {who} for {body.get('for')}: dropped: {body['dropped']}"
            picks = " · ".join(f"{key} {a['choice']}" for key, a in answers(body))
            return "pass", f"  pass {who}" + (f" for {body['for']}" if body.get("for") else "") + f": {picks}"
        return None

    def _raw(self, event: Line, at: int) -> tuple[str, str] | None:
        """A raw event: only actions have a row; the view says the rest."""
        seq = event.get("seq")
        if a := action(event):
            if a["name"] == "needs_you":
                return None  # the state's strip shows it, and the view its line
            self.names[seq] = a["name"]
            if a["by"] == "rule":
                self._rule(a, at)
            else:
                self._action(a, seq, at)
            by = f" (by {a['by']})" if a.get("by") else ""
            style, mark = ("fail", "✗") if not a["ok"] else ("dim", "…") if a.get("pending") else ("ok", "✓")
            return style, f"  {mark} {a['name']}{by}: {a['message']}"
        if end := action_end(event):
            if end["name"] == "needs_you":
                return None
            if row := self._decided_by_action.get(end["for"]):
                row["settle"] = end
            name = f"{self.names.get(end['for'], '?')} ({end['for']})"
            if end["end"] == "done":
                return "ok", f"  ✓ {name} done"
            return "fail", f"  ✗ {name} didn't happen: {end.get('why')}"
        return None

    # Sorting lines into the columns.

    def _sent(self, msg: Line, at: int) -> tuple[str, str] | None:
        if msg.get("t") == "state":
            unchanged = msg == self.state
            before, self.state = self.state, msg
            self._state_changed(before, msg, at)
            return None if unchanged else ("sent", "→ state " + state_text(msg))
        if msg.get("t") == "moment":
            if not msg.get("mood"):  # a reaction's moment has its face; a reflex's doesn't
                if msg.get("anim"):
                    loops = f", loops {msg['loops']}" if msg.get("loops") else ""
                    self.reflexes.append({"at": at, "what": msg["anim"] + loops, "anim": True, "trigger": None})
                elif msg.get("say"):
                    self.reflexes.append({"at": at, "what": "working chatter " + mumble(msg["say"]),
                                          "trigger": "an agent is working"})
                self._reflex = (at, self.reflexes[-1]["what"])
            parts = ([msg["anim"]] if msg.get("anim") else []) + (["say " + say_text(msg["say"])] if msg.get("say") else [])
            return "sent", "→ moment " + " + ".join(parts)
        return "sent", "→ " + json.dumps(msg)

    def _state_changed(self, before: Line | None, now: Line, at: int) -> None:
        mood = now.get("mood")
        if before is None:
            self.moods.append({"at": at, "mood": mood, "from": None, "cause": "at launch"})
        elif mood != before.get("mood"):
            self.moods.append({"at": at, "mood": mood, "from": before.get("mood"), "cause": None})
        # Needs you: a new request, or a different one, alerts (PROTOCOL.md §3).
        old, new = (before or {}).get("attn"), now.get("attn")
        ident = lambda a: (a.get("id", 0), a.get("agent"), a.get("project"))  # noqa: E731
        if new and (not old or ident(old) != ident(new)):
            more = f" (+{new['more']})" if new.get("more") else ""
            what = ("needs you: " if not old else "needs you now: ") + f"{new['agent']} · {new['project']}{more} · alert"
            self.reflexes.append({"at": at, "what": what, "attn": True, "trigger": None})
        elif old and not new:
            self.reflexes.append({"at": at, "what": "needs you cleared", "attn": True, "trigger": None})

    def _event(self, view: Line, at: int) -> None:
        """A view event of a request that waits on you names the needs-you
        strip just sent before it."""
        if view_name(view) != "tool wait":
            return
        waiting = [r for r in self.reflexes[-3:] if r["trigger"] is None and at - r["at"] <= TRIGGER_MS]
        match = next((r for r in waiting if r.get("attn")), None)
        if match:
            match["trigger"] = "▸ " + view["line"]

    def _rule(self, a: Line, at: int) -> None:
        """A rule's action names what set off the animation just sent before
        it; one the device plays by itself (the poke's wiggle) is a reflex
        of its own. Either way its trigger is the view event it's for."""
        event = self.events.get(a.get("for"))
        trigger = "▸ " + event["line"] if event else None
        waiting = [r for r in self.reflexes[-3:] if r["trigger"] is None and at - r["at"] <= TRIGGER_MS]
        match = next((r for r in waiting if r.get("anim")), None)
        if match:
            match["trigger"] = trigger
            return
        self.reflexes.append({"at": at, "what": a["message"], "trigger": trigger})
        self._reflex = (at, a["message"])

    def _pass(self, body: Line, seq: int, at: int) -> None:
        mood_keys = {q["key"] for q in self.questions if q["action"] == "mood"}
        row = {"at": at, "seq": seq, "pass": body, "event": self.events.get(body.get("for")), "react": None,
               "settle": None,
               # A pass that asks no mood question: the mood sat it out.
               "sat_out": bool(body.get("brain") and "questions" in body and mood_keys
                               and not mood_keys & set(body["questions"]))}
        self.decided.append(row)
        self._pass_for[body.get("for")] = row
        if row["sat_out"]:
            line = row["event"]["line"] if row["event"] else f"the pass for {body.get('for')}"
            self.moods.append({"at": at, "sat_out": line})

    def _action(self, body: Line, seq: int, at: int) -> None:
        if body["name"] == "react":
            row = self._pass_for.get(body.get("for"))
            if row and (row["pass"].get("by") or None) == (body.get("by") or None) and row["react"] is None:
                row["react"] = body
                self._decided_by_action[seq] = row
        elif body["name"] == "mood":
            if not body["ok"]:
                self.moods.append({"at": at, "refused": body["message"], "by": body.get("by")})
                return
            last = next((r for r in reversed(self.moods) if "mood" in r), None)
            if not last or last["cause"] is not None:
                return
            if body.get("by"):
                last["cause"] = f"forced by {body['by']}"
                return
            row = self._pass_for.get(body.get("for"))
            event = self.events.get(body.get("for"))
            last["cause"] = f"▸ {event['line']}" if event else f"the pass for {body.get('for')}"
            if row:
                a = row["pass"].get("answers", {}).get("mood")
                if a and a.get("p", {}).get(last["mood"]) is not None:
                    last["p"] = a["p"][last["mood"]]
                last["brain"] = row["pass"].get("brain")

    # The panes, as text.

    def stale(self, now_ms: int) -> bool:
        """No app is writing the file: its newest line is older than
        STALE_S, or it has none."""
        return self.newest_ms is None or now_ms - self.newest_ms > STALE_S * 1000

    def facts(self, now_ms: int | None = None) -> list[tuple[str, str]]:
        """Boop now, as (name, value)."""
        now_ms = (self.newest_ms or 0) if now_ms is None else now_ms
        s, st = self.state or {}, self.status
        attn = s.get("attn")
        count = lambda status: sum(x["status"] == status for x in st.get("sessions", []))  # noqa: E731
        look = s.get("base", "?") + (" with the needs-you strip" if attn else "")
        live = not self.stale(now_ms)
        return [
            ("look", look),
            ("mood", s.get("mood", "?")),
            ("showing", self.showing(now_ms)),
            ("needs you", f"{attn['agent']} · {attn['project']}" + (f" (+{attn['more']})" if attn.get("more") else "")
             if attn else "no"),
            ("sessions", f"{count('working')} working, {count('idle')} idle, {count('waiting')} waiting"),
            ("board", ("connected" if st.get("connected") else "not connected (the sim shows what it would)")
             if live else "unknown: no live log"),
            ("brain", f"{st.get('brain', '?')} · "
             + (f"{self.latency_ms} ms" if self.latency_ms is not None else "no pass yet") + f" · dropped {self.dropped}"),
        ]

    def showing(self, now_ms: int) -> str:
        """What the face is doing: a decided reaction still playing, a
        reflex just sent, or the look."""
        playing = next((r for r in reversed(self.decided) if r["react"]), None)
        if playing and playing["react"]["ok"] and playing["react"].get("pending") and not playing["settle"]:
            return reaction_text(playing)
        if self._reflex and now_ms - self._reflex[0] <= SHOWING_MS:
            return self._reflex[1]
        s = self.state or {}
        return f"its {s.get('base', '?')} look" + (" with the needs-you strip" if s.get("attn") else "")

    def mood_column(self) -> list[tuple[str, str]]:
        """The mood now, then its changes, newest first."""
        changes = [r for r in self.moods if "mood" in r]
        if not changes:
            return [("dim", "no state yet")]
        now = changes[-1]
        out = [("head", f"{now['mood']} since {clock(now['at'])}"), ("dim", "")]
        for r in reversed(self.moods):
            if "sat_out" in r:
                out.append(("dim", f"{clock(r['at'])} · mood sat out: {r['sat_out']}"))
            elif "refused" in r:
                out.append(("fail", f"{clock(r['at'])} ✗ forced mood refused: {r['refused']}"))
            else:
                change = f"{r['from']} → {r['mood']}" if r["from"] else f"{r['mood']}"
                out.append(("mood", f"{clock(r['at'])} {change}"))
                out.append(("dim", f"  {r['cause'] or '…'}"))
                if r.get("p") is not None:
                    out.append(("pass", f"  {brain_name(r.get('brain'))}: {r['mood']} {r['p']:.2f}"))
        return out

    def reflex_column(self) -> list[tuple[str, str]]:
        if not self.reflexes:
            return [("dim", "none yet")]
        out = []
        for r in reversed(self.reflexes):
            style = "attn" if r.get("attn") else "ok"
            out.append((style, f"{clock(r['at'])} {r['what']}"))
            trigger = r["trigger"] or ("no event: played from the dashboard" if r.get("anim") else "")
            if trigger:
                out.append(("dim", f"  {trigger}"))
        return out

    def decided_column(self) -> list[tuple[str, str]]:
        if not self.decided:
            return [("dim", "no pass yet")]
        out = []
        for r in reversed(self.decided):
            p = r["pass"]
            if not p.get("dropped") and choice(p, FACE) is None:
                continue  # a pass that asked no reaction couldn't react
            if r["event"]:
                out.append(("event", f"{clock(r['at'])} ▸ {r['event']['line']}"))
            elif p.get("by"):
                out.append(("event", f"{clock(r['at'])} forced by {p['by']}"))
            else:
                out.append(("event", f"{clock(r['at'])} the pass for {p.get('for')}"))
            if not p.get("dropped") and choice(p, FACE) not in (None, "none"):
                out.append(("pass", "  " + picks_text(p)))
            out.append(fate(r))
            if r["sat_out"]:
                out.append(("dim", "  the mood sat this pass out"))
        return out


def fate(row: Line) -> tuple[str, str]:
    """What became of a pass's reaction."""
    p, react, settle = row["pass"], row["react"], row["settle"]
    if p.get("dropped"):
        return "fail", f"  ✗ pass dropped: {p['dropped']}"
    if choice(p, FACE) == "none":
        return "dim", f"  stayed quiet · none {prob(p, FACE):.2f}"
    if react is None:
        return "dim", "  … waiting for the reaction"
    if not react["ok"]:
        return "fail", f"  ✗ didn't happen: {react['message']}"
    if settle:
        return ("ok", "  ✓ played") if settle["end"] == "done" else ("fail", f"  ✗ didn't happen: {settle.get('why')}")
    if react.get("pending"):
        return "playing", "  ▶ playing"
    return "ok", "  ✓ played"


# The reaction's face is `react.mood`, and its animation `react.animation`.
# Older logs name the face `react`, and for a while it carried the cheer
# too (`proud-cheer`); `answer` reads either.
FACE = "react.mood"


def answer(p: Line, key: str) -> Line:
    answers = p.get("answers") or {}
    if key == FACE and key not in answers:
        key = "react"
    return answers.get(key, {})


def choice(p: Line, key: str) -> str | None:
    return answer(p, key).get("choice")


def prob(p: Line, key: str) -> float:
    a = answer(p, key)
    return a.get("p", {}).get(a.get("choice"), 0.0)


def word_keys(p: Line) -> list[str]:
    return [k for k in p.get("questions") or p.get("answers", {}) if k.startswith("word.")]


def picks_text(p: Line) -> str:
    """The face, its animation, its word and its hold, each with its
    probability: `proud 0.82 · cheer 0.90 · "finally" 0.71 · three times 0.64`."""
    parts = [f"{choice(p, FACE)} {prob(p, FACE):.2f}"]
    if choice(p, "react.animation") not in (None, "none"):
        parts.append(f"{choice(p, 'react.animation')} {prob(p, 'react.animation'):.2f}")
    words = [(choice(p, k), prob(p, k)) for k in word_keys(p) if choice(p, k) not in (None, "none")]
    parts += [f"“{w}” {v:.2f}" for w, v in words] or ["no word"]
    if choice(p, "react.loops"):
        parts.append(f"{choice(p, 'react.loops')} {prob(p, 'react.loops'):.2f}")
    return " · ".join(parts)


def reaction_text(row: Line) -> str:
    """A playing reaction: `a proud reaction face, three times, "…finally!"`,
    or `a cheer in a proud face, …`."""
    p = row["pass"]
    words = [choice(p, k) for k in word_keys(p) if choice(p, k) not in (None, "none")]
    loops = choice(p, "react.loops")
    face, _, anim = (choice(p, FACE) or "?").partition("-")
    if choice(p, "react.animation") not in (None, "none"):
        anim = choice(p, "react.animation")
    what = (f"a {anim} in " if anim else "") + f"{'an' if face[0] in 'aeiou' else 'a'} {face}"
    what += " face" if anim else " reaction face"
    return (what + (f", {loops}" if loops else "")
            + (f", “…{words[0]}!”" if words else ""))


def brain_name(brain: str | None) -> str:
    name = (brain or "the brain").split(":")[0]
    return "Jev" if name == "jev" else name


def mumble(say: Line) -> str:
    return f"“{say.get('syl', '')}”" + (f" + {say['word']}" if say.get("word") else "")


def state_text(s: Line) -> str:
    attn = s.get("attn")
    more = f" +{attn['more']}" if attn and attn.get("more") else ""
    return (f"{s.get('base')} {s.get('mood')} · busy {s.get('busy', 0)}"
            + (f" · needs you: {attn['agent']} {attn['project']}{more}" if attn else "") + f" · vol {s.get('vol')}")


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
