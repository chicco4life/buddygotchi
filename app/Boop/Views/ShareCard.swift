import LeaderboardWire
import AppKit
import SwiftUI

struct ShareCard: View {
    var creature: Creature
    var cosmetic: EquippedCosmetic
    var name: String
    var level: Int
    var streak: Int
    var line: String
    var language = "en"
    private var cardCreature: Creature {
        var c = creature; c.dots = 0; c.dotAlert = nil; c.focus = false; return c
    }
    var body: some View {
        HStack(spacing: 64) {
            CreatureView(creature: cardCreature, cosmetic: cosmetic, frozen: true, cream: true, frozenTime: 2.5)
                .frame(width: 440, height: 420)
            VStack(alignment: .leading, spacing: 28) {
                Text(name).font(.buddy(64, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.5)
                Text(String(format: BuddyCopy.phase7("shareGrowth", language: language), level, streak))
                    .font(.buddy(28))
                Text(line).font(.buddy(30)).lineLimit(3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(60).frame(width: 1200, height: 630)
        .foregroundStyle(Color(hex: "453D33")).background(Color(hex: "F6EEDC"))
    }
    @MainActor func cgImage() throws -> CGImage {
        let renderer = ImageRenderer(content: self); renderer.scale = 1
        guard let image = renderer.cgImage else { throw LeaderboardError.unavailable("share render failed") }
        return image
    }
    nonisolated static func pngData(_ image: CGImage) throws -> Data {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw LeaderboardError.unavailable("png encode failed") }
        return png
    }
    @MainActor func pngData() throws -> Data { try Self.pngData(cgImage()) }
}
@MainActor
extension BuddyEngine {
    func shareCard() -> ShareCard {
        let register = shareRegister
        let line = VoiceBanks.lines(language: state.language, occasion: "share", register: register).randomElement() ?? ""
        return ShareCard(creature: state.creature, cosmetic: state.cosmetic, name: displayName,
                         level: state.growth.level, streak: state.growth.streak, line: line, language: state.language)
    }
}

struct LeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let engine: BuddyEngine
    @State private var view = RankView.all
    @State private var error = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(BuddyCopy.phase7("leaderboard", language: engine.state.language), selection: $view) {
                Text(BuddyCopy.phase7("rankAll", language: engine.state.language)).tag(RankView.all)
                Text(BuddyCopy.phase7("rankMonth", language: engine.state.language)).tag(RankView.month)
                Text(BuddyCopy.phase7("rankFriends", language: engine.state.language)).tag(RankView.friends)
            }.pickerStyle(.segmented)
            if error {
                Text(BuddyCopy.phase7("rankUnavailable", language: engine.state.language))
            }
            if let snapshot = engine.state.leaderboard, snapshot.view == view {
                if let rank = snapshot.rank { Text(String(format: BuddyCopy.phase7("yourRank", language: engine.state.language), rank)) }
                List(snapshot.entries) { entry in
                    HStack { Text(String(entry.rank)); Text(entry.buddyName); Spacer(); Text(String(entry.xpTotal)) }
                }
            }
            HStack {
                Spacer()
                Button(BuddyCopy.phase7("shareDone", language: engine.state.language)) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 440, height: 420)
        .task(id: view) {
            do { _ = try await engine.refreshRank(view: view); error = false }
            catch { self.error = true }
        }
    }
}
