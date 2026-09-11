import Foundation

// MARK: - Internal State

struct InternalState: Sendable, Equatable {
    var buddy: BuddyState
    var sessions: [String: Session]
    var staleMs: Double
    var celebrateDurationMs: Double
    var approvalTimeoutMs: Double
    /// Sessions whose agent host process has a live exit watcher. Fed by
    /// `.processWatchChanged`; exempt from the stale-activity reap because the
    /// watcher reports death definitively — silence is not evidence.
    var watchedSessionIds: Set<String> = []
    /// The pet's persisted inner life (System P). Seeded via `.memoryLoaded`,
    /// mutated only here, written back by the engine when it changes.
    var memory: PetMemory = .empty

    var pendingAwards: [XPAward] = []
    var pendingFacts: [PendingFact] = []
    var cheerThresholds: CheerThresholds = .defaults
    var nudgeTiming: NudgeTiming = .defaults
    var nudges: [String: CardNudge] = [:]
    var bubbleUntil: Double?
    /// Size of the cheer currently playing; `celebrateUntil` is its timer.
    var doneSize: CheerSize?

    var version: Int { buddy.version }

    static func initial(staleMs: Double, celebrateDurationMs: Double, approvalTimeoutMs: Double = 290_000) -> InternalState {
        InternalState(buddy: .initial, sessions: [:], staleMs: staleMs, celebrateDurationMs: celebrateDurationMs, approvalTimeoutMs: approvalTimeoutMs)
    }
}

// MARK: - Reducer

func reduce(_ state: InternalState, _ event: BuddyEvent, localHour: Int = 0) -> InternalState {
    var input = state
    input.pendingAwards = []; input.pendingFacts = []
    var next = reduceInner(input, event)
    if case .sessionStarted(_, let id, _, _, _) = event, state.sessions[id] == nil {
        appendFact(&next, .activity(hour: localHour, tool: nil, firstGoal: nil), id: id, at: event.at)
    }
    if !next.pendingAwards.isEmpty, next.buddy.greetUntil != state.buddy.greetUntil,
       state.memory.lastSeenAt.map({ event.at - $0 >= 86_400_000 }) ?? false {
        next.pendingAwards[0].greet = true
        appendFact(&next, .greet, id: next.pendingAwards[0].sessionId, at: event.at)
    }
    updateCreatureTimers(&next, event: event)
    // Recompute even on a quiet tick so effort and timed projections advance.
    // `updatedAt` is left alone until we know something changed: a timestamp
    // alone is not a state change worth notifying outputs about.
    next.buddy = aggregate(next, now: event.at)
    var projection = next
    projection.pendingAwards = []; projection.pendingFacts = []
    guard projection != input else { return next }
    next.buddy.version = state.buddy.version + 1
    next.buddy.updatedAt = event.at
    return next
}

