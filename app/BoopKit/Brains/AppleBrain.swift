import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, the default brain. Guided generation with a
/// schema built at runtime (the `@Generable` macro doesn't compile here,
/// PLAN.md §1), so every answer already matches the tools' choices:
///
///     Answer { calls: [≤ 3 of: say {tool: "say", feeling: …, word?: …} | face {…} | …] }
///
/// Numbers are offered as their digits, and text lengths are only asked
/// for, so the harness's shape check still has work to do.
public struct AppleBrain: Brain {
    public let id: String

    public init() {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        id = "apple:\(v.majorVersion).\(v.minorVersion)"
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

    public func complete(system: String, user: String, tools: [ToolDefinition], deadline: Duration) async throws -> String {
        #if canImport(FoundationModels)
        if let why = AppleBrain.unavailableReason { throw BrainError("apple model unavailable: \(why)") }
        let schema = try AppleBrain.schema(tools)
        let session = LanguageModelSession(instructions: system)
        do {
            let response = try await session.respond(to: user, schema: schema,
                                                     options: GenerationOptions(temperature: 0.5))
            return response.content.jsonString
        } catch let error as LanguageModelSession.GenerationError {
            throw BrainError("apple: \(error)")
        }
        #else
        throw BrainError("FoundationModels isn't in this SDK")
        #endif
    }

    #if canImport(FoundationModels)
    static func schema(_ tools: [ToolDefinition]) throws -> GenerationSchema {
        let calls = tools.map { tool -> DynamicGenerationSchema in
            var properties = [DynamicGenerationSchema.Property(
                name: "tool", schema: DynamicGenerationSchema(name: tool.name + "_tool", anyOf: [tool.name]))]
            for p in tool.parameters {
                let schema: DynamicGenerationSchema
                var description: String?
                switch p.kind {
                case .choice(let options):
                    schema = DynamicGenerationSchema(name: "\(tool.name)_\(p.name)", anyOf: options)
                case .number(let options):
                    schema = DynamicGenerationSchema(name: "\(tool.name)_\(p.name)", anyOf: options.map(String.init))
                case .text(let max):
                    schema = DynamicGenerationSchema(type: String.self)
                    description = "A few words, at most \(max) characters."
                }
                properties.append(.init(name: p.name, description: description, schema: schema, isOptional: p.optional))
            }
            return DynamicGenerationSchema(name: tool.name, description: tool.description, properties: properties)
        }
        let call = DynamicGenerationSchema(name: "ToolCall", anyOf: calls)
        let root = DynamicGenerationSchema(name: "Answer", description: "Your tool calls, often none.", properties: [
            .init(name: "calls", schema: DynamicGenerationSchema(arrayOf: call, minimumElements: 0,
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

    public func complete(system: String, user: String, tools: [ToolDefinition], deadline: Duration) async throws -> String {
        throw BrainError("the cloud brain isn't available yet")
    }
}

/// The brain setting (HARNESS.md §7): `apple` (the default), `rules`, or
/// `cloud:<model>`. Apple's model falls back to rules when it can't run.
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
