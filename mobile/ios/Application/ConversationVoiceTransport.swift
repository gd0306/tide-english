import Foundation
import TideEnglishCore

/// Chooses voice capability without changing the supplier of helper requests.
@MainActor final class ConversationVoiceTransport {
    var onEvent: (([String: Any]) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var onHostedLease: ((HostedLease) -> Void)?
    var onInput: ((String) -> Void)?
    var onDegraded: ((String) -> Void)?
    private let openAI = LiveTransport()
    private let glm = GLMRealtimeTransport()
    private let gemini = GeminiLiveTransport()
    private let system = SystemVoiceTransport()
    private enum Mode { case openAI, glm, gemini, system }
    private var mode: Mode = .openAI
    private var attempt = UUID()
    var isTurnBased: Bool { mode == .system }
    var started: Bool {
        switch mode { case .openAI: openAI.started; case .glm: glm.started; case .gemini: gemini.started; case .system: system.started }
    }
    var notice: String? { mode == .system ? system.notice : nil }

    init() {
        openAI.onEvent = { [weak self] in self?.onEvent?($0) }
        openAI.onLevels = { [weak self] in self?.onLevels?($0, $1) }
        openAI.onFailure = { [weak self] in self?.onFailure?($0) }
        openAI.onHostedLease = { [weak self] in self?.onHostedLease?($0) }
        glm.onEvent = { [weak self] in self?.onEvent?($0) }
        glm.onLevels = { [weak self] in self?.onLevels?($0, $1) }
        glm.onFailure = { [weak self] in self?.onFailure?($0) }
        gemini.onEvent = { [weak self] in self?.onEvent?($0) }
        gemini.onLevels = { [weak self] in self?.onLevels?($0, $1) }
        gemini.onFailure = { [weak self] in self?.onFailure?($0) }
        system.onEvent = { [weak self] in self?.onEvent?($0) }
        system.onLevels = { [weak self] in self?.onLevels?($0, $1) }
        system.onInput = { [weak self] in self?.onInput?($0) }
        system.onDegraded = { [weak self] in self?.onDegraded?($0) }
    }
    func connect(api: APIClient, instructions: String, history: [[String: Any]],
                 hosted: HostedConnectRequest? = nil, locale: String) async throws {
        disconnect()
        let token = UUID(); attempt = token
        if hosted != nil || api.configuration.provider == .openAI {
            mode = .openAI
            try await openAI.connect(api: api, instructions: instructions, history: history, hosted: hosted)
        } else if api.configuration.provider == .glm {
            mode = .glm
            do { try await glm.connect(api: api, instructions: instructions, history: history) }
            catch is GLMRealtimeTransport.CapabilityError {
                try Task.checkCancellation()
                guard attempt == token else { throw CancellationError() }
                glm.disconnect(); mode = .system
                onDegraded?("GLM realtime is unavailable for this account. Using on-device turn-based voice with your selected GLM chat model.")
                try await system.connect(locale: locale)
            }
        } else if api.configuration.provider == .gemini {
            mode = .gemini
            do { try await gemini.connect(api: api, instructions: instructions, history: history) }
            catch is GeminiLiveTransport.CapabilityError {
                try Task.checkCancellation()
                guard attempt == token else { throw CancellationError() }
                gemini.disconnect(); mode = .system
                onDegraded?("Gemini native realtime is unavailable for this account. Using on-device turn-based voice with your selected Gemini chat model.")
                try await system.connect(locale: locale)
            }
        } else {
            mode = .system
            try await system.connect(locale: locale)
        }
        try Task.checkCancellation()
        guard attempt == token else { throw CancellationError() }
    }
    @discardableResult func send(_ event: [String: Any]) -> Bool {
        switch mode { case .openAI: openAI.send(event); case .glm: glm.send(event); case .gemini: gemini.send(event); case .system: false }
    }
    func mute(_ value: Bool) {
        switch mode { case .openAI: openAI.mute(value); case .glm: glm.mute(value); case .gemini: gemini.mute(value); case .system: system.mute(value) }
    }
    func close() {
        switch mode { case .openAI: openAI.close(); case .glm: glm.close(); case .gemini: gemini.close(); case .system: system.close() }
    }
    func disconnect() {
        attempt = UUID()
        openAI.disconnect(); glm.disconnect(); gemini.disconnect(); system.disconnect()
    }
    func suspendInput() { if isTurnBased { system.suspendInput() } }
    func resumeInput() { if isTurnBased { system.resumeInput() } }
    func speak(_ text: String, locale: String) { if isTurnBased { system.speak(text, locale: locale) } }
}
