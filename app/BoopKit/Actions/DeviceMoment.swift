import Foundation

/// A `moment` message: something for the device to play (PROTOCOL.md §3).
/// A rule moment has an `anim`; a mumble has only `say`, which plays over
/// whatever face is showing. A brain mumble also has `mood`, its
/// expression: the device draws that mood's version of the look while the
/// moment plays. The rules' moments never carry one. Whoever plays the
/// cheer or a face says how many `loops` of its design. A moment the app
/// waits on has an `id`, which the device's `ended` gives back (§4). A
/// cheer for a thread's turn says `who`: the device names it in the strip
/// while the cheer plays.
public struct DeviceMoment: Equatable, Sendable {
    /// The agent and thread a cheer is for.
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

    public var anim: String?
    public var say: VoiceLine?
    public var mood: String?
    /// With the cheer, how many times its design plays; with a `mood` and
    /// no animation, how many loops of the design it's drawn in the face
    /// holds. Nil sends none, which the device reads as 1.
    public var loops: Int?
    /// The animation's variation (the cheer's), from 1; nil sends none,
    /// which the device reads as 1.
    public var variant: Int?
    /// With the cheer, whose turn it cheers; nil sends none.
    public var who: Who?
    public var id: Int?
    /// With task_complete, the turn's outcome: `success` or `failure`;
    /// the device plays a variation for it. Nil sends none.
    public var outcome: String?
    /// With starting, what started: `new_task`, `session` or
    /// `continuation`. Nil sends none.
    public var ctx: String?

    public init(anim: String? = nil, say: VoiceLine? = nil, mood: String? = nil, loops: Int? = nil,
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

    /// The animations the device plays (BEHAVIORS.md §5), besides
    /// `listening`, which only push-to-talk plays (§3.3). `cheer` is the
    /// old name of task_complete's success, which the device still reads.
    public static let anims = ["cheer", "wiggle", "task_complete", "reply_ready", "starting", "helper_return",
                               "error", "stopped", "poked", "tap_spam"]

    /// The design state an animation plays: its own name, the cheer's
    /// task_complete, and none for the wiggle.
    public static func designState(_ anim: String) -> String? {
        switch anim {
        case "cheer": "task_complete"
        case "wiggle": nil
        default: anims.contains(anim) ? anim : nil
        }
    }
    /// Push-to-talk's face, from the mic turning on until the reply.
    public static let listening = "listening"

    /// The most `loops` the device plays (firmware `Behaviour::kMaxLoops`).
    public static let maxLoops = 6

    /// Bubble time after the last syllable (firmware `kBubbleReadMs`).
    static let bubbleReadMs: Int64 = 1200
    /// A tap's wiggle (firmware `render::kWiggleMs`).
    static let wiggleMs: Int64 = 700

    /// How long the device plays it at most while it shows `look` (a
    /// `state`'s base, or `task_complete` while the cheer plays) in Boop's
    /// `mood`, worked out as firmware/src/app/behaviour.cpp's `onMoment`
    /// and `play` do: the cheer is its loops of its design, a wiggle
    /// 0.7 s; a face with no animation holds its loops of the look's
    /// design, which ends on a loop boundary, so this long or less, timed
    /// by the look's longest variation, since the device's variations take
    /// turns (BEHAVIORS.md §2); and a mumble lasts its syllables, plus two
    /// beats for a word, at 60–400 ms each, then 1.2 s for the bubble, when
    /// that's longer.
    public func playMs(look: String, mood: String) -> Int64 {
        let loops = Int64(Swift.max(1, Swift.min(Self.maxLoops, self.loops ?? 1)))
        var ms: Int64 = 0
        if anim == "wiggle" {
            ms = Self.wiggleMs
        } else if let anim, let state = Self.designState(anim) {
            ms = loops * FaceLoops.ms(mood: self.mood ?? mood, state: state, variant: variant ?? 1)
        }
        // (the device doesn't play an animation it doesn't know)
        if !Self.anims.contains(anim ?? ""), let face = self.mood {
            ms = loops * (1...FaceLoops.count(mood: face, state: look)).map { FaceLoops.ms(mood: face, state: look, variant: $0) }.max()!
        }
        return Swift.max(ms, sayMs)
    }

    /// How long its mumble plays: its syllables, plus two beats for a word,
    /// at 60–400 ms each, then 1.2 s for the bubble; 0 with none.
    public var sayMs: Int64 {
        guard let say, say.syllableCount > 0 else { return 0 }
        let beats = Int64(say.syllableCount + (say.word?.isEmpty == false ? 2 : 0))
        return beats * Int64(Swift.max(60, Swift.min(400, say.ms))) + DeviceMoment.bubbleReadMs
    }

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
