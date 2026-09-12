import Foundation

/// Facts and presentation are shared by every occasion. No model-owned timers.
enum MomentKind: String, Codable, Sendable { case start, completed, longRunning, returned }
enum MomentTier: String, Codable, Sendable {
    case face, caption, full
    var rank: Int { self == .face ? 0 : self == .caption ? 1 : 2 }
}
enum MomentExpression: String, Codable, Sendable { case nod, pleased, weary, wave, pull }
struct TurnMoment: Encodable, Equatable, Sendable {
    var id: Int
    var kind: MomentKind
    var tier: MomentTier
    var expression: MomentExpression
    var text: String = ""
    var count: Int = 1
    var startedAt: Double
    var until: Double
    var sessionId: String?
    var turnStartedAt: Double?
    var elapsedMs: Double = 0
    var absenceMs: Double = 0
    var title: String = ""
    var characterLimit: Int { kind == .completed ? 48 : 24 }
    var lines: Int { kind == .completed ? 2 : 1 }
    var wantsText: Bool { !(kind == .completed && tier == .face) }
}

/// One JSON fence in the existing guide. Unknown keys or invalid policy fall
/// back atomically to the bundled policy; owner prose is still preserved.
struct MomentPolicy: Codable, Equatable, Sendable {
    var captionAfterMs: Double = 3000
    var fullAfterMs: Double = 20000
    var faceMs: Double = 1200
    var startMs: Double = 1500
    var remarkMs: Double = 4000
    var captionMs: Double = 4000
    var fullMs: Double = 5000
    var batchMaxMs: Double = 8000
    var batchTailMs: Double = 2000
    var cooldownMs: Double = 3000
    var returnAfterMs: Double = 64800000
    var longAfterMs: [Double] = [300000, 900000]
    var longCooldownMs: Double = 120000
    var expressions: [String: MomentExpression] = [:]
    var fallbacks: [String: String] = [:]

    static func block(in markdown: String) -> Data? {
        guard let start = markdown.range(of: "```boop-policy\n"),
              let end = markdown.range(of: "```", range: start.upperBound..<markdown.endIndex) else { return nil }
        return String(markdown[start.upperBound..<end.lowerBound]).data(using: .utf8)
    }
    static func parse(_ markdown: String, fallback: MomentPolicy) -> MomentPolicy {
        guard let data = block(in: markdown), let patch = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseData = try? JSONEncoder().encode(fallback),
              var base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              Set(patch.keys).isSubset(of: Set(base.keys)) else { return fallback }
        for (key, value) in patch { base[key] = value }
        guard let merged = try? JSONSerialization.data(withJSONObject: base),
              let result = try? JSONDecoder().decode(Self.self, from: merged), result.valid else { return fallback }
        return result
    }
    private var valid: Bool {
        let values = [captionAfterMs, fullAfterMs, faceMs, startMs, remarkMs, captionMs, fullMs, batchMaxMs, batchTailMs, cooldownMs, returnAfterMs, longCooldownMs] + longAfterMs
        return values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 604800000 } &&
            captionAfterMs > 0 && fullAfterMs > captionAfterMs &&
            [faceMs, startMs, remarkMs, captionMs, fullMs, batchTailMs].allSatisfy { (500...8000).contains($0) } &&
            batchMaxMs >= max(captionMs, fullMs) && batchMaxMs <= 8000 &&
            returnAfterMs >= 60000 && longCooldownMs >= 60000 &&
            longAfterMs.count <= 3 && longAfterMs == Array(Set(longAfterMs)).sorted() &&
            longAfterMs.allSatisfy { $0 >= 60000 } &&
            Set(expressions.keys).isSubset(of: ["start", "completed", "full", "longRunning", "returned"]) &&
            Set(fallbacks.keys).isSubset(of: ["start", "completed", "longRunning", "returned"]) &&
            fallbacks.values.allSatisfy { $0.utf8.count <= 63 && $0.count <= 48 && !$0.contains("\n") }
    }
    func tier(_ duration: Double) -> MomentTier { duration < captionAfterMs ? .face : duration < fullAfterMs ? .caption : .full }
    func duration(_ tier: MomentTier) -> Double { tier == .face ? faceMs : tier == .caption ? captionMs : fullMs }
}

/// Conservative host fit check; device measures the actual bundled font too.
/// English companion text uses printable ASCII; unsupported glyphs stay silent.
func momentText(_ text: String, characters: Int, lines: Int, glyphWidth: Int = 12) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text != "SILENT", text.count <= characters, text.utf8.count <= 63,
          text.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else { return nil }
    var row = 1, width = 0
    for word in text.split(separator: " ") {
        let next = word.count * glyphWidth
        guard next <= 408 else { return nil }
        if width > 0 && width + glyphWidth + next > 408 { row += 1; width = next }
        else { width += (width == 0 ? 0 : glyphWidth) + next }
    }
    return row <= lines ? text : nil
}

