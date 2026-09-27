import Foundation

/// A `moment` message: something for the device to play (PROTOCOL.md §3).
/// A rule moment has an `anim`; a mumble has only `say`, which plays over
/// whatever face is showing. A brain mumble also has `mood`, its
/// expression: the device draws that mood's version of the look while the
/// moment plays. The rules' moments never carry one. Whoever plays the
/// cheer or a face says how many `loops` of its design. A moment the app
/// waits on has an `id`, which the device's `ended` gives back (§4).
public struct DeviceMoment: Equatable, Sendable {
    public var anim: String?
    public var say: VoiceLine?
    public var mood: String?
    /// With the cheer, how many times its design plays; with a `mood` and
    /// no animation, how many loops of the design it's drawn in the face
    /// holds. Nil sends none, which the device reads as 1.
    public var loops: Int?
    public var id: Int?

    public init(anim: String? = nil, say: VoiceLine? = nil, mood: String? = nil, loops: Int? = nil, id: Int? = nil) {
        self.anim = anim
        self.say = say
        self.mood = mood
        self.loops = loops
        self.id = id
    }

    /// The animations the device plays (BEHAVIORS.md §5).
    public static let anims = ["cheer", "wiggle"]

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
    /// design, which ends on a loop boundary, so this long or less; and a
    /// mumble lasts its syllables, plus two beats for a word, at 60–400 ms
    /// each, then 1.2 s for the bubble, when that's longer.
    public func playMs(look: String, mood: String) -> Int64 {
        let loops = Int64(Swift.max(1, Swift.min(Self.maxLoops, self.loops ?? 1)))
        var ms: Int64 = switch anim {
        case nil: 0
        case "cheer": loops * FaceLoops.ms(mood: self.mood ?? mood, state: "task_complete")
        case "wiggle": Self.wiggleMs
        default: 0  // the device doesn't play an animation it doesn't know
        }
        if !Self.anims.contains(anim ?? ""), let face = self.mood {
            ms = loops * FaceLoops.ms(mood: face, state: look)
        }
        if let say, say.syllableCount > 0 {
            let beats = Int64(say.syllableCount + (say.word?.isEmpty == false ? 2 : 0))
            ms = Swift.max(ms, beats * Int64(Swift.max(60, Swift.min(400, say.ms))) + DeviceMoment.bubbleReadMs)
        }
        return ms
    }

    public var jsonLine: String {
        var parts = ["\"t\":\"moment\""]
        if let anim { parts.append("\"anim\":\"\(anim)\"") }
        if let say { parts.append("\"say\":" + say.json) }
        if let mood { parts.append("\"mood\":\"\(mood)\"") }
        if let loops { parts.append("\"loops\":\(loops)") }
        if let id { parts.append("\"id\":\(id)") }
        return "{" + parts.joined(separator: ",") + "}"
    }
}
