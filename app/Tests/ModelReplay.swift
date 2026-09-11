#if BOOP_SHIM_RUNNER
import Foundation
@testable import BoopCore

/// Explicit opt-in diagnostic; ordinary tests never invoke the live model.
enum ModelReplay {
    @MainActor static func run(arguments: [String]) async {
        do {
            guard arguments.count == 4 || (arguments.count == 5 && arguments[4] == "--guided") else { throw ReplayError.usage }
            let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))) as? [[String: Any]] ?? []
            guard !cases.isEmpty else { throw ReplayError.usage }
            let output = URL(fileURLWithPath: arguments[3])
            guard !FileManager.default.fileExists(atPath: output.path) else { throw ReplayError.existingOutput }
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            var runtime: any VoiceRuntime = VoiceRuntimes.make(setting: "auto")
            #if canImport(FoundationModels)
            if arguments.count == 5, #available(macOS 26, *) { runtime = GuidedDisplayRuntime() }
            #endif
            guard !(runtime is NullRuntime) else { throw ReplayError.unavailable }
            for item in cases {
                guard let raw = item["context"] as? [String: Any], let desk = raw["desk"] as? [String: Any] else { throw ReplayError.usage }
                let projects = (desk["projects"] as? [[String: Any]] ?? []).enumerated().map { i, p in
                    WorkContext.Project(id: p["id"] as? String ?? "p\(i)", name: p["name"] as? String ?? "Unknown", tasks:
                        (p["tasks"] as? [[String: Any]] ?? []).enumerated().map { j, t in
                            .init(id: t["id"] as? String ?? "t\(j)", state: t["state"] as? String ?? "idle", intent: t["intent"] as? String, latest_request: t["latest_request"] as? String)
                        })
                }
                let context = BehaviorContext(desk: .init(coverage: desk["coverage"] as? String ?? "complete", projects: projects,
                    omitted_projects: desk["omitted_projects"] as? Int ?? 0, omitted_tasks: desk["omitted_tasks"] as? Int ?? 0),
                    event: raw["event"] as? [String: String], previous_scope: raw["previous_scope"] as? String,
                    recent_remarks: raw["recent_remarks"] as? [String] ?? [], memories: raw["memories"] as? [String] ?? [])
                let occasion: Occasion
                switch raw["occasion"] as? String {
                case "work_context_changed": occasion = .workContextChanged
                case "greet": occasion = .greet(1)
                case "completed": occasion = .completed
                case "uhoh_error": occasion = .uhoh(.error)
                default: throw ReplayError.usage
                }
                let start = Date()
                let result = await Voice(runtime: runtime).line(for: .init(occasion: occasion, context: context,
                    language: "en", byteCap: raw["max_utf8_bytes"] as? Int ?? 63))
                let row: [String: Any] = ["case": item["name"] as? String ?? "case", "text": result.text,
                    "source": result.source.rawValue, "bytes": result.text.utf8.count, "seconds": Date().timeIntervalSince(start)]
                var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); data.append(10)
                try handle.write(contentsOf: data)
                print(String(decoding: data, as: UTF8.self), terminator: ""); fflush(stdout)
            }
        } catch { fputs("Model replay failed: \(error)\n", stderr); exit(1) }
    }
    enum ReplayError: Error { case usage, existingOutput, unavailable }
}
#endif
