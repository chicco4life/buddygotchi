import Foundation

/// Whether you yelled on push-to-talk (BEHAVIORS.md §3.3): the mic heard you
/// at −18 dBFS or louder for 300 ms or more in all. The app hands it each
/// stretch of audio as it's recorded and keeps only the answer; the audio
/// itself is thrown away.
public struct YellMeter: Sendable {
    /// Loud enough to count, in dBFS (proposed).
    public static let loudDBFS: Float = -18
    /// How long it has to be that loud, in all (proposed).
    public static let yellMs: Double = 300

    /// How long it has been that loud so far.
    public private(set) var loudMs: Double = 0

    public init() {}

    /// A stretch of samples' level: its RMS against full scale, in dBFS.
    public static func dbfs(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        var sum: Float = 0
        for x in samples { sum += x * x }
        let rms = (sum / Float(samples.count)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -.infinity
    }

    /// Adds a stretch of audio: its level and how long it lasted.
    public mutating func add(dbfs: Float, ms: Double) {
        if dbfs >= YellMeter.loudDBFS { loudMs += ms }
    }

    public var yelled: Bool { loudMs >= YellMeter.yellMs }
}