private func reduceInner(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    switch event {
    case .workScopeChanged(_, let text):
        var s = state; s.buddy.workScope = text; return s
    case .onboardingCheer(let at):
        guard state.memory.completedTurns == 0, state.buddy.creature.card == nil else { return state }
        var s = state
        s.doneSize = .hop
        s.buddy.celebrateUntil = at + s.cheerThresholds.duration(.hop)
        return s
    case .languageChanged(_, let language):
        var s = state; s.buddy.language = language == "ko" ? "ko" : "en"; return s
    case .voiceLine(let at, _, let text):
        guard state.buddy.creature.state != .asleep, state.buddy.creature.card == nil,
              !state.sessions.values.contains(where: { $0.prompt != nil }) else { return state }
        var s = state
        setBubble(&s, text, at: at)
        return s
    case .growthUpdated(_, let growth, let cosmetic):
        var s = state; s.buddy.growth = growth; s.buddy.cosmetic = cosmetic; return s
    case .requestDescribed(_, let id, let stakes, let gloss):
        var s = state
        s.sessions[id]?.prompt?.stakes = stakes
        s.sessions[id]?.prompt?.gloss = gloss
        return s
    case .adapterDegraded: return state
    case .devicePostureChanged(_, let posture):
        var s = state
        s.buddy.devicePosture = posture
        return s
    case .deviceBatteryChanged(_, let battery):
        var s = state
        s.buddy.deviceBattery = battery
        return s
    case .turnStarted(let at, let id, let source):
        return handleTurnStarted(state, at: at, sessionId: id, source: source)
    case .toolCalled(let at, let id, let source, let tool, let hint, let goal):
        return handleToolCalled(state, at: at, sessionId: id, source: source, tool: tool, hint: hint, goal: goal)
    case .toolResulted(let at, let id, let source, let tool, let ok, _, let goal):
        return handleToolResulted(state, at: at, sessionId: id, source: source, tool: tool, ok: ok, goal: goal)
    case .turnEnded(let at, let id, let source, let outcome):
        return handleTurnEnded(state, at: at, sessionId: id, source: source, outcome: outcome)
    case .focusToggled(_, let on):
        var s = state
        s.buddy.creature.focus = on
        return s
    case .nudgeDismissed(let at):
        return dismissNudge(state, at: at)
    case .sessionStarted(let at, let sessionId, let source, let cwd, let project):
        return handleSessionStarted(state, at: at, sessionId: sessionId, source: source, cwd: cwd, project: project)
    case .sessionEnded(let at, let sessionId):
        return handleSessionEnded(state, sessionId: sessionId, at: at)
    case .requestArrived(let at, let sessionId, let requestId, let tool, let hint, let sessionLabel):
        return handleRequestArrived(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)
    case .requestCleared(let at, let sessionId):
        return handleRequestCleared(state, at: at, sessionId: sessionId)
    case .activitySignal(let at, let sessionId, let source, let signal, let tool, let hint):
        // Compatibility input: the same turn/tool handlers, with the legacy
        // signal's tool/hint stamped through the one shared helper.
        switch signal {
        case .startWorking:
            return handleTurnStarted(state, at: at, sessionId: sessionId, source: source, tool: tool, hint: hint)
        case .keepWorking:
            return handleToolCalled(state, at: at, sessionId: sessionId, source: source, tool: tool ?? "", hint: hint ?? "")
        case .stopWorking, .celebrate:
            return handleTurnEnded(state, at: at, sessionId: sessionId, source: source, outcome: .completed, tool: tool, hint: hint)
        case .error:
            return handleTurnEnded(state, at: at, sessionId: sessionId, source: source, outcome: .failed(errorClass: nil), tool: tool, hint: hint)
        }
    case .staleTick(let at):
        return handleStaleTick(state, now: at)
    case .approvalArrived(let at, let sessionId, let requestId, let tool, let hint, let sessionLabel, let source):
        return handleApprovalArrived(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: source)
    case .approvalResolved(let at, let sessionId, let requestId, let decision):
        return handleApprovalResolved(state, at: at, sessionId: sessionId, requestId: requestId, decision: decision)
    case .approvalAbandoned(let at, let sessionId, let requestId):
        return handleApprovalAbandoned(state, at: at, sessionId: sessionId, requestId: requestId)
    case .processWatchChanged(_, let watchedSessionIds):
        var s = state
        s.watchedSessionIds = watchedSessionIds
        return s
    case .speciesChanged(_, let species):
        return handleSpeciesChanged(state, species: species)
    case .boopArrived(let at):
        return handleBoopArrived(state, at: at)
    case .reviewDismissed:
        return handleReviewDismissed(state)
    case .errorDismissed(let at, let sessionId):
        return handleErrorDismissed(state, at: at, sessionId: sessionId)
    case .memoryLoaded(_, let memory):
        var s = state
        s.memory = memory
        return s
    }
}

// MARK: - Event Handlers

private func handleSessionStarted(_ state: InternalState, at: Double, sessionId: String, source: String, cwd: String?, project: String) -> InternalState {
    var s = state
    s.pendingAwards.append(XPAward(at: at, sessionId: sessionId))
    let isNewSession = s.sessions[sessionId] == nil
    observePresence(&s, at: at)
    if isNewSession {
        s.sessions[sessionId] = Session(source: source, state: .idle, prompt: nil, cwd: cwd, lastActivityAt: at, workStartedAt: nil)
        s.sessions[sessionId]?.project = project
    } else {
        let existingCwd = s.sessions[sessionId]?.cwd
        s.sessions[sessionId]?.lastActivityAt = at
        s.sessions[sessionId]?.cwd = cwd ?? existingCwd
    }
    return s
}

