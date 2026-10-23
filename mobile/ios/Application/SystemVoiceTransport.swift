import Foundation
import AVFoundation
@preconcurrency import Speech
import TideEnglishCore
import CoreMedia

/// On-device, turn-based speech. It never opens a cloud recognition connection.
@MainActor final class SystemVoiceTransport: NSObject, AVSpeechSynthesizerDelegate {
    var onEvent: (([String: Any]) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onInput: ((String) -> Void)?
    var onDegraded: ((String) -> Void)?
    #if DEBUG
    var onRecognitionFailure: ((String, Int) -> Void)?
    struct Diagnostics: Encodable {
        var backend = "none"
        var assets = "unchecked"
        var recognitionStarts = 0
        var microphoneCallbacks = 0
        var microphoneFrames = 0
        var microphoneCallbacksAfterOutput = 0
        var convertedBuffers = 0
        var conversionFailures = 0
        var outputStarts = 0
        var outputFinishes = 0
        var recognitionStartsAfterOutput = 0
        var nonemptyRecognition = false
        var expectedSyntheticRecognition = false
        var analyzerPreparations = 0
        var analyzerPrepared = 0
        var analyzerCleanupStarts = 0
        var analyzerCleanupFinishes = 0
        var finishCallbacksWhileSpeaking = 0
    }
    struct StateSnapshot: Encodable {
        var waiting: Bool
        var canListen: Bool
        var speechAvailable: Bool
        var outputPending: Bool
        var synthesizerSpeaking: Bool
        var startingRecognition: Bool
        var analyzerActive: Bool
        var engineRunning: Bool
    }
    var stateSnapshot: StateSnapshot {
        StateSnapshot(waiting: waiting, canListen: turn.canListen,
                      speechAvailable: speechAvailable, outputPending: utteranceID != nil,
                      synthesizerSpeaking: synthesizer.isSpeaking,
                      startingRecognition: startingRecognition, analyzerActive: analyzer != nil,
                      engineRunning: engine?.isRunning == true)
    }
    private(set) var diagnostics = Diagnostics()
    var inputStopped: Bool { engine == nil && analyzer == nil && !startingRecognition }
    var syntheticInputRequested = false
    private let syntheticSynthesizer = AVSpeechSynthesizer()
    var currentRecognitionCapability: (available: Bool, onDevice: Bool) {
        (recognizer?.isAvailable ?? false, recognizer?.supportsOnDeviceRecognition ?? false)
    }
    #endif
    private(set) var started = false
    private(set) var notice: String?
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var modernLocale: Locale?
    private var preparedTranscriber: SpeechTranscriber?
    private var analyzerFormat: AVAudioFormat?
    private var analyzer: SpeechAnalyzer?
    private var analyzerInput: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerTask: Task<Void, Never>?
    private var analyzerCleanupTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var startingRecognition = false
    private var segments = VoiceSegmentTranscript()
    private var pcmCapture: LocalSpeechPCMStream?
    private let synthesizer = AVSpeechSynthesizer()
    private var turn = VoiceTurnState()
    private var silenceTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var outputActivityTask: Task<Void, Never>?
    private var attempt = UUID()
    private var recognitionID = UUID()
    private var muted = false
    private var waiting = false
    private var speechAvailable = false
    private var ownsAudio = false
    private var beganAt: Date?
    private var utteranceID: ObjectIdentifier?

    override init() { super.init(); synthesizer.delegate = self }

    func connect(locale: String) async throws {
        disconnect()
        let token = UUID(); attempt = token
        // A cancelled connect owns cleanup only while it is the current attempt.
        var connected = false
        defer { if !connected && attempt == token { disconnect() } }
        muted = false; waiting = false; turn = VoiceTurnState(); notice = nil
        #if DEBUG
        diagnostics = Diagnostics()
        #endif
        let language = locale == "en" ? "en-US" : locale
        // Authorization must precede recognizer capability checks. A fresh
        // recognizer can report offline support as unavailable before permission.
        speechAvailable = try await LocalSpeechPreparation.prepare(
            requestSpeechAuthorization: {
                await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
                }
            },
            requestMicrophonePermission: { await AVAudioApplication.requestRecordPermission() },
            recognitionAvailable: {
                let candidate = SFSpeechRecognizer(locale: Locale(identifier: language))
                self.recognizer = candidate
                return candidate?.supportsOnDeviceRecognition == true && candidate?.isAvailable == true
            },
            isCurrent: { self.attempt == token })
        try checkAttempt(token)
        let permissionsGranted = SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
        #if DEBUG
        if syntheticInputRequested { speechAvailable = false }
        #endif
        if !speechAvailable && permissionsGranted {
            do { speechAvailable = try await prepareModern(locale: Locale(identifier: language), token: token) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try checkAttempt(token)
                reportFailure(error)
                #if DEBUG
                diagnostics.assets = "failed"
                #endif
                setNotice("Local speech language resources could not be prepared. Use Type a reply; Tide English can still read its responses.")
            }
        }
        try checkAttempt(token)
        let audio = AVAudioSession.sharedInstance()
        if speechAvailable {
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        } else {
            try audio.setCategory(.playback, mode: .spokenAudio)
            if notice == nil { setNotice("On-device speech is unavailable or not allowed for this language. Use Type a reply; Tide English can still read its responses.") }
        }
        try audio.setActive(true); ownsAudio = true
        try checkAttempt(token)
        started = true; beganAt = .now; connected = true
        onEvent?(["type": "session.started", "session": ["id": "local-" + token.uuidString]])
        resumeInput()
    }

