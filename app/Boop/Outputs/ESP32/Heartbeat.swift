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
    var nudgeRung: Int = 0
    var dots: Int = 0
    var dotAlert: Int?
    var card: Card?
    var scope: String?
    var bubble: String?
    var focus: Bool = false
    var mute: Int = 1
    var posture: DevicePosture?
    var cosmetic: EquippedCosmetic?
    var snap: Snapshot?
    var agents: [AgentCounts]?
    var threads: [ThreadRow]?
    var threadTotal: Int?
    var recent: [FinishRow]?
    var notice: Notice?
    struct ThreadRow: Encodable, Sendable {
        var source: Int; var status: Int; var title: String
        func encode(to encoder: any Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(source); try c.encode(status); try c.encode(deviceTitle(title))
        }
    }
    struct FinishRow: Encodable, Sendable {
        var sequence: Int; var source: Int; var title: String
        func encode(to encoder: any Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(sequence); try c.encode(source); try c.encode(deviceTitle(title))
        }
    }
    struct Notice: Encodable, Sendable {
        var id: Int; var count: Int; var age: Int; var left: Int; var cheer: CheerSize
    }
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
    // Free text is capped at encoding on a character boundary, like Card.
    struct Snapshot: Encodable, Sendable {
        var name: String
        var growth = GrowthSnapshot()
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(name.prefix(utf8Bytes: 23), forKey: .name)
            try c.encode(1, forKey: .level); try c.encode(growth.xp, forKey: .xp); try c.encode(0, forKey: .xpNext)
            try c.encode(growth.streak, forKey: .streak); try c.encode(growth.bestStreak, forKey: .bestStreak)
            try c.encode(growth.daysTogether, forKey: .daysTogether); try c.encode(growth.tasks, forKey: .tasks); try c.encode(growth.today, forKey: .today)
            try c.encode(growth.biggest, forKey: .biggest)
        }
        private enum Keys: String, CodingKey { case name, level, xp, xpNext, streak, tasks, today, biggest
            case bestStreak = "best", daysTogether = "days" }
    }
    private enum CodingKeys: String, CodingKey {
        case v, state, effort, cheer, uhoh, overlay, greetLevel, dots, dotAlert, card
        case threads, threadTotal, recent, notice
        case agents, scope, bubble, gift, focus, mute, nudgeRung, posture, cosmetic, snap, t
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
        // Never clip a scope phrase: the suffix may be a second project.
        try c.encodeIfPresent(scope.flatMap { $0.utf8.count <= 120 ? $0 : nil }, forKey: .scope)
        try c.encodeIfPresent(bubble?.prefix(utf8Bytes: 63), forKey: .bubble)
        try c.encode(false, forKey: .gift) // Retired v2 field; clear gifts on older firmware.
        try c.encode(state == .needsYou ? min(2, max(0, nudgeRung)) : 0, forKey: .nudgeRung)
        try c.encode(focus, forKey: .focus)
        try c.encode(min(3, max(0, mute)), forKey: .mute)
        try c.encodeIfPresent(posture, forKey: .posture)
        try c.encodeIfPresent(cosmetic, forKey: .cosmetic)
        try c.encodeIfPresent(snap, forKey: .snap)
        try c.encodeIfPresent(agents.map { rows in rows.prefix(4).map {
            AgentCounts(source: ["codex", "claude-code", "cursor"].contains($0.source) ? $0.source : "other",
                        working: min(99, max(0, $0.working)), idle: min(99, max(0, $0.idle)))
        } }, forKey: .agents)
        try c.encodeIfPresent(threads.map { Array($0.prefix(12)) }, forKey: .threads)
        try c.encodeIfPresent(threadTotal, forKey: .threadTotal)
        try c.encodeIfPresent(recent.map { Array($0.prefix(6)) }, forKey: .recent)
        try c.encodeIfPresent(notice, forKey: .notice)
        try c.encode(t, forKey: .t)
    }
}

