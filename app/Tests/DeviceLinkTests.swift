import Foundation
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

func sampleSnapshot(busy: Int = 0, time: Int64 = 1_790_000_000) -> StateSnapshot {
    StateSnapshot(time: time, name: "Pip", base: busy > 0 ? "working" : "idle", attn: nil, busy: busy, idle: 0, wait: 0,
                  mood: Mood(), quiet: 0, vol: 6, night: false, level: 1, prog: 0, days: 1, hungry: 0,
                  threads: [])
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

    func testDecodesStatusInputAndIgnoresTheRest() {
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1","bat":3910,"usb":1}"#),
                       .status(DeviceStatus(id: "b00p-7f3a", fw: "0.3.1", bat: 3910, usb: true)))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"talk_on"}"#), .input(.talkOn))
        // Focus and touch-and-hold were removed; an older board's are ignored.
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"focus"}"#), .other(#"{"t":"input","k":"focus"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"feel"}"#), .other(#"{"t":"input","k":"feel"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"input","k":"dance"}"#), .other(#"{"t":"input","k":"dance"}"#))
        XCTAssertEqual(DeviceMessage.decode(#"{"t":"dbg.ping","up":5}"#), .other(#"{"t":"dbg.ping","up":5}"#))
        XCTAssertEqual(DeviceMessage.decode("rst:0x1 (POWERON_RESET)"), .other("rst:0x1 (POWERON_RESET)"))
    }

    func testMomentEncodingMatchesTheProtocol() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(DeviceMoment(anim: "cheer", size: 2, say: line, ttl: 5).jsonLine,
                       #"{"t":"moment","anim":"cheer","size":2,"say":{"syl":"bi-do ba-na","word":"done","at":4,"tune":"up","ms":120},"ttl":5}"#)
        XCTAssertEqual(DeviceMoment(anim: "nod").jsonLine, #"{"t":"moment","anim":"nod","size":1,"ttl":5}"#)
    }

    func testStateGoesOutOnChangeAndEveryTenSeconds() {
        let transport = FakeTransport()
        let link = DeviceLink(transport: transport)
        link.update(sampleSnapshot(), now: 0)
        link.update(sampleSnapshot(time: 1_790_000_001), now: 1000)  // only the clock changed
        XCTAssertEqual(transport.sent.count, 1)
        link.update(sampleSnapshot(busy: 1), now: 2000)
        XCTAssertEqual(transport.sent.count, 2)
        link.tick(now: 11_000, current: sampleSnapshot(busy: 1))
        XCTAssertEqual(transport.sent.count, 2)
        link.tick(now: 12_000, current: sampleSnapshot(busy: 1, time: 1_790_000_012))
        XCTAssertEqual(transport.sent.count, 3)
        XCTAssertTrue(transport.sent[2].contains("\"time\":1790000012"))
    }

    func testStatusAndConnectGetTheLatestState() {
        let transport = FakeTransport()
        let link = DeviceLink(transport: transport)
        link.update(sampleSnapshot(busy: 2), now: 0)
        link.connection(true, now: 100)
        XCTAssertEqual(transport.types(), ["state", "state"])
        XCTAssertEqual(link.receive(#"{"t":"status","v":1,"id":"b00p-54fe","fw":"1.0.0","bat":0,"usb":1}"#, now: 200),
                       .status(DeviceStatus(id: "b00p-54fe", fw: "1.0.0", bat: 0, usb: true)))
        XCTAssertEqual(transport.types(), ["state", "state", "state"])
        XCTAssertEqual(link.status?.id, "b00p-54fe")
        XCTAssertTrue(transport.sent.last!.contains("\"busy\":2"))
        link.connection(false, now: 300)
        XCTAssertNil(link.status)
        XCTAssertFalse(link.connected)
    }

    func testEveryStateLineFitsTheProtocol() {
        var s = sampleSnapshot()
        s.threads = (0..<8).map { ["claude", String(repeating: "p\($0)", count: 20), "work"] }
        s.fit()
        XCTAssertLessThanOrEqual(s.jsonLine.utf8.count, StateSnapshot.maxLine)
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
