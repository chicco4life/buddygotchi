import AgentHooks
import Foundation

/// The way every event goes (harness/HARNESS.md §2), with no queue: it's
/// recorded in the transcript and folded into the view; an agent's event or
/// a poke goes to the core, and what the core did by rule is recorded after
/// it; then the view events it made are gated. The runtime runs one on
/// `home`; replays, evals and tests drive their own.
public final class Pipeline {
    public let core: Core
    public let transcript: Log
    public let view: TranscriptView
    /// Whether there's a brain to wake (Jev's key): without one, no view
    /// event wakes it (harness/EVENTS.md §6).
    public var brain = true
    /// Every event as it's recorded, and every view event as it's gated,
    /// for debug mode.
    public var onRecord: ((Event) -> Void)?
    public var onView: ((ViewEvent) -> Void)?

    /// What one input did.
    public struct Step: Sendable {
        /// The core's effects, its records included.
        public var effects: [CoreEffect] = []
        /// Every event recorded, stamped: the input's first.
        public var recorded: [Event] = []
        /// The view events made, gated.
        public var views: [ViewEvent] = []

        /// The view events that wake the brain.
        public var waking: [ViewEvent] { views.filter(\.wakesBrain) }
    }

    public init(core: Core, transcript: Log = Transcript.log(), view: TranscriptView) {
        self.core = core
        self.transcript = transcript
        self.view = view
    }

    /// An agent's event, from an adapter: its `ts` is now. It's recorded
    /// without what its session already has (`Core.unrepeated`).
    @discardableResult
    public func agent(_ event: Event) -> Step {
        var step = Step()
        let e = record(core.unrepeated(event), &step)
        run(core.handle(e), &step)
        return gated(step)
    }

    /// The device's poke: the device has already played it.
    @discardableResult
    public func poke(at now: Int64, finish: ThreadRef? = nil) -> Step {
        var step = Step()
        let e = record(Event(ts: now, source: .device, type: .poke, specificType: "input"), &step)
        run(core.poke(at: now, seq: e.seq, finish: finish), &step)
        // A tap that opens a finished turn's thread means "take me there",
        // not a poke: it doesn't wake the brain (harness/EVENTS.md §6).
        return gated(step, wake: finish == nil)
    }

    /// What you said to Boop on push-to-talk, heard by the Mac's mic
    /// after `by`'s button (`device` or `app`), cut to 2,000 characters as
    /// a prompt is on the wire (harness/EVENTS.md §2). It wakes the brain
    /// even while something needs you (§6).
    @discardableResult
    public func said(_ words: String, by: Core.Talker, at now: Int64) -> Step {
        var step = Step()
        let cut = words.count > HookLine.maxMessage ? String(words.prefix(HookLine.maxMessage)) : words
        record(Event(ts: now, source: .mic, type: .talk, specificType: by.rawValue, data: ["words": .string(cut)]), &step)
        return gated(step)
    }

    /// You stepping away from the Mac or coming back, as the presence
    /// detector decided (harness/EVENTS.md §2.1): recorded and folded, but
    /// never the core's. Only a back wakes the brain.
    @discardableResult
    public func presence(_ event: Event) -> Step {
        var step = Step()
        record(event, &step)
        return gated(step)
    }

    /// The core's timers, then a heartbeat if one is due.
    @discardableResult
    public func tick(at now: Int64) -> Step {
        var step = Step()
        run(core.tick(at: now), &step)
        if let beat = view.heartbeat(at: now) { record(beat, &step) }
        return gated(step)
    }

    /// Records an event nothing else acts on, such as an action's: it can
    /// make no view event that wakes the brain.
    @discardableResult
    public func record(_ event: Event) -> Event {
        var step = Step()
        let e = record(event, &step)
        _ = gated(step, wake: false)
        return e
    }

    /// Records the core's effects' events; the caller carries out the rest.
    public func run(_ effects: [CoreEffect], _ step: inout Step) {
        step.effects += effects
        for case .record(let e) in effects { record(e, &step) }
    }

    /// Folds the transcript's last days into the view and the core, as a
    /// launch reads them back, and returns how many events it read. A
    /// started action with no end can't end now (its handle went with the
    /// last launch), so it's ended here as failed.
    @discardableResult
    public func readBack(now: Int64) -> Int {
        let read = transcript.load(now: now)
        for e in read {
            view.take(e)
            core.replay(e)
        }
        for (seq, name) in view.openActions() {
            record(Event.ended(seq, action: name, by: transcript.event(seq)?["by"]?.string ?? "brain",
                               failed: "Boop restarted", at: now))
        }
        return read.count
    }

    @discardableResult
    func record(_ event: Event, _ step: inout Step) -> Event {
        let e = transcript.append(event, now: event.at)
        step.recorded.append(e)
        onRecord?(e)
        step.views += view.take(e)
        return e
    }

    /// Why a view event may not wake the brain now, or nil if it may: it
    /// needs a brain; nothing but what you said wakes it while something
    /// needs you (a tap then opens the thread); and a poke doesn't while
    /// the brain's reaction to its run is in progress, with the mood
    /// unchanged (harness/EVENTS.md §6).
    public func whyNotWake(_ v: ViewEvent) -> String? {
        if !brain { return "no brain" }
        if !TranscriptView.wakesWhileNeeded.contains(v.type), let why = core.needsYouBlock { return why }
        if v.type == .poke && view.pokesAnswered { return "Boop is answering these pokes" }
        return nil
    }

    func gated(_ step: Step, wake: Bool = true) -> Step {
        var step = step
        step.views = view.gate(step.views) { wake && self.whyNotWake($0) == nil }
        for v in step.views { onView?(v) }
        return step
    }
}
