import Foundation
import CoreFoundation
import CryptoKit

/// Offline framing and event normalization for BigModel's native realtime API.
public struct GLMRealtimeProtocol {
    public enum Failure: Error, Equatable, Sendable {
        case credential, malformed, tooLarge, invalidAudio
        case capability, authentication, billing, rateLimit, unavailable, invalidRequest
    }
    public struct Update {
        public var events: [[String: Any]] = []
        public var audio: Data?
        public var clearPlayback = false
        public var responseCompleted = false
    }
    public static let socketURL = URL(string: "wss://open.bigmodel.cn/api/paas/v4/realtime")!
    public static let maximumMessageBytes = 262_144
    public static let outputSampleRate = 24_000.0
    private var instructions: String
    public private(set) var configured = false
    private struct Transcript {
        var text = ""
        var final = false
        var start: Int
        var end: Int
        var sequence = 0
    }
    private var transcripts: [String: Transcript] = [:]
    private var responseStarts: [String: Int] = [:]
    private var activeResponses: Set<String> = []
    private var cancelledResponses: Set<String> = []
    private var finishedResponses: Set<String> = []
    private var playbackResponse: String?
    private var seenTranscriptEvents: Set<String> = []
    private var seenOrder: [String] = []
    private var inputTimes: [String: (Int, Int)] = [:]
    private var pendingInputTimes: [(Int, Int)] = []
    private var speechStart: Int?
    private var speechItem: String?

    public init(instructions: String = "") { self.instructions = instructions }

