import Foundation

// MARK: - Internal State

struct InternalState: Sendable, Equatable {
    var buddy: BuddyState
    var sessions: [String: Session]
    var staleMs: Double

    var version: Int { buddy.version }

    static func initial(staleMs: Double) -> InternalState {
        InternalState(buddy: .initial, sessions: [:], staleMs: staleMs)
    }
}

// MARK: - Reducer

func reduce(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    var next = reduceInner(state, event)
    guard next != state else { return state }
    next.buddy.version = state.buddy.version + 1
    next.buddy.updatedAt = event.at
    next.buddy = aggregate(next)
    return next
}

private func reduceInner(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    switch event {
    case .sessionStarted(let at, let sessionId, let source, let cwd):
        return handleSessionStarted(state, at: at, sessionId: sessionId, source: source, cwd: cwd)
    case .sessionEnded(_, let sessionId):
        return handleSessionEnded(state, sessionId: sessionId)
    case .requestArrived(let at, let sessionId, let requestId, let tool, let hint, let sessionLabel):
        return handleRequestArrived(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)
    case .requestCleared(let at, let sessionId):
        return handleRequestCleared(state, at: at, sessionId: sessionId)
    case .activitySignal(let at, let sessionId, let source, let signal):
        return handleActivitySignal(state, at: at, sessionId: sessionId, source: source, signal: signal)
    case .staleTick(let at):
        return handleStaleTick(state, now: at)
    }
}

// MARK: - Event Handlers

private func handleSessionStarted(_ state: InternalState, at: Double, sessionId: String, source: String, cwd: String?) -> InternalState {
    var s = state
    if s.sessions[sessionId] == nil {
        s.sessions[sessionId] = Session(source: source, state: .idle, prompt: nil, cwd: cwd, lastActivityAt: at)
    } else {
        let existingCwd = s.sessions[sessionId]?.cwd
        s.sessions[sessionId]?.lastActivityAt = at
        s.sessions[sessionId]?.cwd = cwd ?? existingCwd
    }
    return s
}

private func handleSessionEnded(_ state: InternalState, sessionId: String) -> InternalState {
    var s = state
    s.sessions.removeValue(forKey: sessionId)
    return s
}

private func handleRequestArrived(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?) -> InternalState {
    var s = state
    touchSession(&s, sessionId: sessionId, at: at)

    let source = s.sessions[sessionId]?.source
    let prompt = Prompt(id: requestId, tool: tool, hint: hint, arrivedAt: at, sessionLabel: sessionLabel, source: source)
    s.sessions[sessionId]?.state = .needsConfirmation
    s.sessions[sessionId]?.prompt = prompt

    let msg = shortMsg(tool: tool, hint: hint, source: s.sessions[sessionId]?.source ?? "")
    s.buddy.entries = Array(([msg] + s.buddy.entries).prefix(10))
    return s
}

private func handleRequestCleared(_ state: InternalState, at: Double, sessionId: String) -> InternalState {
    guard let session = state.sessions[sessionId], session.state == .needsConfirmation else {
        return state
    }
    var s = state
    s.sessions[sessionId]?.state = .working
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.lastActivityAt = at
    return s
}

private func handleActivitySignal(_ state: InternalState, at: Double, sessionId: String, source: String, signal: ActivitySignalKind) -> InternalState {
    var s = state
    touchSession(&s, sessionId: sessionId, at: at, source: source)

    switch signal {
    case .startWorking, .keepWorking:
        if s.sessions[sessionId]?.state == .needsConfirmation {
            s.sessions[sessionId]?.prompt = nil
        }
        s.sessions[sessionId]?.state = .working
    case .stopWorking:
        s.sessions[sessionId]?.state = .idle
        s.sessions[sessionId]?.prompt = nil
    case .celebrate:
        s.sessions[sessionId]?.state = .working
        s.buddy.pet.oneShotUntil = at + 2000
    }

    let msg = "[\(source)] \(signal.rawValue)"
    s.buddy.entries = Array(([msg] + s.buddy.entries).prefix(10))
    return s
}

private func handleStaleTick(_ state: InternalState, now: Double) -> InternalState {
    var changed = false
    var s = state

    let staleIds = s.sessions.filter { now - $0.value.lastActivityAt > s.staleMs }.map(\.key)
    for id in staleIds {
        s.sessions.removeValue(forKey: id)
        changed = true
    }

    let oneShotExpired = s.buddy.pet.oneShotUntil != nil && now >= (s.buddy.pet.oneShotUntil ?? 0)
    if oneShotExpired {
        s.buddy.pet.oneShotUntil = nil
        changed = true
    }

    guard changed else { return state }
    return s
}

// MARK: - Aggregation

private func aggregate(_ state: InternalState) -> BuddyState {
    var buddy = state.buddy
    let allSessions = Array(state.sessions.values)

    let waiting = allSessions.filter { $0.state == .needsConfirmation }
    let working = allSessions.filter { $0.state == .working }

    buddy.sessions = SessionCounts(
        total: allSessions.count,
        running: working.count + waiting.count,
        waiting: waiting.count
    )

    let highestPrompt = waiting.min(by: { ($0.prompt?.arrivedAt ?? .infinity) < ($1.prompt?.arrivedAt ?? .infinity) })?.prompt
    buddy.prompt = highestPrompt

    let hasConnected = !allSessions.isEmpty
    buddy.desktop = DesktopLink(
        status: hasConnected ? .connected : .disconnected,
        lastHeartbeatAt: allSessions.map(\.lastActivityAt).max()
    )

    if !hasConnected {
        buddy.pet = Pet(state: .sleep, oneShotUntil: nil, species: buddy.pet.species)
        buddy.msg = ""
        buddy.lastSignal = nil
    } else if !waiting.isEmpty {
        buddy.pet = Pet(state: .attention, oneShotUntil: nil, species: buddy.pet.species)
        if let p = highestPrompt {
            buddy.msg = shortMsg(tool: p.tool, hint: p.hint, source: waiting.first?.source ?? "")
        }
        buddy.lastSignal = "attention"
    } else if buddy.pet.oneShotUntil != nil {
        buddy.pet = Pet(state: .celebrate, oneShotUntil: buddy.pet.oneShotUntil, species: buddy.pet.species)
    } else if !working.isEmpty {
        buddy.pet = Pet(state: .busy, oneShotUntil: nil, species: buddy.pet.species)
        buddy.lastSignal = "busy"
    } else {
        buddy.pet = Pet(state: .idle, oneShotUntil: nil, species: buddy.pet.species)
        buddy.lastSignal = "idle"
    }

    return buddy
}

// MARK: - Helpers

private func touchSession(_ state: inout InternalState, sessionId: String, at: Double, source: String? = nil) {
    if var session = state.sessions[sessionId] {
        session.lastActivityAt = at
        if let source { session.source = source }
        state.sessions[sessionId] = session
    } else {
        state.sessions[sessionId] = Session(
            source: source ?? "unknown",
            state: .idle,
            prompt: nil,
            cwd: nil,
            lastActivityAt: at
        )
    }
}

private func shortMsg(tool: String, hint: String, source: String) -> String {
    let base = !source.isEmpty && source != "other" ? "[\(source)] \(tool)" : tool
    if hint.isEmpty { return base }
    let short = hint.count <= 60 ? hint : String(hint.prefix(57)) + "..."
    return "\(base): \(short)"
}
