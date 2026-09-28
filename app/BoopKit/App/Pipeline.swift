import Foundation

/// The way every event goes (harness/HARNESS.md §2), with no queue: it's
/// recorded in the transcript and folded into the view; an agent's event or
/// a poke goes to the core, and what the core did by rule is recorded after
/// it; then the view events it made are gated. The runtime runs one on
/// `home`; replays, evals and tests drive their own.
public final class Pipeline {
    public let core: Core
    public let transcript: Transcript
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

    public init(core: Core, transcript: Transcript = Transcript(), view: TranscriptView) {
        self.core = core
        self.transcript = transcript
        self.view = view
    }

    /// An agent's event, from an adapter: its `ts` is now.
    @discardableResult
    public func agent(_ event: Event) -> Step {
        var step = Step()
        let e = record(event, &step)
        run(core.handle(e), &step)
        return gated(step)
    }

    /// The device's poke: the device has already wiggled.
    @discardableResult
    public func poke(at now: Int64) -> Step {
        var step = Step()
        let e = record(Event(ts: now, source: .device, type: .poke, specificType: "input"), &step)
        run(core.input(.tap, at: now, seq: e.seq), &step)
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

    /// Folds the events a launch read back into the view. A started action
    /// with no end can't end now (its handle went with the last launch),
    /// so it's ended here as failed.
    public func replay(_ events: [Event], now: Int64) {
        for e in events { view.take(e) }
        for (seq, name) in view.openActions() {
            record(Event(ts: now, source: .boop, type: .action, phase: .end, specificType: name,
                         data: ["for": .int(Int64(seq)), "outcome": "failed", "why": "Boop restarted"]))
        }
    }

    @discardableResult
    func record(_ event: Event, _ step: inout Step) -> Event {
        let e = transcript.append(event)
        step.recorded.append(e)
        onRecord?(e)
        step.views += view.take(e)
        return e
    }

    /// Why a view event may not wake the brain now, or nil if it may: it
    /// needs a brain; nothing but a poke wakes it while something needs
    /// you; and a poke doesn't while the brain's reaction to its run is in
    /// progress, with the mood unchanged (harness/EVENTS.md §6).
    public func whyNotWake(_ v: ViewEvent) -> String? {
        if !brain { return "no brain" }
        if !TranscriptView.wakesWhileNeeded.contains(v.type) && core.needsYouShowing { return "something needs you" }
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
