import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model as the writer (Stage 2, HARNESS.md §6): the
/// default. Private and free, with an 8K context.
///
/// Each call is a fresh session. Its instructions are a short preamble,
/// `steering.md` and both memory files; its prompt is what just happened,
/// what was said and what Boop decided, then a line for each slot. It
/// doesn't read the rest of the transcript's window: with it, the model
/// copied the words it wrote before instead of following steering
/// (ARCHITECTURE.md §11). Guided generation, with a schema built at
/// runtime, has one property per slot: a word from `none` and its list, or
/// text with its length asked for. With `wordRequired` (chatty mode), a
/// word left empty is asked for once more with `none` off its list, when
/// there's time: taken off from the start, it made the model's words worse
/// (a failed test run got "ugh", not "tests"). A slot that names
/// its sources gets one more property just before it, where the model first
/// picks which source the value comes from (HARNESS.md §7). There's no choice to decline, so
/// it can't answer "stay quiet": deciding was Stage 1's job. Text lengths
/// are only asked for, so the harness still checks them.
///
/// Guardrails are `permissiveContentTransformations`; a refusal fails the
/// write like any error, marked as a refusal. When the model can't run (it's
/// updating, or Apple Intelligence is off), every write fails, so a mumble
/// goes without a word and nothing is remembered.
public struct AppleWriter: Writer {
    public let id: String
    /// Every word slot gets a word: `none` isn't offered.
    public let wordRequired: Bool
    /// Why the model can't run right now, or nil; asked before every write.
    let unavailable: @Sendable () -> String?

    public init(wordRequired: Bool = false) {
        self.init(wordRequired: wordRequired, unavailable: { AppleWriter.unavailableReason })
    }

