import Foundation
import JHarness
import JHarnessLink
import LinkKit
import Testing

/// Records what the link sends.
final class FakeTransport: Transport, @unchecked Sendable {
    let lock = NSLock()
    var lines: [String] = []
    var name: String { "fake" }

    func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {}
    func send(_ line: String) { lock.withLock { lines.append(line) } }
    func reconnect() {}
    func stop() {}

    /// The `do`s sent, as the device reads them.
    var dos: [(id: Int, name: String, play: String)] {
        lock.withLock { lines }.compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["t"] as? String == "do",
                  let id = o["id"] as? Int, let name = o["name"] as? String, let play = o["play"] as? String else { return nil }
            return (id, name, play)
        }
    }
}

let helloLine = #"{"t":"hello","kit":1,"app":"pip","id":"pip-54fe","fw":"1.0.0","does":["react","cheer"]}"#

func ended(_ id: Int, _ how: String, _ why: String? = nil) -> String {
    #"{"t":"ev","kind":"ended","data":{"id":\#(id),"how":"\#(how)""# + (why.map { #","why":"\#($0)""# } ?? "") + "}}"
}

/// A harness with no brain and a link to a fake device, both on one queue,
/// as an app runs them.
final class Rig: @unchecked Sendable {
    let queue = DispatchQueue(label: "jharnesslink.test")
    let harness: Harness
    let link: DeviceLink
    let transport = FakeTransport()
    var now: Int64 = 1_790_000_000_000

    init(connected: Bool = true, hello: Bool = true) {
        var options = Harness.Options()
        options.loop = false
        let clock = Box(now)
        harness = Harness(name: "Pip", brain: nil, log: Log(), clock: .init(now: { clock.value }), queue: queue, options: options)
        link = DeviceLink(app: "pip", transport: transport)
        queue.sync {
            if connected { link.connection(true, now: now) }
            if hello { link.receive(helloLine, now: now) }
        }
    }

    @discardableResult
    func sync<T>(_ body: () throws -> T) rethrows -> T { try queue.sync(execute: body) }

