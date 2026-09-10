import Foundation

/// Which sound a state change should make, if any.
enum Chirp: String, Sendable, Equatable {
    case complete
    case attention
    case error
}

/// Decides what to play from a pair of states. Pure on purpose: `DesktopOutput`
/// needs an `NSStatusItem` to exist, which makes it painful to test, and the
/// interesting part here is the edge detection rather than the playback.
enum ChirpDecision {
    /// Completion sounds use the same minimum duration as visual celebrations.
    static let minCompletionDurationMs = PetTuning.celebrationMinMs

    static func chirp(prev: BuddyState, next: BuddyState, soundsEnabled: Bool) -> Chirp? {
        guard soundsEnabled else { return nil }

        // Attention and completion edge on counts, not on pet state: a second
        // agent asking while the pet is already in .attention, or one agent
        // finishing while another works on, produce no pet-state change at all
        // and would otherwise be silent.
        //
        // Deliberately the waiting *count* rather than `prompt.id`: the
        // projection only carries the front-of-queue prompt, so resolving the
        // first of two approvals changes the id without anything new having
        // arrived. The count only rises when an agent actually joins the queue.
        if next.sessions.waiting > prev.sessions.waiting {
            return .attention
        }

        if let completedAt = next.lastCompletionAt, completedAt != prev.lastCompletionAt {
            let duration = next.lastTaskDurationMs ?? 0
            return duration >= minCompletionDurationMs ? .complete : nil
        }

        // Errors have no equivalent identity on BuddyState, and a run of
        // failures inside one errored session is one problem, not several.
        if next.pet.state == .error && prev.pet.state != .error {
            return .error
        }

        return nil
    }
}
