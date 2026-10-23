import Foundation
import CoreFoundation

/// Pure Gemini Live wire validation and normalization. Contains no credentials or audio devices.
public struct GeminiLiveProtocol {
    public static let maximumMessageBytes = 262_144
    public static let socketURL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained")!
    public static let tokenURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/auth_tokens")!
    public enum Failure: Error, Equatable { case malformed, tooLarge, invalidAudio, credential, capability, authentication, billing, rateLimit, unavailable, unsafeResume }
    public struct Update {
        public var events: [[String: Any]] = []
        public var audio: [Data] = []
        public var clearPlayback = false
        public var resumeHandle: String?
        public init() {}
    }
    public private(set) var configured = false
    public private(set) var replyActive = false
    private var hasStarted = false
    private var handle: String?
    // Developer API v1beta has no supported transparent/consumed-message boundary.
    // Once any content was sent, a later-arriving handle cannot prove it includes that content.
    private var outboundUncertain = false
    private var inputPending = false
    private var captureStarted = false
    private var learnerSpeaking = false
    private var resumes = 0
    private var outputCancelled = false
    private var commandSendPending = false
    private var replyObservedSinceOutbound = false
    private var pendingReplyTurn: Int?
    private var outputTurn = 0
    private var outputSessionStart: Int?
    private var inputTurn = 0
    private var replyInputTurn: Int?
    private var sequence = 0
    private var inputStart: Int?
    private var outputStart: Int?
    private var inputFinished = false
    private var outputFinished = false
    private var lastOutputFinal: String?
    private var lastInputFinal: String?
    private var inputText = ""
    private var outputText = ""
    private struct Transcript {
        var text = ""
        var finished = false
        var start: Int
        var end: Int
    }
    private var offsetTranscripts: [String: Transcript] = [:]
    private var offsetOrder: [String] = []
    private var retiredInputOffset = -1
    private var latestInputOffsetKey: String?
    private var latestOutputOffsetKey: String?
    private var lastUsage: Data?
    private let identity = UUID().uuidString
    public init() {}