    func suspendInput() {
        waiting = true
        turn.setRequestActive(true)
        stopRecognition()
    }
    private func checkAttempt(_ token: UUID) throws {
        try Task.checkCancellation()
        guard attempt == token else { throw CancellationError() }
    }
    private func prepareModern(locale: Locale, token: UUID) async throws -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        try checkAttempt(token)
        guard let supported else { return false }
        let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        let status = await AssetInventory.status(forModules: [module])
        try checkAttempt(token)
        #if DEBUG
        diagnostics.assets = String(describing: status)
        #endif
        guard status != .unsupported else { return false }
        if status != .installed {
            setNotice("Preparing local speech language resources for on-device recognition.")
            let installation = try await AssetInventory.assetInstallationRequest(supporting: [module])
            try checkAttempt(token)
            if let installation {
                try await installation.downloadAndInstall()
                try checkAttempt(token)
            }
        }
        let installed = await AssetInventory.status(forModules: [module])
        try checkAttempt(token)
        #if DEBUG
        diagnostics.assets = String(describing: installed)
        #endif
        guard installed == .installed else { throw SpeechError.unavailable }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        try checkAttempt(token)
        guard let format else { throw SpeechError.unavailable }
        modernLocale = supported; preparedTranscriber = module; analyzerFormat = format
        if notice != nil { setNotice("On-device speech is ready.") }
        return true
    }
    func resumeInput() {
        waiting = false
        turn.setRequestActive(false)
        guard started, speechAvailable, turn.canListen,
              engine == nil, analyzer == nil, !startingRecognition else { return }
        if modernLocale != nil {
            let id = UUID(); recognitionID = id
            startingRecognition = true
            let generation = turn.begin()
            segments = VoiceSegmentTranscript()
            startupTask = Task { [weak self] in
                guard let self else { return }
                do { try await self.startModernRecognition(id: id, generation: generation) }
                catch {
                    guard self.accepts(id) else { return }
                    self.recognitionFailed(error)
                }
            }
        } else {
            do { try startRecognition() }
            catch { recognitionFailed(error) }
        }
    }
    private func accepts(_ id: UUID) -> Bool {
        started && recognitionID == id && !muted && !waiting && turn.canListen
    }
    private func reportFailure(_ error: Error) {
        #if DEBUG
        let value = error as NSError
        onRecognitionFailure?(value.domain, value.code)
        #endif
    }
    private func recognitionFailed(_ error: Error) {
        reportFailure(error)
        speechAvailable = false; stopRecognition()
        setNotice("On-device recognition stopped. Use Type a reply for this conversation, or try voice again in a new conversation.")
    }
    private func recognitionStarted(backend: String) {
        #if DEBUG
        diagnostics.backend = backend; diagnostics.recognitionStarts += 1
        if diagnostics.outputFinishes > 0 { diagnostics.recognitionStartsAfterOutput += 1 }
        #endif
    }
    private func updateTranscript(_ text: String, generation: UInt64, id: UUID) {
        guard accepts(id) else { return }
        #if DEBUG
        diagnostics.nonemptyRecognition = diagnostics.nonemptyRecognition || !text.isEmpty
        if syntheticInputRequested {
            let normalized = text.lowercased().filter { $0.isLetter || $0.isWhitespace }
            diagnostics.expectedSyntheticRecognition = diagnostics.expectedSyntheticRecognition || normalized.contains("i like coffee")
        }
        #endif
        guard turn.update(text, generation: generation) else { return }
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            self?.commit(generation: generation, recognitionID: id)
        }
    }
    private func startModernRecognition(id: UUID, generation: UInt64) async throws {
        guard let locale = modernLocale, let format = analyzerFormat, accepts(id) else { throw CancellationError() }
        // The prior analyzer releases its model before this generation prepares one.
        if let cleanup = analyzerCleanupTask { await cleanup.value }
        try Task.checkCancellation()
        guard accepts(id) else { throw CancellationError() }
        analyzerCleanupTask = nil
        // Results belong to this generation only. Never reuse a completed module stream.
        let module = preparedTranscriber ?? SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        preparedTranscriber = nil
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        #if DEBUG
        diagnostics.analyzerPreparations += 1
        #endif
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        guard accepts(id) else { await analyzer.cancelAndFinishNow(); throw CancellationError() }
        #if DEBUG
        diagnostics.analyzerPrepared += 1
        #endif
        let pair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(32))
        analyzerInput = pair.continuation
        resultsTask = Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self, self.accepts(id), !Task.isCancelled else { return }
                    let start = result.range.start.seconds * 1000
                    let end = CMTimeRangeGetEnd(result.range).seconds * 1000
                    guard start.isFinite, end.isFinite, start >= 0, end > start,
                          end < Double(Int.max) else { continue }
                    let text = String(result.text.characters)
                    let assembled = self.segments.update(text: text, startMS: Int(start), endMS: Int(end), isFinal: result.isFinal)
                    // A final segment is evidence, never an end-of-turn signal.
                    self.updateTranscript(assembled, generation: generation, id: id)
                }
            } catch {
                guard let self, self.accepts(id), !Task.isCancelled else { return }
                self.recognitionFailed(error)
            }
        }
        analyzerTask = Task { [weak self] in
            do {
                _ = try await analyzer.analyzeSequence(pair.stream)
                guard let self, self.accepts(id), !Task.isCancelled else { return }
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                guard let self, self.accepts(id), !Task.isCancelled else { return }
                self.recognitionFailed(error)
            }
        }
        #if DEBUG
        if syntheticInputRequested {
            let capture = LocalSpeechPCMStream(target: format, continuation: pair.continuation)
            pcmCapture = capture
            startingRecognition = false; startupTask = nil
            recognitionStarted(backend: "analyzer_synthetic")
            startMeter(capture: capture, id: id, microphone: false)
            let utterance = AVSpeechUtterance(string: "I like coffee.")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            syntheticSynthesizer.write(utterance) { buffer in
                guard let buffer = buffer as? AVAudioPCMBuffer else { capture.finish(); return }
                if buffer.frameLength == 0 { capture.finish() }
                else { capture.consume(buffer) }
            }
            return
        }
        #endif
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0 else { throw SpeechError.unavailable }
        let capture = LocalSpeechPCMStream(target: format, continuation: pair.continuation)
        pcmCapture = capture; self.engine = engine
        input.installTap(onBus: 0, bufferSize: 1024, format: source) { buffer, _ in capture.consume(buffer) }
        engine.prepare(); try engine.start()
        guard accepts(id) else { throw CancellationError() }
        startingRecognition = false; startupTask = nil
        recognitionStarted(backend: "analyzer")
        startMeter(capture: capture, id: id)
    }
    private var meterTask: Task<Void, Never>?
    private func startMeter(capture: LocalSpeechPCMStream, id: UUID, microphone: Bool = true) {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.accepts(id) else { return }
                let snapshot = capture.snapshot()
                #if DEBUG
                if microphone {
                    self.diagnostics.microphoneCallbacks += snapshot.callbacks
                    self.diagnostics.microphoneFrames += snapshot.frames
                    if self.diagnostics.outputFinishes > 0 { self.diagnostics.microphoneCallbacksAfterOutput += snapshot.callbacks }
                }
                self.diagnostics.convertedBuffers += snapshot.converted
                self.diagnostics.conversionFailures += snapshot.failures
                #endif
                self.onLevels?(snapshot.level, 0)
                if snapshot.failures > 0 { self.recognitionFailed(SpeechError.conversion); return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    private func startRecognition() throws {
        guard let recognizer, recognizer.isAvailable else { throw SpeechError.unavailable }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechError.unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        let id = UUID(); recognitionID = id
        let generation = turn.begin()
        self.request = request; self.engine = engine
        recognitionStarted(backend: "legacy")
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, request] buffer, _ in
            request.append(buffer)
            let channel = buffer.floatChannelData?[0]
            let count = Int(buffer.frameLength)
            var peak: Float = 0
            if let channel { for index in 0..<count { peak = max(peak, abs(channel[index])) } }
            let level = Double(min(1, peak))
            Task { @MainActor [weak self] in
                guard let self, self.accepts(id) else { return }
                #if DEBUG
                self.diagnostics.microphoneCallbacks += 1
                self.diagnostics.microphoneFrames += count
                if self.diagnostics.outputFinishes > 0 { self.diagnostics.microphoneCallbacksAfterOutput += 1 }
                #endif
                self.onLevels?(level, 0)
            }
        }
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            #if DEBUG
            let failureDomain = (error as NSError?)?.domain
            let failureCode = (error as NSError?)?.code
            #endif
            Task { @MainActor [weak self] in
                guard let self, self.started, self.recognitionID == id, !self.muted, !self.waiting else { return }
                if let text { self.updateTranscript(text, generation: generation, id: id) }
                if final { self.commit(generation: generation, recognitionID: id) }
                else if failed {
                    #if DEBUG
                    if let failureDomain, let failureCode { self.onRecognitionFailure?(failureDomain, failureCode) }
                    #endif
                    // Do not turn an errored partial into learning evidence.
                    self.speechAvailable = false; self.stopRecognition()
                    self.setNotice("On-device recognition stopped. Use Type a reply for this conversation, or try voice again in a new conversation.")
                }
            }
        }
        engine.prepare()
        try engine.start()
    }
    private func commit(generation: UInt64, recognitionID: UUID) {
        guard accepts(recognitionID) else { return }
        let text = turn.commit(generation: generation)
        stopRecognition()
        if let text {
            waiting = true
            turn.setRequestActive(true)
            onInput?(text)
        } else {
            restartTask?.cancel()
            let token = attempt
            restartTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, self.attempt == token else { return }
                self.resumeInput()
            }
        }
    }
    private func stopRecognition() {
        recognitionID = UUID(); turn.cancel()
        startupTask?.cancel(); startupTask = nil; startingRecognition = false
        meterTask?.cancel(); meterTask = nil
        analyzerInput?.finish(); analyzerInput = nil
        pcmCapture?.finish(); pcmCapture = nil
        analyzerTask?.cancel(); analyzerTask = nil
        resultsTask?.cancel(); resultsTask = nil
        if let analyzer {
            let previous = analyzerCleanupTask
            #if DEBUG
            diagnostics.analyzerCleanupStarts += 1
            #endif
            analyzerCleanupTask = Task { [weak self] in
                if let previous { await previous.value }
                await analyzer.cancelAndFinishNow()
                #if DEBUG
                self?.diagnostics.analyzerCleanupFinishes += 1
                #endif
            }
        }
        analyzer = nil; segments = VoiceSegmentTranscript()
        #if DEBUG
        syntheticSynthesizer.stopSpeaking(at: .immediate)
        #endif
        silenceTask?.cancel(); silenceTask = nil
        restartTask?.cancel(); restartTask = nil
        if let engine { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        engine = nil
        request?.endAudio(); request = nil
        recognitionTask?.cancel(); recognitionTask = nil
        onLevels?(0, utteranceID == nil ? 0 : 0.2)
    }
    func speak(_ text: String, locale: String) {
        guard started, !text.isEmpty else { resumeInput(); return }
        stopRecognition()
        turn.setOutputActive(true)
        outputActivityTask?.cancel()
        utteranceID = nil
        synthesizer.stopSpeaking(at: .immediate)
        let language = locale == "en" ? "en-US" : locale
        guard let voice = AVSpeechSynthesisVoice(language: language) else {
            turn.setOutputActive(false)
            setNotice("No system reading voice is available for this language. Your text conversation still works.")
            if turn.canListen { resumeInput() }; return
        }
        let utterance = AVSpeechUtterance(string: String(text.prefix(12_000)))
        utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utteranceID = ObjectIdentifier(utterance)
        onLevels?(0, 0.2)
        synthesizer.speak(utterance)
        let id = ObjectIdentifier(utterance)
        outputActivityTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.started, self.utteranceID == id else { return }
                self.onLevels?(0, 0.2)
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.started, self.utteranceID == id else { return }
            #if DEBUG
            self.diagnostics.outputStarts += 1
            #endif
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.started, self.utteranceID == id else { return }
            #if DEBUG
            self.diagnostics.outputFinishes += 1
            if self.synthesizer.isSpeaking { self.diagnostics.finishCallbacksWhileSpeaking += 1 }
            #endif
            self.finishedOutput(id)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishedOutput(id)
        }
    }
    private func finishedOutput(_ id: ObjectIdentifier) {
        // The identity-matched delegate event is authoritative. iOS can still
        // report isSpeaking during didFinish; waiting for that property strands
        // outputActive forever because no second completion event is delivered.
        guard started, utteranceID == id else { return }
        outputActivityTask?.cancel(); outputActivityTask = nil
        utteranceID = nil
        turn.setOutputActive(false); onLevels?(0, 0)
        if turn.canListen { resumeInput() }
    }
    func mute(_ value: Bool) {
        muted = value; turn.setMuted(value)
        if value { stopRecognition() }
        else if !waiting { resumeInput() }
    }
    func close() {
        let elapsed = beganAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        disconnect()
        onEvent?(["type": "session.closed", "usage": ["seconds": elapsed]])
    }
    func disconnect() {
        started = false; attempt = UUID(); speechAvailable = false
        outputActivityTask?.cancel(); outputActivityTask = nil
        stopRecognition(); utteranceID = nil; synthesizer.stopSpeaking(at: .immediate)
        turn = VoiceTurnState(); recognizer = nil; waiting = false; beganAt = nil
        modernLocale = nil; preparedTranscriber = nil; analyzerFormat = nil
        if ownsAudio {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudio = false
        }
        onLevels?(0, 0)
    }
    private func setNotice(_ value: String) { notice = value; onDegraded?(value) }
    private enum SpeechError: Error { case unavailable, conversion }
}


