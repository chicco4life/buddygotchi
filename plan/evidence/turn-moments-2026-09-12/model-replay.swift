import Foundation
import FoundationModels

let arguments = CommandLine.arguments
let guide = try String(contentsOfFile: arguments[1], encoding: .utf8)
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))) as! [[String: Any]]
if #available(macOS 26, *) {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
        print("UNAVAILABLE: \(model.availability)")
        exit(3)
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 45) { print("Evaluation deadline reached"); exit(2) }
    Task { @MainActor in
        for item in cases {
            let data = try JSONSerialization.data(withJSONObject: item["context"]!, options: [.sortedKeys])
            let prompt = String(decoding: data, as: UTF8.self) + "\nReturn only the response for this occasion in the requested language. Follow max_utf8_bytes, event.max_characters and event.max_lines exactly."

            let start = Date()
            do {
                let session = LanguageModelSession(instructions: guide)
                let output = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.4)).content
                print("\(item["name"]!): \(output) [\(output.utf8.count) bytes; \(Date().timeIntervalSince(start)) seconds]")
            } catch { print("\(item["name"]!): ERROR \(error)") }
        }
        exit(0)
    }
    RunLoop.main.run()
} else { print("UNAVAILABLE: macOS 26 required"); exit(3) }
