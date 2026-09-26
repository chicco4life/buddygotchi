import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model as the writer (Stage 2, HARNESS.md §6): the
/// default. Private and free, with an 8K context.
///
/// Each call is a fresh session. Its instructions are a short preamble,
/// `steering.md` and both memory files; its prompt is the transcript's window
/// as text (HARNESS.md §4), which ends with what Boop just decided, then a
/// line for each slot. Guided generation, with a schema built at runtime,
/// has one property per slot: a word from `none` and its list, or text with
/// its length asked for. There's no choice to decline, so it can't answer
/// "stay quiet": deciding was Stage 1's job. Text lengths are only asked
/// for, so the harness still checks them.
///
/// Guardrails are `permissiveContentTransformations`; a refusal fails the
/// write like any error, marked as a refusal. When the model can't run (it's
/// updating, or Apple Intelligence is off), every write fails, so a mumble
/// goes without a word and nothing is remembered.
public struct AppleWriter: Writer {
    public let id: String
    /// Why the model can't run right now, or nil; asked before every write.
    let unavailable: @Sendable () -> String?

    public init() {
        self.init(unavailable: { AppleWriter.unavailableReason })
    }

    /// Tests pass their own `unavailable` so they never reach the model.
    init(unavailable: @escaping @Sendable () -> String?) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        id = "apple:\(v.majorVersion).\(v.minorVersion)"
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

    /// Three lines ahead of `steering.md`.
    static let preamble = """
        You are the voice of a Boop, a small creature on a person's desk.
        Boop has already decided what to do. You only write the words it needs.
        Keep them short and plain, in Boop's own character.
        """

    public func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        if let why = unavailable() { throw BrainError("apple: \(why)") }
        #if canImport(FoundationModels)
        let schema = try AppleWriter.schema(slots)
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: AppleWriter.instructions(context.memory))
        do {
            let response = try await session.respond(to: AppleWriter.request(context, slots), schema: schema,
                                                     options: GenerationOptions(temperature: 0.5))
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
        #else
        throw BrainError("FoundationModels isn't in this SDK")
        #endif
    }

    /// The preamble, `steering.md` and the memory files.
    static func instructions(_ memory: Prompt.Memory) -> String {
        [preamble, Prompt.stripComment(memory.steering), memory.longTerm, memory.shortTerm]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// The window, what just happened again, then what to write.
    ///
    ///     --- what happened ---
    ///     you said · 11:45 Tuesday
    ///       they said: "remember the demo is on Thursday"
    ///       decided: react(feeling: happy, voice: mumble), remember(where: today)
    ///     --- now ---
    ///     you said · 11:45 Tuesday
    ///     They just said: "remember the demo is on Thursday"
    ///     Boop decided: react(feeling: happy, voice: mumble), remember(where: today)
    ///     --- write ---
    ///     react.word: one word from its list that fits the mumble; almost always pick one, even a plain yay, and none only when nothing fits.
    ///     remember.text: at most 80 characters. A note for later today… Plain words; leave it empty if nothing is worth keeping.
    static func request(_ context: Context, _ slots: [Slot]) -> String {
        var lines = ["--- what happened ---", Transcript.text(context.window), "--- now ---", context.input.line]
        if let words = context.input.words { lines.append("They just said: \"\(Transcript.oneLine(words))\"") }
        if case .decided(_, let calls, _) = context.window.last {
            lines.append("Boop decided: " + calls.map(\.plain).joined(separator: ", "))
        }
        lines.append("--- write ---")
        for slot in slots {
            switch slot.kind {
            case .word:
                lines.append("\(slot.key): one word from its list that fits the mumble; almost always pick one, even a plain yay, and none only when nothing fits.")
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

    #if canImport(FoundationModels)
    static func schema(_ slots: [Slot]) throws -> GenerationSchema {
        let properties = slots.map { slot -> DynamicGenerationSchema.Property in
            switch slot.kind {
            case .word(let options):
                return .init(name: property(slot.key), description: "One word that fits the mumble; almost always one, even a plain yay.",
                             schema: DynamicGenerationSchema(name: property(slot.key), anyOf: ["none"] + options))
            case .text(let max):
                return .init(name: property(slot.key), description: "At most \(max) characters, or empty.",
                             schema: DynamicGenerationSchema(type: String.self))
            }
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Words", properties: properties), dependencies: [])
    }
    #endif
}
