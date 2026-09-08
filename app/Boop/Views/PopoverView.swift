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
    @State private var showingShelf = false
    @AppStorage(DefaultsKey.agentDrawingsEnabled) private var agentDrawingsEnabled = true
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
            BuddyTheme.paper.ignoresSafeArea()

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
                } else if showingShelf {
                    KeepsakeShelfView(engine: engine, isPresented: $showingShelf)
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
        .animation(reduceMotion ? nil : .buddyEase(0.2), value: showingShelf)
        .onReceive(NotificationCenter.default.publisher(for: .boopOpenSettings)) { _ in
            showingSettings = true
        }
        .onHover { hovering in
            if hovering { onUserInteraction?() }
        }
    }

    private var unfinishedSetupView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text(BuddyCopy.Onboarding.finishMeeting)
                    .font(.buddy(15, weight: .semibold))
                    .foregroundStyle(BuddyTheme.ink)
                    .multilineTextAlignment(.center)
                Text(BuddyCopy.Onboarding.finishMeetingSubtitle)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Button(BuddyCopy.Onboarding.meetBuddy, action: onOpenOnboarding)
                .buttonStyle(BuddyPrimaryButtonStyle())

            Spacer()
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.unfinishedSetupHeight)
        .preferredColorScheme(.light)
    }

    // MARK: - Live View

    // The popover is the approve/deny surface plus a health readout. Anything the
    // device says better does not belong here.
    private var liveView: some View {
        VStack(spacing: 0) {
            headerRow

            if showMenuHint {
                Spacer().frame(height: 6)
                Text(BuddyCopy.Onboarding.menuHint)
                    .font(.buddy(9.5, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amberInk)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        showMenuHint = false
                    }
            }

            // Agent expression (System E). Never rendered while a prompt is
            // pending — the reducer guarantees the overlay is gone by then —
            // and always labeled with who is speaking.
            if let overlay = engine.state.agentOverlay {
                Spacer().frame(height: 8)
                AgentExpressionRow(overlay: overlay)
                    .transition(.opacity)
            }

            // A drawing the pet is holding up (E4) — same S1 guarantee.
            // The settings toggle also silences resurfaced memories here.
            if let drawing = engine.state.agentDrawing, agentDrawingsEnabled {
                Spacer().frame(height: 8)
                AgentDrawingCard(drawing: drawing, isMemory: engine.state.agentDrawingIsMemory == true)
                    .transition(.opacity)
            }

            if let prompt = engine.state.prompt {
                Spacer().frame(height: 12)
                ToolCardView(
                    prompt: prompt,
                    waitingCount: engine.state.sessions.waiting,
                    onApprove: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .allow) } : nil,
                    onDeny: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .deny) } : nil
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let errored = engine.state.firstErrored {
                Spacer().frame(height: 12)
                ErrorCardView(
                    source: errored.source,
                    sessionLabel: errored.sessionLabel,
                    tool: errored.tool,
                    hint: errored.hint,
                    onDismiss: { engine.dismissError(sessionId: errored.id) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            let rows = activityRows
            if !rows.isEmpty {
                Spacer().frame(height: 12)
                ActivityList(rows: rows)
                    .transition(.opacity)
            } else if engine.state.sessions.total == 0 {
                Spacer().frame(height: 12)
                EmptyAgentsView()
                    .transition(.opacity)
            }

            Spacer(minLength: 12)

            footerRow
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth)
        .frame(minHeight: BuddyTheme.liveViewHeight)
        .animation(reduceMotion ? nil : Animation.buddyBloom(), value: engine.state.prompt != nil)
        .preferredColorScheme(.light)
    }

    /// Name, state, and the way out. One row instead of a pill and a footer.
    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(statusName)
                .font(.buddy(13, weight: .semibold))
                .foregroundStyle(BuddyTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Text(stateLabel)
                .font(.buddy(9.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateFill.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(stateFill.opacity(0.35), lineWidth: BuddyTheme.hairlineWidth))
                .foregroundStyle(stateInk)
                .fixedSize()
                .accessibilityLabel("\(statusName), \(stateLabel)")

            Spacer(minLength: 8)

            // The museum door: only appears once there's something on the
            // shelf — a discovered surface, not an announced feature.
            if !engine.petMemory.keepsakes.isEmpty {
                Button(action: { showingShelf = true }) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .buttonStyle(BuddyPlainButtonStyle())
                .accessibilityLabel(BuddyCopy.shared.popover.keepsakeShelf)
            }

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .accessibilityLabel(BuddyCopy.settings)
        }
    }

    /// Connection health, and the server warning when there is one — the warning
    /// replaces the status rather than stacking another row on top of it.
    private var footerRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(serverWarning == nil ? statusColor : BuddyTheme.clayInk)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text(serverWarning ?? engine.state.desktop.status.rawValue)
                .font(.buddy(11))
                .foregroundStyle(serverWarning == nil ? BuddyTheme.inkFaint : BuddyTheme.clayInk)
                .lineLimit(2)

            Spacer(minLength: 8)

            if engine.state.sessions.total > 0 {
                Text(BuddyCopy.shared.popover.activeTemplate.replacingOccurrences(of: "{count}", with: "\(engine.state.sessions.running)"))
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connectionAccessibilityLabel)
    }

    /// One line per active session, plus a line for a just-finished task. The
    /// reducer clears `lastCompleted` on the next prompt or work signal, so the
    /// done line ages out on its own.
    private var activityRows: [ActivityRow] {
        let completed = engine.state.lastCompleted
        var claimed = false
        var rows = engine.state.activeSessions.map { session -> ActivityRow in
            // The session that just finished is still listed, as idle. Say what it
            // finished instead of saying nothing — that is the whole of what the
            // review card was for.
            if !claimed, let completed, session.state == .idle, completed.source == session.source {
                claimed = true
                return ActivityRow(completed: completed, id: session.id)
            }
            return ActivityRow(session: session, state: engine.state)
        }
        if !claimed, let completed, rows.isEmpty {
            rows.append(ActivityRow(completed: completed))
        }
        return rows
    }

    private var serverWarning: String? {
        guard let serverHealth else { return nil }
        if case .failed(let reason) = serverHealth.status {
            return BuddyCopy.shared.popover.serverWarningTemplate
                .replacingOccurrences(of: "{port}", with: "\(BuddyConfig.default.httpPort)")
                .replacingOccurrences(of: "{reason}", with: reason)
        }
        return nil
    }

    private var statusName: String {
        let trimmed = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? engine.state.pet.species : trimmed
    }

    private var connectionAccessibilityLabel: String {
        let status = engine.state.desktop.status.rawValue
        guard engine.state.sessions.total > 0 else {
            return BuddyCopy.shared.popover.desktopStatusTemplate.replacingOccurrences(of: "{status}", with: status)
        }
        let sessions = BuddyCopy.shared.popover.activeSessionsTemplate.replacingOccurrences(of: "{count}", with: "\(engine.state.sessions.running)")
        return BuddyCopy.shared.popover.desktopStatusWithSessionsTemplate
            .replacingOccurrences(of: "{status}", with: status)
            .replacingOccurrences(of: "{sessions}", with: sessions)
    }

    private var stateInk: Color { BuddyTheme.stateInk(engine.state.pet.state) }
    private var stateFill: Color { BuddyTheme.stateFill(engine.state.pet.state) }

    private var stateLabel: String { engine.state.creature.statusLabel }

    private var statusColor: Color {
        switch engine.state.desktop.status {
        case .connected: BuddyTheme.green
        case .disconnected: BuddyTheme.inkFaint
        }
    }
}

