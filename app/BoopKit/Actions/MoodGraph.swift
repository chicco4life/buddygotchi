import Foundation

/// Boop's 13 moods and the moves between them (harness/DECISIONS.md §2.3):
/// the owner's approved graph,
/// internal/boop-design/boop-mood-spectrum-v2/mood-graph.json, which a
/// test holds this copy to. A mood only ever moves to one of its
/// neighbours, one step a pass; staying is always allowed and isn't a
/// move. An ordinary move is a small, plausible change; a dramatic one is
/// a jump that needs a fresh, big event. A move's reverse may be of the
/// other kind, or not exist. No timer paces the moves: the steering does.
public enum MoodGraph {
    /// Every mood, in the device's order (`render::Mood`, `FaceLoops.moods`):
    /// the seven older ones keep their numbers.
    public static let moods = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad",
                               "calm", "engaged", "annoyed", "irritated", "whiny", "wounded"]

    /// Where a mood can move, in the graph file's order.
    public struct Moves: Equatable, Sendable {
        public let ordinary: [String]
        public let dramatic: [String]
        /// Every neighbour: the ordinary moves, then the dramatic ones.
        public var all: [String] { ordinary + dramatic }
    }

    /// Each mood's moves.
    public static let moves: [String: Moves] = [
        "calm": Moves(ordinary: ["happy", "curious", "engaged", "annoyed"], dramatic: ["excited", "wounded", "sad"]),
        "happy": Moves(ordinary: ["calm", "excited", "proud", "curious", "engaged", "annoyed"], dramatic: ["wounded", "sad"]),
        "excited": Moves(ordinary: ["happy", "proud", "curious", "determined"], dramatic: ["grumpy", "sad"]),
        "proud": Moves(ordinary: ["happy", "excited", "engaged", "determined", "annoyed"], dramatic: ["wounded", "grumpy", "sad"]),
        "curious": Moves(ordinary: ["calm", "happy", "excited", "engaged", "determined", "annoyed"], dramatic: ["wounded", "sad"]),
        "engaged": Moves(ordinary: ["calm", "happy", "curious", "determined", "proud", "annoyed"], dramatic: ["excited", "sad"]),
        "determined": Moves(ordinary: ["engaged", "proud", "annoyed", "irritated", "whiny"], dramatic: ["excited", "grumpy", "sad"]),
        "annoyed": Moves(ordinary: ["calm", "engaged", "determined", "irritated", "whiny"], dramatic: ["grumpy", "wounded", "sad"]),
        "irritated": Moves(ordinary: ["annoyed", "grumpy", "determined", "whiny"], dramatic: ["calm", "wounded", "sad", "proud"]),
        "grumpy": Moves(ordinary: ["irritated", "annoyed", "whiny", "determined"], dramatic: ["calm", "wounded", "sad", "proud"]),
        "whiny": Moves(ordinary: ["annoyed", "irritated", "determined", "wounded", "sad", "calm"], dramatic: ["happy", "grumpy"]),
        "wounded": Moves(ordinary: ["sad", "whiny", "calm", "annoyed"], dramatic: ["happy", "determined", "grumpy"]),
        "sad": Moves(ordinary: ["wounded", "whiny", "calm"], dramatic: ["determined", "happy", "grumpy"]),
    ]

    /// Where `mood` can move: its ordinary moves, then its dramatic ones;
    /// none for a word that isn't a mood.
    public static func neighbours(of mood: String) -> [String] { moves[mood]?.all ?? [] }

    /// Whether `from` can move to `to` in one step. Staying isn't a move.
    public static func isMove(from: String, to: String) -> Bool { neighbours(of: from).contains(to) }

    /// Whether moving from `from` to `to` is one of its dramatic moves.
    public static func isDramatic(from: String, to: String) -> Bool { moves[from]?.dramatic.contains(to) ?? false }
}
