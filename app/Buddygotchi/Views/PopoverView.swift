import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let serverHealth: ServerHealth?
    var onUserInteraction: (() -> Void)? = nil
    var onOpenOnboarding: () -> Void = {}
    @AppStorage(DefaultsKey.setupCompleted) private var setupCompleted = false
    @AppStorage(DefaultsKey.buddyName) private var buddyName = ""
    @AppStorage(DefaultsKey.showMenuHint) private var showMenuHint = false
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        engine: BuddyEngine,
        esp32Output: ESP32Output,
        serverHealth: ServerHealth? = nil,
        onUserInteraction: (() -> Void)? = nil,
        onOpenOnboarding: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.esp32Output = esp32Output
        self.serverHealth = serverHealth
        self.onUserInteraction = onUserInteraction
        self.onOpenOnboarding = onOpenOnboarding
    }

    var body: some View {
        ZStack {
            BuddyTheme.night.ignoresSafeArea()

            Group {
                if !setupCompleted {
                    unfinishedSetupView
                } else if showingSettings {
                    SettingsView(
                        isPresented: $showingSettings,
                        engine: engine,
                        esp32Output: esp32Output,
                        serverHealth: serverHealth,
                        onOpenOnboarding: onOpenOnboarding
                    )
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    liveView
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .buddyEase(0.2), value: showingSettings)
        .onReceive(NotificationCenter.default.publisher(for: .buddygotchiOpenSettings)) { _ in
            showingSettings = true
        }
        .onHover { hovering in
            if hovering { onUserInteraction?() }
        }
    }

    private var unfinishedSetupView: some View {
        VStack(spacing: 16) {
            PetStageView(petState: .sleep, species: engine.state.pet.species)
                .padding(.top, 8)

            VStack(spacing: 5) {
                Text(BuddyCopy.Onboarding.finishMeeting)
                    .font(.buddy(15, weight: .semibold))
                    .foregroundStyle(BuddyTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(BuddyCopy.Onboarding.finishMeetingSubtitle)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(BuddyCopy.Onboarding.meetBuddy, action: onOpenOnboarding)
                .buttonStyle(BuddyPrimaryButtonStyle())

            Spacer()
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth, height: 260)
        .preferredColorScheme(.dark)
    }

    // MARK: - Live View

    private var liveView: some View {
        VStack(spacing: 0) {
            PetStageView(petState: engine.state.pet.state, species: engine.state.pet.species)
                .padding(.top, 4)

            Spacer().frame(height: 6)

            statusPill

            if showMenuHint {
                Spacer().frame(height: 6)
                Text(BuddyCopy.Onboarding.menuHint)
                    .font(.buddy(9.5, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amber)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        showMenuHint = false
                    }
            }

            Spacer().frame(height: 10)

            connectionBar

            if let serverWarning {
                Spacer().frame(height: 6)
                ServerWarningRow(message: serverWarning)
                    .transition(.opacity)
            }

            if engine.state.activeSessions.count > 1 {
                Spacer().frame(height: 6)
                SessionListView(sessions: engine.state.activeSessions)
                    .transition(.opacity)
            }

            if engine.state.pet.state == .sleep && engine.state.sessions.total == 0 {
                Spacer().frame(height: 10)
                EmptyAgentsView()
                    .transition(.opacity)
            }

            if engine.state.pet.state == .busy && !engine.state.msg.isEmpty {
                Spacer().frame(height: 8)
                CurrentActivityRow(msg: engine.state.msg, kind: engine.state.currentActivityKind ?? .work)
                    .transition(.opacity)
            } else if engine.state.pet.state == .thinking, let thinking = engine.state.firstThinking {
                Spacer().frame(height: 8)
                ThinkingRow(thinking: thinking, now: engine.state.updatedAt)
                    .transition(.opacity)
            }

            if let prompt = engine.state.prompt {
                Spacer().frame(height: 10)
                ToolCardView(
                    prompt: prompt,
                    waitingCount: engine.state.sessions.waiting,
                    onApprove: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .allow) } : nil,
                    onDeny: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .deny) } : nil
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                if let errored = engine.state.firstErrored {
                    ErrorTrailerView(errored: errored)
                        .transition(.opacity)
                }
            } else if let errored = engine.state.firstErrored {
                Spacer().frame(height: 10)
                ErrorCardView(
                    source: errored.source,
                    sessionLabel: errored.sessionLabel,
                    tool: errored.tool,
                    hint: errored.hint,
                    onDismiss: { engine.dismissError(sessionId: errored.id) }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let completed = engine.state.lastCompleted {
                Spacer().frame(height: 10)
                ReviewCardView(
                    completed: completed,
                    onDismiss: { engine.dismissReview() }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(16)
        .frame(width: BuddyTheme.popoverWidth)
        .frame(minHeight: BuddyTheme.liveViewHeight)
        .animation(reduceMotion ? nil : .buddyEase(0.25), value: engine.state.prompt != nil)
        .preferredColorScheme(.dark)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Text(statusName)
                .font(.buddy(11, weight: .semibold))
                .foregroundStyle(speciesColor)

            Text(engine.state.pet.state.rawValue)
                .font(.buddy(9.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.15), in: Capsule())
                .foregroundStyle(stateColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusName), \(engine.state.pet.state.rawValue)")
    }

    private var connectionBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text(engine.state.desktop.status.rawValue)
                .font(.buddy(11))
                .foregroundStyle(.tertiary)

            Spacer()

            if engine.state.sessions.total > 0 {
                Text("\(engine.state.sessions.running) active")
                    .font(.buddy(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BuddyTheme.textPrimary.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Desktop \(engine.state.desktop.status.rawValue)\(engine.state.sessions.total > 0 ? ", \(engine.state.sessions.running) active sessions" : "")")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .accessibilityLabel("Settings")
        }
    }

    private var serverWarning: String? {
        guard let serverHealth else { return nil }
        if case .failed(let reason) = serverHealth.status {
            return "Can't listen on port \(BuddyConfig.default.httpPort) — \(reason)"
        }
        return nil
    }

    private var speciesColor: Color {
        buddySpeciesColor(for: engine.state.pet.species)
    }

    private var statusName: String {
        let trimmed = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? engine.state.pet.species : trimmed
    }

    private var stateColor: Color {
        switch engine.state.pet.state {
        case .attention: BuddyTheme.amber
        case .busy: BuddyTheme.workGlow
        case .celebrate: BuddyTheme.green
        case .error: BuddyTheme.stuckRed
        case .thinking: BuddyTheme.workGlow
        default: BuddyTheme.textSecondary
        }
    }

    private var statusColor: Color {
        switch engine.state.desktop.status {
        case .connected: BuddyTheme.green
        case .disconnected: BuddyTheme.textTertiary
        }
    }
}

// MARK: - Empty / Server Rows

private struct EmptyAgentsView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text("No agents awake. Open Claude Code, Cursor, or Codex and send a message — your buddy will hear it.")
                .font(.buddy(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BuddyTheme.textPrimary.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ServerWarningRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(BuddyTheme.stuckRed)
                .frame(width: 5, height: 5)
            Text(message)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.stuckRed)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BuddyTheme.stuckRed.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorTrailerView: View {
    let errored: ErroredSession

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(.caption2))
                .foregroundStyle(BuddyTheme.stuckRed)
            Text("Also: \(AgentKind(rawValue: errored.source)?.displayName ?? errored.source) hit an error")
                .font(.buddy(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tool Card

struct ToolCardView: View {
    let prompt: Prompt
    var waitingCount: Int = 1
    var onApprove: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil
    @State private var isHoveringActions = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BuddyTheme.amber)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let source = prompt.source {
                        Text(sourceName(source))
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BuddyTheme.amber.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if waitingCount > 1 {
                        Text("+\(waitingCount - 1) more waiting")
                            .font(.buddy(9.5, weight: .semibold))
                            .foregroundStyle(BuddyTheme.amber)
                    }
                    if let label = prompt.sessionLabel {
                        Text(label)
                            .font(.buddy(11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(prompt.tool)
                    .font(.buddy(13, weight: .semibold))

                if !prompt.hint.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: prompt.activityKind.sfSymbol)
                            .font(.system(.caption2))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(prompt.hint)
                            .font(.buddy(11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(pathLikeHint ? .middle : .tail)
                    }
                }

                if let onApprove, let onDeny {
                    HStack(spacing: 8) {
                        Button(action: onDeny) {
                            HStack(spacing: 6) {
                                Text("Deny")
                                if isHoveringActions {
                                    Text("⌫")
                                        .font(.buddy(11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .font(.buddy(11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(BuddyTheme.stuckRed.opacity(0.15), in: Capsule())
                            .foregroundStyle(BuddyTheme.stuckRed)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                        .keyboardShortcut(.delete, modifiers: [])

                        Button(action: onApprove) {
                            HStack(spacing: 6) {
                                Text("Approve")
                                if isHoveringActions {
                                    Text("↵")
                                        .font(.buddy(11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .font(.buddy(11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(BuddyTheme.amber.opacity(0.15), in: Capsule())
                            .foregroundStyle(BuddyTheme.amber)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])

                        Spacer()
                    }
                    .onHover { isHoveringActions = $0 }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .fill(BuddyTheme.nightRaised2)
        )
        .clipShape(RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool request: \(prompt.tool)\(prompt.hint.isEmpty ? "" : ", \(prompt.hint)")")
    }

    private func sourceName(_ source: String) -> String {
        AgentKind(rawValue: source)?.displayName ?? source
    }

    private var pathLikeHint: Bool {
        prompt.activityKind == .read || prompt.activityKind == .write
    }
}

// MARK: - Current Activity Row

struct CurrentActivityRow: View {
    let msg: String
    var kind: ActivityKind = .work

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.sfSymbol)
                .font(.system(.caption2))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            Text(msg)
                .font(.buddy(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Working: \(msg)")
    }

    private var iconColor: Color {
        switch kind {
        case .verify: BuddyTheme.green
        case .read: .secondary
        case .write: BuddyTheme.amber
        case .shell: .secondary
        case .web: BuddyTheme.amber
        case .work: Color.secondary.opacity(0.6)
        }
    }
}

// MARK: - Review Card

struct ReviewCardView: View {
    let completed: CompletedTask
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BuddyTheme.green)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(BuddyTheme.green)
                    Text(headlineLabel)
                        .font(.buddy(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let durationMs = completed.durationMs {
                        Text(formatDuration(durationMs))
                            .font(.buddy(11))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let tool = completed.tool {
                    HStack(spacing: 6) {
                        Image(systemName: completed.activityKind.sfSymbol)
                            .font(.system(.caption2))
                            .foregroundStyle(BuddyTheme.green)
                            .accessibilityHidden(true)
                        Text(tool)
                            .font(.buddy(13, weight: .semibold))
                    }
                }

                if let hint = completed.hint, !hint.isEmpty {
                    Text(hint)
                        .font(.buddy(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Text("Dismiss")
                                .font(.buddy(9.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(BuddyTheme.green.opacity(0.12), in: Capsule())
                                .foregroundStyle(BuddyTheme.green)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .fill(BuddyTheme.nightRaised)
        )
        .clipShape(RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Completed: \(completed.tool ?? "task")\(completed.hint.map { ", \($0)" } ?? "")")
    }

    private var headlineLabel: String {
        if let source = completed.source {
            return "Done · \(AgentKind(rawValue: source)?.displayName ?? source)"
        }
        return "Done"
    }
}

// MARK: - Error Card

struct ErrorCardView: View {
    let source: String
    var sessionLabel: String? = nil
    var tool: String? = nil
    var hint: String? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BuddyTheme.stuckRed)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(BuddyTheme.stuckRed)
                    Text(headlineLabel)
                        .font(.buddy(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let sessionLabel {
                        Text(sessionLabel)
                            .font(.buddy(11))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let tool {
                    Text(tool)
                        .font(.buddy(13, weight: .semibold))
                }

                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.buddy(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Text("Dismiss")
                                .font(.buddy(9.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(BuddyTheme.stuckRed.opacity(0.12), in: Capsule())
                                .foregroundStyle(BuddyTheme.stuckRed)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .fill(BuddyTheme.nightRaised2)
        )
        .clipShape(RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error in \(source)\(tool.map { ": \($0)" } ?? "")\(hint.map { ", \($0)" } ?? "")")
    }

    private var headlineLabel: String {
        let agentName = AgentKind(rawValue: source)?.displayName ?? source
        return "Error · \(agentName)"
    }
}

// MARK: - Thinking Row

/// Calm "agent is thinking hard" surface. Shown when a working session has gone
/// silent past the work-stall threshold (≥ 5 min default) but isn't errored.
/// No Dismiss — the user doesn't need to act; the agent is presumed alive.
struct ThinkingRow: View {
    let thinking: ThinkingSession
    let now: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(.caption2))
                    .foregroundStyle(BuddyTheme.amber)
                    .accessibilityHidden(true)
                Text("Thinking")
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let tool = thinking.tool, !tool.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(tool)
                        .font(.buddy(11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer()
                if let elapsed = elapsed(at: timeline.date.timeIntervalSince1970 * 1000) {
                    Text(elapsed)
                        .font(.buddy(11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thinking · \(AgentKind(rawValue: thinking.source)?.displayName ?? thinking.source)\(thinking.tool.map { ", \($0)" } ?? "")")
        }
    }

    private func elapsed(at currentTime: Double) -> String? {
        guard let start = thinking.workStartedAt else { return nil }
        let base = max(now, currentTime)
        let secs = Int((base - start) / 1000)
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }
}

// MARK: - Session List

struct SessionListView: View {
    let sessions: [SessionSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sessions) { sess in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(stateColor(for: sess.state))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(displayName(for: sess.source))
                                .font(.buddy(9.5, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(stateLabel(for: sess.state))
                                .font(.buddy(11))
                                .foregroundStyle(.secondary)
                        }
                        if let tool = sess.currentTool, !tool.isEmpty {
                            Text(tool)
                                .font(.buddy(11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if let label = sess.sessionLabel, !label.isEmpty {
                        Text(label)
                            .font(.buddy(11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                .padding(.horizontal, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(displayName(for: sess.source)) \(stateLabel(for: sess.state))\(sess.currentTool.map { ", \($0)" } ?? "")")
            }
        }
    }

    private func displayName(for source: String) -> String {
        AgentKind(rawValue: source)?.displayName ?? source
    }

    private func stateLabel(for state: SessionState) -> String {
        switch state {
        case .working: return "busy"
        case .idle: return "idle"
        case .needsConfirmation: return "waiting"
        case .errored: return "error"
        case .thinking: return "thinking"
        }
    }

    private func stateColor(for state: SessionState) -> Color {
        switch state {
        case .working: return BuddyTheme.workGlow
        case .idle: return Color.secondary.opacity(0.5)
        case .needsConfirmation: return BuddyTheme.amber
        case .errored: return BuddyTheme.stuckRed
        case .thinking: return BuddyTheme.workGlow.opacity(0.6)
        }
    }
}
