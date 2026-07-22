import Darwin
import Foundation
import Observation

@Observable
@MainActor
final class BuddyEngine {
    private(set) var state: BuddyState = .initial
    let diagnosticLog: DiagnosticLog

    private var internalState: InternalState
    private var staleTimer: Timer?
    private var config: BuddyConfig
    private let clock: any Clock
    private var outputs: [any OutputProvider] = []
    private var processWatchers: [String: DispatchSourceProcess] = [:]
    private var pendingApprovals: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]

    init(config: BuddyConfig = .default, clock: (any Clock)? = nil, diagnosticLog: DiagnosticLog? = nil) {
        self.config = config
        self.clock = clock ?? WallClock()
        self.diagnosticLog = diagnosticLog ?? DiagnosticLog()
        self.internalState = .initial(staleMs: config.staleTimeoutMs, celebrateDurationMs: config.celebrateDurationMs, workStallTimeoutMs: config.workStallTimeoutMs, approvalTimeoutMs: config.approvalTimeoutMs)
        if BuddyConfig.recreatedCorruptConfig {
            self.diagnosticLog.log(category: "engine", source: "system", event: "config", detail: "config.json was unreadable; recreated with defaults")
        }
    }

    // MARK: - Lifecycle

    func start() {
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, (!self.internalState.sessions.isEmpty || self.state.celebrateUntil != nil || self.state.affectionUntil != nil) else { return }
                self.apply(.staleTick(at: self.clock.now()))
            }
        }
    }

    func stop() {
        staleTimer?.invalidate()
        staleTimer = nil
        for (_, source) in processWatchers { source.cancel() }
        processWatchers.removeAll()
    }

    func triggerStaleTick() {
        apply(.staleTick(at: clock.now()))
    }

    // MARK: - Registration

    func register(output: any OutputProvider) {
        outputs.append(output)
    }

    // MARK: - Session API

    func sessionStarted(sessionId: String, source: String, cwd: String?, hookPid: Int32? = nil) {
        apply(.sessionStarted(at: clock.now(), sessionId: sessionId, source: source, cwd: cwd))
        if let hookPid, processWatchers[sessionId] == nil,
           let appPid = Self.resolveAncestor(from: hookPid) {
            let name = Self.processName(of: appPid) ?? "unknown"
            let shouldWatch = Self.isPlausibleAgentHost(name)
            diagnosticLog.log(
                category: "engine",
                source: source,
                event: "watcher",
                detail: "session=\(sessionId) pid=\(appPid) name=\(name) decision=\(shouldWatch ? "watch" : "skip")"
            )
            if shouldWatch {
                watchProcess(pid: appPid, sessionId: sessionId)
            }
        }
    }

    func sessionEnded(sessionId: String) {
        apply(.sessionEnded(at: clock.now(), sessionId: sessionId))
    }

    func submitRequest(sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?) {
        apply(.requestArrived(at: clock.now(), sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel))
    }

    func clearRequest(sessionId: String) {
        apply(.requestCleared(at: clock.now(), sessionId: sessionId))
    }

    func activitySignal(sessionId: String, source: String, signal: ActivitySignalKind, tool: String? = nil, hint: String? = nil) {
        apply(.activitySignal(at: clock.now(), sessionId: sessionId, source: source, signal: signal, tool: tool, hint: hint))
    }

    func dismissReview() {
        apply(.reviewDismissed(at: clock.now()))
    }

    func dismissError(sessionId: String) {
        apply(.errorDismissed(at: clock.now(), sessionId: sessionId))
    }

    func setSpecies(_ species: String) {
        apply(.speciesChanged(at: clock.now(), species: species))
    }

    /// Physical affection from the device (button boop or a petting stroke).
    /// The follow-up tick is what flips the pet back out of heart-eyes right
    /// when the affection window lapses — the 2s stale timer alone would let
    /// the heart linger up to 2s past it.
    func boop() {
        apply(.boopArrived(at: clock.now()))
        Timer.scheduledTimer(withTimeInterval: boopAffectionMs / 1000 + 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerStaleTick() }
        }
    }

    // MARK: - Approval API

    func submitApproval(sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?) async -> ApprovalDecision {
        apply(.approvalArrived(at: clock.now(), sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: source))
        return await withCheckedContinuation { continuation in
            pendingApprovals[requestId] = continuation
        }
    }

    func resolveApproval(requestId: String, decision: ApprovalDecision) {
        guard let continuation = pendingApprovals.removeValue(forKey: requestId) else { return }
        if let sessionId = findSessionForApproval(requestId) {
            apply(.approvalResolved(at: clock.now(), sessionId: sessionId, requestId: requestId, decision: decision))
        }
        continuation.resume(returning: decision)
    }

    func resolveAllPendingApprovals(decision: ApprovalDecision) {
        let approvals = pendingApprovals
        pendingApprovals.removeAll()
        for (requestId, continuation) in approvals {
            if let sessionId = findSessionForApproval(requestId) {
                apply(.approvalResolved(at: clock.now(), sessionId: sessionId, requestId: requestId, decision: decision))
            }
            continuation.resume(returning: decision)
        }
    }

    private func findSessionForApproval(_ requestId: String) -> String? {
        internalState.sessions.first(where: { $0.value.prompt?.id == requestId })?.key
    }

    // MARK: - Process Monitoring

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size > 0 else { return nil }
        let ppid = pid_t(info.pbi_ppid)
        guard ppid > 1 else { return nil }
        return ppid
    }

    private static func processName(of pid: pid_t) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN))
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
            let name = stringFromNullTerminatedCString(nameBuffer)
            if !name.isEmpty { return name }
        }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let path = stringFromNullTerminatedCString(pathBuffer)
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }

        return nil
    }

    private static func stringFromNullTerminatedCString(_ buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func isPlausibleAgentHost(_ processName: String) -> Bool {
        let lowered = processName.lowercased()
        return ["claude", "node", "cursor", "codex", "bun", "electron"].contains { lowered.contains($0) }
    }

    /// Walk up from hook script PID → intermediate shell → app (grandparent).
    private static func resolveAncestor(from hookPid: pid_t) -> pid_t? {
        guard let shell = parentPID(of: hookPid),
              let app = parentPID(of: shell) else { return nil }
        return app
    }

    private func watchProcess(pid: Int32, sessionId: String) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.cancelWatcher(sessionId: sessionId)
                self?.apply(.sessionEnded(at: self!.clock.now(), sessionId: sessionId))
            }
        }
        processWatchers[sessionId] = source
        source.resume()
    }

    private func cancelWatcher(sessionId: String) {
        processWatchers.removeValue(forKey: sessionId)?.cancel()
    }

    // MARK: - Internal

    private func apply(_ event: BuddyEvent) {
        let prev = state
        let previousPromptIds = Self.promptIds(in: internalState)
        let next = reduce(internalState, event)
        guard next != internalState else { return }
        let removedIds = Set(internalState.sessions.keys).subtracting(next.sessions.keys)
        let disappearedPromptIds = previousPromptIds.subtracting(Self.promptIds(in: next))
        internalState = next
        state = next.buddy
        for id in removedIds {
            cancelWatcher(sessionId: id)
        }
        for requestId in disappearedPromptIds {
            if let continuation = pendingApprovals.removeValue(forKey: requestId) {
                continuation.resume(returning: .passthrough)
            }
        }
        for output in outputs {
            output.stateDidChange(prev: prev, next: state)
        }
        diagnosticLog.log(category: "engine", source: "system", event: event.name, detail: "pet=\(state.pet.state.rawValue) sessions=\(state.sessions.total)")
    }

    private static func promptIds(in state: InternalState) -> Set<String> {
        Set(state.sessions.values.compactMap { $0.prompt?.id })
    }
}