func updateTurnMoments(_ s: inout InternalState, previous: InternalState, event: BuddyEvent) {
    let now = event.at, policy = s.momentPolicy
    if let m = s.buddy.moment, now >= m.until {
        if m.kind == .completed { s.momentCooldownUntil = max(s.momentCooldownUntil, m.until + policy.cooldownMs) }
        s.buddy.moment = nil
    }
    // Legacy accounting remains, but these are no longer independent displays.
    if s.finishSequence != previous.finishSequence { s.buddy.celebrateUntil = nil }
    let blocked = s.sessions.values.contains { $0.prompt != nil || $0.uhoh != nil || $0.state == .errored }
    if blocked { s.buddy.moment = nil }
    if let m = s.buddy.moment, let id = m.sessionId, m.kind != .completed,
       s.sessions[id]?.workStartedAt != m.turnStartedAt { s.buddy.moment = nil }
    s.longMilestones = s.longMilestones.filter { s.sessions[$0.key]?.workStartedAt != nil }

    func make(_ kind: MomentKind, _ tier: MomentTier, id: String? = nil, elapsed: Double = 0, absence: Double = 0) -> TurnMoment {
        s.momentSequence += 1
        let duration = kind == .completed ? policy.duration(tier) : kind == .start ? policy.startMs : policy.remarkMs
        let key = tier == .full ? "full" : absence > 0 ? "returned" : kind.rawValue
        var m = TurnMoment(id: s.momentSequence, kind: kind, tier: tier,
            expression: policy.expressions[key] ?? .nod, startedAt: now, until: now + duration,
            sessionId: id, turnStartedAt: id.flatMap { s.sessions[$0]?.workStartedAt }, elapsedMs: elapsed, absenceMs: absence,
            title: id.flatMap { s.sessions[$0]?.displayTitle } ?? "")
        if m.wantsText { m.text = momentText(policy.fallbacks[absence > 0 ? "returned" : kind.rawValue] ?? "", characters: m.characterLimit, lines: m.lines, glyphWidth: m.tier == .full ? 16 : 12) ?? "" }
        return m
    }
    var person = false
    switch event { case .turnStarted, .boopArrived: person = true; default: break }
    let absence = person ? previous.memory.lastInteractionAt.map { max(0, now - $0) } ?? 0 : 0
    if person { s.memory.lastInteractionAt = now }
    let returned = person && absence >= policy.returnAfterMs
    var workSignal = false
    switch event {
    case .turnStarted, .toolCalled, .toolResulted: workSignal = true
    case .activitySignal(_, _, _, let signal, _, _): workSignal = signal == .startWorking || signal == .keepWorking
    default: break
    }
    let starts = workSignal ? s.sessions.keys.sorted().filter { previous.sessions[$0]?.workStartedAt == nil && s.sessions[$0]?.workStartedAt != nil } : []
    for id in starts { s.longMilestones[id] = 0 }
    var completedId: String?
    switch event {
    case .turnEnded(_, let id, _, _), .activitySignal(_, let id, _, _, _, _): completedId = id
    default: break
    }
    if s.finishSequence != previous.finishSequence, let duration = s.buddy.lastTaskDurationMs {
        if !blocked {
            let tier = policy.tier(duration)
            if var m = s.buddy.moment, m.kind == .completed {
                m.count += 1
                if tier.rank > m.tier.rank {
                    m.tier = tier; m.expression = policy.expressions[tier == .full ? "full" : "completed"] ?? .pleased
                    m.text = momentText(policy.fallbacks["completed"] ?? "", characters: 48, lines: 2, glyphWidth: tier == .full ? 16 : 12) ?? ""
                    m.until = min(m.startedAt + policy.batchMaxMs, max(m.until, now + policy.duration(tier)))
                } else { m.until = min(m.startedAt + policy.batchMaxMs, max(m.until, now + min(policy.batchTailMs, policy.duration(tier)))) }
                m.elapsedMs = max(m.elapsedMs, duration)
                m.title = s.buddy.recentFinishes.prefix(2).map(\.title).joined(separator: " / ").prefix(utf8Bytes: 96)
                s.buddy.moment = m
            } else if now >= s.momentCooldownUntil {
                s.buddy.moment = make(.completed, tier, id: completedId, elapsed: duration)
            }
        }
    } else if !blocked, let id = starts.first {
        if s.buddy.moment?.kind != .completed { s.buddy.moment = make(.start, .caption, id: id, absence: returned ? absence : 0) }
    } else if returned && !blocked && s.buddy.moment == nil {
        s.buddy.moment = make(.returned, .caption, absence: absence)
    }
    if case .staleTick = event {
        for id in s.sessions.keys.sorted() {
            guard let start = s.sessions[id]?.workStartedAt else { continue }
            let index = s.longMilestones[id, default: 0]
            guard index < policy.longAfterMs.count, now - start >= policy.longAfterMs[index] else { continue }
            s.longMilestones[id] = index + 1 // consumed even while an interruption wins
            if !blocked && s.buddy.moment == nil && now >= s.longMomentAfter &&
                (s.sessions[id]?.state == .working || s.sessions[id]?.state == .thinking) {
                s.buddy.moment = make(.longRunning, .caption, id: id, elapsed: now - start)
                s.longMomentAfter = now + policy.longCooldownMs
            }
        }
    }
    if s.sessions.isEmpty { s.buddy.moment = nil }
    if case .momentText(_, let id, let count, let text) = event,
       var m = s.buddy.moment, m.id == id, m.count == count, now < m.until, !blocked, m.wantsText {
        m.text = momentText(text, characters: m.characterLimit, lines: m.lines, glyphWidth: m.tier == .full ? 16 : 12) ?? ""
        s.buddy.moment = m
    }
}
