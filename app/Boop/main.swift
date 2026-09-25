import AppKit
import BoopKit
import Foundation

// The Boop app. With no arguments it's the menu-bar app on Bluetooth.
// `--headless` runs the same runtime with no UI and no Bluetooth, for tests
// and agents (VERIFICATION.md L4).

let usage = """
    usage: Boop [--state-dir DIR] [--link ble|usb:SOCKET|none]
               The menu-bar app. The owner runs this; it uses Bluetooth by default.
           Boop --headless --state-dir DIR [--link usb:SOCKET|none] [--socket PATH] [--brain apple|rules]
                [--name NAME] [--nature sweet|cheeky] [--debug-log FILE] [--trace]
               No UI and no Bluetooth. The hook socket defaults to DIR/boop.sock. A new state directory
               is set up with --name (default Boop). Stops cleanly on SIGINT or SIGTERM. --trace logs
               every hook and every line sent to the device. {"dev":"advance","ms":N} on the socket
               moves the clock forward.
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
            handle?.write(Data(line.utf8))
            if echo { FileHandle.standardError.write(Data(line.utf8)) }
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
} else {
    MenuBarApp.run(args)
}