private func handleSessionEnded(_ state: InternalState, sessionId: String, at: Double) -> InternalState {
    var s = state
    s.sessions.removeValue(forKey: sessionId)
    return s
}

private func handleRequestArrived(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?) -> InternalState {
    setPrompt(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: nil, isApproval: false)
}

/// A blocking approval is owed an answer, so ordinary work activity must not
/// silently withdraw it.
///
/// The agent runs tools in parallel: a `Read` finishing sends PostToolUse for
/// the same session while a `Bash` PermissionRequest is still parked. That
/// used to wipe the prompt — the card vanished from popover and device
/// mid-glance and the blocked hook returned passthrough, so approval mode was
/// unreliable in any session doing more than one thing at a time. A passive
/// notification card carries no blocked caller and is still dismissed here.
private func hasBlockingApproval(_ session: Session?) -> Bool {
    session?.prompt?.isApproval == true
}

private func handleRequestCleared(_ state: InternalState, at: Double, sessionId: String) -> InternalState {
    guard let session = state.sessions[sessionId], session.state == .needsConfirmation else {
        return state
    }
    if hasBlockingApproval(session) {
        var s = state
        s.sessions[sessionId]?.lastActivityAt = at
        return s
    }
    var s = state
    s.sessions[sessionId]?.state = .working
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.lastActivityAt = at
    // Same gap as handleApprovalResolved: entering .working without a start
    // time is permanent, because keepWorking only stamps it on the way IN.
    if s.sessions[sessionId]?.workStartedAt == nil {
        s.sessions[sessionId]?.workStartedAt = at
    }
    s.sessions[sessionId]?.lastWorkSignalAt = at
    return s
}

/// "What is the agent doing" fields, stamped in one place so every path
/// (tool call, legacy signal) records the same set.
private func stampTool(_ s: inout InternalState, sessionId: String, tool: String?, hint: String?) {
    guard let tool, !tool.isEmpty else { return }
    s.sessions[sessionId]?.lastTool = tool
    s.sessions[sessionId]?.lastHint = hint
    s.sessions[sessionId]?.currentTool = tool
    s.sessions[sessionId]?.currentHint = hint
    s.sessions[sessionId]?.currentActivityKind = activityKind(tool: tool, hint: hint ?? "")
}

/// The one "session is alive and working again" rule: clears uh-oh, resets
/// the repeat counter, and (unless an approval blocks it) returns to working.
private func markAlive(_ s: inout InternalState, sessionId: String, at: Double) {
    s.sessions[sessionId]?.uhoh = nil
    s.sessions[sessionId]?.lastWorkSignalAt = at
    if s.sessions[sessionId]?.workStartedAt == nil { s.sessions[sessionId]?.workStartedAt = at }
    if !hasBlockingApproval(s.sessions[sessionId]) {
        s.sessions[sessionId]?.state = .working
        s.sessions[sessionId]?.prompt = nil
    }
}

private func handleTurnStarted(_ state: InternalState, at: Double, sessionId: String, source: String, tool: String? = nil, hint: String? = nil) -> InternalState {
    var s = state
    s.pendingAwards.append(XPAward(at: at, sessionId: sessionId))
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    stampTool(&s, sessionId: sessionId, tool: tool, hint: hint)
    markAlive(&s, sessionId: sessionId, at: at)
    return s
}

private func handleToolResulted(_ state: InternalState, at: Double, sessionId: String, source: String, tool: String, ok: Bool?, goal: String? = nil) -> InternalState {
    var s = state
    s.pendingAwards.append(XPAward(at: at, sessionId: sessionId))
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    s.sessions[sessionId]?.lastWorkSignalAt = at
    if ok == true && (goal == nil || goal == s.sessions[sessionId]?.lastGoal) {
        markAlive(&s, sessionId: sessionId, at: at)
    }
    if !hasBlockingApproval(s.sessions[sessionId]), s.sessions[sessionId]?.uhoh == nil {
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.state = .working
        if s.sessions[sessionId]?.workStartedAt == nil { s.sessions[sessionId]?.workStartedAt = at }
    }
    if !tool.isEmpty { s.sessions[sessionId]?.currentTool = tool }
    return s
}