// MARK: - Agent Expression (System E)

/// The agent-channel surface: always carried in the agent's identity color,
/// always labeled with who is speaking, styled like nothing the system uses.
private struct AgentExpressionRow: View {
    let overlay: AgentOverlay

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(identityColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(overlay.agentId)
                    .font(.buddy(9, weight: .semibold))
                    .foregroundStyle(BuddyTheme.inkFaint)
                Text(overlay.say ?? "feels \(overlay.emotion)")
                    .font(.buddy(12, weight: overlay.say == nil ? .regular : .medium))
                    .foregroundStyle(BuddyTheme.ink)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(identityColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(identityColor.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(overlay.agentId) \(overlay.say ?? "feels \(overlay.emotion)")")
    }

    private var identityColor: Color { agentIdentityColor(overlay.color) }
}

/// The agent identity palette, shared by the expression row and the drawing
/// card so an agent's channel is one color everywhere.
private func agentIdentityColor(_ name: String?) -> Color {
    switch name {
    case "coral": Color(red: 0.94, green: 0.50, blue: 0.42)
    case "amber": Color(red: 0.95, green: 0.69, blue: 0.28)
    case "mint": Color(red: 0.38, green: 0.78, blue: 0.60)
    case "sky": Color(red: 0.36, green: 0.66, blue: 0.92)
    case "lavender": Color(red: 0.65, green: 0.58, blue: 0.90)
    case "rose": Color(red: 0.92, green: 0.50, blue: 0.68)
    case "sand": Color(red: 0.82, green: 0.70, blue: 0.50)
    case "teal": Color(red: 0.26, green: 0.70, blue: 0.72)
    default: BuddyTheme.inkSoft
    }
}

/// A drawing the pet is holding up (E4). Rendered chunky from the fixed
/// 16-color palette; framed in the agent's identity color like every other
/// agent-channel surface.
private struct AgentDrawingCard: View {
    let drawing: AgentDrawing
    /// The pet dug this one out for a returning agent — "remember this?".
    var isMemory: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            DrawingGrid(drawing: drawing)
                .frame(width: gridSize.width, height: gridSize.height)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Circle()
                    .fill(identityColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(caption)
                    .font(.buddy(10))
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(identityColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(identityColor.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drawing from \(drawing.agentId)\(drawing.caption.map { ": \($0)" } ?? "")")
    }

    private var caption: String {
        if isMemory {
            let original = drawing.caption.map { " · \($0)" } ?? ""
            return "\(BuddyCopy.shared.popover.rememberThis)\(original)"
        }
        if let c = drawing.caption, !c.isEmpty { return "\(drawing.agentId): \(c)" }
        return "from \(drawing.agentId)"
    }

    private var identityColor: Color { agentIdentityColor(drawing.color) }

    private var gridSize: CGSize {
        let w = max(drawing.width, 1), h = max(drawing.height, 1)
        let cell = (128.0 / CGFloat(max(w, h))).rounded(.down)
        return CGSize(width: cell * CGFloat(w), height: cell * CGFloat(h))
    }
}

private struct DrawingGrid: View {
    let drawing: AgentDrawing

    var body: some View {
        Canvas { context, size in
            let w = max(drawing.width, 1), h = max(drawing.height, 1)
            let cell = min(size.width / CGFloat(w), size.height / CGFloat(h))
            for (y, row) in drawing.rows.enumerated() {
                for (x, digit) in row.enumerated() {
                    guard let color = drawingPaletteColor(digit) else { continue }
                    // Overdraw by a hair so cells butt cleanly at non-integer scales.
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                      width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Empty / Server Rows

private struct EmptyAgentsView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(.caption))
                .foregroundStyle(BuddyTheme.inkSoft)
                .padding(.top, 1)
            Text(BuddyCopy.shared.popover.emptyAgents)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.wellCornerRadius)
                .fill(BuddyTheme.ink.opacity(0.03))
        )
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
        VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let source = prompt.source {
                        Text(sourceName(source))
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.amberInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BuddyTheme.ink.opacity(0.07), in: Capsule())
                            .alignmentGuide(.firstTextBaseline) { context in
                                context[VerticalAlignment.center] + 4
                            }
                    }
                    Spacer(minLength: 8)
                    if waitingCount > 1 {
                        Text(BuddyCopy.shared.popover.moreWaitingTemplate.replacingOccurrences(of: "{count}", with: "\(waitingCount - 1)"))
                            .font(.buddy(9.5, weight: .semibold))
                            .foregroundStyle(BuddyTheme.amberInk)
                    }
                    if let label = prompt.sessionLabel {
                        Text(label)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.ink.opacity(0.55))
                    }
                }

                Text(prompt.tool)
                    .font(.buddy(13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(buddyTruncationMode(for: prompt.tool))

                if !prompt.hint.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: prompt.activityKind.sfSymbol)
                            .font(.system(.caption2))
                            .foregroundStyle(BuddyTheme.ink.opacity(0.55))
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
                            .accessibilityHidden(true)
                        Text(prompt.hint)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.ink.opacity(0.70))
                            .lineLimit(3)
                            .truncationMode(pathLikeHint ? .middle : .tail)
                    }
                }

