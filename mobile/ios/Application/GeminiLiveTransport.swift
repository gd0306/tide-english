import Foundation
@preconcurrency import AVFoundation
import TideEnglishCore

/// Header-authenticated Gemini Live. All ephemeral credentials and resume handles are memory-only.
@MainActor final class GeminiLiveTransport {
    enum CapabilityError: LocalizedError {
        case denied
        var errorDescription: String? { "Gemini native realtime is unavailable for this account." }
    }
    var onEvent: (([String: Any]) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var started = false
    private let audio = RealtimeAudioIO()
    private var attempt = UUID()
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupFailure: Error?
    private var state = GeminiLiveProtocol()
    private var queue = GeminiLiveProtocol.SendQueue()
    private var deferred: [GeminiLiveProtocol.Command] = []
    private var ephemeralToken: String?
    private var instructions = ""
    private var beganAt: ContinuousClock.Instant?
    private var muted = false
    private var resuming = false
    private var initialEvent: [String: Any]?
    private var canProcess: () -> Bool = { false }

    func connect(api: APIClient, instructions: String, history: [[String: Any]]) async throws {
        disconnect()
        let token = UUID(); attempt = token
        do {
            try await withTaskCancellationHandler {
                let configuration = try api.configuration.validated()
                guard configuration.provider == .gemini, api.canProcessAI() else { throw TransportError.consent }
                canProcess = { [weak api] in api?.canProcessAI() == true && api?.configuration == configuration }
                self.instructions = instructions
                let historyFrame = try GeminiLiveProtocol.history(history)
                let setup = try GeminiLiveProtocol.setup(instructions: instructions, hasHistory: historyFrame != nil)
                let network = URLSessionConfiguration.ephemeral
                network.httpCookieStorage = nil; network.urlCache = nil
                network.timeoutIntervalForRequest = 20; network.timeoutIntervalForResource = 65 * 60
                let session = URLSession(configuration: network, delegate: ProviderNoRedirect(), delegateQueue: nil)
                self.session = session
                armTimeout(token: token)
                var request = URLRequest(url: GeminiLiveProtocol.tokenURL)
                request.httpMethod = "POST"
                request.setValue(try GeminiLiveProtocol.checkedSecret(api.credential()), forHTTPHeaderField: "x-goog-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: GeminiLiveProtocol.tokenBody(now: Date()))
                // Stream and bound the provisioning response before accumulating it.
                let (bytes, response) = try await session.bytes(for: request)
                try validateAttempt(token)
                guard let response = response as? HTTPURLResponse else { throw TransportError.service(.unavailable) }
                guard (200..<300).contains(response.statusCode) else { throw classified(response.statusCode) }
                guard response.expectedContentLength <= Int64(GeminiLiveProtocol.maximumMessageBytes) else { throw TransportError.service(.tooLarge) }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < GeminiLiveProtocol.maximumMessageBytes else { throw TransportError.service(.tooLarge) }
                    data.append(byte)
                }
                try validateAttempt(token)
                ephemeralToken = try GeminiLiveProtocol.token(from: data)
                let socket = try makeSocket(session: session)
                self.socket = socket; socket.resume()
                try await write(setup, to: socket)
                try validateAttempt(token)
                receiveTask = Task { [weak self] in await self?.receive(token: token, socket: socket) }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if let startupFailure { continuation.resume(throwing: startupFailure) }
                    else if state.configured { continuation.resume() }
                    else { startupContinuation = continuation }
                }
                try validateAttempt(token)
                // Initial history has its own non-generating mode; never replay it on resume.
                if let historyFrame { state.noteOutbound(); try await write(historyFrame, to: socket); try validateAttempt(token) }
                let granted = await AVAudioApplication.requestRecordPermission()
                try validateAttempt(token)
                guard granted else { throw TransportError.microphone }
                configureAudio(token: token)
                do { try audio.start(); audio.mute(muted) } catch { throw TransportError.audio }
                try validateAttempt(token)
                timeoutTask?.cancel(); timeoutTask = nil
                beganAt = .now; started = true
                let event = initialEvent; initialEvent = nil
                if let event { onEvent?(event) }
            } onCancel: {
                Task { @MainActor [weak self] in self?.fail(CancellationError(), token: token) }
            }
        } catch {
            let failure: Error
            if let startupFailure { failure = startupFailure }
            else if let safe = error as? GeminiLiveProtocol.Failure { failure = mapped(safe) }
            else if error is TransportError || error is CapabilityError || error is CancellationError { failure = error }
            else { failure = classified((socket?.response as? HTTPURLResponse)?.statusCode) }
            if attempt == token { disconnect() }
            throw failure
        }
    }
    private func validateAttempt(_ token: UUID) throws {
        try Task.checkCancellation()
        guard attempt == token else { throw CancellationError() }
        if let startupFailure { throw startupFailure }
        guard canProcess() else { throw TransportError.consent }
    }
    private func makeSocket(session: URLSession) throws -> URLSessionWebSocketTask {
        guard let ephemeralToken else { throw TransportError.service(.credential) }
        var request = URLRequest(url: GeminiLiveProtocol.socketURL)
        request.setValue("Token " + ephemeralToken, forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = GeminiLiveProtocol.maximumMessageBytes
        return socket
    }
    private func write(_ frame: [String: Any], to socket: URLSessionWebSocketTask) async throws {
        guard canProcess(), self.socket === socket else { throw TransportError.consent }
        let data = try JSONSerialization.data(withJSONObject: frame)
        guard data.count <= GeminiLiveProtocol.maximumMessageBytes, let text = String(data: data, encoding: .utf8) else { throw TransportError.service(.tooLarge) }
        try await socket.send(.string(text))
    }
    @discardableResult func send(_ event: [String: Any]) -> Bool {
        guard started, !resuming, canProcess(), socket != nil, queue.count + deferred.count < 16 else { return false }
        do {
            let command = try GeminiLiveProtocol.command(event)
            guard state.supports(command) else { return false }
            if !state.canSend(command) { deferred.append(command); return true }
            return enqueue(.init(command: command), token: attempt)
        } catch { return false }
    }
    private func enqueue(_ entry: GeminiLiveProtocol.SendQueue.Entry, token: UUID) -> Bool {
        guard attempt == token, !resuming, socket != nil, (try? queue.append(entry)) == true else { return false }
        if entry.isAudio { state.noteInputQueued() }
        if sendTask == nil { sendTask = Task { [weak self] in await self?.drain(token: token) } }
        return true
    }
    private func drain(token: UUID) async {
        while attempt == token, !resuming {
            // Recheck after every suspended write: capture can start while that write is
            // in flight. Settle unsent passive IDs once, even if capture then stops.
            let rejected = deferred.filter { !state.supports($0) }
            deferred.removeAll { !state.supports($0) }
            for command in rejected {
                guard attempt == token else { return }
                if let rejection = state.rejection(for: command) { onEvent?(rejection) }
            }
            guard attempt == token, let socket, let entry = queue.pop() else { break }
            do {
                try validateAttempt(token)
                guard state.beginSend(entry) else {
                    guard let command = entry.command else { throw TransportError.overloaded }
                    if let rejection = state.rejection(for: command) { onEvent?(rejection); continue }
                    guard deferred.count < 16 else { throw TransportError.overloaded }
                    deferred.append(command); continue
                }
                try await write(entry.wire, to: socket)
                guard attempt == token, self.socket === socket else { return }
                if let command = entry.command { deliver(state.accept(command), token: token) }
            } catch { fail(safeError(error, socket: socket), token: token); return }
        }
        if attempt == token { sendTask = nil }
    }
    private func flushDeferred(token: UUID) throws {
        guard !state.replyActive, !resuming else { return }
        while let command = deferred.first {
            guard enqueue(.init(command: command), token: token) else { throw TransportError.overloaded }
            deferred.removeFirst()
        }
    }
    private func receive(token: UUID, socket original: URLSessionWebSocketTask) async {
        var socket = original
        do {
            while attempt == token, self.socket === socket {
                let message = try await socket.receive()
                try validateAttempt(token)
                guard self.socket === socket else { return }
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let value): data = value
                @unknown default: throw GeminiLiveProtocol.Failure.malformed
                }
                let update = try state.consume(data, elapsedMS: elapsedMS)
                if let handle = update.resumeHandle {
                    // An in-flight send has uncertain delivery. Stop instead of replaying or
                    // resuming an older context snapshot and silently losing learner evidence.
                    guard started, sendTask == nil, !queue.hasCommands, deferred.isEmpty, let session else { throw GeminiLiveProtocol.Failure.unsafeResume }
                    queue.discardAudio(); resuming = true; audio.mute(true); audio.clearPlayback()
                    try state.beginResume()
                    socket.cancel(with: .normalClosure, reason: nil)
                    let next = try makeSocket(session: session)
                    self.socket = next; socket = next; next.resume()
                    armTimeout(token: token)
                    try await write(GeminiLiveProtocol.setup(instructions: instructions, hasHistory: false, resumeHandle: handle), to: next)
                    try validateAttempt(token)
                    continue
                }
                if !started {
                    if let event = update.events.first(where: { $0["type"] as? String == "session.started" }) { initialEvent = event }
                    if state.configured {
                        let continuation = startupContinuation; startupContinuation = nil; continuation?.resume()
                    }
                } else {
                    if resuming, state.configured {
                        resuming = false; timeoutTask?.cancel(); timeoutTask = nil; audio.mute(muted)
                    }
                    deliver(update, token: token)
                    try flushDeferred(token: token)
                }
            }
        } catch { fail(safeError(error, socket: socket), token: token) }
    }
    private func deliver(_ update: GeminiLiveProtocol.Update, token: UUID) {
        guard attempt == token, started else { return }
        if update.clearPlayback { audio.clearPlayback() }
        for event in update.events {
            guard attempt == token, started else { return }
            onEvent?(event)
        }
        guard attempt == token, started else { return }
        do { for pcm in update.audio { try audio.play(pcm) } }
        catch { fail(TransportError.audio, token: token) }
    }
    private func configureAudio(token: UUID) {
        audio.onPCM = { [weak self] pcm, _ in
            guard let self, self.attempt == token, self.started, !self.muted, !self.resuming else { return }
            guard self.canProcess() else { self.fail(TransportError.consent, token: token); return }
            do {
                let frame = try self.state.audio(pcm)
                guard self.enqueue(.init(wire: frame, isAudio: true), token: token) else { throw TransportError.overloaded }
            } catch { self.fail(TransportError.audio, token: token) }
        }
        audio.onLevels = { [weak self] input, output in
            guard let self, self.attempt == token else { return }; self.onLevels?(input, output)
        }
        audio.onFailure = { [weak self] in self?.fail(TransportError.audio, token: token) }
    }
    func mute(_ value: Bool) {
        muted = value; audio.mute(value || resuming)
        if value {
            queue.discardAudio()
            if started, !resuming, !enqueue(.init(wire: ["realtimeInput": ["audioStreamEnd": true]]), token: attempt) { fail(TransportError.overloaded, token: attempt) }
        }
    }
    func close() {
        guard started else { disconnect(); return }
        let seconds = Double(elapsedMS) / 1000
        disconnect(); onEvent?(["type": "session.closed", "usage": ["seconds": seconds]])
    }
    func disconnect() {
        attempt = UUID(); started = false
        let continuation = startupContinuation; startupContinuation = nil
        continuation?.resume(throwing: CancellationError())
        timeoutTask?.cancel(); timeoutTask = nil
        receiveTask?.cancel(); receiveTask = nil; sendTask?.cancel(); sendTask = nil
        audio.disconnect()
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        ephemeralToken = nil; instructions = ""; state = GeminiLiveProtocol(); queue = .init(); deferred = []
        startupFailure = nil; initialEvent = nil; beganAt = nil; muted = false; resuming = false; canProcess = { false }
    }
    private func armTimeout(token: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            self?.fail(TransportError.timeout, token: token)
        }
    }
    private var elapsedMS: Int {
        guard let beganAt else { return 0 }
        let time = beganAt.duration(to: .now).components
        return max(0, Int(time.seconds * 1000 + time.attoseconds / 1_000_000_000_000_000))
    }
    private func mapped(_ failure: GeminiLiveProtocol.Failure) -> Error {
        if !started, failure == .capability { return CapabilityError.denied }
        return TransportError.service(failure)
    }
    private func classified(_ status: Int?) -> Error { mapped(GeminiLiveProtocol.failure(status: status, started: started)) }
    private func safeError(_ error: Error, socket: URLSessionWebSocketTask) -> Error {
        if let failure = error as? GeminiLiveProtocol.Failure { return mapped(failure) }
        if error is TransportError || error is CapabilityError || error is CancellationError { return error }
        return classified((socket.response as? HTTPURLResponse)?.statusCode)
    }
    private func fail(_ error: Error, token: UUID) {
        guard attempt == token else { return }
        if !started {
            guard startupFailure == nil else { return }
            startupFailure = error
            let continuation = startupContinuation; startupContinuation = nil
            continuation?.resume(throwing: error)
            timeoutTask?.cancel(); timeoutTask = nil
            socket?.cancel(with: .goingAway, reason: nil); session?.invalidateAndCancel(); audio.disconnect()
        } else {
            let message = (error as? LocalizedError)?.errorDescription ?? TransportError.service(.unavailable).localizedDescription
            disconnect(); onFailure?(message)
        }
    }
    private enum TransportError: LocalizedError {
        case microphone, audio, consent, timeout, overloaded, service(GeminiLiveProtocol.Failure)
        var errorDescription: String? {
            switch self {
            case .microphone: "Allow Tide English microphone access in Settings to use Gemini voice."
            case .audio: "Gemini voice audio could not start or continue. Check your microphone and audio route."
            case .consent: "Gemini voice settings or consent changed. Start a new conversation."
            case .timeout: "Gemini voice did not confirm setup in time. Your conversation is saved; please start again."
            case .overloaded: "Gemini voice could not keep up with this connection. Your conversation is saved; please start again."
            case .service(.credential), .service(.authentication): "Your Gemini key or account access wasn’t accepted. Check Google AI Studio and Settings."
            case .service(.billing): "Gemini returned HTTP 402: prepaid credits are unavailable. Check this key’s project and billing balance in Google AI Studio before starting again."
            case .service(.rateLimit): "Gemini request or billing limits need attention. Check Google AI Studio, then try again."
            case .service(.unsafeResume): "Gemini voice could not safely resume. Your conversation is saved; start a new conversation to continue."
            case .service(.capability): "Gemini native realtime is unavailable for this account."
            case .service(.malformed), .service(.tooLarge), .service(.invalidAudio): "Gemini returned an invalid voice response. Your conversation is saved; start again."
            case .service(.unavailable): "Gemini voice connection was lost. Your conversation is saved; start again."
            }
        }
    }
}
