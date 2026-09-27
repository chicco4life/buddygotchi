import AppKit
import BoopKit
import SwiftUI

/// The popover (UX.md §6). One 360 pt column on warm paper; Overview,
/// Settings and Setup all open inside it.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void = {}
    /// The tallest the column grows before it scrolls. The snapshot harness
    /// raises it to capture whole panes.
    var maxHeight: CGFloat? = nil

    private var limit: CGFloat {
        maxHeight ?? min(720, (NSScreen.main?.visibleFrame.height ?? 900) - 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.pane {
                case .overview: OverviewPane(model: model, maxHeight: limit - 44)
                case .settings: SettingsPane(model: model, maxHeight: (maxHeight ?? min(limit, 640)) - 96)
                case .setup: SetupPane(model: model)
                }
            }
            .transition(.opacity)
            footer
        }
        .frame(width: Theme.width)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .animation(.boopSettle, value: model.pane)
        .onExitCommand(perform: onClose)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                if model.pane == .overview {
                    Button {
                        model.pane = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                } else if model.pane == .settings {
                    // The versions, where Settings would be.
                    Text("Boop \(BoopVersion.current)" + (model.status?.device.map { " · firmware \($0.fw)" } ?? ""))
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .padding(.leading, 8)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .font(.system(size: 12))
            .buttonStyle(.quiet)
            .padding(.horizontal, Theme.gutter - 8)
            .padding(.vertical, Theme.gapSnug)
        }
    }
}

/// A scroll view as tall as its content, up to `maxHeight`, so a short pane
/// makes a short popover and a long one scrolls. A hidden, disabled copy of
/// the content sets the height in the same layout pass, so the popover opens
/// at its final size instead of growing into it.
struct FittedScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .disabled(true)
            .accessibilityHidden(true)
            .frame(maxHeight: maxHeight, alignment: .top)
            .overlay(alignment: .top) {
                ScrollView { content }
                    .scrollBounceBehavior(.basedOnSize)
            }
    }
}

/// A pane's title row: an optional Back chevron and the title.
struct PaneHeader: View {
    let title: String
    var back: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.gapTight) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.quiet)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back")
            }
            Text(title).font(.boop(16))
            Spacer()
        }
        .padding(.horizontal, back == nil ? Theme.gutter : Theme.gutter - 8)
        .padding(.top, Theme.gutter - 4)
        .padding(.bottom, Theme.gap)
    }
}
