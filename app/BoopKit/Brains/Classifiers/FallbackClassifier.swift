import Foundation

/// A model classifier with an if-else table behind it (Stage 1, HARNESS.md
/// §6): normal mode's Jev, with the normal table. The model gets half the
/// input's deadline, which leaves the other half for the writer. When it
/// fails, refuses or hasn't answered by then, the table decides that pass,
/// so a failed turn or "be quiet" never goes unanswered because the model
/// is down, slow or has a bad key. The evidence says which one decided, and
/// the log why the model didn't: only its error, which for Jev is the HTTP
/// status. An answer the model gave that couldn't be used goes only to the
/// debug log, as the classification's `raw`.
public struct FallbackClassifier: Classifier {
    let model: any Classifier
    let table: any Classifier
    let log: @Sendable (String) -> Void

    /// The model's id: the table only stands in for it.
    public var id: String { model.id }

    public init(_ model: any Classifier, else table: any Classifier, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.model = model
        self.table = table
        self.log = log
    }

    /// The model's share of the input's deadline.
    static func modelMs(_ deadline: Duration) -> Int {
        deadline.ms / 2
    }

    public func classify(_ context: Context, _ menu: Menu, deadline: Duration) async throws -> Classification {
        let ms = FallbackClassifier.modelMs(deadline)
        let (model, table) = (self.model, self.table)
        let answer = await Harness.race(ms) { try await model.classify(context, menu, deadline: .milliseconds(ms)) }
        switch answer {
        case .success(let classification):
            return classification
        case .failure(let error):
            // You talking cancelled the pass: nothing more to decide.
            try Task.checkCancellation()
            log("brain: \(model.id) failed (\(error.description)); \(table.id) decided")
            let decided = try await table.classify(context, menu, deadline: deadline)
            let rule = decided.evidence.map { ": \($0)" } ?? ""
            return Classification(calls: decided.calls, evidence: "\(model.id) failed (\(error.description)) · \(table.id)\(rule)",
                                  raw: error.raw)
        }
    }
}