                if let onApprove, let onDeny {
                    HStack(spacing: 8) {
                        Button(action: onDeny) {
                            HStack(spacing: 6) {
                                Text(BuddyCopy.deny)
                                if isHoveringActions {
                                    Text("⌫")
                                        .font(.buddy(11))
                                        .foregroundStyle(BuddyTheme.inkFaint)
                                }
                            }
                            .font(.buddy(11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(BuddyTheme.paperRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(BuddyTheme.clayInk.opacity(0.35), lineWidth: BuddyTheme.hairlineWidth))
                            .foregroundStyle(BuddyTheme.clayInk)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                        .keyboardShortcut(.delete, modifiers: [])

                        Button(action: onApprove) {
                            HStack(spacing: 6) {
                                Text(BuddyCopy.approve)
                                if isHoveringActions {
                                    Text("↵")
                                        .font(.buddy(11))
                                        .foregroundStyle(BuddyTheme.inkFaint)
                                }
                            }
                            .font(.buddy(11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(BuddyTheme.paperRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(BuddyTheme.amberInk.opacity(0.45), lineWidth: BuddyTheme.hairlineWidth))
                            .foregroundStyle(BuddyTheme.amberInk)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])

                        Spacer()
                    }
                    .onHover { isHoveringActions = $0 }
                }
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .fill(waitingCount > 1 ? BuddyTheme.lanternHot : BuddyTheme.lantern)
        )
        // The accent bar is an overlay, not an HStack sibling: a Shape with only
        // its width constrained is greedy vertically, and it was stretching the
        // whole card to fill the popover.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BuddyTheme.amberInk)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .strokeBorder(BuddyTheme.hairlineStrong, lineWidth: BuddyTheme.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toolAccessibilityLabel)
    }

    private func sourceName(_ source: String) -> String {
        AgentKind(rawValue: source)?.displayName ?? source
    }

    private var toolAccessibilityLabel: String {
        let template = prompt.hint.isEmpty
            ? BuddyCopy.shared.popover.toolRequestTemplate
            : BuddyCopy.shared.popover.toolRequestWithHintTemplate
        return template
            .replacingOccurrences(of: "{tool}", with: prompt.tool)
            .replacingOccurrences(of: "{hint}", with: prompt.hint)
    }

    private var pathLikeHint: Bool {
        prompt.activityKind == .read || prompt.activityKind == .write
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
        VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(BuddyTheme.clayInk)
                    Text(headlineLabel)
                        .font(.buddy(11))
                        .foregroundStyle(BuddyTheme.inkSoft)
                    Spacer()
                    if let sessionLabel {
                        Text(sessionLabel)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.inkFaint)
                    }
                }

                if let tool {
                    Text(tool)
                        .font(.buddy(13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(buddyTruncationMode(for: tool))
                }

                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.buddy(11))
                        .foregroundStyle(BuddyTheme.inkSoft)
                        .lineLimit(3)
                        .truncationMode(buddyTruncationMode(for: hint))
                }

                if let onDismiss {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Text(BuddyCopy.dismiss)
                                .font(.buddy(9.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(BuddyTheme.paper, in: Capsule())
                                .overlay(Capsule().strokeBorder(BuddyTheme.clayInk.opacity(0.30), lineWidth: BuddyTheme.hairlineWidth))
                                .foregroundStyle(BuddyTheme.clayInk)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                    }
                    .padding(.top, 4)
                }
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .fill(BuddyTheme.paperRaised)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BuddyTheme.clayInk)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                .strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(errorAccessibilityLabel)
    }

