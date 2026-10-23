import Foundation
@preconcurrency import AVFoundation
import TideEnglishCore

/// Native BigModel realtime voice. Credentials and audio remain in memory for this connection.
@MainActor final class GLMRealtimeTransport {
    enum CapabilityError: LocalizedError {
        case denied
        var errorDescription: String? { "GLM native realtime is unavailable for this account." }
    }
    var onEvent: (([String: Any]) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var started = false
    private var attempt = UUID()
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupFailure: Error?
    private var startupGate = GLMRealtimeProtocol.StartupGate(historyIDs: [])
    private var startupHistory: [[String: Any]] = []
    private var historyAwaiting: String?
    private var startedEvent: [String: Any]?
    private var state = GLMRealtimeProtocol()
    private var queue = GLMRealtimeProtocol.SendQueue()
    private let audio = RealtimeAudioIO()
    private var muted = false
    private var beganAt: ContinuousClock.Instant?
    private var canProcess: () -> Bool = { false }
    private struct ContextCommand {
        let type: String
        let id: String
        let itemID: String?
        let instructions: String?
        let response: [String: Any]?
        let responseID: UUID?
    }
    private var contextCommands: [ContextCommand] = []
    private var responseGate = GLMRealtimeProtocol.ResponseGate()

    func connect(api: APIClient, instructions: String, history: [[String: Any]]) async throws {
        disconnect()
        let token = UUID(); attempt = token
        do {
            let configuration = try api.configuration.validated()
            guard configuration.provider == .glm, api.canProcessAI() else { throw TransportError.service(.invalidRequest) }
            canProcess = { [weak api] in api?.canProcessAI() == true && api?.configuration == configuration }
            state = GLMRealtimeProtocol(instructions: instructions)
            let update = try GLMRealtimeProtocol.configuration(instructions: instructions)
            startupHistory = try GLMRealtimeProtocol.historyCommands(history)
            startupGate = GLMRealtimeProtocol.StartupGate(historyIDs: startupHistory.compactMap { ($0["item"] as? [String: Any])?["id"] as? String })
            let granted = await AVAudioApplication.requestRecordPermission()
            try Task.checkCancellation()
            guard attempt == token else { throw CancellationError() }
            guard granted else { throw TransportError.microphone }
            guard canProcess() else { throw TransportError.service(.invalidRequest) }
            // No selected chat model is sent here: the native realtime endpoint has its own model.
            let jwt = try GLMRealtimeProtocol.token(key: api.credential(), now: Date().timeIntervalSince1970)
            var request = URLRequest(url: GLMRealtimeProtocol.socketURL)
            request.setValue("Bearer " + jwt, forHTTPHeaderField: "Authorization")
            let network = URLSessionConfiguration.ephemeral
            network.httpCookieStorage = nil; network.urlCache = nil
            network.timeoutIntervalForRequest = 20; network.timeoutIntervalForResource = 65 * 60
            let session = URLSession(configuration: network, delegate: ProviderNoRedirect(), delegateQueue: nil)
            self.session = session
            let socket = session.webSocketTask(with: request)
            socket.maximumMessageSize = GLMRealtimeProtocol.maximumMessageBytes
            self.socket = socket; socket.resume()
            receiveTask = Task { [weak self] in await self?.receive(token: token, socket: socket) }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    startupContinuation = continuation
                    timeoutTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(20)) } catch { return }
                        self?.fail(TransportError.timeout, token: token)
                    }
                    if !enqueue([update], token: token) { fail(TransportError.overloaded, token: token) }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.fail(CancellationError(), token: token) }
            }
            try Task.checkCancellation()
            guard attempt == token else { throw CancellationError() }
            if let startupFailure { throw startupFailure }
            guard canProcess() else { throw TransportError.service(.invalidRequest) }
            try startAudio(token: token)
            beganAt = .now; started = true
            onEvent?(startedEvent ?? ["type": "session.started", "session": ["id": "glm-" + token.uuidString]])
            startedEvent = nil
        } catch let failure as GLMRealtimeProtocol.Failure {
            if attempt == token { disconnect() }
            throw TransportError.service(failure)
        } catch {
            if attempt == token { disconnect() }
            throw error
        }
    }

    @discardableResult func send(_ event: [String: Any]) -> Bool {
        guard started, socket != nil, canProcess(), contextCommands.count < 16 else { return false }
        do {
            var next = state
            let commands = try next.commands(event)
            let clearLocalPlayback = commands.contains { $0["type"] as? String == "client.playback.clear" }
            let serverCommands = commands.filter { $0["type"] as? String != "client.playback.clear" }
            let response = serverCommands.last?["type"] as? String == "response.create" ? serverCommands.last : nil
            let immediate = response == nil ? serverCommands : Array(serverCommands.dropLast())
            guard enqueue(immediate, token: attempt) else { return false }
            state = next
            if immediate.contains(where: { $0["type"] as? String == "response.cancel" }) {
                responseGate.cancel(); queue.discardResponseRequests(); clearPlayback()
            } else if clearLocalPlayback { clearPlayback() }
            if let context = immediate.last, let type = event["type"] as? String, type.hasPrefix("session.") {
                let id = event["event_id"] as? String ?? UUID().uuidString
                contextCommands.append(ContextCommand(type: type, id: id,
                    itemID: (context["item"] as? [String: Any])?["id"] as? String,
                    instructions: (context["session"] as? [String: Any])?["instructions"] as? String,
                    response: response, responseID: response == nil ? nil : responseGate.request()))
            }
            return true
        } catch { return false }
    }
    private func enqueue(_ events: [[String: Any]], token: UUID) -> Bool {
        guard attempt == token, socket != nil else { return false }
        let frames = events.map { event -> [String: Any] in
            var value = event
            value["event_id"] = event["event_id"] ?? UUID().uuidString
            value["client_timestamp"] = Int64(Date().timeIntervalSince1970 * 1000)
            value.removeValue(forKey: "respond")
            return value
        }
        guard (try? queue.append(frames)) == true else { return false }
        if sendTask == nil {
            sendTask = Task { [weak self] in await self?.drain(token: token) }
        }
        return true
    }
    private func drain(token: UUID) async {
        while attempt == token, let socket, let frame = queue.pop() {
            guard canProcess() else { fail(TransportError.service(.invalidRequest), token: token); return }
            do { try await socket.send(.string(frame)) }
            catch { fail(networkError(socket: socket), token: token); return }
        }
        if attempt == token { sendTask = nil }
    }
    private func receive(token: UUID, socket: URLSessionWebSocketTask) async {
        do {
            while attempt == token {
                let message = try await socket.receive()
                guard attempt == token else { return }
                guard canProcess() else { throw TransportError.service(.invalidRequest) }
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: throw GLMRealtimeProtocol.Failure.malformed
                }
                let update = try state.consume(data, elapsedMS: elapsedMS)
                if update.clearPlayback { clearPlayback() }
                for event in update.events {
                    if event["type"] as? String == "session.started", !started {
                        startedEvent = event; startupGate.acceptConfiguration()
                        try advanceHistory(token: token)
                    } else if started { onEvent?(event) }
                }
                // The decoder already bounded and validated JSON before this small ack read.
                if let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if event["type"] as? String == "input_audio_buffer.speech_started" {
                        responseGate.cancel(); queue.discardResponseRequests()
                    }
                    try acknowledge(event, token: token)
                }
                if started, let pcm = update.audio { try play(pcm, token: token) }
            }
        } catch let failure as GLMRealtimeProtocol.Failure {
            let error: Error = !started && failure == .capability ? CapabilityError.denied : TransportError.service(failure)
            fail(error, token: token)
        } catch {
            let safe = error is TransportError ? error : networkError(socket: socket)
            fail(safe, token: token)
        }
    }
    private func acknowledge(_ event: [String: Any], token: UUID) throws {
        let type = event["type"] as? String
        let itemID = (event["item"] as? [String: Any])?["id"] as? String
        if !started, type == "conversation.item.created", let itemID, itemID == historyAwaiting {
            startupGate.acceptHistory(itemID); historyAwaiting = nil
            try advanceHistory(token: token)
        }
        guard started else { return }
        let instructions = (event["session"] as? [String: Any])?["instructions"] as? String
        if let index = contextCommands.firstIndex(where: {
            (type == "conversation.item.created" && $0.itemID != nil && $0.itemID == itemID) ||
            (type == "session.updated" && $0.instructions != nil && $0.instructions == instructions)
        }) {
            let command = contextCommands.remove(at: index)
            if let response = command.response, let responseID = command.responseID, responseGate.consume(responseID),
               !enqueue([response], token: token) { throw TransportError.overloaded }
            onEvent?(["type": command.type.replacingOccurrences(of: ".append", with: ".appended"), "client_event_id": command.id])
        }
    }
    private func advanceHistory(token: UUID) throws {
        guard state.configured, historyAwaiting == nil else { return }
        if !startupHistory.isEmpty {
            let event = startupHistory.removeFirst()
            historyAwaiting = (event["item"] as? [String: Any])?["id"] as? String
            guard enqueue([event], token: token) else { throw TransportError.overloaded }
        } else if startupGate.ready {
            timeoutTask?.cancel(); timeoutTask = nil
            let continuation = startupContinuation; startupContinuation = nil
            continuation?.resume()
        }
    }
    private func startAudio(token: UUID) throws {
        audio.onPCM = { [weak self] pcm, _ in
            guard let self, self.attempt == token, self.started, !self.muted else { return }
            guard self.canProcess() else { self.fail(TransportError.service(.invalidRequest), token: token); return }
            do {
                let wav = try GLMRealtimeProtocol.wav(pcm: pcm)
                guard self.enqueue([["type": "input_audio_buffer.append", "audio": wav.base64EncodedString()]], token: token) else {
                    self.fail(TransportError.overloaded, token: token); return
                }
            } catch { self.fail(TransportError.audio, token: token) }
        }
        audio.onLevels = { [weak self] input, output in
            guard let self, self.attempt == token else { return }; self.onLevels?(input, output)
        }
        audio.onFailure = { [weak self] in self?.fail(TransportError.audio, token: token) }
        do { try audio.start(); audio.mute(muted) } catch { throw TransportError.audio }
    }
    private func play(_ pcm: Data, token: UUID) throws {
        guard attempt == token else { return }
        do { try audio.play(pcm) }
        catch RealtimeAudioIO.Failure.overloaded { throw TransportError.overloaded }
        catch { throw TransportError.audio }
    }
    private func clearPlayback() { audio.clearPlayback() }
    func mute(_ value: Bool) {
        muted = value; audio.mute(value)
        if value {
            // Remove unsent microphone chunks; never submit a half-muted learner turn later.
            queue.discardMicrophoneAudio()
            if started, !enqueue([["type": "input_audio_buffer.clear"]], token: attempt) { fail(TransportError.overloaded, token: attempt) }
        }
    }
    func close() {
        guard started else { disconnect(); return }
        let seconds = Double(elapsedMS) / 1000
        disconnect()
        onEvent?(["type": "session.closed", "usage": ["seconds": seconds]])
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
        queue = GLMRealtimeProtocol.SendQueue(); state = GLMRealtimeProtocol()
        startupHistory = []; historyAwaiting = nil; contextCommands = []; startedEvent = nil; startupFailure = nil
        responseGate = GLMRealtimeProtocol.ResponseGate()
        muted = false; beganAt = nil; canProcess = { false }
    }
    private var elapsedMS: Int {
        guard let beganAt else { return 0 }
        let duration = beganAt.duration(to: .now).components
        return max(0, Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000))
    }
    private func fail(_ error: Error, token: UUID) {
        guard attempt == token else { return }
        if !started {
            guard startupFailure == nil else { return }
            startupFailure = error
            timeoutTask?.cancel(); timeoutTask = nil
            let continuation = startupContinuation; startupContinuation = nil
            continuation?.resume(throwing: error)
            socket?.cancel(with: .goingAway, reason: nil)
        } else {
            let message = (error as? LocalizedError)?.errorDescription ?? "GLM voice connection was lost. Start a new conversation."
            disconnect(); onFailure?(message)
        }
    }
    private func networkError(socket: URLSessionWebSocketTask) -> TransportError {
        switch (socket.response as? HTTPURLResponse)?.statusCode {
        case 401: return .service(.authentication)
        case 429: return .service(.rateLimit)
        case 400, 403, 404: return .service(.invalidRequest)
        default: return .service(.unavailable)
        }
    }
    private enum TransportError: LocalizedError {
        case microphone, audio, timeout, overloaded, service(GLMRealtimeProtocol.Failure)
        var errorDescription: String? {
            switch self {
            case .microphone: "Allow Tide English microphone access in Settings to use GLM voice."
            case .audio: "GLM voice audio could not start or continue. Check your microphone and audio route."
            case .timeout: "GLM voice did not confirm setup in time. Please try again."
            case .overloaded: "GLM voice could not keep up with this connection. Start a new conversation."
            case .service(.credential): "Your GLM key must have the provider's id.secret format. Check it in Settings."
            case .service(.authentication): "Your GLM key wasn’t accepted. Check it in Settings."
            case .service(.billing): "GLM billing or account limits need attention. Check your provider account."
            case .service(.rateLimit): "GLM is limiting requests. Wait briefly and try again."
            case .service(.capability): "GLM native realtime access was denied. Check your account and start a new conversation."
            case .service(.unavailable): "GLM voice connection was lost. Start a new conversation."
            case .service(.malformed), .service(.tooLarge), .service(.invalidAudio): "GLM returned an invalid voice response. Start a new conversation."
            case .service(.invalidRequest): "GLM could not accept this voice request. Check the provider settings and start again."
            }
        }
    }
}
