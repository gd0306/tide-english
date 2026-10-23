import Foundation

/// Timestamped recognition segments form one turn; final segments do not commit it.
public struct VoiceSegmentTranscript: Sendable {
    private struct Segment: Sendable {
        let text: String
        let startMS: Int
        let endMS: Int
        let isFinal: Bool
    }
    private var segments: [Segment] = []
    public private(set) var text = ""
    public init() {}

    @discardableResult public mutating func update(text: String, startMS: Int, endMS: Int, isFinal: Bool) -> String {
        guard startMS >= 0, endMS > startMS else { return self.text }
        let bounded = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !bounded.isEmpty else { return self.text }
        // Half-open ranges keep adjacent phrases distinct. Final evidence wins over
        // late volatile callbacks; a newer final may correct the same audio range.
        let overlaps: (Segment) -> Bool = { $0.startMS < endMS && startMS < $0.endMS }
        if !isFinal && segments.contains(where: { $0.isFinal && overlaps($0) }) {
            return self.text
        }
        segments.removeAll(where: overlaps)
        segments.append(Segment(text: bounded, startMS: startMS, endMS: endMS, isFinal: isFinal))
        segments.sort { $0.startMS < $1.startMS }
        // Retain earliest evidence, matching VoiceTurnState's chronological prefix.
        if segments.count > 128 { segments.removeLast(segments.count - 128) }
        self.text = String(segments.map(\.text).joined(separator: " ").prefix(2000))
        return self.text
    }
}

/// Local speech startup keeps permission order and stale connections consistent.
public enum LocalSpeechPreparation {
    @MainActor public static func prepare(
        requestSpeechAuthorization: () async -> Bool,
        requestMicrophonePermission: () async -> Bool,
        recognitionAvailable: () -> Bool,
        isCurrent: () -> Bool
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        let speech = await requestSpeechAuthorization()
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        guard speech else { return false }
        let microphone = await requestMicrophonePermission()
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        guard microphone else { return false }
        return recognitionAvailable()
    }
}

/// One recognition turn. Generations reject late callbacks after output, mute or teardown.
public struct VoiceTurnState: Sendable {
    private var generation: UInt64 = 0
    private var active = false
    private var pending = ""
    private var muted = false
    private var outputActive = false
    private var requestActive = false
    public init() {}
    public var canListen: Bool { !muted && !outputActive && !requestActive }

    @discardableResult public mutating func begin() -> UInt64 {
        generation &+= 1
        active = canListen
        pending = ""
        return generation
    }
    @discardableResult public mutating func update(_ text: String, generation: UInt64) -> Bool {
        guard active, generation == self.generation else { return false }
        let bounded = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard bounded != pending else { return false }
        pending = bounded
        return true
    }
    public mutating func commit(generation: UInt64) -> String? {
        guard active, generation == self.generation else { return nil }
        active = false
        let text = pending
        pending = ""
        return text.isEmpty ? nil : text
    }
    public mutating func cancel() {
        generation &+= 1
        active = false
        pending = ""
    }
    public mutating func setMuted(_ value: Bool) {
        guard value != muted else { return }
        muted = value
        cancel()
    }
    public mutating func setOutputActive(_ value: Bool) {
        guard value != outputActive else { return }
        outputActive = value
        cancel()
    }
    public mutating func setRequestActive(_ value: Bool) {
        guard value != requestActive else { return }
        requestActive = value
        cancel()
    }
}

/// A reply consumes only the instructions it actually sent. Later intent stays queued.
public struct VoicePromptQueue: Sendable {
    public struct Snapshot: Sendable {
        fileprivate let revision: UInt64
        public let text: String
    }
    private struct Entry: Sendable { let revision: UInt64; let text: String; let respond: Bool }
    private var revision: UInt64 = 0
    private var entries: [Entry] = []
    public init() {}
    public var needsResponse: Bool { entries.contains { $0.respond } }
    public mutating func append(_ text: String, respond: Bool) {
        revision &+= 1
        entries.append(Entry(revision: revision, text: String(text.suffix(5000)), respond: respond))
        while entries.count > 1 && entries.reduce(0, { $0 + $1.text.count + 1 }) > 5001 {
            entries.removeFirst()
        }
    }
    public func snapshot() -> Snapshot {
        Snapshot(revision: revision, text: String(entries.map(\.text).joined(separator: "\n").suffix(5000)))
    }
    public mutating func acknowledge(_ sent: Snapshot) {
        entries.removeAll { $0.revision <= sent.revision }
    }
}
