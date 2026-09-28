"""Builds the device's faces from the mood designs as C tables.

The designs are animated SVGs, one per mood and state, in design/svg/ (the
designer's package, with the source that drew them). This reads each one
as rectangles and step-wise timings and writes firmware/assets/faces.h,
plus the frames the firmware test checks the device's player against
(internal/firmware/test/test_scene/frames.h), the faces the Mac's
popover shows (app/Boop/Views/FaceDesigns.swift), and each design's loop
length for the Mac (app/BoopKit/Core/FaceLoops.swift), which faces.h has
too, so both sides time a moment's loops alike. Nothing is rounded or
smoothed: every shape sits on whole pixels and every move is a whole-pixel
step, so the device draws each design exactly. Rerun it when the designs
change:

    internal/tools/.venv/bin/python internal/tools/facegen/facegen.py [--check]

--check also renders every design in Chrome at the same moments and
compares it with this file's own renderer, pixel for pixel.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SVG_DIR = HERE / "design" / "svg"
OUT = REPO / "firmware" / "assets" / "faces.h"
FRAMES = REPO / "internal" / "firmware" / "test" / "test_scene" / "frames.h"
SWIFT = REPO / "app" / "Boop" / "Views" / "FaceDesigns.swift"
LOOPS = REPO / "app" / "BoopKit" / "Core" / "FaceLoops.swift"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
NS = "{http://www.w3.org/2000/svg}"
W, H = 320, 240

# The order of render::Mood and render::SceneState.
MOODS = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad"]
STATES = ["idle", "working", "needs_you", "task_complete", "asleep", "no_app"]
# The faces the popover's tile shows, as mood and look. Asleep is
# one design for every mood, and the tile reads happy's
# (app/Boop/Views/BoopFace.swift).
TILES = [(mood, state) for mood in MOODS
         for state in ["idle", "working", "needs_you"] + (["asleep"] if mood == "happy" else [])]
# The designs' colours, by what they're for; index 0 is the black field.
COLORS = {"#000000": "black", "#F8F7EF": "ink", "#F1787D": "cheek", "#7BB4EF": "blue",
          "#F4BC50": "amber", "#68685E": "dim", "#A9A99B": "prop"}
COLOR_NAMES = list(COLORS.values())
# What the device does with a group (render::faces::Role).
ROLES = ["none", "face", "mouth", "prop", "eyes_open", "eyes_closed"]
PROPS = {"keyboard", "request-cue", "result-cue", "disconnected-cue"}
PROP_TOP = 144  # the band the props share with the bubble (render/screens.h kBubbleTop)
BLINK_KEYS = [0.0, 0.76, 0.79, 1.0]
# Moments the check and the frames sample, in ms; each scene skips those
# within 4 ms of a step, where Chrome and the device could disagree by a
# rounding.
SAMPLES = [0, 150, 420, 700, 1100, 1650, 2300, 3100, 4200, 5500, 7300, 9900]
# A design with nothing moving but the blink, or nothing at all, still
# loops, in this time.
STILL_LOOP_MS = 1000


@dataclass
class Track:
    kind: str  # "move" or "show"
    dur: int  # ms
    once: bool  # plays once and holds its last value
    keys: list[int]  # ms, the first 0
    values: list[tuple[int, int]]  # (dx, dy) to move; (1 or 0, 0) to show
    raw_keys: list[float] = field(default_factory=list)

    def index(self, t: int) -> int:
        if self.once and t >= self.dur:
            return len(self.keys) - 1
        lt = t % self.dur
        return max(i for i, k in enumerate(self.keys) if k <= lt)


@dataclass
class Group:
    parent: int
    tx: int = 0
    ty: int = 0
    visible: bool = True
    move: Track | None = None
    show: Track | None = None
    role: str = "none"


@dataclass
class Rect:
    group: int
    x: int
    y: int
    w: int
    h: int
    color: int


@dataclass
class Scene:
    groups: list[Group]
    rects: list[Rect]

    def tracks(self) -> list[Track]:
        return [t for g in self.groups for t in (g.move, g.show) if t]

    def boundaries(self, until: int) -> set[int]:
        out: set[int] = set()
        for tr in self.tracks():
            reps = 1 if tr.once else until // tr.dur + 1
            for r in range(reps):
                out.update(r * tr.dur + k for k in tr.keys)
                out.add(r * tr.dur + tr.dur)
        return out

    def samples(self) -> list[int]:
        bounds = self.boundaries(max(SAMPLES) + 1)
        return [t for t in SAMPLES if t == 0 or all(abs(t - b) > 4 for b in bounds)]

    def key(self) -> str:
        return hashlib.sha1(repr((self.groups, self.rects)).encode()).hexdigest()

    def loop_ms(self) -> int:
        """How long the design takes to play once through:
        its longest animation, played once or on repeat, leaving out the
        blink, which the device times on its own. A moment's `loops` count
        these. It doesn't check that the design ends as it starts."""
        timed = [tr.dur for g in self.groups if g.role not in ("eyes_open", "eyes_closed")
                 for tr in (g.move, g.show) if tr]
        return max(timed or [STILL_LOOP_MS])