    /// Tests pass their own `unavailable` so they never reach the model.
    init(wordRequired: Bool = false, unavailable: @escaping @Sendable () -> String?) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        id = "apple:\(v.majorVersion).\(v.minorVersion)"
        self.wordRequired = wordRequired
        self.unavailable = unavailable
    }

    /// Nil when the model can be used, otherwise why not.
    public static var unavailableReason: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let reason): return "\(reason)"
        }
        #else
        return "FoundationModels isn't in this SDK"
        #endif
    }

    /// Low, so the same moment gets the same word: at 0.5 a failed test run
    /// was "tests" one time and "ugh" the next. Variety comes from what
    /// happened, not from chance.
    static let temperature = 0.2

    /// Three lines ahead of `steering.md`.
    static let preamble = """
        You are the voice of a Boop, a small creature on a person's desk.
        Boop has already decided what to do. You only write the words it needs.
        Keep them short and plain, in Boop's own character.
        """

    public func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        if let why = unavailable() { throw BrainError("apple: \(why)") }
        #if canImport(FoundationModels)
        let start = ContinuousClock.now
        let first = try await generate(context, slots, wordRequired: false)
        let took = ContinuousClock.now - start
        // Chatty: a word left empty gets one more try, with `none` off its
        // list, if it can finish in the time left; otherwise the first
        // answer stands.
        guard wordRequired, AppleWriter.missesAWord(first.values, slots), took * 2 < deadline else { return first }
        guard let again = try? await generate(context, slots, wordRequired: true) else { return first }
        return Writing(values: first.values.merging(again.values) { old, _ in old }, raw: again.raw)
        #else
        throw BrainError("FoundationModels isn't in this SDK")
        #endif
    }

    /// Whether a word slot was left empty.
    static func missesAWord(_ values: [String: String], _ slots: [Slot]) -> Bool {
        slots.contains { slot in
            if case .word = slot.kind { return values[slot.key] == nil }
            return false
        }
    }

    #if canImport(FoundationModels)
    /// One call to the model, in a fresh session.
    func generate(_ context: Context, _ slots: [Slot], wordRequired: Bool) async throws -> Writing {
        let schema = try AppleWriter.schema(slots, wordRequired: wordRequired)
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: AppleWriter.instructions(context.memory))
        do {
            let response = try await session.respond(to: AppleWriter.request(context, slots),
                                                     schema: schema,
                                                     options: GenerationOptions(temperature: AppleWriter.temperature))
            let json = response.content.jsonString
            return Writing(values: AppleWriter.values(json, slots), raw: json)
        } catch let error as LanguageModelSession.GenerationError {
            // Only the case name: a refusal's details can carry generated
            // text, which never goes to the log (HARNESS.md §8).
            let kind = String(describing: error).prefix { $0 != "(" }
            switch error {
            case .guardrailViolation, .refusal: throw BrainError.refused("apple: \(kind)")
            default: throw BrainError("apple: \(kind)")
            }
        }
    }
    #endif

    /// The preamble, `steering.md` and the memory files.
    static func instructions(_ memory: Prompt.Memory) -> String {
        [preamble, Prompt.stripComment(memory.steering), memory.longTerm, memory.shortTerm]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// What just happened, what Boop decided (the window's last entry), then
    /// what to write.
    ///
    ///     --- now ---
    ///     you said · 11:45 Tuesday
    ///     They just said: "remember the demo is on Thursday"
    ///     Boop decided: react(feeling: happy, voice: mumble), remember(where: today)
    ///     --- write ---
    ///     react.word: the mumble's one real word, from its list, as Writing says; none only when nothing fits.
    ///     remember.text: at most 80 characters. Short-term, for today: a fact about a project or this session… Plain words; leave it empty if nothing is worth keeping.
    ///
    /// The lines are the same with `wordRequired`.
    static func request(_ context: Context, _ slots: [Slot]) -> String {
        var lines = ["--- now ---", context.input.line]
        if let words = context.input.words { lines.append("They just said: \"\(Transcript.oneLine(words))\"") }
        if case .decided(_, let calls, _) = context.window.last {
            lines.append("Boop decided: " + calls.map(\.plain).joined(separator: ", "))
        }
        lines.append("--- write ---")
        for slot in slots {
            switch slot.kind {
            case .word:
                lines.append("\(slot.key): the mumble's one real word, from its list, as Writing says; none only when nothing fits.")
            case .text(let max):
                lines.append("\(slot.key): at most \(max) characters. \(slot.choice ?? slot.about) "
                             + "Plain words, no code; leave it empty if nothing is worth keeping.")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A property name the schema accepts: `react.word` → `react_word`.
    static func property(_ key: String) -> String {
        key.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "#", with: "_")
    }

    /// Slot values from the answer, by slot key; `none` and blanks are left out.
    static func values(_ json: String, _ slots: [Slot]) -> [String: String] {
        guard let o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [:] }
        var values: [String: String] = [:]
        for slot in slots {
            if let v = o[property(slot.key)] as? String, !v.isEmpty, v != "none" { values[slot.key] = v }
        }
        return values
    }

    /// A word slot's choices in the schema: `none` first, unless a word is required.
    static func wordChoices(_ options: [String], _ wordRequired: Bool) -> [String] {
        wordRequired ? options : ["none"] + options
    }

    #if canImport(FoundationModels)
    static func schema(_ slots: [Slot], wordRequired: Bool = false) throws -> GenerationSchema {
        let properties = slots.flatMap { slot -> [DynamicGenerationSchema.Property] in
            let name = property(slot.key)
            // Which source first, then the value that comes from it.
            let source: [DynamicGenerationSchema.Property] = slot.sources.isEmpty ? [] : [
                .init(name: name + "_from", description: "What the \(slot.parameter) comes from: the first of these that fits.",
                      schema: DynamicGenerationSchema(name: name + "_from", anyOf: slot.sources)),
            ]
            switch slot.kind {
            case .word(let options):
                return source + [.init(name: name, description: "The mumble's one real word, as Writing says.",
                                       schema: DynamicGenerationSchema(name: name, anyOf: wordChoices(options, wordRequired)))]
            case .text(let max):
                return source + [.init(name: name, description: "At most \(max) characters, or empty.",
                                       schema: DynamicGenerationSchema(type: String.self))]
            }
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Words", properties: properties), dependencies: [])
    }
    #endif
}
