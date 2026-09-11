import Foundation
import XCTest
@testable import BoopCore

/// The "Boop Cream" palette is hand-authored for both appearances rather than
/// inherited from the system, which means the system's contrast guarantees no
/// longer apply. `plan/UX-APP.md` promises that every `*Ink` tone clears 4.5:1
/// against its own appearance's paper; this is that promise, checked.
///
/// These read `BuddyPalette`'s hex strings rather than the `BuddyTheme` colors,
/// because the tokens resolve through `NSAppearance` and a headless test has no
/// appearance to resolve against.
final class PaletteTests: XCTestCase {

    // MARK: WCAG relative luminance

    private func channel(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ hex: String) -> Double {
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = channel(Double((int >> 16) & 0xFF) / 255)
        let g = channel(Double((int >> 8) & 0xFF) / 255)
        let b = channel(Double(int & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: Text tones

    func testInkTonesClearBodyTextContrast() {
        let light: [(String, String)] = [
            ("ink", BuddyPalette.inkLight),
            ("inkSoft", BuddyPalette.inkSoftLight),
            ("terracottaInk", BuddyPalette.terracottaInkLight),
            ("amberInk", BuddyPalette.amberInkLight),
            ("greenInk", BuddyPalette.greenInkLight),
            ("clayInk", BuddyPalette.clayInkLight),
            ("pinkInk", BuddyPalette.pinkInkLight),
        ]
        for (name, hex) in light {
            let ratio = contrast(hex, BuddyPalette.paperLight)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "light \(name) is \(String(format: "%.2f", ratio)):1 on paper; body text needs 4.5:1")
        }

        let dark: [(String, String)] = [
            ("ink", BuddyPalette.inkDark),
            ("inkSoft", BuddyPalette.inkSoftDark),
            ("terracottaInk", BuddyPalette.terracottaInkDark),
            ("amberInk", BuddyPalette.amberInkDark),
            ("greenInk", BuddyPalette.greenInkDark),
            ("clayInk", BuddyPalette.clayInkDark),
            ("pinkInk", BuddyPalette.pinkInkDark),
        ]
        for (name, hex) in dark {
            let ratio = contrast(hex, BuddyPalette.paperDark)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "dark \(name) is \(String(format: "%.2f", ratio)):1 on paper; body text needs 4.5:1")
        }
    }

    /// The faint tones are deliberately below 4.5:1 — they are decoration and
    /// disabled affordances. This pins that they stay *visible*, so a future
    /// tweak cannot quietly turn an empty activity cell into invisible paper.
    func testFaintTonesRemainVisibleWithoutPosingAsBodyText() {
        for (name, hex, paper) in [("light", BuddyPalette.inkFaintLight, BuddyPalette.paperLight),
                                   ("dark", BuddyPalette.inkFaintDark, BuddyPalette.paperDark)] {
            let ratio = contrast(hex, paper)
            XCTAssertGreaterThan(ratio, 1.8, "\(name) inkFaint vanishes into paper at \(ratio):1")
            XCTAssertLessThan(ratio, 4.5, "\(name) inkFaint now reads as body text; use inkSoft instead")
        }
    }

    /// Surfaces must be distinguishable from each other, or the card stack
    /// flattens into one sheet and the whole structure disappears.
    func testSurfacesSeparate() {
        for (name, paper, raised, well) in [
            ("light", BuddyPalette.paperLight, BuddyPalette.raisedLight, BuddyPalette.wellLight),
            ("dark", BuddyPalette.paperDark, BuddyPalette.raisedDark, BuddyPalette.wellDark),
        ] {
            XCTAssertNotEqual(paper, raised, "\(name): raised must lift off paper")
            XCTAssertNotEqual(raised, well, "\(name): well must sit under raised")
            XCTAssertGreaterThan(abs(luminance(paper) - luminance(well)), 0.004,
                                 "\(name): paper and well are too close to tell apart")
        }
    }

    /// The one rule that makes the palette learnable across both screens, and
    /// the one most likely to erode: amber means "an agent needs you". It must
    /// never be reused as a primary action tint.
    func testAmberIsNotUsedForPrimaryActions() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Boop/Views")
        let files = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "no view sources found at \(views.path)")
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("borderedProminent") && line.contains("BuddyTheme.amber") {
                XCTFail("\(file.lastPathComponent):\(index + 1) tints a primary action amber; "
                        + "amber is reserved for \"needs you\" — use BuddyTheme.accent")
            }
        }
    }
}
