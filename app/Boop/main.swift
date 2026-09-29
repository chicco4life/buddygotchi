import AppKit
import BoopKit
import Foundation

// The Boop app. With no arguments it's the menu-bar app on Bluetooth.
// `--headless` runs the same runtime with no UI and no Bluetooth, for tests
// and agents (VERIFICATION.md L4).

let usage = """
    usage: Boop [--state-dir DIR] [--link ble|usb:SOCKET|none] [--debug]
               The menu-bar app. The owner runs this; it uses Bluetooth by default. With a --state-dir
               other than the everyday one it never installs or repairs the hooks in ~/.claude and
               ~/.codex: they keep reporting to the everyday app's socket, not this one.
           Boop --headless --state-dir DIR [--link usb:SOCKET|none] [--socket PATH] [--personality boop|chatter]
                [--brain jev|scripted] [--name NAME] [--nature sweet|cheeky] [--debug]
               No UI and no Bluetooth. The hook socket defaults to DIR/boop.sock. A new state directory
               is set up with --name (default Boop). --personality overrides the saved one for this run only.
               --brain jev (the default) asks Jev only when BOOP_JEV_KEY holds its key, since headless never
               reads the Keychain; without it Boop does only its rule reactions. --brain scripted answers
               every pass the same way without a network: an excited "Go", for pipeline checks.
               Stops cleanly on SIGINT or SIGTERM. {"dev":"advance","ms":N} on the socket moves the clock forward.
               Every event goes to DIR/transcript/<date>.jsonl, read back at the next launch.
           --debug prints everything to this terminal as it happens: each hook and the raw event Boop made
               of it, every line sent to the device, and every view event, pass (with Jev's whole state) and
               action. The events, view events and passes also go to DIR/debug.jsonl, started afresh each
               launch, with the lines sent to the device, status changes and the questions (boopdev watch
               and boopctl dash read it). The last 10 launches' files are kept as DIR/debug.1.jsonl (the latest) to
               debug.10.jsonl, and boopctl day sums them all up by the hour. Jev's state never reaches boop.log.
           Headless, or with --debug, the hook socket also takes {"dev":…} lines from boopctl dash: "answer"
               (a forced pass), "mood" and "moment"; and for push-to-talk with no mic, "listen" (the app's
               button, {"dev":"listen","on":true}) and "said" (what the mic heard, {"dev":"said","words":"…"}).
           Boop --snapshots DIR
               Renders the popover's panes and the menu-bar icons to PNGs from fixtures, then exits.
               No runtime, no Bluetooth.
           A flag the chosen way doesn't take stops Boop with this usage, before anything starts.
    (boop \(BoopVersion.current))
    """

/// The steering folder as bundled with the app (a copy of `plan/steering/`).
func bundledSteering() -> Steering {
    guard let url = Bundle.module.url(forResource: "steering", withExtension: nil) else {
        fail("the steering folder is missing from the app")
    }
    do { return try Steering(directory: url) } catch { fail("the app's steering folder is broken: \(error)") }
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
            let line = stamped(message)
            // The throwing write: the old one raises an Objective-C exception
            // (a crash) on any error, such as a full disk.
            try? handle?.write(contentsOf: line)
            if echo { try? FileHandle.standardError.write(contentsOf: line) }
        }
    }

    func echo(_ message: String) {
        lock.withLock { try? FileHandle.standardError.write(contentsOf: stamped(message)) }
    }

    /// The message as a line, after the time. Only under `lock`.
    private func stamped(_ message: String) -> Data {
        Data((format.string(from: Date()) + " " + message + "\n").utf8)
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
        case .headless: ["--state-dir", "--link", "--socket", "--personality", "--brain", "--name", "--nature"]
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
let args = Arguments.parse(raw, options: launch.options, flags: launch.flags, command: "boop", usage: usage)
switch launch {
case .headless: Headless.run(args)
case .snapshots: MainActor.assumeIsolated { Snapshots.run(args) }
case .menuBar: MenuBarApp.run(args)
}
