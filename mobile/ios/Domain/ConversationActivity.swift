import Foundation

/// An unanswered check-in never extends the paid session. Times use a monotonic clock.
public struct ConversationActivity: Sendable {
    public enum Action: Equatable, Sendable { case wait, checkIn, warning(Int), end }
    public static let quietSeconds: Double = SessionLimits.idleVoiceSeconds
    public static let checkInSeconds: Double = 15
    public static let speechGraceSeconds: Double = 15
    public static let typingGraceSeconds: Double = 60
    public static let responseGraceSeconds: Double = 45
    private var quietSince: Double
    private var outputDeadline: Double
    private var lastInput: Double?
    private var typingStarted: Double?
    private var lastTyping: Double?
    private var busyStarted: Double?
    private var checkedIn = false
    public init(now: Double) { quietSince = now; outputDeadline = now + 60 }
    public mutating func learnerEngaged(now: Double) {
        quietSince = now; outputDeadline = now + 60; checkedIn = false
        typingStarted = nil; lastTyping = nil; lastInput = nil; busyStarted = nil
    }
    public mutating func assistantActive(now: Double) {
        if !checkedIn && now <= outputDeadline { quietSince = now }
    }
    public mutating func inputActive(now: Double) { lastInput = now }
    public mutating func typing(now: Double) {
        if typingStarted == nil { typingStarted = now }
        lastTyping = now
    }
    public mutating func tick(now: Double, muted: Bool = false, busy: Bool = false) -> Action {
        if busy && busyStarted == nil { busyStarted = now }
        if !busy { busyStarted = nil }
        let recentInput = !muted && lastInput.map { now - $0 < 1.5 } == true
        let editing = lastTyping.map { now - $0 < 10 } == true
        var deadline = quietSince + Self.quietSeconds
        // Audio levels provide bounded protection for delayed transcripts, never unlimited activity.
        if recentInput { deadline += Self.speechGraceSeconds }
        if editing, let started = typingStarted { deadline = max(deadline, started + Self.typingGraceSeconds) }
        if busy, let started = busyStarted { deadline = max(deadline, started + Self.responseGraceSeconds) }
        if now >= deadline { return .end }
        if deadline - now <= 5 { return .warning(Int(ceil(deadline - now))) }
        if !checkedIn && !muted && !recentInput && !editing && !busy && now - quietSince >= Self.checkInSeconds {
            checkedIn = true; return .checkIn
        }
        return .wait
    }
}
