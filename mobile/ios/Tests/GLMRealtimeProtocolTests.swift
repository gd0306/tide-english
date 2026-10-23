import XCTest
@testable import TideEnglishCore

final class GLMRealtimeProtocolTests: XCTestCase {
    func testOwnerJWTUsesHS256AndSafeInputs() throws {
        // Independent Python hashlib/hmac fixture, containing no real key.
        XCTAssertEqual(try GLMRealtimeProtocol.token(key: "fixture-id.fixture-secret", now: 1_700_000_000, lifetime: 600),
                       "eyJhbGciOiJIUzI1NiIsInNpZ25fdHlwZSI6IlNJR04ifQ.eyJhcGlfa2V5IjoiZml4dHVyZS1pZCIsImV4cCI6MTcwMDAwMDYwMCwidGltZXN0YW1wIjoxNzAwMDAwMDAwMDAwfQ.8d6jikNgYXP_Nu_WyXzG07rjjy6v5-h7kUdVp2XtSX4")
        for key in ["", "id", ".secret", "id.", "id.secret.extra", "id.sec\nret", "id. secret"] {
            XCTAssertThrowsError(try GLMRealtimeProtocol.token(key: key, now: 1_700_000_000))
        }
        for now in [Double.nan, .infinity, -1, Double.greatestFiniteMagnitude] {
            XCTAssertThrowsError(try GLMRealtimeProtocol.token(key: "id.secret", now: now))
        }
        XCTAssertThrowsError(try GLMRealtimeProtocol.token(key: "id.secret", now: 1, lifetime: 0))
        XCTAssertThrowsError(try GLMRealtimeProtocol.token(key: "id.secret", now: 1, lifetime: 3601))
    }

    func testMonoWAVFramesPCM16At16kAndRejectsInvalidChunks() throws {
        let wav = try GLMRealtimeProtocol.wav(pcm: Data([0, 0, 255, 127, 0, 128]))
        XCTAssertEqual(wav.prefix(44), Data([82,73,70,70,42,0,0,0,87,65,86,69,102,109,116,32,16,0,0,0,1,0,1,0,128,62,0,0,0,125,0,0,2,0,16,0,100,97,116,97,6,0,0,0]))
        XCTAssertEqual(wav.suffix(6), Data([0,0,255,127,0,128]))
        XCTAssertThrowsError(try GLMRealtimeProtocol.wav(pcm: Data()))
        XCTAssertThrowsError(try GLMRealtimeProtocol.wav(pcm: Data([0])))
        XCTAssertThrowsError(try GLMRealtimeProtocol.wav(pcm: Data(repeating: 0, count: 32_002)))
    }

    func testConfigurationAcceptanceIsRequiredAndStartsOnlyOnce() throws {
        var state = GLMRealtimeProtocol()
        XCTAssertTrue(try consume(["type": "session.created"], into: &state).events.isEmpty)
        XCTAssertTrue(try consume(["type": "session.updated", "session": ["output_audio_format": "mp3"]], into: &state).events.isEmpty)
        let session: [String: Any] = ["id": "session-fixture", "input_audio_format": "wav", "output_audio_format": "pcm", "turn_detection": ["type": "server_vad"], "beta_fields": ["chat_mode": "audio", "auto_search": false]]
        XCTAssertEqual(try consume(["type": "session.updated", "session": session], into: &state).events.first?["type"] as? String, "session.started")
        XCTAssertTrue(try consume(["type": "session.updated", "session": session], into: &state).events.isEmpty)
    }

