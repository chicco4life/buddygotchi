import Foundation

/// Boop's voice (VOICE.md): the recorded takes the board has, and what a
/// reaction says. The only code that knows what Boop can say. The brain
/// answers how Boop feels and what NOW is about, and a kind; the face picks
/// the mood; Voice finds a take for each answer performed in that mood and
/// joins them into a line of at most two: the feeling, then the topic. A
/// take is never borrowed from another mood.
public struct Voice: Sendable {
    public let takes: [Take]

    /// The pause between a line's two takes, in milliseconds (VOICE.md §4).
    public static let joinGapMs = 180
    /// The longest line of two takes, gap included; a longer pair keeps
    /// only its first (VOICE.md §4).
    public static let maxLineMs = 2800

    public init(takes: [Take] = Take.all) {
        self.takes = takes
    }

    /// Every answer to `part`'s question that has a take, each once.
    public func answers(_ part: Take.Part) -> Set<String> {
        Set(takes.filter { $0.part == part }.map(\.meaning))
    }

    /// The faces that can say `meaning` for `part`, in `moods`' order.
    public func faces(saying meaning: String, part: Take.Part, in moods: [String]) -> [String] {
        let have = Set(takes.filter { $0.part == part && $0.meaning == meaning }.map(\.mood))
        return moods.filter(have.contains)
    }

    /// The kinds to try for `kind`, nearest first (VOICE.md §4): the kind
    /// itself, then plainer and fancier by distance, plainer first; a
    /// swear only when one was asked for.
    static func order(_ kind: Take.Kind) -> [Take.Kind] {
        let all = Take.Kind.allCases
        let at = all.firstIndex(of: kind)!
        return all.indices.sorted { (abs($0 - at), $0 > at ? 1 : 0) < (abs($1 - at), $1 > at ? 1 : 0) }
            .map { all[$0] }.filter { $0 != .swear || kind == .swear }
    }

    /// The take one answer says (VOICE.md §4): `part`'s `meaning`,
    /// performed in the `face`'s mood, fit for the turn's `finish` (a
    /// success take only on a success, a swear only on a failure), of the
    /// nearest kind to `kind` that has one, at random, and not one of
    /// `avoiding` (the last ones said) when another fits. Nil when none does.
    public func take(_ part: Take.Part, meaning: String, kind: Take.Kind, face: String, finish: String?,
                     avoiding: Set<String> = [], rng: inout SplitMix64) -> Take? {
        guard part != .attention else { return nil }
        let fit = takes.filter {
            $0.part == part && $0.meaning == meaning && $0.mood == face && ($0.finish == nil || $0.finish == finish)
        }
        for k in Self.order(kind) {
            var pool = fit.filter { $0.kind == k }
            if pool.contains(where: { !avoiding.contains($0.id) }) { pool.removeAll { avoiding.contains($0.id) } }
            if !pool.isEmpty { return pool[rng.int(in: 0...(pool.count - 1))] }
        }
        return nil
    }

    /// What a reaction says (VOICE.md §4): the feeling's take, then the
    /// topic's, each of the nearest kind to `kind` and in the face's mood.
    /// Either may be missing. A phrase plays alone, and so does the first
    /// take when the two would run past `maxLineMs`.
    public func line(feeling: String?, about: String?, kind: Take.Kind, face: String, finish: String?,
                     avoiding: Set<String> = [], rng: inout SplitMix64) -> [Take] {
        let first = feeling.flatMap {
            take(.feeling, meaning: $0, kind: kind, face: face, finish: finish, avoiding: avoiding, rng: &rng)
        }
        let second = about.flatMap {
            take(.about, meaning: $0, kind: kind, face: face, finish: finish, avoiding: avoiding, rng: &rng)
        }
        guard let first else { return second.map { [$0] } ?? [] }
        guard let second, first.kind != .phrase, second.kind != .phrase,
              first.ms + Self.joinGapMs + second.ms <= Self.maxLineMs else { return [first] }
        return [first, second]
    }
}
