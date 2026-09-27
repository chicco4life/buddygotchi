import Foundation

/// A `moment` message: something for the device to play once (PROTOCOL.md §3).
/// A rule moment has an `anim`; a mumble has only `say`, which plays over
/// whatever face is showing.
public struct DeviceMoment: Equatable, Sendable {
    public var anim: String?
    public var say: VoiceLine?
    /// Seconds; the device skips it if it can't start in time.
    public var ttl: Int

    public init(anim: String? = nil, say: VoiceLine? = nil, ttl: Int = 5) {
        self.anim = anim
        self.say = say
        self.ttl = ttl
    }

    /// Bubble time after the last syllable (firmware `kBubbleReadMs`).
    static let bubbleReadMs: Int64 = 1200

    /// How long the device plays it, worked out as
    /// firmware/src/app/behaviour.cpp's `onMoment` and `play` do: the
    /// animation's length (`animDuration` in firmware/src/render/anim.cpp),
    /// and a mumble lasts its syllables, plus two beats for a word, at
    /// 60–400 ms each, then 1.2 s for the bubble, when that's longer.
    public var playMs: Int64 {
        var ms: Int64 = switch anim {
        case nil: 0
        case "cheer": 2000
        case "wiggle": 700
        default: 2500
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
        parts.append("\"ttl\":\(ttl)")
        return "{" + parts.joined(separator: ",") + "}"
    }
}
