import Foundation

typealias Traits = [String: Int]
enum VoiceRegister: String, CaseIterable, Sendable {
    case earnest, wry, cheeky
    init(cheek: Int) { self = cheek < 96 ? .earnest : cheek < 192 ? .wry : .cheeky }
}
enum TimeOfDay: String, Sendable { case morning, day, evening, late
    init(hour: Int) { self = (5..<12).contains(hour) ? .morning : (12..<18).contains(hour) ? .day : (18..<23).contains(hour) ? .evening : .late }
}
enum Occasion: Sendable {
    case greet(Int), cheer(Moment?, CheerSize, String?), uhoh(UhohKind, Moment?)
    case recap(RecapFacts), profileLine(String)
    var key: String {
        switch self {
        case .greet: "greet"
        case .cheer(let moment, let size, _): moment?.kind.rawValue ?? "cheer_" + size.rawValue
        case .uhoh(let kind, let moment): moment?.kind.rawValue ?? "uhoh_" + kind.rawValue
        case .recap: "recap"
        case .profileLine: "profileLine"
        }
    }
    var dance: Bool { if case .cheer(_, .dance, _) = self { return true }; return false }
}
struct VoiceRequest: Sendable {
    var occasion: Occasion
    var profile: [String] = []
    var traits: Traits = [:]
    var agent: String? = nil
    var timeOfDay: TimeOfDay = .day
    var language: String = "en"
    var byteCap: Int = 40
    var register: VoiceRegister { VoiceRegister(cheek: traits["cheek", default: 128]) }
}
struct VoiceLine: Sendable, Equatable {
    enum Source: String, Sendable { case authored, model }
    var text: String
    var source: Source
}
enum VoiceLineKind: Sendable { case gift, bubble }

/// An unstructured race deliberately does not await a cancelled, uncooperative runtime.
/// Only the first completion can resume the caller; later results are discarded.
private final class VoiceRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }
    func finish(_ value: String?) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(returning: value)
    }
}
actor Voice {
    private let runtime: any VoiceRuntime
    private weak var store: (any EngineStore)?
    private let day: @Sendable () async -> String
    private var used: [String: Set<String>] = [:]
    private var recent: [String] = []
    private var inFlight = false
    init(runtime: any VoiceRuntime = NullRuntime(), store: (any EngineStore)? = nil,
         localDay: @escaping @Sendable () async -> String = { LocalDayCalendar().localDay(at: Date().timeIntervalSince1970 * 1000) }) {
        self.runtime = runtime; self.store = store; self.day = localDay
    }
    func line(for request: VoiceRequest) async -> VoiceLine {
        let result = await produce(for: request)
        // Rule candidates are persistent facts, not repeated device remarks.
        if case .profileLine = request.occasion { return result }
        guard !result.text.isEmpty else { return result }
        let today = await day()
        used[today, default: []].insert(result.text)
        recent.append(result.text); recent = Array(recent.suffix(20))
        try? await store?.rememberVoice(result.text, localDay: today)
        return result
    }
    private func produce(for request: VoiceRequest) async -> VoiceLine {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        let fallback = await authored(request)
        // At most one outstanding generation, including a runtime that ignores cancellation.
        guard !inFlight, !(runtime is NullRuntime) else { return fallback }
        inFlight = true
        let runtime = runtime, prompt = VoicePrompt.make(request)
        let result = await withCheckedContinuation { continuation in
            let race = VoiceRace(continuation)
            let generation = Task { [weak self] in
                let text = try? await runtime.generate(prompt: prompt, maxBytes: request.byteCap)
                race.finish(text)
                await self?.generationFinished()
            }
            Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                race.finish(nil)
                generation.cancel()
            }
        }
        guard let result, let text = VoiceFilter.check(result, language: request.language, byteCap: request.byteCap, allowExclamation: request.occasion.dance) else { return fallback }
        if case .profileLine = request.occasion { return VoiceLine(text: text, source: .model) }
        if case .recap(let recap) = request.occasion, request.byteCap > 63 {
            // The paragraph must keep all numeric facts, even when the model is terse.
            let numbers = [String(recap.turns), String(recap.tasks), String(recap.openGoals), String(format: "%.1f", recap.hours)]
            guard numbers.allSatisfy({ text.contains($0) }) else { return fallback }
        }
        let today = await day()
        let persisted = (try? await store?.voiceExclusions(localDay: today)) ?? []
        guard !used[today, default: []].contains(text), !recent.contains(text), !persisted.contains(text) else { return fallback }
        used[today, default: []].insert(text)
        return VoiceLine(text: text, source: .model)
    }
    private func generationFinished() { inFlight = false }
    private func authored(_ request: VoiceRequest) async -> VoiceLine {
        if case .recap(let facts) = request.occasion, request.byteCap > 63 {
            return VoiceLine(text: VoiceFilter.check(facts.paragraph(language: request.language), language: request.language, byteCap: request.byteCap) ?? "", source: .authored)
        }
        if case .profileLine(let candidate) = request.occasion {
            return VoiceLine(text: VoiceFilter.check(candidate, language: request.language, byteCap: request.byteCap) ?? "", source: .authored)
        }
        let today = await day()
        used = used.filter { $0.key == today }
        let persisted = (try? await store?.voiceExclusions(localDay: today)) ?? []
        let excluded = used[today, default: []].union(recent).union(persisted)
        let lines = VoiceBanks.lines(language: request.language, occasion: request.occasion.key, register: request.register)
        let ordered = lines.sorted { stableHash(today + request.occasion.key + $0) < stableHash(today + request.occasion.key + $1) }
        for template in ordered {
            let rendered = VoiceBanks.render(template, request: request)
            guard let text = VoiceFilter.check(rendered, language: request.language, byteCap: request.byteCap, allowExclamation: request.occasion.dance), !excluded.contains(text) else { continue }
            used[today, default: []].insert(text) // Reserve while a model request is in flight.
            return VoiceLine(text: text, source: .authored)
        }
        // A finite bank cannot supply infinitely many unique lines: silence on exhaustion.
        return VoiceLine(text: "", source: .authored)
    }
}
private func stableHash(_ text: String) -> UInt64 {
    text.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
}
