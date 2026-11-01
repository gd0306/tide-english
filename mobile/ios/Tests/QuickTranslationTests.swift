import XCTest
@testable import TideEnglishCore

@MainActor final class QuickTranslationTests: XCTestCase {
    private func request(_ text: String, target: String = "Chinese (Simplified)") -> QuickTranslationRequest {
        QuickTranslationRequest(text: text, sourceLanguage: "English", targetLanguage: target)
    }

    func testRejectsBlankOversizedAndUnsupportedRequests() async throws {
        var calls = 0
        let controller = QuickTranslationController(delay: .zero) { _ in calls += 1; return "unexpected" }
        for value in [request(" \n"), request(String(repeating: "😀", count: 1001)), request("Hi", target: "invented")] {
            controller.update(value)
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(controller.isLoading)
    }

    func testDebouncesTypingAndPreservesTheInput() async throws {
        var inputs: [String] = []
        let controller = QuickTranslationController(delay: .milliseconds(30)) { value in
            inputs.append(value.text); return "  你好！ \n"
        }
        controller.update(request("H"))
        controller.update(request("  Hello!\n"))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(inputs, ["  Hello!\n"])
        XCTAssertEqual(controller.text, "你好！")
        XCTAssertFalse(controller.isLoading)
    }

    func testChangedLanguageDiscardsALateUncancellableResult() async throws {
        var finish: CheckedContinuation<String, Never>?
        let controller = QuickTranslationController(delay: .zero) { value in
            if value.targetLanguage == "Chinese (Simplified)" {
                return await withCheckedContinuation { finish = $0 }
            }
            return "Bonjour"
        }
        controller.update(request("Hello"))
        try await Task.sleep(for: .milliseconds(10))
        controller.update(request("Hello", target: "French"))
        try await Task.sleep(for: .milliseconds(10))
        finish?.resume(returning: "你好")
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(controller.text, "Bonjour")
        controller.reset()
        XCTAssertEqual(controller.text, "")
    }

    func testEmptyResponseOffersManualRetry() async throws {
        var calls = 0
        let controller = QuickTranslationController(delay: .zero) { _ in
            calls += 1; return calls == 1 ? " \n" : "你好"
        }
        controller.update(request("Hello"))
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertNotNil(controller.error)
        XCTAssertEqual(controller.text, "")
        controller.update(request("Hello"), immediately: true)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.text, "你好")
    }

    func testResetPreventsPendingInputFromBeingSent() async throws {
        var calls = 0
        let controller = QuickTranslationController(delay: .milliseconds(20)) { _ in calls += 1; return "你好" }
        controller.update(request("Hello")); controller.reset()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(controller.isLoading)
    }

    func testManualTranslationBypassesTypingDelay() async throws {
        var calls = 0
        let controller = QuickTranslationController(delay: .seconds(10)) { _ in calls += 1; return "你好" }
        controller.update(request("Hello"))
        XCTAssertFalse(controller.isLoading, "Manual translation must remain available during the typing delay")
        controller.update(request("Hello"), immediately: true)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(controller.text, "你好")
    }
}
