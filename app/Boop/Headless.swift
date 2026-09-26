import BoopKit
import Foundation

/// `Boop --headless`: the whole runtime with isolated state, no UI and no
/// Bluetooth. The device, if any, is reached through `boopctl bridge`.
enum Headless {
    static func run(_ args: [String]) -> Never {
        guard let dir = option(args, "--state-dir") else { fail("--headless needs --state-dir\n" + usage) }
        let stateDir = URL(fileURLWithPath: dir).standardizedFileURL
        let transport: DeviceTransport?
        switch LinkSetting(option(args, "--link") ?? "none") {
        case .usb(let path): transport = USBTransport(path: path)
        case .none?: transport = nil
        case .bluetooth?: fail("headless mode never uses Bluetooth; use --link usb:SOCKET")
        case nil: fail("--link is usb:SOCKET or none")
        }
        let log = LogFile(directory: stateDir, echo: true)

        let memory = try? MemoryStore(directory: stateDir, steering: "")
        if memory?.isSetUp != true {
            let nature = LongTerm.Nature(rawValue: option(args, "--nature") ?? "sweet") ?? .sweet
            let name = option(args, "--name") ?? "Boop"
            do {
                try Runtime.setUp(stateDir: stateDir, name: name, nature: nature, today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
                log.write("boop: set up \(name) (\(nature.rawValue)) in \(stateDir.path)")
            } catch {
                fail("can't set up \(stateDir.path): \(error)")
            }
        }

        var options = Runtime.Options(stateDir: stateDir,
                                      socketPath: option(args, "--socket") ?? stateDir.appendingPathComponent("boop.sock").path,
                                      link: transport, steering: bundledSteering())
        // The clock can be moved forward with `{"dev":"advance","ms":N}`, so
        // the pipeline check can finish a 6-minute turn without waiting it out.
        let skew = Skew()
        options.clock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.ms }
        options.advance = { skew.add($0) }
        options.trace = args.contains("--trace")
        if let name = option(args, "--mode") {
            guard let mode = Mode(rawValue: name) else { fail("--mode is chatty, normal or calm") }
            options.mode = mode
        }
        options.classifier = option(args, "--classifier")
        options.writer = option(args, "--writer")
        if let c = options.classifier, !Brains.classifiers.contains(c) {
            fail("--classifier is " + Brains.classifiers.joined(separator: ", "))
        }
        if let w = options.writer, !Brains.writers.contains(w) { fail("--writer is " + Brains.writers.joined(separator: ", ")) }
        options.devLines = true
        options.debugLog = option(args, "--debug-log").map { URL(fileURLWithPath: $0) }
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