# ---- Reading the SVGs --------------------------------------------------------


def seconds_ms(s: str) -> int:
    assert s.endswith("s"), s
    return round(float(s[:-1]) * 1000)


def parse_track(el: ET.Element) -> Track:
    assert el.get("calcMode") == "discrete", "only step-wise animation"
    dur = seconds_ms(el.get("dur"))
    raw = [float(k) for k in el.get("keyTimes").split(";")]
    keys = [round(k * dur) for k in raw]
    values = el.get("values").split(";")
    assert len(values) == len(keys) and raw[0] == 0, "one value per key time, from 0"
    once = el.get("repeatCount") == "1"
    assert once or el.get("repeatCount") == "indefinite"
    if el.tag == NS + "animateTransform":
        assert el.get("type") == "translate"
        vals = []
        for v in values:
            x, y = (int(n) for n in v.split())
            vals.append((x, y))
        return Track("move", dur, once, keys, vals, raw)
    assert el.get("attributeName") == "opacity"
    vals = [(int(float(v)), 0) for v in values]
    assert all(v in ((0, 0), (1, 0)) for v in vals), "opacity is 0 or 1"
    return Track("show", dur, once, keys, vals, raw)


def path_rects(d: str) -> list[tuple[int, int, int, int]]:
    """An outline of straight lines between whole pixels, filled nonzero, as
    rectangles. A pixel is filled when its centre is inside; a centre exactly
    on an edge belongs to the shape on the edge's left, as Chrome draws it."""
    assert re.fullmatch(r"(?:\s*(?:[MmHhVvLlZz]|-?\d+(?:\.\d+)?))*\s*", d), f"only M, H, V, L and Z: {d}"
    tokens = re.findall(r"[MmHhVvLlZz]|-?\d+(?:\.\d+)?", d)
    edges: list[tuple[int, int, int, int]] = []
    x = y = sx = sy = 0
    i = 0

    def num() -> int:
        nonlocal i
        v = float(tokens[i])
        assert v == int(v), "whole pixels only"
        i += 1
        return int(v)

    while i < len(tokens):
        c = tokens[i]
        i += 1
        if c in "Mm":
            nx, ny = num(), num()
            x, y = (nx, ny) if c == "M" else (x + nx, y + ny)
            sx, sy = x, y
            continue
        if c in "Hh":
            nx = num()
            nx, ny = (nx if c == "H" else x + nx), y
        elif c in "Vv":
            ny = num()
            nx, ny = x, (ny if c == "V" else y + ny)
        elif c in "Ll":
            nx, ny = num(), num()
            nx, ny = (nx, ny) if c == "L" else (x + nx, y + ny)
        else:  # Z
            nx, ny = sx, sy
        if (nx, ny) != (x, y):
            edges.append((x, y, nx, ny))
        x, y = nx, ny
    xs = [e[0] for e in edges] + [e[2] for e in edges]
    ys = [e[1] for e in edges] + [e[3] for e in edges]
    rows: list[list[tuple[int, int]]] = []
    for py in range(min(ys), max(ys)):
        cy = py + 0.5
        run: list[tuple[int, int]] = []
        start = None
        for px in range(min(xs), max(xs) + 1):
            cx = px + 0.5
            wind = 0
            for x0, y0, x1, y1 in edges:
                if y0 == y1 or not (min(y0, y1) <= cy < max(y0, y1)):
                    continue
                if x0 + (cy - y0) * (x1 - x0) / (y1 - y0) < cx:
                    continue
                wind += 1 if y1 > y0 else -1
            if wind and start is None:
                start = px
            if not wind and start is not None:
                run.append((start, px))
                start = None
        rows.append(run)
    return merge_runs(rows, min(ys))


