import Foundation
@preconcurrency import AVFoundation

/// Shared native PCM16 input (16 kHz) and output (24 kHz), owned by one voice session.
@MainActor final class RealtimeAudioIO {
    enum Failure: Error { case audio, overloaded }
    var onPCM: ((Data, Double) -> Void)?
    var onLevels: ((Double, Double) -> Void)?
    var onFailure: (() -> Void)?
    private var attempt = UUID()
    private var started = false
    private var captureTask: Task<Void, Never>?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var capture: RealtimeMicrophoneCapture?
    private var muted = false
    private var ownsAudio = false
    private var hasInputTap = false
    private var playbackID = UUID()
    private var queuedPlaybackFrames = 0
    private var queuedPlaybackBuffers = 0
    private var configurationObserver: NSObjectProtocol?
    private var configurationRestarts = 0
    #if DEBUG
    var captureStatisticsForVerification: RealtimeMicrophoneCapture.Statistics? { capture?.statistics }
    var engineRunningForVerification: Bool { engine?.isRunning == true }
    #endif
    static func makeVoiceEngine() throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        // voiceChat alone does not enable acoustic echo cancellation. Configure
        // Voice I/O while stopped, before reading formats or installing the tap.
        try engine.inputNode.setVoiceProcessingEnabled(true)
        guard engine.inputNode.isVoiceProcessingEnabled,
              engine.outputNode.isVoiceProcessingEnabled else { throw Failure.audio }
        return engine
    }
    func start() throws {
        disconnect()
        let token = attempt
        defer { if !started { disconnect() } }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setPreferredSampleRate(16_000)
        try audio.setActive(true); ownsAudio = true
        let engine = try Self.makeVoiceEngine(), player = AVAudioPlayerNode()
        self.engine = engine; self.player = player
        engine.attach(player)
        guard let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false) else { throw Failure.audio }
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        try installCapture(on: engine, token: token)
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            // AVAudioEngine stops itself on a hardware format change. Recover on
            // our actor, never tear it down on Apple's internal notification queue.
            Task { @MainActor [weak self] in self?.recoverConfiguration(token: token) }
        }
        engine.prepare(); try engine.start(); player.play(); started = true
    }
    private func installCapture(on engine: AVAudioEngine, token: UUID) throws {
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.audio }
        let pair = AsyncStream<RealtimeMicrophoneCapture.Packet>.makeStream(bufferingPolicy: .bufferingNewest(4))
        let capture = try RealtimeMicrophoneCapture(format: format, continuation: pair.continuation)
        self.capture = capture
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [capture] buffer, _ in capture.consume(buffer) }
        hasInputTap = true
        captureTask = Task { [weak self] in
            for await packet in pair.stream {
                guard let self, self.attempt == token else { return }
                guard self.started, !self.muted, self.capture?.epoch == packet.epoch else { continue }
                if packet.failed { self.onFailure?(); return }
                self.onLevels?(packet.level, self.queuedPlaybackFrames > 0 ? 0.2 : 0)
                guard self.attempt == token, self.started, !self.muted, self.capture?.epoch == packet.epoch else { continue }
                self.onPCM?(packet.pcm, packet.level)
            }
        }
    }
    private func recoverConfiguration(token: UUID) {
        guard attempt == token, started, let engine, !engine.isRunning else { return }
        do {
            guard configurationRestarts < 3 else { throw Failure.audio }
            configurationRestarts += 1
            // A stopped output unit cannot establish which queued audio was
            // heard. Drop that tail rather than replaying it after recovery.
            clearPlayback(resume: false)
            capture?.finish(); captureTask?.cancel(); captureTask = nil
            if hasInputTap { engine.inputNode.removeTap(onBus: 0); hasInputTap = false }
            try installCapture(on: engine, token: token)
            capture?.setMuted(muted)
            engine.prepare(); try engine.start(); player?.play()
        } catch {
            let failure = onFailure
            disconnect()
            failure?()
        }
    }
    func play(_ pcm: Data) throws {
        guard let player, let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false) else { throw Failure.audio }
        guard !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 96_000 else { throw Failure.audio }
        let token = attempt
        let frames = pcm.count / 2
        guard queuedPlaybackFrames + frames <= 24_000 * 8, queuedPlaybackBuffers < 64 else { throw Failure.overloaded }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { throw Failure.audio }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm.withUnsafeBytes { bytes in
            let source = bytes.bindMemory(to: UInt8.self)
            for index in 0..<frames {
                let bits = UInt16(source[index * 2]) | (UInt16(source[index * 2 + 1]) << 8)
                channel[index] = Float(Int16(bitPattern: bits)) / 32_768
            }
        }
        queuedPlaybackFrames += frames; queuedPlaybackBuffers += 1
        let playback = playbackID
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.attempt == token, self.playbackID == playback else { return }
                self.queuedPlaybackFrames = max(0, self.queuedPlaybackFrames - frames)
                self.queuedPlaybackBuffers = max(0, self.queuedPlaybackBuffers - 1)
                if self.queuedPlaybackFrames == 0 { self.onLevels?(0, 0) }
            }
        }
        if !player.isPlaying { player.play() }
    }
    func clearPlayback(resume: Bool = true) {
        playbackID = UUID(); queuedPlaybackFrames = 0; queuedPlaybackBuffers = 0
        player?.stop()
        if started, resume { player?.play() }
        onLevels?(0, 0)
    }
    func mute(_ value: Bool) {
        muted = value; capture?.setMuted(value)
        if value { onLevels?(0, queuedPlaybackFrames > 0 ? 0.2 : 0) }
    }
    func disconnect() {
        attempt = UUID(); started = false
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil; configurationRestarts = 0
        capture?.finish(); capture = nil; captureTask?.cancel(); captureTask = nil
        if let engine {
            if hasInputTap { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
        }
        hasInputTap = false; engine = nil
        clearPlayback(); player = nil; muted = false
        if ownsAudio { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); ownsAudio = false }
    }
}

