import Foundation

private let debug = ProcessInfo.processInfo.environment["BOOP_DEBUG"] != nil

private struct SignalConfig {
    var port: Int
    var approvalMode: Bool
    var token: String?

    static func read() -> SignalConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configFile = "\(home)/.boop/config.json"
        guard let data = FileManager.default.contents(atPath: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SignalConfig(port: 21321, approvalMode: false, token: nil)
        }
        return SignalConfig(
            port: json["port"] as? Int ?? 21321,
            approvalMode: json["approvalMode"] as? Bool ?? false,
            token: json["token"] as? String
        )
    }
}

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ newValue: String?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func postApproval(config: SignalConfig, agentId: String, body: Data) -> String? {
    guard let token = config.token, !token.isEmpty else { return nil }
    let urlString = "http://127.0.0.1:\(config.port)/hook/approve?source=\(agentId)"
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "X-Boop-Token")
    request.httpBody = body
    request.timeoutInterval = 300

    let result = LockedString()
    let semaphore = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        // A 401 or a 500 carries an empty body. Treating "no error" as
        // "a decision" printed a blank line, which is not valid hook output —
        // require a 2xx AND something to actually say.
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if error == nil, (200..<300).contains(status), let data,
           let str = String(data: data, encoding: .utf8),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.set(str)
        }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 300)
    return result.get()
}

private func log(_ msg: String) {
    guard debug else { return }
    FileHandle.standardError.write(Data("[boop-signal] \(msg)\n".utf8))
}

/// The two Cursor events that gate an action on a permission answer.
let approvalEvents: Set<String> = ["beforeShellExecution", "beforeMCPExecution"]

private let cursorSignalMap: [String: String] = [
    "beforeSubmitPrompt": "start_working",
    "sessionStart": "start_working",
    "afterShellExecution": "keep_working",
    "afterMCPExecution": "keep_working",
    "beforeShellExecution": "keep_working",
    "beforeMCPExecution": "keep_working",
    "afterFileEdit": "keep_working",
    // `stop` is handled separately so its `status` field can steer the signal
    // (see stopSignal). It is intentionally absent from this map.
    "sessionEnd": "session_end",
]

/// Pick the signal for a Cursor `stop` event from its `status`.
///
/// Cursor's stop payload reports `"completed" | "aborted" | "error"`. Mapping
/// every stop to `celebrate` (the old behavior) made the pet throw up the
/// review/celebration surface even when the run actually failed. Only a real
/// completion should celebrate; an errored turn goes to the error state.
///
/// `error` is used (not `stop_working`) on purpose: the server force-rewrites a
/// cursor `stop_working` back to `celebrate` for backward compatibility with
/// older helpers, so it is not a usable "quietly stop" channel here.
private func stopSignal(status: String?) -> String {
    status == "error" ? "error" : "celebrate"
}

private func parseAgentFlag() -> String {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--agent"), idx + 1 < args.count {
        return args[idx + 1]
    }
    return "cursor"
}

@main
struct SignalCLI {
    static func main() {
        let config = SignalConfig.read()
        let url = "http://127.0.0.1:\(config.port)/hook/signal"
        let agentId = parseAgentFlag()
        guard agentId == "cursor" else {
            log("unsupported signal agent: \(agentId)")
            return
        }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""

        guard !raw.isEmpty,
              let jsonData = raw.data(using: .utf8),
              let hookInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            log("no valid stdin")
            // Unparseable input means we can't tell which event this was, so
            // assume it might be a gating one and defer to Cursor's own prompt.
            print("{\"permission\":\"ask\"}")
            return
        }

        let hookEvent = (hookInput["hook_event_name"] as? String)
            ?? (hookInput["hookEventName"] as? String)
            ?? (hookInput["event_name"] as? String)
            ?? ""

        if approvalEvents.contains(hookEvent) {
            // Boop only ever ADDS a way to say yes. When it has no answer of
            // its own — approval mode off, Boop down, an error response — the
            // neutral reply is "ask", which hands the decision back to
            // Cursor's own confirmation dialog. Replying "allow" here (as this
            // did) told Cursor to run the command with nobody having approved
            // it: with approval mode off, installing Boop silently disabled
            // Cursor's shell prompt entirely.
            if config.approvalMode,
               let response = postApproval(config: config, agentId: agentId, body: jsonData) {
                print(response)
            } else {
                print("{\"permission\":\"ask\"}")
            }
            return
        }

        defer {
            // Cursor requires a permission response for non-blocking hooks; this
            // is protocol plumbing, not an approval decision. Safe as "allow"
            // only because these events fire after the fact (afterShellExecution,
            // stop, sessionEnd) and gate nothing.
            print("{\"permission\":\"allow\"}")
        }

        let signal: String
        if hookEvent == "stop" {
            signal = stopSignal(status: hookInput["status"] as? String)
        } else if let mapped = cursorSignalMap[hookEvent] {
            signal = mapped
        } else {
            log("unmapped event: \(hookEvent)")
            return
        }

        log("\(hookEvent) -> \(signal)")

        let sessionId = (hookInput["session_id"] as? String)
            ?? (hookInput["conversation_id"] as? String)
        let cwd = hookInput["cwd"] as? String
            ?? (hookInput["workspace_roots"] as? [String])?.first

        var body: [String: Any] = ["agent_id": agentId, "signal": signal]
        if let sessionId { body["session_id"] = sessionId }
        if let cwd { body["cwd"] = cwd }
        body["pid"] = Int32(ProcessInfo.processInfo.processIdentifier)
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let requestURL = URL(string: url) else {
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = config.token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Boop-Token")
        }
        request.httpBody = bodyData
        request.timeoutInterval = 3

        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { _, _, _ in
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
    }
}
