import HookWire
import XCTest
@testable import BoopKit

/// BEHAVIORS.md §3.2: where a thread opens on the Mac.
final class ThreadLinkTests: XCTestCase {
    func target(_ agent: String, _ session: String = "s1", app: String? = nil,
                appSession: String? = nil) -> ThreadLink.Target? {
        ThreadLink.target(ThreadRef(agent: agent, session: session, app: app, appSession: appSession))
    }

    func testClaudeOpensInTheClaudeAppByItsOwnID() {
        XCTAssertEqual(target("claude", app: HostApp.claude, appSession: "local_7db526ef-3ac2"),
                       .url("claude://code/continue?session=local_7db526ef-3ac2"))
        XCTAssertEqual(target("claude", app: HostApp.claude), .app(HostApp.claude), "no ID: the app, forward")
        XCTAssertEqual(target("claude", app: HostApp.claude, appSession: "local_x&q=1"), .app(HostApp.claude),
                       "an ID that isn't one isn't put in a link")
    }

    func testCodexOpensInTheCodexAppByItsThreadID() {
        XCTAssertEqual(target("codex", "01a0e6fd-587d-74a2", app: HostApp.codex), .url("codex://threads/01a0e6fd-587d-74a2"))
        XCTAssertEqual(target("codex", "01a0e6fd"), .url("codex://threads/01a0e6fd"), "no app named: Codex's own")
        XCTAssertEqual(target("codex", "a/b"), .url("codex://threads/a%2Fb"))
    }

    func testATerminalIsBroughtForward() {
        XCTAssertEqual(target("claude", app: "com.mitchellh.ghostty"), .app("com.mitchellh.ghostty"))
        XCTAssertEqual(target("codex", app: "com.googlecode.iterm2"), .app("com.googlecode.iterm2"))
        XCTAssertEqual(ThreadLink.Target.app("com.mitchellh.ghostty").arguments, ["-b", "com.mitchellh.ghostty"])
        XCTAssertNil(target("claude"), "nothing says where it runs")
    }
}