def merge_runs(rows: list[list[tuple[int, int]]], y0: int) -> list[tuple[int, int, int, int]]:
    """Runs of pixels, row by row, as rectangles: a run that repeats on the next row grows down."""
    out: list[tuple[int, int, int, int]] = []
    open_: dict[tuple[int, int], int] = {}  # run → the row it started on
    for r, runs in enumerate(rows + [[]]):
        now = set(runs)
        for run, top in list(open_.items()):
            if run not in now:
                out.append((run[0], y0 + top, run[1] - run[0], r - top))
                del open_[run]
        for run in runs:
            open_.setdefault(run, r)
    return sorted(out, key=lambda q: (q[1], q[0]))


def translate(s: str | None) -> tuple[int, int]:
    if not s:
        return 0, 0
    m = re.fullmatch(r"translate\((-?\d+) (-?\d+)\)", s)
    assert m, s
    return int(m[1]), int(m[2])


def read_scene(path: Path) -> Scene:
    root = ET.parse(path).getroot()
    motion = next(g for g in root if g.tag == NS + "g" and g.get("class") == "boop-motion")
    scene = Scene([], [])

    def walk(el: ET.Element, parent: int, fill: str | None) -> None:
        g = Group(parent)
        g.tx, g.ty = translate(el.get("transform"))
        g.visible = el.get("opacity", "1") != "0"
        part = el.get("data-part")
        g.role = "face" if part == "face" else "mouth" if part == "mouth" else "prop" if part in PROPS else "none"
        fill = el.get("fill", fill)
        me = len(scene.groups)
        scene.groups.append(g)
        for child in el:
            tag = child.tag[len(NS):]
            if tag in ("animate", "animateTransform"):
                tr = parse_track(child)
                assert getattr(g, tr.kind) is None, "one animation of each kind a group"
                setattr(g, tr.kind, tr)
            elif tag == "g":
                walk(child, me, fill)
            elif tag in ("rect", "path"):
                color = COLOR_NAMES.index(COLORS[child.get("fill", fill)])
                if tag == "rect":
                    q = [int(child.get(a, "0")) for a in ("x", "y", "width", "height")]
                    scene.rects.append(Rect(me, *q, color))
                else:
                    scene.rects.extend(Rect(me, *q, color) for q in path_rects(child.get("d")))
            else:
                raise AssertionError(f"{path.name}: unexpected <{tag}>")
        if g.show and g.show.raw_keys == BLINK_KEYS:
            if [v[0] for v in g.show.values] == [1, 0, 1, 1]:
                g.role = "eyes_open"
            elif [v[0] for v in g.show.values] == [0, 1, 0, 0]:
                g.role = "eyes_closed"

    walk(motion, -1, None)
    # A loose group drawn only in the props' band, such as the sparkles by
    # the result card, gives way to the bubble with the props.
    for i, g in enumerate(scene.groups):
        if g.parent != 0 or g.role != "none":
            continue
        mine = {i}
        for j in range(i + 1, len(scene.groups)):
            if scene.groups[j].parent in mine:
                mine.add(j)
        ys = [r.y + g.ty for r in scene.rects if r.group in mine]
        if ys and min(ys) >= PROP_TOP:
            g.role = "prop"
    roles = [g.role for g in scene.groups]
    assert roles.count("eyes_open") == roles.count("eyes_closed") <= 1, f"{path.name}: one blink"
    assert roles.count("face") == 1 and roles.count("mouth") == 1, f"{path.name}: one face, one mouth"
    return scene


# ---- Drawing, as the device does and as the SVG does -------------------------


