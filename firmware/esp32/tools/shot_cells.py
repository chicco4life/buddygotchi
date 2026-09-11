"""Deterministic RenderState v2 scenes shared by shots and golden tooling."""
import json
import time


def cells():
    result = {}
    base = {"v": 2, "dots": 0, "gift": False, "focus": False, "mute": 0, "t": 0, "settle": 2500}
    for state in ("asleep", "idle", "working", "needsYou", "done", "uhoh"):
        result[state] = {**base, "state": state, "settle": 600 if state == "done" else 2500}
    for field, state, values in (("effort", "working", ("light", "hard", "grinding")), ("cheer", "done", ("hop", "cheer", "dance")), ("uhoh", "uhoh", ("error",))):
        for value in values:
            result[f"{field}-{value}"] = {**base, "state": state, field: value, "settle": 600 if state == "done" else 2500}
    for stakes in ("fine", "checkIt", "careful"):
        result[f"card-{stakes}"] = {**base, "state": "needsYou", "card": {"id": "shot", "tool": "Bash", "gloss": "Run tests", "stakes": stakes, "n": 1, "of": 1, "approval": True}}
    result["bubble-ko"] = {**base, "state": "idle", "bubble": "테스트 통과"}
    result["travel-snap"] = {**base, "state": "idle", "posture": "travel", "snap": {"name": "Boop", "level": 4, "xp": 120, "xpNext": 200, "streak": 3, "best": 7, "rest": 1, "days": 12, "tasks": 45, "today": 6, "biggest": "dance"}}
    result["first-wake-grey"] = {**base, "state": "asleep", "settle": 4500, "trigger": "firstwake reset"}
    for level in range(4):
        result[f"greet-{level}"] = {**base, "state": "idle", "overlay": "greet", "greetLevel": level, "settle": 700}
    result["levelup"] = {**base, "state": "idle", "snap": {"level": 2}, "cosmetic": {"skin": "mint", "accessory": "sprout"}, "settle": 450}
    result["streak-7"] = {**base, "state": "idle", "snap": {"level": 1, "streak": 7}, "settle": 450}
    for accessory in ("sprout", "scarf", "crown"):
        result[f"cosmetic-{accessory}"] = {**base, "state": "idle", "cosmetic": {"skin": "mint", "accessory": accessory}}
    for silhouette in ("round", "tall"):
        result[f"silhouette-{silhouette}"] = {**base, "state": "idle", "cosmetic": {"skin": "mint", "silhouette": silhouette}}
    for name, state, fields in (("idle", "idle", {}), ("working-grinding", "working", {"effort": "grinding"}),
                                ("needsYou", "needsYou", {}), ("done-dance", "done", {"cheer": "dance"}), ("asleep", "asleep", {})):
        result[f"perch-{name}"] = {**base, "state": state, "posture": "perch", **fields, "settle": 600 if state == "done" else 2500}
    result["pickup"] = {**base, "state": "idle", "settle": 300, "trigger": "imu set 0.7 0 0.7"}
    rows = [[0,1,"Fix device layout"], [1,1,"Run regression checks"], [0,0,"Write release notes"]]
    glance = {**base, "state":"working", "agents":[{"source":"codex","working":1,"idle":1}, {"source":"claude-code","working":1,"idle":0}], "threads":rows, "threadTotal":3}
    result["glance-working"] = {**glance, "settle":1200}
    result["glance-threads"] = {**glance, "trigger":"press a 100", "settle":1200}
    result["glance-threads-long"] = {**glance, "threads":[[0,1,"A deliberately long title that needs truncation"], [1,0,"기기 화면과 대시보드 탐색 개선"], [2,1,"Inspect a second project"]], "trigger":"press a 100", "settle":1200}
    result["glance-history"] = {**glance, "recent":[[103,0,"Fix dashboard navigation"],[102,1,"기기 화면 개선"],[101,2,"Run firmware tests"]], "trigger":"tap 400 255", "settle":1200}
    for name, title, count in [("finish", "Fix device layout", 1), ("finish-ko", "기기 화면 개선", 1), ("finish-batch", "Run regression checks", 2)]:
        result[name] = {**glance, "recent":[[101,0,title],[100,1,"Write release notes"]],
            "notice":{"id":101,"count":count,"age":0,"left":5000,"cheer":"cheer"}, "settle":800}
    result["glance-last"] = {**glance,"recent":[[101,0,"Fix device layout"]],"settle":1200}
    # The single heart, at its peak and on the way out.
    for name, settle in (("peak", 320), ("rise", 700)):
        result[f"boop-{name}"] = {**base, "state": "idle", "overlay": "boop", "settle": settle}
    for lang, text in (("en", "Boop polish and shop website updates"),
                       ("ko", "Boop과 쇼핑몰 웹사이트를 다듬고 있어요")):
        result[f"scope-face-{lang}"] = {**base, "state": "working", "scope": text}
        result[f"scope-idle-{lang}"] = {**base, "state": "idle", "scope": text,
            "agents": [{"source": "codex", "working": 0, "idle": 5}]}
        result[f"scope-dashboard-{lang}"] = {**glance, "scope": text,
            "recent": [[101,0,"Fix device layout"]], "settle": 1200}
    return result


def prepare(s):
    """Isolate persisted cosmetics, growth, overlays and motion between cells."""
    s.write_line("clock clear")
    s.write_line("imu set 0 0 0.98")
    s.write_line(json.dumps({"v": 2, "state": "working", "posture": "desk", "mute": 0,
                             "cosmetic": {}, "snap": {"level": 1, "streak": 0}}))
    time.sleep(3.2)  # finish first color, old rituals, motion and decision feedback


def trigger(s, command):
    """Run a cell's optional command after its frame, then await motion."""
    if not command:
        return
    if command.startswith("tap ") and not s.framed_json("ping", "PONG", 3).get("usbOnly"):
        raise RuntimeError("Panel-tap scenes require the USB-only verification firmware")
    s.write_line(command)
    if command.startswith("imu set "):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if s.framed_json("state", "STATE", 3).get("pickup"):
                break
        else:
            raise RuntimeError("pickup did not trigger")
