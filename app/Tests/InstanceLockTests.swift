import Foundation
import XCTest
@testable import BoopCore

/// One Boop per desk. `NSRunningApplication` only sees bundled apps, so the
/// installed app and a bare `swift run` debug binary could run side by side —
/// both writing BLE heartbeats to the same device, where the idle instance's
/// empty keepalives read as "desktop gone" and the pet flickers asleep every
/// 10 seconds with a prompt on screen. The flock is the arbiter every build
/// flavor can see; these tests pin its claim/lose/handoff contract.
///
/// flock contention is per open-file-description, not per process, so two
/// InstanceLock values in one test process genuinely contend.
final class InstanceLockTests: XCTestCase {

    private func tempLockPath() -> String {
        "/tmp/boop-instance-test-\(getpid())-\(UUID().uuidString).lock"
    }

    func testSecondClaimOnSamePathLoses() {
        let path = tempLockPath()
        defer { unlink(path) }
        let first = InstanceLock(path: path)
        let second = InstanceLock(path: path)
        XCTAssertTrue(first.tryClaim())
        XCTAssertFalse(second.tryClaim())
        first.release()
    }

    func testClaimIsIdempotentForTheHolder() {
        let path = tempLockPath()
        defer { unlink(path) }
        let lock = InstanceLock(path: path)
        XCTAssertTrue(lock.tryClaim())
        XCTAssertTrue(lock.tryClaim())
        lock.release()
    }

    func testReleaseHandsTheClaimToTheNextComer() {
        let path = tempLockPath()
        defer { unlink(path) }
        let first = InstanceLock(path: path)
        let second = InstanceLock(path: path)
        XCTAssertTrue(first.tryClaim())
        first.release()
        XCTAssertTrue(second.tryClaim())
        second.release()
    }

    func testDistinctPathsDoNotContend() {
        let a = InstanceLock(path: tempLockPath())
        let b = InstanceLock(path: tempLockPath())
        defer {
            unlink(a.path)
            unlink(b.path)
        }
        XCTAssertTrue(a.tryClaim())
        XCTAssertTrue(b.tryClaim())
        a.release()
        b.release()
    }
}
