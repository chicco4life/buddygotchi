"""Deterministic RenderState v2 scenes shared by shots and golden tooling."""

def cells():
    result = {}
    base = {"v": 2, "dots": 0, "gift": False, "focus": False, "mute": 0, "t": 0}
    for state in ("asleep", "idle", "working", "needsYou", "done", "uhoh"):
        result[state] = {**base, "state": state}
    for field, state, values in (("effort", "working", ("light", "hard", "grinding")), ("cheer", "done", ("hop", "cheer", "dance")), ("uhoh", "uhoh", ("error", "stuck", "hungry"))):
        for value in values:
            result[f"{field}-{value}"] = {**base, "state": state, field: value}
    for stakes in ("fine", "checkIt", "careful"):
        result[f"card-{stakes}"] = {**base, "state": "needsYou", "card": {"id": "shot", "tool": "Bash", "gloss": "Run tests", "stakes": stakes, "n": 1, "of": 1, "approval": True}}
    result["bubble-ko"] = {**base, "state": "idle", "bubble": "테스트 통과"}
    result["gift"] = {**base, "state": "idle", "gift": True, "giftLine": "Tests passed"}
    result["travel-snap"] = {**base, "state": "idle", "posture": "travel", "snap": {"name": "Boop", "level": 4, "xp": 120, "xpNext": 200, "streak": 3, "best": 7, "rest": 1, "days": 12, "tasks": 45, "today": 6, "biggest": "dance"}}
    return result