func renderState(from state: BuddyState, defaults: UserDefaults = .standard, now: Double) -> RenderState {
    let c = state.creature
    var frame = RenderState(state: c.state, effort: c.effort, cheer: c.cheer, uhoh: c.uhoh,
        overlay: c.overlay, greetLevel: c.greetLevel, nudgeRung: c.nudgeRung, dots: c.dots, dotAlert: c.dotAlert,
        bubble: c.bubble, focus: c.focus,
        mute: c.focus ? 0 : SoundSettings.volume(defaults: defaults),
        t: Int(now))
    if c.state == .needsYou, let card = c.card {
        frame.card = .needsYou(id: card.id, tool: card.tool, gloss: card.gloss,
            stakes: card.stakes, n: card.index, of: card.count, approval: card.isApproval)
    }
    frame.scope = [.idle, .working, .done].contains(c.state) ? state.workScope : nil
    func sourceIndex(_ source: String) -> Int { ["codex", "claude-code", "cursor"].firstIndex(of: source) ?? 3 }
    frame.threads = state.deviceThreads.prefix(12).map { .init(source: sourceIndex($0.source), status: $0.status, title: $0.title) }
    frame.threadTotal = state.deviceThreads.count
    frame.recent = state.recentFinishes.map { .init(sequence: $0.sequence, source: sourceIndex($0.source), title: $0.title) }
    if let notice = state.completionNotice, now >= notice.startedAt, now < notice.until,
       ![CreatureState.needsYou, .uhoh, .asleep].contains(c.state) {
        frame.notice = .init(id: notice.id, count: notice.count, age: Int(now-notice.startedAt),
            left: Int(notice.until-now), cheer: notice.cheer)
    }
    frame.agents = state.agentCounts
    // Device activity is availability, not duration-based celebration. Keep
    // attention, errors and sleep authoritative; desktop celebrations remain.
    if [.idle, .working, .done].contains(frame.state), !state.agentCounts.isEmpty {
        frame.state = state.agentCounts.contains { $0.working > 0 } ? .working : .idle
        frame.cheer = nil
        frame.bubble = nil
    }
    frame.snap = .init(name: defaults.string(forKey: DefaultsKey.buddyName) ?? "Boop", growth: state.growth)
    frame.cosmetic = state.cosmetic
    return frame
}

func renderStateData(from state: BuddyState, defaults: UserDefaults = .standard, now: Double) -> Data? {
    renderStateData(from: renderState(from: state, defaults: defaults, now: now))
}

/// Frame cap, newline included. The firmware reads lines into a fixed
/// buffer (`data.h`) and drops an oversize line whole, so an overflow does
/// not truncate a frame, it loses it: the buddy would sit on stale state
/// until the next change. Kept below the buffer with headroom for escaping.
let maxHeartbeatBytes = 1536
private let heartbeatEncoder = JSONEncoder()

func renderStateData(from frame: RenderState) -> Data? {
    let encoder = heartbeatEncoder
    var frame = frame
    guard var data = try? encoder.encode(frame) else { return nil }
    if data.count + 1 > maxHeartbeatBytes {
        frame.scope = nil
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    if data.count + 1 > maxHeartbeatBytes {
        frame.snap = nil
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    if data.count + 1 > maxHeartbeatBytes {
        frame.cosmetic = nil
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    // Detail is a bounded preview: preserve the newest finish and expose the
    // full count, rather than losing an entire heartbeat to a long title.
    while data.count + 1 > maxHeartbeatBytes,
          (frame.recent?.count ?? 0) > 1 || (frame.threads?.count ?? 0) > 0 {
        if (frame.recent?.count ?? 0) > 2 { frame.recent?.removeLast() }
        else if (frame.threads?.count ?? 0) > 0 { frame.threads?.removeLast() }
        else { frame.recent?.removeLast() }
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
    }
    // Cut the free text by the overage in one pass (escaping can expand a
    // character several-fold, so re-check once and cut again if needed).
    var attempts = 0
    while data.count + 1 > maxHeartbeatBytes, attempts < 4,
          !(frame.bubble ?? "").isEmpty {
        let overage = data.count + 1 - maxHeartbeatBytes
        func cut(_ text: String?) -> String? {
            guard let text, !text.isEmpty else { return text }
            return text.prefix(utf8Bytes: max(0, text.utf8.count - overage))
        }
        frame.bubble = cut(frame.bubble)
        guard let next = try? encoder.encode(frame) else { return nil }
        data = next
        attempts += 1
    }
    data.append(0x0A)
    assert(data.count <= maxHeartbeatBytes, "ESP32 heartbeat exceeds frame cap")
    guard data.count <= maxHeartbeatBytes else { return nil }
    return data
}

extension EquippedCosmetic {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(skin.prefix(utf8Bytes: 15), forKey: .skin)
        try c.encode(accessory.prefix(utf8Bytes: 15), forKey: .accessory)
        try c.encode(silhouette.prefix(utf8Bytes: 15), forKey: .silhouette)
    }
    private enum Keys: String, CodingKey { case skin, accessory, silhouette }
}
