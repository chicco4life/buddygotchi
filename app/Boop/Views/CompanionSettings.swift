import SwiftUI

struct CompanionSettings: View {
    let engine: BuddyEngine
    let device: ESP32Output
    var onRetired: () -> Void = {}
    var sections = SettingsSection.companion
    @State private var quick = ""
    @State private var voice = "auto"
    @State private var volume = 1
    @State private var leaderboard = false
    @State private var leaderboardURL = ""
    @State private var friendCode = ""
    @State private var focus = false
    @State private var start = 9
    @State private var end = 17
    @State private var confirming = false
    @State private var error = false
    @State private var retiring = false
    var body: some View {
        Group {
            ForEach(sections, id: \.self) { section in
                content(section)
            }

        }
        .onAppear {
            quick = engine.quickCommand; volume = engine.soundVolume; voice = engine.voiceSetting
            leaderboardURL = engine.leaderboardURL
            leaderboard = engine.boolSetting(DefaultsKey.leaderboardOptIn)
            let hours = engine.focusHours; focus = hours.enabled; start = hours.start; end = hours.end
        }
        .sheet(isPresented: $confirming) {
            VStack(spacing: 20) {
                Text(BuddyCopy.phase7("retireMessage", language: engine.state.language))
                HStack {
                    Button(BuddyCopy.book(language: engine.state.language).common.cancel) { confirming = false }
                    Button(BuddyCopy.phase7("retire", language: engine.state.language), role: .destructive) {
                        confirming = false; retiring = true
                        Task {
                            do { try await engine.retire(sendToDevice: { device.sendRetire() }); onRetired() }
                            catch { self.error = true }
                            retiring = false
                        }
                    }
                }
            }.padding(28).frame(width: 340)
        }
        .alert(BuddyCopy.phase7("error", language: engine.state.language), isPresented: $error) { Button(BuddyCopy.phase7("continue", language: engine.state.language)) {} }
    }
    @ViewBuilder private func content(_ section: SettingsSection) -> some View {
        switch section {
        case .sounds:
            Picker(BuddyCopy.phase7("volume", language: engine.state.language), selection: Binding(get: { volume }, set: { volume = $0; engine.setSoundVolume(volume) })) { ForEach(0...3, id: \.self) { Text(String($0)).tag($0) } }
        case .focus:
            Toggle(BuddyCopy.phase7("focusHours", language: engine.state.language), isOn: Binding(get: { focus }, set: { focus = $0; engine.setFocusHours(enabled: focus, start: start, end: end) }))
            HStack {
                Picker(BuddyCopy.phase7("start", language: engine.state.language), selection: Binding(get: { start }, set: { start = $0; engine.setFocusHours(enabled: focus, start: start, end: end) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker(BuddyCopy.phase7("end", language: engine.state.language), selection: Binding(get: { end }, set: { end = $0; engine.setFocusHours(enabled: focus, start: start, end: end) })) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            }.disabled(!focus)
        case .language:
            Picker(BuddyCopy.phase7("language", language: engine.state.language), selection: Binding(get: { engine.state.language }, set: { value in Task { await engine.setLanguage(value) } })) {
                Text(BuddyCopy.phase7("english", language: engine.state.language)).tag("en")
                Text(BuddyCopy.phase7("korean", language: engine.state.language)).tag("ko")
            }
        case .voice:
            Picker(BuddyCopy.phase7("voice", language: engine.state.language), selection: $voice) {
                Text(BuddyCopy.phase7("auto", language: engine.state.language)).tag("auto")
                Text(BuddyCopy.phase7("off", language: engine.state.language)).tag("off")
            }.onChange(of: voice) { _, value in Task { await engine.setVoiceRuntime(value) } }
        case .quick:
            TextField(BuddyCopy.phase7("quick", language: engine.state.language), text: $quick).font(.body.monospaced()).textFieldStyle(.roundedBorder)
                .onChange(of: quick) { _, text in engine.setQuickCommand(text) }
            Text(BuddyCopy.phase7("quickNote", language: engine.state.language)).font(.footnote).foregroundStyle(BuddyTheme.inkSoft)
        case .leaderboard:
            Toggle(BuddyCopy.phase7("leaderboard", language: engine.state.language), isOn: Binding(get: { leaderboard }, set: { leaderboard = $0; engine.configureLeaderboard(url: leaderboardURL, optIn: leaderboard) }))
            if leaderboard {
                HStack {
                    TextField(BuddyCopy.phase7("leaderboardURL", language: engine.state.language), text: $leaderboardURL)
                        .onSubmit { engine.configureLeaderboard(url: leaderboardURL, optIn: leaderboard) }
                    Button(BuddyCopy.phase7("saveLeaderboard", language: engine.state.language)) { engine.configureLeaderboard(url: leaderboardURL, optIn: leaderboard) }
                }
                if let identity = engine.deviceIdentity { Text((BuddyCopy.phase7("friendsCodeLabel", language: engine.state.language)) + identity.friendsCode).textSelection(.enabled) }
                HStack {
                    TextField(BuddyCopy.phase7("friendCode", language: engine.state.language), text: $friendCode)
                    Button(BuddyCopy.phase7("addFriend", language: engine.state.language)) { engine.addFriend(friendCode); friendCode = "" }
                }
                Text(engine.friendsCodes.joined(separator: " · "))
            }
        case .profile:
            Button(BuddyCopy.phase7("profile", language: engine.state.language)) { CompanionWindows.shared.profile(engine: engine) }
        case .retire:
            Button(BuddyCopy.phase7("retire", language: engine.state.language), role: .destructive) { confirming = true }.foregroundStyle(.red).disabled(retiring)
        default: EmptyView()
        }
    }
}
