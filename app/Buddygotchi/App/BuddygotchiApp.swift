import SwiftUI

@main
enum BuddygotchiMain {
    static func main() {
        // Headless snapshot mode: render every UI surface to PNGs and exit.
        // Usage: Buddygotchi --render-snapshots [output-dir]
        let args = CommandLine.arguments
        if let flagIndex = args.firstIndex(of: "--render-snapshots") {
            let dir = args.indices.contains(flagIndex + 1) ? args[flagIndex + 1] : "/tmp/buddy-snapshots"
            MainActor.assumeIsolated {
                SnapshotRenderer.renderAll(to: dir)
            }
            exit(0)
        }
        BuddygotchiApp.main()
    }
}

struct BuddygotchiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
