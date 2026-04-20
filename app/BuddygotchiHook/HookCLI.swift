import Foundation

private func readPort() -> Int {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let portFile = "\(home)/.buddygotchi/port"
    if let contents = try? String(contentsOfFile: portFile, encoding: .utf8),
       let port = Int(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return port
    }
    return 8080
}

private func extractToolAndHint(_ input: [String: Any]) -> (String, String) {
    let tool = (input["tool_name"] as? String)
        ?? (input["hook_event_name"] as? String)
        ?? "Shell"

    var candidates: [String] = []
    for key in ["command", "user_prompt", "prompt"] {
        if let v = input[key] as? String, !v.isEmpty { candidates.append(v) }
    }
    if let ti = input["tool_input"] as? [String: Any] {
        for key in ["command", "file_path", "path", "url", "query"] {
            if let v = ti[key] as? String, !v.isEmpty { candidates.append(v) }
        }
        if candidates.isEmpty, let data = try? JSONSerialization.data(withJSONObject: ti) {
            candidates.append(String(String(data: data, encoding: .utf8)?.prefix(200) ?? ""))
        }
    }
    return (tool, candidates.first ?? "")
}

@main
struct HookCLI {
    static func main() {
        let port = readPort()
        let baseURL = "http://127.0.0.1:\(port)/hook/request"

        let data = FileHandle.standardInput.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""

        var hookInput: [String: Any] = [:]
        if let data = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hookInput = parsed
        }

        let (tool, hint) = extractToolAndHint(hookInput)
        let source: String
        let args = CommandLine.arguments
        if args.contains("--format"), let idx = args.firstIndex(of: "--format"), idx + 1 < args.count, args[idx + 1] == "claude-code" {
            source = "claude-code"
        } else {
            source = "cursor"
        }

        let sessionId = (hookInput["session_id"] as? String)
            ?? (hookInput["conversation_id"] as? String)

        var body: [String: Any] = ["tool": tool, "hint": hint, "source": source]
        if let sessionId { body["session_id"] = sessionId }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: baseURL) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
