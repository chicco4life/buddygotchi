import BoopKit
import SwiftUI

/// Settings, inside the popover (UX.md §7): sound, agents and hooks, the
/// device, the mode and Jev's key, and what Boop remembers.
struct SettingsPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat
    @ViewState private var apiKey = ""
    @ViewState private var keySaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Settings") { model.pane = .overview }
            FittedScroll(maxHeight: maxHeight) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    PaneSection("Sound") { sound }
                    PaneSection("Agents") { agents }
                    PaneSection("Device") { device }
                    PaneSection("Mode") { modes }
                    PaneSection("What \(model.name) remembers") { remembered }
                    PaneSection("About") { about }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gapLoose)
            }
        }
        .task {
            // Off the main thread: a Keychain prompt would freeze the popover.
            let read = model.readKey
            apiKey = await Task.detached { read() }.value ?? ""
        }
    }

    // MARK: Sound

    private var sound: some View {
        let s = model.status?.snapshot
        return Card(padding: 0) {
            SettingRow(icon: s?.vol == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "Volume",
                       detail: "How loud \(model.name) mumbles and chirps.") {
                HStack(spacing: 6) {
                    Slider(value: Binding(get: { Double(s?.vol ?? 6) },
                                          set: { model.setVolume(Int($0.rounded())) }),
                           in: 0...10, step: 1)
                        .controlSize(.small)
                        .frame(width: 96)
                        .accessibilityLabel("Volume")
                    Text(s?.vol == 0 ? "Off" : "\(s?.vol ?? 6)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
        .disabled(model.status == nil)
    }

    // MARK: Agents

    private var agents: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(HookInstaller.Agent.allCases.enumerated()), id: \.element) { index, agent in
                        if index > 0 { Hairline().padding(.leading, 40) }
                        agentRow(agent)
                    }
                }
            }
            if model.restartAgents {
                Label("Restart open agent sessions to pick up the change.", systemImage: "arrow.clockwise")
                    .font(.system(size: 11)).foregroundStyle(Theme.amberInk)
                    .padding(.leading, 2)
            }
        }
    }

    private func agentRow(_ agent: HookInstaller.Agent) -> some View {
        let health = model.hooks[agent]
        let found = model.installer.detected(agent)
        let (text, tone): (String, Color) = switch health {
        case .installed?: ("Connected", Theme.sageInk)
        case .outdated?: ("Needs a repair", Theme.amberInk)
        case .unreadable(let why)?: ("Can't read its settings: \(why)", Theme.clayInk)
        case .clientMissing?: ("boop-hook isn't built. Run make build, then restart Boop.", Theme.clayInk)
        default: found ? ("Not connected", Theme.inkSoft) : ("Not found on this Mac", Theme.inkFaint)
        }
        return SettingRow(icon: agentSymbol(agent == .claude ? "claude" : "codex"), title: agent.displayName,
                          detail: text, detailTone: tone) {
            switch health {
            case .installed?:
                Button("Remove") { model.remove(agent) }.buttonStyle(.row)
            case .outdated?:
                Button("Repair") { model.install(agent) }.buttonStyle(.rowFilled)
            case .unreadable?, .clientMissing?:
                EmptyView()
            default:
                Button("Connect") { model.install(agent) }.buttonStyle(.rowFilled).disabled(!found)
            }
        }
    }

    // MARK: Device

    private var device: some View {
        let connected = model.status?.connected == true
        let how = switch model.link {
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .none: ""
        }
        let firmware = model.status?.device.map { ", firmware \($0.fw)" } ?? ""
        let detail = connected ? "Connected over \(how)\(firmware)"
            : model.link == .none ? "This copy of Boop runs without a device"
            : "Looking for it over \(how). Plug it into USB power."
        return Card(padding: 0) {
            SettingRow(icon: "rectangle.inset.filled", title: "\(model.name)'s body", detail: detail,
                       detailTone: connected ? Theme.sageInk : Theme.inkSoft) {
                if model.link != .none {
                    Button("Reconnect") { model.reconnectDevice() }.buttonStyle(.row).fixedSize()
                        .help("Drop the connection and look for \(model.name)'s body again now")
                }
            }
        }
    }

    // MARK: Mode

    /// What each mode does, in one line (BEHAVIORS.md §6).
    private func about(_ mode: Mode) -> String {
        switch mode {
        case .chatty: "A mumble and a word for every turn, and chatter while agents work. Decides with plain rules on this Mac."
        case .normal: "A balance. TypeSafe's Jev decides, online, with your API key below; without one, \(model.name) acts as in Chatty."
        case .calm: "Only what you need: something needs you, a turn failed, or a long one finished. Decides with plain rules on this Mac."
        }
    }

    /// Why the brain running isn't the mode's usual one, if it isn't.
    private var brainNote: String? {
        guard let status = model.status else { return nil }
        if status.writer == "none" { return "Apple's model can't run here, so mumbles have no word." }
        if model.mode == .normal && !status.classifier.hasPrefix("jev") { return "No Jev key yet, so \(model.name) acts as in Chatty." }
        return nil
    }

    private var modes: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                        Text("Chatty").tag(Mode.chatty)
                        Text("Normal").tag(Mode.normal)
                        Text("Calm").tag(Mode.calm)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    Text(about(model.mode))
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = brainNote {
                        Text(note)
                            .font(.system(size: 11)).foregroundStyle(Theme.amberInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .disabled(model.status == nil)
                Hairline().padding(.leading, 12)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Theme.gapSnug) {
                        SecureField("Jev API key", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairlineStrong, lineWidth: 1))
                            .onChange(of: apiKey) { keySaved = false }
                        Button(keySaved ? "Saved" : "Save") {
                            keySaved = Keychain.setKey(apiKey, for: .jev)
                            if keySaved { model.jevKeyChanged() }
                        }
                            .buttonStyle(.row)
                            .disabled(keySaved)
                    }
                    Text("For Normal. Kept in your Keychain. With Jev, what happens and \(model.name)'s memory go to TypeSafe with each call.")
                        .font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
    }

    // MARK: Remembered

    private var remembered: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                if model.remembered.isEmpty {
                    Text("Nothing yet. Tell \(model.name) something lasting about you, like \"remember I ship on Fridays\", and it keeps it here.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(Array(model.remembered.enumerated()), id: \.element) { index, line in
                    if index > 0 { Hairline().padding(.leading, 12) }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug) {
                        Text(line).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.boopSettle) { model.forget(line) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.quiet)
                        .help("Forget this")
                        .accessibilityLabel("Forget “\(line)”")
                    }
                    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: About

    private var about: some View {
        Card(padding: 0) {
            SettingRow(icon: "info.circle", title: "Version", detail: nil) {
                Text(BoopVersion.current).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// One settings row: an icon, a title with an optional line under it, and
/// a control at the trailing edge.
struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    let detail: String?
    var detailTone: Color = Theme.inkSoft
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.gapSnug + 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(detailTone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.gapSnug)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}