private func handleToolCalled(_ state: InternalState, at: Double, sessionId: String, source: String, tool: String, hint: String, goal: String? = nil) -> InternalState {
    var s = state
    s.pendingAwards.append(XPAward(at: at, sessionId: sessionId))
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    let previous = s.sessions[sessionId]!
    s.sessions[sessionId]?.lastGoal = goal
    s.sessions[sessionId]?.lastWorkSignalAt = at
    if previous.workStartedAt == nil { s.sessions[sessionId]?.workStartedAt = at }
    stampTool(&s, sessionId: sessionId, tool: tool, hint: hint)
    if !hasBlockingApproval(previous) {
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.state = previous.uhoh == nil ? .working : previous.state
    }
    s.buddy.entries.insert(shortMsg(tool: tool, hint: hint, source: source), at: 0)
    if s.buddy.entries.count > 10 { s.buddy.entries.removeLast(s.buddy.entries.count - 10) }
    return s
}

private func handleTurnEnded(_ state: InternalState, at: Double, sessionId: String, source: String, outcome: TurnOutcome, tool: String? = nil, hint: String? = nil) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    stampTool(&s, sessionId: sessionId, tool: tool, hint: hint)
    let session = s.sessions[sessionId]!
    switch outcome {
    case .failed:
        enterUhoh(&s, sessionId: sessionId, kind: .error, at: at)
    case .completed:
        s.sessions[sessionId]?.uhoh = nil
        guard !hasBlockingApproval(session) else { return s }
        s.sessions[sessionId]?.state = .idle
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.workStartedAt = nil
        s.sessions[sessionId]?.lastWorkSignalAt = nil
        s.sessions[sessionId]?.currentTool = nil
        s.sessions[sessionId]?.currentHint = nil
        s.sessions[sessionId]?.currentActivityKind = nil
        guard let start = session.workStartedAt else { return s }
        s.pendingAwards.append(XPAward(at: at, sessionId: sessionId, sources: [.turn]))
        s.memory.completedTurns += 1
        let duration = max(0, at - start)
        appendFact(&s, .turnCompleted(elapsedMs: duration), id: sessionId, at: at)
        if let size = s.cheerThresholds.size(span: duration) {
            s.pendingAwards[s.pendingAwards.count - 1].cheer = size
            // A smaller nearby completion cannot truncate or restart the larger cheer.
            let folded = s.buddy.lastCompletionAt.map { at - $0 <= s.cheerThresholds.foldMs } ?? false
            s.sessions[sessionId]?.lastDone = DoneRecord(size: size, until: at + s.cheerThresholds.duration(size))
            if !folded || size.intensity > (s.doneSize?.intensity ?? 0) {
                s.doneSize = size
                s.buddy.celebrateUntil = at + s.cheerThresholds.duration(size)
            }
            s.memory.lifetimeCelebrations += 1
        }
        s.buddy.lastTaskDurationMs = duration
        s.buddy.lastCompletionAt = at
        s.buddy.lastCompleted = CompletedTask(
            id: "\(sessionId)_\(Int(at))", tool: session.lastTool, hint: session.lastHint,
            source: source, sessionLabel: session.cwd.flatMap { ($0 as NSString).lastPathComponent },
            durationMs: duration, completedAt: at,
            activityKind: session.currentActivityKind ?? .work)
    }
    return s
}

