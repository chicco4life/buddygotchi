"""`boopctl dash`: Boop's live dashboard (plan/DASHBOARD.md). The state with
the face, the harness's latest pass and a timeline, all from debug.jsonl,
and keys that force a mood, a reaction or an animation, or preview any look
on the dashboard's own sim."""
from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any, Callable, Protocol

from rich.table import Table
from rich.text import Text
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, VerticalScroll
from textual.message import Message
from textual.screen import ModalScreen
from textual.widgets import Footer, Label, OptionList, RichLog, Static

from boopctl_lib.common import ANIMS, send_line
from boopctl_lib.dash import controls
from boopctl_lib.device import DeviceError
from boopctl_lib.dash.feed import Board, Follower, clock, kind

STYLES = {"event": "bold", "pass": "cyan", "ok": "green", "fail": "red", "sent": "magenta", "status": "yellow",
          "head": "bold underline", "dim": "grey62"}
# Preview resends its state this often: the device shows the no-app look
# after 30 s without one (PROTOCOL.md §3).
PREVIEW_RESEND_S = 10
LEAVE = "leave Preview"


class Face(Protocol):
    whole: bool

    def start(self) -> None: ...
    def stop(self) -> None: ...
    def send(self, message: dict) -> None: ...
    def restart(self, state: dict | None) -> None: ...


class Frame(Message):
    """From the sim's thread, without waiting on the app: a drawn frame, or
    why the sim stopped."""

    def __init__(self, text: Text | None, error: str = "") -> None:
        super().__init__()
        self.text, self.error = text, error

    def can_replace(self, message: Message) -> bool:
        # A frame the app hasn't drawn yet is stale once a newer one comes.
        return isinstance(message, Frame) and message.text is not None and self.text is not None


class Picker(ModalScreen[str | None]):
    """One choice from a list; Escape cancels."""

    BINDINGS = [Binding("escape", "dismiss(None)", "cancel")]
    DEFAULT_CSS = """
    Picker { align: center middle; }
    Picker > Label { width: 70; background: $panel; padding: 0 1; }
    Picker > OptionList { width: 70; height: auto; max-height: 16; }
    """

    def __init__(self, title: str, choices: list[str]) -> None:
        super().__init__()
        self.title_text, self.choices = title, choices

    def compose(self) -> ComposeResult:
        yield Label(self.title_text)
        yield OptionList(*self.choices)

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        self.dismiss(self.choices[event.option_index])


class StateView(ModalScreen[None]):
    """The latest pass's whole state text."""

    BINDINGS = [Binding("escape,s,q", "dismiss(None)", "close")]
    DEFAULT_CSS = "StateView { background: $background 90%; } StateView > VerticalScroll { border: round $accent; }"

    def __init__(self, state: str) -> None:
        super().__init__()
        self.state = state

    def compose(self) -> ComposeResult:
        with VerticalScroll() as scroll:
            scroll.border_title = "the state Jev read (s or Escape closes)"
            yield Static(Text(self.state))


