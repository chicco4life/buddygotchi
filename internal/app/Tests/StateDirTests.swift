import Foundation
import XCTest
@testable import BoopKit

/// ADAPTERS.md §5: only the everyday Boop, on its own folder, installs or
/// repairs hooks, since they report to its socket.
final class StateDirTests: XCTestCase {
    func testOnlyTheEverydayFolderOwnsTheHooks() throws {
        let home = tempDir("home")
        defer { try? FileManager.default.removeItem(at: home) }
        let everyday = AppSettings.defaultStateDir(home: home.path)
        try FileManager.default.createDirectory(at: everyday, withIntermediateDirectories: true)
        XCTAssertTrue(AppSettings.isEveryday(everyday, home: home.path))
        XCTAssertTrue(AppSettings.isEveryday(URL(fileURLWithPath: everyday.path + "/../Boop/"), home: home.path))
        let link = home.appendingPathComponent("boop-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: everyday)
        XCTAssertTrue(AppSettings.isEveryday(link, home: home.path), "a symlink to it is the same folder")
        XCTAssertFalse(AppSettings.isEveryday(home.appendingPathComponent("debug-state"), home: home.path))
    }
}