private func handleStaleTick(_ state: InternalState, now: Double) -> InternalState {
    var changed = false
    var s = state

    if let until = s.buddy.celebrateUntil, now >= until {
        s.buddy.celebrateUntil = nil
        s.buddy.lastTaskDurationMs = nil
        changed = true
    }

    if let until = s.buddy.affectionUntil, now >= until {
        s.buddy.affectionUntil = nil
        changed = true
    }

    if let until = s.buddy.greetUntil, now >= until {
        s.buddy.greetUntil = nil
        s.buddy.greetLevel = nil
        changed = true
    }

    for (id, session) in s.sessions {
        guard let prompt = session.prompt, now - prompt.arrivedAt > s.approvalTimeoutMs else { continue }
        s.sessions[id]?.prompt = nil
        s.sessions[id]?.state = .idle
        s.sessions[id]?.lastActivityAt = now
        changed = true
    }

    // Supervised sessions (live process watcher) are exempt: the watcher
    // delivers sessionEnded the instant the agent host exits, so a quiet
    // 15-minute build shouldn't make the pet give up and sleep.
    let staleIds = s.sessions.filter {
        now - $0.value.lastActivityAt > s.staleMs && !s.watchedSessionIds.contains($0.key)
    }.map(\.key)
    for id in staleIds {
        s.sessions.removeValue(forKey: id)
        changed = true
    }

    guard changed else { return state }
    return s
}

private func handleApprovalArrived(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?) -> InternalState {
    setPrompt(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: source, isApproval: true)
}

private func handleApprovalResolved(_ state: InternalState, at: Double, sessionId: String, requestId: String, decision: ApprovalDecision) -> InternalState {
    guard let session = state.sessions[sessionId],
          session.state == .needsConfirmation,
          session.prompt?.id == requestId else {
        return state
    }
    var s = state
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.state = decision == .allow ? .working : .idle
    s.sessions[sessionId]?.lastActivityAt = at
    if decision == .allow {
        // Entering .working here without a start time was permanent: the
        // keepWorking branch only stamps workStartedAt when the prior state
        // ISN'T .working, so it never filled it in later. That left the
        // session unable to ever look stalled (stall detection needs both
        // timestamps) and made its eventual completion durationless — no
        // celebrate sound, no elapsed time on the review card. It bites any
        // session Boop first meets at an approval.
        if s.sessions[sessionId]?.workStartedAt == nil {
            s.sessions[sessionId]?.workStartedAt = at
        }
        s.sessions[sessionId]?.lastWorkSignalAt = at
    }
    return s
}

/// The hook that was waiting on this approval is gone — its HTTP request was
/// cancelled (agent killed, curl timed out, or the agent's own hook timeout
/// fired and it fell back to its native prompt). The card must come down NOW:
/// leaving it up invites the user to "approve" something nobody can act on,
/// while the terminal is already showing the real prompt.
private func handleApprovalAbandoned(_ state: InternalState, at: Double, sessionId: String, requestId: String) -> InternalState {
    guard let session = state.sessions[sessionId],
          session.state == .needsConfirmation,
          session.prompt?.id == requestId else {
        // Already superseded, resolved, or expired — nothing to withdraw.
        return state
    }
    var s = state
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.state = .idle
    s.sessions[sessionId]?.lastActivityAt = at
    return s
}

/// How long a device boop keeps the desktop pet in heart-eyes. Mirrors the
/// firmware's BOOP_REACT_MS; sustained petting re-sends boops (rate-limited to
/// ~1.5s) so the window keeps sliding for the whole stroke.
let boopAffectionMs: Double = 2500

private func handleBoopArrived(_ state: InternalState, at: Double) -> InternalState {
    var s = state
    s.pendingAwards.append(XPAward(at: at, sources: []))
    appendFact(&s, .checkIn(collected: false), id: "", at: at)
    observePresence(&s, at: at)
    s.buddy.affectionUntil = at + boopAffectionMs
    return s
}

// MARK: - Personality Handlers

/// Every user-adjacent event passes through here: it stamps `lastSeenAt`,
/// triggers the return-greeting when a real absence just ended, and samples
/// the circadian histogram (at most one sample per ~30 min so activity volume
/// doesn't skew the shape). Absence is a ratchet — a gap earns warmth on
/// return, never a penalty.
private func observePresence(_ s: inout InternalState, at: Double) {
    if let last = s.memory.lastSeenAt, at - last >= PetTuning.greetGapMs {
        let big = at - last >= PetTuning.greetBigGapMs
        s.buddy.greetUntil = at + (big ? PetTuning.greetBigMs : PetTuning.greetShortMs)
        s.buddy.greetLevel = big ? 2 : 1
    }

    s.memory.lastSeenAt = at
}

private func handleSpeciesChanged(_ state: InternalState, species: String) -> InternalState {
    guard !species.isEmpty, state.buddy.species != species else { return state }
    var s = state
    s.buddy.species = species
    return s
}

