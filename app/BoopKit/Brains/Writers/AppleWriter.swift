import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model as the writer (Stage 2, HARNESS.md §6): the
/// default. Private and free, with an 8K context.
///
/// Each call is a fresh session. Its instructions are a short preamble,
/// `steering.md` and the memory files, less all but the latest Happened
/// lines (`instructions`); its prompt is what just happened,
/// what was said and what Boop decided, then a line for each slot. It
/// doesn't read the rest of the transcript's window: with it, the model
/// copied the words it wrote before instead of following steering
/// (ARCHITECTURE.md §11). Guided generation, with a schema built at
/// runtime, has one property per slot: a word from `none` and its list, or
/// text with its length asked for. The request and `steering.md` both push
/// hard for a word, and `none` comes last among the choices; it stays one,
/// since taking it off made the model's words worse (a failed test run got
/// "ugh", not "tests"). A slot that names
/// its sources gets one more property just before it, where the model first
/// picks which source the value comes from (HARNESS.md §7). There's no choice to decline, so
/// it can't answer "stay quiet": deciding was Stage 1's job. Text lengths
/// are only asked for, so the harness still checks them.
///
/// A memory line the model copied from memory, instead of writing what was
/// said, is left empty (`copied`), so the harness drops that call.
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

    #if canImport(FoundationModels)
    /// Greedy: the same moment always gets the same words. At temperature
    /// 0.2 a failed test run was still "tests" one time and "ugh" the next.
    /// Variety comes from what happened, not from chance.
    static let sampling = GenerationOptions(samplingMode: .greedy)
    #endif

    /// Three lines ahead of `steering.md`.
    static let preamble = """
        You are the voice of a Boop, a small creature on a person's desk.
        Boop has already decided what to do. You only write the words it needs.
        Keep them short and plain, in Boop's own character.
        """

    public func write(_ context: Context, _ slots: [Slot], deadline: Duration) async throws -> Writing {
        if let why = unavailable() { throw BrainError("apple: \(why)") }
        #if canImport(FoundationModels)
        return AppleWriter.withoutCopies(try await generate(context, slots), slots, context)
        #else
        throw BrainError("FoundationModels isn't in this SDK")
        #endif
    }

    /// The answer with any copied memory line left empty.
    static func withoutCopies(_ writing: Writing, _ slots: [Slot], _ context: Context) -> Writing {
        var writing = writing
        for slot in slots {
            if case .text = slot.kind, let text = writing.values[slot.key], copied(text, context) {
                writing.values[slot.key] = nil
            }
        }
        return writing
    }

    /// A line the model copied from memory instead of writing what was
    /// said: it's already a line there, and shares no word with what was
    /// said. A small model given the memory files sometimes answers
    /// "remember I work with Bob" with a note it read there ("demo on
    /// Thursday"). A line that's there and was said again is left to the
    /// memory store, which refuses duplicates.
    static func copied(_ text: String, _ context: Context) -> Bool {
        let written = line(text)
        let memory = (context.memory.longTerm + "\n" + context.memory.shortTerm).split(separator: "\n")
        guard memory.contains(where: { line(String($0)) == written }) else { return false }
        let said = Set(stems(context.input.words ?? ""))
        return stems(text).allSatisfy { !said.contains($0) }
    }

    /// A memory line compared loosely: no bullet, and no case or end
    /// punctuation, as the memory store compares lines (`MemoryStore.key`).
    static func line(_ s: String) -> String {
        var s = s.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("- ") { s.removeFirst(2) }
        return MemoryStore.key(s)
    }

    /// Words of three letters or more, without the commonest, cut to four
    /// letters so "works" and "work" match.
    static func stems(_ s: String) -> [String] {
        Input.plain(s).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !common.contains($0) }.map { String($0.prefix(4)) }
    }
    static let common: Set = ["the", "and", "for", "with", "that", "this", "you", "are", "was", "has", "have", "its",
                              "remember", "note", "about", "from", "they", "their"]

    #if canImport(FoundationModels)
    /// One call to the model, in a fresh session.
    func generate(_ context: Context, _ slots: [Slot]) async throws -> Writing {
        let schema = try AppleWriter.schema(slots)
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: AppleWriter.instructions(context.memory))
        do {
            let response = try await session.respond(to: AppleWriter.request(context, slots),
                                                     schema: schema,
                                                     options: AppleWriter.sampling)
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

    /// How many of short-term memory's latest Happened lines the writer
    /// reads. The log grows all day, and every character of instructions
    /// costs prefill time on every write (about 0.2 ms), without changing
    /// the words.
    static let happenedLines = 5

    /// The preamble, `steering.md`, long-term memory, and short-term memory
    /// with only its latest Happened lines. All of steering stays: without
    /// What Boop can do and Remembering, which look like Stage 1's, the
    /// memory lines and the words got worse (a request got "hi").
    static func instructions(_ memory: Prompt.Memory) -> String {
        [preamble, Prompt.stripComment(memory.steering), memory.longTerm, recent(memory.shortTerm)]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Short-term memory with only the last `happenedLines` of Happened, or
    /// as it is when it doesn't read.
    static func recent(_ shortTerm: String) -> String {
        guard var today = try? ShortTerm.parse(shortTerm) else { return shortTerm }
        today.happened = Array(today.happened.suffix(happenedLines))
        return today.markdown
    }

    /// The request, for the debug log.
    public func prompt(_ context: Context, _ slots: [Slot]) -> String? {
        AppleWriter.request(context, slots)
    }

    /// What just happened, what Boop decided (the window's last entry), then
    /// what to write.
    ///
    ///     --- now ---
    ///     you said · 11:45 Tuesday
    ///     They just said: "remember the demo is on Thursday"
    ///     Boop decided: react(feeling: happy), remember(where: today)
    ///     --- write ---
    ///     react.word: the mumble's one real word, from its list, as Writing says. Pick one whenever any could fit; none only when nothing on the list fits at all.
    ///     remember.text: at most 80 characters. Short-term, for today: a fact about a project or this session… Plain words; leave it empty if nothing is worth keeping.
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
                lines.append("\(slot.key): the mumble's one real word, from its list, as Writing says. "
                             + "Pick one whenever any could fit; none only when nothing on the list fits at all.")
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

    /// A word slot's choices in the schema: its words, then `none`.
    static func wordChoices(_ options: [String]) -> [String] { options + ["none"] }

    #if canImport(FoundationModels)
    static func schema(_ slots: [Slot]) throws -> GenerationSchema {
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
                                       schema: DynamicGenerationSchema(name: name, anyOf: wordChoices(options)))]
            case .text(let max):
                return source + [.init(name: name, description: "At most \(max) characters, or empty.",
                                       schema: DynamicGenerationSchema(type: String.self))]
            }
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Words", properties: properties), dependencies: [])
    }
    #endif
}
