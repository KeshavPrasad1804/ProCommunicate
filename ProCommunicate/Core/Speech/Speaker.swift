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

/// Speaks English phrases with the phone's built-in voices (works offline).
@MainActor @Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    /// The text currently being spoken, so the matching play button can show it's playing.
    private(set) var speakingText: String?
    /// Whether the current speech is the slow version (so only the "Slow" button shows as playing).
    private(set) var speakingSlow = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, slow: Bool = false, voice: SpeechVoice = .current) {
        let session = AVAudioSession.sharedInstance()
        // Plays even with the silent switch on, and lowers other audio while speaking.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: voice)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.7 : 0.95)
        utterance.postUtteranceDelay = 0.05
        speakingText = text
        speakingSlow = slow
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingText = nil
    }

    /// The highest-quality installed voice for the accent (enhanced/premium if downloaded).
    static func bestVoice(for voice: SpeechVoice) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == voice.rawValue }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: voice.rawValue)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingText = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingText = nil }
    }
}
