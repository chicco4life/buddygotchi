import Foundation

/// A `moment` message: something for the device to play (PROTOCOL.md §3).
/// A rule moment has an `anim`; a brain reaction has a `say` and a `mood`,
/// its expression: the device draws that mood's version of the look while
/// the moment plays, and says the take in `say`, if there is one, over it. The rules' moments never carry one. Whoever plays an
/// animation or a face says how many `loops` of its design. A moment the
/// app waits on has an `id`, which the device's `ended` gives back (§4). The
/// finish for a thread's turn says `who`: the device names it in the strip
/// while the finish plays.
public struct DeviceMoment: Equatable, Sendable {
    /// The agent and thread the finish is for.
    public struct Who: Equatable, Sendable {
        /// `claude` or `codex`.
        public var agent: String
        /// The thread's name, cut as `StateSnapshot.clip` cuts names.
        public var thread: String

        public init(agent: String, thread: String) {
            self.agent = agent
            self.thread = StateSnapshot.clip(thread, marked: true)
        }
    }

    /// What a brain reaction says: a recorded take, or nothing. A reaction
    /// always has one, even with no take: it's the reply that ends
    /// push-to-talk's `listening` (PROTOCOL.md §3).
    public struct Say: Equatable, Sendable {
        public var take: Take?

        public init(take: Take?) {
            self.take = take
        }

        /// The `say` object: `{"take":"new.d02"}`, or `{}`.
        public var json: String { take.map { "{\"take\":\(Event.quote($0.id))}" } ?? "{}" }
    }

    public var anim: String?
    public var say: Say?
    public var mood: String?
    /// With an animation, how many times its design plays; with a `mood`
    /// and no animation, how many loops of the design it's drawn in the
    /// face holds. Nil sends none, which the device reads as 1.
    public var loops: Int?
    /// The animation's variation, from 1; nil sends none, and the device
    /// picks one for the moment's facts.
    public var variant: Int?
    /// With the finish, whose turn it was; nil sends none.
    public var who: Who?
    public var id: Int?
    /// With task_complete, the turn's outcome: `success` or `failure`;
    /// the device plays a variation for it. Nil sends none.
    public var outcome: String?
    /// With starting, what started: `new_task`, `session` or
    /// `continuation`. Nil sends none.
    public var ctx: String?

    public init(anim: String? = nil, say: Say? = nil, mood: String? = nil, loops: Int? = nil,
                variant: Int? = nil, who: Who? = nil, id: Int? = nil, outcome: String? = nil, ctx: String? = nil) {
        self.anim = anim
        self.say = say
        self.mood = mood
        self.loops = loops
        self.variant = variant
        self.who = who
        self.id = id
        self.outcome = outcome
        self.ctx = ctx
    }

    /// The animations the device plays (BEHAVIORS.md §5), each its design
    /// state's name, besides `listening`, which only push-to-talk plays
    /// (§3.3). The device also reads older names the app no longer sends
    /// (PROTOCOL.md §3).
    public static let anims = ["task_complete", "reply_ready", "starting", "helper_return",
                               "error", "stopped", "poked", "tap_spam"]
    /// Push-to-talk's face, from the mic turning on until the reply.
    public static let listening = "listening"

    /// The most `loops` the device plays (firmware `Behaviour::kMaxLoops`).
    public static let maxLoops = 6

    /// Bubble time after the take (firmware `kBubbleReadMs`).
    static let bubbleReadMs: Int64 = 1200

    /// Its animation's design, in the mood it's drawn in, and the
    /// variations (from 1) the device may play of it: `variant` when it's
    /// one of those for the moment's facts (task_complete's outcome,
    /// starting's context), else any of those, since the device then picks
    /// one (PROTOCOL.md §3). Nil for no animation, or one the device
    /// doesn't play.
    func design(mood: String) -> (mood: String, state: String, variants: [Int])? {
        guard let state = anim, Self.anims.contains(state) else { return nil }
        let face = self.mood ?? mood
        let fit = FaceLoops.variants(mood: face, state: state, outcome: state == "task_complete" ? outcome : nil,
                                     ctx: state == "starting" ? ctx : nil)
        return (face, state, variant.map { fit.contains($0) ? [$0] : fit } ?? fit)
    }

