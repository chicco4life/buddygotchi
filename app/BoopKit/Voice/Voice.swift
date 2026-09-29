import Foundation

/// Boop's voice (VOICE.md): the recorded takes the board has, and which one
/// a reaction says. The only code that knows what Boop can say. The brain
/// picks a meaning and a kind, the face picks the mood, and Voice finds a
/// take of that meaning performed in that mood, or none: then Boop makes
/// its face in silence. A take is never borrowed from another mood.
public struct Voice: Sendable {
    public let takes: [Take]

    /// Meanings only the rules may say (needs you's), which no reaction
    /// offers: the ding is needs you's only sound (BEHAVIORS.md §3.2).
    public static let rulesOnly: Set<String> = ["attention"]

    public init(takes: [Take] = Take.all) {
        self.takes = takes
    }

    /// Every meaning a reaction can say, each once.
    public var meanings: Set<String> { Set(takes.map(\.meaning)).subtracting(Voice.rulesOnly) }

    /// The faces that can say `meaning`, in `moods`' order.
    public func faces(saying meaning: String, in moods: [String]) -> [String] {
        let have = Set(takes.filter { $0.meaning == meaning }.map(\.mood))
        return moods.filter(have.contains)
    }

    /// The take a reaction says (VOICE.md §4): of `meaning`, performed in
    /// the `face`'s mood, fit for the turn's `finish` (a success take only
    /// on a success, a swear only on a failure), of the `kind` asked for or
    /// the nearest plainer kind that has one, at random, and not `avoiding`
    /// (the last one said) when another fits. Nil when none does.
    public func take(meaning: String, kind: Take.Kind, face: String, finish: String?, avoiding: String?,
                     rng: inout SplitMix64) -> Take? {
        guard !Voice.rulesOnly.contains(meaning) else { return nil }
        let fit = takes.filter { $0.meaning == meaning && $0.mood == face && ($0.finish == nil || $0.finish == finish) }
        let order = Take.Kind.allCases
        for k in order[...order.firstIndex(of: kind)!].reversed() {
            var pool = fit.filter { $0.kind == k }
            if pool.count > 1 { pool.removeAll { $0.id == avoiding } }
            if !pool.isEmpty { return pool[rng.int(in: 0...(pool.count - 1))] }
        }
        return nil
    }
}
