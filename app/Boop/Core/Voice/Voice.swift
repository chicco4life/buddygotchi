import Foundation

enum VoiceCap: Int, Sendable { case gift = 40, bubble = 63, paragraph = 1024 }

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
    var byteCap: Int = VoiceCap.gift.rawValue
    var isParagraph: Bool { byteCap > VoiceCap.bubble.rawValue }
    var keepsHistory: Bool {
        if case .profileLine = occasion { return false }
        return !isParagraph
    }
    var register: VoiceRegister { VoiceRegister(cheek: traits["cheek", default: 128]) }
}
struct VoiceLine: Sendable, Equatable {
    enum Source: String, Sendable { case authored, model }
    var text: String
    var source: Source
}
enum VoiceLineKind: Sendable { case gift, bubble }

/// Resolves once without awaiting an uncooperative runtime. Attaching after a
/// fast completion also cancels the tasks, closing the creation/completion race.
private final class VoiceRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var tasks: [Task<Void, Never>] = []
    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }
    func attach(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        let finished = continuation == nil
        if !finished { self.tasks = tasks }
        lock.unlock()
        if finished { tasks.forEach { $0.cancel() } }
    }
    func finish(_ value: String?) {
        lock.lock()
        let pending = continuation, tasks = tasks
        continuation = nil; self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        pending?.resume(returning: value)
    }
}
actor Voice {
    private let runtime: any VoiceRuntime
    private weak var store: (any EngineStore)?
    private let day: @Sendable () async -> String
    private struct History {
        var day: String
        var lines: Set<String>
        var draws: Int
        var seasoned: Int
    }
    private var history: [String: History] = [:]
    private var loading: [String: (day: String, task: Task<[String], Never>)] = [:]
    private var reservations: [String: Set<String>] = [:]
    // Separate device and paragraph lanes permit a concurrent recap.
    private var inFlight: [Bool: UUID] = [:]
    init(runtime: any VoiceRuntime = NullRuntime(), store: (any EngineStore)? = nil,
         localDay: @escaping @Sendable () async -> String = { LocalDayCalendar().localDay(at: Date().timeIntervalSince1970 * 1000) }) {
        self.runtime = runtime; self.store = store; self.day = localDay
    }
    private func exclusions(day today: String, language: String) async -> Set<String> {
        if history[language]?.day != today {
            let task: Task<[String], Never>
            if let pending = loading[language], pending.day == today { task = pending.task }
            else {
                let store = store
                task = Task { (try? await store?.voiceExclusions(localDay: today)) ?? [] }
                loading[language] = (today, task)
            }
            let persisted = await task.value
            if history[language]?.day != today {
                let leads = VoiceBanks.leadIns[language]?.values.flatMap { $0 } ?? []
                history[language] = History(day: today, lines: Set(persisted), draws: persisted.count,
                    seasoned: persisted.filter { line in leads.contains { line.hasPrefix($0) } }.count)
            }
            if loading[language]?.day == today { loading[language] = nil }
        }
        return (history[language]?.lines ?? []).union(reservations[language] ?? [])
    }
    func line(for request: VoiceRequest) async -> VoiceLine {
        let today = await day(), language = request.language
        let excluded = request.keepsHistory ? await exclusions(day: today, language: language) : []
        let values = VoiceBanks.values(request)
        let fallback = authored(request, day: today, excluded: excluded, values: values)
        if request.keepsHistory, !fallback.text.isEmpty { reservations[language, default: []].insert(fallback.text) }
        defer { if request.keepsHistory { reservations[language]?.remove(fallback.text) } }
        let result = await produce(for: request, fallback: fallback, values: values, day: today)
        guard request.keepsHistory, !result.text.isEmpty, !Task.isCancelled else { return result }
        // Commit only what the caller receives; a model win releases its fallback.
        _ = await exclusions(day: today, language: language)
        history[language]?.lines.insert(result.text)
        history[language]?.draws += 1
        let leads = VoiceBanks.leadIns[language]?[request.register.rawValue] ?? []
        if leads.contains(where: { result.text.hasPrefix($0) }) { history[language]?.seasoned += 1 }
        try? await store?.rememberVoice(result.text, localDay: today)
        return result
    }
    private func produce(for request: VoiceRequest, fallback: VoiceLine, values: [String: String], day: String) async -> VoiceLine {
        let lane = request.isParagraph
        guard inFlight[lane] == nil, !(runtime is NullRuntime), !Task.isCancelled else { return fallback }
        let token = UUID()
        inFlight[lane] = token
        let runtime = runtime, prompt = VoicePrompt.make(request, values: values)
        let result: String? = await withCheckedContinuation { continuation in
            let race = VoiceRace(continuation)
            let generation = Task {
                let text = try? await runtime.generate(prompt: prompt, maxBytes: request.byteCap)
                race.finish(text)
            }
            let timeout = Task {
                do { try await Task.sleep(for: .seconds(1)); race.finish(nil) }
                catch { /* The winning generation cancelled the timer. */ }
            }
            race.attach([generation, timeout])
        }
        // Clear on race resolution, not on eventual runtime completion.
        if inFlight[lane] == token { inFlight[lane] = nil }
        guard !Task.isCancelled, let result,
              let text = VoiceFilter.check(result, language: request.language, byteCap: request.byteCap, allowExclamation: request.occasion.dance) else { return fallback }
        if case .recap = request.occasion, request.isParagraph {
            let supplied = ["turns", "tasks", "openGoals", "hours"].compactMap { values[$0] }
            let numbers = Set(text.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty })
            guard supplied.allSatisfy(numbers.contains) else { return fallback }
        }
        if request.keepsHistory {
            let excluded = await exclusions(day: day, language: request.language)
            guard !excluded.contains(text) else { return fallback }
        }
        return VoiceLine(text: text, source: .model)
    }
    private func authored(_ request: VoiceRequest, day: String, excluded: Set<String>, values: [String: String]) -> VoiceLine {
        if case .profileLine(let candidate) = request.occasion {
            return VoiceLine(text: VoiceFilter.check(candidate, language: request.language, byteCap: request.byteCap) ?? "", source: .authored)
        }
        let key = request.isParagraph ? "recapParagraph" : request.occasion.key
        let lines = VoiceBanks.lines(language: request.language, occasion: key, register: request.register)
        let history = history[request.language]
        let seasoningAllowed = request.keepsHistory && (history?.seasoned ?? 0) < ((history?.draws ?? 0) + 1) * 4 / 10
        // Decorate once: the comparator never hashes or renders.
        let seed = stableHash(day + key + request.register.rawValue)
        let leads = VoiceBanks.leadIns[request.language]?[request.register.rawValue] ?? []
        var candidates: [(order: UInt64, text: String)] = []
        for template in lines {
            let order = stableHash(String(seed) + template)
            candidates.append((order, VoiceBanks.render(template, request: request, values: values)))
            if seasoningAllowed {
                for index in leads.indices {
                    let variantSeed = UInt64(index) * 10 + order % 4
                    candidates.append((stableHash(String(order) + String(index)),
                        VoiceBanks.render(template, request: request, values: values, seed: variantSeed, allowLeadIn: true)))
                }
            }
        }
        for candidate in candidates.sorted(by: { $0.order == $1.order ? $0.text < $1.text : $0.order < $1.order }) {
            guard candidate.text.utf8.count <= request.byteCap,
                  let text = VoiceFilter.check(candidate.text, language: request.language, byteCap: request.byteCap, allowExclamation: request.occasion.dance),
                  !excluded.contains(text) else { continue }
            return VoiceLine(text: text, source: .authored)
        }
        return VoiceLine(text: "", source: .authored)
    }
}
private func stableHash(_ text: String) -> UInt64 {
    text.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
}
