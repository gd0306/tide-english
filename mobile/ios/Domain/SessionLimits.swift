import Foundation

/// Shared session duration policy used by the native clients.
public enum SessionLimits {
    public static let idleVoiceSeconds: Double = 30
    public static func endsForInactivity(voice: Bool, idleSeconds: Double) -> Bool {
        voice && idleSeconds >= idleVoiceSeconds
    }
}
