import SwiftUI

struct CompanionSettings: View {
    let engine: BuddyEngine
    let device: ESP32Output
    var onRetired: () -> Void = {}
    var section: String? = nil
    @AppStorage(DefaultsKey.language) private var language = "en"
    @AppStorage(DefaultsKey.voiceRuntime) private var voice = "auto"
    @AppStorage(DefaultsKey.leaderboardOptIn) private var leaderboard = false
    @AppStorage(DefaultsKey.soundVolume) private var volume = 1
    @AppStorage(DefaultsKey.focusHoursEnabled) private var focus = false
    @AppStorage(DefaultsKey.focusStart) private var start = 9
    @AppStorage(DefaultsKey.focusEnd) private var end = 17
    @State private var quick = ""
    @State private var confirming = false
    @State private var error = false
    @State private var retiring = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if section == nil || section == "sounds" {
            Picker(BuddyCopy.phase7("volume"), selection: $volume) { ForEach(0...3, id: \.self) { Text(String($0)).tag($0) } }
            }
            if section == nil || section == "focus" {
            Toggle(BuddyCopy.phase7("focusHours"), isOn: $focus)
            HStack {
                Picker(BuddyCopy.phase7("start"), selection: $start) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker(BuddyCopy.phase7("end"), selection: $end) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            }.disabled(!focus)
            }
            if section == nil || section == "language" {
            Picker(BuddyCopy.phase7("language"), selection: $language) {
                Text(BuddyCopy.phase7("english")).tag("en")
                Text(BuddyCopy.phase7("korean")).tag("ko")
            }.onChange(of: language) { _, value in Task { await engine.setLanguage(value) } }
            }
            if section == nil || section == "voice" {
            Picker(BuddyCopy.phase7("voice"), selection: $voice) {
                Text(BuddyCopy.phase7("auto")).tag("auto")
                Text(BuddyCopy.phase7("off")).tag("off")
            }.onChange(of: voice) { _, value in Task { await engine.setVoiceRuntime(value) } }
            }
            if section == nil || section == "quick" {
            TextField(BuddyCopy.phase7("quick"), text: $quick).textFieldStyle(.roundedBorder)
                .onChange(of: quick) { _, text in engine.setQuickCommand(text) }
            Text(BuddyCopy.phase7("quickNote")).font(.buddy(11)).foregroundStyle(BuddyTheme.inkSoft)
            }
            if section == nil || section == "leaderboard" {
            Toggle(BuddyCopy.phase7("leaderboard"), isOn: $leaderboard)
            }
            if section == nil || section == "profile" {
            Button(BuddyCopy.phase7("profile")) { CompanionWindows.shared.profile(engine: engine) }
            }
            if section == nil || section == "retire" {
            Button(BuddyCopy.phase7("retire"), role: .destructive) { confirming = true }.disabled(retiring)
            }

        }.font(.buddy(12)).padding(.vertical, 16)
        .onAppear { quick = engine.quickCommand }
        .onChange(of: focus) { _, _ in engine.updateFocusHours() }
        .onChange(of: start) { _, _ in engine.updateFocusHours() }
        .onChange(of: end) { _, _ in engine.updateFocusHours() }
        .sheet(isPresented: $confirming) {
            VStack(spacing: 20) {
                Text(BuddyCopy.phase7("retireMessage"))
                HStack {
                    Button(BuddyCopy.phase7("cancel")) { confirming = false }
                    Button(BuddyCopy.phase7("retire"), role: .destructive) {
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
        .alert(BuddyCopy.phase7("error"), isPresented: $error) { Button(BuddyCopy.phase7("continue")) {} }
    }
}