    public static func checkedSecret(_ value: String, limit: Int = 8192) throws -> String {
        guard !value.isEmpty, value.utf8.count <= limit, value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { throw Failure.credential }
        return value
    }
    public static func tokenBody(now: Date) throws -> [String: Any] {
        guard now.timeIntervalSince1970.isFinite, (0...9_000_000_000).contains(now.timeIntervalSince1970) else { throw Failure.malformed }
        let format = ISO8601DateFormatter()
        return ["uses": 1, "newSessionExpireTime": format.string(from: now.addingTimeInterval(60)), "expireTime": format.string(from: now.addingTimeInterval(65 * 60))]
    }
    public static func token(from data: Data) throws -> String {
        let object = try object(data)
        guard let value = object["name"] as? String else { throw Failure.credential }
        return try checkedSecret(value)
    }
    public static func setup(instructions: String, hasHistory: Bool, resumeHandle: String? = nil) throws -> [String: Any] {
        guard instructions.utf8.count <= 65_536 else { throw Failure.tooLarge }
        var setup: [String: Any] = ["model": "models/gemini-3.8-live", "generationConfig": ["responseModalities": ["AUDIO"]],
            "systemInstruction": ["parts": [["text": instructions]]], "inputAudioTranscription": [:], "outputAudioTranscription": [:],
            "sessionResumption": [:], "contextWindowCompression": ["slidingWindow": [:]],
            "realtimeInputConfig": ["automaticActivityDetection": ["disabled": false], "activityHandling": "START_OF_ACTIVITY_INTERRUPTS"]]
        if let resumeHandle { setup["sessionResumption"] = ["handle": try checkedSecret(resumeHandle)] }
        else if hasHistory { setup["historyConfig"] = ["initialHistoryInClientContent": true] }
        return ["setup": setup]
    }
    public static func history(_ history: [[String: Any]]) throws -> [String: Any]? {
        guard history.count <= 40, JSONSerialization.isValidJSONObject(history), try JSONSerialization.data(withJSONObject: history).count <= 6000 else { throw Failure.tooLarge }
        guard !history.isEmpty else { return nil }
        let turns = try history.map { item -> [String: Any] in
            guard let role = item["role"] as? String, ["user", "assistant", "system"].contains(role),
                  let content = item["content"] as? [[String: Any]], !content.isEmpty else { throw Failure.malformed }
            let parts = try content.map { part -> [String: Any] in
                guard let text = part["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.malformed }
                return ["text": role == "system" ? "Conversation context: " + text : text]
            }
            return ["role": role == "assistant" ? "model" : "user", "parts": parts]
        }
        return ["clientContent": ["turns": turns, "turnComplete": true]]
    }
    public func audio(_ pcm: Data) throws -> [String: Any] {
        guard configured else { throw Failure.malformed }
        guard !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 32_000 else { throw Failure.invalidAudio }
        return ["realtimeInput": ["audio": ["mimeType": "audio/pcm;rate=16000", "data": pcm.base64EncodedString()]]]
    }
    public struct Command {
        public let wire: [String: Any]
        public let id: String
        public let type: String
        public let respond: Bool
    }
    public static func command(_ event: [String: Any]) throws -> Command {
        guard let type = event["type"] as? String, ["session.instructions.append", "session.thinking.append", "session.commentary.append"].contains(type),
              let content = event["content"] as? String, !content.isEmpty, content.utf8.count <= 8192 else { throw Failure.malformed }
        let respond = try boolean(event["respond"], default: true)
        let id = try checkedSecret(event["event_id"] as? String ?? UUID().uuidString, limit: 256)
        let prefix = type == "session.instructions.append" ? "Conversation instructions: " : type == "session.thinking.append" ? "Reference data: " : "Conversation context: "
        return Command(wire: ["clientContent": ["turns": [["role": "user", "parts": [["text": prefix + content]]]], "turnComplete": respond]], id: id, type: type, respond: respond)
    }
    /// Developer API has no consumed-audio barrier for safely inserting passive
    /// clientContent during continuous capture. Do not accept work we cannot safely send.
    public func supports(_ command: Command) -> Bool { command.respond || !captureStarted }
    public func rejection(for command: Command) -> [String: Any]? {
        guard !supports(command) else { return nil }
        return ["type": "error", "error": ["code": "gemini_passive_update_unavailable",
            "client_event_id": command.id, "message": "Live learning-plan updates apply at your next conversation."]]
    }
    public func canSend(_ command: Command) -> Bool {
        configured && supports(command) && (command.respond || (!replyActive && !inputPending && !learnerSpeaking && !commandSendPending))
    }
    /// Called only after the WebSocket send completes successfully.
    public mutating func accept(_ command: Command) -> Update {
        var update = Update()
        if command.respond {
            // A new reply may arrive while the WebSocket send continuation is suspended.
            // Its audio has already reached playback by the time this acknowledgement runs.
            if !(commandSendPending && replyObservedSinceOutbound) {
                update.clearPlayback = true
                // Ignore trailing output from the previous generation until its boundary.
                if replyActive && (pendingReplyTurn.map { outputTurn < $0 } ?? true) { outputCancelled = true }
                replyActive = true
            }
            // Otherwise the receive path owns the state, including a completed/idle
            // reply. A delayed acknowledgement must not resurrect that generation.
        }
        noteOutbound()
        commandSendPending = false; replyObservedSinceOutbound = false; pendingReplyTurn = nil
        update.events = [["type": command.type.replacingOccurrences(of: ".append", with: ".appended"), "client_event_id": command.id]]
        return update
    }
    /// Called synchronously when capture enters the send queue, before a drain can admit
    /// a previously queued passive command against an older idle observation.
    public mutating func noteInputQueued() { captureStarted = true; inputPending = true; handle = nil }
    /// The adapter's final synchronous admission boundary immediately before socket.send.
    /// Tests can interleave inbound events between enqueue, admission and send completion.
    public mutating func beginSend(_ entry: SendQueue.Entry) -> Bool {
        guard configured else { return false }
        if let command = entry.command {
            guard canSend(command) else { return false }
            beginCommandSend()
        } else {
            if entry.isAudio { noteInputQueued() }
            noteOutbound()
        }
        return true
    }
    public mutating func noteOutbound() { handle = nil; outboundUncertain = true }
    public mutating func beginCommandSend() {
        noteOutbound(); commandSendPending = true; replyObservedSinceOutbound = false
        // Output from a reply already active at admission still belongs to the old
        // generation until its turnComplete boundary, even if it arrives during send.
        pendingReplyTurn = outputTurn + (replyActive ? 1 : 0)
    }
    public mutating func beginResume() throws {
        guard handle != nil, !outboundUncertain, !replyActive, !inputPending, resumes < 6 else { throw Failure.unsafeResume }
        resumes += 1; configured = false; handle = nil
    }
    public static func failure(status: Int?, started: Bool) -> Failure {
        switch status {
        case 404, 501: return started ? .unavailable : .capability
        case 401, 403: return .authentication
        case 402: return .billing
        case 429: return .rateLimit
        default: return .unavailable
        }
    }
    public mutating func consume(_ data: Data, elapsedMS: Int) throws -> Update {
        guard elapsedMS >= 0 else { throw Failure.malformed }
        let event = try Self.object(data)
        var update = Update()
        if let error = event["error"] as? [String: Any] {
            let code = try Self.integer(error["code"])
            throw Self.failure(status: code, started: hasStarted)
        }
        if event["setupComplete"] != nil {
            guard event["setupComplete"] is [String: Any] else { throw Failure.malformed }
            configured = true
            if !hasStarted {
                hasStarted = true
                update.events.append(["type": "session.started", "session": ["id": "gemini-" + identity]])
            }
        }
        if let resumption = event["sessionResumptionUpdate"] as? [String: Any] {
            handle = nil
            if try Self.boolean(resumption["resumable"], default: false), !replyActive, !inputPending, !outboundUncertain {
                guard let value = resumption["newHandle"] as? String else { throw Failure.malformed }
                handle = try Self.checkedSecret(value)
            }
        }
        if event["goAway"] != nil {
            guard configured, !outboundUncertain, !replyActive, !inputPending, let handle, resumes < 6 else { throw Failure.unsafeResume }
            update.resumeHandle = handle
        }
        if let activity = event["voiceActivity"] as? [String: Any] {
            let type = activity["type"] as? String
            if type == "ACTIVITY_START" {
                handle = nil; inputPending = true; learnerSpeaking = true
                // ASR lifecycle follows learner activity, never the model's output turn.
                // Offset-addressed older transcripts remain independently addressable below.
                inputTurn += 1; inputFinished = false; lastInputFinal = nil; inputText = ""; latestInputOffsetKey = nil
                inputStart = activity["audioOffset"] == nil ? elapsedMS : try Self.offset(activity["audioOffset"])
            } else if type == "ACTIVITY_END" {
                learnerSpeaking = false; inputPending = true
            }
        }
        if let content = event["serverContent"] as? [String: Any] {
            guard configured else { throw Failure.malformed }
            let interrupted = try Self.boolean(content["interrupted"], default: false)
            let completed = try Self.boolean(content["turnComplete"], default: false)
            if interrupted { outputCancelled = true; update.clearPlayback = true; handle = nil }
            if let input = content["inputTranscription"] as? [String: Any] {
                inputPending = true
                update.events += try transcript(input, output: false, elapsed: elapsedMS)
            }
            if !outputCancelled {
                if commandSendPending, outputTurn >= (pendingReplyTurn ?? outputTurn),
                   content["outputTranscription"] != nil || content["modelTurn"] != nil {
                    replyObservedSinceOutbound = true
                }
                if let output = content["outputTranscription"] as? [String: Any] {
                    let events = try transcript(output, output: true, elapsed: elapsedMS)
                    if !events.isEmpty { replyInputTurn = replyInputTurn ?? inputTurn; replyActive = true; handle = nil }
                    update.events += events
                }
                if let turn = content["modelTurn"] as? [String: Any] {
                    if !replyActive { lastOutputFinal = nil }
                    replyInputTurn = replyInputTurn ?? inputTurn
                    replyActive = true; handle = nil
                    guard let parts = turn["parts"] as? [[String: Any]], parts.count <= 64 else { throw Failure.malformed }
                    var total = 0
                    for part in parts {
                        guard let blob = part["inlineData"] as? [String: Any] else { continue }
                        guard blob["mimeType"] as? String == "audio/pcm;rate=24000", let encoded = blob["data"] as? String,
                              encoded.utf8.count <= 128_000, let pcm = Data(base64Encoded: encoded),
                              !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 96_000 else { throw Failure.invalidAudio }
                        total += pcm.count
                        guard total <= 96_000 else { throw Failure.invalidAudio }
                        outputSessionStart = outputSessionStart ?? elapsedMS
                        update.audio.append(pcm)
                    }
                }
            }
            if completed {
                // Even an empty new reply can finish before send returns. An old
                // generation's boundary must not settle the pending command instead.
                if commandSendPending, outputTurn >= (pendingReplyTurn ?? outputTurn) {
                    replyObservedSinceOutbound = true
                }
                replyActive = content["interactionStatus"] as? String == "IN_PROGRESS"
                if !replyActive {
                    if !learnerSpeaking, replyInputTurn == nil || replyInputTurn == inputTurn { inputPending = false }
                    replyInputTurn = nil
                }
                outputCancelled = false; outputTurn += 1
                outputSessionStart = nil
                outputStart = nil; outputFinished = false; outputText = ""; latestOutputOffsetKey = nil
            }
        }
        if let usage = event["usageMetadata"] as? [String: Any] {
            let canonical = try JSONSerialization.data(withJSONObject: usage, options: .sortedKeys)
            let input = try Self.integer(usage["promptTokenCount"]), output = try Self.integer(usage["responseTokenCount"])
            if canonical != lastUsage {
                lastUsage = canonical
                // Coordinator voice accounting is elapsed time, not repeated token accumulation.
                update.events.append(["type": "session.usage.updated", "usage": ["seconds": Double(elapsedMS) / 1000, "input_tokens": input, "output_tokens": output]])
            }
        }
        return update
    }
    private mutating func transcript(_ value: [String: Any], output: Bool, elapsed sessionElapsed: Int) throws -> [[String: Any]] {
        // Output offsets address audio within one generation, not the session.
        // Keep transcript identity/finalization in that relative clock and translate
        // only emitted timestamps. Optional-offset fallbacks use the same clock.
        let sessionStart = output ? (outputSessionStart ?? sessionElapsed) : 0
        let elapsed = max(0, sessionElapsed - sessionStart)
        let finished = try Self.boolean(value["finished"], default: false)
        let rawText: String
        if let supplied = value["text"] {
            guard let text = supplied as? String else { throw Failure.malformed }
            rawText = text
        } else {
            guard finished else { throw Failure.malformed }
            rawText = ""
        }
        guard rawText.utf8.count <= 32_768 else { throw Failure.tooLarge }
        let prefix = output ? "output" : "input"
        let key: String
        var stream: Transcript
        let hasOffsets = value["startOffset"] != nil || value["endOffset"] != nil
        let latestOffsetKey = output ? latestOutputOffsetKey : latestInputOffsetKey
        let finalizesOffset = !hasOffsets && finished && latestOffsetKey != nil
        if hasOffsets {
            let providedStart = try value["startOffset"].map { try Self.offset($0) }
            let providedEnd = try value["endOffset"].map { try Self.offset($0) }
            let start = providedStart ?? min(elapsed, providedEnd ?? elapsed)
            let end = providedEnd ?? max(start, elapsed)
            guard end >= start else { throw Failure.malformed }
            // End offsets may extend in a final. The start anchor identifies the utterance.
            key = "\(prefix):\(output ? String(outputTurn) : "stream"):offset:\(start)"
            if !output, offsetTranscripts[key] == nil, start <= retiredInputOffset { return [] }
            stream = offsetTranscripts[key] ?? Transcript(start: start, end: end)
            stream.end = max(stream.end, end)
        } else if finalizesOffset, let latestOffsetKey, let previous = offsetTranscripts[latestOffsetKey] {
            key = latestOffsetKey; stream = previous
        } else if output {
            guard !(outputStart == nil && finished && (rawText.isEmpty || rawText == lastOutputFinal)) else { return [] }
            key = "output:\(outputTurn)"
            stream = Transcript(text: outputText, finished: outputFinished, start: outputStart ?? elapsed, end: max(outputStart ?? elapsed, elapsed))
        } else {
            if inputFinished {
                if finished, rawText.isEmpty || rawText == lastInputFinal { return [] }
                inputTurn += 1; inputFinished = false; inputStart = nil; inputText = ""
            }
            key = "input:\(inputTurn)"
            stream = Transcript(text: inputText, finished: inputFinished, start: inputStart ?? elapsed, end: max(inputStart ?? elapsed, elapsed))
        }
        let delta = try Self.appendTranscript(rawText, finished: finished, cumulative: hasOffsets || finalizesOffset, to: &stream)
        if hasOffsets || finalizesOffset {
            if output { latestOutputOffsetKey = key }
            else if stream.start >= (inputStart ?? 0) { latestInputOffsetKey = key }
            if offsetTranscripts[key] == nil { offsetOrder.append(key) }
            offsetTranscripts[key] = stream
            // Retain bounded recent utterances for delayed finals. Retired input offsets
            // are dropped instead of replaying old evidence after eviction.
            if offsetOrder.count > 128 {
                let retired = offsetOrder.removeFirst()
                if let old = offsetTranscripts.removeValue(forKey: retired), retired.hasPrefix("input:") { retiredInputOffset = max(retiredInputOffset, old.start) }
            }
        } else if output {
            latestOutputOffsetKey = nil
            outputStart = stream.start; outputText = stream.text; outputFinished = stream.finished
            if finished { lastOutputFinal = rawText }
        } else {
            latestInputOffsetKey = nil
            inputStart = stream.start; inputText = stream.text; inputFinished = stream.finished
            if finished { lastInputFinal = rawText }
        }
        guard !delta.isEmpty else { return [] }
        guard stream.end <= Int.max - sessionStart else { throw Failure.malformed }
        if output { outputSessionStart = sessionStart }
        sequence += 1
        return [["type": "session.\(prefix)_transcript.delta", "event_id": "gemini:\(identity):\(key):\(sequence)", "delta": delta, "start_ms": sessionStart + stream.start, "end_ms": sessionStart + stream.end]]
    }
    private static func appendTranscript(_ raw: String, finished: Bool, cumulative: Bool, to stream: inout Transcript) throws -> String {
        guard !stream.finished else { return "" }
        var delta = raw
        if cumulative || finished {
            if raw.hasPrefix(stream.text) { delta = String(raw.dropFirst(stream.text.count)) }
            else if cumulative { delta = "" } // Append-only coordinator cannot replace a divergent revision.
        }
        guard stream.text.utf8.count + delta.utf8.count <= 32_768 else { throw Failure.tooLarge }
        stream.text += delta; stream.finished = finished
        return delta
    }
    private static func offset(_ value: Any?) throws -> Int {
        guard let text = value as? String, text.hasSuffix("s"), text.utf8.count < 32, let seconds = Double(text.dropLast()),
              seconds.isFinite, seconds >= 0, seconds <= Double(Int32.max) / 1000 else { throw Failure.malformed }
        return Int((seconds * 1000).rounded())
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumMessageBytes else { throw Failure.tooLarge }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure.malformed }
        return object
    }
    private static func boolean(_ value: Any?, default fallback: Bool) throws -> Bool {
        guard let value else { return fallback }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Failure.malformed }
        return number.boolValue
    }
    private static func integer(_ value: Any?) throws -> Int {
        guard let value else { return 0 }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max), number.doubleValue.rounded(.down) == number.doubleValue else { throw Failure.malformed }
        return number.intValue
    }
    public struct SendQueue {
        public struct Entry {
            public let wire: [String: Any]
            public let command: Command?
            public let isAudio: Bool
            public init(wire: [String: Any], isAudio: Bool = false) { self.wire = wire; command = nil; self.isAudio = isAudio }
            public init(command: Command) { wire = command.wire; self.command = command; isAudio = false }
        }
        private var entries: [(Entry, Int)] = []
        private var bytes = 0
        public init() {}
        public var count: Int { entries.count }
        public var hasCommands: Bool { entries.contains { $0.0.command != nil } }
        public var first: Entry? { entries.first?.0 }
        public mutating func append(_ entry: Entry) throws -> Bool {
            guard JSONSerialization.isValidJSONObject(entry.wire) else { throw Failure.malformed }
            let size = try JSONSerialization.data(withJSONObject: entry.wire).count
            guard size <= maximumMessageBytes else { throw Failure.tooLarge }
            guard count < 32, bytes + size <= 1_048_576,
                  entry.command == nil || entries.filter({ $0.0.command != nil }).count < 16 else { return false }
            entries.append((entry, size)); bytes += size; return true
        }
        public mutating func pop() -> Entry? {
            guard !entries.isEmpty else { return nil }
            let entry = entries.removeFirst(); bytes -= entry.1; return entry.0
        }
        public mutating func discardAudio() {
            entries.removeAll { $0.0.isAudio }; bytes = entries.reduce(0) { $0 + $1.1 }
        }
    }
}
