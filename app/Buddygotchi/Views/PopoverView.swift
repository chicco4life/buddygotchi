import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    @AppStorage("setupCompleted") private var setupCompleted = false
    @AppStorage("buddySpecies") private var species = "cat"
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

            if let prompt = engine.state.prompt {
                Spacer().frame(height: 10)
                ToolCardView(
                    prompt: prompt,
                    onApprove: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .allow) } : nil,
                    onDeny: prompt.isApproval ? { engine.resolveApproval(requestId: prompt.id, decision: .deny) } : nil
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
        engine.state.prompt != nil
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
                    Text(prompt.hint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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
