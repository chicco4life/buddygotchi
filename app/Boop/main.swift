import AppKit
import BoopKit
import Foundation

// The Boop app. With no arguments it's the menu-bar app on Bluetooth.
// `--headless` runs the same runtime with no UI and no Bluetooth, for tests
// and agents (VERIFICATION.md L4).

let usage = """
    usage: Boop [--state-dir DIR] [--link ble|usb:SOCKET|none] [--debug-log FILE]
               The menu-bar app. The owner runs this; it uses Bluetooth by default. --debug-log appends
               every brain pass and aside to FILE as JSON lines, what you said included (boopdev watch).
           Boop --headless --state-dir DIR [--link usb:SOCKET|none] [--socket PATH] [--mode chatty|normal|calm]
                [--classifier chatty|calm|jev] [--writer apple|none|deepseek] [--name NAME] [--nature sweet|cheeky]
                [--debug-log FILE] [--trace]
               No UI and no Bluetooth. The hook socket defaults to DIR/boop.sock. A new state directory
               is set up with --name (default Boop). --mode, --classifier and --writer override the saved
               mode and its brain for this run only. Stops cleanly on SIGINT or SIGTERM. --trace logs
               every hook and every line sent to the device. {"dev":"advance","ms":N} on the socket
               moves the clock forward.
           Boop --snapshots DIR
               Renders the popover's panes and the menu-bar icons to PNGs from fixtures, then exits.
               No runtime, no Bluetooth.
    (boop \(BoopVersion.current))
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func option(_ args: [String], _ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

/// `steering.md` as bundled with the app (a copy of `plan/steering.md`).
func bundledSteering() -> String {
    guard let url = Bundle.module.url(forResource: "steering", withExtension: "md"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { fail("steering.md is missing from the app") }
    return text
}

/// Appends to `DIR/boop.log`, and echoes to stderr when asked.
final class LogFile: @unchecked Sendable {
    let handle: FileHandle?
    let echo: Bool
    let lock = NSLock()
    let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(directory: URL, echo: Bool) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("boop.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        self.echo = echo
    }

    func write(_ message: String) {
        lock.withLock {
            let line = format.string(from: Date()) + " " + message + "\n"
            // The throwing write: the old one raises an Objective-C exception
            // (a crash) on any error, such as a full disk.
            try? handle?.write(contentsOf: Data(line.utf8))
            if echo { try? FileHandle.standardError.write(contentsOf: Data(line.utf8)) }
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("-h") || args.contains("--help") {
    print(usage)
    exit(0)
}
if args.contains("--headless") {
    Headless.run(args)
} else if args.contains("--snapshots") {
    MainActor.assumeIsolated { Snapshots.run(args) }
} else {
    MenuBarApp.run(args)
}
