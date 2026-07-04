import SwiftUI

public enum BoopEntrypoint {
    @MainActor
    public static func main() {
        // Headless snapshot mode: render every UI surface to PNGs and exit.
        // Usage: Boop --render-snapshots [output-dir]
        let args = CommandLine.arguments
        if let flagIndex = args.firstIndex(of: "--render-snapshots") {
            let dir = args.indices.contains(flagIndex + 1) ? args[flagIndex + 1] : "/tmp/buddy-snapshots"
            MainActor.assumeIsolated {
                SnapshotRenderer.renderAll(to: dir)
            }
            exit(0)
        }
        BoopApp.main()
    }
}

struct BoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
