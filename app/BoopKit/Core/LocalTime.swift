import Foundation

/// Local calendar maths for the core: days, and the time as input lines
/// and memory files write it. Times are milliseconds since 1970.
public struct LocalTime: Sendable {
    public var timeZone: TimeZone
    private var calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// `2026-10-14`.
    public func day(_ ms: Int64) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date(ms))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `14:05`.
    public func clock(_ ms: Int64) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date(ms))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `Tuesday`.
    public func weekday(_ ms: Int64) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let index = calendar.component(.weekday, from: date(ms)) - 1
        return names[max(0, min(6, index))]
    }

    /// The day `n` days after a `yyyy-MM-dd`.
    public static func day(_ day: String, plus n: Int) -> String {
        guard let o = ordinal(day) else { return day }
        return fromOrdinal(o + n)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar.
    static func ordinal(_ day: String) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var (y, m) = (parts[0], parts[1])
        let d = parts[2]
        if m <= 2 { y -= 1; m += 12 }
        let era = y / 400
        let yoe = y - era * 400
        let doy = (153 * (m - 3) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func fromOrdinal(_ n: Int) -> String {
        let z = n + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

/// A small seeded generator, so rule timings are repeatable in tests.
public struct SplitMix64: Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range`.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func chance(_ percent: Int) -> Bool { int(in: 0...99) < percent }
}