/// The audio callback owns conversion. Its four-slot mailbox bounds work on the main actor.
final class RealtimeMicrophoneCapture: @unchecked Sendable {
    struct Packet: Sendable { let pcm: Data; let level: Double; let epoch: UUID; let failed: Bool }
    #if DEBUG
    struct Statistics: Sendable { var callbacks = 0; var sourceFrames = 0; var outputFrames = 0; var mutedCallbacks = 0 }
    private var statisticsValue = Statistics()
    var statistics: Statistics { lock.withLock { statisticsValue } }
    #endif
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<Packet>.Continuation
    private var muted = false
    private var terminal = false
    private var currentEpoch = UUID()
    var epoch: UUID { lock.withLock { currentEpoch } }
    init(format: AVAudioFormat, continuation: AsyncStream<Packet>.Continuation) throws {
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: format, to: output) else { throw RealtimeAudioIO.Failure.audio }
        self.converter = converter; outputFormat = output; self.continuation = continuation
    }
    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            #if DEBUG
            statisticsValue.callbacks += 1
            statisticsValue.sourceFrames += Int(buffer.frameLength)
            if muted { statisticsValue.mutedCallbacks += 1 }
            #endif
            guard !muted else { return }
            if terminal { _ = continuation.yield(Packet(pcm: Data(), level: 0, epoch: currentEpoch, failed: true)); return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 32)
            guard capacity > 0, capacity <= 16_000,
                  let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { terminal = true; return }
            var provided = false, error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if provided { inputStatus.pointee = .noDataNow; return nil }
                provided = true; inputStatus.pointee = .haveData; return buffer
            }
            guard error == nil, status != .error else { terminal = true; return }
            #if DEBUG
            statisticsValue.outputFrames += Int(output.frameLength)
            #endif
            guard output.frameLength > 0, let channel = output.int16ChannelData?[0] else { return }
            let count = Int(output.frameLength)
            var peak = 0.0
            for index in 0..<count { peak = max(peak, abs(Double(channel[index])) / 32_768) }
            let packet = Packet(pcm: Data(bytes: channel, count: count * 2), level: min(1, peak), epoch: currentEpoch, failed: false)
            if case .dropped = continuation.yield(packet) { terminal = true }
        }
    }
    func setMuted(_ value: Bool) {
        lock.withLock { muted = value; currentEpoch = UUID(); converter.reset() }
    }
    @discardableResult func finish() -> Bool {
        lock.withLock {
            muted = true; currentEpoch = UUID(); continuation.finish()
            return !terminal
        }
    }
}
