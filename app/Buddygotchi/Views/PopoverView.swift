import SwiftUI

struct PopoverView: View {
    let engine: BuddyEngine
    @AppStorage("setupCompleted") private var setupCompleted = false
    @AppStorage("buddySpecies") private var species = "cat"
    @State private var showingSettings = false
    @State private var showingDebug = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !setupCompleted {
                SetupWizardView(engine: engine) { setupCompleted = true }
            } else if showingSettings {
                SettingsView(isPresented: $showingSettings, engine: engine)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else if showingDebug {
                DebugView(isPresented: $showingDebug, entries: engine.state.entries)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showingDebug)
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

            if let prompt = engine.state.prompt {
                Spacer().frame(height: 10)
                ToolCardView(prompt: prompt)
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

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(action: { showingDebug = true }) {
                Image(systemName: "ladybug")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Debug log")

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    private var liveViewHeight: CGFloat {
        engine.state.prompt != nil ? BuddyTheme.liveViewExpandedHeight : BuddyTheme.liveViewHeight
    }

    private var speciesColor: Color {
        buddySpeciesColor(for: species)
    }

    private var stateColor: Color {
        switch engine.state.pet.state {
        case .attention: BuddyTheme.attentionAmber
        case .celebrate: speciesColor
        case .busy: BuddyTheme.accent
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
                    Text(prompt.hint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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
        switch source {
        case "claude-code": "Claude Code"
        case "cursor": "Cursor"
        case "codex": "Codex"
        default: source
        }
    }
}

// MARK: - Debug Pane

struct DebugView: View {
    @Binding var isPresented: Bool
    let entries: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Debug")
                            .font(.system(.headline, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to live view")
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal)
                .padding(.top, 8)

            if entries.isEmpty {
                Spacer()
                Text("No recent events")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.fullPanelHeight)
        .preferredColorScheme(.dark)
    }
}
