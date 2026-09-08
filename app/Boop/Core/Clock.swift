import Foundation

@MainActor
protocol Clock: Sendable {
    func now() -> Double
}

@MainActor
final class WallClock: Clock {
    func now() -> Double { Date.now.timeIntervalSince1970 * 1000 }
}
