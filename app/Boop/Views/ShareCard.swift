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
                Text(language == "ko" ? "레벨 \(level) · \(streak)일 연속" : "Level \(level) · \(streak) day streak")
                    .font(.buddy(28))
                Text(line).font(.buddy(30)).lineLimit(3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(60).frame(width: 1200, height: 630)
        .foregroundStyle(Color(hex: "453D33")).background(Color(hex: "F6EEDC"))
    }
    @MainActor func pngData() throws -> Data {
        let renderer = ImageRenderer(content: self); renderer.scale = 1
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw LeaderboardError.unavailable("png encode failed") }
        return png
    }
}
@MainActor
extension BuddyEngine {
    func shareCard() -> ShareCard {
        let register = shareRegister
        let line = VoiceBanks.lines(language: state.language, occasion: "share", register: register).randomElement() ?? ""
        return ShareCard(creature: state.creature, cosmetic: state.cosmetic, name: buddyName,
                         level: state.growth.level, streak: state.growth.streak, line: line, language: state.language)
    }
    @discardableResult func saveShareCard() throws -> URL {
        let png = try shareCard().pngData()
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Boop-share-\(UUID().uuidString).png")
        try png.write(to: url, options: .atomic)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        return url
    }
    func presentShareCard() {
        do { let url = try saveShareCard(); NSWorkspace.shared.activateFileViewerSelecting([url]) }
        catch { NSAlert(error: error).runModal() }
    }
}

struct LeaderboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let engine: BuddyEngine
    @State private var view = RankView.all
    @State private var error = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(engine.state.language == "ko" ? "리더보드" : "Leaderboard", selection: $view) {
                Text(engine.state.language == "ko" ? "전체" : "All time").tag(RankView.all)
                Text(engine.state.language == "ko" ? "이번 달" : "This month").tag(RankView.month)
                Text(engine.state.language == "ko" ? "친구" : "Friends").tag(RankView.friends)
            }.pickerStyle(.segmented)
            if error {
                Text(engine.state.language == "ko" ? "기기를 연결하고 설정에서 리더보드를 켜 주세요." : "Connect your device and enable the leaderboard in settings.")
            }
            if let snapshot = engine.state.leaderboard, snapshot.view == view {
                if let rank = snapshot.rank { Text(engine.state.language == "ko" ? "내 순위: \(rank)" : "Your rank: \(rank)") }
                List(snapshot.entries) { entry in
                    HStack { Text(String(entry.rank)); Text(entry.buddyName); Spacer(); Text(String(entry.xpTotal)) }
                }
            }
            HStack {
                Spacer()
                Button(engine.state.language == "ko" ? "닫기" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 440, height: 420)
        .task(id: view) {
            do { _ = try await engine.syncLeaderboard(view: view); error = false }
            catch { self.error = true }
        }
    }
}
