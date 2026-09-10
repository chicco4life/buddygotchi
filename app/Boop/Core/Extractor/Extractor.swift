import Foundation

struct Extraction: Sendable {
    var events: [BuddyEvent] = []
    var facts: [Fact] = []
    var goalRunner: String?
}
actor Extractor {
    private(set) var windows: [String: SessionWindow] = [:]
    private var degraded: Set<String> = []
    func reset() { windows.removeAll(); degraded.removeAll() }
    func clearClosingLines() { for id in windows.keys { windows[id]?.closingLine = nil } }
    func drop(sessionId: String) { windows.removeValue(forKey: sessionId) }

    func ingest(_ p: RawHookPayload, localHour: Int? = nil) -> Extraction {
        var result = Extraction()
        if p.kind == .sessionEnd {
            result.events.append(.sessionEnded(at: p.timestamp, sessionId: p.sessionId))
            if let w = windows.removeValue(forKey: p.sessionId) {
                result.facts.append(.sessionSummary(turns: w.turns, tasks: w.completedTurns, elapsedMs: max(0, p.timestamp - w.startedAt)))
            }
            return result
        }
        let isNew = windows[p.sessionId] == nil
        var w = windows.removeValue(forKey: p.sessionId) ?? SessionWindow(project: ThemeReader.project(cwd: p.cwd), startedAt: p.timestamp)
        if (isNew || p.kind == .sessionStart) && !p.closingOnly {
            result.events.append(.sessionStarted(at: p.timestamp, sessionId: p.sessionId, source: p.source, cwd: p.cwd, project: w.project))
            if isNew { result.facts.append(.project(id: w.project)) }
        }
        // A bare result is a valid liveness ping, not evidence of schema drift.
        let toolRelated = p.kind == .toolCall || (p.kind == .toolResult && (p.outputHead != nil || p.outputTail != nil || p.exitStatus != nil || p.errorClass != nil))
        if toolRelated && p.toolName.isEmpty && p.toolInput == nil && degraded.insert(p.source).inserted {
            result.events.append(.adapterDegraded(at: p.timestamp, source: p.source))
        }
        let dictionary = p.toolInput.flatMap { $0.data(using: .utf8) }.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        switch p.kind {
        case .sessionStart: break
        case .turnStart: turnStart(p, window: &w, result: &result, localHour: localHour)
        case .turnEnd: turnEnd(p, window: &w, result: &result)
        case .toolCall:
            if !degraded.contains(p.source) { toolCall(p, dictionary: dictionary, window: &w, result: &result, localHour: localHour) }
        case .toolResult:
            if !degraded.contains(p.source) { toolResult(p, window: &w, result: &result) }
        case .needsYou:
            let (stakes, gloss) = StakesReader.read(tool: p.toolName, input: p.toolInput ?? "", dictionary: dictionary ?? [:])
            result.events.append(.requestArrived(at: p.timestamp, sessionId: p.sessionId, requestId: "\(p.sessionId)_\(Int(p.timestamp))", tool: p.toolName, hint: gloss, sessionLabel: w.project))
            result.events.append(.requestDescribed(at: p.timestamp, sessionId: p.sessionId, stakes: stakes, gloss: p.displayHint.isEmpty ? gloss : p.displayHint))
        case .sessionEnd: break
        }
        if !degraded.contains(p.source) {
            if let error = p.errorClass { result.facts.append(.errorClass(["rate_limit", "tool_error", "auth", "timeout"].contains(error) ? error : "unknown")) }
        }
        windows[p.sessionId] = w
        return result
    }

    private func turnStart(_ p: RawHookPayload, window w: inout SessionWindow, result: inout Extraction, localHour: Int?) {
        w.turns += 1
        w.workActive = true
        result.events.append(.turnStarted(at: p.timestamp, sessionId: p.sessionId, source: p.source))
        guard !degraded.contains(p.source) else { return }
        if let prompt = p.promptText { result.facts += [.tone(ThemeReader.tone(prompt)), .topics(ThemeReader.topics(prompt))] }
    }

    private func turnEnd(_ p: RawHookPayload, window w: inout SessionWindow, result: inout Extraction) {
        if !p.closingOnly {
            if p.errorClass == nil, w.workActive { w.completedTurns += 1; w.workActive = false }
            result.events.append(.turnEnded(at: p.timestamp, sessionId: p.sessionId, source: p.source, outcome: p.errorClass.map { .failed(errorClass: $0) } ?? .completed))
        }
        if let message = p.closingMessage { w.closingLine = String(message.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(120)) }
    }

    private func toolCall(_ p: RawHookPayload, dictionary: [String: Any]?, window w: inout SessionWindow, result: inout Extraction, localHour: Int?) {
        if let command = dictionary?["command"] as? String ?? dictionary?["cmd"] as? String ?? (dictionary == nil ? p.toolInput : nil), let runner = GoalsReader.runner(command) {
            result.goalRunner = runner.runner.name
        }
        w.workActive = true
        let safeTool = ["Bash","Shell","Read","Write","Edit","Grep","Glob","apply_patch"].contains(p.toolName) ? p.toolName : "other"
        result.facts.append(.activity(hour: localHour ?? -1, tool: safeTool, firstGoal: w.sawTool ? nil : (result.goalRunner ?? "none")))
        w.sawTool = true
        w.pending.append((result.goalRunner ?? "", p.toolName, p.callId))
        if w.pending.count > SessionWindow.pendingCap { w.pending.removeFirst() }
        result.events.append(.toolCalled(at: p.timestamp, sessionId: p.sessionId, source: p.source, tool: p.toolName, hint: p.displayHint))
        if let path = dictionary?["file_path"] as? String ?? dictionary?["path"] as? String {
            let topic = String((path as NSString).pathExtension.prefix(16))
            if ["swift", "py", "js", "ts", "tsx", "md", "json", "rs", "go"].contains(topic) { result.facts.append(.topics([topic])) }

        }
    }

    private func toolResult(_ p: RawHookPayload, window w: inout SessionWindow, result: inout Extraction) {
        let output = (p.outputHead ?? "") + "\n" + (p.outputTail ?? "")
        var outcome: GoalOutcome = p.exitStatus.map { $0 == 0 ? .pass : .fail } ?? .unknown
        if let index = w.pending.firstIndex(where: { p.callId != nil ? $0.callId == p.callId : $0.tool == p.toolName }) {
            let pending = w.pending.remove(at: index)
            if let runner = GoalsReader.byName[pending.runner] {
                result.goalRunner = pending.runner
                outcome = GoalsReader.outcome(p, runner: runner, output: output)
            }
        }
        w.workActive = true
        result.events.append(.toolResulted(at: p.timestamp, sessionId: p.sessionId, source: p.source, tool: p.toolName, ok: outcome == .unknown ? nil : outcome == .pass, durationMs: nil))
        result.facts.append(.toolOutcome(runner: result.goalRunner, outcome: outcome))
    }
}
