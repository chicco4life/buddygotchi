import Foundation
import OSLog
import Observation

// MARK: - Diagnostic Entry

struct DiagnosticEntry: Codable, Sendable {
    let timestamp: Double
    let category: String
    let source: String
    let event: String
    let detail: String
}

// MARK: - Diagnostic Log

@Observable
@MainActor
final class DiagnosticLog {
    private(set) var entries: [DiagnosticEntry] = []
    private(set) var appendedCount = 0
    private let capacity: Int

    private let hooksLogger = Logger(subsystem: "com.boopcomputer.boop", category: "hooks")
    private let engineLogger = Logger(subsystem: "com.boopcomputer.boop", category: "engine")

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    func log(category: String, source: String, event: String, detail: String) {
        let entry = DiagnosticEntry(
            timestamp: Date.now.timeIntervalSince1970 * 1000,
            category: category,
            source: source,
            event: event,
            detail: detail
        )
        entries.append(entry)
        appendedCount += 1
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }

        let logger = category == "engine" ? engineLogger : hooksLogger
        logger.info("[\(category)] \(source) \(event): \(detail)")
    }

    func exportBundle(engine: BuddyEngine) async -> Data? {
        let state = engine.state
        let logSnapshot = entries.reversed()
        let settingsSnapshot: [String: Any] = [
            "species": UserDefaults.standard.string(forKey: DefaultsKey.buddySpecies) ?? "cat",
            "interactiveMode": UserDefaults.standard.bool(forKey: DefaultsKey.interactiveMode),
            "approvalMode": UserDefaults.standard.bool(forKey: DefaultsKey.approvalMode),
            "httpPort": BuddyConfig.default.httpPort,
            "buddyOutput": UserDefaults.standard.string(forKey: DefaultsKey.buddyOutput) ?? "this-mac",
        ]
        var agents: [String: Any] = [:]
        for agent in AgentKind.allCases {
            agents[agent.rawValue] = [
                "detected": HookInstaller.shared.detectInstalledAgents()[agent] ?? false,
                "installed": HookInstaller.shared.isInstalled(agent: agent),
            ]
        }

        let systemLogData = await Task.detached { @Sendable in Self.collectSystemLogJSON() }.value

        var bundle: [String: Any] = [:]

        let formatter = ISO8601DateFormatter()
        bundle["note"] = "Entries may contain file paths and commands from your agent sessions."
        bundle["exportedAt"] = formatter.string(from: Date.now)
        bundle["appVersion"] = AppMetadata.displayVersion
        bundle["macOSVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
        bundle["uptimeMs"] = ProcessInfo.processInfo.systemUptime * 1000

        bundle["state"] = [
            "version": state.version,
            "updatedAt": state.updatedAt,
            "petState": state.pet.state.rawValue,
            "species": state.pet.species,
            "desktopStatus": state.desktop.status.rawValue,
            "sessions": [
                "total": state.sessions.total,
                "running": state.sessions.running,
                "waiting": state.sessions.waiting,
            ],
            "prompt": state.prompt.map { [
                "id": $0.id,
                "tool": $0.tool,
                "hint": $0.hint,
                "isApproval": $0.isApproval,
                "source": $0.source as Any,
                "sessionLabel": $0.sessionLabel as Any,
            ] as [String: Any] } as Any,
            "celebrateUntil": state.celebrateUntil as Any,
            "lastTaskDurationMs": state.lastTaskDurationMs as Any,
            "entries": state.entries,
        ] as [String: Any]

        bundle["settings"] = settingsSnapshot
        bundle["agents"] = agents

        bundle["log"] = logSnapshot.map { entry in
            let dict: [String: Any] = [
                "timestamp": entry.timestamp,
                "category": entry.category,
                "source": entry.source,
                "event": entry.event,
                "detail": entry.detail,
            ]
            return dict
        }

        if let sysLog = try? JSONSerialization.jsonObject(with: systemLogData) {
            bundle["systemLog"] = sysLog
        }

        return try? JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
    }

    private nonisolated static func collectSystemLogJSON() -> Data {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return Data("[]".utf8) }
        let tenMinutesAgo = store.position(date: Date.now.addingTimeInterval(-600))
        guard let logEntries = try? store.getEntries(at: tenMinutesAgo, matching: NSPredicate(format: "subsystem == %@", "com.boopcomputer.boop")) else { return Data("[]".utf8) }

        let entries = logEntries.compactMap { entry -> [String: Any]? in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            return [
                "timestamp": logEntry.date.timeIntervalSince1970 * 1000,
                "level": logEntry.level.rawValue,
                "category": logEntry.category,
                "message": logEntry.composedMessage,
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: entries)) ?? Data("[]".utf8)
    }
}
