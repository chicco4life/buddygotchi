import AppKit
import SwiftUI

/// The app's palette, "Boop Cream" (UX.md §7): warm paper and ink in both
/// appearances, one terracotta accent, and the device's meanings for amber
/// (needs you), sage (done) and clay (trouble). It's hand-set rather than
/// the system's greys, because the popover belongs to a toy on your desk.
/// Every `*Ink` tone clears 4.5:1 on its own paper; `inkFaint` doesn't and is
/// for decoration and disabled things only.
enum Palette {
    static let paperLight = "#FAF7F2", paperDark = "#1B1815"
    static let raisedLight = "#F3EDE3", raisedDark = "#24211C"
    static let wellLight = "#EBE3D6", wellDark = "#2C2822"
    static let hairlineLight = "#E4DACA", hairlineDark = "#38332B"
    static let hairlineStrongLight = "#D6C8B2", hairlineStrongDark = "#4A4339"
    static let inkLight = "#24211C", inkDark = "#F2EBE0"
    static let inkSoftLight = "#6E665A", inkSoftDark = "#ADA396"
    static let inkFaintLight = "#A29888", inkFaintDark = "#787064"

    static let terracotta = "#D97757", terracottaPressed = "#C05F3F"
    static let terracottaInkLight = "#A8482B", terracottaInkDark = "#F0A98C"
    static let amber = "#E8A33D", amberInkLight = "#8A5A16", amberInkDark = "#E8B970"
    static let sage = "#6E9B5E", sageInkLight = "#4A6B3C", sageInkDark = "#A3CC90"
    static let clay = "#C4574A", clayInkLight = "#9C3B2E", clayInkDark = "#F09384"
    static let rose = "#D4839B", roseInkLight = "#A35270", roseInkDark = "#EFB3C5"

    /// The device's own colours (firmware `palette.h`): black glass, oat eyes
    /// and its brighter amber, for the little face.
    static let glass = "#000000", oat = "#E8DCC4", deviceAmber = "#FFB000"
}

enum Theme {
    private static func adaptive(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    static let paper = adaptive(Palette.paperLight, Palette.paperDark)
    static let raised = adaptive(Palette.raisedLight, Palette.raisedDark)
    static let well = adaptive(Palette.wellLight, Palette.wellDark)
    static let hairline = adaptive(Palette.hairlineLight, Palette.hairlineDark)
    static let hairlineStrong = adaptive(Palette.hairlineStrongLight, Palette.hairlineStrongDark)

    static let ink = adaptive(Palette.inkLight, Palette.inkDark)
    static let inkSoft = adaptive(Palette.inkSoftLight, Palette.inkSoftDark)
    static let inkFaint = adaptive(Palette.inkFaintLight, Palette.inkFaintDark)

    static let accent = Color(hex: Palette.terracotta)
    static let accentPressed = Color(hex: Palette.terracottaPressed)
    static let accentInk = adaptive(Palette.terracottaInkLight, Palette.terracottaInkDark)
    static let amber = Color(hex: Palette.amber)
    static let amberInk = adaptive(Palette.amberInkLight, Palette.amberInkDark)
    static let sage = Color(hex: Palette.sage)
    static let sageInk = adaptive(Palette.sageInkLight, Palette.sageInkDark)
    static let clay = Color(hex: Palette.clay)
    static let clayInk = adaptive(Palette.clayInkLight, Palette.clayInkDark)
    static let rose = Color(hex: Palette.rose)
    static let roseInk = adaptive(Palette.roseInkLight, Palette.roseInkDark)

    static let glass = Color(hex: Palette.glass)
    static let oat = Color(hex: Palette.oat)

    // One spacing scale, so margins can't drift a point or two per view.
    static let gutter: CGFloat = 18
    static let gapTight: CGFloat = 4
    static let gapSnug: CGFloat = 8
    static let gap: CGFloat = 12
    static let gapLoose: CGFloat = 18
    static let gapSection: CGFloat = 20

    static let cardRadius: CGFloat = 12
    static let wellRadius: CGFloat = 8
    static let chipRadius: CGFloat = 6

    static let width: CGFloat = 360
}

extension Font {
    /// Rounded for names, titles and numbers: the friendly voice. Body text
    /// stays the system face.
    static func boop(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Motion

extension Animation {
    static func boopEase(_ duration: Double = 0.3) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    /// Tone crossfades and number changes: a soft settle, no bounce.
    static var boopSettle: Animation { boopEase(0.28) }

    /// Something arriving: one gentle overshoot, like the device's cards.
    static var boopPop: Animation { .spring(response: 0.34, dampingFraction: 0.68) }
}

// A plain key: the `@Entry` macro's plugin isn't in Command Line Tools.
private struct StillMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Holds every looping animation still, for snapshots.
    var stillMotion: Bool {
        get { self[StillMotionKey.self] }
        set { self[StillMotionKey.self] = newValue }
    }
}

// MARK: - Building blocks

/// A raised card on the paper: one hairline, one radius, one padding, so the
/// column reads as a stack of the same object.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var tone: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.map { $0.opacity(0.08) } ?? Theme.raised,
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(tone?.opacity(0.45) ?? Theme.hairline, lineWidth: 1))
    }
}

/// A small, tracked-out label over a card. Space and this label separate
/// sections, not rules.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.inkFaint)
            .padding(.leading, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A labelled section: the label, then its content.
struct PaneSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            SectionLabel(text: label)
            content
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

/// A status dot. It breathes only while something is live, so motion here
/// always means "happening now".
struct StateDot: View {
    var tone: Color
    var pulsing = false
    var size: CGFloat = 7
    @ViewState private var up = false
    @Environment(\.stillMotion) private var still

    var body: some View {
        Circle()
            .fill(tone)
            .frame(width: size, height: size)
            .overlay(Circle().fill(tone).scaleEffect(up ? 2.2 : 1).opacity(up ? 0 : 0.35))
            .animation(pulsing ? .easeOut(duration: 1.6).repeatForever(autoreverses: false) : .default, value: up)
            .onAppear { up = pulsing && !still }
            .onChange(of: pulsing) { _, live in up = live && !still }
            .accessibilityHidden(true)
    }
}

/// The status word in its tone, on a wash of the same hue.
struct StatusChip: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.chipRadius))
    }
}

/// Footer and inline buttons: quiet text that warms on hover.
struct QuietButtonStyle: ButtonStyle {
    var tone: Color? = nil
    @ViewState private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.accentPressed
                             : hovering ? (tone ?? Theme.accentInk) : (tone ?? Theme.inkSoft))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: Theme.chipRadius).fill(hovering ? Theme.well : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
    }
}

/// The one filled button per screen: terracotta, rounded, a little squash
/// when pressed.
struct ProminentButtonStyle: ButtonStyle {
    var wide = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(configuration.isPressed ? Theme.accentPressed : Theme.accent,
                        in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.boopSettle, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A small outlined button for rows: Connect, Repair, Save.
struct RowButtonStyle: ButtonStyle {
    var filled = false
    @ViewState private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? .white : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(
                filled ? (configuration.isPressed ? Theme.accentPressed : Theme.accent)
                    : (hovering || configuration.isPressed ? Theme.well : Theme.paper)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(filled ? .clear : Theme.hairlineStrong, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering = $0 }
            .animation(.boopSettle, value: hovering)
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
    static var rowFilled: RowButtonStyle { RowButtonStyle(filled: true) }
}

// MARK: - Hex colours

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(digits, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