def render(scene: Scene, t: int, svg_blink: bool = False, face_only: bool = False, shut: bool = False) -> bytes:
    """The colour index of every pixel at t ms. The device blinks on its own
    clock, so it shows the open eyes, or the closed ones when `shut`; with
    `svg_blink` the eyes blink on the design's clock, as Chrome draws it.
    `face_only` leaves out everything outside the face's group."""
    px = bytearray(W * H)
    in_face: list[bool] = []
    offset: list[tuple[int, int]] = []
    shown: list[bool] = []
    for g in scene.groups:
        ox, oy = offset[g.parent] if g.parent >= 0 else (0, 0)
        on = shown[g.parent] if g.parent >= 0 else True
        ox, oy = ox + g.tx, oy + g.ty
        if g.move:
            dx, dy = g.move.values[g.move.index(t)]
            ox, oy = ox + dx, oy + dy
        vis = g.visible
        if g.show and (svg_blink or g.role not in ("eyes_open", "eyes_closed")):
            vis = bool(g.show.values[g.show.index(t)][0])
        elif g.role == "eyes_open":
            vis = not shut
        elif g.role == "eyes_closed":
            vis = shut
        offset.append((ox, oy))
        shown.append(on and vis)
        in_face.append(g.role == "face" or (g.parent >= 0 and in_face[g.parent]))
    for r in scene.rects:
        if not shown[r.group] or (face_only and not in_face[r.group]):
            continue
        ox, oy = offset[r.group]
        x0, y0 = max(0, r.x + ox), max(0, r.y + oy)
        x1, y1 = min(W, r.x + ox + r.w), min(H, r.y + oy + r.h)
        for y in range(y0, y1):
            px[y * W + x0:y * W + x1] = bytes([r.color]) * max(0, x1 - x0)
    return bytes(px)


# ---- Writing -----------------------------------------------------------------


def emit(scenes: list[Scene], index: dict[tuple[int, int], int], sources: dict[int, str]) -> str:
    tracks: list[Track] = []
    keys: list[int] = []
    vals: list[int] = []
    groups: list[str] = []
    rects: list[str] = []
    scene_rows: list[str] = []
    track_rows: list[str] = []
    max_groups = max_tracks = 0
    for n, s in enumerate(scenes):
        g0, r0, t0 = len(groups), len(rects), len(tracks)
        for g in s.groups:
            ids = []
            for tr in (g.move, g.show):
                # The device blinks on its own clock (plan/BEHAVIORS.md §2), so
                # the design's blink timing isn't kept.
                if tr is None or g.role in ("eyes_open", "eyes_closed"):
                    ids.append(-1)
                    continue
                ids.append(len(tracks) - t0)
                track_rows.append(f"{{{tr.dur}, {int(tr.once)}, {len(tr.keys)}, {len(keys)}}}")
                tracks.append(tr)
                keys.extend(tr.keys)
                for v in tr.values:
                    vals.extend(v)
            groups.append(f"{{{g.tx}, {g.ty}, {g.parent}, {ROLES.index(g.role)}, {int(g.visible)}, {ids[0]}, {ids[1]}}}")
        for r in s.rects:
            assert 0 < r.w < 256 and 0 < r.h < 256 and r.group < 256
            rects.append(f"{{{r.x}, {r.y}, {r.w}, {r.h}, {r.group}, {r.color}}}")
        assert len(s.groups) < 128 and len(tracks) - t0 < 128, "groups and tracks fit an int8_t"
        max_groups = max(max_groups, len(s.groups))
        max_tracks = max(max_tracks, len(tracks) - t0)
        assert 0 < s.loop_ms() < 65536, "a loop fits a uint16_t"
        scene_rows.append(f"{{{g0}, {len(s.groups)}, {r0}, {len(s.rects)}, {t0}, {len(tracks) - t0}, {s.loop_ms()}}},"
                          f"  // {n}: {sources[n]}")
    assert all(-128 <= v <= 127 for v in vals) and all(k < 65536 for k in keys)
    size = len(rects) * 8 + len(groups) * 10 + len(tracks) * 6 + len(keys) * 2 + len(vals) + len(scenes) * 14

    def block(name: str, ctype: str, rows: list[str], per_line: int = 1) -> list[str]:
        out = [f"static const {ctype} {name}[{len(rows)}] = {{"]
        for i in range(0, len(rows), per_line):
            out.append("  " + ", ".join(rows[i:i + per_line]) + ",")
        out.append("};")
        return out

    lines = [
        "// Generated by internal/tools/facegen/facegen.py from the mood designs in",
        "// internal/tools/facegen/design/svg/. Do not edit.",
        f"// {len(scenes)} scenes, {len(groups)} groups, {len(rects)} rectangles, {len(tracks)} tracks: about {size // 1024 + 1} KB.",
        "#pragma once",
        "#include <cstdint>",
        "",
        "namespace render {",
        "namespace faces {",
        "",
        "// What the device does with a group besides drawing it (render/scene.cpp).",
        "enum Role : uint8_t { kRoleNone, kRoleFace, kRoleMouth, kRoleProp, kRoleEyesOpen, kRoleEyesClosed };",
        "// The designs' colours, by what they're for; 0 is the black field.",
        "enum Color : uint8_t { kBlackField, kInk, kCheek, kBlue, kAmber, kDim, kPropGrey, kColorCount };",
        "",
        "// A group moves and shows its rectangles and its child groups. Its",
        "// offset is its parent's plus (tx, ty) plus its move track's step; it",
        "// shows while its parent does and, with a show track, while that says so.",
        "struct Group {",
        "  int16_t tx, ty;",
        "  int8_t parent;  // within the scene; -1 for the top",
        "  uint8_t role;",
        "  uint8_t visible;  // before any show track",
        "  int8_t move, show;  // tracks within the scene; -1 for none",
        "};",
        "struct Rect {",
        "  int16_t x, y;",
        "  uint8_t w, h;",
        "  uint8_t group;  // within the scene",
        "  uint8_t color;",
        "};",
        "// A step-wise animation: key k holds from keys[k] ms into each run of",
        "// `dur` ms, and `once` holds the last value after the first run.",
        "struct Track {",
        "  uint16_t dur;",
        "  uint8_t once, n;",
        "  uint16_t key0;  // into kKeys and, two a key, kValues",
        "};",
        "// A scene's `loopMs` is how long it takes to play once through: its",
        "// longest track but the blink, which the device times itself. A",
        "// moment's loops count these (plan/PROTOCOL.md §3).",
        "struct Scene {",
        "  uint16_t group0, groups, rect0, rects, track0, tracks;",
        "  uint16_t loopMs;",
        "};",
        "",
        f"constexpr int kMaxGroups = {max_groups};",
        f"constexpr int kMaxTracks = {max_tracks};",
        f"constexpr int kSceneCount = {len(scenes)};",
        "",
    ]
    lines += block("kScenes", "Scene", scene_rows)
    table = []
    for m in range(len(MOODS)):
        table.append("{" + ", ".join(str(index[(m, s)]) for s in range(len(STATES))) + "},  // " + MOODS[m])
    lines += [f"// The scene for each mood and state ({', '.join(STATES)}).",
              f"static const uint8_t kSceneOf[{len(MOODS)}][{len(STATES)}] = {{"] + ["  " + r for r in table] + ["};"]
    lines += block("kGroups", "Group", groups, 4)
    lines += block("kRects", "Rect", rects, 5)
    lines += block("kTracks", "Track", track_rows, 6)
    lines += block("kKeys", "uint16_t", [str(k) for k in keys], 16)
    lines += block("kValues", "int8_t", [str(v) for v in vals], 24)
    lines += ["", "}  // namespace faces", "}  // namespace render", ""]
    return "\n".join(lines)


