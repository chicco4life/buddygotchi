import Foundation

private let debug = ProcessInfo.processInfo.environment["BUDDYGOTCHI_DEBUG"] != nil

private struct SignalConfig {
    var port: Int
    var approvalMode: Bool

    static func read() -> SignalConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configFile = "\(home)/.buddygotchi/config.json"
        guard let data = FileManager.default.contents(atPath: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SignalConfig(port: 21321, approvalMode: false)
        }
        return SignalConfig(
            port: json["port"] as? Int ?? 21321,
            approvalMode: json["approvalMode"] as? Bool ?? false
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

private func postApproval(port: Int, agentId: String, body: Data) -> String? {
    let urlString = "http://127.0.0.1:\(port)/hook/approve?source=\(agentId)"
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    request.timeoutInterval = 300

    let result = LockedString()
    let semaphore = DispatchSemaphore(value: 0)
    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        if error == nil, let data, let str = String(data: data, encoding: .utf8) {
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
    FileHandle.standardError.write(Data("[buddygotchi-signal] \(msg)\n".utf8))
}

private let cursorSignalMap: [String: String] = [
    "beforeSubmitPrompt": "start_working",
    "sessionStart": "start_working",
    "afterShellExecution": "keep_working",
    "afterMCPExecution": "keep_working",
    "beforeShellExecution": "keep_working",
    "beforeMCPExecution": "keep_working",
    "stop": "stop_working",
    "sessionEnd": "session_end",
]

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
            print("{\"permission\":\"allow\"}")
            return
        }

        let hookEvent = (hookInput["hook_event_name"] as? String)
            ?? (hookInput["hookEventName"] as? String)
            ?? (hookInput["event_name"] as? String)
            ?? ""

        let approvalEvents: Set<String> = ["beforeShellExecution", "beforeMCPExecution"]
        if config.approvalMode && approvalEvents.contains(hookEvent) {
            if let response = postApproval(port: config.port, agentId: agentId, body: jsonData) {
                print(response)
            } else {
                print("{\"permission\":\"allow\"}")
            }
            return
        }

        defer {
            print("{\"permission\":\"allow\"}")
        }

        guard let signal = cursorSignalMap[hookEvent] else {
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
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body),
              let requestURL = URL(string: url) else {
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
