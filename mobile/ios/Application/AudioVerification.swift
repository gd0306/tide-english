import Foundation

enum AudioVerification {
    static var systemVoiceRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--verify-system-voice") || ProcessInfo.processInfo.arguments.contains("--verify-system-voice-synthetic") || ProcessInfo.processInfo.arguments.contains("--verify-system-voice-cycle") || ProcessInfo.processInfo.arguments.contains("--verify-deepseek-voice-cycle")
        #else
        false
        #endif
    }
    static var echoRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--verify-echo") || ProcessInfo.processInfo.arguments.contains("--verify-input")
        #else
        false
        #endif
    }
    static var providerRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--verify-provider") || ProcessInfo.processInfo.arguments.contains("--verify-deepseek-provider")
        #else
        false
        #endif
    }
    static var vocabularyRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--verify-vocabulary-definitions")
        #else
        false
        #endif
    }
    static var requested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--verify-audio") || providerRequested || echoRequested || systemVoiceRequested || vocabularyRequested
        #else
        false
        #endif
    }
}

#if DEBUG
import AVFoundation
import UIKit
import WebRTC
import TideEnglishCore
import Speech

extension AudioVerification {
    @MainActor private static var vocabularyCheckHasRun = false
    @MainActor private static func verifyVocabulary(configuration: ProviderConfiguration) async {
        guard vocabularyRequested, !vocabularyCheckHasRun else { return }
        vocabularyCheckHasRun = true
        struct Report: Encodable {
            var status = "running"
            var provider: String
            var model: String
            var count = 0
            var nonempty = false
            var chineseScript = false
            var unchangedLearning = false
        }
        var report = Report(provider: configuration.provider.rawValue, model: configuration.model)
        let destination = URL.documentsDirectory.appendingPathComponent("vocabulary-definitions-verification.json")
        func write() {
            if let data = try? JSONEncoder().encode(report) {
                try? data.write(to: destination, options: [.atomic, .completeFileProtection])
            }
        }
        write()
        do {
            let store = try LearningStore(inMemory: true)
            store.selectLanguage("en")
            var session = SessionRecord(languageID: "en")
            session.append(Fragment(speaker: .user, text: "The journey took three hours.", startMS: 0, endMS: 2000))
            let passage = session.passages[0]
            session.assessments = [Assessment(passageID: passage.id, revisionKey: passage.revisionKey, outcome: .success,
                suggestedLevel: 1, nextGoal: "", capability: "", words: [WordProposal(lemma: "journey",
                meaning: "a trip from one place to another", form: "journey", kind: .independent, confidence: 0.95,
                sourceIDs: passage.fragments.map(\.id), quote: passage.text, language: "en")])]
            store.save(session)
            let baseline = try store.exportData()
            guard let word = store.learner.words.first else { throw VocabularyDefinitionError.invalidRequest }
            let request = VocabularyRequest(word: word, learningLanguageID: "en", meaningLanguage: "Chinese (Simplified)")
            let batch = try VocabularyBatch(requests: [request])
            let api = APIClient(configuration: configuration)
            api.canProcessAI = { vocabularyRequested && UIApplication.shared.isProtectedDataAvailable }
            let response = try await api.respond(instructions: batch.instructions, input: batch.input, schema: batch.schema, purpose: "lookup")
            let values = try batch.decodeResponse(response.text)
            report.count = values.count
            if let value = values[request.cacheKey] {
                report.nonempty = !value.learningDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !value.meaningDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                report.chineseScript = value.meaningDefinition.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }
            }
            report.unchangedLearning = baseline == (try store.exportData())
            report.status = report.count == 1 && report.nonempty && report.chineseScript && report.unchangedLearning ? "passed" : "failed_checks"
        } catch { report.status = "request_failed" }
        write()
    }

    /// Exercise local speech without retained content. Only the explicit DeepSeek
    /// cycle flag authorizes a synthetic API request; microphone text stays local.
    @MainActor static func verifySystemVoice() async {
        struct Report: Encodable {
            var status = "running"
            var locale = "en-US"
            var microphonePermission = "unknown"
            var speechAuthorization = "unknown"
            var recognizerAvailable = false
            var onDeviceSupported = false
            var connected = false
            var foreground = false
            var inputCallbacks = 0
            var peakInput = 0.0
            var outputCallbacks = 0
            var inputAfterOutput = 0
            var recognisedTurn = false
            var synthetic = false
            var engine = SystemVoiceTransport.Diagnostics()
            var state: SystemVoiceTransport.StateSnapshot?
            var stateAtCompletion: SystemVoiceTransport.StateSnapshot?
            var completedCycles = 0
            var cyclePassed = false
            var provider: String?
            var modelReplies = 0
            var modelReplyResumedInput = false
            var disconnected = false
            var inputStoppedAfterDisconnect = false
            var degradation: String?
            var errorCode: Int?
            var errorDomain: String?
            var recognitionErrorCode: Int?
            var recognitionErrorDomain: String?
        }
        var report = Report()
        let voice = SystemVoiceTransport()
        let liveCycle = ProcessInfo.processInfo.arguments.contains("--verify-deepseek-voice-cycle")
        let cycle = ProcessInfo.processInfo.arguments.contains("--verify-system-voice-cycle") || liveCycle
        report.synthetic = ProcessInfo.processInfo.arguments.contains("--verify-system-voice-synthetic")
        voice.syntheticInputRequested = report.synthetic
        var outputStarted = false
        let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled }
        let destination = URL.documentsDirectory.appendingPathComponent(liveCycle ? "deepseek-voice-cycle-verification.json" : cycle ? "system-voice-cycle-verification.json" : report.synthetic ? "system-voice-synthetic-verification.json" : "system-voice-verification.json")
        func write() {
            report.engine = voice.diagnostics
            report.state = voice.stateSnapshot
            report.foreground = UIApplication.shared.applicationState == .active
            report.microphonePermission = String(describing: AVAudioApplication.shared.recordPermission)
            report.speechAuthorization = String(describing: SFSpeechRecognizer.authorizationStatus())
            if let data = try? JSONEncoder().encode(report) { try? data.write(to: destination, options: .atomic) }
        }
        voice.onLevels = { input, output in
            if output > 0 { outputStarted = true; report.outputCallbacks += 1 }
            if input > 0 {
                report.inputCallbacks += 1
                report.peakInput = max(report.peakInput, input)
                if outputStarted && output == 0 { report.inputAfterOutput += 1 }
            }
        }
        voice.onInput = { _ in
            report.recognisedTurn = true
            if !report.synthetic { voice.resumeInput() }
            write()
        }
        voice.onDegraded = { report.degradation = $0; write() }
        voice.onRecognitionFailure = { domain, code in report.recognitionErrorDomain = domain; report.recognitionErrorCode = code; write() }
        write()
        defer { voice.disconnect() }
        do {
            let deadline = Date().addingTimeInterval(10)
            while UIApplication.shared.applicationState != .active, Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard UIApplication.shared.applicationState == .active else { report.status = "foreground_required"; write(); return }
            report.foreground = true
            try await voice.connect(locale: report.locale)
            report.connected = voice.started
            if cycle {
                // Wait for actual capture before stopping the first analyzer. The
                // old one-shot check stopped its asynchronous startup too early.
                let initialDeadline = Date().addingTimeInterval(20)
                while voice.diagnostics.microphoneCallbacks < 5, Date() < initialDeadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                write()
                for index in 0..<3 {
                    guard voice.diagnostics.microphoneCallbacks >= 5 else { break }
                    let finishes = voice.diagnostics.outputFinishes
                    let restarts = voice.diagnostics.recognitionStartsAfterOutput
                    let callbacks = voice.diagnostics.microphoneCallbacksAfterOutput
                    voice.suspendInput()
                    var reply = "This is a microphone connection check."
                    if liveCycle && index == 0 {
                        // One explicit synthetic request, using the saved DeepSeek
                        // configuration and normal app credential handling. No
                        // microphone transcript is sent to the provider here.
                        let configuration = ModelSettings.configuration(for: .deepSeek)
                        report.provider = configuration.provider.rawValue
                        let api = APIClient(configuration: configuration)
                        api.conversationProvider = .personalKey
                        api.canProcessAI = { AudioVerification.requested && UIApplication.shared.isProtectedDataAvailable }
                        let result = try await api.respond(instructions: "Reply in English with a natural short greeting and one question, at most 40 words. Return only speakable text.", input: "This is a voice connection check.", purpose: "conversation")
                        reply = result.text
                        report.modelReplies += 1
                    }
                    voice.speak(reply, locale: report.locale)
                    voice.resumeInput()
                    let deadline = Date().addingTimeInterval(20)
                    while Date() < deadline {
                        try await Task.sleep(for: .milliseconds(100))
                        write()
                        if voice.diagnostics.outputFinishes > finishes,
                           voice.diagnostics.recognitionStartsAfterOutput > restarts,
                           voice.diagnostics.microphoneCallbacksAfterOutput >= callbacks + 5 {
                            report.completedCycles += 1
                            if liveCycle && index == 0 { report.modelReplyResumedInput = true }
                            break
                        }
                    }
                    if report.completedCycles == 0 || voice.stateSnapshot.outputPending { break }
                }
                report.cyclePassed = report.completedCycles == 3
            } else if report.synthetic {
                let deadline = Date().addingTimeInterval(25)
                while !report.recognisedTurn, Date() < deadline, !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(100))
                }
            } else {
                voice.suspendInput()
                voice.speak("This is a microphone connection check.", locale: report.locale)
                voice.resumeInput()
                try await Task.sleep(for: .seconds(8))
            }
            report.status = UIApplication.shared.applicationState == .active ? "complete" : "foreground_required"
        } catch {
            report.status = "failed"
            let error = error as NSError
            report.errorCode = error.code; report.errorDomain = error.domain
        }
        report.microphonePermission = String(describing: AVAudioApplication.shared.recordPermission)
        report.speechAuthorization = String(describing: SFSpeechRecognizer.authorizationStatus())
        report.recognizerAvailable = voice.currentRecognitionCapability.available
        report.onDeviceSupported = voice.currentRecognitionCapability.onDevice
        report.stateAtCompletion = voice.stateSnapshot
        write()
        voice.disconnect()
        report.disconnected = !voice.started
        report.inputStoppedAfterDisconnect = voice.inputStopped
        write()
    }
    /// Inspect the production engine without starting it, capturing or playing audio.
    @MainActor static func verifyEcho() async -> String {
        struct Report: Encodable {
            var inputProcessing = false
            var outputProcessing = false
            var engineStopped = true
            var passed = false
            var selectedProvider = ModelSettings.load().provider.rawValue
            var microphonePermission = "unknown"
            var inputSampleRate = 0.0
            var inputChannels: UInt32 = 0
            var inputMuted = false
            var conversionPassed = false
            var convertedFrames = 0
        }
        var report = Report()
        switch AVAudioApplication.shared.recordPermission {
        case .granted: report.microphonePermission = "granted"
        case .denied: report.microphonePermission = "denied"
        case .undetermined: report.microphonePermission = "undetermined"
        @unknown default: break
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredSampleRate(16_000)
            try session.setActive(true)
            defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
            let engine = try RealtimeAudioIO.makeVoiceEngine()
            report.inputProcessing = engine.inputNode.isVoiceProcessingEnabled
            report.outputProcessing = engine.outputNode.isVoiceProcessingEnabled
            report.engineStopped = !engine.isRunning
            report.passed = report.inputProcessing && report.outputProcessing && report.engineStopped
            let format = engine.inputNode.outputFormat(forBus: 0)
            report.inputSampleRate = format.sampleRate
            report.inputChannels = format.channelCount
            report.inputMuted = engine.inputNode.isVoiceProcessingInputMuted
            guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024),
                  let channels = buffer.floatChannelData else { throw RealtimeAudioIO.Failure.audio }
            buffer.frameLength = 1_024
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<1_024 { channels[channel][frame] = Float(0.25 * sin(Double(frame) * 2 * .pi * 440 / format.sampleRate)) }
            }
            let pair = AsyncStream<RealtimeMicrophoneCapture.Packet>.makeStream(bufferingPolicy: .bufferingNewest(4))
            let capture = try RealtimeMicrophoneCapture(format: format, continuation: pair.continuation)
            for _ in 0..<3 { capture.consume(buffer) }
            let conversionCompleted = capture.finish()
            var nonzero = false, failed = false
            for await packet in pair.stream {
                report.convertedFrames += packet.pcm.count / 2
                nonzero = nonzero || packet.level > 0.05
                failed = failed || packet.failed
            }
            report.conversionPassed = conversionCompleted && !failed && nonzero && report.convertedFrames > 0
        } catch { report.conversionPassed = false }
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("echo-verification.json"), options: .atomic)
        }
        return report.passed ? "Echo cancellation enabled" : "Echo cancellation unavailable"
    }
    /// Test one production engine independently of the stopped echo inspection.
    /// PCM is transient; only aggregate counters are written, with no network calls.
    @MainActor static func verifyInput() async -> String {
        struct Report: Encodable {
            var provider = ModelSettings.load().provider.rawValue
            var permissionGranted = AVAudioApplication.shared.recordPermission == .granted
            var started = false
            var engineRunningAtEnd = false
            var packets = 0
            var frames = 0
            var peakLevel = 0.0
            var failed = false
            var tapCallbacks = 0
            var sourceFrames = 0
            var convertedFrames = 0
            var mutedCallbacks = 0
            var configurationChanges = 0
            var interruptions = 0
            var foregroundAtStart = false
            var foregroundAtEnd = false
        }
        var report = Report()
        var observations: [NSObjectProtocol] = []
        for name in [Notification.Name.AVAudioEngineConfigurationChange, AVAudioSession.interruptionNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                let changed = notification.name == .AVAudioEngineConfigurationChange
                Task { @MainActor in
                    if changed { report.configurationChanges += 1 } else { report.interruptions += 1 }
                }
            })
        }
        defer { observations.forEach(NotificationCenter.default.removeObserver) }
        let audio = RealtimeAudioIO()
        defer { audio.disconnect() }
        if report.permissionGranted {
            audio.onPCM = { pcm, level in
                report.packets += 1; report.frames += pcm.count / 2
                report.peakLevel = max(report.peakLevel, level)
            }
            audio.onFailure = { report.failed = true }
            do {
                let deadline = Date().addingTimeInterval(10)
                while UIApplication.shared.applicationState != .active, Date() < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard UIApplication.shared.applicationState == .active else { throw RealtimeAudioIO.Failure.audio }
                try audio.start()
                report.foregroundAtStart = UIApplication.shared.applicationState == .active
                report.started = audio.engineRunningForVerification
                try await Task.sleep(for: .seconds(6))
            } catch { report.failed = true }
            report.engineRunningAtEnd = audio.engineRunningForVerification
            report.foregroundAtEnd = UIApplication.shared.applicationState == .active
            if let statistics = audio.captureStatisticsForVerification {
                report.tapCallbacks = statistics.callbacks
                report.sourceFrames = statistics.sourceFrames
                report.convertedFrames = statistics.outputFrames
                report.mutedCallbacks = statistics.mutedCallbacks
            }
        }
        audio.disconnect()
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("input-verification.json"), options: .atomic)
        }
        return report.packets > 0 && !report.failed ? "Microphone input received" : "Microphone input unavailable"
    }
    @MainActor private static var providerCheckHasRun = false
    private struct Playback: Codable {
        var connected = false
        var receivedCaption = false
        var peakAudioLevel = 0.0
        var outputPorts: Set<String> = []
        var outputVolumes: Set<Float> = []
        var speakerPreferenceRetained = true
        var closed = false
        var audioReleased = false
        var error: String?
        var passed: Bool {
            connected && receivedCaption && peakAudioLevel > 0.001 &&
            outputPorts == [AVAudioSession.Port.builtInSpeaker.rawValue] &&
            speakerPreferenceRetained && closed && audioReleased && error == nil
        }
    }

    // Explicit debug launch only. Uses an in-memory learning store and records
    // routing facts, never credentials, audio, or conversation text.
    @MainActor static func run(_ coordinator: ConversationCoordinator) async {
        if vocabularyRequested { await verifyVocabulary(configuration: coordinator.modelConfiguration); return }
        if systemVoiceRequested { await verifySystemVoice(); return }
        if providerRequested {
            await verifyProvider(configuration: coordinator.modelConfiguration)
            return
        }
        let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = !ProcessInfo.processInfo.arguments.contains("--verify-background")
        defer { UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled }
        if ProcessInfo.processInfo.arguments.contains("--verify-connectivity") {
            // Nonbillable preflight: no account, provider session, or conversation request.
            var result: [String: Any] = ["providerCalls": false]
            do {
                guard let configuration = ManagedAccountConfiguration.load() else { throw ManagedAccountError.unavailable }
                let (_, response) = try await ManagedAccountHTTP().send(URLRequest(url: configuration.origin.appendingPathComponent("healthz")))
                result["httpStatus"] = (response as? HTTPURLResponse)?.statusCode
                let member = try ManagedAccountKeychain(scope: configuration.storageScope).load()
                let owner = try await GuestAccess.shared.owner(member: member)
                result["verificationAccountID"] = owner.accountID.uuidString
                result["hostedAvailable"] = try await HostedClient.shared?.available(owner)
                result["canStart"] = try await HostedClient.shared?.balance(owner).canStart
            } catch let error as URLError {
                result["networkErrorCode"] = error.code.rawValue
            } catch {
                result["unexpectedFailure"] = true
                result["failureType"] = String(describing: type(of: error))
                if let account = error as? ManagedAccountError { result["accountFailure"] = String(describing: account) }
                if let hosted = error as? HostedError { result["hostedFailure"] = String(describing: hosted) }
                result["networkErrorCode"] = UserDefaults.standard.object(forKey: "verificationNetworkErrorCode")
            }
            if let data = try? JSONSerialization.data(withJSONObject: result) {
                try? data.write(to: URL.documentsDirectory.appendingPathComponent("connectivity-verification.json"), options: .atomic)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--record-spanish-demo") {
            await recordSpanishDemo(coordinator)
            return
        }
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--verify-language=") }) {
            let id = String(argument.dropFirst("--verify-language=".count))
            guard LanguageRegistry.module(for: id) != nil else { return }
            coordinator.selectLanguage(id)
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-language-flow") {
            await verifyLanguageFlow(coordinator)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--verify-meaning") {
            await verifyMeaning(coordinator)
            return
        }
        let destination = URL.documentsDirectory.appendingPathComponent("audio-verification.json")
        func write(status: String, results: [Playback]) {
            struct Report: Encodable {
                var date: Date
                var status: String
                var languageID: String
                var passed: Bool
                var playback: [Playback]
            }
            let report = Report(date: .now, status: status, languageID: coordinator.language.id, passed: results.count == 2 && results.allSatisfy(\.passed), playback: results)
            if let data = try? JSONEncoder().encode(report) { try? data.write(to: destination, options: .atomic) }
        }
        coordinator.store.updatePreferences { $0.meaningVisible = false }
        var results: [Playback] = []
        write(status: "running", results: results)
        for _ in 0..<2 {
            var result = Playback()
            coordinator.start()
            let deadline = Date().addingTimeInterval(60)
            var connectedAt: Date?
            while Date() < deadline && !Task.isCancelled {
                if coordinator.state == .active {
                    if connectedAt == nil {
                        connectedAt = .now
                    }
                    result.connected = true
                    result.receivedCaption = result.receivedCaption || coordinator.assistantPassage != nil
                    result.peakAudioLevel = max(result.peakAudioLevel, coordinator.outputLevel)
                    if coordinator.outputLevel > 0.001 {
                        let audio = AVAudioSession.sharedInstance()
                        result.outputPorts.formUnion(audio.currentRoute.outputs.map { $0.portType.rawValue })
                        result.outputVolumes.insert(audio.outputVolume)
                        result.speakerPreferenceRetained = result.speakerPreferenceRetained && audio.categoryOptions.contains(.defaultToSpeaker)
                    }
                    if let connectedAt, Date().timeIntervalSince(connectedAt) >= 12 { break }
                }
                if coordinator.state == .failed || coordinator.showSettings { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            result.error = coordinator.error
            coordinator.end(reason: "Audio verification")
            let closingDeadline = Date().addingTimeInterval(7)
            while coordinator.isRunning && Date() < closingDeadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            result.closed = !coordinator.isRunning
            result.audioReleased = !RTCAudioSession.sharedInstance().isActive
            results.append(result)
            write(status: results.count == 2 ? "complete" : "running", results: results)
            if !result.connected || !result.closed || Task.isCancelled { break }
        }
        write(status: "complete", results: results)
    }

    /// Explicit owner-authorized requests, with no microphone or persistent learning writes.
    @MainActor static func verifyProvider(configuration: ProviderConfiguration) async {
        guard !providerCheckHasRun else { return }
        providerCheckHasRun = true
        struct Check: Encodable {
            var result = "pending"
            var failure: ProviderDiagnosticFailure?
            var networkCode: Int?
            var finishReason: String?
        }
        struct Report: Encodable {
            var date = Date()
            var status = "running"
            var provider: String
            var protectedDataAvailable: Bool
            var usesDefaultChatModel: Bool
            var chat = Check()
            var structured = Check()
            var streaming = Check()
            var token = Check()
            var live = Check()
            var receivedPCMBytes = 0
            var receivedTranscript = false
            var socketCloseCode: Int?
        }
        var report = Report(provider: configuration.provider.rawValue,
                            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
                            usesDefaultChatModel: configuration.model == configuration.provider.defaultModel)
        let deepSeekCheck = ProcessInfo.processInfo.arguments.contains("--verify-deepseek-provider")
        // This explicit one-request probe never changes the owner's saved provider.
        let configuration = deepSeekCheck ? ProviderConfiguration(provider: .deepSeek) : configuration
        report.provider = configuration.provider.rawValue
        report.usesDefaultChatModel = configuration.model == configuration.provider.defaultModel
        let destination = URL.documentsDirectory.appendingPathComponent(deepSeekCheck ? "deepseek-provider-verification.json" : "gemini-provider-verification.json")
        func write() {
            guard let data = try? JSONEncoder().encode(report) else { return }
            try? data.write(to: destination, options: .atomic)
        }
        func failed(_ error: Error) -> Check {
            if let value = error as? APIClient.ProviderRequestError {
                return Check(result: "http_failed", failure: ProviderDiagnosticFailure(status: value.failure.status, body: Data()))
            }
            if error is APIClient.CredentialError { return Check(result: "credential_unavailable") }
            if let error = error as? ChatCompletion.Failure {
                switch error {
                case .incomplete: return Check(result: "incomplete")
                case .malformed: return Check(result: "malformed")
                case .refused: return Check(result: "refused")
                case .tooLarge: return Check(result: "too_large")
                case .searchUnavailable: return Check(result: "search_unavailable")
                }
            }
            let value = error as NSError
            return Check(result: value.domain == NSURLErrorDomain ? "network_failed" : "request_failed",
                         networkCode: value.domain == NSURLErrorDomain ? value.code : nil)
        }
        write()
        guard configuration.provider == (deepSeekCheck ? .deepSeek : .gemini) else { report.status = "wrong_provider"; write(); return }
        guard report.protectedDataAvailable else { report.status = "unlock_required"; write(); return }
        #if targetEnvironment(simulator)
        report.status = "physical_phone_required"; write(); return
        #else
        let wasIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = wasIdle }
        let api = APIClient(configuration: configuration)
        api.conversationProvider = .personalKey
        api.canProcessAI = { AudioVerification.requested && UIApplication.shared.isProtectedDataAvailable }
        var capturedHTTP: ProviderDiagnosticFailure?
        api.onDiagnosticFailure = { capturedHTTP = $0 }
        do {
            let payload = try ChatCompletion.payload(configuration: configuration, instructions: "Reply only OK.", input: "Connection check.")
            let json = try await api.post("chat/completions", body: payload)
            let finish = (json["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String
            if let finish, ["stop", "length", "content_filter"].contains(finish) { report.chat.finishReason = finish }
            do { _ = try ChatCompletion.decode(json); report.chat.result = "passed" }
            catch { report.chat.result = failed(error).result }
        } catch { report.chat = failed(error); report.chat.failure = capturedHTTP }
        write()
        if deepSeekCheck { report.status = "complete"; write(); return }
        // Avoid repeat authentication/network requests after a definitive chat failure.
        guard report.chat.result == "passed" || report.chat.result == "incomplete" else {
            report.status = "complete"; write(); return
        }
        let schema: [String: Any] = ["type": "object", "properties": ["ok": ["type": "boolean"]], "required": ["ok"], "additionalProperties": false]
        capturedHTTP = nil
        do {
            _ = try await api.respond(instructions: "Return a JSON object with ok true.", input: "Connection check.", schema: schema)
            report.structured.result = "passed"
        } catch { report.structured = failed(error); report.structured.failure = capturedHTTP }
        write()
        capturedHTTP = nil
        do {
            _ = try await api.respond(instructions: "Reply only OK.", input: "Connection check.", onText: { _ in })
            report.streaming.result = "passed"
        } catch { report.streaming = failed(error); report.streaming.failure = capturedHTTP }
        write()
        let network = URLSessionConfiguration.ephemeral
        network.httpCookieStorage = nil; network.urlCache = nil
        network.timeoutIntervalForRequest = 20; network.timeoutIntervalForResource = 30
        let session = URLSession(configuration: network, delegate: ProviderNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var socket: URLSessionWebSocketTask?
        do {
            var request = URLRequest(url: GeminiLiveProtocol.tokenURL)
            request.httpMethod = "POST"
            request.setValue(try GeminiLiveProtocol.checkedSecret(api.credential()), forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: GeminiLiveProtocol.tokenBody(now: .now))
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatCompletion.Failure.malformed }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 16_384 else { throw ChatCompletion.Failure.tooLarge }
                data.append(byte)
            }
            guard (200..<300).contains(http.statusCode) else {
                report.token = Check(result: "http_failed", failure: ProviderDiagnosticFailure(status: http.statusCode, body: data))
                report.status = "complete"; write(); return
            }
            let token = try GeminiLiveProtocol.token(from: data)
            report.token.result = "passed"; write()
            var websocketRequest = URLRequest(url: GeminiLiveProtocol.socketURL)
            websocketRequest.setValue("Token " + token, forHTTPHeaderField: "Authorization")
            let ws = session.webSocketTask(with: websocketRequest)
            ws.maximumMessageSize = GeminiLiveProtocol.maximumMessageBytes
            socket = ws; ws.resume()
            let deadline = Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) }
            }
            defer { deadline.cancel(); ws.cancel(with: .normalClosure, reason: nil) }
            func send(_ value: [String: Any]) async throws {
                try await ws.send(.string(String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)))
            }
            try await send(GeminiLiveProtocol.setup(instructions: "Say OK briefly.", hasHistory: false))
            var protocolState = GeminiLiveProtocol()
            var sentText = false
            while !Task.isCancelled {
                let message = try await ws.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: throw ChatCompletion.Failure.malformed
                }
                if let failure = ProviderDiagnosticFailure.fromLiveMessage(data) {
                    report.live = Check(result: "server_failed", failure: failure)
                    break
                }
                let update = try protocolState.consume(data, elapsedMS: 0)
                report.receivedPCMBytes += update.audio.reduce(0) { $0 + $1.count }
                report.receivedTranscript = report.receivedTranscript || update.events.contains { $0["type"] as? String == "session.output_transcript.delta" }
                if protocolState.configured && !sentText {
                    report.live.result = "setup_passed"; write()
                    try await send([
                        "clientContent": [
                            "turns": [["role": "user", "parts": [["text": "Say OK briefly."]]]],
                            "turnComplete": true
                        ]
                    ])
                    sentText = true
                }
                if report.receivedPCMBytes > 0 && report.receivedTranscript {
                    report.live.result = "passed"; break
                }
            }
        } catch {
            if report.token.result == "pending" { report.token = failed(error) }
            else { report.live = failed(error) }
            if let socket { report.socketCloseCode = Int(socket.closeCode.rawValue) }
        }
        report.status = "complete"; write()
        #endif
    }

    // Explicit recording helper: real provider responses to two scripted typed
    // turns. It never changes the owner's learning record or exports their key.
    @MainActor private static func recordSpanishDemo(_ coordinator: ConversationCoordinator) async {
        coordinator.selectLanguage("es")
        coordinator.selectMeaningLanguage("English")
        coordinator.chooseTheme(ConversationTheme.shared.first { $0.id == "coffee" })
        coordinator.store.updatePreferences { $0.meaningVisible = true }
        let destination = URL.documentsDirectory.appendingPathComponent("demo-verification.json")
        func report(_ status: String, replies: Int = 0) {
            let data = try? JSONEncoder().encode(["status": status, "replies": String(replies), "input": "scripted typed turns", "output": "live provider audio"])
            try? data?.write(to: destination, options: .atomic)
        }
        report("ready")
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        coordinator.start()
        defer { coordinator.end(reason: "Spanish recording demo") }
        let connectionDeadline = Date().addingTimeInterval(45)
        while coordinator.state == .connecting && Date() < connectionDeadline {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { coordinator.end(reason: "Demo cancelled"); return }
        }
        guard coordinator.state == .active else { report("connection failed"); return }
        coordinator.toggleMute()
        let absoluteDeadline = Date().addingTimeInterval(100)
        func waitForReply(after previous: String) async -> Bool {
            var lastChange = Date(), previousText = previous
            while coordinator.state == .active && Date() < absoluteDeadline && !Task.isCancelled {
                let current = coordinator.caption
                if current != previousText || coordinator.outputLevel > 0.01 { lastChange = .now; previousText = current }
                if current != previous, coordinator.assistantPassage != nil, !coordinator.working,
                   Date().timeIntervalSince(lastChange) > 3 { return true }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
            }
            return false
        }
        var replies = 0
        if await waitForReply(after: coordinator.language.greeting) {
            for line in ["Hola. Me gustaría tomar un café con leche.", "Yo quiere una tostada también, por favor."] {
                let previous = coordinator.caption
                await coordinator.sendTyped(line)
                guard await waitForReply(after: previous) else { break }
                replies += 1
            }
        }
        report(replies == 2 ? "complete" : "incomplete", replies: replies)
    }

    @MainActor private static func verifyMeaning(_ coordinator: ConversationCoordinator) async {
        struct Report: Encodable {
            var date = Date()
            var status = "running"
            var languageID: String
            var translatedWhileActive = false
            var cachedMeaningAfterEnd = false
            var newTranslationAfterEnd = false
            var resetAfter15Seconds = false
            var savedConversationRetained = false
            var audioReleased = false
            var error: String?
            var passed: Bool {
                translatedWhileActive && cachedMeaningAfterEnd && newTranslationAfterEnd &&
                resetAfter15Seconds && savedConversationRetained && audioReleased && error == nil
            }
            // Include the computed outcome in the written report.
            enum CodingKeys: String, CodingKey {
                case date, status, languageID, translatedWhileActive, cachedMeaningAfterEnd,
                     newTranslationAfterEnd, resetAfter15Seconds, savedConversationRetained, audioReleased, error, passed
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(date, forKey: .date); try c.encode(status, forKey: .status)
                try c.encode(languageID, forKey: .languageID)
                try c.encode(translatedWhileActive, forKey: .translatedWhileActive)
                try c.encode(cachedMeaningAfterEnd, forKey: .cachedMeaningAfterEnd)
                try c.encode(newTranslationAfterEnd, forKey: .newTranslationAfterEnd)
                try c.encode(resetAfter15Seconds, forKey: .resetAfter15Seconds)
                try c.encode(savedConversationRetained, forKey: .savedConversationRetained)
                try c.encode(audioReleased, forKey: .audioReleased)
                try c.encodeIfPresent(error, forKey: .error); try c.encode(passed, forKey: .passed)
            }
        }
        var report = Report(languageID: coordinator.language.id)
        let destination = URL.documentsDirectory.appendingPathComponent("meaning-verification.json")
        func write() {
            if let data = try? JSONEncoder().encode(report) { try? data.write(to: destination, options: .atomic) }
        }
        write()
        coordinator.store.updatePreferences { $0.meaningVisible = true; $0.meaningLanguage = "English" }
        coordinator.start()
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline && !Task.isCancelled {
            if coordinator.state == .active, !coordinator.meaning.isEmpty, !coordinator.translating {
                report.translatedWhileActive = true; break
            }
            if coordinator.meaningError != nil || coordinator.error != nil || coordinator.showSettings { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        report.error = coordinator.meaningError ?? coordinator.error
        let sessionID = coordinator.session?.id
        coordinator.end(reason: "Meaning verification")
        let closingDeadline = Date().addingTimeInterval(7)
        while coordinator.isRunning && Date() < closingDeadline { try? await Task.sleep(for: .milliseconds(100)) }
        let endedAt = coordinator.session?.endedAt
        report.audioReleased = !RTCAudioSession.sharedInstance().isActive
        let english = coordinator.meaning
        coordinator.toggleMeaning()
        coordinator.toggleMeaning()
        report.cachedMeaningAfterEnd = coordinator.state == .ended && !english.isEmpty && coordinator.meaning == english && !coordinator.translating
        coordinator.selectMeaningLanguage("French")
        let translationDeadline = Date().addingTimeInterval(13)
        while Date() < translationDeadline && coordinator.state == .ended && !Task.isCancelled {
            if !coordinator.meaning.isEmpty && !coordinator.translating {
                report.newTranslationAfterEnd = true; break
            }
            if coordinator.meaningError != nil { report.error = coordinator.meaningError; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        write()
        let resetDeadline = (endedAt ?? .now).addingTimeInterval(18)
        while coordinator.state == .ended && Date() < resetDeadline { try? await Task.sleep(for: .milliseconds(100)) }
        report.resetAfter15Seconds = coordinator.state == .idle && coordinator.session == nil && coordinator.selectedTheme == nil &&
            coordinator.caption == coordinator.language.greeting && endedAt.map { Date().timeIntervalSince($0) >= 14.5 } == true
        report.savedConversationRetained = coordinator.store.sessions.contains { $0.id == sessionID && $0.endedAt != nil && !$0.fragments.isEmpty }
        report.status = "complete"; write()
    }
}
#endif
