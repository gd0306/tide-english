import XCTest
@testable import TideEnglishCore

final class VoiceTurnStateTests: XCTestCase {
    func testSegmentFinalPreservesEarlierWordsAndDoesNotSubmitWholeTurn() {
        var transcript = VoiceSegmentTranscript()
        var turn = VoiceTurnState()
        let generation = turn.begin()
        XCTAssertEqual(transcript.update(text: "I li", startMS: 0, endMS: 1000, isFinal: false), "I li")
        XCTAssertEqual(transcript.update(text: "I like", startMS: 0, endMS: 1000, isFinal: true), "I like")
        XCTAssertTrue(turn.update(transcript.text, generation: generation))
        XCTAssertEqual(transcript.update(text: "coffee", startMS: 1000, endMS: 2000, isFinal: true), "I like coffee")
        XCTAssertTrue(turn.update(transcript.text, generation: generation))
        XCTAssertEqual(transcript.update(text: "coffee", startMS: 1000, endMS: 2000, isFinal: true), "I like coffee")
        XCTAssertFalse(turn.update(transcript.text, generation: generation))
        XCTAssertEqual(turn.commit(generation: generation), "I like coffee")
        XCTAssertNil(turn.commit(generation: generation))
    }

    func testOverlappingVolatileSegmentsAreReplacedRatherThanAppended() {
        var transcript = VoiceSegmentTranscript()
        _ = transcript.update(text: "I", startMS: 0, endMS: 300, isFinal: false)
        _ = transcript.update(text: "lick", startMS: 300, endMS: 900, isFinal: false)
        _ = transcript.update(text: "coffee", startMS: 1000, endMS: 2000, isFinal: false)
        XCTAssertEqual(transcript.update(text: "I like", startMS: 0, endMS: 1000, isFinal: true), "I like coffee")
        XCTAssertEqual(transcript.update(text: "tea", startMS: 1100, endMS: 1900, isFinal: true), "I like tea")
    }

    func testLateVolatileResultCannotReplaceFinalWords() {
        var transcript = VoiceSegmentTranscript()
        _ = transcript.update(text: "I like", startMS: 0, endMS: 1000, isFinal: true)
        XCTAssertEqual(transcript.update(text: "I li", startMS: 0, endMS: 900, isFinal: false), "I like")
        XCTAssertEqual(transcript.update(text: "coffee", startMS: 1000, endMS: 2000, isFinal: false), "I like coffee")
    }

    func testOutOfOrderSegmentsAreChronologicalAndRepeatedWordsRemainDistinct() {
        var transcript = VoiceSegmentTranscript()
        _ = transcript.update(text: "very", startMS: 1000, endMS: 2000, isFinal: true)
        _ = transcript.update(text: "good", startMS: 2000, endMS: 3000, isFinal: true)
        XCTAssertEqual(transcript.update(text: "very", startMS: 0, endMS: 1000, isFinal: true), "very very good")
        XCTAssertEqual(transcript.update(text: "very", startMS: 1000, endMS: 2000, isFinal: true), "very very good")
    }

    func testEmptyOrInvalidSegmentsLeaveTranscriptIntactAndNewGenerationStartsEmpty() {
        var transcript = VoiceSegmentTranscript()
        XCTAssertEqual(transcript.update(text: "  hello \n", startMS: 0, endMS: 1000, isFinal: true), "hello")
        for invalid in [(" \n ", 1000, 2000), ("negative", -1, 1000), ("zero", 1000, 1000), ("reversed", 2000, 1000)] {
            XCTAssertEqual(transcript.update(text: invalid.0, startMS: invalid.1, endMS: invalid.2, isFinal: true), "hello")
        }
        transcript = VoiceSegmentTranscript()
        XCTAssertEqual(transcript.update(text: "fresh", startMS: 0, endMS: 1000, isFinal: false), "fresh")
    }

    func testTranscriptPreservesChronologicalPrefixWithinCharacterLimit() {
        var transcript = VoiceSegmentTranscript()
        _ = transcript.update(text: "tail", startMS: 1000, endMS: 2000, isFinal: true)
        let oversized = String(repeating: "字", count: 2500)
        let bounded = transcript.update(text: oversized, startMS: 0, endMS: 1000, isFinal: true)
        XCTAssertEqual(bounded.count, 2000)
        XCTAssertEqual(bounded, String(repeating: "字", count: 2000))
        XCTAssertEqual(transcript.update(text: "head", startMS: 0, endMS: 1000, isFinal: true), "head tail")
    }

