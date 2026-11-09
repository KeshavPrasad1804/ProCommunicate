import AVFoundation
import os

/// Tunable settings for detecting when the learner has finished speaking.
struct TurnDetection: Sendable {
    /// Silence that ends a turn. Longer than in normal conversation: learners often pause to find the English.
    var endSilence: Double = 1.6
    /// A pause at least this long inside a turn counts as a "long pause" in the fluency numbers.
    var longPause: Double = 1.0
    /// Very long answers are cut here.
    var maxTurn: Double = 120
    /// Speech must last this long before it counts (ignores coughs and clicks).
    var minSpeech: Double = 0.35

    static var current: TurnDetection {
        var detection = TurnDetection()
        let stored = UserDefaults.standard.double(forKey: "turnEndSilence")
        if stored > 0 { detection.endSilence = stored }
        return detection
    }
}

/// Events from the microphone during a call.
enum VoiceEvent: Sendable {
    case level(Double)
    case speechStarted
    /// A finished turn: 16 kHz mono samples, how long it was, and how many long pauses it had.
    case turnEnded(samples: [Float], duration: Double, longPauses: Int)
}

/// Listens to the microphone with Apple's voice processing (echo cancellation and noise reduction),
/// converts to 16 kHz mono for Whisper, and detects the start and end of each spoken turn.
final class VoiceCapture: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    private let state = OSAllocatedUnfairLock(initialState: DetectorState())
    private var converter: AVAudioConverter?
    private let onEvent: @Sendable (VoiceEvent) -> Void
    private let detection: TurnDetection

    private struct DetectorState {
        var listening = false
        var inSpeech = false
        var samples: [Float] = []
        var preRoll: [Float] = []
        var speechSeconds = 0.0
        var silenceSeconds = 0.0
        var turnSeconds = 0.0
        var longPauses = 0
        var countedThisPause = false
        var noiseFloor = -60.0
        var aboveCount = 0
        /// While the AI is speaking, only a loud voice counts (to interrupt it).
        var aiSpeaking = false
    }

    init(detection: TurnDetection = .current, onEvent: @escaping @Sendable (VoiceEvent) -> Void) {
        self.detection = detection
        self.onEvent = onEvent
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true)

        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state.withLock { $0 = DetectorState() }
    }

    /// Start or stop listening for a turn (e.g. paused while the AI is thinking).
    func setListening(_ listening: Bool) {
        state.withLock { s in
            s.listening = listening
            if !listening { s.inSpeech = false; s.samples = []; s.aboveCount = 0 }
        }
    }

    func setAISpeaking(_ speaking: Bool) {
        state.withLock { $0.aiSpeaking = speaking }
    }

    /// Ends the current turn now ("I'm done" button).
    func finishTurnNow() {
        let event: VoiceEvent? = state.withLock { s in
            guard s.inSpeech, s.speechSeconds >= detection.minSpeech else { return nil }
            let result = VoiceEvent.turnEnded(samples: s.samples, duration: s.turnSeconds, longPauses: s.longPauses)
            s.inSpeech = false
            s.samples = []
            s.listening = false
            return result
        }
        if let event { onEvent(event) }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        guard !samples.isEmpty else { return }

        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let db = 20 * log10(Double(max(rms, 1e-7)))
        let seconds = Double(samples.count) / Self.sampleRate
        onEvent(.level(max(0, min(1, (db + 55) / 45))))

        let events: [VoiceEvent] = state.withLock { s -> [VoiceEvent] in
            var events: [VoiceEvent] = []
            // Track the background noise when nobody is speaking.
            if !s.inSpeech { s.noiseFloor = min(-25, 0.95 * s.noiseFloor + 0.05 * db) }
            let threshold = max(-48, s.noiseFloor + (s.aiSpeaking ? 22 : 12))
            let loud = db > threshold

            guard s.listening || s.aiSpeaking else { return events }

            if !s.inSpeech {
                s.preRoll.append(contentsOf: samples)
                if s.preRoll.count > Int(0.35 * Self.sampleRate) { s.preRoll.removeFirst(s.preRoll.count - Int(0.35 * Self.sampleRate)) }
                s.aboveCount = loud ? s.aboveCount + 1 : 0
                if s.aboveCount >= (s.aiSpeaking ? 8 : 4) {
                    s.inSpeech = true
                    s.listening = true
                    s.samples = s.preRoll
                    s.preRoll = []
                    s.speechSeconds = 0
                    s.silenceSeconds = 0
                    s.turnSeconds = 0
                    s.longPauses = 0
                    s.countedThisPause = false
                    events.append(.speechStarted)
                }
                return events
            }

            s.samples.append(contentsOf: samples)
            s.turnSeconds += seconds
            if loud {
                s.speechSeconds += seconds
                s.silenceSeconds = 0
                s.countedThisPause = false
            } else {
                s.silenceSeconds += seconds
                if s.silenceSeconds >= detection.longPause && !s.countedThisPause {
                    s.longPauses += 1
                    s.countedThisPause = true
                }
            }
            let ended = (s.silenceSeconds >= detection.endSilence) || s.turnSeconds >= detection.maxTurn
            if ended {
                if s.speechSeconds >= detection.minSpeech {
                    // Trim the trailing silence, and don't count the final pause as a "long pause".
                    let trailing = Int(s.silenceSeconds * Self.sampleRate)
                    let trimmed = Array(s.samples.dropLast(min(trailing, max(0, s.samples.count - 1))))
                    let pauses = max(0, s.longPauses - (s.countedThisPause ? 1 : 0))
                    events.append(.turnEnded(samples: trimmed, duration: s.turnSeconds - s.silenceSeconds, longPauses: pauses))
                    s.listening = false
                }
                s.inSpeech = false
                s.samples = []
                s.aboveCount = 0
            }
            return events
        }
        for event in events { onEvent(event) }
    }
}

enum AudioFileWriter {
    /// Saves 16 kHz mono samples as an AAC .m4a file.
    static func writeM4A(_ samples: [Float], to url: URL, sampleRate: Double = VoiceCapture.sampleRate) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }

    /// Reads any audio file as 16 kHz mono samples (for "Analyse my recording" and stand-up drills).
    static func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: VoiceCapture.sampleRate, channels: 1, interleaved: false)!
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: input)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return [] }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * target.sampleRate / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
