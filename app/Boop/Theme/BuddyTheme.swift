import AppKit
import SwiftUI

/// Raw hex strings for the palette, with no framework dependency, so that both
/// SwiftUI (`Color`) and AppKit (`NSColor`) read one set of constants. Prefer the
/// `BuddyTheme` tokens; reach for these only where a `Color` will not do.
enum BuddyPalette {
    static let night = "#000000"

    // One accent, in a fill form and an ink form. See the note on BuddyTheme.amber.
    static let amber = "#E8A33D"
    static let amberPressed = "#C9862B"
    static let amberInk = "#8A5A16"

    static let green = "#7FA96B"
    static let greenInk = "#456B36"
    static let clay = "#C96B5E"
    static let clayInk = "#9C4436"
    static let pink = "#D98BA4"
    static let pinkInk = "#A35270"
}

enum BuddyTheme {
    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(buddyHex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let groupedBackground = Color(nsColor: .controlBackgroundColor)
    static let night = Color(hex: BuddyPalette.night)
    static let ink = Color(nsColor: .labelColor)
    static let inkSoft = Color(nsColor: .secondaryLabelColor)
    static let inkFaint = Color(nsColor: .secondaryLabelColor)

    static let amber = Color(hex: BuddyPalette.amber)
    static let amberPressed = Color(hex: BuddyPalette.amberPressed)
    static let amberInk = adaptive(BuddyPalette.amberInk, "E8B970")

    static let green = Color.green
    static let greenInk = Color.green
    static let clay = Color.red
    static let clayInk = Color.red
    static let pink = Color(hex: BuddyPalette.pink)
    static let pinkInk = Color(hex: BuddyPalette.pinkInk)

    /// Working uses the secondary label tone.
    static let work = inkSoft

    static let hairline = Color(nsColor: .separatorColor)
    static let hairlineStrong = Color(nsColor: .separatorColor)
    static let hairlineWidth: CGFloat = 1
    static let divider = hairline

    static let cardCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 14
    static let wellCornerRadius: CGFloat = 8
    static let accentBarRadius: CGFloat = 2

    static let geistRegularPostScriptName = "Geist-Regular"
    static let geistSemiBoldPostScriptName = "Geist-SemiBold"
    static let geistMonoRegularPostScriptName = "GeistMono-Regular"

    static let popoverWidth: CGFloat = 760
    /// Resting minimum: header, one activity line, footer, and air. The popover
    /// auto-sizes past this (AppDelegate sets .preferredContentSize).
    static let liveViewHeight: CGFloat = 620
    /// Snapshot canvas for the approval states; not used for layout.
    static let liveViewExpandedHeight: CGFloat = 620
    static let popoverHeight: CGFloat = 460
    /// The "finish setup" stub, which has no live content to size against.
    static let unfinishedSetupHeight: CGFloat = 220
    static let onboardingWidth: CGFloat = 760
    static let onboardingHeight: CGFloat = 660

    /// Semantic state tones for text, icons, and status dots.
    static func stateInk(_ state: PetState) -> Color {
        switch state {
        case .sleep, .idle: inkFaint
        case .busy, .thinking: work
        case .attention: amberInk
        case .celebrate: greenInk
        case .error: clayInk
        case .heart: pinkInk
        }
    }

    /// Chips, bars, and washes behind `stateInk`. Never used as a foreground.
    static func stateFill(_ state: PetState) -> Color {
        switch state {
        case .sleep, .idle: inkFaint
        case .busy, .thinking: inkSoft
        case .attention: amber
        case .celebrate: green
        case .error: clay
        case .heart: pink
        }
    }
}

extension Animation {
    static func buddyEase(_ duration: Double = 0.5) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    // The firmware calls these "bloom" and "snuff" — a surface arriving takes
    // longer than a surface resolving. Same durations, so the Mac and the device
    // answer a prompt at the same speed.
    static func buddyBloom() -> Animation { buddyEase(0.35) }
    static func buddySnuff() -> Animation { buddyEase(0.25) }
}

struct BuddyDivider: View {
    var inset: CGFloat = 0
    var body: some View { Divider().padding(.horizontal, inset) }
}

struct BuddySettingToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(description).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Color Hex Init

// Both initializers read `BuddyPalette`; keep them side by side so they cannot drift.

extension Color {
    init(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(buddyHex: String) {
        var hex = buddyHex
        if hex.hasPrefix("#") { hex.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = CGFloat((int >> 16) & 0xFF) / 255
        let green = CGFloat((int >> 8) & 0xFF) / 255
        let blue = CGFloat(int & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

