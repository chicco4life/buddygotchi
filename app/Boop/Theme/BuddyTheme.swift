import AppKit
import SwiftUI

/// Raw hex strings for the palette, with no framework dependency, so that both
/// SwiftUI (`Color`) and AppKit (`NSColor`) read one set of constants. Prefer the
/// `BuddyTheme` tokens; reach for these only where a `Color` will not do.
enum BuddyPalette {
    static let night = "#1B1714"
    static let nightRaised = "#27211B"
    static let nightRaised2 = "#312A22"

    static let textPrimary = "#EFE7D8"
    static let textSecondary = "#B9AE9C"
    static let textTertiary = "#877D6D"

    static let amber = "#E8A33D"
    static let amberDeep = "#C9862B"
    static let green = "#7FA96B"
    static let stuckRed = "#C96B5E"
    static let boopPink = "#D98BA4"
}

enum BuddyTheme {
    static let night = Color(hex: BuddyPalette.night)
    static let nightRaised = Color(hex: BuddyPalette.nightRaised)
    static let nightRaised2 = Color(hex: BuddyPalette.nightRaised2)

    static let textPrimary = Color(hex: BuddyPalette.textPrimary)
    static let textSecondary = Color(hex: BuddyPalette.textSecondary)
    static let textTertiary = Color(hex: BuddyPalette.textTertiary)

    static let amber = Color(hex: BuddyPalette.amber)
    static let amberDeep = Color(hex: BuddyPalette.amberDeep)
    static let green = Color(hex: BuddyPalette.green)
    static let stuckRed = Color(hex: BuddyPalette.stuckRed)
    static let workGlow = Color(hex: BuddyPalette.textPrimary)
    static let boopPink = Color(hex: BuddyPalette.boopPink)

    static let divider = textPrimary.opacity(0.08)

    static let cardCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 14
    static let wellCornerRadius: CGFloat = 8
    static let accentBarRadius: CGFloat = 2

    static let geistRegularPostScriptName = "Geist-Regular"
    static let geistSemiBoldPostScriptName = "Geist-SemiBold"
    static let geistMonoRegularPostScriptName = "GeistMono-Regular"

    static let popoverWidth: CGFloat = 320
    static let liveViewHeight: CGFloat = 240
    static let liveViewExpandedHeight: CGFloat = 380
    static let popoverHeight: CGFloat = 440
    static let onboardingWidth: CGFloat = 760
    static let onboardingHeight: CGFloat = 560

    static func stateColor(_ state: PetState) -> Color {
        switch state {
        case .sleep, .idle: textSecondary
        case .busy, .thinking: workGlow
        case .attention: amber
        case .celebrate: green
        case .error: stuckRed
        case .heart: boopPink
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
}

// MARK: - Card Modifiers

struct BuddyCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .fill(elevated ? BuddyTheme.nightRaised2 : BuddyTheme.nightRaised)
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
                    .fill(BuddyTheme.nightRaised)
            )
    }
}

extension View {
    func buddyGroupedCard() -> some View {
        modifier(BuddyGroupedCardModifier())
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
                (configuration.isPressed ? BuddyTheme.amberDeep : BuddyTheme.amber),
                in: Capsule()
            )
            .foregroundStyle(BuddyTheme.night)
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
            .foregroundStyle(configuration.isPressed ? BuddyTheme.textPrimary : BuddyTheme.textSecondary)
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
            .foregroundStyle(BuddyTheme.textTertiary)
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
                    .foregroundStyle(BuddyTheme.textPrimary)
                Text(description)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.textTertiary)
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
                Capsule()
                    .fill(configuration.isOn ? BuddyTheme.amber : BuddyTheme.textPrimary.opacity(0.16))
                    .frame(width: 52, height: 28)
                Circle()
                    .fill(BuddyTheme.textPrimary)
                    .frame(width: 22, height: 22)
                    .shadow(color: BuddyTheme.night.opacity(0.22), radius: 3, y: 1)
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

