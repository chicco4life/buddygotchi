import Foundation

/// The `state` message: the whole picture the device draws (PROTOCOL.md §3).
public struct StateSnapshot: Equatable, Sendable {
    public struct Attention: Equatable, Sendable {
        public var agent: String
        public var project: String
        /// The thread's name, which the device shows in the project's
        /// place; `""` for none, and then the line doesn't carry it.
        public var name: String
        public var more: Int
        /// The request shown's number, counting up from a random one each
        /// launch: a new one is a different request, which alerts
        /// (PROTOCOL.md §3).
        /// 0 sends none.
        public var id: Int

        public init(agent: String, project: String, name: String = "", more: Int, id: Int = 0) {
            self.agent = agent
            self.project = project
            self.name = name
            self.more = more
            self.id = id
        }
    }

    public static let version = 1
    /// A protocol line is at most 512 bytes (PROTOCOL.md §2).
    public static let maxLine = 512
    /// The device keeps names in 24-byte fields.
    public static let maxNameBytes = 23

    /// `text` precomposed (NFC) and cut to at most `maxNameBytes` of UTF-8,
    /// on a character boundary. Finder names folders decomposed (e and
    /// U+0301), which the device would draw as "e?"; precomposed, é shows as
    /// e. With `marked`, a cut text ends in "..", within those bytes, so the
    /// device shows it was cut (PROTOCOL.md §3).
    public static func clip(_ text: String, marked: Bool = false) -> String {
        let text = text.precomposedStringWithCanonicalMapping
        guard text.utf8.count > maxNameBytes else { return text }
        let room = marked ? maxNameBytes - 2 : maxNameBytes
        var out = ""
        for ch in text {
            if out.utf8.count + String(ch).utf8.count > room { break }
            out.append(ch)
        }
        return marked ? out + ".." : out
    }

    /// `asleep`, `idle` or `working`.
    public var base: String
    /// What the agents are doing, one of `Act`'s names, only while `base`
    /// is `working` and nothing needs you: the look shows it in working's
    /// place. Nil sends none (PROTOCOL.md §3).
    public var act: String?
    /// Boop's mood, one of the 13 (harness/DECISIONS.md §2.3), which
    /// picks the set of faces the device draws everything in.
    public var mood: String
    public var attn: Attention?
    public var busy: Int
    public var vol: Int
    /// Which variation of the visual shows, from 1: needs you's while
    /// something needs you, else the look's (BEHAVIORS.md §2). The core
    /// picks it at random when the visual changes.
    public var variant: Int

    public init(base: String, act: String? = nil, mood: String, attn: Attention?, busy: Int, vol: Int,
                variant: Int = 1) {
        self.base = base
        self.act = act
        self.mood = mood
        self.attn = attn
        self.busy = busy
        self.vol = vol
        self.variant = variant
    }

    /// The look the device shows when nothing needs you: what the agents
    /// are doing, else the base.
    public var look: String { act ?? base }

    /// The visual the device shows for it: needs you's while something
    /// does, else the look.
    public var visual: String { attn != nil ? "needs_you" : look }

    /// How many sessions need you: `attn`'s and its `more`. The popover's
    /// headline; the line doesn't carry it.
    public var waiting: Int { attn.map { $0.more + 1 } ?? 0 }

    /// One JSON line, keys in the protocol's order.
    public var jsonLine: String {
        var parts: [String] = ["\"t\":\"state\"", "\"v\":\(StateSnapshot.version)", "\"base\":\(json(base))"]
        if let act { parts.append("\"act\":\(json(act))") }
        parts.append("\"mood\":\(json(mood))")
        if let attn {
            let name = attn.name.isEmpty ? "" : ",\"name\":\(json(attn.name))"
            let id = attn.id > 0 ? ",\"id\":\(attn.id)" : ""
            parts.append("\"attn\":{\"agent\":\(json(attn.agent)),\"project\":\(json(attn.project))\(name),\"more\":\(attn.more)\(id)}")
        }
        parts += ["\"busy\":\(busy)", "\"vol\":\(vol)", "\"variant\":\(variant)"]
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func json(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
