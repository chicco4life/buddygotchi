import Foundation

/// A replacement cancels only its own lane. Revision checks also reject a
/// late result from an operation that does not cooperate with cancellation.
@MainActor
final class TransientVoiceTasks {
    private var tasks: [VoiceLineKind: Task<Void, Never>] = [:]
    private var revisions: [VoiceLineKind: Int] = [:]

    func cancel(_ kind: VoiceLineKind) {
        revisions[kind, default: 0] += 1
        tasks[kind]?.cancel()
    }

    func cancelAll() {
        cancel(.bubble)
    }

    func replace(_ kind: VoiceLineKind,
                 produce: @escaping @MainActor () async -> String?,
                 deliver: @escaping @MainActor (String) -> Void) {
        cancel(kind)
        let revision = revisions[kind]
        tasks[kind] = Task { [weak self] in
            guard let text = await produce(), !text.isEmpty,
                  !Task.isCancelled, let self, self.revisions[kind] == revision else { return }
            deliver(text)
        }
    }

    func finish() async {
        await tasks[.bubble]?.value
    }
}
