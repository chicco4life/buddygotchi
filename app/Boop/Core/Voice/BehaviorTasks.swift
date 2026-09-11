import Foundation

/// One display worker, latest scope and latest remark. No per-feature model lane.
@MainActor
final class BehaviorTasks {
    private struct Job {
        var revision: Int
        var ready: UInt64
        var produce: @MainActor () async -> String?
        var deliver: @MainActor (String) -> Void
    }
    private var pending: [VoiceLineKind: Job] = [:]
    private var revisions: [VoiceLineKind: Int] = [:]
    private var worker: Task<Void, Never>?
    private let debounceNs: UInt64
    init(debounceMs: UInt64 = 2000) { debounceNs = debounceMs * 1_000_000 }

    func cancel(_ kind: VoiceLineKind) {
        revisions[kind, default: 0] += 1
        pending[kind] = nil
    }
    func cancelAll() { cancel(.bubble); cancel(.scope) }

    func replace(_ kind: VoiceLineKind,
                 produce: @escaping @MainActor () async -> String?,
                 deliver: @escaping @MainActor (String) -> Void) {
        cancel(kind)
        pending[kind] = Job(revision: revisions[kind, default: 0],
                            ready: DispatchTime.now().uptimeNanoseconds + (kind == .scope ? debounceNs : 0),
                            produce: produce, deliver: deliver)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !self.pending.isEmpty {
                let kind: VoiceLineKind = self.pending[.bubble] != nil ? .bubble : .scope
                guard let job = self.pending[kind] else { continue }
                let now = DispatchTime.now().uptimeNanoseconds
                if job.ready > now {
                    // Short slices let a new remark preempt a debouncing scope.
                    try? await Task.sleep(nanoseconds: min(job.ready - now, 50_000_000))
                    continue
                }
                self.pending[kind] = nil
                let text = await job.produce()
                if let text, self.revisions[kind] == job.revision { job.deliver(text) }
            }
            self.worker = nil
        }
    }
    func finish() async { await worker?.value }
}
