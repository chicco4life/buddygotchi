import Foundation
import HookWire
import XCTest
@testable import BoopKit

/// Records what the link sends, and lets a test play the device.
final class FakeTransport: DeviceTransport, @unchecked Sendable {
    let lock = NSLock()
    var lines: [String] = []
    var onLine: (@Sendable (String) -> Void)?
    var onConnection: (@Sendable (Bool) -> Void)?
    var name: String { "fake" }

    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        self.onLine = onLine
        self.onConnection = onConnection
    }

    func send(_ line: String) { lock.withLock { lines.append(line) } }
    func reconnect() {}
    func stop() {}

    var sent: [String] { lock.withLock { lines } }
    func types() -> [String] {
        sent.compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])?["t"] as? String }
    }
}

func sampleSnapshot(busy: Int = 0) -> StateSnapshot {
    StateSnapshot(base: busy > 0 ? "working" : "idle", mood: "happy", attn: nil, busy: busy, idle: 0, wait: 0, vol: 6)
}

final class DeviceLinkTests: XCTestCase {
    func testFramerReassemblesLinesAcrossPackets() {
        var framer = LineFramer()
        XCTAssertEqual(framer.push(Array("{\"t\":\"inp".utf8)), [])
        XCTAssertEqual(framer.push(Array("ut\",\"k\":\"tap\"}\n{\"t\":".utf8)), ["{\"t\":\"input\",\"k\":\"tap\"}"])
        XCTAssertEqual(framer.push(Array("\"status\"}\r\n\n".utf8)), ["{\"t\":\"status\"}"])
    }

    func testFramerDropsAnOverlongLineAndRecovers() {
        var framer = LineFramer(maxLine: 16)
        XCTAssertEqual(framer.push(Array(String(repeating: "x", count: 40).utf8)), [])
        XCTAssertEqual(framer.push(Array("yyyy\nok\n".utf8)), ["ok"])
    }

