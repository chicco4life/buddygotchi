import AppKit
import SwiftUI

private enum ShareCardError: Error { case unavailable(String) }

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
                Text(name).font(.custom("Geist-SemiBold", size: 64)).lineLimit(2).minimumScaleFactor(0.5)
                Text(String(format: BuddyCopy.phase7("shareGrowth", language: language), level, streak))
                    .font(.custom("Geist-Regular", size: 28))
                Text(line).font(.custom("Geist-Regular", size: 30)).lineLimit(3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(60).frame(width: 1200, height: 630)
        .foregroundStyle(Color(hex: "453D33")).background(Color(hex: "F6EEDC"))
    }
    @MainActor func cgImage() throws -> CGImage {
        let renderer = ImageRenderer(content: self); renderer.scale = 1
        guard let image = renderer.cgImage else { throw ShareCardError.unavailable("share render failed") }
        return image
    }
    nonisolated static func pngData(_ image: CGImage) throws -> Data {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ShareCardError.unavailable("png encode failed") }
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
