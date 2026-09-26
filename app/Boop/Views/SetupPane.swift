import BoopKit
import SwiftUI

/// First launch (UX.md §6), inside the popover: hello, a name and sweet or
/// cheeky, which agents to watch, then wake Boop up. One thing per step.
struct SetupPane: View {
    @ObservedObject var model: AppModel
    @ViewState private var forward = true
    @ViewState private var showHooks = false
    @FocusState private var nameFocused: Bool

    private var step: SetupDraft.Step { model.setup.step }
    private var name: String { model.setup.trimmedName.isEmpty ? "Boop" : model.setup.trimmedName }

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, Theme.gutter)
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
                        removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(height: 448)
        .padding(.horizontal, Theme.gutter + 4)
        .padding(.bottom, Theme.gutter)
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(SetupDraft.Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.accent : Theme.well)
                    .frame(width: s == step ? 26 : 12, height: 5)
            }
        }
        .animation(.boopEase(0.3), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(SetupDraft.Step.allCases.count)")
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .hello: hello
        case .name: naming
        case .agents: agents
        case .ready: ready
        }
    }

    private func go(_ to: SetupDraft.Step) {
        forward = to.rawValue > step.rawValue
        withAnimation(.boopEase(0.35)) { model.setup.step = to }
    }

    private func title(_ text: String, _ detail: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(text).font(.boop(20)).multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nav(back: SetupDraft.Step?, next: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        HStack {
            if let back {
                Button("Back") { go(back) }.buttonStyle(.quiet).font(.system(size: 12))
            }
            Spacer()
            Button(next, action: action)
                .buttonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled)
        }
    }

    // MARK: Steps

    private var hello: some View {
        VStack(spacing: Theme.gapLoose) {
            Spacer()
            BoopFace(mood: .idle, size: 104)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            title("Hi! I'm Boop.",
                  "A little creature for your desk. I watch your coding agents, cheer when they finish, and tell you when one needs you.")
            Spacer()
            Button("Let's go") { go(.name) }
                .buttonStyle(ProminentButtonStyle(wide: true))
                .keyboardShortcut(.defaultAction)
        }
    }

    private var naming: some View {
        VStack(spacing: Theme.gap) {
            Spacer(minLength: 0)
            BoopFace(mood: model.setup.nature == .cheeky ? .working : .happy, size: 64)
            title("What should I be called?")
            TextField("A name", text: Binding(
                get: { model.setup.name },
                set: { model.setup.name = StateSnapshot.clip($0) }))
                .textFieldStyle(.plain)
                .font(.boop(16, .medium))
                .multilineTextAlignment(.center)
                .padding(.vertical, 9)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(nameFocused ? Theme.accent : Theme.hairlineStrong, lineWidth: nameFocused ? 1.5 : 1))
                .focused($nameFocused)
                .onAppear { nameFocused = true }
            Text("Names are for keeps, so pick one you love.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.inkSoft)
            Text("Sweet or cheeky?").font(.system(size: 12, weight: .semibold)).padding(.top, Theme.gapSnug)
            HStack(spacing: Theme.gapSnug) {
                natureCard(.sweet, "heart.fill", Theme.rose, "Sweet", "Warm and encouraging")
                natureCard(.cheeky, "face.smiling.inverse", Theme.accent, "Cheeky", "Playful, a bit sassy")
            }
            Spacer(minLength: 0)
            nav(back: .hello, next: "Continue", enabled: !model.setup.trimmedName.isEmpty) { go(.agents) }
        }
    }

    private func natureCard(_ nature: LongTerm.Nature, _ icon: String, _ tone: Color, _ title: String, _ detail: String) -> some View {
        let selected = model.setup.nature == nature
        return Button {
            withAnimation(.boopPop) { model.setup.nature = nature }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tone)
                    .scaleEffect(selected ? 1.12 : 1)
                Text(title).font(.boop(13))
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? tone.opacity(0.1) : Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(selected ? tone : Theme.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var agents: some View {
        let detected = HookInstaller.Agent.allCases.filter(model.installer.detected)
        return VStack(spacing: Theme.gap) {
            title("Which agents should I watch?",
                  "I listen through their hooks. I never approve, deny or block anything.")
                .padding(.top, Theme.gapLoose)
            VStack(spacing: Theme.gapSnug) {
                ForEach(HookInstaller.Agent.allCases, id: \.self) { agentRow($0) }
            }
            .padding(.top, Theme.gapTight)
            if !detected.isEmpty {
                DisclosureGroup(isExpanded: $showHooks) {
                    ScrollView {
                        Text(detected.filter { model.setup.agents.contains($0) }.map { agent in
                            "\(model.installer.configURL(agent).path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\n"
                                + model.installer.preview(agent)
                        }.joined(separator: "\n\n"))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.inkSoft)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(height: 104)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
                    .padding(.top, 4)
                } label: {
                    Text("See exactly what gets added").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                }
                .tint(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            nav(back: .name, next: "Continue") { go(.ready) }
        }
    }

    private func agentRow(_ agent: HookInstaller.Agent) -> some View {
        let found = model.installer.detected(agent)
        let on = found && model.setup.agents.contains(agent)
        return Card(padding: 0) {
            SettingRow(icon: agentSymbol(agent == .claude ? "claude" : "codex"), title: agent.displayName,
                       detail: found ? "Found on this Mac" : "Not found. You can add it later in Settings.",
                       detailTone: found ? Theme.sageInk : Theme.inkSoft) {
                Toggle("Watch \(agent.displayName)", isOn: Binding(get: { on }, set: { value in
                    if value { model.setup.agents.insert(agent) } else { model.setup.agents.remove(agent) }
                }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!found)
            }
        }
        .opacity(found ? 1 : 0.75)
    }

    private var ready: some View {
        VStack(spacing: Theme.gapLoose) {
            Spacer(minLength: 0)
            BoopFace(mood: .happy, size: 88)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            title("Ready to wake \(name)?")
            VStack(alignment: .leading, spacing: Theme.gap) {
                tip("powerplug.fill", "Plug \(name)'s body into USB power. It finds this Mac over Bluetooth by itself.")
                tip("hand.raised.fill", "macOS will ask to use Bluetooth, and the microphone the first time you hold \(name)'s button to talk.")
                if !model.setup.agents.isEmpty {
                    tip("arrow.clockwise", "Restart any open agent sessions afterwards so I can hear them.")
                }
            }
            .padding(.horizontal, 4)
            if let error = model.setup.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Theme.clayInk).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            nav(back: .agents, next: "Wake \(name) up") { model.finishSetup() }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.gapSnug + 2) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Theme.accentInk).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