    /// How long the device plays it at most while it shows `look` (a
    /// `state`'s look, or an animation's design while one plays) in Boop's
    /// `mood`, worked out as firmware/src/app/behaviour.cpp's `onMoment`
    /// and `play` do: an animation is its loops of its design, in its own
    /// mood, the longest of the variations it may play; with a line, which
    /// starts at the design's voice window, at least until the line and its
    /// bubble end (`lineStartMs`). A face with no animation holds its loops
    /// of the look's design, which ends on a loop boundary, so this long or
    /// less, timed by the look's longest variation, since the device's
    /// variations take turns (BEHAVIORS.md §2); and a take lasts its
    /// length, then 1.2 s for the bubble, when that's longer.
    public func playMs(look: String, mood: String) -> Int64 {
        let loops = Int64(Swift.max(1, Swift.min(Self.maxLoops, self.loops ?? 1)))
        var ms: Int64 = 0
        if let d = design(mood: mood) {
            ms = loops * d.variants.map { FaceLoops.ms(mood: d.mood, state: d.state, variant: $0) }.max()!
        } else if let face = self.mood {
            // A face on the look (the device plays no animation it doesn't know).
            ms = loops * (1...FaceLoops.count(mood: face, state: look)).map { FaceLoops.ms(mood: face, state: look, variant: $0) }.max()!
        }
        return Swift.max(ms, sayMs == 0 ? 0 : lineStartMs(mood: mood) + sayMs)
    }

    /// When its line starts on the device, from the moment's start: with an
    /// animation, at its design's voice window (VOICE.md §10), the latest of
    /// the variations it may play, in its own mood; with none, at once.
    public func lineStartMs(mood: String) -> Int64 {
        guard let d = design(mood: mood) else { return 0 }
        return d.variants.map { FaceLoops.voiceMs(mood: d.mood, state: d.state, variant: $0) }.max()!
    }

    /// How long the device plays a tap (BEHAVIORS.md §3.3): `mood`'s poked
    /// design, or tap_spam's from the `MomentSchedule.tapSpamFrom`-th tap
    /// of a run (`run`, from 1) on, the longest of its variations, since
    /// the device picks one.
    public static func tapMs(mood: String, run: Int) -> Int64 {
        DeviceMoment(anim: run >= MomentSchedule.tapSpamFrom ? "tap_spam" : "poked").playMs(look: "idle", mood: mood)
    }

    /// How long its take plays, then 1.2 s for the bubble; 0 with none.
    public var sayMs: Int64 {
        guard let take = say?.take else { return 0 }
        return Int64(take.ms) + DeviceMoment.bubbleReadMs
    }

    /// How long a brain reaction with no animation keeps the next one from
    /// replacing its face (ARCHITECTURE.md §3.2): its take and bubble, or
    /// for one that says nothing, as long as a bubble shows, so a silent
    /// face is seen before the next replaces it.
    public var faceFirstMs: Int64 { say?.take == nil ? DeviceMoment.bubbleReadMs : sayMs }

    public var jsonLine: String {
        var parts = ["\"t\":\"moment\""]
        if let anim { parts.append("\"anim\":\"\(anim)\"") }
        if let say { parts.append("\"say\":" + say.json) }
        if let mood { parts.append("\"mood\":\"\(mood)\"") }
        if let loops { parts.append("\"loops\":\(loops)") }
        if let variant { parts.append("\"variant\":\(variant)") }
        if let who {
            parts.append("\"who\":{\"agent\":\(Event.quote(who.agent)),\"thread\":\(Event.quote(who.thread))}")
        }
        if let outcome { parts.append("\"outcome\":\(Event.quote(outcome))") }
        if let ctx { parts.append("\"ctx\":\(Event.quote(ctx))") }
        if let id { parts.append("\"id\":\(id)") }
        return "{" + parts.joined(separator: ",") + "}"
    }
}