    func testInputFinalDeduplicatesByItemButPreservesRepeatedLearnerTurns() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "input_audio_buffer.speech_started", "item_id": "u1", "audio_start_ms": 100], into: &state, elapsed: 100)
        _ = try consume(["type": "input_audio_buffer.speech_stopped", "item_id": "u1", "audio_end_ms": 400], into: &state, elapsed: 400)
        let event: [String: Any] = ["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": "你好"]
        let first = try consume(event, into: &state, elapsed: 600).events
        XCTAssertEqual(first.first?["delta"] as? String, "你好")
        XCTAssertEqual(first.first?["start_ms"] as? Int, 100)
        XCTAssertEqual(first.first?["end_ms"] as? Int, 400)
        XCTAssertTrue(try consume(event, into: &state).events.isEmpty)
        let second = try consume(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u2", "transcript": "你好"], into: &state, elapsed: 700).events
        XCTAssertEqual(second.first?["delta"] as? String, "你好")
        XCTAssertNotEqual(first.first?["event_id"] as? String, second.first?["event_id"] as? String)
    }

    func testOutputFinalOnlyAppendsMissingSuffixAndKeepsSpeakerIDsDistinct() throws {
        var state = GLMRealtimeProtocol()
        let delta: [String: Any] = ["type": "response.audio_transcript.delta", "response_id": "r1", "event_id": "d1", "delta": "Hello"]
        let first = try consume(delta, into: &state, elapsed: 10).events
        XCTAssertEqual(first.first?["delta"] as? String, "Hello")
        XCTAssertTrue(try consume(delta, into: &state).events.isEmpty)
        let final: [String: Any] = ["type": "response.audio_transcript.done", "response_id": "r1", "item_id": "i1", "transcript": "Hello there"]
        let suffix = try consume(final, into: &state, elapsed: 20).events
        XCTAssertEqual(suffix.first?["delta"] as? String, " there")
        XCTAssertEqual(suffix.first?["start_ms"] as? Int, 10)
        XCTAssertEqual(suffix.first?["end_ms"] as? Int, 20)
        XCTAssertNotEqual(first.first?["event_id"] as? String, suffix.first?["event_id"] as? String)
        XCTAssertTrue(try consume(final, into: &state).events.isEmpty)
        let input = try consume(["type": "conversation.item.input_audio_transcription.completed", "item_id": "r1", "transcript": "Hello"], into: &state).events
        XCTAssertNotEqual(first.first?["event_id"] as? String, input.first?["event_id"] as? String)
    }

    func testCancellationClearsPlaybackAndLateAudioCannotComplete() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.created", "response": ["id": "r1", "status": "in_progress"]], into: &state)
        XCTAssertEqual(try consume(["type": "response.audio.delta", "response_id": "r1", "delta": "AACA/w=="], into: &state).audio, Data([0,0,128,255]))
        XCTAssertTrue(try consume(["type": "input_audio_buffer.speech_started"], into: &state).clearPlayback)
        XCTAssertNil(try consume(["type": "response.audio.delta", "response_id": "r1", "delta": "AAA="], into: &state).audio)
        XCTAssertFalse(try consume(["type": "response.audio.done", "response_id": "r1"], into: &state).responseCompleted)
        let done = try consume(["type": "response.done", "response": ["id": "r1", "status": "completed"]], into: &state)
        XCTAssertFalse(done.responseCompleted)
    }

    func testOnlyCompletedResponseDoneCompletesAndUsageIsNormalized() throws {
        for status in ["cancelled", "incomplete", "failed"] {
            var state = GLMRealtimeProtocol()
            XCTAssertFalse(try consume(["type": "response.audio.done", "response_id": "r"], into: &state).responseCompleted)
            let result = try consume(["type": "response.done", "response": ["id": "r", "status": status]], into: &state)
            XCTAssertFalse(result.responseCompleted)
            XCTAssertTrue(result.clearPlayback)
        }
        var state = GLMRealtimeProtocol()
        let result = try consume(["type": "response.done", "response": ["id": "r", "status": "completed", "usage": ["input_tokens": 3, "output_tokens": 5]]], into: &state, elapsed: 1250)
        XCTAssertTrue(result.responseCompleted)
        XCTAssertEqual(result.events.first?["type"] as? String, "session.usage.updated")
        XCTAssertEqual((result.events.first?["usage"] as? [String: Any])?["seconds"] as? Double, 1.25)
        XCTAssertFalse(try consume(["type": "response.done", "response": ["id": "r", "status": "completed"]], into: &state).responseCompleted)
    }

    func testCancelledOldResponseDoesNotClearNewResponsePlayback() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.audio.delta", "response_id": "old", "delta": "AAA="], into: &state)
        _ = try consume(["type": "input_audio_buffer.speech_started"], into: &state)
        _ = try consume(["type": "response.audio.delta", "response_id": "new", "delta": "AAA="], into: &state)
        XCTAssertFalse(try consume(["type": "response.done", "response": ["id": "old", "status": "cancelled"]], into: &state).clearPlayback)
    }

    func testSpeechInterruptsQueuedAudioEvenAfterResponseCompleted() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.audio.delta", "response_id": "r", "delta": "AAA="], into: &state)
        _ = try consume(["type": "response.done", "response": ["id": "r", "status": "completed"]], into: &state)
        XCTAssertTrue(try consume(["type": "input_audio_buffer.speech_started"], into: &state).clearPlayback)
        XCTAssertNil(try consume(["type": "response.audio.delta", "response_id": "r", "delta": "AAA="], into: &state).audio)
    }

    func testRespondingPromptClearsCompletedBufferedPlaybackWithoutCancellingServer() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.created", "response": ["id": "old"]], into: &state)
        _ = try consume(["type": "response.audio.delta", "response_id": "old", "delta": "AAA="], into: &state)
        XCTAssertTrue(try consume(["type": "response.done", "response": ["id": "old", "status": "completed"]], into: &state).responseCompleted)

        let silent = try state.commands(["type": "session.thinking.append", "content": "Additional context", "respond": false])
        XCTAssertEqual(silent.map { $0["type"] as? String }, ["conversation.item.create"])
        let commands = try state.commands(["type": "session.commentary.append", "content": "Typed learner reply", "respond": true])
        XCTAssertEqual(commands.map { $0["type"] as? String },
                       ["client.playback.clear", "conversation.item.create", "response.create"])
        let final = try consume(["type": "response.audio_transcript.done", "response_id": "old", "transcript": "Finished answer"], into: &state)
        XCTAssertEqual(final.events.first?["delta"] as? String, "Finished answer")
    }

    func testCompletedResponseRejectsLatePCM() throws {
        var state = GLMRealtimeProtocol()
        XCTAssertEqual(try consume(["type": "response.audio.delta", "response_id": "old", "delta": "AAA="], into: &state).audio, Data([0, 0]))
        _ = try consume(["type": "response.done", "response": ["id": "old", "status": "completed"]], into: &state)
        XCTAssertNil(try consume(["type": "response.audio.delta", "response_id": "old", "delta": "AAA="], into: &state).audio)
    }

    func testLateCompletedPCMDoesNotStealNewResponsePlaybackOwnership() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.audio.delta", "response_id": "old", "delta": "AAA="], into: &state)
        _ = try consume(["type": "response.done", "response": ["id": "old", "status": "completed"]], into: &state)
        XCTAssertEqual(try consume(["type": "response.audio.delta", "response_id": "new", "delta": "AAA="], into: &state).audio, Data([0, 0]))
        XCTAssertNil(try consume(["type": "response.audio.delta", "response_id": "old", "delta": "AAA="], into: &state).audio)
        XCTAssertFalse(try consume(["type": "response.done", "response": ["id": "old", "status": "cancelled"]], into: &state).clearPlayback)
        XCTAssertFalse(try consume(["type": "response.done", "response": ["id": "old", "status": "incomplete"]], into: &state).clearPlayback)
        XCTAssertTrue(try consume(["type": "response.done", "response": ["id": "new", "status": "incomplete"]], into: &state).clearPlayback)
    }

    func testRespondingPromptCancelsActiveResponseButKeepsOlderCompletedFinalTranscript() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.audio.delta", "response_id": "completed", "delta": "AAA="], into: &state)
        _ = try consume(["type": "response.done", "response": ["id": "completed", "status": "completed"]], into: &state)
        _ = try consume(["type": "response.created", "response": ["id": "active"]], into: &state)

        let commands = try state.commands(["type": "session.instructions.append", "content": "Next task", "respond": true])
        XCTAssertEqual(commands.map { $0["type"] as? String }, ["response.cancel", "session.update", "response.create"])
        let final = try consume(["type": "response.audio_transcript.done", "response_id": "completed", "transcript": "Earlier answer"], into: &state)
        XCTAssertEqual(final.events.first?["delta"] as? String, "Earlier answer")
        XCTAssertNil(try consume(["type": "response.audio.delta", "response_id": "active", "delta": "AAA="], into: &state).audio)
    }

    func testCompletedResponseAllowsLateTranscriptFinalButCancelledResponseDoesNot() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.audio_transcript.delta", "response_id": "r", "delta": "Good"], into: &state)
        _ = try consume(["type": "response.done", "response": ["id": "r", "status": "completed"]], into: &state)
        let final = try consume(["type": "response.audio_transcript.done", "response_id": "r", "transcript": "Good morning"], into: &state)
        XCTAssertEqual(final.events.first?["delta"] as? String, " morning")
    }

    func testStartupGateRequiresConfigurationAndEveryHistoryAcknowledgement() {
        var gate = GLMRealtimeProtocol.StartupGate(historyIDs: ["h1", "h2"])
        gate.acceptHistory("unrelated")
        XCTAssertFalse(gate.ready)
        gate.acceptConfiguration()
        XCTAssertFalse(gate.ready)
        gate.acceptHistory("h2")
        gate.acceptHistory("h2")
        XCTAssertFalse(gate.ready)
        gate.acceptHistory("h1")
        XCTAssertTrue(gate.ready)
        var empty = GLMRealtimeProtocol.StartupGate(historyIDs: [])
        XCTAssertFalse(empty.ready)
        empty.acceptConfiguration()
        XCTAssertTrue(empty.ready)
    }

    func testExplicitCancelBlocksLateTranscriptAndAudio() throws {
        var state = GLMRealtimeProtocol()
        _ = try consume(["type": "response.created", "response": ["id": "r1", "status": "in_progress"]], into: &state)
        XCTAssertEqual(try state.commands(["type": "response.cancel"]).first?["type"] as? String, "response.cancel")
        XCTAssertTrue(try consume(["type": "response.audio_transcript.done", "response_id": "r1", "transcript": "old output"], into: &state).events.isEmpty)
        XCTAssertNil(try consume(["type": "response.audio.delta", "response_id": "r1", "delta": "AAA="], into: &state).audio)
    }

    func testMalformedOversizedMessagesAndPCMFailSafely() throws {
        var state = GLMRealtimeProtocol()
        for data in [Data("null".utf8), Data("{".utf8), Data("{}".utf8), Data(repeating: 32, count: 262145)] {
            XCTAssertThrowsError(try state.consume(data, elapsedMS: 0))
        }
        for delta in ["!", "AA==", String(repeating: "A", count: 128004)] {
            XCTAssertThrowsError(try consume(["type": "response.audio.delta", "response_id": "r", "delta": delta], into: &state))
        }
        XCTAssertThrowsError(try consume(["type": "response.audio_transcript.delta", "delta": "text"], into: &state))
    }

    func testAppendCommandsConsumeRespondAndNeverEchoTypedLearnerEvidence() throws {
        var state = GLMRealtimeProtocol(instructions: "Teach French")
        let silent = try state.commands(["type": "session.instructions.append", "content": "Wait", "respond": false])
        XCTAssertEqual(silent.count, 1)
        XCTAssertEqual(silent.first?["type"] as? String, "session.update")
        XCTAssertEqual((silent.first?["session"] as? [String: Any])?["instructions"] as? String, "Teach French\nWait")
        let prompt = try state.commands(["type": "session.commentary.append", "content": "Typed learner reply: Bonjour", "respond": true])
        XCTAssertEqual(prompt.map { $0["type"] as? String }, ["conversation.item.create", "response.create"])
        XCTAssertEqual((prompt.first?["item"] as? [String: Any])?["role"] as? String, "system")
        XCTAssertNil(prompt.first?["respond"])
        XCTAssertTrue(try consume(["type": "conversation.item.created", "item": prompt[0]["item"]!], into: &state).events.isEmpty)
        let history = try GLMRealtimeProtocol.historyCommands([["role": "assistant", "content": [["type": "output_text", "text": "Salut"]]]])
        XCTAssertEqual((((history.first?["item"] as? [String: Any])?["content"] as? [[String: Any]])?.first)?["type"] as? String, "text")
    }

    func testCapabilityErrorsAreStructuredAndExcludeAuthBillingAndNetwork() {
        for code in ["1212", "1220", "1311"] { XCTAssertEqual(GLMRealtimeProtocol.failure(code: code), .capability) }
        for code in ["1000", "1001", "1003", "1005"] { XCTAssertEqual(GLMRealtimeProtocol.failure(code: code), .authentication) }
        for code in ["1113", "1309", "1310", "1314", "1315", "1316"] { XCTAssertEqual(GLMRealtimeProtocol.failure(code: code), .billing) }
        XCTAssertEqual(GLMRealtimeProtocol.failure(code: "1234"), .unavailable)
        XCTAssertEqual(GLMRealtimeProtocol.failure(code: "permission_denied"), .invalidRequest)
        XCTAssertEqual(GLMRealtimeProtocol.failure(code: nil), .invalidRequest)
    }

    func testMuteQueueDiscardPreservesContextUpdatesAndResponseRequests() throws {
        var queue = GLMRealtimeProtocol.SendQueue()
        XCTAssertTrue(try queue.append([["type": "session.update"], ["type": "input_audio_buffer.append", "audio": "AAA="], ["type": "response.create"]]))
        queue.discardMicrophoneAudio()
        XCTAssertEqual(queue.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(queue.pop()).utf8)) as? [String: Any]
        let second = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(queue.pop()).utf8)) as? [String: Any]
        XCTAssertEqual(first?["type"] as? String, "session.update")
        XCTAssertEqual(second?["type"] as? String, "response.create")
    }

    func testInterruptDropsUnsentResponseRequestsAndPreservesContext() throws {
        var queue = GLMRealtimeProtocol.SendQueue()
        XCTAssertTrue(try queue.append([["type": "response.create"], ["type": "session.update"], ["type": "response.cancel"]]))
        queue.discardResponseRequests()
        XCTAssertEqual(queue.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(queue.pop()).utf8)) as? [String: Any]
        XCTAssertEqual(first?["type"] as? String, "session.update")
    }

    func testDeferredResponseAcknowledgementsCannotRestartCancelledOrSupersededPrompts() {
        var gate = GLMRealtimeProtocol.ResponseGate()
        let old = gate.request(), latest = gate.request()
        XCTAssertFalse(gate.consume(old))
        XCTAssertTrue(gate.consume(latest))
        XCTAssertFalse(gate.consume(latest))
        let interrupted = gate.request()
        gate.cancel()
        XCTAssertFalse(gate.consume(interrupted))
    }

    func testSendQueueRejectsOverloadAtomicallyAndBoundsEachFrame() throws {
        var queue = GLMRealtimeProtocol.SendQueue()
        let event: [String: Any] = ["type": "response.create"]
        XCTAssertTrue(try queue.append(Array(repeating: event, count: 31)))
        XCTAssertFalse(try queue.append([event, event]))
        XCTAssertEqual(queue.count, 31)
        XCTAssertNotNil(queue.pop())
        XCTAssertTrue(try queue.append([event, event]))
        XCTAssertEqual(queue.count, 32)
        XCTAssertThrowsError(try GLMRealtimeProtocol.SendQueue().frames([["type": "x", "content": String(repeating: "a", count: 262_145)]]))
    }

    private func consume(_ event: [String: Any], into state: inout GLMRealtimeProtocol, elapsed: Int = 0) throws -> GLMRealtimeProtocol.Update {
        try state.consume(JSONSerialization.data(withJSONObject: event), elapsedMS: elapsed)
    }
}