def emit_swift(scenes: list[Scene], index: dict[tuple[int, int], int]) -> str:
    """Each tile look's face at rest (the moment its design starts), open
    and shut, as rectangles of one colour each."""
    import base64

    faces: dict[str, tuple[str, str]] = {}
    boxes = []
    rects_of: dict[tuple[int, bool], list[tuple[int, int, int, int, int]]] = {}
    for mood, state in TILES:
        n = index[(MOODS.index(mood), STATES.index(state))]
        for shut in (False, True):
            if (n, shut) in rects_of:
                continue
            px = render(scenes[n], 0, face_only=True, shut=shut)
            out = []
            for color in range(1, len(COLOR_NAMES)):
                rows = []
                for y in range(H):
                    run, start = [], None
                    for x in range(W + 1):
                        on = x < W and px[y * W + x] == color
                        if on and start is None:
                            start = x
                        if not on and start is not None:
                            run.append((start, x))
                            start = None
                    rows.append(run)
                out += [(x, y, w, h, color) for x, y, w, h in merge_runs(rows, 0)]
            rects_of[(n, shut)] = out
            boxes += out
    x0 = min(r[0] for r in boxes)
    y0 = min(r[1] for r in boxes)
    x1 = max(r[0] + r[2] for r in boxes)
    y1 = max(r[1] + r[3] for r in boxes)
    assert x1 - x0 < 256 and y1 - y0 < 256
    for mood, state in TILES:
        n = index[(MOODS.index(mood), STATES.index(state))]
        enc = []
        for shut in (False, True):
            data = bytes(v for x, y, w, h, c in rects_of[(n, shut)] for v in (x - x0, y - y0, w, h, c))
            enc.append(base64.b64encode(data).decode())
        faces[f"{mood}/{state}"] = (enc[0], enc[1])
    lines = [
        "// Generated by internal/tools/facegen/facegen.py from the mood designs in",
        "// internal/tools/facegen/design/svg/. Do not edit.",
        "import CoreGraphics",
        "",
        "/// Each mood design's face as its look starts, open-eyed and blinking,",
        "/// for the popover's tile: the device's own shapes, without",
        "/// the props.",
        "enum FaceDesigns {",
        "    /// Where the faces sit in the designs' 320×240 screen.",
        f"    static let box = CGRect(x: {x0}, y: {y0}, width: {x1 - x0}, height: {y1 - y0})",
        "",
        "    /// By \"mood/look\": base64 of five bytes a rectangle, x and y from the",
        "    /// box's corner, width, height and colour (1 the eyes and mouth,",
        "    /// 2 the cheeks, 3 the tears).",
        "    static let faces: [String: (open: String, shut: String)] = [",
    ]
    for k, (o, sh) in faces.items():
        lines.append(f'        "{k}": ("{o}",')
        lines.append(f'            "{sh}"),')
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def emit_loops(scenes: list[Scene], index: dict[tuple[int, int], int]) -> str:
    """Each mood and state's loop length, for the Mac: the numbers faces.h
    gives the device."""
    lines = [
        "// Generated by internal/tools/facegen/facegen.py from the mood designs in",
        "// internal/tools/facegen/design/svg/. Do not edit.",
        "",
        "/// How long each mood design takes to play once through, in ms: its",
        "/// longest animation, leaving out the blink, which the device times on",
        "/// its own. A moment's `loops` count these, and the device's",
        "/// firmware/assets/faces.h has the same numbers (PROTOCOL.md §3).",
        "public enum FaceLoops {",
        "    /// The designs' states, in `ms`'s order.",
        "    public static let states = [" + ", ".join(f'"{st}"' for st in STATES) + "]",
        "",
        "    /// By mood, each state's loop length, in `states`' order.",
        "    public static let ms: [String: [Int64]] = [",
    ]
    for m, mood in enumerate(MOODS):
        lines.append(f'        "{mood}": [' + ", ".join(str(scenes[index[(m, s)]].loop_ms()) for s in range(len(STATES))) + "],")
    lines += [
        "    ]",
        "",
        "    /// A design's loop length: `mood`'s design for `state`, happy's for a",
        "    /// mood it doesn't know and idle's for a state it doesn't, as the",
        "    /// device reads them.",
        "    public static func ms(mood: String, state: String) -> Int64 {",
        "        let row = ms[mood] ?? ms[\"happy\"]!",
        "        return row[states.firstIndex(of: state) ?? 0]",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def emit_frames(frames: list[tuple[int, int, int, int]]) -> str:
    lines = [
        "// Generated by internal/tools/facegen/facegen.py. Do not edit.",
        "// Each design at moments away from its steps, as facegen draws it for",
        "// the device: CRC-32 of the colour index of every pixel (faces::Color).",
        "#pragma once",
        "#include <cstdint>",
        "",
        "struct FacegenFrame {",
        "  uint8_t mood, state;",
        "  uint32_t t, crc;",
        "};",
        f"static const FacegenFrame kFacegenFrames[{len(frames)}] = {{",
    ]
    for m, s, t, crc in frames:
        lines.append(f"  {{{m}, {s}, {t}, 0x{crc:08x}u}},  // {MOODS[m]} {STATES[s]}")
    lines += ["};", ""]
    return "\n".join(lines)


# ---- Checking against Chrome ---------------------------------------------------


def chrome_frames(files: list[Path], t_ms: int, tmp: Path) -> list[bytes]:
    """Each file drawn by Chrome at t ms, as colour indexes."""
    from PIL import Image

    cols = 7
    rows = (len(files) + cols - 1) // cols
    cells = []
    for i, f in enumerate(files):
        svg = f.read_text().split("?>")[-1]
        cells.append(f'<div style="position:absolute;left:{i % cols * W}px;top:{i // cols * H}px;width:{W}px;height:{H}px">{svg}</div>')
    page = tmp / f"t{t_ms}.html"
    page.write_text(
        "<!doctype html><html><body style='margin:0;background:#000'>" + "".join(cells) +
        f"<script>for(const s of document.querySelectorAll('svg')){{s.setAttribute('data-motion','on');"
        f"s.pauseAnimations();s.setCurrentTime({t_ms / 1000});}}</script></body></html>")
    shot = tmp / f"t{t_ms}.png"
    cmd = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
           f"--window-size={cols * W},{rows * H}", f"--screenshot={shot}", page.as_uri()]
    # Chrome's output isn't captured, since a helper it leaves running would
    # hold the pipe open; and it gets no --user-data-dir, whose first run
    # hangs headless Chrome on macOS. It still hangs now and then.
    for attempt in (1, 2, 3):
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            break
        except subprocess.TimeoutExpired:
            if attempt == 3:
                raise
    img = Image.open(shot).convert("RGB")
    rgb = {tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)): COLOR_NAMES.index(n) for h, n in COLORS.items()}
    out = []
    for i in range(len(files)):
        crop = img.crop((i % cols * W, i // cols * H, i % cols * W + W, i // cols * H + H))
        data = bytearray(W * H)
        for n, p in enumerate(crop.get_flattened_data()):
            if p not in rgb:
                raise SystemExit(f"{files[i].name} at {t_ms} ms: Chrome drew {p}, not one of the designs' colours")
            data[n] = rgb[p]
        out.append(bytes(data))
    return out


def check(scenes: list[Scene], files: dict[int, Path]) -> None:
    order = sorted(files)
    by_time: dict[int, list[int]] = {}
    for n in order:
        for t in scenes[n].samples():
            by_time.setdefault(t, []).append(n)
    compared = 0
    with tempfile.TemporaryDirectory() as tmp:
        for t, ns in sorted(by_time.items()):
            got = chrome_frames([files[n] for n in ns], t, Path(tmp))
            for n, chrome in zip(ns, got):
                mine = render(scenes[n], t, svg_blink=True)
                if mine != chrome:
                    bad = sum(a != b for a, b in zip(mine, chrome))
                    first = next(i for i, (a, b) in enumerate(zip(mine, chrome)) if a != b)
                    raise SystemExit(f"{files[n].name} at {t} ms: {bad} pixels differ from Chrome, "
                                     f"first at ({first % W}, {first // W})")
                compared += 1
    print(f"check: {compared} frames of {len(scenes)} scenes match Chrome pixel for pixel")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="compare every scene with Chrome's rendering first")
    args = parser.parse_args()
    scenes: list[Scene] = []
    seen: dict[str, int] = {}
    index: dict[tuple[int, int], int] = {}
    sources: dict[int, str] = {}
    files: dict[int, Path] = {}
    for m, mood in enumerate(MOODS):
        for s, state in enumerate(STATES):
            path = SVG_DIR / f"{mood}--{state}.svg"
            scene = read_scene(path)
            k = scene.key()
            if k not in seen:
                seen[k] = len(scenes)
                scenes.append(scene)
                sources[seen[k]] = path.name
                files[seen[k]] = path
            index[(m, s)] = seen[k]
    if args.check:
        check(scenes, files)
    frames = []
    for m in range(len(MOODS)):
        for s in range(len(STATES)):
            n = index[(m, s)]
            if sources[n] != f"{MOODS[m]}--{STATES[s]}.svg":
                continue  # a shared design, checked once
            for t in scenes[n].samples():
                frames.append((m, s, t, zlib.crc32(render(scenes[n], t))))
    OUT.write_text(emit(scenes, index, sources))
    SWIFT.write_text(emit_swift(scenes, index))
    LOOPS.write_text(emit_loops(scenes, index))
    FRAMES.parent.mkdir(parents=True, exist_ok=True)
    FRAMES.write_text(emit_frames(frames))
    print(f"wrote {OUT.relative_to(REPO)} ({len(scenes)} scenes), {FRAMES.relative_to(REPO)} ({len(frames)} frames)"
          f", {SWIFT.relative_to(REPO)} and {LOOPS.relative_to(REPO)}")


if __name__ == "__main__":
    sys.exit(main())