    func testChunksFitTheLinkAndReassemble() {
        let line = sampleSnapshot().jsonLine
        let chunks = LineFramer.chunks(line, size: 20)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.count }, line.utf8.count + 1)
        var framer = LineFramer()
        XCTAssertEqual(chunks.flatMap { framer.push($0) }, [line])
    }

    /// PROTOCOL.md §2: Bluetooth lines go out whole, one piece at a time as
    /// CoreBluetooth takes them; a newer `state` replaces one still waiting,
    /// and a backlog drops its oldest lines that haven't started.
    func testBluetoothOutboxKeepsLinesWholeAndStatesFresh() {
        func drain(_ box: inout BLEOutbox) -> String {
            var bytes = Data()
            while let chunk = box.next() { bytes.append(chunk) }
            return String(decoding: bytes, as: UTF8.self)
        }
        let state1 = #"{"t":"state","v":1,"base":"working"}"#
        let state2 = #"{"t":"state","v":1,"base":"idle"}"#
        let cheer = #"{"t":"moment","anim":"cheer"}"#
        var box = BLEOutbox()
        box.add(state1, size: 8)
        box.add(cheer, size: 8)
        box.add(state2, size: 8)
        XCTAssertEqual(drain(&box), state2 + "\n" + cheer + "\n", "the newer state takes the waiting one's place")

        box.add(state1, size: 8)
        let started = String(decoding: box.next() ?? Data(), as: UTF8.self)  // state1 has started
        box.add(state2, size: 8)
        XCTAssertEqual(started + drain(&box), state1 + "\n" + state2 + "\n",
                       "a state that has started goes out whole, and the new one after it")

        for i in 0..<200 { box.add(#"{"t":"moment","anim":"wiggle","n":\#(i)}"#, size: 20) }
        XCTAssertLessThanOrEqual(box.bytes, BLEOutbox.limit)
        let lines = drain(&box).split(separator: "\n")
        XCTAssertTrue(lines.last?.contains(#""n":199"#) == true, "the newest is kept")
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("{") && $0.hasSuffix("}") }, "only whole lines")
        XCTAssertEqual(box.bytes, 0, "all sent")
    }

    /// PROTOCOL.md §2 (USB): the USB link sends on the runtime's queue, so a
    /// bridge that stops reading must cost a reconnect, not a frozen app.
    func testAUSBBridgeThatStopsReadingCantFreezeTheApp() throws {
        let path = "/tmp/boop-usb-stall-\(getpid()).sock"
        unlink(path)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        defer {
            close(server)
            unlink(path)
        }
        var address = try XCTUnwrap(HookSocket.unixAddress(path))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(server, 8), 0)  // accepts, never reads

        let transport = USBTransport(path: path)
        let ups = NSLock()
        nonisolated(unsafe) var changes: [Bool] = []
        transport.start(onLine: { _ in }, onConnection: { up in ups.withLock { changes.append(up) } })
        defer { transport.stop() }
        eventually("connected", timeout: 2) { !ups.withLock { changes.isEmpty } }
        XCTAssertEqual(ups.withLock { changes }, [true])

        let line = String(repeating: "x", count: 64 * 1024)
        let start = Date()
        for _ in 0..<64 { transport.send(line) }  // 4 MB into a socket nobody reads
        XCTAssertLessThan(Date().timeIntervalSince(start), 2 * Double(USBTransport.sendTimeoutMs) / 1000 + 1,
                          "one timed-out write, then the rest are dropped")
        eventually("dropped", timeout: 2) { ups.withLock { changes.count >= 2 } }
        XCTAssertEqual(ups.withLock { changes }.prefix(2), [true, false], "it lets go, to reconnect")
    }

    func testDecodesStatusInputAndIgnoresTheRest() {
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1"}"#),
                       .status(DeviceStatus(id: "b00p-7f3a", fw: "0.3.1")))
        // An older board's `bat` and `usb` are ignored.
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1","bat":3910,"usb":1}"#),
                       .status(DeviceStatus(id: "b00p-7f3a", fw: "0.3.1")))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"tap"}"#), .input(.tap))
        // Focus, touch-and-hold and push-to-talk were removed; an older
        // board's are ignored.
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"talk_on"}"#), .other(#"{"t":"input","k":"talk_on"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"focus"}"#), .other(#"{"t":"input","k":"focus"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"feel"}"#), .other(#"{"t":"input","k":"feel"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"dance"}"#), .other(#"{"t":"input","k":"dance"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"dbg.ping","up":5}"#), .other(#"{"t":"dbg.ping","up":5}"#))
        XCTAssertEqual(DeviceMessage.decode("rst:0x1 (POWERON_RESET)"), .other("rst:0x1 (POWERON_RESET)"))
    }

    /// PROTOCOL.md §3: `anim` is optional, and there's no `size` or `ttl`.
    func testMomentEncodingMatchesTheProtocol() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(DeviceMoment(anim: "cheer", say: line).jsonLine,
                       #"{"t":"moment","anim":"cheer","say":{"syl":"bi-do ba-na","word":"done","at":4,"tune":"up","ms":120}}"#)
        XCTAssertEqual(DeviceMoment(anim: "wiggle").jsonLine, #"{"t":"moment","anim":"wiggle"}"#)
        XCTAssertEqual(DeviceMoment(say: line).jsonLine,
                       #"{"t":"moment","say":{"syl":"bi-do ba-na","word":"done","at":4,"tune":"up","ms":120}}"#)
    }

    /// PROTOCOL.md §3: a `state` on every change, and the latest again
    /// after 10 s without one.
    func testStateGoesOutOnChangeAndEveryTenSeconds() {
        let transport = FakeTransport()
        let link = DeviceLink(transport: transport)
        link.update(sampleSnapshot(), now: 0)
        link.update(sampleSnapshot(), now: 1000)  // nothing changed
        XCTAssertEqual(transport.sent.count, 1)
        link.update(sampleSnapshot(busy: 1), now: 2000)
        XCTAssertEqual(transport.sent.count, 2)
        link.tick(now: 11_000)
        XCTAssertEqual(transport.sent.count, 2)
        link.tick(now: 12_000)
        XCTAssertEqual(transport.sent.count, 3)
        XCTAssertEqual(transport.sent[2], transport.sent[1], "the keepalive is the latest line again")
    }

    func testStatusAndConnectGetTheLatestState() {
        let transport = FakeTransport()
        let link = DeviceLink(transport: transport)
        link.update(sampleSnapshot(busy: 2), now: 0)
        link.connection(true, now: 100)
        XCTAssertEqual(transport.types(), ["state", "state"])
        XCTAssertEqual(link.receive(#"{"t":"status","v":1,"id":"b00p-54fe","fw":"1.0.0"}"#, now: 200),
                       .status(DeviceStatus(id: "b00p-54fe", fw: "1.0.0")))
        XCTAssertEqual(transport.types(), ["state", "state", "state"])
        XCTAssertEqual(link.status?.id, "b00p-54fe")
        XCTAssertTrue(transport.sent.last!.contains("\"busy\":2"))
        link.connection(false, now: 300)
        XCTAssertNil(link.status)
        XCTAssertFalse(link.connected)
    }

    private let esc = String(repeating: "\\u0001", count: 23)

    /// PROTOCOL.md §2: a line is at most 512 bytes. The biggest `state`,
    /// with a 23-byte project that escapes to six bytes a character, fits.
    func testEveryStateLineFitsTheProtocol() {
        let widest = String(repeating: "\u{1}", count: 23)
        let s = StateSnapshot(base: "working", mood: "determined", attn: .init(agent: "claude", project: widest, more: 999),
                              busy: 999, idle: 999, wait: 999, vol: 10)
        XCTAssertLessThanOrEqual(s.jsonLine.utf8.count, StateSnapshot.maxLine)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(s.jsonLine.utf8)))
        XCTAssertEqual(s.jsonLine, #"{"t":"state","v":1,"base":"working","mood":"determined","attn":{"agent":"claude","project":"\#(esc)","more":999},"busy":999,"idle":999,"wait":999,"vol":10}"#)
    }

    /// PROTOCOL.md §2, "Reconnecting": 1 s, doubling to 5 s, reset once a
    /// connection works; an attempt gets 10 s to become ready.
    func testBluetoothReconnectTiming() {
        var backoff = ReconnectBackoff()
        XCTAssertEqual((0..<5).map { _ in backoff.next() }, [1, 2, 4, 5, 5])
        backoff.reset()
        XCTAssertEqual(backoff.next(), 1)
        XCTAssertEqual(BLETransport.connectTimeout, 10)
    }

    func testLinkSettings() {
        XCTAssertEqual(LinkSetting("usb:/tmp/x.sock"), .usb("/tmp/x.sock"))
        XCTAssertEqual(LinkSetting("ble"), .bluetooth)
        XCTAssertEqual(LinkSetting("none"), LinkSetting.none)
        XCTAssertNil(LinkSetting("usb:"))
        XCTAssertNil(LinkSetting("wifi"))
    }
}
