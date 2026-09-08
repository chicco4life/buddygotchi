import AppKit
import SwiftUI

/// Raw hex strings for the palette, with no framework dependency, so that both
/// SwiftUI (`Color`) and AppKit (`NSColor`) read one set of constants. Prefer the
/// `BuddyTheme` tokens; reach for these only where a `Color` will not do.
enum BuddyPalette {
    // Surfaces. `paper` is the landing page's cream; `lantern` is the firmware's
    // FIELD_LANTERN, the warm field the device lights up with to ask a question.
    static let paper = "#F7F2E9"
    static let paperRaised = "#FDFAF4"
    static let paperSunken = "#EFE7D8"
    static let lantern = "#FFDBAD"
    static let lanternHot = "#FFB652"
    static let night = "#1B1714"

    // Ink. Warm, never pure black.
    static let ink = "#2B2724"
    static let inkSoft = "#6E675D"
    static let inkFaint = "#7A7369"

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

    static let paper = adaptive(BuddyPalette.paper, "211E1B")
    static let paperRaised = adaptive(BuddyPalette.paperRaised, "2C2824")
    static let paperSunken = adaptive(BuddyPalette.paperSunken, "191715")
    static let night = Color(hex: BuddyPalette.night)

    /// The approval field, and nothing else. Reserved so that the one moment the
    /// Mac lights up matches the one moment the device does.
    static let lantern = Color(hex: BuddyPalette.lantern)
    static let lanternHot = Color(hex: BuddyPalette.lanternHot)

    static let ink = adaptive(BuddyPalette.ink, "F7F2E9")
    static let inkSoft = adaptive(BuddyPalette.inkSoft, "C9C0B3")
    /// 4.1:1 on paper — captions and meta. Still short of AA for body copy, so
    /// never let it be the only thing carrying a meaning.
    static let inkFaint = adaptive(BuddyPalette.inkFaint, "B9B0A4")

    // The accent is split because #E8A33D is 1.93:1 on paper: fine as a fill,
    // illegible as text. Use `amber` for backgrounds and `amberInk` (5.2:1) for
    // anything a reader has to resolve — labels, icons, hairlines.
    static let amber = Color(hex: BuddyPalette.amber)
    static let amberPressed = Color(hex: BuddyPalette.amberPressed)
    static let amberInk = adaptive(BuddyPalette.amberInk, "E8B970")
    static let amberWash = Color(hex: BuddyPalette.amber).opacity(0.18)

    static let green = Color(hex: BuddyPalette.green)
    static let greenInk = adaptive(BuddyPalette.greenInk, "A4C992")
    static let clay = Color(hex: BuddyPalette.clay)
    static let clayInk = adaptive(BuddyPalette.clayInk, "E89E92")
    static let pink = Color(hex: BuddyPalette.pink)
    static let pinkInk = Color(hex: BuddyPalette.pinkInk)

    /// Working quietly reads as ink on paper, not as glow.
    static let work = inkSoft

    // The dark theme separated surfaces by raising their fill. Two percent of
    // luminance cannot do that, so on paper a card is a fill *and* a hairline.
    static let hairline = ink.opacity(0.10)
    static let hairlineStrong = ink.opacity(0.16)
    static let hairlineWidth: CGFloat = 1
    static let divider = hairline

    static let cardCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 14
    static let wellCornerRadius: CGFloat = 8
    static let accentBarRadius: CGFloat = 2

    static let geistRegularPostScriptName = "Geist-Regular"
    static let geistSemiBoldPostScriptName = "Geist-SemiBold"
    static let geistMonoRegularPostScriptName = "GeistMono-Regular"

    static let popoverWidth: CGFloat = 320
    /// Resting minimum: header, one activity line, footer, and air. The popover
    /// auto-sizes past this (AppDelegate sets .preferredContentSize).
    static let liveViewHeight: CGFloat = 360
    /// Snapshot canvas for the approval states; not used for layout.
    static let liveViewExpandedHeight: CGFloat = 600
    static let popoverHeight: CGFloat = 460
    /// The "finish setup" stub, which has no live content to size against.
    static let unfinishedSetupHeight: CGFloat = 220
    static let onboardingWidth: CGFloat = 760
    static let onboardingHeight: CGFloat = 660

    /// Text, icons, and status dots. Always legible on paper.
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

extension Font {
    static func buddy(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(
            weight == .semibold ? BuddyTheme.geistSemiBoldPostScriptName : BuddyTheme.geistRegularPostScriptName,
            size: size
        )
    }

    static func buddyMono(_ size: CGFloat) -> Font {
        .custom(BuddyTheme.geistMonoRegularPostScriptName, size: size)
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

// MARK: - Card Modifiers

struct BuddyCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .fill(elevated ? BuddyTheme.paperRaised : BuddyTheme.paperSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
            )
    }
}

extension View {
    func buddyCard(elevated: Bool = false) -> some View {
        modifier(BuddyCardModifier(elevated: elevated))
    }
}

// MARK: - Grouped Card (multiple items with internal dividers)

struct BuddyGroupedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .fill(BuddyTheme.paperRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
            )
    }
}