    func testSegmentFloodRetainsBoundedEarliestEvidenceAndAllowsCorrection() {
        var transcript = VoiceSegmentTranscript()
        for index in 0..<3000 {
            _ = transcript.update(text: "x", startMS: index, endMS: index + 1, isFinal: false)
        }
        XCTAssertEqual(transcript.text.count, 255)
        XCTAssertEqual(transcript.update(text: "first", startMS: 0, endMS: 1, isFinal: true).prefix(8), "first x ")
        XCTAssertEqual(transcript.text.count, 259)
        // A late callback for the earliest evidence still sorts into a saturated transcript.
        var outOfOrder = VoiceSegmentTranscript()
        for index in 1...128 {
            _ = outOfOrder.update(text: "x", startMS: index, endMS: index + 1, isFinal: true)
        }
        XCTAssertEqual(outOfOrder.update(text: "first", startMS: 0, endMS: 1, isFinal: true).prefix(8), "first x ")
        XCTAssertEqual(outOfOrder.text.count, 259)
    }

    @MainActor func testSpeechAuthorizationInitializesCapabilityBeforeItIsChecked() async throws {
        var authorized = false
        var steps: [String] = []
        let ready = try await LocalSpeechPreparation.prepare(
            requestSpeechAuthorization: { steps.append("speech"); authorized = true; return true },
            requestMicrophonePermission: { steps.append("microphone"); return true },
            recognitionAvailable: { steps.append("capability"); return authorized },
            isCurrent: { true })
        XCTAssertTrue(ready)
        XCTAssertEqual(steps, ["speech", "microphone", "capability"])
    }

    @MainActor func testDeniedSpeechDoesNotRequestMicrophoneOrConstructRecognizer() async throws {
        var steps: [String] = []
        let ready = try await LocalSpeechPreparation.prepare(
            requestSpeechAuthorization: { steps.append("speech"); return false },
            requestMicrophonePermission: { steps.append("microphone"); return true },
            recognitionAvailable: { steps.append("capability"); return true },
            isCurrent: { true })
        XCTAssertFalse(ready)
        XCTAssertEqual(steps, ["speech"])
    }

    @MainActor func testDeniedMicrophoneDoesNotStartRecognition() async throws {
        var steps: [String] = []
        let ready = try await LocalSpeechPreparation.prepare(
            requestSpeechAuthorization: { steps.append("speech"); return true },
            requestMicrophonePermission: { steps.append("microphone"); return false },
            recognitionAvailable: { steps.append("capability"); return true },
            isCurrent: { true })
        XCTAssertFalse(ready)
        XCTAssertEqual(steps, ["speech", "microphone"])
    }

    @MainActor func testCancelledConnectionDoesNotContinuePermissionRequests() async throws {
        var current = true
        var steps: [String] = []
        do {
            _ = try await LocalSpeechPreparation.prepare(
                requestSpeechAuthorization: { steps.append("speech"); current = false; return true },
                requestMicrophonePermission: { steps.append("microphone"); return true },
                recognitionAvailable: { steps.append("capability"); return true },
                isCurrent: { current })
            XCTFail("An obsolete connection must stop before requesting another permission")
        } catch is CancellationError {}
        XCTAssertEqual(steps, ["speech"])
    }

    @MainActor func testUnsupportedOfflineRecognitionStillRequestsPermissionAndStaysUnavailable() async throws {
        var steps: [String] = []
        let ready = try await LocalSpeechPreparation.prepare(
            requestSpeechAuthorization: { steps.append("speech"); return true },
            requestMicrophonePermission: { steps.append("microphone"); return true },
            recognitionAvailable: { steps.append("capability"); return false },
            isCurrent: { true })
        XCTAssertFalse(ready)
        XCTAssertEqual(steps, ["speech", "microphone", "capability"])
    }

    func testFinishingOldOutputCannotResumeRecognitionDuringNewRequest() {
        var state = VoiceTurnState()
        state.setOutputActive(true)
        state.setRequestActive(true)
        state.setOutputActive(false)
        XCTAssertFalse(state.canListen)
        let blocked = state.begin()
        XCTAssertFalse(state.update("speech while waiting", generation: blocked))
        state.setRequestActive(false)
        XCTAssertTrue(state.canListen)
    }

    func testCompletedRequestCannotListenUntilNewOutputFinishes() {
        var state = VoiceTurnState()
        state.setRequestActive(true)
        state.setOutputActive(true)
        state.setRequestActive(false)
        XCTAssertFalse(state.canListen)
        state.setOutputActive(false)
        XCTAssertTrue(state.canListen)
    }

