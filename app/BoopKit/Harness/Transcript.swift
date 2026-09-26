import Foundation

/// The brain's transcript (HARNESS.md §4): one append-only list of what
/// happened, shared by both stages. Each pass appends its input, the rules'
/// reaction, what Stage 1 decided, what Stage 2 wrote and what ran; taps and
/// "needs you" are noted as asides. Nothing in it is ever changed.
///
/// Brains see a window onto it: at most `windowInputs` inputs. When one more
/// arrives, the window starts again from the last `keptInputs`, so Boop
/// still knows what was just said. That is the only rule: nothing is
/// summarized, and the window just moves its start. Asides don't move it, so
/// at most `asidesPerInput` follow one input and later ones aren't noted: a
/// burst of taps can't crowd out the prompt. Kept in memory only, and
/// touched only on the harness's queue.
public final class Transcript: @unchecked Sendable {
    public enum Entry: Equatable, Sendable {
        /// An input reached the pipeline.
        case input(Input)
        /// The rules' instant reaction to that input, e.g. `cheer`.
        case rules(String)
        /// Something only the rules handled, e.g. `tapped · 14:07 Tuesday: Boop wiggled`.
        case aside(String, ts: Int64)
        /// Stage 1's calls, and how it got there.
        case decided(by: String, [ToolCall], evidence: String?)
        /// The pass produced nothing: Stage 1 failed, was late or cancelled,
        /// or answered off the menu.
        case dropped(String)
        /// Stage 2's values by slot key; an empty value was left empty.
        case wrote(by: String, [String: String])
        /// Stage 2 failed or was late; every slot was left empty.
        case writeFailed(by: String, String)
        /// A call went to its action.
        case ran(ToolCall, ActionOutcome)
    }

    public static let windowInputs = 8
    public static let keptInputs = 2
    public static let asidesPerInput = 8
    /// Entries before the window are never read again; past this many they're let go.
    static let behindLimit = 1000

    public private(set) var entries: [Entry] = []
    public private(set) var windowStart = 0
    /// How many times the window started again, for L5.
    public private(set) var restarts = 0

    public init() {}

    /// The entries brains see, oldest first.
    public var window: [Entry] { Array(entries[windowStart...]) }

    /// How many inputs the window holds.
    public var inputs: Int { window.filter { if case .input = $0 { true } else { false } }.count }

    /// A pass starts: moves the window first when it's full, then appends
    /// the input and the rules' reaction.
    func begin(_ input: Input) {
        let starts = entries.indices.filter { i in
            if i >= windowStart, case .input = entries[i] { return true }
            return false
        }
        if starts.count >= Transcript.windowInputs {
            restarts += 1
            windowStart = starts[starts.count - Transcript.keptInputs]
        }
        append(.input(input))
        if let rules = input.rules { append(.rules(rules)) }
        if windowStart > Transcript.behindLimit {
            entries.removeFirst(windowStart)
            windowStart = 0
        }
    }

    func append(_ entry: Entry) {
        entries.append(entry)
    }

    /// An aside, unless `asidesPerInput` already follow the last input.
    /// Returns whether it was noted.
    @discardableResult
    func note(_ aside: String, at ts: Int64) -> Bool {
        var since = 0
        for entry in entries.reversed() {
            if case .input = entry { break }
            if case .aside = entry { since += 1 }
        }
        guard since < Transcript.asidesPerInput else { return false }
        append(.aside(aside, ts: ts))
        return true
    }

    // MARK: As text

    /// Text on one line, with double quotes made single, to quote in a prompt.
    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "'")
    }

    // MARK: Grouped

    /// One input and what followed it, or an aside, for brains that read
    /// structure rather than text (Jev).
    public struct Group: Equatable, Sendable {
        public var ts: Int64
        public var happened: String
        public var words: String?
        public var rules: String?
        /// Calls that ran, nil for an aside.
        public var did: [ToolCall]?
    }

    public static func groups(_ window: [Entry]) -> [Group] {
        var groups: [Group] = []
        for entry in window {
            switch entry {
            case .input(let input):
                groups.append(Group(ts: input.ts, happened: input.line, words: input.words, rules: input.rules, did: []))
            case .aside(let what, let ts):
                groups.append(Group(ts: ts, happened: what, did: nil))
            case .ran(let call, let outcome):
                if outcome.isDone, let last = groups.indices.last(where: { groups[$0].did != nil }) {
                    groups[last].did?.append(call)
                }
            case .rules, .decided, .dropped, .wrote, .writeFailed:
                continue
            }
        }
        return groups
    }
}
