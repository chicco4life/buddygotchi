import Foundation

/// Adapter identity: worktrees share their common Git directory, not a basename.
/// Paths stay here; only the digest and display label enter model context.
struct WorkProject: Sendable, Equatable {
    var id: String
    var name: String

    static func resolve(cwd: String?, sessionId: String) -> Self {
        guard let cwd, !cwd.isEmpty else {
            return .init(id: "unknown", name: "Unknown project")
        }
        let original = URL(fileURLWithPath: cwd).standardizedFileURL.resolvingSymlinksInPath()
        var root = original
        while root.path != "/" {
            var git = root.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: git.path) {
                if let pointer = try? String(contentsOf: git, encoding: .utf8), pointer.hasPrefix("gitdir: ") {
                    git = URL(fileURLWithPath: String(pointer.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: root).standardizedFileURL
                }
                if let common = try? String(contentsOf: git.appendingPathComponent("commondir"), encoding: .utf8) {
                    git = URL(fileURLWithPath: common.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: git).standardizedFileURL
                }
                git = git.resolvingSymlinksInPath()
                return .init(id: stableHashCwd(git.path), name: label(git.deletingLastPathComponent().lastPathComponent))
            }
            root.deleteLastPathComponent()
        }
        return .init(id: stableHashCwd(original.path), name: label(original.lastPathComponent))
    }
    private static func label(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(utf8Bytes: 64)
    }
}

/// Never persisted. Initial intent grounds short follow-ups; the latest request
/// can override it without a second model call or a topic-change classifier.
struct WorkIntent: Sendable, Equatable {
    var project: WorkProject
    var first: String?
    var latest: String?
    mutating func receive(_ prompt: String?) {
        guard let prompt else { return }
        let text = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(utf8Bytes: 768)
        guard !text.isEmpty else { return }
        if first == nil { first = text }
        latest = text == first ? nil : text
    }
}

struct WorkContext: Sendable, Equatable, Encodable {
    struct TaskContext: Sendable, Equatable, Encodable {
        var id: String
        var state: String
        var intent: String?
        var latest_request: String?
    }
    struct Project: Sendable, Equatable, Encodable {
        var id: String
        var name: String
        var tasks: [TaskContext]
    }
    var coverage = "complete"
    var projects: [Project] = []
    var omitted_projects = 0
    var omitted_tasks = 0
    static let idleGraceMs: Double = 15 * 60 * 1000

    static func eligible(_ session: Session, now: Double) -> Bool {
        [.working, .thinking, .needsConfirmation].contains(session.state) || now - session.lastActivityAt < idleGraceMs
    }

    static func make(sessions: [String: Session], intents: [String: WorkIntent], now: Double) -> Self {
        var grouped: [String: Project] = [:]
        for (id, session) in sessions where eligible(session, now: now) {
            let input = intents[id]
            let project = input?.project ?? WorkProject(id: session.cwd.map { stableHashCwd($0) } ?? "unknown", name: cwdLabel(session.cwd) ?? "Unknown project")
            var row = grouped[project.id] ?? Project(id: project.id, name: project.name, tasks: [])
            let state: String = switch session.state {
            case .working, .thinking: "working"
            case .needsConfirmation: "waiting"
            case .idle: "idle"
            case .errored: "error"
            }
            row.tasks.append(.init(id: stableHashCwd(id), state: state, intent: input?.first, latest_request: input?.latest))
            grouped[project.id] = row
        }
        return .init(projects: grouped.values.sorted { $0.id < $1.id }.map { project in
            var project = project; project.tasks.sort { $0.id < $1.id }; return project
        })
    }

    /// Every project gets an equal text allowance regardless of its task count.
    /// If even metadata does not fit, report omissions rather than choose a winner.
    func bounded(maxBytes: Int = 6144) -> Self {
        let encoder = JSONEncoder()
        var result = self
        for budget in [4096, 2048, 1024, 0] {
            result = self
            for p in result.projects.indices {
                let perTask = budget / max(1, projects.count) / max(1, projects[p].tasks.count) / 2
                for t in result.projects[p].tasks.indices {
                    result.projects[p].tasks[t].intent = projects[p].tasks[t].intent.map { $0.prefix(utf8Bytes: perTask) }
                    result.projects[p].tasks[t].latest_request = projects[p].tasks[t].latest_request.map { $0.prefix(utf8Bytes: perTask) }
                }
            }
            if let data = try? encoder.encode(result), data.count <= maxBytes { return result }
        }
        return .init(coverage: "partial", omitted_projects: projects.count, omitted_tasks: projects.reduce(0) { $0 + $1.tasks.count })
    }
}

/// The same snapshot is supplied for every display occasion. Event details and
/// grounded episodic memories can be added here without another model pipeline.
struct BehaviorContext: Sendable, Encodable {
    var desk: WorkContext
    var event: [String: String]? = nil
    var previous_scope: String?
    var recent_remarks: [String] = []
    var memories: [String] = []
}
