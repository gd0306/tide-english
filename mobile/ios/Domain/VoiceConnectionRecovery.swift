import Foundation

/// Gives a brief network handoff time to recover without leaving a dead call active.
@MainActor public final class VoiceConnectionRecovery {
    private let timeout: Duration
    private let onLost: () -> Void
    private var timer: Task<Void, Never>?

    public init(timeout: Duration = .seconds(8), onLost: @escaping () -> Void) {
        self.timeout = timeout; self.onLost = onLost
    }
    deinit { timer?.cancel() }

    public func disconnected() {
        guard timer == nil else { return }
        timer = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled else { return }
            self?.onLost()
        }
    }
    /// Also used when the call closes, so its timer cannot affect a later call.
    public func connected() {
        timer?.cancel(); timer = nil
    }
}
