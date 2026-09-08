import Foundation

/// A kernel flock claim that makes "one Boop per desk" hold across build
/// flavors. `NSRunningApplication` can only see bundled apps, so the
/// installed app and a bare `swift run` debug binary would otherwise run
/// side by side — and macOS multiplexes both onto the same BLE link, where
/// the idle instance's empty keepalives fight the real one's heartbeats
/// (on glass: the pet flickers asleep every 10s while a prompt is pending).
///
/// The kernel releases the lock when the holder exits, however it exits,
/// so a crash never strands a stale lock.
final class InstanceLock {
    let path: String
    private var fd: Int32 = -1

    /// Per-user and outside any per-app container, so every build flavor
    /// resolves the same file.
    init(path: String = "/tmp/boop-instance-\(getuid()).lock") {
        self.path = path
    }

    /// True if this process now holds (or already held) the claim.
    func tryClaim() -> Bool {
        if fd >= 0 { return true }
        let opened = open(path, O_CREAT | O_RDWR, 0o600)
        // Fail open: an unwritable /tmp shouldn't brick the app over a
        // guard that exists for a dev-workflow edge case.
        guard opened >= 0 else { return true }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            return false
        }
        fd = opened
        return true
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit {
        release()
    }
}
