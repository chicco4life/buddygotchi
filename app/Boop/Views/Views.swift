import BoopKit
import SwiftUI

/// The popover (UX.md §7): sessions by agent, Boop's name, level and days,
/// focus, away and volume, Boop's record, and a way into settings.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = model.status {
                let s = status.snapshot
                HStack {
                    Text(s.name).font(.headline)
                    Spacer()
                    Text("Level \(s.level) · day \(s.days)").foregroundStyle(.secondary)
                }
                Text(deviceLine(status)).font(.caption).foregroundStyle(.secondary)
                Divider()
                sessions(s)
                Divider()
                Toggle("Focus mode", isOn: Binding(get: { s.focus }, set: { model.runtime?.setFocus($0) }))
                Toggle("I'm away", isOn: Binding(get: { status.away }, set: { model.runtime?.setAway($0) }))
                HStack {
                    Text("Volume")
                    Slider(value: Binding(get: { Double(s.vol) }, set: { model.runtime?.setVolume(Int($0.rounded())) }),
                           in: 0...10, step: 1)
                }
                Divider()
                Text("Record").font(.subheadline.bold())
                Text("\(status.finished) tasks finished · \(status.projects) projects · \(s.days) days together · level \(s.level), \(s.prog)% to the next")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Boop isn't running yet.").foregroundStyle(.secondary)
            }
            if model.restartAgents {
                Text("Restart open agent sessions so they pick up Boop's hooks.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button("Settings…") { delegate.showSettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    func deviceLine(_ status: Runtime.Status) -> String {
        guard status.connected else { return "Looking for Boop's body…" }
        return status.device.map { "Connected to \($0.id) (firmware \($0.fw))" } ?? "Connected"
    }

    @ViewBuilder
    func sessions(_ s: StateSnapshot) -> some View {
        if s.threads.isEmpty {
            Text("No agents running").foregroundStyle(.secondary)
        } else {
            let agents = s.threads.map { $0[0] }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ForEach(agents, id: \.self) { agent in
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.capitalized).font(.subheadline.bold())
                    ForEach(Array(s.threads.filter { $0[0] == agent }.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row[1])
                            Spacer()
                            Text(label(row[2])).foregroundStyle(row[2] == "wait" ? .orange : .secondary)
                        }.font(.caption)
                    }
                }
            }
        }
    }

    func label(_ status: String) -> String {
        switch status {
        case "wait": "needs you"
        case "work": "working"
        default: "idle"
        }
    }
}

/// Settings: agents and hooks, the device, the brain and API key, and what
/// Boop remembers about you.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ViewState var apiKey = Keychain.apiKey() ?? ""
    @ViewState var saved = false

    var body: some View {
        Form {
            Section("Agents and hooks") {
                ForEach(HookInstaller.Agent.allCases, id: \.self) { agent in
                    HStack {
                        Text(agent.displayName)
                        Spacer()
                        Text(describe(model.hooks[agent])).foregroundStyle(.secondary)
                        if model.hooks[agent] == .installed {
                            Button("Remove") { model.remove(agent) }
                        } else if case .unreadable = model.hooks[agent] {
                            EmptyView()
                        } else {
                            Button(model.hooks[agent] == .outdated ? "Repair" : "Install") { model.install(agent) }
                        }
                    }
                }
                if model.restartAgents {
                    Text("Restart open agent sessions to pick up the change.").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Device") {
                if let status = model.status, status.connected {
                    Text(status.device.map { "\($0.id), firmware \($0.fw)" } ?? "Connected")
                } else {
                    Text("Not connected").foregroundStyle(.secondary)
                }
            }
            Section("Brain") {
                Picker("Brain", selection: Binding(get: { model.brain }, set: {
                    model.brain = $0
                    model.runtime?.setBrain($0)
                })) {
                    Text("Apple's on-device model").tag("apple")
                    Text("Rules only").tag("rules")
                }
                Text("Changes take effect when Boop restarts.").font(.caption).foregroundStyle(.secondary)
                SecureField("API key (for a cloud brain)", text: $apiKey)
                HStack {
                    Button("Save key") { saved = Keychain.setAPIKey(apiKey) }
                    if saved { Text("Saved in the Keychain").font(.caption).foregroundStyle(.secondary) }
                }
                Text("Cloud brains aren't available yet.").font(.caption).foregroundStyle(.secondary)
            }
            Section("What Boop remembers about you") {
                if model.remembered.isEmpty {
                    Text("Nothing yet").foregroundStyle(.secondary)
                }
                ForEach(model.remembered, id: \.self) { line in
                    HStack {
                        Text(line)
                        Spacer()
                        Button("Delete") { model.forget(line) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
    }

    func describe(_ health: HookInstaller.Health?) -> String {
        switch health {
        case .installed?: "installed"
        case .outdated?: "needs repair"
        case .unreadable(let why)?: why
        default: "not installed"
        }
    }
}

/// First launch (UX.md §6): name Boop, sweet or cheeky, and the hooks it
/// will add, one agent at a time.
struct SetupView: View {
    @ObservedObject var model: AppModel
    let done: (String, LongTerm.Nature, [HookInstaller.Agent]) -> Void
    @ViewState var name = ""
    @ViewState var nature = LongTerm.Nature.sweet
    @ViewState var agents: Set<HookInstaller.Agent> = Set(HookInstaller.Agent.allCases)

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                Picker("Sweet or cheeky?", selection: $nature) {
                    Text("Sweet").tag(LongTerm.Nature.sweet)
                    Text("Cheeky").tag(LongTerm.Nature.cheeky)
                }.pickerStyle(.segmented)
            }
            ForEach(HookInstaller.Agent.allCases.filter(model.installer.detected), id: \.self) { agent in
                Section(agent.displayName) {
                    Toggle("Add Boop's hooks", isOn: Binding(
                        get: { agents.contains(agent) },
                        set: { if $0 { agents.insert(agent) } else { agents.remove(agent) } }))
                    Text("In \(model.installer.configURL(agent).path):\n" + model.installer.preview(agent))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Button("Wake Boop up") {
                done(name.trimmingCharacters(in: .whitespaces), nature,
                     HookInstaller.Agent.allCases.filter { agents.contains($0) && model.installer.detected($0) })
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name.count > 23)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}
