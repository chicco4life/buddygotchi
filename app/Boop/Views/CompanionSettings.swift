import SwiftUI
import AppKit

struct CompanionSettings: View {
    let engine: BuddyEngine
    let device: ESP32Output
    var onRetired: () -> Void = {}
    var sections = SettingsSection.companion
    var body: some View {
        Group {
            ForEach(sections, id: \.self) { section in
                content(section)
            }

        }

    }
    @ViewBuilder private func content(_ section: SettingsSection) -> some View {
        switch section {
        case .focus:
            BuddySettingToggle(
                title: BuddyCopy.phase7("quietMode", language: engine.state.language),
                description: BuddyCopy.phase7("quietModeDescription", language: engine.state.language),
                isOn: Binding(get: { engine.quietMode }, set: { engine.setQuietMode($0) }))
        case .language:
            Picker(BuddyCopy.phase7("language", language: engine.state.language), selection: Binding(get: { engine.state.language }, set: { value in Task { await engine.setLanguage(value) } })) {
                Text(BuddyCopy.phase7("english", language: engine.state.language)).tag("en")
                Text(BuddyCopy.phase7("korean", language: engine.state.language)).tag("ko")
            }
        case .voice:
            Button(engine.state.language == "ko" ? "버디 행동 편집…" : "Edit buddy behavior…") {
                do {
                    let url = try engine.editableBehaviorGuide()
                    if !NSWorkspace.shared.open(url) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } catch { NSAlert(error: error).runModal() }
            }
        case .profile:
            Button(BuddyCopy.phase7("profile", language: engine.state.language)) { CompanionWindows.shared.profile(engine: engine) }
        default: EmptyView()
        }
    }
}
