import XCTest
@testable import TideEnglishCore

final class ConversationActivityTests: XCTestCase {
    func testOneCheckInAndExactDeadlineDespiteItsAudio() {
        var activity = ConversationActivity(now: 100)
        XCTAssertEqual(activity.tick(now: 114.9), .wait)
        XCTAssertEqual(activity.tick(now: 115), .checkIn)
        activity.assistantActive(now: 120)
        XCTAssertEqual(activity.tick(now: 124), .wait)
        XCTAssertEqual(activity.tick(now: 125), .warning(5))
        XCTAssertEqual(activity.tick(now: 129.1), .warning(1))
        XCTAssertEqual(activity.tick(now: 130), .end)
    }
    func testGenuineAnswerRestartsQuietWindowAndAllowsLaterCheckIn() {
        var activity = ConversationActivity(now: 0)
        XCTAssertEqual(activity.tick(now: 15), .checkIn)
        activity.learnerEngaged(now: 29)
        activity.assistantActive(now: 33)
        XCTAssertEqual(activity.tick(now: 47), .wait)
        XCTAssertEqual(activity.tick(now: 48), .checkIn)
        XCTAssertEqual(activity.tick(now: 63), .end)
    }
    func testMicrophoneNoiseAndAssistantMonologueCannotKeepSessionOpen() {
        var noisy = ConversationActivity(now: 0)
        for second in 0..<45 { noisy.inputActive(now: Double(second)); XCTAssertNotEqual(noisy.tick(now: Double(second)), .end) }
        noisy.inputActive(now: 45)
        XCTAssertEqual(noisy.tick(now: 45), .end)
        var monologue = ConversationActivity(now: 0)
        for second in 0...90 { monologue.assistantActive(now: Double(second)) }
        XCTAssertEqual(monologue.tick(now: 90), .end)
    }
    func testMutedInputDoesNotPreventCloseOrTriggerCheckIn() {
        var activity = ConversationActivity(now: 0)
        activity.inputActive(now: 15)
        XCTAssertEqual(activity.tick(now: 15, muted: true), .wait)
        activity.inputActive(now: 30)
        XCTAssertEqual(activity.tick(now: 30, muted: true), .end)
    }
    func testTypingAndPendingResponseGraceAreBounded() {
        var typing = ConversationActivity(now: 0)
        typing.typing(now: 20)
        XCTAssertEqual(typing.tick(now: 25), .wait)
        for second in 26...79 { typing.typing(now: Double(second)); XCTAssertNotEqual(typing.tick(now: Double(second)), .end) }
        typing.typing(now: 80)
        XCTAssertEqual(typing.tick(now: 80), .end)
        var pending = ConversationActivity(now: 0)
        XCTAssertEqual(pending.tick(now: 10, busy: true), .wait)
        XCTAssertEqual(pending.tick(now: 50, busy: true), .warning(5))
        XCTAssertEqual(pending.tick(now: 55, busy: true), .end)
    }
    func testAbandonedDraftAndFinishedHelperDoNotCountAsReplies() {
        var draft = ConversationActivity(now: 0)
        draft.typing(now: 20)
        XCTAssertEqual(draft.tick(now: 30), .end)
        var helper = ConversationActivity(now: 0)
        XCTAssertEqual(helper.tick(now: 10, busy: true), .wait)
        XCTAssertEqual(helper.tick(now: 30, busy: false), .end)
        XCTAssertEqual(ConversationActivity.quietSeconds, 30)
    }
}
