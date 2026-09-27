import BoopKit
import Foundation

/// `Boop --headless`: the whole runtime with isolated state, no UI and no
/// Bluetooth. The device, if any, is reached through `boopctl bridge`.
enum Headless {
    static func run(_ args: Arguments) -> Never {
        guard let dir = args["--state-dir"] else { fail("--headless needs --state-dir\n" + usage) }
        let stateDir = URL(fileURLWithPath: dir).standardizedFileURL
        let transport: DeviceTransport?
        switch LinkSetting(args["--link"] ?? "none") {
        case .usb(let path): transport = USBTransport(path: path)
        case .none?: transport = nil
        case .bluetooth?: fail("headless mode never uses Bluetooth; use --link usb:SOCKET")
        case nil: fail("--link is usb:SOCKET or none")
        }
        let socketPath = args["--socket"] ?? stateDir.appendingPathComponent("boop.sock").path
        // Checked before anything is set up: a Unix socket's path has room
        // for 103 bytes (sockaddr_un), and a scratch directory is often longer.
        let room = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
        if socketPath.utf8.count > room {
            fail("the hook socket \(socketPath) is \(socketPath.utf8.count) bytes, and a Unix socket's path "
                 + "has room for \(room): pass --socket with a shorter one")
        }
        // Every value is checked before anything is written, so a typo
        // doesn't leave a set-up Boop behind for the next run to keep.
        let mode = args.choice("--mode", of: Mode.allCases.map(\.rawValue)).flatMap(Mode.init(rawValue:))
        let classifier = args.choice("--classifier", of: Brains.classifiers)
        let writer = args.choice("--writer", of: Brains.writers)
        guard let nature = LongTerm.Nature(rawValue: args["--nature"] ?? "sweet") else { fail("--nature is sweet or cheeky") }
        let log = LogFile(directory: stateDir, echo: true)

        let memory = try? MemoryStore(directory: stateDir, steering: "")
        if memory?.isSetUp != true {
            let name = args["--name"] ?? "Boop"
            do {
                try Runtime.setUp(stateDir: stateDir, name: name, nature: nature, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
                log.write("boop: set up \(name) (\(nature.rawValue)) in \(stateDir.path)")
            } catch {
                fail("can't set up \(stateDir.path): \(error)")
            }
        }

        var options = Runtime.Options(stateDir: stateDir,
                                      socketPath: socketPath,
                                      link: transport, steering: bundledSteering())
        // Jev's key only from BOOP_JEV_KEY, as boopdev: a run from an agent
        // shell must never use the owner's key from the Keychain (HARNESS.md §6).
        options.readJevKey = { Brains.environmentJevKey() }
        // The clock can be moved forward with `{"dev":"advance","ms":N}`, so
        // the pipeline check can finish a 6-minute turn without waiting it out.
        let skew = Skew()
        let steady = Runtime.steadyClock()
        options.clock = { steady() + skew.ms }
        options.wallClock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.ms }
        options.advance = { skew.add($0) }
        options.debug = args.has("--debug")
        options.debugPrint = { log.echo($0) }
        if let mode { options.mode = mode }
        options.classifier = classifier
        options.writer = writer
        options.devLines = true
        options.log = { log.write($0) }
        let runtime: Runtime
        do {
            runtime = try Runtime(options)
            try runtime.start()
        } catch {
            fail("boop: \(error)")
        }

        // Stop cleanly: close the socket and the link, then exit 0.
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                log.write("boop: stopping (signal \(sig))")
                runtime.stop()
                runtime.home.sync {}
                log.write("boop: stopped")
                exit(0)
            }
            source.resume()
            sources.append(source)
        }
        withExtendedLifetime(sources) { dispatchMain() }
    }
}

/// How far headless mode's clock has been moved forward.
final class Skew: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0
    var ms: Int64 { lock.withLock { value } }
    func add(_ ms: Int64) { lock.withLock { value += ms } }
}
