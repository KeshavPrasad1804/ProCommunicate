import AVFoundation
import Observation

/// English accent for the app's voice.
enum SpeechVoice: String, CaseIterable, Identifiable, Sendable {
    case indian = "en-IN"
    case british = "en-GB"
    case american = "en-US"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indian: "Indian English"
        case .british: "British English"
        case .american: "American English"
        }
    }

    static let settingsKey = "speechVoice"

    static var current: SpeechVoice {
        UserDefaults.standard.string(forKey: settingsKey).flatMap(SpeechVoice.init(rawValue:)) ?? .indian
    }
}

/// Speaks English with the phone's built-in voices (works offline).
@MainActor @Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    /// The text currently being spoken, so the matching play button can show it's playing.
    private(set) var speakingText: String?
    /// Whether the current speech is the slow version (so only the "Slow" button shows as playing).
    private(set) var speakingSlow = false
    /// Utterances queued or speaking (calls queue one sentence at a time).
    private(set) var pending = 0

    var isSpeaking: Bool { pending > 0 }
    /// Called when everything queued has been spoken (used by calls to start listening).
    @ObservationIgnored var onFinishedAll: (@MainActor () -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks now, replacing anything playing. Sets up the audio session for playback
    /// unless `configureSession` is false (calls manage the session themselves).
    func speak(_ text: String, slow: Bool = false, voice: SpeechVoice = .current, configureSession: Bool = true) {
        if configureSession {
            let session = AVAudioSession.sharedInstance()
            // Plays even with the silent switch on, and lowers other audio while speaking.
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        pending = 0
        enqueue(text, slow: slow, voice: voice)
    }

    /// Adds a sentence after whatever is already being spoken.
    func enqueue(_ text: String, slow: Bool = false, voice: SpeechVoice = .current, rate: Float? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestVoice(for: voice)
        utterance.rate = rate ?? AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.7 : 0.95)
        utterance.postUtteranceDelay = 0.05
        speakingText = text
        speakingSlow = slow
        pending += 1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingText = nil
        pending = 0
    }

    /// The highest-quality installed voice for the accent (enhanced/premium if downloaded).
    static func bestVoice(for voice: SpeechVoice) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == voice.rawValue }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: voice.rawValue)
    }

    private func finishedOne() {
        pending = max(0, pending - 1)
        if pending == 0 {
            speakingText = nil
            onFinishedAll?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingText = nil
            self.pending = 0
        }
    }
}

/// Splits streamed text into sentences so each can be spoken as soon as it's complete.
struct SentenceSplitter {
    private var buffer = ""

    /// Adds text; returns any complete sentences.
    mutating func add(_ piece: String) -> [String] {
        buffer += piece
        var sentences: [String] = []
        while let range = buffer.range(of: #"[.!?](\s|$)"#, options: .regularExpression),
              range.upperBound < buffer.endIndex || buffer.last?.isWhitespace == true {
            let sentence = String(buffer[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[range.upperBound...])
            // Keep abbreviations like "e.g." or "Mr." with the next words.
            if sentence.count > 3 { sentences.append(sentence) } else { buffer = sentence + " " + buffer }
        }
        return sentences
    }

    /// Whatever is left at the end.
    mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }
}
