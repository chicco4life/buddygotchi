import Foundation

enum VoiceCap: Int, Sendable { case bubble = 63, profile = 240 }

typealias Traits = [String: Int]
enum VoiceRegister: String, CaseIterable, Sendable {
    case earnest, wry, cheeky
    init(cheek: Int) { self = cheek < 96 ? .earnest : cheek < 192 ? .wry : .cheeky }
}
enum TimeOfDay: String, Sendable { case morning, day, evening, late
    init(hour: Int) { self = (5..<12).contains(hour) ? .morning : (12..<18).contains(hour) ? .day : (18..<23).contains(hour) ? .evening : .late }
}
enum Occasion: Sendable {
    case greet(Int), uhoh(UhohKind), completed, periodic, profileLine(String), share
    var key: String {
        switch self {
        case .completed: "completed"
        case .periodic: "periodic"
        case .share: "share"
        case .greet: "greet"
        case .uhoh(let kind): "uhoh_" + kind.rawValue
        case .profileLine: "profileLine"
        }
    }
}
struct VoiceRequest: Sendable {
    var occasion: Occasion
    var profile: [String] = []
    var traits: Traits = [:]
    var agent: String? = nil
    var timeOfDay: TimeOfDay = .day
    var language: String = "en"
    var byteCap: Int = VoiceCap.bubble.rawValue
    var growth: GrowthSnapshot? = nil
    var memory: BehaviorMemory? = nil
    var state: CreatureState? = nil
    var sessionCount: Int = 0
    var effort: CreatureEffort? = nil
    var lastCompletedTaskDurationMs: Double? = nil
    var isParagraph: Bool { byteCap > VoiceCap.bubble.rawValue }
    var keepsHistory: Bool {
        if case .profileLine = occasion { return false }
        return !isParagraph
    }
}
struct VoiceLine: Sendable, Equatable {
    enum Source: String, Sendable { case authored, model }
    var text: String
    var source: Source
}
enum VoiceLineKind: Sendable, Hashable { case bubble }

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
    private let guide: BuddyBehaviorGuide
    private let deadlineNs: UInt64
    private weak var store: (any EngineStore)?
    private let day: @Sendable () async -> String
    private struct History {
        var day: String
        var lines: Set<String>
    }
    private var history: [String: History] = [:]
    private var loading: [String: (day: String, task: Task<[String], Never>)] = [:]
    // Separate device and profile lanes permit concurrent reflection.
    private var inFlight: [Bool: UUID] = [:]
    init(runtime: any VoiceRuntime = NullRuntime(), guide: BuddyBehaviorGuide = .init(), deadlineMs: UInt64 = 5_000, store: (any EngineStore)? = nil,
         localDay: @escaping @Sendable () async -> String = { LocalDayCalendar().localDay(at: Date().timeIntervalSince1970 * 1000) }) {
        self.runtime = runtime; self.guide = guide; self.deadlineNs = min(deadlineMs, 60_000) * 1_000_000; self.store = store; self.day = localDay
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
                history[language] = History(day: today, lines: Set(persisted))
            }
            if loading[language]?.day == today { loading[language] = nil }
        }
        return history[language]?.lines ?? []
    }
    func line(for request: VoiceRequest) async -> VoiceLine {
        let today = await day(), language = request.language
        let excluded = request.keepsHistory ? await exclusions(day: today, language: language) : []
        let fallback = fallback(for: request, excluded: excluded)
        let result = await produce(for: request, fallback: fallback, recent: excluded.sorted(), day: today)
        guard request.keepsHistory, !result.text.isEmpty, !Task.isCancelled else { return result }
        // Keep accepted lines as context and exclude exact repeats.
        _ = await exclusions(day: today, language: language)
        history[language]?.lines.insert(result.text)
        try? await store?.rememberVoice(result.text, localDay: today)
        return result
    }
    private func produce(for request: VoiceRequest, fallback: VoiceLine, recent: [String], day: String) async -> VoiceLine {
        guard let result = await generate(prompt: VoicePrompt.make(request, guide: guide.read(), recent: recent), maxBytes: request.byteCap, lane: request.isParagraph) else { return fallback }
        if result.trimmingCharacters(in: .whitespacesAndNewlines) == "SILENT" {
            return VoiceLine(text: "", source: .model)
        }
        guard let text = VoiceFilter.check(result, language: request.language, byteCap: request.byteCap) else { return fallback }
        if request.keepsHistory {
            let excluded = await exclusions(day: day, language: request.language)
            guard !excluded.contains(text) else { return fallback }
        }
        return VoiceLine(text: text, source: .model)
    }
    func reflect(history: [StoredFact], profile: [String], traits: Traits, day: String, language: String) async -> ReflectionUpdate? {
        let evidence = Reflection.evidence(history)
        guard !evidence.isEmpty else { return nil }
        let prompt = Reflection.prompt(guide: guide.read(), evidence: evidence, profile: profile, traits: traits, day: day, language: language)
        guard let result = await generate(prompt: prompt, maxBytes: 8192, lane: true) else { return nil }
        return ReflectionUpdate.decode(result, evidenceCount: evidence.count, language: language)
    }

    private func generate(prompt: String, maxBytes: Int, lane: Bool) async -> String? {
        guard inFlight[lane] == nil, !(runtime is NullRuntime), !Task.isCancelled else { return nil }
        let token = UUID()
        inFlight[lane] = token
        let deadlineNs = deadlineNs, runtime = runtime
        let result: String? = await withCheckedContinuation { continuation in
            let race = VoiceRace(continuation)
            let generation = Task {
                let text = try? await runtime.generate(prompt: prompt, maxBytes: maxBytes)
                race.finish(text)
            }
            let timeout = Task {
                // nanoseconds, not `for:`: the clock-generic sleep aborts in release
                // builds when the winning generation cancels it (swift_task_dealloc).
                do { try await Task.sleep(nanoseconds: deadlineNs); race.finish(nil) }
                catch { /* The winning generation cancelled the timer. */ }
            }
            race.attach([generation, timeout])
        }
        // Clear on race resolution, not on eventual runtime completion.
        if inFlight[lane] == token { inFlight[lane] = nil }
        return Task.isCancelled ? nil : result
    }

    private func fallback(for request: VoiceRequest, excluded: Set<String>) -> VoiceLine {
        let text: String
        switch request.occasion {
        case .greet: text = request.language == "ko" ? "다시 만나서 반가워요" : "hello again"
        case .uhoh: text = request.language == "ko" ? "문제가 생겼어요" : "something went wrong"
        case .profileLine(let candidate): text = candidate
        case .completed, .periodic, .share: text = ""
        }
        let safe = VoiceFilter.check(text, language: request.language, byteCap: request.byteCap) ?? ""
        return VoiceLine(text: excluded.contains(safe) ? "" : safe, source: .authored)
    }
}
