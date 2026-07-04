import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    @AppStorage(DefaultsKey.setupCompleted) private var setupCompleted = false
    @AppStorage(DefaultsKey.buddySpecies) private var species = "cat"
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !setupCompleted {
                SetupWizardView(engine: engine, esp32Output: esp32Output) { setupCompleted = true }
            } else if showingSettings {
                SettingsView(isPresented: $showingSettings, engine: engine, esp32Output: esp32Output)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                liveView
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showingSettings)
    }

    // MARK: - Live View

    private var liveView: some View {
        VStack(spacing: 0) {
            PetStageView(petState: engine.state.pet.state, species: species)
                .padding(.top, 4)

            Spacer().frame(height: 6)

            statusPill

            Spacer().frame(height: 10)

            connectionBar

            if engine.state.activeSessions.count > 1 {
                Spacer().frame(height: 6)
                SessionListView(sessions: engine.state.activeSessions)
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
                    onApprove: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .allow) } : nil,
                    onDeny: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .deny) } : nil
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .frame(width: BuddyTheme.popoverWidth, height: liveViewHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: engine.state.prompt != nil)
        .preferredColorScheme(.dark)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Text(species)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(speciesColor)

            Text(engine.state.pet.state.rawValue)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.15), in: Capsule())
                .foregroundStyle(stateColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(species), \(engine.state.pet.state.rawValue)")
    }

    private var connectionBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text(engine.state.desktop.status.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            if engine.state.sessions.total > 0 {
                Text("\(engine.state.sessions.running) active")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Desktop \(engine.state.desktop.status.rawValue)\(engine.state.sessions.total > 0 ? ", \(engine.state.sessions.running) active sessions" : "")")
    }

    @State private var isExporting = false

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(action: { Task { await exportBugReport() } }) {
                Group {
                    if isExporting {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "ladybug")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .disabled(isExporting)
            .accessibilityLabel("Export bug report")

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .accessibilityLabel("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.tertiary)
        }
    }

    private func exportBugReport() async {
        isExporting = true
        defer { isExporting = false }

        guard let data = await engine.diagnosticLog.exportBundle(engine: engine) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "buddygotchi-report-\(formatter.string(from: Date.now)).json"

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {}
    }

    private var liveViewHeight: CGFloat {
        (engine.state.prompt != nil || engine.state.lastCompleted != nil || engine.state.firstErrored != nil)
            ? BuddyTheme.liveViewExpandedHeight
            : BuddyTheme.liveViewHeight
    }

    private var speciesColor: Color {
        buddySpeciesColor(for: species)
    }

    private var stateColor: Color {
        switch engine.state.pet.state {
        case .attention: BuddyTheme.attentionAmber
        case .busy: BuddyTheme.accent
        case .celebrate: BuddyTheme.celebrateGreen
        case .error: BuddyTheme.destructive
        case .thinking: BuddyTheme.accent
        default: .secondary
        }
    }

    private var statusColor: Color {
        switch engine.state.desktop.status {
        case .connected: BuddyTheme.connected
        case .disconnected: BuddyTheme.disconnected
        }
    }
}

// MARK: - Tool Card

struct ToolCardView: View {
    let prompt: Prompt
    var onApprove: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BuddyTheme.attentionAmber)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let source = prompt.source {
                        Text(sourceName(source))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(BuddyTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BuddyTheme.accentSubtle, in: Capsule())
                    }
                    Spacer()
                    if let label = prompt.sessionLabel {
                        Text(label)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(prompt.tool)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))

                if !prompt.hint.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: prompt.activityKind.sfSymbol)
                            .font(.system(.caption2))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        Text(prompt.hint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                if let onApprove, let onDeny {
                    HStack(spacing: 8) {
                        Button(action: onDeny) {
                            Text("Deny")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(BuddyTheme.destructive.opacity(0.15), in: Capsule())
                                .foregroundStyle(BuddyTheme.destructive)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())

                        Button(action: onApprove) {
                            Text("Approve")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(BuddyTheme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(BuddyTheme.accent)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])

                        Spacer()
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .fill(BuddyTheme.cardFillElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                        .strokeBorder(BuddyTheme.cardStrokeElevated, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool request: \(prompt.tool)\(prompt.hint.isEmpty ? "" : ", \(prompt.hint)")")
    }

    private func sourceName(_ source: String) -> String {
        AgentKind(rawValue: source)?.displayName ?? source
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
                .font(.system(.caption, design: .monospaced))
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
        case .verify: BuddyTheme.celebrateGreen
        case .read: .secondary
        case .write: BuddyTheme.accent
        case .shell: .secondary
        case .web: BuddyTheme.accent
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
                .fill(BuddyTheme.celebrateGreen)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(BuddyTheme.celebrateGreen)
                    Text(headlineLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let durationMs = completed.durationMs {
                        Text(formatDuration(durationMs))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let tool = completed.tool {
                    HStack(spacing: 6) {
                        Image(systemName: completed.activityKind.sfSymbol)
                            .font(.system(.caption2))
                            .foregroundStyle(BuddyTheme.celebrateGreen)
                            .accessibilityHidden(true)
                        Text(tool)
                            .font(.system(.callout, design: .monospaced, weight: .semibold))
                    }
                }

                if let hint = completed.hint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Text("Dismiss")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(BuddyTheme.celebrateGreen.opacity(0.12), in: Capsule())
                                .foregroundStyle(BuddyTheme.celebrateGreen)
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
                .fill(BuddyTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                        .strokeBorder(BuddyTheme.cardStroke, lineWidth: 0.5)
                )
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
                .fill(BuddyTheme.destructive)
                .frame(width: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(BuddyTheme.destructive)
                    Text(headlineLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let sessionLabel {
                        Text(sessionLabel)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                if let tool {
                    Text(tool)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                }

                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Text("Dismiss")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(BuddyTheme.destructive.opacity(0.12), in: Capsule())
                                .foregroundStyle(BuddyTheme.destructive)
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
                .fill(BuddyTheme.cardFillElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                        .strokeBorder(BuddyTheme.destructive.opacity(0.3), lineWidth: 0.5)
                )
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
        HStack(spacing: 6) {
            Image(systemName: "brain")
                .font(.system(.caption2))
                .foregroundStyle(BuddyTheme.accent)
                .accessibilityHidden(true)
            Text("Thinking")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            if let tool = thinking.tool, !tool.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(tool)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
            if let elapsed = elapsed {
                Text(elapsed)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thinking · \(AgentKind(rawValue: thinking.source)?.displayName ?? thinking.source)\(thinking.tool.map { ", \($0)" } ?? "")")
    }

    private var elapsed: String? {
        guard let start = thinking.workStartedAt else { return nil }
        let secs = Int((now - start) / 1000)
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
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor(for: sess.state))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(displayName(for: sess.source))
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(stateLabel(for: sess.state))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let tool = sess.currentTool, !tool.isEmpty {
                        Text(tool)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let label = sess.sessionLabel, !label.isEmpty {
                        Text(label)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
        case .working: return BuddyTheme.accent
        case .idle: return Color.secondary.opacity(0.5)
        case .needsConfirmation: return BuddyTheme.attentionAmber
        case .errored: return BuddyTheme.destructive
        case .thinking: return BuddyTheme.accent.opacity(0.6)
        }
    }
}
