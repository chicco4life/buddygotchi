import AppKit
import BoopKit
import Foundation

// The Boop app. With no arguments it's the menu-bar app on Bluetooth.
// `--headless` runs the same runtime with no UI and no Bluetooth, for tests
// and agents (VERIFICATION.md L4).

let usage = """
    usage: Boop [--state-dir DIR] [--link ble|usb:SOCKET|none] [--debug]
               The menu-bar app. The owner runs this; it uses Bluetooth by default.
           Boop --headless --state-dir DIR [--link usb:SOCKET|none] [--socket PATH] [--mode chatty|normal|calm]
                [--classifier \(Brains.classifiers.joined(separator: "|"))] [--writer \(Brains.writers.joined(separator: "|"))]
                [--name NAME] [--nature sweet|cheeky] [--debug]
               No UI and no Bluetooth. The hook socket defaults to DIR/boop.sock. A new state directory
               is set up with --name (default Boop). --mode, --classifier and --writer override the saved
               mode and its brain for this run only. Stops cleanly on SIGINT or SIGTERM.
               {"dev":"advance","ms":N} on the socket moves the clock forward.
           --debug prints everything to this terminal as it happens: each hook and what Boop made of it,
               the core's decisions, every line sent to the device, and every brain pass (the input, the
               memory and window the brains read, what Stage 1 decided and why, Stage 2's words, what ran).
               The passes also go to DIR/debug.jsonl, started afresh each launch (boopdev watch reads it).
               What you said and what the brain wrote never reach boop.log.
           Boop --snapshots DIR
               Renders the popover's panes and the menu-bar icons to PNGs from fixtures, then exits.
               No runtime, no Bluetooth.
           A flag the chosen way doesn't take stops Boop with this usage, before anything starts.
    (boop \(BoopVersion.current))
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}


/// `steering.md` as bundled with the app (a copy of `plan/steering.md`).
func bundledSteering() -> String {
    guard let url = Bundle.module.url(forResource: "steering", withExtension: "md"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { fail("steering.md is missing from the app") }
    return text
}

/// Appends to `DIR/boop.log`, and echoes to stderr when asked. `echo`
/// prints to stderr alone, for what must stay out of the file.
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

    func echo(_ message: String) {
        lock.withLock {
            let line = format.string(from: Date()) + " " + message + "\n"
            try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
        }
    }
}

/// The ways to run Boop and what each takes. Anything else stops with the
/// usage: a mistyped flag would otherwise start the menu-bar app, which uses
/// Bluetooth and repairs the real hooks.
enum Launch {
    case menuBar, headless, snapshots

    var options: Set<String> {
        switch self {
        case .menuBar: ["--state-dir", "--link"]
        case .headless: ["--state-dir", "--link", "--socket", "--mode", "--classifier", "--writer", "--name", "--nature"]
        case .snapshots: ["--snapshots"]
        }
    }

    var flags: Set<String> {
        switch self {
        case .menuBar: ["--debug"]
        case .headless: ["--headless", "--debug"]
        case .snapshots: []
        }
    }
}

let raw = Array(CommandLine.arguments.dropFirst())
let launch: Launch = raw.contains("--headless") ? .headless : raw.contains("--snapshots") ? .snapshots : .menuBar
let args: Arguments
do {
    args = try Arguments(raw, options: launch.options, flags: launch.flags)
} catch {
    fail("boop: \(error)\n\(usage)")
}
if args.help {
    print(usage)
    exit(0)
}
switch launch {
case .headless: Headless.run(args)
case .snapshots: MainActor.assumeIsolated { Snapshots.run(args) }
case .menuBar: MenuBarApp.run(args)
}
