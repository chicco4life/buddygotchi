import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(engine: BuddyEngine, esp32Output: ESP32Output, onFinish: @escaping () -> Void) {
        let root = OnboardingView(engine: engine, esp32Output: esp32Output, onFinish: onFinish)
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: BuddyTheme.onboardingWidth, height: BuddyTheme.onboardingHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.title = BuddyCopy.shared.common.appName
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.backgroundColor = NSColor(calibratedRed: 0.106, green: 0.09, blue: 0.078, alpha: 1)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
