import JHarness
import LinkKit

/// The device in a JHarness log (jharness/SPEC.md §2): every `ev` it sends
/// but `ended`, as an event from `device` whose kind is the `ev`'s and
/// whose data is its `data`, with its `did`; what the device already did
/// about it on its own, as a `did` for that event in the app's words; and
/// the device coming and going, as `device_up` (the first `hello` that
/// fits on a link, with its `id` and `fw`) and `device_down` (that link
/// dropping). Register the kinds as inputs to give them lines and let them
/// wake the brain. A device whose firmware doesn't fit (`link.trouble`)
/// sends none of them: the link drops its `ev`s, which are another
/// firmware's words.
///
/// It sets the link's `onEvent`, `onHello` and `onConnection`, calling
/// what was set before first, and lives as long as they do. Everything
/// runs on the harness's queue, which must be the link's.
public final class DeviceEvents {
    public static let up = "device_up", down = "device_down"

    /// The events' source: `device`.
    public let source: String
    let harness: Harness
    let said: (DeviceEvent) -> String?
    /// A `device_up` was emitted and no `device_down` since.
    var isUp = false

    /// `said` words what the device did about an `ev` on its own (its
    /// `did`, `stopped`) as HISTORY's line for it, `The lamp stopped blinking.`; nil
    /// records none.
    public init(link: DeviceLink, harness: Harness, source: String = "device",
                said: @escaping (DeviceEvent) -> String? = { _ in nil }) {
        self.harness = harness
        self.source = source
        self.said = said
        let onEvent = link.onEvent
        link.onEvent = { ev in
            onEvent?(ev)
            self.event(ev)
        }
        let onHello = link.onHello
        link.onHello = { hello in
            onHello?(hello)
            self.hello(hello)
        }
        let onConnection = link.onConnection
        link.onConnection = { up in
            onConnection?(up)
            if !up { self.dropped() }
        }
    }

    /// `ev` as an event, and its `did` as the device's, in one batch, so
    /// the brain hears of both at once. Returns the event, as logged.
    @discardableResult
    public func event(_ ev: DeviceEvent) -> Event {
        var data = ev.data.values
        if let did = ev.did { data["did"] = .string(did) }
        var logged: Event!
        harness.batch {
            logged = harness.emit(source: source, kind: ev.kind, data: data)
            if let did = ev.did, let line = said(ev) { harness.did(line, for: logged, action: did, by: source) }
        }
        return logged
    }

    func hello(_ hello: Hello) {
        guard !isUp else { return }
        isUp = true
        harness.emit(source: source, kind: Self.up, data: ["id": .string(hello.id), "fw": .string(hello.fw)])
    }

    func dropped() {
        guard isUp else { return }
        isUp = false
        harness.emit(source: source, kind: Self.down)
    }
}