private func handleReviewDismissed(_ state: InternalState) -> InternalState {
    guard state.buddy.lastCompleted != nil else { return state }
    var s = state
    s.buddy.lastCompleted = nil
    return s
}

private func handleErrorDismissed(_ state: InternalState, at: Double, sessionId: String) -> InternalState {
    guard state.sessions[sessionId]?.uhoh != nil || state.sessions[sessionId]?.state == .errored else { return state }
    var s = state
    s.sessions[sessionId]?.uhoh = nil
    s.sessions[sessionId]?.state = hasBlockingApproval(state.sessions[sessionId]) ? .needsConfirmation : .idle
    s.sessions[sessionId]?.workStartedAt = nil
    s.sessions[sessionId]?.lastWorkSignalAt = nil
    s.sessions[sessionId]?.currentTool = nil
    s.sessions[sessionId]?.currentHint = nil
    s.sessions[sessionId]?.lastActivityAt = at
    return s
}

// MARK: - Aggregation

private func aggregate(_ state: InternalState, now: Double) -> BuddyState {
    var buddy = state.buddy
    let allSessions = state.sessions.sorted { $0.key < $1.key }

    let waiting = allSessions.filter { $0.value.state == .needsConfirmation }
    let working = allSessions.filter { $0.value.state == .working && $0.value.uhoh == nil }
    let errored = allSessions.filter { $0.value.state != .needsConfirmation && ($0.value.state == .errored || $0.value.uhoh == .error) }

    buddy.sessions = SessionCounts(
        total: allSessions.count,
        running: working.count + waiting.count,
        waiting: waiting.count
    )

    let highestPrompt = waiting.min(by: { ($0.value.prompt?.arrivedAt ?? .infinity) < ($1.value.prompt?.arrivedAt ?? .infinity) })?.value.prompt
    buddy.prompt = highestPrompt

    // Build per-session breakdown for the popover. Order: needsConfirmation
    // (oldest prompt first) → errored (oldest workStartedAt) → working (oldest
    // workStartedAt) → idle (most recent first). Cap at 6 to match firmware
    // tama.lines[6] capacity.
    let waitingOrdered = waiting
        .sorted { ($0.value.prompt?.arrivedAt ?? .infinity) < ($1.value.prompt?.arrivedAt ?? .infinity) }
    let erroredOrdered = errored
        .sorted { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) }
    let workingOrdered = working
        .sorted { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) }
    let idleOrdered = allSessions
        .filter { $0.value.state == .idle && $0.value.uhoh == nil }
        .sorted { $0.value.lastActivityAt > $1.value.lastActivityAt }
    let combined = waitingOrdered + erroredOrdered + workingOrdered + idleOrdered
    var activeSnapshots: [SessionSnapshot] = []
    activeSnapshots.reserveCapacity(min(combined.count, 6))
    for (id, sess) in combined.prefix(6) {
        let tier = effortTier(elapsedMs: sess.workStartedAt.map { now - $0 } ?? 0)
        activeSnapshots.append(SessionSnapshot(
            cheer: sess.lastDone.flatMap { $0.until > now ? $0.size : nil },
            effort: tier.creatureEffort,
            id: id,
            source: sess.source,
            state: sess.uhoh == nil || sess.state == .needsConfirmation ? sess.state : .errored,
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            currentTool: sess.currentTool
        ))
    }
    buddy.activeSessions = activeSnapshots
    buddy.agentCounts = ["codex", "claude-code", "cursor", "other"].compactMap { source in
        let sessions = allSessions.map(\.value).filter {
            let group = ["codex", "claude-code", "cursor"].contains($0.source) ? $0.source : "other"
            return group == source
        }
        guard !sessions.isEmpty else { return nil }
        return AgentCounts(source: source,
            working: sessions.filter { ($0.state == .working || $0.state == .thinking) && $0.uhoh == nil }.count,
            idle: sessions.filter { $0.state == .idle && $0.uhoh == nil }.count)
    }

    // Project the oldest errored session for the popover Error card. Carries the
    // session id so dismissError(sessionId:) can target a specific one.
    let firstErroredSession = erroredOrdered.first
    buddy.firstErrored = firstErroredSession.map { id, sess in
        return ErroredSession(
            id: id,
            source: sess.source,
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            tool: sess.currentTool,
            hint: sess.currentHint,
            workStartedAt: sess.workStartedAt
        )
    }

    // The review surface clears as soon as a new prompt arrives (live state takes
    // visual primacy) or work resumes (the user reset the loop). It survives the
    // 4-second celebrate window into idle so the user can see what finished.
    if !waiting.isEmpty || !working.isEmpty {
        buddy.lastCompleted = nil
    }

    // Default — gets overwritten below in the busy branch when present.
    buddy.currentActivityKind = nil
    buddy.effortTier = nil

    let hasConnected = !allSessions.isEmpty
    buddy.desktop = DesktopLink(
        status: hasConnected ? .connected : .disconnected,
        lastHeartbeatAt: allSessions.lazy.map(\.value.lastActivityAt).max()
    )

    var creature = buddy.creature
    creature.effort = nil
    creature.cheer = nil
    creature.uhoh = nil
    creature.card = nil
    creature.overlay = nil
    creature.greetLevel = nil
    creature.nudgeRung = 0
    creature.dots = min(buddy.activeSessions.count, 5)
    creature.dotAlert = buddy.activeSessions.prefix(5).firstIndex { $0.state == .errored }
    if let prompt = highestPrompt {
        creature.state = .needsYou
        let stakes: Stakes = .checkIt // Legacy wire field; no safety classification.
        creature.card = CreatureCard(id: prompt.id, tool: prompt.tool, gloss: prompt.gloss ?? prompt.hint,
                                     stakes: stakes, index: 0, count: waiting.count, isApproval: false)
        creature.nudgeRung = state.nudges[prompt.id]?.rung ?? 0
        buddy.msg = shortMsg(tool: prompt.tool, hint: prompt.hint, source: prompt.source ?? "")
    } else if !errored.isEmpty {
        creature.state = .uhoh
        let primary = firstErroredSession?.value
        creature.uhoh = primary?.uhoh ?? .error
        let label = "Error"
        buddy.msg = primary?.currentTool.flatMap { $0.isEmpty ? nil : "\(label): \($0)" } ?? label
    } else if let until = buddy.celebrateUntil, now < until {
        creature.state = .done
        creature.cheer = state.doneSize ?? .hop
        buddy.msg = buddy.lastCompleted?.tool.map { "Done: \($0)" } ?? ""
    } else if let primary = workingOrdered.first?.value {
        creature.state = .working
        let tier = effortTier(elapsedMs: primary.workStartedAt.map { now - $0 } ?? 0)
        buddy.effortTier = tier
        creature.effort = tier.creatureEffort
        buddy.currentActivityKind = primary.currentActivityKind
        buddy.msg = primary.currentTool.map { shortMsg(tool: $0, hint: primary.currentHint ?? "", source: primary.source) } ?? ""
    } else {
        creature.state = hasConnected ? .idle : .asleep
        buddy.msg = buddy.lastCompleted?.tool.map { "Done: \($0)" } ?? ""
    }
    // Sleep wins over affection, like urgency does: a booped sleeper gets the
    // device's one-eye peek, not heart-eyes, and the desktop mirrors that.
    if creature.state == .idle || creature.state == .working || creature.state == .done {
        if let until = buddy.affectionUntil, now < until {
            creature.overlay = .boop
        } else if let until = buddy.greetUntil, now < until {
            creature.overlay = .greet
            creature.greetLevel = buddy.greetLevel == 2 ? 3 : 1
        }
    }
    buddy.creature = creature

    return buddy
}