extension View {
    func buddyGroupedCard() -> some View {
        modifier(BuddyGroupedCardModifier())
    }

    /// A filled surface plus the hairline that separates it. Use for anything that
    /// used to lean on a raised fill alone — on paper that reads as nothing.
    /// `paperRaised` lifts (cards, rows); `paperSunken` recesses (fields, wells).
    func buddySurface(
        _ fill: Color = BuddyTheme.paperRaised,
        radius: CGFloat = BuddyTheme.panelCornerRadius
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
            )
    }
}

// MARK: - Button Styles

/// Controls sit at two scales: `.compact` inside the 320pt popover and settings
/// rows, `.large` in the roomier onboarding window.
enum BuddyControlSize {
    case compact
    case large

    /// Padding for filled buttons.
    var filledPadding: (h: CGFloat, v: CGFloat) {
        switch self {
        case .compact: (20, 8)
        case .large: (22, 10)
        }
    }

    /// Padding for plain-label buttons. Compact carries none — it sits inline in a
    /// row that already has padding of its own.
    var plainPadding: (h: CGFloat, v: CGFloat) {
        switch self {
        case .compact: (0, 0)
        case .large: (14, 8)
        }
    }
}

struct BuddyPrimaryButtonStyle: ButtonStyle {
    var size: BuddyControlSize = .compact

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(13, weight: .semibold))
            .padding(.horizontal, size.filledPadding.h)
            .padding(.vertical, size.filledPadding.v)
            .background(
                (configuration.isPressed ? BuddyTheme.amberPressed : BuddyTheme.amber),
                in: Capsule()
            )
            // Ink on amber is 6.9:1, and still 4.9:1 when pressed.
            .foregroundStyle(BuddyTheme.ink)
            .animation(.buddyEase(0.15), value: configuration.isPressed)
    }
}

struct BuddySecondaryButtonStyle: ButtonStyle {
    var size: BuddyControlSize = .compact

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(13, weight: .semibold))
            .padding(.horizontal, size.plainPadding.h)
            .padding(.vertical, size.plainPadding.v)
            .foregroundStyle(configuration.isPressed ? BuddyTheme.ink : BuddyTheme.inkSoft)
    }
}

/// Row-level secondary actions — Repair, Forget, Close. Replaces
/// `.buttonStyle(.bordered)`, whose fill comes from the system appearance and
/// reads as cool grey against warm paper.
struct BuddyChipButtonStyle: ButtonStyle {
    var tone: Color = BuddyTheme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(11, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                configuration.isPressed ? BuddyTheme.ink.opacity(0.08) : BuddyTheme.paperRaised,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(BuddyTheme.hairlineStrong, lineWidth: BuddyTheme.hairlineWidth))
            .animation(.buddyEase(0.15), value: configuration.isPressed)
    }
}

struct BuddyPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BuddyPlainButtonBody(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct BuddyPlainButtonBody<Label: View>: View {
    let isPressed: Bool
    @ViewBuilder let label: Label
    @State private var isHovering = false

    var body: some View {
        label
            .opacity(isPressed ? 0.5 : isHovering ? 0.8 : 1.0)
            .onHover { isHovering = $0 }
            .animation(.buddyEase(0.15), value: isHovering)
    }
}

// MARK: - Divider

/// The one rule in the app. A bare `Divider()` resolves from the system
/// appearance, which is a cool grey that reads wrong against a warm palette.
struct BuddyDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(BuddyTheme.divider)
            .frame(height: 1)
            .padding(.horizontal, inset)
    }
}

// MARK: - Section Header

struct BuddySectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.buddy(9.5, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            // inkSoft, not inkFaint — 9.5pt needs the contrast.
            .foregroundStyle(BuddyTheme.inkSoft)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}

// MARK: - Setting Toggle Row

struct BuddySettingToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.buddy(13))
                    .foregroundStyle(BuddyTheme.ink)
                Text(description)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(BuddySwitchToggleStyle())
                .tint(BuddyTheme.amber)
                .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .tint(BuddyTheme.amber)
    }
}

struct BuddySwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                // The off track was a light wash on a dark field; on paper it
                // inverts to an ink wash, and the knob needs a hairline or it
                // vanishes into the track.
                Capsule()
                    .fill(configuration.isOn ? BuddyTheme.amber : BuddyTheme.ink.opacity(0.14))
                    .frame(width: 52, height: 28)
                Circle()
                    .fill(BuddyTheme.paperRaised)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth))
                    .shadow(color: BuddyTheme.ink.opacity(0.18), radius: 3, y: 1)
                    .offset(x: configuration.isOn ? 12 : -12)
            }
            .frame(width: 52, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.buddyEase(0.15), value: configuration.isOn)
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

