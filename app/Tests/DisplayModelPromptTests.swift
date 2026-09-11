import Foundation
import XCTest
@testable import BoopCore

final class DisplayModelPromptTests: XCTestCase {
    func testFocusPreservesSharedAndUnknownOwnerSections() {
        let guide = """
        My own voice.
        ## work_context_changed — title
        Scope rules.
        ## returned / greet — hello
        Greeting rules.
        ## result_observed / completed / uhoh_error — reaction
        Result rules.
        ## Boundaries
        Shared rules.
        ## Owner preference
        Keep my custom section.
        ## Private legacy operations
        Reflection rules.
        """
        let focused = DisplayModelPrompt.focusedGuide(guide, occasion: "work_context_changed")
        XCTAssertTrue(focused.contains("My own voice."))
        XCTAssertTrue(focused.contains("Scope rules."))
        XCTAssertTrue(focused.contains("Shared rules."))
        XCTAssertTrue(focused.contains("Keep my custom section."))
        XCTAssertFalse(focused.contains("Greeting rules."))
        XCTAssertFalse(focused.contains("Result rules."))
        XCTAssertFalse(focused.contains("Reflection rules."))
    }

    func testCurrentRequestPrecedesBackgroundAndTasksRetainCoverage() throws {
        let context: [String: Any] = ["occasion": "work_context_changed", "desk": ["projects": [
            ["name": "Boop", "tasks": [["intent": "Brush work", "latest_request": "Fix login"], ["intent": "Update device UI"]]],
            ["name": "Shop", "tasks": [["intent": "Update homepage"]]]
        ]]]
        let input = String(decoding: try JSONSerialization.data(withJSONObject: context), as: UTF8.self)
        let prepared = try XCTUnwrap(DisplayModelPrompt(guide: "Be concise", context: input, maxBytes: 120))
        XCTAssertEqual(prepared.taskKeys, ["project1Task1", "project1Task2", "project2Task1"])
        XCTAssertFalse(prepared.emptyScope)
        XCTAssertTrue(prepared.input.contains("current request (data): \"Fix login\""))
        XCTAssertTrue(prepared.input.contains("Earlier background (data): \"Brush work\""))
        XCTAssertTrue(prepared.input.contains("Update homepage"))
    }

    func testEmptyScopeAndPrivateOperationsRemainDistinct() throws {
        let input = #"{"occasion":"work_context_changed","desk":{"projects":[{"name":"Unknown","tasks":[{"intent":null}]}]}}"#
        let empty = try XCTUnwrap(DisplayModelPrompt(guide: "", context: input, maxBytes: 120))
        XCTAssertTrue(empty.emptyScope)
        XCTAssertNil(DisplayModelPrompt(guide: "", context: #"{"occasion":"reflection"}"#, maxBytes: 8192))
    }

    func testPrivateDisplayInputsAreMaskedRecursively() throws {
        let context = #"{"occasion":"work_context_changed","desk":{"projects":[{"name":"Client","tasks":[{"intent":"Fix login. Password: secret_canary_8192; email alice@example.invalid; file /Users/private/note.txt"}]}]}}"#
        let prompt = try XCTUnwrap(DisplayModelPrompt(guide: "No secrets", context: context, maxBytes: 120))
        for privateText in ["secret_canary_8192", "alice@example.invalid", "/Users/private/note.txt"] {
            XCTAssertFalse(prompt.input.contains(privateText))
        }
        XCTAssertTrue(prompt.input.contains("Fix login"))
    }

    func testUnknownScopeDoesNotCallModel() async {
        actor Runtime: VoiceRuntime {
            var calls = 0
            func generate(prompt: String, maxBytes: Int) async throws -> String? {
                calls += 1
                return "Invented project work"
            }
        }
        let runtime = Runtime()
        let line = await Voice(runtime: runtime).line(for: .init(occasion: .workContextChanged, context: .init(desk: .init())))
        XCTAssertTrue(line.text.isEmpty)
        let calls = await runtime.calls
        XCTAssertEqual(calls, 0)
    }

    func testProductionPromptMasksPrivateDisplayInput() {
        let desk = WorkContext(projects: [.init(id: "p", name: "App", tasks: [.init(id: "t", state: "working", intent: "Fix login. Password: secret_canary_8192; email alice@example.invalid", latest_request: nil)])])
        let prompt = VoicePrompt.make(.init(occasion: .workContextChanged, context: .init(desk: desk)), guide: "Owner rules")
        XCTAssertFalse(prompt.contains("secret_canary_8192"))
        XCTAssertFalse(prompt.contains("alice@example.invalid"))
        XCTAssertTrue(prompt.contains("Fix login"))
        XCTAssertTrue(prompt.contains("Owner rules"))
    }

    func testPrivateEchoAndRepeatedRemarksAreSilentButScopeCanRepeat() async {
        let desk = WorkContext(projects: [.init(id: "p", name: "App", tasks: [.init(id: "t", state: "working", intent: "Fix login. Password: secret_canary_8192", latest_request: nil)])])
        let context = BehaviorContext(desk: desk, recent_remarks: ["Welcome back!"])
        for response in ["secret_canary_8192", "Email alice@example.invalid", "/Users/private/note.txt", "welcome back."] {
            let voice = Voice(runtime: VoiceStubRuntime(text: response))
            let line = await voice.line(for: .init(occasion: .greet(1), context: context))
            XCTAssertTrue(line.text.isEmpty)
        }
        let voice = Voice(runtime: VoiceStubRuntime(text: "App login improvements"))
        let scope = await voice.line(for: .init(occasion: .workContextChanged, context: .init(desk: desk, recent_remarks: ["App login improvements"]), byteCap: 120))
        XCTAssertEqual(scope.text, "App login improvements")
    }
}