/// Effort and celebrations share the same elapsed-duration thresholds.
private func effortTier(elapsedMs: Double) -> EffortTier {
    if elapsedMs >= PetTuning.effortGrindingMinMs { return .grinding }
    if elapsedMs >= PetTuning.effortHardMinMs { return .hard }
    return .light
}

// MARK: - Helpers

private func setPrompt(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?, isApproval: Bool) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at)

    let effectiveSource = source ?? s.sessions[sessionId]?.source
    let kind = activityKind(tool: tool, hint: hint)
    let prompt = Prompt(id: requestId, tool: tool, hint: hint, arrivedAt: at, sessionLabel: sessionLabel, source: effectiveSource, isApproval: isApproval, activityKind: kind)
    s.sessions[sessionId]?.state = .needsConfirmation
    s.sessions[sessionId]?.prompt = prompt

    let msg = shortMsg(tool: tool, hint: hint, source: effectiveSource ?? "")
    s.buddy.entries = Array(([msg] + s.buddy.entries).prefix(10))
    return s
}

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
            lastActivityAt: at,
            workStartedAt: nil
        )
    }
}

private func shortMsg(tool: String, hint: String, source: String) -> String {
    let base = !source.isEmpty && source != "other" ? "[\(source)] \(tool)" : tool
    if hint.isEmpty { return base }
    let short = hint.count <= 60 ? hint : String(hint.prefix(57)) + "..."
    return "\(base): \(short)"
}

