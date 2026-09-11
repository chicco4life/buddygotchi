import AppKit
import SwiftUI

/// Raw hex strings for the palette, with no framework dependency, so that both
/// SwiftUI (`Color`) and AppKit (`NSColor`) read one set of constants. Prefer the
/// `BuddyTheme` tokens; reach for these only where a `Color` will not do.
///
/// The palette is "Boop Cream": warm paper, warm ink, one terracotta accent and
/// three semantic tones. It is hand-authored for both appearances rather than
/// inherited from the system, because the app is a companion surface for a
/// physical toy and a default grey panel reads as a utility. Every `*Ink` tone
/// clears 4.5:1 against its own appearance's `paper`; the `*Faint` tones do not
/// and are for decoration and disabled affordances only.
///
/// The device shares the accent trio (amber = needs you, sage = done, rose =
/// affection) so a colour means the same thing on both screens. It inverts the
/// field: see `firmware/esp32/firmware/palette.h`.
enum BuddyPalette {
    static let night = "#000000"

    // MARK: Light — warm paper

    static let paperLight = "#FAF7F2"
    static let raisedLight = "#F3EDE3"
    static let wellLight = "#EBE3D6"
    static let hairlineLight = "#E4DACA"
    static let hairlineStrongLight = "#D6C8B2"
    static let inkLight = "#24211C"
    static let inkSoftLight = "#6E665A"
    static let inkFaintLight = "#A29888"

    // MARK: Dark — warm charcoal

    static let paperDark = "#1B1815"
    static let raisedDark = "#24211C"
    static let wellDark = "#2C2822"
    static let hairlineDark = "#38332B"
    static let hairlineStrongDark = "#4A4339"
    static let inkDark = "#F2EBE0"
    static let inkSoftDark = "#ADA396"
    static let inkFaintDark = "#787064"

    // MARK: Accent — terracotta, the one primary

    static let terracotta = "#D97757"
    static let terracottaPressed = "#C05F3F"
    static let terracottaInkLight = "#A8482B"
    static let terracottaInkDark = "#F0A98C"

    // MARK: Semantic trio, shared with the device

    // Amber — needs you.
    static let amber = "#E8A33D"
    static let amberPressed = "#C9862B"
    static let amberInkLight = "#8A5A16"
    static let amberInkDark = "#E8B970"

    // Sage — done.
    static let green = "#6E9B5E"
    static let greenInkLight = "#4A6B3C"
    static let greenInkDark = "#A3CC90"

    // Clay — error.
    static let clay = "#C4574A"
    static let clayInkLight = "#9C3B2E"
    static let clayInkDark = "#F09384"

    // Rose — affection.
    static let pink = "#D4839B"
    static let pinkInkLight = "#A35270"
    static let pinkInkDark = "#EFB3C5"
}