    /// The SDK's JWT example uses epoch seconds for exp, epoch milliseconds for timestamp.
    public static func token(key: String, now: TimeInterval, lifetime: Int = 600) throws -> String {
        let pieces = key.split(separator: ".", omittingEmptySubsequences: false)
        guard key.utf8.count <= 4096, pieces.count == 2, pieces.allSatisfy({ !$0.isEmpty }),
              key.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              now.isFinite, now >= 0, now < 9_000_000_000_000,
              (1...3600).contains(lifetime) else { throw Failure.credential }
        let header = try JSONSerialization.data(withJSONObject: ["alg": "HS256", "sign_type": "SIGN"], options: .sortedKeys)
        let payload = try JSONSerialization.data(withJSONObject: ["api_key": String(pieces[0]), "exp": Int64(now) + Int64(lifetime), "timestamp": Int64(now * 1000)], options: .sortedKeys)
        let input = base64URL(header) + "." + base64URL(payload)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(input.utf8), using: SymmetricKey(data: Data(pieces[1].utf8)))
        return input + "." + base64URL(Data(signature))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    /// Every chunk is an independent mono, little-endian PCM16 WAV file, at 16 kHz.
    public static func wav(pcm: Data) throws -> Data {
        guard !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 32_000 else { throw Failure.invalidAudio }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(16_000))
        append(UInt32(32_000)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }
    public static func configuration(instructions: String) throws -> [String: Any] {
        guard instructions.utf8.count <= 65_536 else { throw Failure.tooLarge }
        return ["type": "session.update", "session": [
            "modalities": ["audio", "text"], "input_audio_format": "wav", "output_audio_format": "pcm",
            "instructions": instructions, "turn_detection": ["type": "server_vad"],
            "beta_fields": ["chat_mode": "audio", "tts_source": "e2e", "auto_search": false], "tools": []
        ]]
    }
    public static func historyCommands(_ history: [[String: Any]]) throws -> [[String: Any]] {
        guard history.count <= 40, JSONSerialization.isValidJSONObject(history),
              try JSONSerialization.data(withJSONObject: history).count <= 6_000 else { throw Failure.tooLarge }
        return try history.map { item in
            guard let role = item["role"] as? String, ["user", "assistant", "system"].contains(role),
                  let parts = item["content"] as? [[String: Any]], !parts.isEmpty else { throw Failure.malformed }
            let content: [[String: Any]] = try parts.map { part in
                guard let text = part["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.malformed }
                return ["type": role == "assistant" ? "text" : "input_text", "text": text]
            }
            return ["type": "conversation.item.create", "item": ["id": "history-" + UUID().uuidString,
                    "type": "message", "role": role, "content": content]]
        }
    }
    /// Context commands never emit learner transcripts: typed learner evidence is already local.
    public mutating func commands(_ event: [String: Any]) throws -> [[String: Any]] {
        guard let type = event["type"] as? String else { throw Failure.malformed }
        if type == "response.cancel" { cancelResponses(); return [["type": type]] }
        guard ["session.instructions.append", "session.thinking.append", "session.commentary.append"].contains(type),
              let content = event["content"] as? String, !content.isEmpty, content.utf8.count <= 8_192 else { throw Failure.malformed }
        let respond: Bool
        if let value = event["respond"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Failure.malformed }
            respond = number.boolValue
        } else { respond = true }
        var result: [[String: Any]] = []
        if respond {
            if !activeResponses.isEmpty { cancelResponses(includeBufferedResponse: false); result.append(["type": "response.cancel"]) }
            else if playbackResponse != nil {
                // Generation can be finished while its PCM is still queued locally.
                // Keep a completed response eligible for its late final transcript.
                playbackResponse = nil
                result.append(["type": "client.playback.clear"])
            }
        }
        if type == "session.instructions.append" {
            let next = instructions.isEmpty ? content : instructions + "\n" + content
            result.append(try Self.configuration(instructions: next)); instructions = next
        } else {
            let prefix = type == "session.thinking.append" ? "Reference data: " : "Conversation context: "
            result.append(["type": "conversation.item.create", "item": ["id": "context-" + UUID().uuidString,
                          "type": "message", "role": "system", "content": [["type": "input_text", "text": prefix + content]]]])
        }
        if respond { result.append(["type": "response.create"]) }
        return result
    }
    /// Only documented business codes identify capability denial, never provider message text.
    public static func failure(code: String?) -> Failure {
        switch code {
        case "1212", "1220", "1311": return .capability
        case "1000", "1001", "1003", "1005": return .authentication
        case "1113", "1309", "1310", "1314", "1315", "1316", "1317", "1318", "1319", "1320", "1321": return .billing
        case "1302", "1305", "1308", "1313": return .rateLimit
        case "1200", "1230", "1234": return .unavailable
        default: return .invalidRequest
        }
    }
    public mutating func consume(_ data: Data, elapsedMS: Int) throws -> Update {
        guard data.count <= Self.maximumMessageBytes else { throw Failure.tooLarge }
        guard elapsedMS >= 0, let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String, !type.isEmpty else { throw Failure.malformed }
        var result = Update()
        switch type {
        case "error":
            let error = event["error"] as? [String: Any]
            let code = (error?["code"] as? String) ?? (error?["code"] as? NSNumber)?.stringValue
            throw Self.failure(code: code)
        case "session.updated":
            guard !configured, let session = event["session"] as? [String: Any],
                  session["input_audio_format"] as? String == "wav", session["output_audio_format"] as? String == "pcm",
                  (session["turn_detection"] as? [String: Any])?["type"] as? String == "server_vad",
                  let beta = session["beta_fields"] as? [String: Any], beta["chat_mode"] as? String == "audio",
                  let search = beta["auto_search"] as? NSNumber, CFGetTypeID(search) == CFBooleanGetTypeID(), !search.boolValue else { return result }
            configured = true
            result.events = [["type": "session.started", "session": ["id": session["id"] as? String ?? "glm-native"]]]
        case "input_audio_buffer.speech_started":
            cancelResponses(); result.clearPlayback = true
            speechStart = try Self.time(event["audio_start_ms"], fallback: elapsedMS)
            speechItem = event["item_id"] as? String
            if let speechItem, let speechStart { try recordInputTime(speechItem, start: speechStart, end: speechStart) }
        case "input_audio_buffer.speech_stopped":
            let end = try Self.time(event["audio_end_ms"], fallback: elapsedMS)
            let start = min(speechStart ?? end, end)
            if let id = event["item_id"] as? String ?? speechItem { try recordInputTime(id, start: start, end: end) }
            else {
                guard pendingInputTimes.count < 128 else { throw Failure.tooLarge }
                pendingInputTimes.append((start, end))
            }
            speechStart = nil; speechItem = nil
        case "input_audio_buffer.committed":
            if let id = event["item_id"] as? String, !pendingInputTimes.isEmpty {
                let time = pendingInputTimes.removeFirst(); try recordInputTime(id, start: time.0, end: time.1)
            }
        case "conversation.item.input_audio_transcription.completed":
            let id = try Self.identity(event["item_id"])
            if inputTimes[id] == nil, !pendingInputTimes.isEmpty {
                let time = pendingInputTimes.removeFirst(); try recordInputTime(id, start: time.0, end: time.1)
            }
            let time = inputTimes[id] ?? (elapsedMS, elapsedMS)
            result.events = try transcript(event, key: "input:" + id, output: false, final: true, start: time.0, end: time.1)
        case "response.created":
            guard let response = event["response"] as? [String: Any] else { throw Failure.malformed }
            let id = try Self.identity(response["id"])
            guard responseStarts.count < 1_024 || responseStarts[id] != nil else { throw Failure.tooLarge }
            if !cancelledResponses.contains(id), !finishedResponses.contains(id) {
                activeResponses.insert(id); responseStarts[id] = elapsedMS
            }
        case "response.audio.delta", "response.audio_transcript.delta", "response.audio_transcript.done":
            let id = try Self.identity(event["response_id"])
            guard !cancelledResponses.contains(id) else { return result }
            if type == "response.audio.delta", finishedResponses.contains(id) { return result }
            guard responseStarts.count < 1_024 || responseStarts[id] != nil else { throw Failure.tooLarge }
            if !finishedResponses.contains(id) { activeResponses.insert(id) }
            if responseStarts[id] == nil { responseStarts[id] = elapsedMS }
            if type == "response.audio.delta" {
                guard let encoded = event["delta"] as? String, encoded.utf8.count <= 128_000,
                      let pcm = Data(base64Encoded: encoded), !pcm.isEmpty, pcm.count % 2 == 0,
                      pcm.count <= 96_000 else { throw Failure.invalidAudio }
                result.audio = pcm
                playbackResponse = id
            } else {
                let output = try Self.index(event["output_index"]), content = try Self.index(event["content_index"])
                let key = "output:\(id):\(output):\(content)"
                result.events = try transcript(event, key: key, output: true, final: type.hasSuffix(".done"), start: responseStarts[id] ?? elapsedMS, end: elapsedMS)
            }
        case "response.done":
            guard let response = event["response"] as? [String: Any], let status = response["status"] as? String else { throw Failure.malformed }
            let id = try Self.identity(response["id"])
            guard !finishedResponses.contains(id) else { return result }
            guard finishedResponses.count < 1_024 else { throw Failure.tooLarge }
            activeResponses.remove(id); finishedResponses.insert(id)
            result.responseCompleted = status == "completed" && !cancelledResponses.contains(id)
            if !result.responseCompleted {
                cancelledResponses.insert(id)
                result.clearPlayback = playbackResponse == nil || playbackResponse == id
            }
            if let usage = response["usage"] as? [String: Any] {
                let input = try Self.index(usage["input_tokens"]), output = try Self.index(usage["output_tokens"])
                result.events = [["type": "session.usage.updated", "usage": ["seconds": Double(elapsedMS) / 1000, "input_tokens": input, "output_tokens": output]]]
            }
        default: break // audio.done/transcript.done alone never prove response completion.
        }
        return result
    }
    private mutating func cancelResponses(includeBufferedResponse: Bool = true) {
        cancelledResponses.formUnion(activeResponses); activeResponses.removeAll()
        if includeBufferedResponse, let playbackResponse { cancelledResponses.insert(playbackResponse) }
        playbackResponse = nil
    }
    private mutating func recordInputTime(_ id: String, start: Int, end: Int) throws {
        _ = try Self.identity(id)
        guard inputTimes.count < 1_024 || inputTimes[id] != nil else { throw Failure.tooLarge }
        inputTimes[id] = (start, end)
    }
    private mutating func transcript(_ event: [String: Any], key: String, output: Bool, final: Bool, start: Int, end: Int) throws -> [[String: Any]] {
        guard let value = event[final ? "transcript" : "delta"] as? String, value.utf8.count <= 32_768 else { throw Failure.malformed }
        if let id = event["event_id"] as? String {
            let identity = key + ":" + (try Self.identity(id))
            guard seenTranscriptEvents.insert(identity).inserted else { return [] }
            seenOrder.append(identity)
            if seenOrder.count > 2_048 { seenTranscriptEvents.remove(seenOrder.removeFirst()) }
        }
        guard transcripts.count < 2_048 || transcripts[key] != nil else { throw Failure.tooLarge }
        var stream = transcripts[key] ?? Transcript(start: start, end: max(start, end))
        guard !stream.final else { return [] }
        var text = value
        if final {
            stream.final = true
            // A divergent ASR final is not another utterance; never append the full text twice.
            text = value.hasPrefix(stream.text) ? String(value.dropFirst(stream.text.count)) : ""
        }
        guard stream.text.utf8.count + text.utf8.count <= 32_768 else { throw Failure.tooLarge }
        stream.text += text; stream.end = max(stream.end, end); stream.sequence += 1
        transcripts[key] = stream
        guard !text.isEmpty else { return [] }
        return [["type": output ? "session.output_transcript.delta" : "session.input_transcript.delta",
                 "event_id": "glm:\(key):\(stream.sequence)", "delta": text, "start_ms": stream.start, "end_ms": stream.end]]
    }
    private static func identity(_ value: Any?) throws -> String {
        guard let id = value as? String, !id.isEmpty, id.utf8.count <= 256,
              id.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { throw Failure.malformed }
        return id
    }
    private static func index(_ value: Any?) throws -> Int {
        guard let value else { return 0 }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= Double(Int32.max),
              number.doubleValue.rounded(.down) == number.doubleValue else { throw Failure.malformed }
        return number.intValue
    }
    private static func time(_ value: Any?, fallback: Int) throws -> Int { value == nil ? fallback : try index(value) }