    private var headlineLabel: String {
        let agentName = AgentKind(rawValue: source)?.displayName ?? source
        return BuddyCopy.shared.popover.errorWithAgentTemplate.replacingOccurrences(of: "{agent}", with: agentName)
    }

    private var errorAccessibilityLabel: String {
        if let tool, let hint {
            return BuddyCopy.shared.popover.errorAccessibilityWithHintTemplate
                .replacingOccurrences(of: "{agent}", with: source)
                .replacingOccurrences(of: "{tool}", with: tool)
                .replacingOccurrences(of: "{hint}", with: hint)
        }
        if let tool {
            return BuddyCopy.shared.popover.errorAccessibilityWithToolTemplate
                .replacingOccurrences(of: "{agent}", with: source)
                .replacingOccurrences(of: "{tool}", with: tool)
        }
        return BuddyCopy.shared.popover.errorAccessibilityTemplate.replacingOccurrences(of: "{agent}", with: source)
    }
}

// MARK: - Activity List

/// One line of "who is doing what". Replaces the separate current-activity,
/// thinking, review, and session-list surfaces, which between them showed four
/// variations on the same sentence.
struct ActivityRow: Identifiable {
    let id: String
    let tone: Color
    let agent: String
    let status: String
    let detail: String?
    let trailing: String?