enum BuddyTheme {
    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(buddyHex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    // MARK: - Surfaces

    /// The base sheet the whole popover sits on.
    static let paper = adaptive(BuddyPalette.paperLight, BuddyPalette.paperDark)
    /// Cards and rows that lift off the paper.
    static let raised = adaptive(BuddyPalette.raisedLight, BuddyPalette.raisedDark)
    /// Inset wells: grid cells, empty states, the inside of a chip.
    static let well = adaptive(BuddyPalette.wellLight, BuddyPalette.wellDark)

    // Retained names, now backed by the palette rather than by system greys.
    static let windowBackground = paper
    static let groupedBackground = raised
    static let night = Color(hex: BuddyPalette.night)

    // MARK: - Ink

    static let ink = adaptive(BuddyPalette.inkLight, BuddyPalette.inkDark)
    static let inkSoft = adaptive(BuddyPalette.inkSoftLight, BuddyPalette.inkSoftDark)
    /// Decoration and disabled affordances only — this does not clear 4.5:1.
    static let inkFaint = adaptive(BuddyPalette.inkFaintLight, BuddyPalette.inkFaintDark)

    // MARK: - Accent

    static let accent = Color(hex: BuddyPalette.terracotta)
    static let accentPressed = Color(hex: BuddyPalette.terracottaPressed)
    static let accentInk = adaptive(BuddyPalette.terracottaInkLight, BuddyPalette.terracottaInkDark)

    static let amber = Color(hex: BuddyPalette.amber)
    static let amberPressed = Color(hex: BuddyPalette.amberPressed)
    static let amberInk = adaptive(BuddyPalette.amberInkLight, BuddyPalette.amberInkDark)

    static let green = Color(hex: BuddyPalette.green)
    static let greenInk = adaptive(BuddyPalette.greenInkLight, BuddyPalette.greenInkDark)
    static let clay = Color(hex: BuddyPalette.clay)
    static let clayInk = adaptive(BuddyPalette.clayInkLight, BuddyPalette.clayInkDark)
    static let pink = Color(hex: BuddyPalette.pink)
    static let pinkInk = adaptive(BuddyPalette.pinkInkLight, BuddyPalette.pinkInkDark)

    /// Working uses the secondary ink tone.
    static let work = inkSoft

    // MARK: - Lines

    static let hairline = adaptive(BuddyPalette.hairlineLight, BuddyPalette.hairlineDark)
    static let hairlineStrong = adaptive(BuddyPalette.hairlineStrongLight, BuddyPalette.hairlineStrongDark)
    static let hairlineWidth: CGFloat = 1
    static let divider = hairline

    // MARK: - Metrics

    /// One spacing scale, so gutters and gaps cannot drift apart by a point or
    /// two per view. `gutter` is the popover's left and right margin; every
    /// section aligns to it.
    static let gutter: CGFloat = 18
    static let gapTight: CGFloat = 4
    static let gapSnug: CGFloat = 8
    static let gap: CGFloat = 12
    static let gapLoose: CGFloat = 18
    static let gapSection: CGFloat = 22

    static let cardCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 14
    static let wellCornerRadius: CGFloat = 8
    static let chipCornerRadius: CGFloat = 6
    static let accentBarRadius: CGFloat = 2

    static let geistRegularPostScriptName = "Geist-Regular"
    static let geistSemiBoldPostScriptName = "Geist-SemiBold"
    static let geistMonoRegularPostScriptName = "GeistMono-Regular"

    static let popoverWidth: CGFloat = 360
    /// Resting minimum: header, one activity line, footer, and air. The popover
    /// auto-sizes past this (AppDelegate sets .preferredContentSize).
    static let liveViewHeight: CGFloat = 548
    /// Snapshot canvas for the approval states; not used for layout.
    static let liveViewExpandedHeight: CGFloat = 692
    static let popoverHeight: CGFloat = 548
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

// MARK: - Motion

extension Animation {
    static func buddyEase(_ duration: Double = 0.5) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    // The firmware calls these "bloom" and "snuff" — a surface arriving takes
    // longer than a surface resolving. Same durations, so the Mac and the device
    // answer a prompt at the same speed.
    static func buddyBloom() -> Animation { buddyEase(0.35) }
    static func buddySnuff() -> Animation { buddyEase(0.25) }

    /// A small, playful arrival with one gentle overshoot. The device's card
    /// spring is zeta 0.65 at ~4 Hz; this is the SwiftUI equivalent, so a chip
    /// or a card popping in on the Mac carries the same character as on the toy.
    static func buddyPop() -> Animation {
        .spring(response: 0.34, dampingFraction: 0.68)
    }

    /// State-tone crossfades and number changes: no bounce, just a soft settle.
    static func buddySettle() -> Animation { buddyEase(0.28) }
}

// MARK: - Building blocks

struct BuddyDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(BuddyTheme.hairline)
            .frame(height: BuddyTheme.hairlineWidth)
            .padding(.horizontal, inset)
    }
}

/// The small tone dot that opens a status line. It breathes only while the
/// state is live work — a resting dot is still, so motion on this surface
/// always means "something is happening right now".
struct BuddyStateDot: View {
    var tone: Color
    var pulsing = false
    @State private var up = false
    var body: some View {
        Circle()
            .fill(tone)
            .frame(width: 7, height: 7)
            .overlay(
                Circle().fill(tone).frame(width: 7, height: 7)
                    .scaleEffect(up ? 2.1 : 1)
                    .opacity(up ? 0 : 0.35)
            )
            .animation(pulsing ? .easeOut(duration: 1.6).repeatForever(autoreverses: false) : .default, value: up)
            .onAppear { if pulsing { up = true } }
            .onChange(of: pulsing) { _, live in up = live }
            .accessibilityHidden(true)
    }
}

/// A raised card on the paper. One hairline, one radius, one padding — used for
/// every grouped block so the column reads as a stack of the same object.
struct BuddyCard<Content: View>: View {
    var padding: CGFloat = 12
    var tone: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BuddyTheme.raised, in: RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .strokeBorder(tone?.opacity(0.35) ?? BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
            )
    }
}

/// A section label: small, tracked-out, and quiet. Sections are separated by
/// space and this label rather than by rules, so the column has fewer lines.
struct BuddySectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(BuddyTheme.inkFaint)
    }
}

/// Footer and inline buttons. Plain text that warms and underlines on hover, so
/// the chrome stays quiet until the pointer says otherwise.
struct BuddyTextButtonStyle: ButtonStyle {
    var tone: Color? = nil
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? BuddyTheme.accentPressed : (hovering ? (tone ?? BuddyTheme.accentInk) : BuddyTheme.inkSoft))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: BuddyTheme.chipCornerRadius)
                    .fill(hovering ? BuddyTheme.well : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: BuddyTheme.chipCornerRadius))
            .onHover { hovering = $0 }
            .animation(.buddySettle(), value: hovering)
            .animation(.buddySettle(), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BuddyTextButtonStyle {
    static var buddyText: BuddyTextButtonStyle { BuddyTextButtonStyle() }
    static func buddyText(tone: Color) -> BuddyTextButtonStyle { BuddyTextButtonStyle(tone: tone) }
}

struct BuddySettingToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(description).font(.footnote).foregroundStyle(BuddyTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
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