    public struct StartupGate {
        private var configured = false
        private var pending: Set<String>
        public init(historyIDs: [String]) { pending = Set(historyIDs) }
        public var ready: Bool { configured && pending.isEmpty }
        public mutating func acceptConfiguration() { configured = true }
        public mutating func acceptHistory(_ id: String) { pending.remove(id) }
    }

    public struct ResponseGate {
        private var pending: UUID?
        public init() {}
        public mutating func request() -> UUID { let id = UUID(); pending = id; return id }
        public mutating func cancel() { pending = nil }
        public mutating func consume(_ id: UUID) -> Bool {
            guard pending == id else { return false }
            pending = nil; return true
        }
    }

    /// Atomic batches prevent accepting half a context update under backpressure.
    public struct SendQueue {
        private var pending: [String] = []
        private var bytes = 0
        public init() {}
        public var count: Int { pending.count }
        public func frames(_ events: [[String: Any]]) throws -> [String] {
            try events.map { event in
                guard JSONSerialization.isValidJSONObject(event) else { throw Failure.malformed }
                let data = try JSONSerialization.data(withJSONObject: event)
                guard data.count <= GLMRealtimeProtocol.maximumMessageBytes else { throw Failure.tooLarge }
                guard let value = String(data: data, encoding: .utf8) else { throw Failure.malformed }
                return value
            }
        }
        public mutating func append(_ events: [[String: Any]]) throws -> Bool {
            let batch = try frames(events), size = batch.reduce(0) { $0 + $1.utf8.count }
            guard pending.count + batch.count <= 32, bytes + size <= 1_048_576 else { return false }
            pending.append(contentsOf: batch); bytes += size; return true
        }
        public mutating func pop() -> String? {
            guard !pending.isEmpty else { return nil }
            let value = pending.removeFirst(); bytes -= value.utf8.count; return value
        }
        public mutating func discardMicrophoneAudio() {
            discard(type: "input_audio_buffer.append")
        }
        public mutating func discardResponseRequests() { discard(type: "response.create") }
        private mutating func discard(type: String) {
            pending.removeAll { frame in
                let event = (try? JSONSerialization.jsonObject(with: Data(frame.utf8))) as? [String: Any]
                return event?["type"] as? String == type
            }
            bytes = pending.reduce(0) { $0 + $1.utf8.count }
        }
    }
}
