import XCTest
@testable import TideEnglishCore

final class GeminiLiveProtocolTests: XCTestCase {
    private func consume(_ event: [String: Any], _ state: inout GeminiLiveProtocol, at: Int = 100) throws -> GeminiLiveProtocol.Update {
        try state.consume(JSONSerialization.data(withJSONObject: event), elapsedMS: at)
    }
    private func ready() throws -> GeminiLiveProtocol {
        var state = GeminiLiveProtocol()
        _ = try consume(["setupComplete": [:]], &state)
        return state
    }
    func testSetupHistoryAndFirstAcknowledgement() throws {
        let setup = try XCTUnwrap(GeminiLiveProtocol.setup(instructions: "Teach", hasHistory: false)["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.8-live")
        XCTAssertEqual((setup["generationConfig"] as? [String: Any])?["responseModalities"] as? [String], ["AUDIO"])
        for key in ["inputAudioTranscription", "outputAudioTranscription", "sessionResumption"] { XCTAssertEqual((setup[key] as? [String: Any])?.count, 0) }
        XCTAssertEqual(((setup["contextWindowCompression"] as? [String: Any])?["slidingWindow"] as? [String: Any])?.count, 0)
        XCTAssertNil(setup["historyConfig"])
        let restored = try GeminiLiveProtocol.setup(instructions: "Teach", hasHistory: true)["setup"] as? [String: Any]
        XCTAssertEqual((restored?["historyConfig"] as? [String: Any])?["initialHistoryInClientContent"] as? Bool, true)
        var state = GeminiLiveProtocol()
        XCTAssertThrowsError(try state.audio(Data([0, 0, 1, 0])))
        XCTAssertEqual(try consume(["setupComplete": [:]], &state).events.first?["type"] as? String, "session.started")
        XCTAssertTrue(try consume(["setupComplete": [:]], &state).events.isEmpty)
        let history = try XCTUnwrap(GeminiLiveProtocol.history([["role": "assistant", "content": [["text": "Hi"]]]]))
        let content = try XCTUnwrap(history["clientContent"] as? [String: Any])
        XCTAssertEqual(content["turnComplete"] as? Bool, true)
        XCTAssertEqual((content["turns"] as? [[String: Any]])?.first?["role"] as? String, "model")
        XCTAssertNil(try GeminiLiveProtocol.history([]))
    }
    func testTokenProvisioningAndHeaderEndpoint() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let body = try GeminiLiveProtocol.tokenBody(now: now)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(body["uses"] as? Int, 1)
        XCTAssertEqual(formatter.date(from: body["newSessionExpireTime"] as! String)?.timeIntervalSince(now), 60)
        XCTAssertEqual(formatter.date(from: body["expireTime"] as! String)?.timeIntervalSince(now), 65 * 60)
        XCTAssertNil(URLComponents(url: GeminiLiveProtocol.socketURL, resolvingAgainstBaseURL: false)?.query)
        XCTAssertNil(URLComponents(url: GeminiLiveProtocol.tokenURL, resolvingAgainstBaseURL: false)?.query)
        XCTAssertEqual(try GeminiLiveProtocol.token(from: Data(#"{"name":"fixture-token"}"#.utf8)), "fixture-token")
        for token in ["", "bad\nvalue", "bad value", String(repeating: "a", count: 8193)] {
            XCTAssertThrowsError(try GeminiLiveProtocol.token(from: JSONSerialization.data(withJSONObject: ["name": token])))
        }
        XCTAssertThrowsError(try GeminiLiveProtocol.token(from: Data("{}".utf8)))
    }
    func testRawPCMValidationAndNoAudioBeforeSetup() throws {
        var state = try ready()
        let bytes = Data([0, 0, 1, 0])
        let input = try state.audio(bytes)
        let blob = (input["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any]
        XCTAssertEqual(blob?["mimeType"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual(blob?["data"] as? String, bytes.base64EncodedString())
        let output: [String: Any] = ["serverContent": ["modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": bytes.base64EncodedString()]]]]]]
        XCTAssertEqual(try consume(output, &state).audio, [bytes])
        var unconfigured = GeminiLiveProtocol()
        XCTAssertThrowsError(try consume(output, &unconfigured))
        for pcm in [Data(), Data([1]), Data(repeating: 0, count: 32002)] { XCTAssertThrowsError(try state.audio(pcm)) }
        for blob: [String: Any] in [["mimeType": "audio/wav", "data": "AAAA"], ["mimeType": "audio/pcm;rate=24000", "data": "AA=="], ["mimeType": "audio/pcm;rate=24000", "data": Data(repeating: 0, count: 96002).base64EncodedString()]] {
            XCTAssertThrowsError(try consume(["serverContent": ["modelTurn": ["parts": [["inlineData": blob]]]]], &state))
        }
        XCTAssertThrowsError(try state.consume(Data(repeating: 32, count: 262145), elapsedMS: 0))
        XCTAssertThrowsError(try state.consume(Data("{".utf8), elapsedMS: 0))
    }
    func testFinishedInputIsIndependentOfModelTurnAndDeduplicated() throws {
        var state = try ready()
        let first = try consume(["serverContent": ["inputTranscription": ["text": "hello "]]], &state, at: 10)
        XCTAssertEqual(first.events.first?["delta"] as? String, "hello ")
        _ = try consume(["serverContent": ["turnComplete": true]], &state, at: 20)
        let final: [String: Any] = ["serverContent": ["inputTranscription": ["text": "world", "finished": true]]]
        let events = try consume(final, &state, at: 30).events
        XCTAssertEqual(events.first?["delta"] as? String, "world")
        XCTAssertEqual(events.first?["start_ms"] as? Int, 10)
        XCTAssertTrue(try consume(final, &state, at: 40).events.isEmpty)
    }
    func testOffsetTranscriptsCanArriveOutOfOrderAcrossModelTurns() throws {
        var state = try ready()
        let later: [String: Any] = ["serverContent": ["inputTranscription": ["text": "later", "startOffset": "2s", "endOffset": "3s"]]]
        let earlier: [String: Any] = ["serverContent": ["inputTranscription": ["text": "earlier", "startOffset": "0.1s", "endOffset": "1s"]]]
        let second = try consume(later, &state).events
        _ = try consume(["serverContent": ["turnComplete": true]], &state)
        let first = try consume(earlier, &state).events
        XCTAssertEqual(second.first?["start_ms"] as? Int, 2000)
        XCTAssertEqual(first.first?["start_ms"] as? Int, 100)
        XCTAssertNotEqual(second.first?["event_id"] as? String, first.first?["event_id"] as? String)
        XCTAssertTrue(try consume(later, &state).events.isEmpty)
    }
    func testOutputFinalAndInterruptionDropLateAudio() throws {
        var state = try ready()
        let first = try consume(["serverContent": ["outputTranscription": ["text": "hello"]]], &state)
        XCTAssertEqual(first.events.first?["delta"] as? String, "hello")
        let final = try consume(["serverContent": ["outputTranscription": ["text": "", "finished": true]]], &state)
        XCTAssertTrue(final.events.isEmpty)
        XCTAssertTrue(try consume(["serverContent": ["turnComplete": true]], &state).events.isEmpty)
        XCTAssertTrue(try consume(["serverContent": ["interrupted": true]], &state).clearPlayback)
        let late = try consume(["serverContent": ["modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": "AAAAAA=="]]]]]], &state)
        XCTAssertTrue(late.audio.isEmpty)
    }
    func testUsageDuplicateDoesNotEmitTwice() throws {
        var state = try ready()
        let usage: [String: Any] = ["usageMetadata": ["promptTokenCount": 4, "responseTokenCount": 8, "totalTokenCount": 12]]
        XCTAssertEqual(try consume(usage, &state).events.count, 1)
        XCTAssertTrue(try consume(usage, &state).events.isEmpty)
    }
    func testCommandsAndPassiveBoundaryAndAcceptance() throws {
        var state = try ready()
        let passive = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "facts", "respond": false, "event_id": "one"])
        XCTAssertEqual((passive.wire["clientContent"] as? [String: Any])?["turnComplete"] as? Bool, false)
        _ = try consume(["serverContent": ["outputTranscription": ["text": "active"]]], &state)
        XCTAssertFalse(state.canSend(passive))
        let reply = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "simpler", "event_id": "two"])
        XCTAssertTrue(state.canSend(reply))
        XCTAssertTrue(state.accept(reply).clearPlayback)
        XCTAssertEqual(state.accept(passive).events.first?["client_event_id"] as? String, "one")
        XCTAssertThrowsError(try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "x", "respond": "false"]))
    }
    func testSafeResumePreservesIdentityAndDoesNotStartTwice() throws {
        var state = try ready()
        _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "fixture-handle"]], &state)
        XCTAssertEqual(try consume(["goAway": ["timeLeft": "10s"]], &state).resumeHandle, "fixture-handle")
        try state.beginResume()
        XCTAssertFalse(state.configured)
        XCTAssertThrowsError(try state.audio(Data([0, 0])))
        let setup = try GeminiLiveProtocol.setup(instructions: "x", hasHistory: true, resumeHandle: "fixture-handle")["setup"] as? [String: Any]
        XCTAssertNil(setup?["historyConfig"])
        XCTAssertEqual((setup?["sessionResumption"] as? [String: Any])?["handle"] as? String, "fixture-handle")
        XCTAssertTrue(try consume(["setupComplete": [:]], &state).events.isEmpty)
        XCTAssertTrue(state.configured)
    }
    func testUnsafeAndBoundedResumptionAndFailureClassification() throws {
        var state = try ready()
        XCTAssertThrowsError(try consume(["goAway": [:]], &state))
        _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "handle"]], &state)
        state.noteOutbound()
        XCTAssertThrowsError(try consume(["goAway": [:]], &state))
        state = try ready() // Only an untouched session has provably current resumable context.
        for _ in 0..<6 {
            _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "handle"]], &state)
            try state.beginResume()
            _ = try consume(["setupComplete": [:]], &state)
        }
        XCTAssertThrowsError(try state.beginResume())
        for status in [404, 501] { XCTAssertEqual(GeminiLiveProtocol.failure(status: status, started: false), .capability) }
        for status in [401, 402, 403, 429, 500] { XCTAssertNotEqual(GeminiLiveProtocol.failure(status: status, started: false), .capability) }
        XCTAssertNotEqual(GeminiLiveProtocol.failure(status: 404, started: true), .capability)
    }
    func testPaymentRequiredStopsLiveWithoutCapabilityFallback() throws {
        for started in [false, true] {
            XCTAssertEqual(GeminiLiveProtocol.failure(status: 402, started: started), .billing)
        }
        var state = try ready()
        XCTAssertThrowsError(try consume(["error": ["code": 402]], &state)) { error in
            XCTAssertEqual(error as? GeminiLiveProtocol.Failure, .billing)
        }
    }
    func testAtomicBoundedQueueDropsAudioAndRetainsCommands() throws {
        var queue = GeminiLiveProtocol.SendQueue()
        let command = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "x", "event_id": "one"])
        XCTAssertTrue(try queue.append(.init(wire: ["realtimeInput": ["audio": [:]]], isAudio: true)))
        XCTAssertTrue(try queue.append(.init(command: command)))
        queue.discardAudio()
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.pop()?.command?.id, "one")
        for _ in 0..<16 { XCTAssertTrue(try queue.append(.init(command: command))) }
        XCTAssertFalse(try queue.append(.init(command: command)))
        XCTAssertEqual(queue.count, 16)
    }
    func testCumulativeFinalDoesNotDuplicatePreviouslyEmittedText() throws {
        var state = try ready()
        _ = try consume(["serverContent": ["inputTranscription": ["text": "hello"]]], &state)
        let final = try consume(["serverContent": ["inputTranscription": ["text": "hello world", "finished": true]]], &state)
        XCTAssertEqual(final.events.first?["delta"] as? String, " world")
        _ = try consume(["serverContent": ["outputTranscription": ["text": "bonjour"]]], &state)
        XCTAssertTrue(try consume(["serverContent": ["outputTranscription": ["text": "bonjour", "finished": true]]], &state).events.isEmpty)
        _ = try consume(["serverContent": ["turnComplete": true]], &state)
        XCTAssertTrue(try consume(["serverContent": ["outputTranscription": ["text": "bonjour", "finished": true]]], &state).events.isEmpty)
    }
    func testNoOffsetInputChunksWithoutFinishedRemainUsableAndBounded() throws {
        var state = try ready()
        for word in ["one", " two", " three"] {
            XCTAssertEqual(try consume(["serverContent": ["inputTranscription": ["text": word]]], &state).events.first?["delta"] as? String, word)
        }
        XCTAssertThrowsError(try consume(["serverContent": ["inputTranscription": ["text": String(repeating: "x", count: 32769)]]], &state))
        for offset in ["-1s", "nans", "infs", "1", "999999999999999s"] {
            XCTAssertThrowsError(try consume(["serverContent": ["inputTranscription": ["text": "bad", "startOffset": offset, "endOffset": "2s"]]], &state))
        }
    }
    func testResumeHandleRevocationAndActiveOutputAreUnsafe() throws {
        var state = try ready()
        _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "handle"]], &state)
        _ = try consume(["sessionResumptionUpdate": ["resumable": false]], &state)
        XCTAssertThrowsError(try consume(["goAway": [:]], &state))
        _ = try consume(["serverContent": ["outputTranscription": ["text": "active"]]], &state)
        _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "handle"]], &state)
        XCTAssertThrowsError(try consume(["goAway": [:]], &state))
        _ = try consume(["serverContent": ["turnComplete": true]], &state)
        _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "fresh"]], &state)
        XCTAssertEqual(try consume(["goAway": [:]], &state).resumeHandle, "fresh")
    }
    func testAudioQueueBoundsAndOversizedHistoryAreAtomic() throws {
        var queue = GeminiLiveProtocol.SendQueue()
        for _ in 0..<32 { XCTAssertTrue(try queue.append(.init(wire: ["realtimeInput": ["audio": [:]]], isAudio: true))) }
        XCTAssertFalse(try queue.append(.init(wire: ["realtimeInput": ["audio": [:]]], isAudio: true)))
        XCTAssertEqual(queue.count, 32)
        queue.discardAudio(); XCTAssertEqual(queue.count, 0)
        XCTAssertThrowsError(try queue.append(.init(wire: ["text": String(repeating: "x", count: 262144)])))
        XCTAssertEqual(queue.count, 0)
        XCTAssertThrowsError(try GeminiLiveProtocol.history([["role": "user", "content": [["text": String(repeating: "x", count: 6000)]]]]))
        XCTAssertThrowsError(try GeminiLiveProtocol.setup(instructions: String(repeating: "x", count: 65537), hasHistory: false))
    }

    func testRepeatedSpeechFinalHasNewIdentityAfterNewVoiceActivity() throws {
        var state = try ready()
        let transcript: [String: Any] = ["serverContent": ["inputTranscription": ["text": "yes", "finished": true]]]
        let first = try consume(transcript, &state).events
        XCTAssertTrue(try consume(transcript, &state).events.isEmpty)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "1s"]], &state)
        let second = try consume(transcript, &state, at: 1200).events
        XCTAssertEqual(second.first?["delta"] as? String, "yes")
        XCTAssertNotEqual(first.first?["event_id"] as? String, second.first?["event_id"] as? String)
        XCTAssertEqual(second.first?["start_ms"] as? Int, 1000)
    }
    func testOutputOffsetsAreScopedToOutputTurns() throws {
        var state = try ready()
        let transcript: [String: Any] = ["serverContent": ["outputTranscription": ["text": "hello", "startOffset": "0s", "endOffset": "1s"]]]
        let first = try consume(transcript, &state).events
        _ = try consume(["serverContent": ["turnComplete": true]], &state)
        let second = try consume(transcript, &state, at: 2000).events
        XCTAssertEqual(second.first?["delta"] as? String, "hello")
        XCTAssertNotEqual(first.first?["event_id"] as? String, second.first?["event_id"] as? String)
    }

    func testOutputGenerationsPreserveSessionPassageChronology() throws {
        var state = try ready()
        var session = SessionRecord()
        let frames: [(Int, [String: Any])] = [
            (0, ["outputTranscription": ["text": "First answer.", "startOffset": "0s", "endOffset": "1s"]]),
            (1100, ["turnComplete": true, "interactionStatus": "IDLE"]),
            (6000, ["inputTranscription": ["text": "Next question?", "startOffset": "5s", "endOffset": "6s", "finished": true]]),
            (10000, ["outputTranscription": ["text": "Second", "startOffset": "0s", "endOffset": "1s"]]),
            (12000, ["outputTranscription": ["text": "Second answer.", "startOffset": "0s", "endOffset": "2s", "finished": true]])
        ]
        for (time, content) in frames {
            for event in try consume(["serverContent": content], &state, at: time).events {
                let type = try XCTUnwrap(event["type"] as? String)
                session.append(Fragment(id: try XCTUnwrap(event["event_id"] as? String),
                    speaker: type == "session.input_transcript.delta" ? .user : .assistant,
                    text: try XCTUnwrap(event["delta"] as? String),
                    startMS: try XCTUnwrap(event["start_ms"] as? Int),
                    endMS: try XCTUnwrap(event["end_ms"] as? Int)))
            }
        }
        XCTAssertEqual(session.passages.map(\.speaker), [.assistant, .user, .assistant])
        XCTAssertEqual(session.passages.map(\.text), ["First answer.", "Next question?", "Second answer."])
        XCTAssertEqual(session.passages.map(\.startMS), [0, 5000, 10000])
        XCTAssertEqual(session.passages.map(\.endMS), [1000, 6000, 12000])
    }

    func testOutputOptionalOffsetsAndFallbackKeepOneGenerationClock() throws {
        for offsetsFirst in [false, true] {
            var state = try ready()
            let first: [String: Any] = offsetsFirst
                ? ["text": "First", "startOffset": "0s", "endOffset": "0.5s"]
                : ["text": "First"]
            let firstEvent = try XCTUnwrap(consume(["serverContent": ["outputTranscription": first]], &state, at: 10000).events.first)
            XCTAssertEqual(firstEvent["start_ms"] as? Int, 10000)
            let second: [String: Any] = offsetsFirst
                ? ["text": " fallback"]
                : ["text": " offset", "startOffset": "0.5s"]
            let secondEvent = try XCTUnwrap(consume(["serverContent": ["outputTranscription": second]], &state, at: 11000).events.first)
            XCTAssertEqual(secondEvent["start_ms"] as? Int, offsetsFirst ? 11000 : 10500)
            XCTAssertEqual(secondEvent["end_ms"] as? Int, 11000)
            let endOnly = try XCTUnwrap(consume(["serverContent": ["outputTranscription": ["text": " end", "endOffset": "2s"]]], &state, at: 11500).events.first)
            XCTAssertEqual(endOnly["start_ms"] as? Int, 11500)
            XCTAssertEqual(endOnly["end_ms"] as? Int, 12000)
            XCTAssertTrue(try consume(["serverContent": ["outputTranscription": ["finished": true]]], &state, at: 12000).events.isEmpty)
            let next = try XCTUnwrap(consume(["serverContent": ["outputTranscription": ["text": " next", "startOffset": "3s", "endOffset": "4s"]]], &state, at: 14000).events.first)
            XCTAssertEqual(next["start_ms"] as? Int, 13000, "A textless final must not reset the generation anchor")
            XCTAssertEqual(next["end_ms"] as? Int, 14000)
            _ = try consume(["serverContent": ["interrupted": true]], &state, at: 14500)
            XCTAssertTrue(try consume(["serverContent": ["outputTranscription": ["text": "dropped", "startOffset": "4s", "endOffset": "5s"]]], &state, at: 15000).events.isEmpty)
            _ = try consume(["serverContent": ["turnComplete": true]], &state, at: 16000)
            let newTurn = try XCTUnwrap(consume(["serverContent": ["outputTranscription": ["text": "New", "startOffset": "0s", "endOffset": "1s"]]], &state, at: 20000).events.first)
            XCTAssertEqual(newTurn["start_ms"] as? Int, 20000)
        }
    }

    func testOutputAudioAnchorsLaterTranscriptionToItsGeneration() throws {
        var state = try ready()
        _ = try consume(["serverContent": ["modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": "AAAAAA=="]]]]]], &state, at: 10000)
        let event = try XCTUnwrap(consume(["serverContent": ["outputTranscription": ["text": "Hello", "startOffset": "0.5s", "endOffset": "1s"]]], &state, at: 13000).events.first)
        XCTAssertEqual(event["start_ms"] as? Int, 10500)
        XCTAssertEqual(event["end_ms"] as? Int, 11000)
    }

    func testPassiveCommandsWaitForBackgroundProcessingToBecomeIdle() throws {
        var state = try ready()
        let command = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "context", "respond": false])
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IN_PROGRESS"]], &state)
        XCTAssertFalse(state.canSend(command))
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
        XCTAssertTrue(state.canSend(command))
    }
    func testOptionalTranscriptOffsetsUseSafeFallbackTimes() throws {
        var state = try ready()
        let startOnly = try consume(["serverContent": ["inputTranscription": ["text": "hello", "startOffset": "0.1s"]]], &state, at: 500)
        XCTAssertEqual(startOnly.events.first?["start_ms"] as? Int, 100)
        XCTAssertEqual(startOnly.events.first?["end_ms"] as? Int, 500)
        let endOnly = try consume(["serverContent": ["inputTranscription": ["text": "world", "endOffset": "1s"]]], &state, at: 1500)
        XCTAssertEqual(endOnly.events.first?["end_ms"] as? Int, 1000)
        XCTAssertEqual(endOnly.events.first?["start_ms"] as? Int, 1000)
    }

    func testSendCompletionCannotCancelAnAlreadyArrivingNewReply() throws {
        var state = try ready()
        let command = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "greet"])
        let pcm: [String: Any] = ["serverContent": ["modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": "AAAAAA=="]]]]]]
        // The server can send a reply before URLSession resumes the send continuation.
        state.beginCommandSend()
        XCTAssertEqual(try consume(pcm, &state).audio.count, 1)
        XCTAssertFalse(state.accept(command).clearPlayback)
        XCTAssertEqual(try consume(pcm, &state).audio.count, 1)
    }

    func testCompletedReplyBeforeSendAcknowledgementDoesNotSuppressNextCommandReply() throws {
        for status in ["IDLE", "IN_PROGRESS"] {
            var state = try ready()
            let first = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "first", "event_id": "first"])
            let second = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "second", "event_id": "second"])
            let pcm = Data([0, 0, 1, 0])
            let output: [String: Any] = ["serverContent": ["outputTranscription": ["text": "Reply"], "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": pcm.base64EncodedString()]]]]]]
            XCTAssertTrue(state.beginSend(.init(command: first)))
            XCTAssertEqual(try consume(output, &state).audio, [pcm])
            _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": status]], &state)
            let acknowledgement = state.accept(first)
            XCTAssertEqual(acknowledgement.events.first?["client_event_id"] as? String, "first")
            XCTAssertFalse(acknowledgement.clearPlayback)
            XCTAssertEqual(state.replyActive, status == "IN_PROGRESS")
            if status == "IN_PROGRESS" {
                _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
            }
            XCTAssertTrue(state.beginSend(.init(command: second)))
            XCTAssertEqual(state.accept(second).events.first?["client_event_id"] as? String, "second")
            let next = try consume(output, &state, at: 10000)
            XCTAssertEqual(next.audio, [pcm])
            XCTAssertEqual(next.events.first?["delta"] as? String, "Reply")
            _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
            XCTAssertFalse(state.replyActive)
        }
    }

    func testOldActiveReplyDuringSendStillCancelsUntilItsBoundary() throws {
        var state = try ready()
        let old: [String: Any] = ["serverContent": ["outputTranscription": ["text": "old"], "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": "AAAAAA=="]]]]]]
        _ = try consume(old, &state)
        let command = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "new"])
        XCTAssertTrue(state.beginSend(.init(command: command)))
        _ = try consume(old, &state)
        XCTAssertTrue(state.accept(command).clearPlayback, "Old output during the write is not the new command's reply")
        XCTAssertTrue(state.replyActive)
        let trailing = try consume(old, &state)
        XCTAssertTrue(trailing.audio.isEmpty)
        XCTAssertTrue(trailing.events.isEmpty)
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
        XCTAssertEqual(try consume(old, &state).audio.count, 1)
    }

    func testCompletionDuringSendDistinguishesOldReplyFromEmptyNewReply() throws {
        for oldReplyActive in [false, true] {
            var state = try ready()
            if oldReplyActive {
                _ = try consume(["serverContent": ["outputTranscription": ["text": "old"]]], &state)
            }
            let command = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "reply"])
            XCTAssertTrue(state.beginSend(.init(command: command)))
            _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
            let acknowledgement = state.accept(command)
            XCTAssertEqual(state.replyActive, oldReplyActive, "Only completion of the new generation settles this command's reply")
            XCTAssertEqual(acknowledgement.clearPlayback, oldReplyActive)
            let next = try consume(["serverContent": ["outputTranscription": ["text": "next"], "modelTurn": ["parts": [["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": "AAAAAA=="]]]]]], &state)
            XCTAssertEqual(next.events.first?["delta"] as? String, "next")
            XCTAssertEqual(next.audio.count, 1)
        }
    }

    func testFixPendingSpeechBlocksPassiveUntilIdleAndBlocksAgainOnNewInput() throws {
        var state = try ready()
        let passive = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "context", "respond": false])
        for activity in 1...2 {
            _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "\(activity)s"]], &state)
            XCTAssertFalse(state.canSend(passive))
            _ = try consume(["serverContent": ["inputTranscription": ["text": "hello"]]], &state)
            _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state)
            XCTAssertFalse(state.canSend(passive), "Speech can be awaiting generation before first model output")
            _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
            XCTAssertTrue(state.canSend(passive))
        }
    }
    func testFixCompletedOutboundThenDelayedOldHandleCannotResume() throws {
        for audio in [false, true] {
            var state = try ready()
            if audio { state.noteOutbound() }
            else {
                let command = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "accepted", "respond": false])
                state.beginCommandSend()
                XCTAssertEqual(state.accept(command).events.count, 1)
            }
            _ = try consume(["sessionResumptionUpdate": ["resumable": true, "newHandle": "queued-before-send", "lastConsumedClientMessageIndex": "999"]], &state)
            XCTAssertThrowsError(try consume(["goAway": [:]], &state), "v1beta cannot prove consumption; arrival time or an unnegotiated index is insufficient")
        }
    }
    func testFixOffsetsAndCumulativeFinalShareUtteranceState() throws {
        for speaker in ["inputTranscription", "outputTranscription"] {
            for end in ["1s", "2s"] {
                var state = try ready()
                let first = try consume(["serverContent": [speaker: ["text": "hello", "startOffset": "0s", "endOffset": "1s"]]], &state)
                XCTAssertEqual(first.events.first?["delta"] as? String, "hello")
                let wire: [String: Any] = ["serverContent": [speaker: ["text": "hello world", "startOffset": "0s", "endOffset": end, "finished": true]]]
                XCTAssertEqual(try consume(wire, &state).events.first?["delta"] as? String, " world")
                XCTAssertTrue(try consume(wire, &state).events.isEmpty)
                XCTAssertTrue(try consume(["serverContent": [speaker: ["text": "corrected", "startOffset": "0s", "endOffset": end, "finished": true]]], &state).events.isEmpty)
            }
        }
    }
    func testFixUnfinishedActivityTextDoesNotAccumulateAcrossLearnerTurns() throws {
        var state = try ready()
        var ids = Set<String>()
        for index in 1...40 {
            let time = index * 1000
            _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "\(index)s"]], &state, at: time)
            let event = try XCTUnwrap(consume(["serverContent": ["inputTranscription": ["text": String(repeating: "x", count: 1000)]]], &state, at: time + 100).events.first)
            XCTAssertEqual(event["start_ms"] as? Int, time)
            XCTAssertTrue(ids.insert(try XCTUnwrap(event["event_id"] as? String)).inserted)
            _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state, at: time + 200)
            _ = try consume(["serverContent": ["turnComplete": true]], &state, at: time + 300)
        }
    }
    func testFixTextlessFinalMarkersAreOptionalTextAndOnceOnly() throws {
        for speaker in ["inputTranscription", "outputTranscription"] {
            var state = try ready()
            _ = try consume(["serverContent": [speaker: ["text": "hello"]]], &state)
            for _ in 0..<2 { XCTAssertTrue(try consume(["serverContent": [speaker: ["finished": true]]], &state).events.isEmpty) }
            XCTAssertThrowsError(try consume(["serverContent": [speaker: ["text": 3, "finished": true]]], &state))
            if speaker == "inputTranscription" { _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "2s"]], &state) }
            else { _ = try consume(["serverContent": ["turnComplete": true]], &state) }
            XCTAssertEqual(try consume(["serverContent": [speaker: ["text": "new"]]], &state).events.first?["delta"] as? String, "new")
        }
    }

    func testFixTransportSendInterleavingRechecksAtWireAdmission() throws {
        var state = try ready()
        var queue = GeminiLiveProtocol.SendQueue()
        let passive = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "context", "respond": false, "event_id": "passive"])
        XCTAssertTrue(state.canSend(passive))
        XCTAssertTrue(try queue.append(.init(command: passive)))
        // Queued while idle; VAD arrives before the drain task gets to its socket write.
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START"]], &state)
        let entry = try XCTUnwrap(queue.pop())
        var written: [[String: Any]] = []
        if state.beginSend(entry) { written.append(entry.wire) }
        XCTAssertTrue(written.isEmpty)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state)
        XCTAssertFalse(state.beginSend(entry))
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
        XCTAssertTrue(state.beginSend(entry))
        written.append(entry.wire)
        // New activity can arrive while socket.send awaits completion. Its state survives ack.
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START"]], &state)
        let acknowledgement = state.accept(passive)
        XCTAssertFalse(acknowledgement.clearPlayback)
        XCTAssertEqual(acknowledgement.events.first?["client_event_id"] as? String, "passive")
        XCTAssertEqual(written.count, 1)
        XCTAssertFalse(state.canSend(passive))
    }
    func testFixMicrophoneQueueInvalidatesAnEarlierIdleAdmission() throws {
        var state = try ready()
        let passive = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "context", "respond": false])
        XCTAssertTrue(state.canSend(passive))
        state.noteInputQueued()
        XCTAssertFalse(state.beginSend(.init(command: passive)))
        XCTAssertTrue(try state.beginSend(.init(wire: state.audio(Data([0, 0])), isAudio: true)))
        XCTAssertFalse(state.canSend(passive))
    }
    func testFixTextlessFinalAfterOffsetTranscriptFinalizesThatUtterance() throws {
        for speaker in ["inputTranscription", "outputTranscription"] {
            var state = try ready()
            _ = try consume(["serverContent": [speaker: ["text": "hello", "startOffset": "0s", "endOffset": "1s"]]], &state)
            _ = try consume(["serverContent": [speaker: ["finished": true]]], &state)
            XCTAssertTrue(try consume(["serverContent": [speaker: ["text": "hello world", "startOffset": "0s", "endOffset": "2s", "finished": true]]], &state).events.isEmpty)
            _ = try consume(["serverContent": ["turnComplete": true]], &state)
            XCTAssertThrowsError(try consume(["serverContent": [speaker: ["text": 5, "finished": true]]], &state))
        }
    }
    func testFixLateOffsetFinalBelongsToPreviousLearnerActivity() throws {
        var state = try ready()
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "1s"]], &state)
        _ = try consume(["serverContent": ["inputTranscription": ["text": "old", "startOffset": "1s", "endOffset": "2s"]]], &state)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "3s"]], &state)
        _ = try consume(["serverContent": ["inputTranscription": ["text": "new", "startOffset": "3s", "endOffset": "4s"]]], &state)
        let final = try consume(["serverContent": ["inputTranscription": ["text": "old final", "startOffset": "1s", "endOffset": "2s", "finished": true]]], &state)
        XCTAssertEqual(final.events.first?["delta"] as? String, " final")
        XCTAssertEqual(final.events.first?["start_ms"] as? Int, 1000)
    }

    func testFixOldReplyIdleCannotAdmitPassiveOverNewLearnerActivity() throws {
        var state = try ready()
        let passive = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "context", "respond": false])
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "1s"]], &state)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state)
        _ = try consume(["serverContent": ["outputTranscription": ["text": "first reply"]]], &state)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START", "audioOffset": "2s"]], &state)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state)
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
        XCTAssertFalse(state.canSend(passive))
        _ = try consume(["serverContent": ["outputTranscription": ["text": "second reply"]]], &state)
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
        XCTAssertTrue(state.canSend(passive))
    }

    func testFix2SilentCaptureRejectsUnsupportedPassiveInsteadOfQueueingForever() throws {
        var state = try ready()
        let passive = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "pace", "respond": false])
        let responding = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "explain", "respond": true])
        XCTAssertTrue(state.supports(passive))
        for _ in 0..<40 {
            state.noteInputQueued()
            XCTAssertTrue(try state.beginSend(.init(wire: state.audio(Data(repeating: 0, count: 320)), isAudio: true)))
            // Silence does not prove server consumption. The capability is explicitly
            // unavailable; adapters must reject instead of accepting into a waiting queue.
            XCTAssertFalse(state.supports(passive))
            XCTAssertFalse(state.canSend(passive))
            XCTAssertTrue(state.supports(responding))
        }
    }
    func testFix2CapabilityRejectionDoesNotClearRealSpeechPending() throws {
        var state = try ready()
        let passive = try GeminiLiveProtocol.command(["type": "session.thinking.append", "content": "context", "respond": false])
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_START"]], &state)
        _ = try consume(["voiceActivity": ["type": "ACTIVITY_END"]], &state)
        state.noteInputQueued()
        XCTAssertFalse(state.supports(passive))
        XCTAssertFalse(state.beginSend(.init(command: passive)))
        _ = try consume(["serverContent": ["turnComplete": true, "interactionStatus": "IDLE"]], &state)
        XCTAssertFalse(state.supports(passive), "IDLE cannot negotiate a missing passive-update consumption barrier")
        XCTAssertFalse(state.canSend(passive))
    }

    func testFix2AcceptedPassiveGetsOneNonfatalErrorWhenCaptureStartsBeforeSend() throws {
        var state = try ready()
        var queue = GeminiLiveProtocol.SendQueue()
        let passive = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "pace", "respond": false, "event_id": "pending-pace"])
        XCTAssertTrue(try queue.append(.init(command: passive)))
        XCTAssertNil(state.rejection(for: passive))
        state.noteInputQueued()
        let entry = try XCTUnwrap(queue.pop())
        XCTAssertFalse(state.beginSend(entry))
        let rejection = try XCTUnwrap(state.rejection(for: try XCTUnwrap(entry.command)))
        XCTAssertEqual(rejection["type"] as? String, "error")
        let details = try XCTUnwrap(rejection["error"] as? [String: Any])
        XCTAssertEqual(details["client_event_id"] as? String, "pending-pace")
        XCTAssertEqual(details["code"] as? String, "gemini_passive_update_unavailable")
        XCTAssertNil(queue.pop())
        let responding = try GeminiLiveProtocol.command(["type": "session.instructions.append", "content": "reply"])
        XCTAssertNil(state.rejection(for: responding))
        XCTAssertTrue(state.beginSend(.init(command: responding)))
    }

}