    /// The log's events of `kind`, oldest first.
    func events(_ kind: String) -> [Event] {
        sync { harness.log.view(now: now).all(kind) }
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite struct PendingDoTests {
    /// How each outcome finishes a `Pending` by default: done is done, a
    /// cut or a skip failed with the device's why, and a failure here in
    /// its own words.
    @Test func testTheDefaultMapping() {
        #expect(DeviceLink.end(.ended(Ended(id: 1, how: .done))) == .done)
        #expect(DeviceLink.end(.ended(Ended(id: 1, how: .cut, why: "tap"))) == .failed("cut short: tap"))
        #expect(DeviceLink.end(.ended(Ended(id: 1, how: .cut))) == .failed("cut short"))
        #expect(DeviceLink.end(.ended(Ended(id: 1, how: .skipped, why: "late"))) == .failed("skipped: late"))
        #expect(DeviceLink.end(.ended(Ended(id: 1, how: .skipped))) == .failed("skipped"))
        #expect(DeviceLink.end(.failed(.disconnected)) == .failed("the device disconnected"))
        #expect(DeviceLink.end(.failed(.notConnected)) == .failed("no device connected"))
        #expect(DeviceLink.end(.failed(.noAnswer)) == .failed("the device never said it ended"))
    }

    /// The device's `ended` finishes the `Pending`, once; a link that drops
    /// fails it; one that can't be sent fails at once.
    @Test func testTheDeviceFinishesThePending() {
        let rig = Rig()
        func pending() -> (Pending, Box<[Pending.End]>) {
            let p = Pending(), ends = Box<[Pending.End]>([])
            p.bind { ends.value.append($0) }
            return (p, ends)
        }
        let (played, playedEnds) = pending(), (dropped, droppedEnds) = pending()
        rig.sync {
            let id = rig.link.do("react", now: rig.now, pending: played)!
            rig.link.do("cheer", play: .now, now: rig.now, pending: dropped)
            rig.link.receive(ended(id, "done"), now: rig.now)
            rig.link.receive(ended(id, "cut", "tap"), now: rig.now)
            rig.link.connection(false, now: rig.now)
        }
        #expect(playedEnds.value == [.done])
        #expect(droppedEnds.value == [.failed("the device disconnected")])
        let (alone, aloneEnds) = pending()
        #expect(rig.sync { rig.link.do("react", now: rig.now, pending: alone) } == nil)
        #expect(aloneEnds.value == [.failed("no device connected")], "at once")
    }

    /// An app's own mapping; nil leaves the `Pending` open for the app to
    /// finish later.
    @Test func testAnAppsMappingMayLeaveItOpen() {
        let rig = Rig()
        let held = Pending(), ends = Box<[Pending.End]>([])
        held.bind { ends.value.append($0) }
        rig.sync {
            let id = rig.link.do("react", now: rig.now, pending: held) { outcome in
                if case .ended(let e) = outcome, e.why == "tap" { return nil }
                return DeviceLink.end(outcome)
            }!
            rig.link.receive(ended(id, "cut", "tap"), now: rig.now)
        }
        #expect(ends.value.isEmpty)
        held.finish(.done)
        #expect(ends.value == [.done])
    }
}

@Suite struct DeviceEventsTests {
    /// Every `ev` but `ended` becomes an event from `device`, with its data
    /// and its `did`; what the device did becomes a `did` for it in the
    /// app's words, when it has some.
    @Test func testEventsReachTheLog() throws {
        let rig = Rig(hello: false)
        let heard = Box<[String]>([])
        rig.sync { rig.link.onEvent = { heard.value.append("app \($0.kind)") } }
        _ = rig.sync {
            DeviceEvents(link: rig.link, harness: rig.harness) { ev in ev.did == "poked" ? "Pip wiggled." : nil }
        }
        let id = try #require(rig.sync { rig.link.receive(helloLine, now: rig.now); return rig.link.do("react", now: rig.now) { _ in } })
        rig.sync {
            for line in [#"{"t":"ev","kind":"tap","did":"poked"}"#, #"{"t":"ev","kind":"tap","did":"dip","data":{"on":44}}"#,
                         ended(id, "done"), #"{"t":"ev","kind":"talk_on"}"#] {
                rig.link.receive(line, now: rig.now)
            }
        }
        #expect(heard.value == ["app tap", "app tap", "app talk_on"], "what the app set is still called")
        let taps = rig.events("tap")
        #expect(taps.map(\.source) == ["device", "device"])
        #expect(taps.map { $0["did"] } == ["poked", "dip"])
        #expect(taps[1]["on"] == .int(44))
        #expect(rig.events("talk_on").count == 1)
        #expect(rig.events("ended").allSatisfy { $0.source != "device" }, "an ended is the link's")
        let dids = rig.events(Event.did)
        #expect(dids.map { $0["message"] } == [.string("Pip wiggled.")])
        #expect(dids.first?.about == taps[0].seq)
        #expect(dids.first?.action == "poked")
        #expect(dids.first?["by"] == "device")
    }

    /// `device_up` at the first `hello` that fits on a link, with its id
    /// and firmware, not at the ones that repeat; `device_down` when that
    /// link drops.
    @Test func testTheDeviceComesAndGoes() {
        let rig = Rig(hello: false)
        _ = rig.sync { DeviceEvents(link: rig.link, harness: rig.harness) }
        rig.sync {
            rig.link.receive(helloLine, now: rig.now)
            rig.link.receive(helloLine.replacingOccurrences(of: "1.0.0", with: "1.0.1"), now: rig.now)
            rig.link.connection(false, now: rig.now)
            rig.link.connection(true, now: rig.now)
            rig.link.connection(false, now: rig.now)
        }
        let up = rig.events(DeviceEvents.up)
        #expect(up.count == 1)
        #expect(up.first?["id"] == "pip-54fe")
        #expect(up.first?["fw"] == "1.0.0")
        #expect(rig.events(DeviceEvents.down).count == 1, "a link that never said hello doesn't count")
    }
}

@Suite struct PlayTests {
    static let described = [Option("cheer", "A win."), Option("dance", "A party.")]

    /// Its options are none, then the names the app describes that the
    /// device's `hello` says it plays, in the app's order.
    @Test func testTheOptionsFollowTheHello() {
        let rig = Rig(hello: false)
        let play = Play(link: rig.link, question: "What should Pip play?", judgeBy: "NOW", options: Self.described,
                        clock: { rig.now })
        let names = { rig.sync { play.questions(now: nil, log: rig.harness.log.view(now: rig.now))[0].options.map(\.name) } }
        #expect(names() == ["none"], "before a hello")
        rig.sync { rig.link.receive(helloLine, now: rig.now) }
        #expect(names() == ["none", "cheer"], "the device doesn't dance")
        rig.sync { rig.link.receive(helloLine.replacingOccurrences(of: #""react","cheer""#, with: #""dance","cheer""#), now: rig.now) }
        #expect(names() == ["none", "cheer", "dance"])
        rig.sync { rig.link.connection(false, now: rig.now) }
        #expect(names() == ["none"])
    }

    /// A pick goes out as a `do` with `play: next` and starts: HISTORY
    /// shows it in progress until the device's `ended` finishes it. None,
    /// or a name it wasn't offered, does nothing.
    @Test func testAPickPlaysAndEndsWhenTheDeviceSays() throws {
        let rig = Rig()
        let play = Play(link: rig.link, question: "What should Pip play?", judgeBy: "NOW", options: Self.described,
                        said: { "Pip played \($0)." }, clock: { rig.now })
        rig.sync { rig.harness.output(play) }
        #expect(rig.sync { rig.harness.force(["play": "none"], by: "test") }.isEmpty)
        #expect(rig.sync { rig.harness.force(["play": "dance"], by: "test") }.isEmpty)
        let ran = rig.sync { rig.harness.force(["play": "cheer"], by: "test") }
        #expect(ran.map(\.result.message) == ["Pip played cheer."])
        let sent = try #require(rig.transport.dos.last)
        #expect(sent.name == "cheer")
        #expect(sent.play == "next")
        let did = try #require(rig.events(Event.did).last)
        #expect(did["open"] == true, "in progress")
        rig.sync { rig.link.receive(ended(sent.id, "skipped", "late"), now: rig.now) }
        let end = try #require(rig.events(Event.ended).last)
        #expect(end.about == did.seq)
        #expect(end["why"] == "skipped: late")
    }
}
