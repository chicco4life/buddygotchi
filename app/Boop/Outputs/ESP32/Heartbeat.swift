import Foundation

/// Host → device contract: plan/WIRE-V2.md. All free text is capped at encoding.
struct RenderState: Encodable, Sendable {
    let v = 2
    var state: CreatureState
    var effort: CreatureEffort?
    var cheer: CheerSize?
    var uhoh: UhohKind?
    var overlay: CreatureOverlay?
    var greetLevel: Int?
    var dots: Int = 0
    var dotAlert: Int?
    var card: Card?
    var bubble: String?
    var gift: Bool = false
    var giftLine: String?
    var focus: Bool = false
    var mute: Int = 1
    var posture: DevicePosture?
    var cosmetic: Cosmetic?
    var snap: Snapshot?
    var agent: Agent?
    var t: Int

    enum Card: Encodable, Sendable {
        case needsYou(id: String, tool: String, gloss: String, stakes: Stakes, n: Int, of: Int, approval: Bool)
        case system(kind: SystemKind, text: String)
        enum SystemKind: String, Encodable, Sendable { case pair, update }
        private enum CodingKeys: String, CodingKey { case id, tool, gloss, stakes, n, of, approval, kind, text }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .needsYou(id, tool, gloss, stakes, n, of, approval):
                try c.encode(id.prefix(utf8Bytes: 23), forKey: .id)
                try c.encode(tool.prefix(utf8Bytes: 23), forKey: .tool)
                try c.encode(gloss.prefix(utf8Bytes: 63), forKey: .gloss)
                try c.encode(stakes, forKey: .stakes)
                try c.encode(n, forKey: .n)
                try c.encode(of, forKey: .of)
                try c.encode(approval, forKey: .approval)
            case let .system(kind, text):
                try c.encode(kind, forKey: .kind)
                try c.encode(text.prefix(utf8Bytes: 63), forKey: .text)
            }
        }
    }
    struct Cosmetic: Encodable, Sendable {
        @Capped15 var skin: String
        @Capped15 var accessory: String
        @Capped15 var silhouette: String
    }
    struct Snapshot: Encodable, Sendable {
        @Capped23 var name: String
        var level = 0, xp = 0, xpNext = 0, streak = 0, best = 0, rest = 0
        var days = 0, tasks = 0, today = 0
        var biggest: CheerSize = .hop
    }
    struct Agent: Encodable, Sendable {
        @Capped15 var name: String
        @Capped7 var color: String
        @Capped15 var emotion: String
        @Capped40 var say: String
    }
    private enum CodingKeys: String, CodingKey {
        case v, state, effort, cheer, uhoh, overlay, greetLevel, dots, dotAlert, card
        case bubble, gift, giftLine, focus, mute, posture, cosmetic, snap, agent, t
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(state == .working ? effort : nil, forKey: .effort)
        try c.encodeIfPresent(state == .done ? cheer : nil, forKey: .cheer)
        try c.encodeIfPresent(state == .uhoh ? uhoh : nil, forKey: .uhoh)
        try c.encodeIfPresent(overlay, forKey: .overlay)
        try c.encodeIfPresent(greetLevel.map { min(3, max(0, $0)) }, forKey: .greetLevel)
        let count = min(5, max(0, dots))
        try c.encode(count, forKey: .dots)
        try c.encodeIfPresent(dotAlert.flatMap { (0..<count).contains($0) ? $0 : nil }, forKey: .dotAlert)
        try c.encodeIfPresent(card, forKey: .card)
        try c.encodeIfPresent(bubble?.prefix(utf8Bytes: 63), forKey: .bubble)
        try c.encode(gift, forKey: .gift)
        try c.encodeIfPresent(giftLine?.prefix(utf8Bytes: 40), forKey: .giftLine)
        try c.encode(focus, forKey: .focus)
        try c.encode(min(3, max(0, mute)), forKey: .mute)
        try c.encodeIfPresent(posture, forKey: .posture)
        try c.encodeIfPresent(cosmetic, forKey: .cosmetic)
        try c.encodeIfPresent(snap, forKey: .snap)
        try c.encodeIfPresent(card == nil ? agent : nil, forKey: .agent)
        try c.encode(t, forKey: .t)
    }
}