/// The tap owns conversion synchronously. Every yielded buffer owns independent PCM;
/// the bounded stream cannot retain the engine's borrowed tap buffer.
private final class LocalSpeechPCMStream: @unchecked Sendable {
    struct Snapshot { var callbacks = 0; var frames = 0; var converted = 0; var failures = 0; var level = 0.0 }
    private let lock = NSLock()
    private let target: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var source: AVAudioFormat?
    private var stopped = false
    private var counters = Snapshot()
    init(target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.target = target; self.continuation = continuation
    }
    func consume(_ input: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        counters.callbacks += 1; counters.frames += Int(input.frameLength)
        if let values = input.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<Int(input.frameLength) { peak = max(peak, abs(values[i])) }
            counters.level = max(counters.level, Double(min(1, peak)))
        }
        if source != input.format {
            source = input.format; converter = AVAudioConverter(from: input.format, to: target)
        }
        guard let converter else { counters.failures += 1; return }
        let frames = ceil(Double(input.frameLength) * target.sampleRate / input.format.sampleRate) + 32
        guard frames > 0, frames < Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(frames)) else {
            counters.failures += 1; return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return input
        }
        guard error == nil, status != .error else { counters.failures += 1; return }
        if output.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: output)); counters.converted += 1
        }
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let value = counters; counters = Snapshot(); return value
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        stopped = true; continuation.finish()
    }
}