    func testAcknowledgingReplyRetainsHelpAndThemeAddedWhileWaiting() {
        var queue = VoicePromptQueue()
        queue.append("Say hello", respond: true)
        let sent = queue.snapshot()
        queue.append("Use simpler words", respond: true)
        queue.append("Discuss coffee", respond: true)
        queue.acknowledge(sent)
        XCTAssertEqual(queue.snapshot().text, "Use simpler words\nDiscuss coffee")
        XCTAssertTrue(queue.needsResponse)
        queue.acknowledge(queue.snapshot())
        XCTAssertFalse(queue.needsResponse)
        XCTAssertEqual(queue.snapshot().text, "")
    }

    func testPassivePaceUpdateRemainsForNextTurnWithoutUnsolicitedReply() {
        var queue = VoicePromptQueue()
        queue.append("Greet", respond: true)
        let sent = queue.snapshot()
        queue.append("Keep the pace gentle", respond: false)
        queue.acknowledge(sent)
        XCTAssertEqual(queue.snapshot().text, "Keep the pace gentle")
        XCTAssertFalse(queue.needsResponse)
        queue.append(String(repeating: "x", count: 7000), respond: true)
        XCTAssertLessThanOrEqual(queue.snapshot().text.count, 5000)
    }

    // Catch duplicate submission when silence and a recognizer's final callback race.
    func testLatestPartialCommitsOnlyOnce() {
        var state = VoiceTurnState()
        let generation = state.begin()
        XCTAssertTrue(state.update("Bon", generation: generation))
        XCTAssertTrue(state.update(" Bonjour ! ", generation: generation))
        XCTAssertEqual(state.commit(generation: generation), "Bonjour !")
        XCTAssertNil(state.commit(generation: generation))
        XCTAssertFalse(state.update("Bonjour !", generation: generation))
    }

    // Catch stale recognizer callbacks being submitted as the next learner turn.
    func testNewTurnRejectsOldCallbacksButAllowsRepeatedUtterance() {
        var state = VoiceTurnState()
        let old = state.begin()
        _ = state.update("你好", generation: old)
        XCTAssertEqual(state.commit(generation: old), "你好")
        let current = state.begin()
        XCTAssertFalse(state.update("stale text", generation: old))
        XCTAssertNil(state.commit(generation: old))
        XCTAssertTrue(state.update("你好", generation: current))
        XCTAssertEqual(state.commit(generation: current), "你好")
    }

    func testMuteCancelsPendingTurnAndCannotBeBypassedByBegin() {
        var state = VoiceTurnState()
        let old = state.begin()
        _ = state.update("private pending speech", generation: old)
        state.setMuted(true)
        XCTAssertNil(state.commit(generation: old))
        let muted = state.begin()
        XCTAssertFalse(state.update("muted speech", generation: muted))
        state.setMuted(false)
        let fresh = state.begin()
        XCTAssertTrue(state.update("Fresh reply", generation: fresh))
        XCTAssertEqual(state.commit(generation: fresh), "Fresh reply")
    }

    func testOutputCannotBecomeLearnerEvidence() {
        var state = VoiceTurnState()
        let listening = state.begin()
        state.setOutputActive(true)
        XCTAssertFalse(state.update("assistant echo", generation: listening))
        let speaking = state.begin()
        XCTAssertFalse(state.update("assistant echo", generation: speaking))
        state.setOutputActive(false)
        let learner = state.begin()
        XCTAssertTrue(state.update("My own words", generation: learner))
        XCTAssertEqual(state.commit(generation: learner), "My own words")
    }

    func testDisconnectInvalidatesPendingTurn() {
        var state = VoiceTurnState()
        let old = state.begin()
        _ = state.update("pending", generation: old)
        state.cancel()
        XCTAssertNil(state.commit(generation: old))
        XCTAssertFalse(state.update("late callback", generation: old))
        let fresh = state.begin()
        XCTAssertTrue(state.update("Reconnected", generation: fresh))
        XCTAssertEqual(state.commit(generation: fresh), "Reconnected")
    }

    func testEmptyUnchangedAndOversizedPartialsAreBounded() {
        var state = VoiceTurnState()
        let empty = state.begin()
        XCTAssertFalse(state.update(" \n ", generation: empty))
        XCTAssertNil(state.commit(generation: empty))
        let fresh = state.begin()
        XCTAssertTrue(state.update("hi", generation: fresh))
        XCTAssertFalse(state.update("hi", generation: fresh))
        XCTAssertTrue(state.update(String(repeating: "字", count: 3000), generation: fresh))
        XCTAssertEqual(state.commit(generation: fresh)?.count, 2000)
    }
}
