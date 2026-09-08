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
    result["first-wake-grey"] = {**base, "state": "asleep"}
    for level in range(4):
        result[f"greet-{level}"] = {**base, "state": "idle", "overlay": "greet", "greetLevel": level}
    result["levelup"] = {**base, "state": "idle", "snap": {"level": 2}, "cosmetic": {"skin": "mint", "accessory": "sprout"}}
    result["streak-7"] = {**base, "state": "idle", "snap": {"level": 1, "streak": 7}}
    for accessory in ("sprout", "scarf", "crown"):
        result[f"cosmetic-{accessory}"] = {**base, "state": "idle", "cosmetic": {"skin": "mint", "accessory": accessory}}
    for silhouette in ("round", "tall"):
        result[f"silhouette-{silhouette}"] = {**base, "state": "idle", "cosmetic": {"skin": "mint", "silhouette": silhouette}}
    for name, state, fields in (("idle", "idle", {}), ("working-grinding", "working", {"effort": "grinding"}),
                                ("needsYou", "needsYou", {}), ("done-dance", "done", {"cheer": "dance"}), ("asleep", "asleep", {})):
        result[f"perch-{name}"] = {**base, "state": state, "posture": "perch", **fields}
    result["pickup"] = {**base, "state": "idle"}
    return result


def settle_ms(name, frame):
    """Exact offset from the triggering frame/reset/motion, in milliseconds."""
    if name == "first-wake-grey":
        return 4500
    if name.startswith("greet-"):
        return 700
    if name in ("levelup", "streak-7"):
        return 450
    if name == "pickup":
        return 300
    return 600 if frame["state"] == "done" else 2500


def prepare(s, name):
    """Isolate persisted cosmetics, growth, overlays and motion between cells."""
    import json
    import time
    s.write_line("clock clear")
    s.write_line("imu set 0 0 0.98")
    s.write_line(json.dumps({"v": 2, "state": "working", "posture": "desk", "mute": 0,
                             "cosmetic": {}, "snap": {"level": 1, "streak": 0}}))
    time.sleep(3.2)  # finish first color, old rituals, motion and decision feedback


def trigger(s, name):
    """Run after the target frame; these commands establish stateAt themselves."""
    import time
    if name == "first-wake-grey":
        s.write_line("firstwake reset")
    elif name == "pickup":
        s.write_line("imu set 0.7 0 0.7")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if s.framed_json("state", "STATE", 3).get("pickup"):
                break
        else:
            raise RuntimeError("pickup did not trigger")
