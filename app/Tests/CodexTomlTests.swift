import Foundation
import XCTest
@testable import BoopCore

/// Editing someone else's config file is the most destructive thing Boop does,
/// so the rules are: never write a file Codex can't parse, and never remove
/// something we didn't add.
///
/// The old detector demanded the exact text `codex_hooks = true`. Any other
/// spelling read as "not enabled", so we appended a SECOND copy of the key to
/// the same table — a duplicate key, which is invalid TOML, so Codex stopped
/// loading its config entirely. Verify then called it repairable and every
/// launch re-applied the same breakage.
final class CodexTomlTests: XCTestCase {

    private func isEnabled(_ toml: String) -> Bool {
        // Mirror the installer's own check via the public helpers it uses.
        var inFeatures = false
        for raw in toml.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inFeatures = (line == "[features]")
                continue
            }
            guard inFeatures, let (k, v) = HookInstaller.tomlKeyValue(line) else { continue }
            if k == "codex_hooks" && v == "true" { return true }
        }
        return false
    }

    /// Every spelling of "already on" must be recognised, or we duplicate it.
    func testTolerantDetectionOfExistingKey() {
        XCTAssertTrue(isEnabled("[features]\ncodex_hooks = true\n"))
        XCTAssertTrue(isEnabled("[features]\ncodex_hooks=true\n"))
        XCTAssertTrue(isEnabled("[features]\n  codex_hooks   =   true  \n"))
        XCTAssertTrue(isEnabled("[features]\ncodex_hooks = true # keep this\n"))
    }

    func testKeyOutsideFeaturesDoesNotCount() {
        XCTAssertFalse(isEnabled("[other]\ncodex_hooks = true\n"))
        XCTAssertFalse(isEnabled("# codex_hooks = true\n[features]\n"))
    }

    /// The header with no trailing newline used to yield
    /// `[features]codex_hooks = true` on a single line.
    func testHeaderWithoutTrailingNewlineStaysValid() {
        let out = HookInstaller.enablingCodexHooks(in: "[features]")
        XCTAssertEqual(out, "[features]\ncodex_hooks = true")
        XCTAssertTrue(isEnabled(out))
        XCTAssertFalse(out.contains("[features]codex_hooks"))
    }

    /// A comment merely mentioning the table used to hijack the insert point,
    /// putting the key in whatever table came before it.
    func testCommentMentioningFeaturesDoesNotHijackTheInsertPoint() {
        let toml = """
        # put it under [features]
        [model]
        name = "gpt"

        [features]
        other = true
        """
        let out = HookInstaller.enablingCodexHooks(in: toml)
        XCTAssertTrue(isEnabled(out), "key did not land under [features]")
        // It must not have landed in [model].
        let modelSection = out.components(separatedBy: "[features]")[0]
        XCTAssertFalse(modelSection.contains("codex_hooks"))
    }

    func testAddsFeaturesTableWhenAbsent() {
        let out = HookInstaller.enablingCodexHooks(in: "[model]\nname = \"gpt\"\n")
        XCTAssertTrue(isEnabled(out))
        XCTAssertTrue(out.contains("[model]"), "existing config was clobbered")
    }

    func testEnablingAnEmptyFileProducesValidToml() {
        let out = HookInstaller.enablingCodexHooks(in: "")
        XCTAssertEqual(out, "[features]\ncodex_hooks = true\n")
    }

    /// Enabling twice must not produce a duplicate key — this is the exact
    /// loop that left Codex permanently unable to read its config.
    func testEnablingIsIdempotentAcrossSpellings() {
        for start in ["[features]\ncodex_hooks = true\n",
                      "[features]\ncodex_hooks=true\n",
                      "[features]\ncodex_hooks = true # note\n"] {
            XCTAssertTrue(isEnabled(start), "should already read as enabled: \(start)")
            let out = HookInstaller.enablingCodexHooks(in: start)
            let occurrences = out.components(separatedBy: "codex_hooks").count - 1
            XCTAssertEqual(occurrences, 1, "enabling an already-enabled config duplicated the key")
        }
    }

    // MARK: Removal

    func testRemovalTakesOnlyOurKey() {
        let toml = "[features]\ncodex_hooks = true\nother = true\n"
        let out = HookInstaller.removingCodexHooks(from: toml)
        XCTAssertFalse(isEnabled(out))
        XCTAssertTrue(out.contains("other = true"), "removed an unrelated key")
        XCTAssertTrue(out.contains("[features]"), "removed the user's table")
    }

    func testRemovalLeavesAnIdenticallyNamedKeyInAnotherTable() {
        let toml = "[other]\ncodex_hooks = true\n\n[features]\ncodex_hooks = true\n"
        let out = HookInstaller.removingCodexHooks(from: toml)
        XCTAssertTrue(out.contains("[other]\ncodex_hooks = true"))
        XCTAssertFalse(isEnabled(out))
    }

    // MARK: MCP registration (System E)

    func testAddingBoopMCPWritesTableAndHeaders() {
        let out = HookInstaller.addingBoopMCP(to: "", url: "http://127.0.0.1:21321/mcp", token: "tok123")
        XCTAssertTrue(out.contains("[mcp_servers.boop]"))
        XCTAssertTrue(out.contains("url = \"http://127.0.0.1:21321/mcp\""))
        XCTAssertTrue(out.contains("[mcp_servers.boop.http_headers]"))
        XCTAssertTrue(out.contains("X-Boop-Token = \"tok123\""))
        XCTAssertTrue(out.contains("X-Boop-Agent = \"codex\""))
    }

    func testAddingBoopMCPPreservesExistingConfig() {
        let toml = "[features]\ncodex_hooks = true\n\n[mcp_servers.other]\ncommand = \"x\"\n"
        let out = HookInstaller.addingBoopMCP(to: toml, url: "http://127.0.0.1:21321/mcp", token: "t")
        XCTAssertTrue(out.contains("[features]\ncodex_hooks = true"))
        XCTAssertTrue(out.contains("[mcp_servers.other]\ncommand = \"x\""))
        XCTAssertTrue(out.contains("[mcp_servers.boop]"))
    }

    /// A duplicate table is invalid TOML and stops Codex loading its config —
    /// the exact failure mode the codex_hooks detector fixed. Re-adding after
    /// a token rotation must REPLACE the managed table.
    func testReAddingReplacesRatherThanDuplicates() {
        let first = HookInstaller.addingBoopMCP(to: "", url: "http://127.0.0.1:21321/mcp", token: "old")
        let second = HookInstaller.addingBoopMCP(to: first, url: "http://127.0.0.1:21321/mcp", token: "new")
        XCTAssertEqual(second.components(separatedBy: "[mcp_servers.boop]").count, 2, "duplicate managed table")
        XCTAssertTrue(second.contains("X-Boop-Token = \"new\""))
        XCTAssertFalse(second.contains("X-Boop-Token = \"old\""))
    }

    func testRemovingBoopMCPTakesOnlyOurTables() {
        let toml = "[mcp_servers.other]\ncommand = \"x\"\n\n"
            + HookInstaller.addingBoopMCP(to: "", url: "http://127.0.0.1:21321/mcp", token: "t")
            + "\n[features]\ncodex_hooks = true\n"
        let out = HookInstaller.removingBoopMCP(from: toml)
        XCTAssertFalse(out.contains("[mcp_servers.boop]"))
        XCTAssertFalse(out.contains("X-Boop-Token"))
        XCTAssertTrue(out.contains("[mcp_servers.other]"), "removed an unrelated MCP server")
        XCTAssertTrue(out.contains("command = \"x\""))
        XCTAssertTrue(out.contains("codex_hooks = true"), "removed an unrelated table's key")
    }

    func testRemovingBoopMCPWhenAbsentIsIdentity() {
        let toml = "[mcp_servers.other]\ncommand = \"x\"\n"
        XCTAssertEqual(HookInstaller.removingBoopMCP(from: toml), toml)
    }
}