    init(session: SessionSnapshot, state: BuddyState) {
        id = session.id
        tone = ActivityRow.tone(for: session.state)
        agent = AgentKind(rawValue: session.source)?.displayName ?? session.source
        status = ActivityRow.label(for: session.state)
        detail = activityDetail(for: session, in: state)
        // Elapsed is derived from the state's own timestamp rather than a live
        // clock: the popover redraws on every state change, and a ticking second
        // counter is exactly the restlessness this surface is meant to lose.
        trailing = ActivityRow.elapsed(session: session, in: state)
            ?? session.sessionLabel.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A task that just finished, once nothing is running. The reducer clears
    /// `lastCompleted` on the next prompt or work signal, so this ages out.
    init(completed: CompletedTask, id: String = "completed") {
        self.id = id
        tone = BuddyTheme.greenInk
        agent = AgentKind(rawValue: completed.source ?? "")?.displayName ?? (completed.source ?? BuddyCopy.shared.popover.task)
        status = BuddyCopy.shared.popover.doneLabel
        detail = [completed.tool, completed.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        trailing = completed.durationMs.map { formatElapsed(ms: $0) }
    }

    private static func tone(for state: SessionState) -> Color {
        switch state {
        case .working: BuddyTheme.work
        case .idle: BuddyTheme.inkFaint
        case .needsConfirmation: BuddyTheme.amberInk
        case .errored: BuddyTheme.clayInk
        case .thinking: BuddyTheme.work
        }
    }

    private static func label(for state: SessionState) -> String {
        switch state {
        case .working: BuddyCopy.shared.popover.busy
        case .idle: BuddyCopy.shared.popover.idle
        case .needsConfirmation: BuddyCopy.shared.popover.waiting
        case .errored: BuddyCopy.shared.popover.error
        case .thinking: BuddyCopy.shared.popover.thinking
        }
    }

    /// Only the thinking session carries a start time; SessionSnapshot does not.
    private static func elapsed(session: SessionSnapshot, in state: BuddyState) -> String? {
        guard let thinking = state.firstThinking, thinking.id == session.id,
              let start = thinking.workStartedAt, state.updatedAt > start else { return nil }
        return formatElapsed(ms: state.updatedAt - start)
    }
}

private func formatElapsed(ms: Double) -> String {
    let secs = Int(ms / 1000)
    return secs < 60 ? "\(secs)s" : "\(secs / 60)m \(secs % 60)s"
}

/// The detail line for a session. For whichever session is currently working,
/// `state.msg` carries a richer "Tool: hint" string than the session snapshot
/// does, so prefer that and fall back to the snapshot's tool.
private func activityDetail(for session: SessionSnapshot, in state: BuddyState) -> String? {
    let tool = nonEmpty(session.currentTool)
    guard session.state == .working, session.id == state.activeSessions.first(where: { $0.state == .working })?.id else {
        return tool
    }
    let parsed = parseActivityMessage(state.msg)
    switch (tool ?? parsed.tool, parsed.hint) {
    case let (.some(tool), .some(hint)): return "\(tool) — \(hint)"
    case let (.some(tool), .none): return tool
    case let (.none, .some(hint)): return hint
    default: return nil
    }
}

/// Agent messages arrive as an optional "[prefix] " followed by "Tool: hint".
private func parseActivityMessage(_ raw: String) -> (tool: String?, hint: String?) {
    var message = raw
    if message.first == "[", let close = message.firstIndex(of: "]") {
        let afterClose = message.index(after: close)
        if afterClose < message.endIndex, message[afterClose] == " " {
            message = String(message[message.index(after: afterClose)...])
        }
    }
    guard let separator = message.firstIndex(of: ":") else {
        return (nonEmpty(message), nil)
    }
    let tool = String(message[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
    let hint = String(message[message.index(after: separator)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "...", with: "…")
    return (nonEmpty(tool), nonEmpty(hint))
}

/// A single token — an identifier like `mcp__filesystem__read_text_file` or a
/// path like `.../oauth2/strategies/Foo.ts` — carries meaning at both ends, so
/// it loses its middle. Anything with spaces is a command or a sentence, which
/// reads front to back and loses its tail.
func buddyTruncationMode(for text: String) -> Text.TruncationMode {
    text.contains(" ") ? .tail : .middle
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

struct ActivityList: View {
    let rows: [ActivityRow]
    var maxRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.prefix(maxRows)) { row in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(row.tone)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(row.agent)
                                .font(.buddy(11, weight: .semibold))
                                .foregroundStyle(BuddyTheme.ink)
                                .lineLimit(1)
                            Text(row.status)
                                .font(.buddy(11))
                                .foregroundStyle(BuddyTheme.inkSoft)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        if let detail = row.detail {
                            Text(detail)
                                .font(.buddy(11))
                                .foregroundStyle(BuddyTheme.inkFaint)
                                .lineLimit(1)
                                .truncationMode(buddyTruncationMode(for: detail))
                        }
                    }

                    Spacer(minLength: 8)

                    if let trailing = row.trailing {
                        Text(trailing)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.inkFaint)
                            .lineLimit(1)
                            .truncationMode(buddyTruncationMode(for: trailing))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.agent) \(row.status)\(row.detail.map { ", \($0)" } ?? "")")
            }

            if rows.count > maxRows {
                Text(BuddyCopy.shared.popover.moreSessionsTemplate.replacingOccurrences(of: "{count}", with: "\(rows.count - maxRows)"))
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkFaint)
                    .padding(.leading, 12)
            }
        }
    }
}
