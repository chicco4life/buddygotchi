import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, the default brain. Guided generation with a
/// schema built at runtime (the `@Generable` macro doesn't compile here,
/// PLAN.md §1), so every answer already matches the tools' choices:
///
///     Answer { react: "stay quiet" | "react",
///              calls: [≤ 3 of: say {tool: "say", feeling: "none" | …, word: "none" | …} | quiet {…} | …] }
///
/// A leading `react` choice makes staying quiet an easy first decision; the
/// brain turns `stay quiet` into no calls. Every choice also starts with
/// `none`, because a small model otherwise drifts to a list's first entry:
/// `none` leaves an optional argument out and drops a call whose required
/// choice it fills (`forget(text: none)` keeps everything). Numbers are offered as their
/// digits, and text lengths are only asked for, so the harness's shape check
/// still has work to do.
public struct AppleBrain: Brain {
    public let id: String
    /// Why the model can't run right now, or nil; asked before every call.
    let unavailable: @Sendable () -> String?

    public init() {
        self.init(unavailable: { AppleBrain.unavailableReason })
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

    public func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                         deadline: Duration) async throws -> String {
        // The model can stop being available after launch (it's updating,
        // or Apple Intelligence was turned off): this call gets the rules
        // brain's answer instead (HARNESS.md §7).
        if unavailable() != nil {
            return try await RulesBrain().complete(system: system, history: history, user: user, tools: tools,
                                                   deadline: deadline)
        }
        #if canImport(FoundationModels)
        let schema = try AppleBrain.schema(tools)
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        // A fresh session from the conversation each time: the harness's
        // exchanges stay the only history, and a late call leaves nothing behind.
        let session = LanguageModelSession(model: model, transcript: AppleBrain.transcript(system, history))
        do {
            let response = try await session.respond(to: user, schema: schema,
                                                     options: GenerationOptions(temperature: 0.5))
            return AppleBrain.fromList(response.content.jsonString, tools: tools)
        } catch let error as LanguageModelSession.GenerationError {
            // Only the case name: a refusal's or decoding failure's details can
            // carry generated text, which never goes to the log (HARNESS.md §8).
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

    #if canImport(FoundationModels)
    /// The first option of every choice.
    static let none = "none"

    static func transcript(_ system: String, _ history: [Exchange]) -> Transcript {
        func text(_ s: String) -> [Transcript.Segment] { [.text(.init(content: s))] }
        var entries: [Transcript.Entry] = [.instructions(.init(segments: text(system), toolDefinitions: []))]
        for exchange in history {
            entries.append(.prompt(.init(segments: text(exchange.user))))
            entries.append(.response(.init(assetIDs: [], segments: text(toList(exchange.answer)))))
        }
        return Transcript(entries: entries)
    }

    /// An earlier answer, `{"calls":[…]}`, in the shape this brain answers in,
    /// so the history reads like its own: `{"react":"stay quiet","calls":[]}`.
    static func toList(_ answer: String) -> String {
        let calls = (try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])?["calls"] as? [Any] ?? []
        let data = (try? JSONSerialization.data(withJSONObject: calls, options: [.sortedKeys])) ?? Data("[]".utf8)
        return "{\"react\":\"" + (calls.isEmpty ? "stay quiet" : "react") + "\",\"calls\":" + String(decoding: data, as: UTF8.self) + "}"
    }

    /// `{"react":"stay quiet",…}` → no calls; otherwise just the calls, with
    /// `none` arguments left out and calls whose required choice is `none`
    /// dropped.
    static func fromList(_ json: String, tools: [ToolDefinition] = []) -> String {
        guard let o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return json }
        let listed = (o["react"] as? String) == "react" ? (o["calls"] as? [Any] ?? []) : []
        let calls = listed.compactMap { item -> Any? in
            guard var call = item as? [String: Any] else { return item }
            let tool = tools.first { $0.name == call["tool"] as? String }
            for (key, value) in call where key != "tool" && (value as? String) == none {
                let optional = tool?.parameters.first { $0.name == key }?.optional ?? false
                if !optional { return nil }
                call[key] = nil
            }
            return call
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["calls": calls], options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func schema(_ tools: [ToolDefinition]) throws -> GenerationSchema {
        // A tool with nothing to choose from can't be called (`forget` with
        // no lines to forget).
        let callable = tools.filter { tool in
            !tool.parameters.contains { p in
                if case .choice(let options) = p.kind { return options.isEmpty && !p.optional }
                return false
            }
        }
        let calls = callable.map { tool -> DynamicGenerationSchema in
            var properties = [DynamicGenerationSchema.Property(
                name: "tool", schema: DynamicGenerationSchema(name: tool.name + "_tool", anyOf: [tool.name]))]
            for p in tool.parameters {
                let schema: DynamicGenerationSchema
                var description: String?
                switch p.kind {
                case .choice(let options):
                    schema = DynamicGenerationSchema(name: "\(tool.name)_\(p.name)", anyOf: [none] + options)
                case .number(let options):
                    schema = DynamicGenerationSchema(name: "\(tool.name)_\(p.name)", anyOf: options.map(String.init))
                case .text(let max):
                    schema = DynamicGenerationSchema(type: String.self)
                    description = "A few words, at most \(max) characters."
                }
                // Choices are always asked for; `none` stands in for leaving one out.
                let optional: Bool
                if case .choice = p.kind { optional = false } else { optional = p.optional }
                properties.append(.init(name: p.name, description: description, schema: schema, isOptional: optional))
            }
            return DynamicGenerationSchema(name: tool.name, description: tool.description, properties: properties)
        }
        let call = DynamicGenerationSchema(name: "ToolCall", anyOf: calls)
        let root = DynamicGenerationSchema(name: "Answer", properties: [
            .init(name: "react", description: "Stay quiet unless this really needs a reaction.",
                  schema: DynamicGenerationSchema(name: "react", anyOf: ["stay quiet", "react"])),
            .init(name: "calls", description: "One to three tool calls, in order. Do what the person asks.", schema: DynamicGenerationSchema(arrayOf: call, minimumElements: 0,
                                                                  maximumElements: Answer.maxCalls)),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }
    #endif
}

/// A cloud model with the person's own API key. Interface only in v1: it
/// shows up in settings as not yet available and refuses every call.
public struct CloudBrain: Brain {
    public let model: String
    public var id: String { "cloud:\(model)" }

    public init(model: String) { self.model = model }

    public func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                         deadline: Duration) async throws -> String {
        throw BrainError("the cloud brain isn't available yet")
    }
}

/// The brain setting (HARNESS.md §7): `apple` (the default), `rules`, or
/// `cloud:<model>`. Apple's model falls back to rules when it can't run: for
/// good if it can't at launch, and call by call if it stops later.
public enum Brains {
    public static func make(_ setting: String, log: (String) -> Void = { _ in }) -> any Brain {
        switch setting {
        case "rules": return RulesBrain()
        case let s where s.hasPrefix("cloud:"): return CloudBrain(model: String(s.dropFirst("cloud:".count)))
        default:
            if let why = AppleBrain.unavailableReason {
                log("brain: Apple's model can't run (\(why)); using rules")
                return RulesBrain()
            }
            return AppleBrain()
        }
    }
}
