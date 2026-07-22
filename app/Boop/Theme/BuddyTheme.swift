import SwiftUI

enum BuddyTheme {
    static let night = Color(hex: "#1B1714")
    static let nightRaised = Color(hex: "#27211B")
    static let nightRaised2 = Color(hex: "#312A22")

    static let textPrimary = Color(hex: "#EFE7D8")
    static let textSecondary = Color(hex: "#B9AE9C")
    static let textTertiary = Color(hex: "#877D6D")

    static let amber = Color(hex: "#E8A33D")
    static let amberDeep = Color(hex: "#C9862B")
    static let green = Color(hex: "#7FA96B")
    static let stuckRed = Color(hex: "#C96B5E")
    static let workGlow = Color(hex: "#EFE7D8")
    static let boopPink = Color(hex: "#D98BA4")

    static let divider = textPrimary.opacity(0.08)

    static let cardCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 999

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

struct BuddyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(13, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                (configuration.isPressed ? BuddyTheme.amberDeep : BuddyTheme.amber),
                in: Capsule()
            )
            .foregroundStyle(BuddyTheme.night)
            .animation(.buddyEase(0.15), value: configuration.isPressed)
    }
}

struct BuddySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(13, weight: .semibold))
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

// MARK: - Species Color Helper

func buddySpeciesColor(for species: String) -> Color {
    if species == Pet.defaultSpecies { return BuddyTheme.textPrimary }
    let buddy = allBuddies[species] ?? allBuddies[Pet.defaultSpecies] ?? allBuddies.values.first!
    return Color(hex: buddy.color)
}