class Dash(App[None]):
    TITLE = "Boop dashboard"
    ENABLE_COMMAND_PALETTE = False
    CSS = """
    #top { height: auto; }
    #face { width: auto; min-width: 85; height: auto; min-height: 24; border: round $accent; }
    #facts { width: 1fr; height: 24; border: round $primary; padding: 0 1; }
    #harness { height: 1fr; border: round $primary; padding: 0 1; }
    #timeline { height: 1fr; border: round $primary; }
    """
    BINDINGS = [
        Binding("m", "mood", "mood"),
        Binding("r", "react", "react"),
        Binding("a", "animate", "animate"),
        Binding("p", "preview", "preview"),
        Binding("s", "state", "state"),
        Binding("z", "whole", "whole screen"),
        Binding("q", "quit", "quit"),
    ]

    def __init__(self, debug_log: Path, socket_path: str,
                 make_face: Callable[[Callable[[Text], None], Callable[[str], None]], Face] | None = None) -> None:
        super().__init__()
        self.follower = Follower(debug_log)
        self.socket_path = socket_path
        self.board = Board()
        self.pending = controls.Pending()
        self.first = True
        self.look: str | None = None  # Preview's look; None is live
        self.look_mood: str | None = None  # Preview's mood; None is the app's
        self.face_lines = -1  # the drawn face's height, less one
        self.face = make_face(lambda text: self.post_message(Frame(text)),
                              lambda why: self.post_message(Frame(None, why))) if make_face else None

    def compose(self) -> ComposeResult:
        # Kept, since queries only search the screen on top, such as a picker.
        self.face_view = Static("starting boop-sim…" if self.face else "no sim", id="face")
        self.facts = Static(id="facts")
        self.harness = Static(id="harness-text")
        self.timeline = RichLog(id="timeline", wrap=True, max_lines=5000)
        with Horizontal(id="top"):
            yield self.face_view
            yield self.facts
        with VerticalScroll(id="harness") as harness:
            harness.border_title = "harness · the latest pass"
            yield self.harness
        yield self.timeline
        yield Footer()

    def on_mount(self) -> None:
        self.facts.border_title = f"state · {self.follower.path.parent}"
        self.timeline.border_title = "timeline"
        self.title_face()
        if self.face:
            self.face.start()
        self.poll()
        self.set_interval(0.25, self.poll)
        self.set_interval(PREVIEW_RESEND_S, self.keep_preview)

    def on_unmount(self) -> None:
        if self.face:
            self.face.stop()

    # Reading debug.jsonl.

    def poll(self) -> None:
        restarted, lines = self.follower.read()
        if restarted:
            self.board = Board()
            self.timeline.write(Text("— debug.jsonl started again: Boop restarted —", "yellow"))
        # At the start and after a restart the sim gets only the latest
        # state, never old moments; after that, every line as it lands.
        catching_up = self.first or restarted
        live = self.face and self.look is None
        for line in lines:
            row = self.board.apply(line)
            if row:
                self.timeline.write(Text(f"{clock(line.get('received_at_ms', 0))} {row[1]}", STYLES[row[0]]))
            if done := self.pending.seen(line):
                self.notify(f"{done}: landed")
            if live and not catching_up and kind(line) == "sent":
                self.face.send(line["sent"])
        if live and catching_up and (lines or restarted):
            self.face.restart(self.board.state)
        self.first = False
        for late in self.pending.late():
            self.notify(f"{late}: nothing in debug.jsonl within {controls.CONFIRM_S:g} s. Is Boop running with --debug?",
                        severity="warning")
        if lines or restarted or not self.board.questions:
            self.show_panes()

    def show_panes(self) -> None:
        facts = Table.grid(padding=(0, 1))
        facts.add_column(style="bold", no_wrap=True)
        facts.add_column()
        for name, value in self.board.facts():
            facts.add_row(name, value)
        self.facts.update(facts, layout=False)  # its height is fixed
        if self.follower.path.exists():
            harness = Text("\n").join(Text(text, STYLES[style]) for style, text in self.board.harness())
        else:
            harness = Text(f"waiting for {self.follower.path} (is Boop running with --debug?)", "yellow")
        self.harness.update(harness)

    def on_frame(self, frame: Frame) -> None:
        if frame.text is None:
            self.notify(frame.error, severity="error")
            return
        # Laid out again only when its size changes: the first frame, and `z`.
        lines = frame.text.plain.count("\n")
        self.face_view.update(frame.text, layout=lines != self.face_lines)
        self.face_lines = lines

    def title_face(self) -> None:
        mode = f"PREVIEW: {self.look}" if self.look else "live"
        self.face_view.border_title = f"face · {mode}" + (" · whole screen" if self.face and self.face.whole else "")

    # The keys.

    def command(self, line: dict[str, Any]) -> None:
        if why := send_line(self.socket_path, line):
            self.notify(why, severity="error")
        else:
            self.pending.add(line)

    async def pick(self, title: str, choices: list[str]) -> str | None:
        return await self.push_screen_wait(Picker(title, choices))

    def questions(self, action: str) -> list[dict]:
        asked = controls.asked_by(self.board.questions, action)
        if not asked:
            self.notify("no questions line in debug.jsonl yet. Is Boop running with --debug?", severity="warning")
        return asked

    @work
    async def action_mood(self) -> None:
        asked = self.questions("mood")
        mood = asked and await self.pick("Preview a mood" if self.look else "Set the mood", controls.options(asked[0]))
        if mood and not self.look:
            self.command({"dev": "mood", "mood": mood})
        elif mood and self.face:
            self.look_mood = mood
            self.keep_preview()

    @work
    async def action_react(self) -> None:
        asked = self.questions("react")
        if not asked:
            return
        if self.look:
            # Preview: any reaction, its face, how long it holds and a mumble,
            # straight to the dashboard's sim.
            face = await self.pick("Preview a reaction: the face", [o for o in controls.options(asked[0]) if o != "none"])
            holds = [o for q in asked if q["key"] == "react.loops" for o in controls.options(q)]
            hold = face and (await self.pick("…how long it holds", holds) if holds else "once")
            words = [o for q in asked if q["key"].startswith("word.") for o in controls.options(q) if o != "none"]
            word = hold and await self.pick("…and its word", ["none"] + words)
            if word and self.face:
                loops = holds.index(hold) + 1 if hold in holds else 1
                try:  # boopdev runs off the event loop, so the face keeps moving
                    line = await asyncio.to_thread(controls.preview_mumble, face, None if word == "none" else word, loops)
                    self.face.send(line)
                except DeviceError as exc:
                    self.notify(str(exc), severity="error")
            return
        choices = {}
        for q in asked:
            choice = await self.pick(f"Force a pass · {q['key']}: {q['text']}", controls.options(q))
            if choice is None:
                return
            choices[q["key"]] = choice
        self.command({"dev": "answer", "answers": choices})

    @work
    async def action_animate(self) -> None:
        anim = await self.pick("Play an animation" + (" (Preview)" if self.look else ""), ANIMS)
        if not anim:
            return
        if not self.look:
            self.command({"dev": "moment", "anim": anim})
        elif self.face:
            self.face.send({"t": "moment", "anim": anim})

    @work
    async def action_preview(self) -> None:
        pick = await self.pick("Preview a look on the dashboard's sim only", controls.LOOKS + ([LEAVE] if self.look else []))
        if not pick or not self.face:
            return
        if pick == LEAVE:
            self.look = self.look_mood = None
            self.face.restart(self.board.state)
        else:
            self.look = pick
            self.keep_preview()
        self.title_face()

    def keep_preview(self) -> None:
        """Preview's look on the sim: when it changes, and every
        PREVIEW_RESEND_S."""
        if self.look and self.face:
            self.face.send(controls.preview_state(self.board.state, self.look, self.look_mood))

    def action_state(self) -> None:
        state = (self.board.last_pass or {}).get("pass", {}).get("state")
        if state:
            self.push_screen(StateView(state))
        else:
            self.notify("the latest pass has no state (none yet, or it was forced)")

    def action_whole(self) -> None:
        if self.face:
            self.face.whole = not self.face.whole
            self.title_face()


def run(state_dir: Path, socket_path: str, sim_program: str) -> None:
    from boopctl_lib.dash.face import SimFace

    Dash(state_dir / "debug.jsonl", socket_path,
         make_face=lambda on_frame, on_error: SimFace(sim_program, on_frame, on_error)).run()