@propertyWrapper struct Capped7: Encodable, Sendable {
    var wrappedValue: String
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue.prefix(utf8Bytes: 7))
    }
}
@propertyWrapper struct Capped15: Encodable, Sendable {
    var wrappedValue: String
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue.prefix(utf8Bytes: 15))
    }
}
@propertyWrapper struct Capped23: Encodable, Sendable {
    var wrappedValue: String
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue.prefix(utf8Bytes: 23))
    }
}
@propertyWrapper struct Capped40: Encodable, Sendable {
    var wrappedValue: String
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue.prefix(utf8Bytes: 40))
    }
}

func renderState(from state: BuddyState, defaults: UserDefaults = .standard, now: Double) -> RenderState {
    let c = state.creature
    var frame = RenderState(state: c.state, effort: c.effort, cheer: c.cheer, uhoh: c.uhoh,
        overlay: c.overlay, greetLevel: c.greetLevel, dots: c.dots, dotAlert: c.dotAlert,
        bubble: c.bubble, gift: c.gift, giftLine: c.giftLine, focus: c.focus,
        mute: (defaults.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true) ? 1 : 0,
        t: Int(now))
    if c.state == .needsYou, let card = c.card {
        frame.card = .needsYou(id: card.id, tool: card.tool, gloss: card.gloss,
            stakes: card.stakes, n: card.index, of: card.count, approval: card.isApproval)
    }
    frame.snap = .init(name: defaults.string(forKey: DefaultsKey.buddyName) ?? "Boop")
    if frame.card == nil, state.prompt == nil, let a = state.agentOverlay {
        frame.agent = .init(name: a.agentId, color: a.color ?? "", emotion: a.emotion, say: a.say ?? "")
    }
    return frame
}

func renderStateData(from state: BuddyState, now: Double) -> Data? {
    renderStateData(from: renderState(from: state, now: now))
}

/// Cap includes the newline. Escaped control characters can expand sixfold.
func renderStateData(from frame: RenderState) -> Data? {
    let encoder = JSONEncoder()
    var frame = frame
    guard var data = try? encoder.encode(frame) else { return nil }
    if data.count + 1 > 1536 {
        frame.snap = nil
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    if data.count + 1 > 1536 {
        frame.cosmetic = nil
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    while data.count + 1 > 1536, !(frame.bubble ?? "").isEmpty || !(frame.giftLine ?? "").isEmpty {
        frame.bubble = frame.bubble.map { String($0.dropLast()) }
        frame.giftLine = frame.giftLine.map { String($0.dropLast()) }
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    data.append(0x0A)
    assert(data.count <= 1536, "ESP32 heartbeat exceeds frame cap")
    guard data.count <= 1536 else { return nil }
    return data
}

extension String {
    /// Trim to at most `maxBytes` UTF-8 bytes, never splitting a character.
    ///
    /// The firmware stores these in fixed `char[N]` buffers and copies with
    /// `strncpy`, which counts BYTES. Bounding by `prefix(n)` counts Swift
    /// Characters, so a hint of 30 emoji is 30 "characters" and 120 bytes: the
    /// device kept the first 63 and left a dangling lead byte, which renders as
    /// garbage and makes the device's own `state` JSON invalid UTF-8 (enough to
    /// crash buddyctl and the HIL suite mid-prompt). Cutting on a Character
    /// boundary here keeps already-flashed devices correct without a reflash.
    func prefix(utf8Bytes maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var out = ""
        var used = 0
        for ch in self {
            let n = String(ch).utf8.count
            if used + n > maxBytes { break }
            out.append(ch)
            used += n
        }
        return out
    }
}