func formatDuration(_ ms: Double) -> String {
    let seconds = Int(ms / 1000)
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    let remSeconds = seconds % 60
    return "\(minutes)m \(remSeconds)s"
}

// MARK: - Creature Policy

struct CheerThresholds: Sendable, Equatable {
    var hopMs: Double = 1500
    var cheerMs: Double = 2500
    var danceMs: Double = 4000
    var foldMs: Double = 3000
    static let defaults = CheerThresholds()

    func size(span: Double) -> CheerSize? {
        guard span >= PetTuning.celebrationMinMs else { return nil }
        if span >= PetTuning.effortGrindingMinMs { return .dance }
        if span >= PetTuning.effortHardMinMs { return .cheer }
        return .hop
    }

    func duration(_ size: CheerSize) -> Double {
        switch size { case .hop: hopMs; case .cheer: cheerMs; case .dance: danceMs }
    }
}

struct NudgeTiming: Sendable, Equatable {
    var t1: Double = 60_000
    var t2: Double = 120_000
    static let defaults = NudgeTiming()
}

struct CardNudge: Sendable, Equatable {
    var rung = 0
    var snoozed = false
}

private func setBubble(_ s: inout InternalState, _ line: String, at: Double) {
    s.buddy.creature.bubble = line
    s.bubbleUntil = at + 4000
}

private func enterUhoh(_ s: inout InternalState, sessionId: String, kind: UhohKind, at: Double) {
    s.sessions[sessionId]?.uhoh = kind
    if !hasBlockingApproval(s.sessions[sessionId]) {
        s.sessions[sessionId]?.state = .errored
        s.sessions[sessionId]?.prompt = nil
    }
}

private func dismissNudge(_ state: InternalState, at: Double) -> InternalState {
    var s = state
    guard let card = s.buddy.creature.card,
          var nudge = s.nudges[card.id] else { return s }
    nudge.rung = 0
    nudge.snoozed = true
    s.nudges[card.id] = nudge
    return s
}

/// Timers use only supplied event time. Each card owns its ladder even when
/// another session's older card is currently on top.
private func updateCreatureTimers(_ s: inout InternalState, event: BuddyEvent) {
    if case .staleTick = event, let until = s.bubbleUntil, event.at >= until {
        s.buddy.creature.bubble = nil
        s.bubbleUntil = nil
    }
    let liveIds = Set(s.sessions.values.compactMap { $0.prompt?.id })
    s.nudges = s.nudges.filter { liveIds.contains($0.key) }
    for session in s.sessions.values {
        guard let prompt = session.prompt else { continue }
        var nudge = s.nudges[prompt.id] ?? CardNudge()
        if !nudge.snoozed, case .staleTick = event {
            let elapsed = event.at - prompt.arrivedAt
            nudge.rung = elapsed >= s.nudgeTiming.t2 ? 2 : elapsed >= s.nudgeTiming.t1 ? 1 : 0
        }
        s.nudges[prompt.id] = nudge
    }
}

private func appendFact(_ s: inout InternalState, _ fact: Fact, id: String, at: Double) {
    s.pendingFacts.append(PendingFact(fact: fact, sessionId: id, project: s.sessions[id]?.project ?? "unknown", at: at))
}
